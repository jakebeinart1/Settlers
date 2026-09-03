import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@Suite struct GameLogArchiveTests {
    @MainActor
    @Test func loggingFailureWarnsButDoesNotRejectALegalMove() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameLogWarning.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: blocked)
        let defaults = try #require(UserDefaults(suiteName: "GameLogWarning.\(UUID().uuidString)"))
        let setupStore = MatchSetupStore()
        setupStore.defaults = defaults
        CivilizationAssignment.current = Array(Civilization.allCases.prefix(4))
        CivilizationAssignment.humanSeat = PlayerID(index: 0)
        let model = GameViewModel(
            gameStore: GameStore(fileURL: root.appendingPathComponent("save.json")),
            civilizationStore: CivilizationAssignmentStore(
                fileURL: root.appendingPathComponent("civilizations.json")),
            matchSetupStore: setupStore,
            gameLogStore: GameLogStore(directoryURL: blocked, maxKeptLogs: 2),
            gameStatsStore: GameStatsStore(fileURL: root.appendingPathComponent("stats.json")))
        model.startNewGame(randomizedBoard: false, randomizeSeat: false)
        let move = try #require(RulesEngine.legalMoves(for: model.state, seat: model.humanPlayer).first)

        try model.apply(move)

        #expect(model.gameLogWarning != nil)
        #expect(model.eventBatch.events.isEmpty == false)
    }

    @Test func hotSeatRosterAndCompletedResultAreReadable() throws {
        try withStore { store in
            let state = GameSetup.newGame(
                board: BoardGenerator.standard(), seed: 7,
                playerCount: 4, victoryPointTarget: 12
            )
            let roster = GameLogStore.SeatRoster(
                humanSeats: [PlayerID(index: 0), PlayerID(index: 2)],
                humanNames: [0: "Alex", 2: "Jake"],
                botProfiles: [1: "rome", 3: "norse"],
                botProfileNames: [1: "Augustus", 3: "Ragnar"],
                botPersonalities: [1: "balanced", 3: "aggressive"],
                civilizations: [0: "Greece", 1: "Rome", 2: "Japan", 3: "Norse"]
            )
            let id = try store.startNewGame(initialState: state, roster: roster)
            try store.appendMove(gameID: id, player: PlayerID(index: 0), move: .rollDice)
            try store.finalizeGame(gameID: id, winner: PlayerID(index: 2))

            let summary = try #require(store.summaries().first)
            #expect(summary.gameID == id)
            #expect(summary.playerCount == 4)
            #expect(summary.victoryPointTarget == 12)
            #expect(summary.humanSeats == [PlayerID(index: 0), PlayerID(index: 2)])
            #expect(summary.winner == PlayerID(index: 2))
            #expect(summary.moveCount == 1)

            let detail = try store.detail(for: summary)
            #expect(detail.roster.humanNames == [0: "Alex", 2: "Jake"])
            #expect(detail.roster.botProfiles == [1: "rome", 3: "norse"])
            #expect(detail.roster.botProfileNames == [1: "Augustus", 3: "Ragnar"])
            #expect(detail.events.count == 1)
            #expect(detail.events[0].player == PlayerID(index: 0))
        }
    }

    @Test func versionTwoRosterWithoutProfilesStillDecodes() throws {
        let json = #"{"humanSeat":{"index":0},"humanSeats":[{"index":0}],"humanNames":{},"botPersonalities":{"1":"balanced"},"civilizations":{"0":"Greece","1":"Rome"}}"#

        let roster = try JSONDecoder().decode(
            GameLogStore.SeatRoster.self, from: Data(json.utf8)
        )

        #expect(roster.botProfiles.isEmpty)
        #expect(roster.botProfileNames.isEmpty)
        #expect(roster.botPersonalities == [1: "balanced"])
    }

    @Test func crashTruncatedFinalLineKeepsAllCompleteEvents() throws {
        try withStore { store in
            let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 8)
            let id = try store.startNewGame(initialState: state, roster: .legacy(humanSeat: PlayerID(index: 0)))
            try store.appendMove(gameID: id, player: PlayerID(index: 0), move: .rollDice)
            let url = try #require(store.logFiles().first)
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(#"{"kind":"move""#.utf8))
            try handle.close()

            let detail = try store.detail(for: url)

            #expect(detail.events.count == 1)
            #expect(!detail.isComplete)
        }
    }

    @Test func malformedCompleteLineIsReported() throws {
        try withStore { store in
            let url = try store.logDirectory().appendingPathComponent("broken.jsonl")
            try Data("not-json\n".utf8).write(to: url)

            #expect(throws: GameLogStore.ReadError.self) {
                try store.detail(for: url)
            }
        }
    }

    @Test func corruptFileDoesNotHideHealthySummaries() throws {
        try withStore { store in
            let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 81)
            let id = try store.startNewGame(
                initialState: state, roster: .legacy(humanSeat: PlayerID(index: 0)))
            let broken = try store.logDirectory().appendingPathComponent("broken.jsonl")
            try Data("not-json\n".utf8).write(to: broken)

            let scan = try store.scan()

            #expect(scan.summaries.map(\.gameID) == [id])
            #expect(scan.failures.count == 1)
            #expect(scan.failures[0].fileURL == broken)
        }
    }

    @Test func writeFailureThrowsInsteadOfTerminatingGameplay() throws {
        let fileInsteadOfDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameLogBlocked.\(UUID().uuidString)")
        try Data("occupied".utf8).write(to: fileInsteadOfDirectory)
        defer { try? FileManager.default.removeItem(at: fileInsteadOfDirectory) }
        let store = GameLogStore(directoryURL: fileInsteadOfDirectory, maxKeptLogs: 2)

        #expect(throws: GameLogStore.IOError.self) {
            try store.startNewGame(
                initialState: GameSetup.newGame(board: BoardGenerator.standard(), seed: 82),
                roster: .legacy(humanSeat: PlayerID(index: 0)))
        }
    }

    @Test func activeGameIdentifierSurvivesStoreRecreationUntilFinalized() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameLogContinuity.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstStore = GameLogStore(directoryURL: directory, maxKeptLogs: 2)
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 83)
        let id = try firstStore.startNewGame(
            initialState: state, roster: .legacy(humanSeat: PlayerID(index: 0)))

        let relaunchedStore = GameLogStore(directoryURL: directory, maxKeptLogs: 2)
        #expect(try relaunchedStore.activeGameID() == id)

        try relaunchedStore.finalizeGame(gameID: id, winner: PlayerID(index: 0))
        #expect(try relaunchedStore.activeGameID() == nil)
    }

    @Test func summariesAreNewestFirst() throws {
        try withStore { store in
            let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 9)
            let first = try store.startNewGame(initialState: state, roster: .legacy(humanSeat: PlayerID(index: 0)))
            let second = try store.startNewGame(initialState: state, roster: .legacy(humanSeat: PlayerID(index: 0)))
            let firstURL = try store.logDirectory().appendingPathComponent("\(first.uuidString).jsonl")
            let secondURL = try store.logDirectory().appendingPathComponent("\(second.uuidString).jsonl")
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: firstURL.path)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 2)], ofItemAtPath: secondURL.path)

            #expect(try store.summaries().map(\.gameID) == [second, first])
        }
    }

    @Test func legacySingleHumanRosterStillLoads() throws {
        try withStore { store in
            let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 10)
            let id = try store.startNewGame(initialState: state, roster: .legacy(humanSeat: PlayerID(index: 3)))
            let url = try store.logDirectory().appendingPathComponent("\(id.uuidString).jsonl")
            let fileData = try Data(contentsOf: url)
            var lines = try #require(String(data: fileData, encoding: .utf8))
                .split(separator: "\n").map(String.init)
            var startObject = try #require(
                JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
            var roster = try #require(startObject["roster"] as? [String: Any])
            roster.removeValue(forKey: "humanSeats")
            roster.removeValue(forKey: "humanNames")
            startObject["roster"] = roster
            let legacyData = try JSONSerialization.data(withJSONObject: startObject)
            lines[0] = try #require(String(data: legacyData, encoding: .utf8))
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)

            let detail = try store.detail(for: url)

            #expect(detail.roster.humanSeats == [PlayerID(index: 3)])
            #expect(detail.roster.humanNames.isEmpty)
        }
    }

    @Test func retentionLimitPrunesTheOldestFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameLogRetentionTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GameLogStore(directoryURL: directory, maxKeptLogs: 2)
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 11)
        _ = try store.startNewGame(initialState: state, roster: .legacy(humanSeat: PlayerID(index: 0)))
        _ = try store.startNewGame(initialState: state, roster: .legacy(humanSeat: PlayerID(index: 0)))
        _ = try store.startNewGame(initialState: state, roster: .legacy(humanSeat: PlayerID(index: 0)))

        #expect(try store.logFiles().count == 2)
    }

    private func withStore(_ body: (GameLogStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameLogStoreTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(GameLogStore(directoryURL: directory, maxKeptLogs: 500))
    }
}
