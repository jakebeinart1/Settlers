import Foundation
import Testing
@testable import CatanEngine
import CatanAI
@testable import Settlers

@Suite struct PolicyContextReplayTests {
    @Test func replayChecksKnownTurnAndProposalCounts() {
        let expected = GameSetup.newGame(board: BoardGenerator.standard(), seed: 23)
        var changed = expected
        changed.completedTurnCount = 1
        #expect(!expected.matchesForReplayValidationExcludingDeclinedTradeHistory(changed))
        changed = expected
        changed.tradesProposedThisTurn = 1
        #expect(!expected.matchesForReplayValidationExcludingDeclinedTradeHistory(changed))
    }

    @Test func replayCannotReplaceKnownHistoryWithUnknownHistory() {
        let known = GameSetup.newGame(board: BoardGenerator.standard(), seed: 23)
        var unknown = known
        unknown.completedTurnCount = nil
        #expect(!known.matchesForReplayValidationExcludingDeclinedTradeHistory(unknown))
        #expect(!unknown.matchesForReplayValidationExcludingDeclinedTradeHistory(known))
    }

    @Test func legacyUnknownHistoryDoesNotInventProposalEquality() {
        var expected = GameSetup.newGame(board: BoardGenerator.standard(), seed: 23)
        expected.completedTurnCount = nil
        var replay = expected
        replay.tradesProposedThisTurn = 2
        #expect(replay.matchesForReplayValidationExcludingDeclinedTradeHistory(expected))
        replay.rng = RandomSource(seed: 24)
        #expect(!replay.matchesForReplayValidationExcludingDeclinedTradeHistory(expected))
    }
}

@MainActor @Suite struct MatchCheckpointStoreTests {
    enum Interruption: Error { case simulatedProcessExit }

