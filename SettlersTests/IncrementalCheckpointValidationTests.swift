import Foundation
import Testing
@testable import CatanEngine
import CatanAI
@testable import Settlers

/// The commit path validates a candidate as a delta against the document it is
/// replacing instead of replaying the whole game, and reads the current
/// document through a content-keyed decode cache. Both are load-bearing for
/// late-game responsiveness (see
/// `docs/plans/2026-09-11-expanded-bots-and-speed.md`), and both are only
/// legitimate while the checks they skip cannot have anything to catch. These
/// tests are what says so: each one damages the exact thing the skipped work
/// used to find and requires the commit to still refuse it.
@MainActor @Suite struct IncrementalCheckpointValidationTests {
    /// One committed document plus the store that wrote it.
    @MainActor private struct Fixture {
        let root: URL
        let store: MatchCheckpointStore
        var session: GameSession
        var document: MatchCheckpointDocument

        init(moves: Int) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            store = MatchCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.json"))
            let initial = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
            let setup = MatchSetup(
                seats: initial.players.map { player in
                    let civilization = Civilization.allCases[player.id.index]
                    let isHuman = player.id.index == 0
                    return MatchSetup.Seat(
                        index: player.id.index, isHuman: isHuman,
                        name: isHuman ? "Alex" : "",
                        civilization: civilization,
                        opponentProfile: isHuman ? nil : .forCivilization(civilization))
                },
                victoryPointTarget: 10, randomizedBoard: false, randomizeSeatOrder: false)
            var policies: [PlayerID: any Policy] = [:]
            for player in initial.players {
                policies[player.id] = HeuristicPolicy(personality: .balanced, id: "incremental-fixture")
            }
            session = GameSession(state: initial, policies: policies, policySeed: 99)
            document = MatchCheckpointDocument(
                activeMatch: MatchCheckpoint(id: UUID(), initialState: initial, setup: setup))
            try store.commit(document, replacingRevision: nil)
            for index in 1...moves {
                guard let step = try session.step() else { break }
                let next = try document.recording(step, session: session.checkpoint,
                                                  elapsedSeconds: Double(index))
                try store.commit(next, replacingRevision: document.revision)
                document = next
                while document.pendingDevCardReveal != nil || document.pendingDevCardResolution != nil {
                    let acknowledged = document.pendingDevCardReveal != nil
                        ? try document.dismissingDevCardReveal()
                        : try document.dismissingDevCardResolution()
                    try store.commit(acknowledged, replacingRevision: document.revision)
                    document = acknowledged
                }
            }
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func aCandidateWhoseAppendedMoveDoesNotProduceItsStateIsRefused() throws {
        var fixture = try Fixture(moves: 12)
        defer { fixture.cleanUp() }
        guard let step = try fixture.session.step() else {
            Issue.record("fixture produced no further move")
            return
        }
        let honest = try fixture.document.recording(step, session: fixture.session.checkpoint,
                                                    elapsedSeconds: 99)
        // Tamper with the recorded end state, leaving the move list intact:
        // exactly what replaying the appended move is there to catch.
        var json = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(honest)) as? [String: Any])
        var active = try #require(json["activeMatch"] as? [String: Any])
        var state = try #require(active["state"] as? [String: Any])
        state["lastDiceRoll"] = ((state["lastDiceRoll"] as? Int) ?? 6) == 5 ? 9 : 5
        active["state"] = state
        json["activeMatch"] = active
        let tampered = try JSONDecoder().decode(
            MatchCheckpointDocument.self,
            from: try JSONSerialization.data(withJSONObject: json))

        #expect(throws: MatchCheckpointStore.StoreError.inconsistentHistory) {
            try fixture.store.commit(tampered, replacingRevision: fixture.document.revision)
        }
    }

    @Test func aCandidateThatRewritesAnAlreadyRecordedMoveIsRefused() throws {
        var fixture = try Fixture(moves: 12)
        defer { fixture.cleanUp() }
        guard let step = try fixture.session.step() else {
            Issue.record("fixture produced no further move")
            return
        }
        let honest = try fixture.document.recording(step, session: fixture.session.checkpoint,
                                                    elapsedSeconds: 99)
        // Rewriting history breaks `isExtending`, so the candidate loses the
        // delta shortcut and faces the full replay - which its untouched
        // state snapshot no longer matches.
        var json = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(honest)) as? [String: Any])
        var active = try #require(json["activeMatch"] as? [String: Any])
        var moves = try #require(active["moves"] as? [[String: Any]])
        moves.remove(at: 4)
        active["moves"] = moves
        json["activeMatch"] = active
        let rewritten = try JSONDecoder().decode(
            MatchCheckpointDocument.self,
            from: try JSONSerialization.data(withJSONObject: json))

        // Any refusal is correct here: the full replay may reject the doctored
        // history at the first move that no longer makes sense (a `MoveError`)
        // rather than at the end-state comparison.
        #expect(throws: (any Error).self) {
            try fixture.store.commit(rewritten, replacingRevision: fixture.document.revision)
        }
    }

    /// The decode cache is keyed on the file's bytes, so anything that writes
    /// that file behind the store must still be decoded and validated rather
    /// than answered from memory.
    @Test func aSaveRewrittenOutsideTheStoreIsNotServedFromTheCache() throws {
        var fixture = try Fixture(moves: 8)
        defer { fixture.cleanUp() }
        try Data("not a checkpoint".utf8).write(to: fixture.store.fileURL)
        guard let step = try fixture.session.step() else {
            Issue.record("fixture produced no further move")
            return
        }
        let next = try fixture.document.recording(step, session: fixture.session.checkpoint,
                                                  elapsedSeconds: 99)
        #expect(throws: (any Error).self) {
            try fixture.store.commit(next, replacingRevision: fixture.document.revision)
        }
        #expect(throws: (any Error).self) { _ = try fixture.store.load() }
    }

    /// A resume is a cold read: it must still re-derive the entire game from
    /// the initial position, because that is the check that a delta-validated
    /// history was never allowed to skip - only to defer to here.
    @Test func aFullyDeltaCommittedMatchStillPassesAColdFullReplay() throws {
        let fixture = try Fixture(moves: 40)
        defer { fixture.cleanUp() }
        let reopened = MatchCheckpointStore(fileURL: fixture.store.fileURL)
        let loaded = try #require(try reopened.load())
        #expect(loaded == fixture.document)
        try #require(loaded.activeMatch).validateHistory()
    }
}

