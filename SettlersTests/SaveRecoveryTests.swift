import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@MainActor
@Suite(.serialized)
struct SaveRecoveryTests {
    @Test func aRealHumanCanContinueAnInterruptedSetup() throws {
        let fixture = try RecoveryFixture()
        let original = fixture.makeModel()
        original.startNewGame(setup: fixture.validSetup)
        original.isSettingsSurfaceOpen = true
        let settlement = try #require(RulesEngine.legalMoves(for: original.state, seat: original.humanPlayer).first)
        try original.apply(settlement)
        let checkpoint = original.state
        let expectedProfiles = original.opponentProfiles

        let resumed = fixture.makeModel()
        resumed.isSettingsSurfaceOpen = true
        #expect(resumed.savedGameAvailability.canResume)
        #expect(resumed.state == checkpoint)
        #expect(resumed.opponentProfiles == expectedProfiles)
        #expect(resumed.playerLabel(for: resumed.humanPlayer) == "Alex")
        let road = try #require(RulesEngine.legalMoves(for: resumed.state, seat: resumed.humanPlayer).first)
        guard case .placeInitialRoad = road else {
            Issue.record("A resumed opening settlement must still require its adjacent road")
            return
        }
        try resumed.apply(road)
        #expect(resumed.state.players[0].roads.count == 1)
        #expect(fixture.makeModel().state == resumed.state)
    }

    @Test(arguments: [[0, 0, 2], [0, -1, 2], [0, 1, 3], [1, 0, 2]])
    func malformedRosterIndicesBlockColdResume(indices: [Int]) async throws {
        let fixture = try RecoveryFixture()
        let initial = fixture.makeModel()
        initial.startNewGame(setup: fixture.validSetup)
        // Seed an actual legacy save; production no longer writes sidecars.
        try fixture.gameStore.save(initial.state)
        var malformed = try #require(initial.checkpointDocument?.activeMatch?.setup)
        try FileManager.default.removeItem(at: initial.checkpointStore.fileURL)
        for (offset, index) in indices.enumerated() { malformed.seats[offset].index = index }
        try fixture.setupStore.saveActiveMatch(malformed)
        let original = try Data(contentsOf: fixture.gameStore.fileURL)

        let model = fixture.makeModel()
        await model.runBotTurnIfNeeded()

        #expect(!model.savedGameAvailability.canResume)
        #expect(model.savedGameAvailability.recoveryMessage != nil)
        #expect(model.saveWasUnreadable)
        #expect(try Data(contentsOf: fixture.gameStore.fileURL) == original)
    }

    @Test(arguments: [-1, 3, Int.max])
    func invalidLegacyHumanSeatBlocksColdResume(index: Int) throws {
        let fixture = try RecoveryFixture()
        try fixture.gameStore.save(GameSetup.newGame(board: BoardGenerator.standard(), seed: 71, playerCount: 3))
        HumanSeatStore(defaults: fixture.defaults).save(PlayerID(index: index))
        #expect(!fixture.makeModel().savedGameAvailability.canResume)
    }

    @Test func validLegacySeatStillResumesWithoutModernMetadata() throws {
        let fixture = try RecoveryFixture()
        let saved = GameSetup.newGame(board: BoardGenerator.standard(), seed: 71, playerCount: 3)
        try fixture.gameStore.save(saved)
        HumanSeatStore(defaults: fixture.defaults).save(PlayerID(index: 2))
        let model = fixture.makeModel()
        #expect(model.savedGameAvailability.canResume)
        #expect(model.humanPlayer.index == 2)
        #expect(model.state == saved)
    }

