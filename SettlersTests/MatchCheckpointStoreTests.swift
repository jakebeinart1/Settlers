import Foundation
import Testing
@testable import CatanEngine
import CatanAI
@testable import Settlers

@MainActor @Suite struct MatchCheckpointStoreTests {
    enum Interruption: Error { case simulatedProcessExit }

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
}
