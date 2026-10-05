import CatanEngine
import Foundation
import Testing
@testable import Settlers

@Suite struct ReplayExportSequenceTests {
    @Test func streamingPositionsMatchTheRecordedPublicBoards() throws {
        let detail = try ReplayExportFixtures.recording(moves: 12)
        var sequence = try ReplayExportSequence(detail: detail)
        var expected = detail.initialState
        let opening = try #require(try sequence.next())
        #expect(opening.position == 0)
        #expect(opening.reconstructionLabel.contains("Older rules unknown"))
        for (index, event) in detail.events.enumerated() {
            try RulesEngine.apply(event.move, by: event.player, to: &expected)
            let frame = try #require(try sequence.next())
            #expect(frame.position == index + 1)
            #expect(frame.boardState.board == expected.board)
            #expect(frame.boardState.players.map(\.settlements) == expected.players.map(\.settlements))
            #expect(frame.boardState.players.map(\.roads) == expected.players.map(\.roads))
            #expect(frame.publicScores == expected.players.map { expected.publicVictoryPoints(for: $0.id) })
            #expect(frame.reconstructionLabel.contains("Current rules for unknown moves"))
            #expect(sequence.closingFrame(from: frame).reconstructionLabel.contains("Older rules unknown"))
        }
        #expect(try sequence.next() == nil)
        #expect(sequence.analysis.lastMove == detail.events.count)
    }

    @Test func invalidMoveLabelsTheWholeValidPrefixPartial() throws {
        let original = try ReplayExportFixtures.recording(moves: 4)
        let invalid = GameLogEvent(timestamp: Date(), player: PlayerID(index: 0), move: .endTurn)
        let detail = ReplayExportFixtures.detail(initial: original.initialState,
                                                 events: Array(original.events.prefix(1)) + [invalid] + original.events.dropFirst(),
                                                 complete: true, winner: PlayerID(index: 0))
        var sequence = try ReplayExportSequence(detail: detail)

        #expect(sequence.analysis.lastMove == 1)
        #expect(sequence.analysis.winner == nil)
        let opening = try #require(try sequence.next())
        let last = try #require(try sequence.next())
        #expect(opening.isPartial && last.isPartial)
        #expect(opening.status.contains("1 of 5"))
        #expect(try sequence.next() == nil)
        #expect(sequence.closingFrame(from: last).caption.contains("beyond move 1"))
    }

    @Test func anEndMarkerWithoutAnEngineWinIsNotACompleteMovie() throws {
        let original = try ReplayExportFixtures.recording(moves: 4)
        let detail = ReplayExportFixtures.detail(initial: original.initialState, events: original.events,
                                                 complete: true, winner: PlayerID(index: 0))

        let sequence = try ReplayExportSequence(detail: detail)

        #expect(sequence.analysis.isPartial)
        #expect(sequence.analysis.notice.contains("verified ending"))
    }

