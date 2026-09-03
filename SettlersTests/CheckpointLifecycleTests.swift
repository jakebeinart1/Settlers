import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@MainActor @Suite struct CheckpointLifecycleTests {
    @Test(arguments: [GameStats(gamesPlayed: Int.max), GameStats(totalDurationSeconds: .greatestFiniteMagnitude)])
    func overflowingTotalsDoNotPartiallyRecordACompletion(baseline: GameStats) throws {
        var terminal = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        terminal.phase = .gameOver(winner: PlayerID(index: 0))
        let setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
        let match = MatchCheckpoint(id: UUID(), initialState: terminal, setup: setup)
        var document = try MatchCheckpointDocument(legacyStatistics: baseline).replacingActiveMatch(with: match)
        let revision = document.revision
        #expect(throws: MatchCheckpointStore.StoreError.self) {
            try document.recordCompletion(duration: .greatestFiniteMagnitude)
        }
        #expect(document.statistics == baseline)
        #expect(document.completions.isEmpty)
        #expect(document.revision == revision)
    }

    @Test func recoveryRefusesASourceThatChangedAfterBackupValidation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("checkpoint.json")
        let backup = root.appendingPathComponent("backup.json")
        let original = Data("old damaged save".utf8)
        let newer = Data("newer save from another writer".utf8)
        try original.write(to: url)
        try original.write(to: backup)
        let store = MatchCheckpointStore(fileURL: url, atCommitStage: { stage in
            if stage == .beforeReplace { try newer.write(to: url) }
        })
        #expect(throws: MatchCheckpointStore.StoreError.self) {
            try store.replaceAfterRecovery(MatchCheckpointDocument(activeMatch: nil), preservedOriginalAt: backup)
        }
        #expect(try Data(contentsOf: url) == newer)
        #expect(try Data(contentsOf: backup) == original)
    }

    @Test func theSourceItselfIsNotAnIndependentRecoveryBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("checkpoint.json")
        let original = Data("damaged checkpoint".utf8)
        try original.write(to: url)
        let store = MatchCheckpointStore(fileURL: url)
        #expect(throws: MatchCheckpointStore.StoreError.self) {
            try store.replaceAfterRecovery(MatchCheckpointDocument(activeMatch: nil), preservedOriginalAt: url)
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test(arguments: [true, false])
    func damagedCheckpointReplacementRequiresAnExactIndependentBackup(matchingBackup: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("checkpoint.json")
        let backup = root.appendingPathComponent("backup.json")
        let damaged = Data("damaged checkpoint".utf8)
        try damaged.write(to: url)
        try (matchingBackup ? damaged : Data("different file".utf8)).write(to: backup)
        let store = MatchCheckpointStore(fileURL: url)
        let replacement = MatchCheckpointDocument(activeMatch: makeMatch(seed: 471))
        if matchingBackup {
            try store.replaceAfterRecovery(replacement, preservedOriginalAt: backup)
            #expect(try store.load() == replacement)
            #expect(try Data(contentsOf: backup) == damaged)
        } else {
            #expect(throws: MatchCheckpointStore.StoreError.self) {
                try store.replaceAfterRecovery(replacement, preservedOriginalAt: backup)
            }
            #expect(try Data(contentsOf: url) == damaged)
        }
    }

    @Test func elapsedTimeCanBeBankedWithoutInventingAMove() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
        let store = MatchCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.json"))
        let original = MatchCheckpointDocument(activeMatch: makeMatch(seed: 471))
        let banked = try original.recordingElapsedTime(42)
        try store.commit(original, replacingRevision: nil)
        try store.commit(banked, replacingRevision: 0)
        #expect(try store.load()?.activeMatch?.elapsedSeconds == 42)
        #expect(banked.activeMatch?.elapsedSeconds == 42)
        #expect(banked.activeMatch?.moves.isEmpty == true)
        #expect(banked.activeMatch?.state == original.activeMatch?.state)
        #expect(banked.revision == 1)
        #expect(try banked.recordingElapsedTime(42) == banked)
        #expect(throws: MatchCheckpointStore.StoreError.self) { try banked.recordingElapsedTime(41) }
    }

    @Test func finishedMatchDurationDoesNotGrowOnLaterLifecycleEvents() throws {
        var terminal = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        terminal.phase = .gameOver(winner: PlayerID(index: 0))
        let setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
        var match = MatchCheckpoint(id: UUID(), initialState: terminal, setup: setup)
        try match.recordElapsedTime(42)
        let completed = MatchCheckpointDocument(activeMatch: match)
        #expect(try completed.recordingElapsedTime(999) == completed)
        #expect(throws: MatchCheckpointStore.StoreError.self) { try completed.recordingElapsedTime(.infinity) }
    }

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

    @Test(arguments: [
        GameStats(gamesPlayed: -1),
        GameStats(gamesPlayed: 1, gamesWon: 2),
        GameStats(totalFinalVP: -1),
        GameStats(totalDurationSeconds: -1)
    ])
    func invalidAuthoritativeStatisticsAreRejectedOnReload(statistics: GameStats) throws {
        let document = MatchCheckpointDocument(legacyStatistics: statistics)
        try expectReloadToReject(document)
    }

    @Test func completionReceiptMustAgreeWithItsRetainedTerminalMatch() throws {
        let (document, match) = try completedDocument()
        let wrongWinner = PlayerID(index: 1)
        try expectReloadToReject(document) { wire in
            try Self.mutateCompletion(for: match.id, in: &wire) { completion in
                completion["winner"] = ["index": wrongWinner.index]
            }
        }
        try expectReloadToReject(document) { wire in
            try Self.mutateCompletion(for: match.id, in: &wire) { completion in
                completion["duration"] = -1
            }
        }
        try expectReloadToReject(document) { wire in
            try Self.mutateCompletion(for: match.id, in: &wire) { completion in
                completion["finalVP"] = -1
            }
        }
    }

    @Test func completionReceiptForANonterminalRetainedMatchIsRejected() throws {
        let (completed, terminalMatch) = try completedDocument()
        let liveMatch = makeMatch(seed: 472)
        let wire = try Self.wire(for: completed)
        var completions = try #require(wire["completions"] as? [Any])
        let receiptIndex = try Self.valueIndex(for: terminalMatch.id, in: completions)
        completions[receiptIndex - 1] = liveMatch.id.uuidString
        let liveDocument = MatchCheckpointDocument(activeMatch: liveMatch)
        var liveWire = try Self.wire(for: liveDocument)
        liveWire["completions"] = completions
        liveWire["activeMatch"] = try Self.wireValue(for: liveMatch)
        try expectReloadToReject(wire: liveWire)
    }

    @Test func archivedSetupMustAgreeWithItsEngineState() throws {
        let match = makeMatch(seed: 471)
        let archived = try MatchCheckpointDocument(activeMatch: match).replacingActiveMatch(with: nil)
        try expectReloadToReject(archived) { wire in
            try Self.mutatePendingMatch(for: match.id, in: &wire) { pending in
                var setup = try #require(pending["setup"] as? [String: Any])
                setup["victoryPointTarget"] = WinCondition.supportedTargets.upperBound
                pending["setup"] = setup
            }
        }
        try expectReloadToReject(archived) { wire in
            try Self.mutatePendingMatch(for: match.id, in: &wire) { pending in
                var setup = try #require(pending["setup"] as? [String: Any])
                var seats = try #require(setup["seats"] as? [[String: Any]])
                seats.removeLast()
                setup["seats"] = seats
                pending["setup"] = setup
            }
        }
    }

    private func completedDocument() throws -> (MatchCheckpointDocument, MatchCheckpoint) {
        var terminal = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        terminal.phase = .gameOver(winner: PlayerID(index: 0))
        let setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
        let match = MatchCheckpoint(id: UUID(), initialState: terminal, setup: setup)
        var document = MatchCheckpointDocument(activeMatch: match)
        try document.recordCompletion(duration: 42)
        return (document, match)
    }

    private func expectReloadToReject(
        _ document: MatchCheckpointDocument,
        mutate: (inout [String: Any]) throws -> Void = { _ in }
    ) throws {
        var wire = try Self.wire(for: document)
        try mutate(&wire)
        try expectReloadToReject(wire: wire)
    }

    private func expectReloadToReject(wire: [String: Any]) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("checkpoint.json")
        try JSONSerialization.data(withJSONObject: wire).write(to: url)
        #expect(throws: MatchCheckpointStore.StoreError.self) { try MatchCheckpointStore(fileURL: url).load() }
    }

    private static func wire(for value: some Encodable) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private static func wireValue(for value: some Encodable) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    private static func mutateCompletion(
        for id: UUID,
        in wire: inout [String: Any],
        mutate: (inout [String: Any]) -> Void
    ) throws {
        var completions = try #require(wire["completions"] as? [Any])
        let index = try valueIndex(for: id, in: completions)
        var completion = try #require(completions[index] as? [String: Any])
        mutate(&completion)
        completions[index] = completion
        wire["completions"] = completions
    }

    private static func mutatePendingMatch(
        for id: UUID,
        in wire: inout [String: Any],
        mutate: (inout [String: Any]) throws -> Void
    ) throws {
        var pending = try #require(wire["pendingExports"] as? [Any])
        let index = try valueIndex(for: id, in: pending)
        var match = try #require(pending[index] as? [String: Any])
        try mutate(&match)
        pending[index] = match
        wire["pendingExports"] = pending
    }

    private static func valueIndex(for id: UUID, in encodedDictionary: [Any]) throws -> Int {
        let keyIndex = try #require(encodedDictionary.indices.first(where: { index in
            index.isMultiple(of: 2) && (encodedDictionary[index] as? String) == id.uuidString
        }))
        return keyIndex + 1
    }

    private func makeMatch(seed: UInt64) -> MatchCheckpoint {
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: seed)
        let setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
        return MatchCheckpoint(id: UUID(), initialState: state, setup: setup)
    }
}