/// The JSONL archive is a derived projection rewritten in full every time it is
/// exported, so it is written at turn boundaries rather than on every move (see
/// `GameViewModel.isArchiveFlushPoint`). What that trades away is precision
/// *within* a turn, and these tests state both halves of the trade so neither
/// can be changed silently.
@MainActor @Suite struct ArchiveFlushPointTests {
    /// All-human seats: every move can be applied directly, with no bot loop
    /// and no pacing delay in the way of the assertions.
    private func hotSeatModel(_ fixture: CheckpointModelFixture) -> GameViewModel {
        let model = fixture.makeModel()
        var setup = fixture.setup
        for index in setup.seats.indices {
            setup.seats[index].isHuman = true
            setup.seats[index].name = "Player \(index + 1)"
        }
        model.startNewGame(setup: setup)
        return model
    }

    /// The seat to move next, with the device passed to it first: in hot seat
    /// the model applies a move as whoever is holding the phone.
    private func actingSeat(_ model: GameViewModel) -> PlayerID? {
        if model.needsHandoff { model.claimDeviceForSeatOwedATurn() }
        switch model.state.phase {
        case .setupForward(let index), .setupBackward(let index),
             .rollDice(let index), .mainTurn(let index), .movingRobber(let index):
            return model.state.players[index].id
        case .discarding(let pending):
            return pending.sorted().first
        case .gameOver:
            return nil
        }
    }

    private func archivedMoveCount(_ fixture: CheckpointModelFixture) throws -> Int? {
        try fixture.logStore.summaries().first?.moveCount
    }

    @Test func theArchiveAppearsOnTheFirstMoveAndCatchesUpAtEveryTurnBoundary() throws {
        let fixture = try CheckpointModelFixture()
        let model = hotSeatModel(fixture)
        #expect(try archivedMoveCount(fixture) == nil, "an unplayed game has nothing to archive")

        var sawStaleArchiveMidTurn = false
        var sawTurnBoundary = false
        for _ in 0..<120 {
            guard let seat = actingSeat(model) else { break }
            let legal = RulesEngine.legalMoves(for: model.state, seat: seat)
            // Prefer anything over ending the turn, so turns contain several
            // moves and the mid-turn case is actually exercised; never buy a
            // card, whose private receipt is a different journey entirely.
            let move = legal.first {
                if case .endTurn = $0 { return false }
                if case .buyDevCard = $0 { return false }
                // Negotiation is its own journey and needs bot seats to
                // answer; this fixture is only about when the archive writes.
                if case .proposeTrade = $0 { return false }
                if case .respondToTrade = $0 { return false }
                return true
            } ?? legal[0]
            try model.apply(move)
            let recorded = model.checkpointDocument?.activeMatch?.moves.count ?? 0
            let archived = try archivedMoveCount(fixture)
            if recorded == 1 {
                #expect(archived == 1, "a started game must be listed in Game History immediately")
            }
            if case .endTurn = move {
                sawTurnBoundary = true
                #expect(archived == recorded, "the archive must be current at a turn boundary")
            } else if recorded > 1, archived != recorded {
                sawStaleArchiveMidTurn = true
            }
        }
        #expect(sawTurnBoundary, "the fixture never completed a turn")
        #expect(sawStaleArchiveMidTurn, "no move deferred the archive - the export is not actually deferred")
    }

    @Test func leavingTheAppMidTurnArchivesWhatTheGameHasSoFar() throws {
        let fixture = try CheckpointModelFixture()
        let model = hotSeatModel(fixture)
        for _ in 0..<40 {
            guard let seat = actingSeat(model) else { break }
            let legal = RulesEngine.legalMoves(for: model.state, seat: seat)
            let move = legal.first {
                if case .endTurn = $0 { return false }
                if case .buyDevCard = $0 { return false }
                // Negotiation is its own journey and needs bot seats to
                // answer; this fixture is only about when the archive writes.
                if case .proposeTrade = $0 { return false }
                if case .respondToTrade = $0 { return false }
                return true
            } ?? legal[0]
            try model.apply(move)
            let recorded = model.checkpointDocument?.activeMatch?.moves.count ?? 0
            if recorded > 1, try archivedMoveCount(fixture) != recorded { break }
        }
        let recorded = model.checkpointDocument?.activeMatch?.moves.count ?? 0
        #expect(try archivedMoveCount(fixture) != recorded, "the fixture never reached a stale archive")

        model.appWillResignActive()

        #expect(try archivedMoveCount(fixture) == recorded)
    }
}