    @Test func aVerifiedEndingNamesTheWinnerWithoutRevealingTheirHiddenScore() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 44)
        let winner = PlayerID(index: 0)
        state.players[0].devCards = Array(repeating: .victoryPoint, count: state.victoryPointTarget)
        state.phase = .gameOver(winner: winner)
        var sequence = try ReplayExportSequence(detail: ReplayExportFixtures.detail(initial: state, complete: true, winner: winner))
        let opening = try #require(try sequence.next())

        let ending = sequence.closingFrame(from: opening)

        #expect(!ending.isPartial)
        #expect(ending.caption == "Player 1 wins")
        #expect(ending.publicScores[0] == 0)
        #expect(ending.boardState.players[0].devCards.isEmpty)
        #expect(ending.reconstructionLabel.contains("Current rules for unknown moves"))
        #expect(ending.reconstructionLabel.contains("Older rules unknown"))
        #expect(sequence.analysis.notice.contains("may differ from the original"),
                "Reaching an ending under current rules must not imply original-rule fidelity")
    }

    @Test func cancellationStopsPreflightBeforeProducingAMovie() async throws {
        let detail = try ReplayExportFixtures.recording()
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ReplayExportSequence(detail: detail)
        }
        do {
            _ = try await task.value
            Issue.record("A cancelled export preflight produced a sequence")
        } catch is CancellationError {
            // Expected; no renderer or writer was started.
        }
    }

    @Test func mixedOldAndCurrentRulesArchiveRetainsVersionsAndReplaysLegacyPublicState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let detail = try ReplayExportFixtures.mixedRulesRecording(directory: root)
        var sequence = try ReplayExportSequence(detail: detail)
        #expect(detail.events.count == 2)
        #expect(detail.events.map(\.rulesVersion) == [RulesEngine.oldestSupportedRulesVersion, RulesEngine.currentRulesVersion])
        #expect(sequence.analysis.lastMove == 2)
        #expect(sequence.analysis.isPartial)
        #expect(!sequence.analysis.hasUnknownRulesVersions)
        #expect(!sequence.analysis.notice.contains("unavailable"))
        var currentOnly = detail.initialState
        let first = try #require(detail.events.first)
        #expect(throws: (any Error).self) { try RulesEngine.apply(first.move, by: first.player, to: &currentOnly) }
        var expected = detail.initialState
        let opening = try #require(try sequence.next())
        for entry in detail.events {
            let version = try #require(entry.rulesVersion)
            try RulesEngine.replay(entry.move, by: entry.player, rulesVersion: version, to: &expected)
            let frame = try #require(try sequence.next())
            #expect(frame.boardState.board == expected.board)
            #expect(frame.boardState.players.map(\.settlements) == expected.players.map(\.settlements))
            #expect(frame.publicScores == expected.players.map { expected.publicVictoryPoints(for: $0.id) })
            #expect(frame.reconstructionLabel == "Reconstructed with recorded rules")
            #expect(frame.isPartial)
        }
        #expect(expected.board.robberTile != opening.boardState.board.robberTile)
        #expect(try sequence.next() == nil)
    }

    @Test func legacyMissingVersionsRemainNilAndWarnOnEveryFrame() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try ReplayExportFixtures.mixedRulesRecording(directory: root)
        // Remove only the version field from an actual JSONL archive. This is
        // a legacy format fixture, not a fabricated default rules assignment.
        let lines = try Data(contentsOf: original.summary.fileURL).split(separator: 0x0A)
        var legacy = Data()
        for line in lines {
            var object = try #require(try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
            object.removeValue(forKey: "rulesVersion")
            legacy.append(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            legacy.append(0x0A)
        }
        try legacy.write(to: original.summary.fileURL)
        let detail = try GameLogStore(directoryURL: root, maxKeptLogs: 1).detail(for: original.summary.fileURL)
        #expect(detail.events.allSatisfy { $0.rulesVersion == nil })
        var sequence = try ReplayExportSequence(detail: detail)
        #expect(sequence.analysis.lastMove == 0, "Unknown legacy robber semantics must not be guessed as version 1")
        #expect(sequence.analysis.hasUnknownRulesVersions)
        #expect(sequence.analysis.notice.contains("Recorded rules versions are unavailable"))
        while let frame = try sequence.next() {
            #expect(frame.reconstructionLabel.contains("Current rules for unknown moves"))
            #expect(frame.reconstructionLabel.contains("Older rules unknown"))
            #expect(frame.isPartial)
            let ending = sequence.closingFrame(from: frame)
            #expect(ending.reconstructionLabel == frame.reconstructionLabel)
            #expect(ending.caption.contains("beyond move 0"))
            #expect(ending.caption.contains("may differ from the original"))
        }
    }

    @Test func appendedMovesWriteCurrentVersionAndFutureVersionsDoNotFallBack() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try ReplayExportFixtures.recording(moves: 1)
        let store = GameLogStore(directoryURL: root, maxKeptLogs: 1)
        let id = try store.startNewGame(initialState: original.initialState, roster: original.roster)
        let entry = try #require(original.events.first)
        try store.appendMove(gameID: id, player: entry.player, move: entry.move)
        let summary = try #require(try store.summary(for: id))
        let written = try store.detail(for: summary)
        #expect(written.events.first?.rulesVersion == RulesEngine.currentRulesVersion)
        let future = GameLogEvent(timestamp: entry.timestamp, player: entry.player, move: entry.move,
                                  rulesVersion: RulesEngine.currentRulesVersion + 1)
        let detail = ReplayExportFixtures.detail(initial: original.initialState, events: [future])
        let sequence = try ReplayExportSequence(detail: detail)
        #expect(sequence.analysis.lastMove == 0)
        #expect(sequence.analysis.isPartial)
        #expect(sequence.analysis.notice.contains("beyond move 0"))
    }

    @Test func mixedKnownAndUnknownVersionsWarnEvenOnKnownPositions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try ReplayExportFixtures.mixedRulesRecording(directory: root)
        let first = try #require(original.events.first)
        let last = try #require(original.events.last)
        let unknown = GameLogEvent(timestamp: last.timestamp, player: last.player, move: last.move)
        let detail = ReplayExportFixtures.detail(initial: original.initialState, events: [first, unknown])
        var sequence = try ReplayExportSequence(detail: detail)
        #expect(unknown.rulesVersion == nil)
        #expect(sequence.analysis.lastMove == 2)
        #expect(sequence.analysis.notice.contains("may differ from the original"))
        while let frame = try sequence.next() {
            #expect(frame.reconstructionLabel.contains("Current rules for unknown moves"))
            #expect(frame.reconstructionLabel.contains("Older rules unknown"))
            #expect(sequence.closingFrame(from: frame).reconstructionLabel == frame.reconstructionLabel)
        }
    }
}