    @Test func fullMatchCheckpointsResumeWithoutChangingTheSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let store = MatchCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.json"))
        let initial = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        let setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
        var policies: [PlayerID: any Policy] = [:]
        for player in initial.players {
            policies[player.id] = HeuristicPolicy(personality: .balanced, id: "checkpoint-fixture")
        }
        var session = GameSession(state: initial, policies: policies, policySeed: 99)
        var document = MatchCheckpointDocument(activeMatch: MatchCheckpoint(id: UUID(), initialState: initial, setup: setup))
        try store.commit(document, replacingRevision: nil)
        for index in 1...3_000 {
            guard let step = try session.step() else { break }
            let next = try document.recording(step, session: session.checkpoint, elapsedSeconds: Double(index))
            try store.commit(next, replacingRevision: document.revision)
            document = next
            let acknowledged = try acknowledgingPrivatePresentation(in: document)
            if acknowledged != document {
                try store.commit(acknowledged, replacingRevision: document.revision)
                document = acknowledged
            }
            if index.isMultiple(of: 25) {
                let reloaded = try #require(try store.load())
                let snapshot = try #require(reloaded.activeMatch?.sessionCheckpoint)
                #expect(snapshot == session.checkpoint)
                session = try GameSession(checkpoint: snapshot, policies: policies)
            }
        }
        guard case .gameOver = session.state.phase else {
            Issue.record("checkpoint-driven match did not finish within the action limit")
            return
        }
        #expect(document.statistics.gamesPlayed == 1)
        #expect(document.completions.count == 1)
        #expect(document.activeMatch?.moves.count ?? 0 > 100)
        #expect(try store.load()?.activeMatch?.state == session.state)
    }

    @Test func committedPolicyStepRestoresTheSameSessionContinuation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let store = MatchCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.json"))
        let initial = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        let setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
        var policies: [PlayerID: any Policy] = [:]
        for player in initial.players {
            policies[player.id] = HeuristicPolicy(personality: .balanced, id: "checkpoint-fixture")
        }
        var session = GameSession(state: initial, policies: policies, policySeed: 99)
        let original = MatchCheckpointDocument(activeMatch: MatchCheckpoint(id: UUID(), initialState: initial, setup: setup))
        let step = try #require(try session.step())
        let next = try original.recording(step, session: session.checkpoint, elapsedSeconds: 12)
        try store.commit(original, replacingRevision: nil)
        try store.commit(next, replacingRevision: 0)
        let restored = try #require(try store.load()?.activeMatch?.sessionCheckpoint)
        var resumed = try GameSession(checkpoint: restored, policies: policies)
        let expected = try session.step()
        let actual = try resumed.step()
        #expect(expected?.move == actual?.move)
        #expect(session.state == resumed.state)
        #expect(session.policyRNG == resumed.policyRNG)
    }

    @Test func unreadPurchaseReceiptPreventsTheGameAdvancingPastItsSourceMove() throws {
        let human = PlayerID(index: 0)
        var initial = GameSetup.newGame(board: BoardGenerator.standard(), seed: 472)
        initial.phase = .mainTurn(playerIndex: human.index)
        initial.players[human.index].resources = [.ore: 1, .grain: 1, .wool: 1]
        initial.devCardDeck = [.monopoly]
        let setup = MatchSetup.default(
            preferredName: "Alex",
            preferredCivilization: Civilization.allCases[0]
        )
        var session = GameSession(state: initial, policies: [:], policySeed: 100)
        var document = MatchCheckpointDocument(
            activeMatch: MatchCheckpoint(id: UUID(), initialState: initial, setup: setup)
        )

        let purchase = try session.applyExternal(.buyDevCard, by: human)
        document = try document.recording(
            purchase,
            session: session.checkpoint,
            elapsedSeconds: 1
        )
        let endTurn = try session.applyExternal(.endTurn, by: human)
        #expect(document.pendingDevCardReveal == DevCardReveal(owner: human, card: .monopoly))
        #expect(throws: MatchCheckpointStore.StoreError.pendingAcknowledgement) {
            _ = try document.recording(
                endTurn,
                session: session.checkpoint,
                elapsedSeconds: 2
            )
        }
        try document.validateAuthority()
    }

    @Test func unreadCardResultIsClearedOnlyByAcknowledgement() throws {
        let human = PlayerID(index: 0)
        var initial = GameSetup.newGame(board: BoardGenerator.standard(), seed: 473)
        initial.phase = .mainTurn(playerIndex: human.index)
        initial.players[human.index].devCards = [.monopoly]
        let setup = MatchSetup.default(
            preferredName: "Alex",
            preferredCivilization: Civilization.allCases[0]
        )
        var session = GameSession(state: initial, policies: [:], policySeed: 101)
        var document = MatchCheckpointDocument(
            activeMatch: MatchCheckpoint(id: UUID(), initialState: initial, setup: setup)
        )

        let play = try session.applyExternal(.playMonopoly(.wool), by: human)
        document = try document.recording(play, session: session.checkpoint, elapsedSeconds: 1)
        let expected = DevCardResolution.monopoly(owner: human, resource: .wool, gained: 0)
        #expect(document.pendingDevCardResolution == expected)

        let endTurn = try session.applyExternal(.endTurn, by: human)
        #expect(throws: MatchCheckpointStore.StoreError.pendingAcknowledgement) {
            _ = try document.recording(endTurn, session: session.checkpoint, elapsedSeconds: 2)
        }

        document = try document.dismissingDevCardResolution()
        #expect(document.pendingDevCardResolution == nil)
        document = try document.recording(endTurn, session: session.checkpoint, elapsedSeconds: 2)
        try document.validateAuthority()
    }

    @Test func winningMoveCommitsStateHistoryAndStatisticsInOneRevision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let store = MatchCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.json"))
        let (before, step) = try winningMove()
        let setup = MatchSetup(
            seats: before.players.map { player in
                MatchSetup.Seat(index: player.id.index, isHuman: player.id == step.actor,
                                name: "Player \(player.id.index)", civilization: Civilization.allCases[player.id.index])
            }, victoryPointTarget: before.victoryPointTarget, randomizedBoard: false, randomizeSeatOrder: false)
        let original = MatchCheckpointDocument(activeMatch: MatchCheckpoint(id: UUID(), initialState: before, setup: setup))
        let next = try original.applying(step.move, by: step.actor, elapsedSeconds: 123)
        try store.commit(original, replacingRevision: nil)
        try store.commit(next, replacingRevision: original.revision)
        #expect(try store.load() == next)
        #expect(next.activeMatch?.state.phase == .gameOver(winner: step.actor))
        #expect(next.activeMatch?.moves.count == 1)
        #expect(next.revision == 1)
        #expect(next.statistics.gamesPlayed == 1)
        #expect(next.statistics.gamesWon == 1)
        #expect(next.completions.count == 1)
        try next.activeMatch?.validateHistory()

        let cleared = try next.replacingActiveMatch(with: nil)
        try store.commit(cleared, replacingRevision: next.revision)
        let afterClear = try #require(try store.load())
        #expect(afterClear.activeMatch == nil)
        #expect(afterClear.statistics == next.statistics)
        #expect(afterClear.completions == next.completions)
        let match = try #require(next.activeMatch)
        #expect(afterClear.pendingExports[match.id] == match)
        #expect(throws: MatchCheckpointStore.StoreError.self) {
            try afterClear.replacingActiveMatch(with: match)
        }
    }

    private func winningMove() throws -> (GameState, GameSession.Step) {
        let initial = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        var policies: [PlayerID: any Policy] = [:]
        for player in initial.players {
            policies[player.id] = HeuristicPolicy(personality: .balanced, id: "checkpoint-fixture")
        }
        var session = GameSession(state: initial, policies: policies, policySeed: 99)
        for _ in 0..<10_000 {
            let before = session.state
            let step = try #require(try session.step())
            if case .gameOver = session.state.phase { return (before, step) }
        }
        throw Interruption.simulatedProcessExit // Failure, not a fabricated terminal fixture.
    }

    @Test func applyingAMoveProducesOneRevisionWithoutChangingThePreviousDocument() throws {
        let initial = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        let setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
        let original = MatchCheckpointDocument(activeMatch: MatchCheckpoint(
            id: UUID(), initialState: initial, setup: setup))
        let actor = PlayerID(index: 0)
        let move = try #require(RulesEngine.legalMoves(for: initial, seat: actor).first)

        let next = try original.applying(move, by: actor, elapsedSeconds: 12)

        #expect(original.activeMatch?.state == initial)
        #expect(original.revision == 0)
        #expect(next.revision == 1)
        #expect(next.activeMatch?.moves.count == 1)
        #expect(next.activeMatch?.elapsedSeconds == 12)
        #expect(next.activeMatch?.state.players[0].settlements.count == 1)
        #expect(next.statistics == GameStats())
    }

    @Test func resettingStatisticsDoesNotRecountTheCurrentCompletedMatch() throws {
        var terminal = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        terminal.phase = .gameOver(winner: PlayerID(index: 0))
        let setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
        var document = MatchCheckpointDocument(activeMatch: MatchCheckpoint(
            id: UUID(), initialState: terminal, setup: setup))
        try document.recordCompletion(duration: 123)
        try document.resetStatistics()
        try document.recordCompletion(duration: 999)
        #expect(document.statistics == GameStats())
        #expect(document.completions.count == 1)
    }

    @Test(arguments: [1, 2])
    func completedMatchIsCountedOnceAcrossReloadAndRetry(humanCount: Int) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let url = root.appendingPathComponent("checkpoint.json")
        var terminal = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        terminal.phase = .gameOver(winner: PlayerID(index: 0))
        var setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
        if humanCount == 2 {
            setup.seats[1].isHuman = true
            setup.seats[1].name = "Sam"
        }
        let match = MatchCheckpoint(id: UUID(), initialState: terminal, setup: setup)
        var document = MatchCheckpointDocument(activeMatch: match)
        try MatchCheckpointStore(fileURL: url).commit(document, replacingRevision: nil)
        try document.recordCompletion(duration: 123)
        let interrupted = MatchCheckpointStore(fileURL: url, atCommitStage: { stage in
            if stage == .afterReplace { throw Interruption.simulatedProcessExit }
        })
        #expect(throws: Interruption.self) { try interrupted.commit(document, replacingRevision: 0) }
        var resumed = try #require(try MatchCheckpointStore(fileURL: url).load())
        try resumed.recordCompletion(duration: 999)
        try MatchCheckpointStore(fileURL: url).commit(resumed, replacingRevision: 0)
        let result = try #require(try MatchCheckpointStore(fileURL: url).load())
        #expect(result.statistics.gamesPlayed == (humanCount == 1 ? 1 : 0))
        #expect(result.statistics.gamesWon == (humanCount == 1 ? 1 : 0))
        #expect(result.statistics.totalDurationSeconds == (humanCount == 1 ? 123 : 0))
        #expect(result.completions.count == 1)
    }

    @Test func recordedMoveAndStateCannotDivergeOnReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let url = root.appendingPathComponent("checkpoint.json")
        let initial = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        let setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
        var match = MatchCheckpoint(id: UUID(), initialState: initial, setup: setup)
        let actor = PlayerID(index: 0)
        let move = try #require(RulesEngine.legalMoves(for: initial, seat: actor).first)
        try match.apply(move, by: actor)
        let document = MatchCheckpointDocument(activeMatch: match)
        try MatchCheckpointStore(fileURL: url).commit(document, replacingRevision: nil)
        #expect(try MatchCheckpointStore(fileURL: url).load()?.activeMatch?.state == match.state)
        var malformed = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        var active = try #require(malformed["activeMatch"] as? [String: Any])
        active["moves"] = []
        malformed["activeMatch"] = active
        try JSONSerialization.data(withJSONObject: malformed).write(to: url)
        #expect(throws: MatchCheckpointStore.StoreError.self) { try MatchCheckpointStore(fileURL: url).load() }
    }

    @Test(arguments: [MatchCheckpointStore.CommitStage.beforeReplace, .afterReplace])
    func interruptionRecoversOneWholeRevision(stage: MatchCheckpointStore.CommitStage) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let url = root.appendingPathComponent("checkpoint.json")
        let original = MatchCheckpointDocument(activeMatch: nil)
        try MatchCheckpointStore(fileURL: url).commit(original, replacingRevision: nil)
        let next = MatchCheckpointDocument(activeMatch: nil, revision: 1)
        let interrupted = MatchCheckpointStore(fileURL: url, atCommitStage: { reached in
            if reached == stage { throw Interruption.simulatedProcessExit }
        })

        #expect(throws: Interruption.self) { try interrupted.commit(next, replacingRevision: 0) }

        let recovered = try MatchCheckpointStore(fileURL: url).load()
        #expect(recovered == (stage == .beforeReplace ? original : next))
    }

    @Test func committedMatchRestoresStateRosterAndHistoryTogether() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let url = root.appendingPathComponent("checkpoint.json")
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        let setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
        let match = MatchCheckpoint(id: UUID(), initialState: state, setup: setup)
        let document = MatchCheckpointDocument(activeMatch: match)

        try MatchCheckpointStore(fileURL: url).commit(document, replacingRevision: nil)

        let restored = try #require(try MatchCheckpointStore(fileURL: url).load())
        #expect(restored == document)
        #expect(restored.activeMatch?.state == state)
        #expect(restored.activeMatch?.moves.isEmpty == true)
    }

    /// Regression test for finding C1 of the final whole-branch review
    /// (2026-09-03). A save recorded before `GameState
    /// .declinedTradeOffersThisTurn` existed has a persisted `state`
    /// snapshot that never recorded a decline, even though the same save's
    /// move history contains a `.respondToTrade(_, false)`. Replaying that
    /// history under the CURRENT engine legitimately re-populates the field
    /// for the current turn - so a naive `replay == state` comparison in
    /// `validateHistory()` would disagree with a snapshot that is, in every
    /// rule/RNG/win-condition sense, perfectly valid, and mark the whole
    /// document blocked. Simulates that shape directly: build a match whose
    /// history contains a genuine decline, then blank the persisted
    /// snapshot's `declinedTradeOffersThisTurn` the way an old build's save
    /// would have (it never wrote to that key), and confirm
    /// `validateHistory()` still does not throw.
    @Test func validateHistoryToleratesADeclinedTradeSnapshotFromBeforeTheFieldExisted() throws {
        var initial = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        initial.phase = .mainTurn(playerIndex: 0)
        initial.players[0].resources = [.lumber: 1]
        let proposer = initial.players[0].id
        let responder = initial.players[1].id
        let setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
        var match = MatchCheckpoint(id: UUID(), initialState: initial, setup: setup)

        let offer = TradeOffer(from: proposer, give: [.lumber: 1], want: [.ore: 1])
        try match.apply(.proposeTrade(offer), by: proposer)
        try match.apply(.respondToTrade(offerID: offer.id, accept: false), by: responder)
        #expect(match.state.declinedTradeOffersThisTurn[proposer] == [offer])
        try match.validateHistory() // Sanity: today's own code round-trips cleanly.

        // Simulate an old build's save: its snapshot never wrote this key at
        // all, so a decoder using `decodeIfPresent` sees it as absent/empty -
        // everything else about the snapshot (moves, board, players, phase,
        // rng) is untouched.
        var object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(match)) as? [String: Any])
        var stateObject = try #require(object["state"] as? [String: Any])
        stateObject.removeValue(forKey: "declinedTradeOffersThisTurn")
        object["state"] = stateObject
        let agedSave = try JSONSerialization.data(withJSONObject: object)
        let reloaded = try JSONDecoder().decode(MatchCheckpoint.self, from: agedSave)

        #expect(reloaded.state.declinedTradeOffersThisTurn.isEmpty)
        #expect(throws: Never.self) { try reloaded.validateHistory() }
    }

    @Test func originMainYearOfPlentyHistoryStillLoadsAfterAtomicSupplyRulesShip() throws {
        let human = PlayerID(index: 0)
        var initial = GameSetup.newGame(board: BoardGenerator.standard(), seed: 911)
        initial.phase = .mainTurn(playerIndex: human.index)
        initial.players[human.index].devCards = [.yearOfPlenty]
        initial.bank[.ore] = 0
        initial.bank[.grain] = 1
        let setup = MatchSetup.default(
            preferredName: "Alex",
            preferredCivilization: Civilization.allCases[0]
        )
        var match = MatchCheckpoint(id: UUID(), initialState: initial, setup: setup)
        try match.apply(
            .playYearOfPlenty(.ore, .grain),
            by: human,
            rulesVersion: RulesEngine.oldestSupportedRulesVersion
        )

        let decoded = try JSONDecoder().decode(
            MatchCheckpoint.self,
            from: encodedAsOriginMainCheckpoint(match)
        )

        #expect(decoded.moves.map(\.rulesVersion) == [RulesEngine.oldestSupportedRulesVersion])
        #expect(decoded.state.players[human.index].resources[.ore] == nil)
        #expect(decoded.state.players[human.index].resources[.grain] == 1)
        #expect(throws: Never.self) { try decoded.validateHistory() }
    }

    @Test func originMainRobberHistoryStillLoadsAfterVictimSelectionBecomesMandatory() throws {
        let human = PlayerID(index: 0)
        let victim = PlayerID(index: 1)
        var initial = GameSetup.newGame(board: BoardGenerator.standard(), seed: 912)
        let target = try #require(initial.board.tiles.map(\.coordinate).first {
            $0 != initial.board.robberTile
        })
        let victimVertex = try #require(HexGeometry.corners(of: target).first)
        initial.phase = .movingRobber(playerIndex: human.index)
        initial.players[victim.index].settlements.insert(victimVertex)
        initial.players[victim.index].resources = [.lumber: 1]
        let setup = MatchSetup.default(
            preferredName: "Alex",
            preferredCivilization: Civilization.allCases[0]
        )
        var match = MatchCheckpoint(id: UUID(), initialState: initial, setup: setup)
        try match.apply(
            .moveRobber(target, stealFrom: nil),
            by: human,
            rulesVersion: RulesEngine.oldestSupportedRulesVersion
        )

        let decoded = try JSONDecoder().decode(
            MatchCheckpoint.self,
            from: encodedAsOriginMainCheckpoint(match)
        )

        #expect(decoded.moves.map(\.rulesVersion) == [RulesEngine.oldestSupportedRulesVersion])
        #expect(decoded.state.board.robberTile == target)
        #expect(decoded.state.players[victim.index].resources[.lumber] == 1)
        #expect(throws: Never.self) { try decoded.validateHistory() }
    }

    /// Removes the field that did not exist in `origin/main`'s encoded move
    /// objects. Decoding those exact bytes must choose version 1 rather than
    /// silently assigning today's behavior to historical decisions.
    private func encodedAsOriginMainCheckpoint(_ match: MatchCheckpoint) throws -> Data {
        var object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(match)) as? [String: Any]
        )
        var moves = try #require(object["moves"] as? [[String: Any]])
        for index in moves.indices {
            moves[index].removeValue(forKey: "rulesVersion")
        }
        object["moves"] = moves
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func acknowledgingPrivatePresentation(
        in document: MatchCheckpointDocument
    ) throws -> MatchCheckpointDocument {
        if document.pendingDevCardReveal != nil {
            return try document.dismissingDevCardReveal()
        }
        if document.pendingDevCardResolution != nil {
            return try document.dismissingDevCardResolution()
        }
        return document
    }
}