    @Test func legacyReplacementPreservesItsHumanSeatMetadata() throws {
        let fixture = try RecoveryFixture()
        try Data("damaged game".utf8).write(to: fixture.gameStore.fileURL)
        HumanSeatStore(defaults: fixture.defaults).save(PlayerID(index: 99))
        let model = fixture.makeModel()

        model.startNewGame(randomizedBoard: false, randomizeSeat: false)

        let recovery = fixture.root.appendingPathComponent("Recovery")
        let archive = try #require(FileManager.default.contentsOfDirectory(
            at: recovery, includingPropertiesForKeys: nil).first)
        #expect(try String(contentsOf: archive.appendingPathComponent("legacy-human-seat.txt"),
                           encoding: .utf8) == "99")
        #expect(model.savedGameAvailability.canResume)
    }

    @Test(arguments: [false, true])
    func recoveryCopyFailurePreventsReplacement(legacyEntryPoint: Bool) throws {
        let fixture = try RecoveryFixture()
        let original = Data("damaged game".utf8)
        let roster = Data("damaged roster".utf8)
        try original.write(to: fixture.gameStore.fileURL)
        fixture.setupStore.restore(roster, forActiveMatch: true)
        // A file in place of the archive directory deterministically refuses
        // backup writes without relying on platform-dependent permissions.
        try Data("not a directory".utf8).write(to: fixture.root.appendingPathComponent("Recovery"))
        let model = fixture.makeModel()

        if legacyEntryPoint {
            model.startNewGame(randomizedBoard: false, randomizeSeat: false)
        } else {
            model.startNewGame(setup: fixture.validSetup)
        }

        #expect(!model.savedGameAvailability.canResume)
        #expect(model.persistenceErrorMessage != nil)
        #expect(try Data(contentsOf: fixture.gameStore.fileURL) == original)
        #expect(fixture.setupStore.data(forActiveMatch: true) == roster)
    }

    @Test func explicitReplacementPreservesTheDamagedSaveAndRoster() throws {
        let fixture = try RecoveryFixture()
        let original = Data("damaged game".utf8)
        let roster = Data("damaged roster".utf8)
        try original.write(to: fixture.gameStore.fileURL)
        fixture.setupStore.restore(roster, forActiveMatch: true)
        let logID = try fixture.logStore.startNewGame(
            initialState: GameSetup.newGame(board: BoardGenerator.standard(), seed: 71),
            roster: .legacy(humanSeat: PlayerID(index: 0)))
        let logFile = try #require(fixture.logStore.logFiles().first)
        let logBytes = try Data(contentsOf: logFile)
        let model = fixture.makeModel()

        model.startNewGame(setup: fixture.validSetup)

        #expect(model.savedGameAvailability.canResume)
        let archives = try FileManager.default.contentsOfDirectory(
            at: fixture.root.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
        #expect(archives.count == 1)
        let archive = try #require(archives.first)
        #expect(try Data(contentsOf: archive.appendingPathComponent("save.json")) == original)
        #expect(try Data(contentsOf: archive.appendingPathComponent("active-match.json")) == roster)
        #expect(try String(contentsOf: archive.appendingPathComponent("active-game-id"), encoding: .utf8)
                == logID.uuidString)
        #expect(try Data(contentsOf: archive.appendingPathComponent("recordings")
            .appendingPathComponent(logFile.lastPathComponent)) == logBytes)
        #expect(FileManager.default.fileExists(atPath: archive.appendingPathComponent("complete.txt").path))
    }

    @Test func anExistingUnreadablePathIsNotAnAbsentSave() throws {
        let fixture = try RecoveryFixture()
        try FileManager.default.createDirectory(at: fixture.gameStore.fileURL, withIntermediateDirectories: true)
        guard case .unreadable = fixture.gameStore.load() else {
            Issue.record("A read failure on an existing path must block recovery, not report no save")
            return
        }
        #expect(!fixture.makeModel().savedGameAvailability.canResume)
    }

    @Test func unreadableRosterCannotSilentlyReplaceHumansWithBots() throws {
        let fixture = try RecoveryFixture()
        let saved = GameSetup.newGame(board: BoardGenerator.standard(), seed: 71)
        try fixture.gameStore.save(saved)
        let damagedRoster = Data("broken roster".utf8)
        fixture.setupStore.restore(damagedRoster, forActiveMatch: true)

        let model = fixture.makeModel()

        #expect(!model.savedGameAvailability.canResume)
        #expect(model.savedGameAvailability.recoveryMessage != nil)
        let move = try #require(RulesEngine.legalMoves(for: model.state, seat: model.humanPlayer).first)
        #expect(throws: (any Error).self) { try model.apply(move) }
        #expect(fixture.setupStore.data(forActiveMatch: true) == damagedRoster)
    }

    @Test func unreadableSaveKeepsItsActiveRecording() throws {
        let fixture = try RecoveryFixture()
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 71)
        let logID = try fixture.logStore.startNewGame(
            initialState: state, roster: .legacy(humanSeat: PlayerID(index: 0)))
        try Data("not a saved game".utf8).write(to: fixture.gameStore.fileURL)

        let model = fixture.makeModel()

        #expect(!model.savedGameAvailability.canResume)
        #expect(try fixture.logStore.activeGameID() == logID)
    }

    @Test func unreadableSaveCannotBeOverwrittenByAPlaceholderMove() throws {
        let fixture = try RecoveryFixture()
        let original = Data("not a saved game".utf8)
        try original.write(to: fixture.gameStore.fileURL)
        let model = fixture.makeModel()
        model.isSettingsSurfaceOpen = true
        let move = try #require(RulesEngine.legalMoves(for: model.state, seat: model.humanPlayer).first)

        #expect(throws: (any Error).self) { try model.apply(move) }
        #expect(try Data(contentsOf: fixture.gameStore.fileURL) == original)
    }
}

/// Owns every persistence location so recovery failures cannot damage a real game.
@MainActor
private final class RecoveryFixture {
    let root: URL
    let defaults: UserDefaults
    let defaultsName: String
    let gameStore: GameStore
    let setupStore: MatchSetupStore
    let civilizationStore: CivilizationAssignmentStore
    let logStore: GameLogStore
    let statsStore: GameStatsStore

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SaveRecovery.\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaultsName = "SaveRecovery.\(UUID())"
        defaults = try #require(UserDefaults(suiteName: defaultsName))
        setupStore = MatchSetupStore()
        setupStore.defaults = defaults
        gameStore = GameStore(fileURL: root.appendingPathComponent("save.json"))
        civilizationStore = CivilizationAssignmentStore(fileURL: root.appendingPathComponent("civs.json"))
        logStore = GameLogStore(directoryURL: root.appendingPathComponent("logs"), maxKeptLogs: 2)
        statsStore = GameStatsStore(fileURL: root.appendingPathComponent("stats.json"))
    }

    deinit {
        // Disposable fixture cleanup must not replace the test's real failure.
        try? FileManager.default.removeItem(at: root)
        UserDefaults.standard.removePersistentDomain(forName: defaultsName)
    }

    func makeModel() -> GameViewModel {
        GameViewModel(gameStore: gameStore, civilizationStore: civilizationStore,
                      matchSetupStore: setupStore, gameLogStore: logStore, gameStatsStore: statsStore)
    }

    var validSetup: MatchSetup {
        MatchSetup(seats: (0..<3).map { index in
            MatchSetup.Seat(index: index, isHuman: index == 0,
                            name: index == 0 ? "Alex" : "",
                            civilization: Civilization.allCases[index])
        }, victoryPointTarget: 8, randomizedBoard: false, randomizeSeatOrder: false)
    }
}
