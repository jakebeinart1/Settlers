import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@MainActor @Suite struct CheckpointLifecycleTests {
    @Test func replacingThenClearingPreservesBothRecordingsAcrossReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let store = MatchCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.json"))
        let oldMatch = makeMatch(seed: 471)
        let newMatch = makeMatch(seed: 472)
        let original = MatchCheckpointDocument(activeMatch: oldMatch)
        try store.commit(original, replacingRevision: nil)

        let replacement = try original.replacingActiveMatch(with: newMatch)
        try store.commit(replacement, replacingRevision: 0)
        let resumed = try #require(try store.load())
        #expect(resumed.activeMatch == newMatch)
        #expect(resumed.pendingExports == [oldMatch.id: oldMatch])
        #expect(resumed.statistics == GameStats())

        let cleared = try resumed.replacingActiveMatch(with: nil)
        try store.commit(cleared, replacingRevision: 1)
        let final = try #require(try store.load())
        #expect(final.activeMatch == nil)
        #expect(final.pendingExports == [oldMatch.id: oldMatch, newMatch.id: newMatch])
        #expect(final.revision == 2)
    }

    @Test func corruptedDisplacedHistoryIsRejectedOnReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("checkpoint.json")
        var match = makeMatch(seed: 471)
        let actor = PlayerID(index: 0)
        let move = try #require(RulesEngine.legalMoves(for: match.state, seat: actor).first)
        try match.apply(move, by: actor)
        var broken = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(match)) as? [String: Any])
        broken["moves"] = []
        let corruptMatch = try JSONDecoder().decode(MatchCheckpoint.self,
                                                   from: JSONSerialization.data(withJSONObject: broken))
        let cleared = try MatchCheckpointDocument(activeMatch: match).replacingActiveMatch(with: nil)
        var wire = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(cleared)) as? [String: Any])
        wire["pendingExports"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([match.id: corruptMatch]))
        try JSONSerialization.data(withJSONObject: wire).write(to: url)

        #expect(throws: MatchCheckpointStore.StoreError.self) { try MatchCheckpointStore(fileURL: url).load() }
    }

    private func makeMatch(seed: UInt64) -> MatchCheckpoint {
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: seed)
        let setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
        return MatchCheckpoint(id: UUID(), initialState: state, setup: setup)
    }
}
