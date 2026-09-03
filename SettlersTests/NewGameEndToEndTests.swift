import Testing
import Foundation
import CatanEngine
@testable import Settlers

/// Does the New Game screen actually produce the game it describes?
///
/// Every other test in this stage checks a piece: `MatchSetup` validates,
/// `GamePhase` reports a seat, the encoding is the right width. None of them
/// check the thing a player cares about - that choosing three seats, two
/// humans and a short game yields a three-seat, two-human, eight-point game.
///
/// These exercise the app entry point with isolated persistence. Native UI
/// tests separately prove that tapping Start reaches that entry point; these
/// tests check the resulting rules and roster rather than just the pixels.

@MainActor
private final class IsolatedStartedMatch {
    let model: GameViewModel
    private let root: URL
    private let defaultsName: String

    init(setup: MatchSetup) {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewGameEndToEndTests.\(UUID().uuidString)")
        defaultsName = "NewGameEndToEndTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        let setupStore = MatchSetupStore()
        setupStore.defaults = defaults
        model = GameViewModel(
            gameStore: GameStore(fileURL: root.appendingPathComponent("save.json")),
            civilizationStore: CivilizationAssignmentStore(fileURL: root.appendingPathComponent("civs.json")),
            matchSetupStore: setupStore,
            gameLogStore: GameLogStore(directoryURL: root.appendingPathComponent("logs"), maxKeptLogs: 2),
            gameStatsStore: GameStatsStore(fileURL: root.appendingPathComponent("stats.json"))
        )
        model.startNewGame(setup: setup)
    }

    deinit {
        // Temporary fixture cleanup must not mask the test's actual failure.
        try? FileManager.default.removeItem(at: root)
        UserDefaults.standard.removePersistentDomain(forName: defaultsName)
    }
}

private func setup(seats: Int, humans: [Int], target: Int,
                   civilizations: [Int: Civilization] = [:]) -> MatchSetup {
    MatchSetup(
        seats: (0..<seats).map { index in
            MatchSetup.Seat(index: index,
                            isHuman: humans.contains(index),
                            name: humans.contains(index) ? "P\(index)" : "",
                            civilization: civilizations[index] ?? Civilization.allCases[index])
        },
        victoryPointTarget: target,
        randomizedBoard: false,
        randomizeSeatOrder: false
    )
}

@Suite struct ConfigurationIsolationTests {
    @MainActor
    @Test func isolatedConfigurationDoesNotChangeTheRealHumanSeatPreference() {
        let defaults = UserDefaults.standard
        let key = "humanSeatIndex"
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        let otherSeat = ((original as? Int ?? 0) + 1) % 3
        let match = IsolatedStartedMatch(setup: setup(seats: 3, humans: [otherSeat], target: 8))
        #expect(match.model.humanPlayer.index == otherSeat)
        #expect(defaults.object(forKey: key) as? Int == original as? Int)
    }
}

@MainActor
@Test func startingAMatchProducesTheTableThatWasConfigured() {
    let match = IsolatedStartedMatch(setup: setup(seats: 3, humans: [0, 1], target: 8))
    let model = match.model

    #expect(model.state.players.count == 3, "three seats were configured")
    #expect(model.humanSeats.count == 2, "two people were configured")
    #expect(model.humanSeats == [PlayerID(index: 0), PlayerID(index: 1)])
    #expect(model.state.victoryPointTarget == 8, "a short game must be short")
}

@MainActor
@Test func everySupportedShapeStarts() {
    // The combinations a player can actually reach through the screen.
    for seats in 3...4 {
        for humanCount in 1...seats {
            for target in MatchSetup.newGameVictoryPointTargets(for: seats) {
                let match = IsolatedStartedMatch(setup: setup(
                    seats: seats,
                    humans: Array(0..<humanCount),
                    target: target
                ))
                let model = match.model
                #expect(model.state.players.count == seats)
                #expect(model.humanSeats.count == humanCount)
                #expect(model.state.victoryPointTarget == target)
                #expect(model.state.phase == .setupForward(playerIndex: 0),
                        "a new game must begin at the first placement")
            }
        }
    }
}

@MainActor
@Test func aSoloGameIsDrivenByBotsAndAFullTableIsNot() {
    // The property that makes seat composition mean anything: seats without a
    // person get a policy, seats with one do not.
    let soloMatch = IsolatedStartedMatch(setup: setup(seats: 4, humans: [0], target: 10))
    let solo = soloMatch.model
    #expect(solo.humanSeats.count == 1)

    let fullMatch = IsolatedStartedMatch(setup: setup(seats: 4, humans: [0, 1, 2, 3], target: 10))
    let full = fullMatch.model
    #expect(full.humanSeats.count == 4)

    // A hot-seat game opens on the handoff cover, and that is deliberate.
    // `seatAtDevice` starts `nil` because nobody has picked the phone up yet -
    // which is also what makes a relaunched hot-seat game correct, since a
    // force-quit leaves nobody holding it either. So the first thing four
    // people see is "Alex, it's your turn", which is the right way to start a
    // game being passed around a table.
    #expect(full.needsHandoff, "a hot-seat game must open by naming whose turn it is")
    #expect(full.seatAtDevice == nil, "nobody has claimed the phone yet")
    #expect(full.seatOwedATurn == PlayerID(index: 0))

    // A solo game must NOT do that - one person holding their own phone should
    // never be asked to pass it to themselves.
    #expect(!solo.needsHandoff)
    #expect(solo.humanPlayer == PlayerID(index: 0))
}

@MainActor
@Test func namesReachTheLabelsPlayersSee() {
    var config = setup(seats: 4, humans: [0, 1], target: 10)
    config.seats[0].name = "Alex"
    config.seats[1].name = "Sam"
    let match = IsolatedStartedMatch(setup: config)
    let model = match.model

    #expect(CatanTheme.playerLabel(for: PlayerID(index: 0)) == "Alex")
    #expect(CatanTheme.playerLabel(for: PlayerID(index: 1)) == "Sam")
    // A bot seat keeps its general's name.
    #expect(!CatanTheme.playerLabel(for: PlayerID(index: 2)).isEmpty)
    #expect(model.humanSeats.count == 2)
}

@MainActor
@Test func chosenCivilizationsAreTheOnesDealt() {
    let wanted: [Int: Civilization] = [0: .norse, 1: .egypt, 2: .japan, 3: .rome]
    let match = IsolatedStartedMatch(
        setup: setup(seats: 4, humans: [0], target: 10, civilizations: wanted))
    _ = match.model
    for (seat, civilization) in wanted {
        #expect(Civilization.forSeat(seat) == civilization,
                "seat \(seat) should be playing \(civilization.displayName)")
    }
}

@MainActor
@Test func aSeatLeftOnRandomStillGetsADistinctCivilization() {
    var config = setup(seats: 4, humans: [0], target: 10)
    config.seats[1].civilization = nil
    config.seats[2].civilization = nil
    let match = IsolatedStartedMatch(setup: config)
    _ = match.model

    let dealt = (0..<4).map { Civilization.forSeat($0) }
    #expect(Set(dealt).count == 4, "the seat colour IS the civilization's colour; duplicates are unreadable")
}

@MainActor
@Test func aShortGameEndsAtItsOwnTarget() {
    // The end-to-end version of the engine's win-condition test: configure a
    // short match through the real entry point, then reach the target.
    let match = IsolatedStartedMatch(setup: setup(seats: 4, humans: [0], target: 8))
    let model = match.model
    var state = model.state
    state.players[0].settlements = Set(state.board.onBoardVertices.sorted().prefix(8))
    WinCondition.checkForWinner(&state)
    guard case .gameOver(let winner) = state.phase else {
        Issue.record("an 8-point game did not end at 8")
        return
    }
    #expect(winner.index == 0)
}

@MainActor
@Test func failedReplacementKeepsTheRunningGameAndItsLogLink() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("FailedReplacement.\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let gameURL = root.appendingPathComponent("save.json")
    let defaults = try #require(UserDefaults(suiteName: "FailedReplacement.\(UUID().uuidString)"))
    let setupStore = MatchSetupStore()
    setupStore.defaults = defaults
    let logStore = GameLogStore(directoryURL: root.appendingPathComponent("logs"), maxKeptLogs: 10)
    let model = GameViewModel(
        gameStore: GameStore(fileURL: gameURL),
        civilizationStore: CivilizationAssignmentStore(fileURL: root.appendingPathComponent("civs.json")),
        matchSetupStore: setupStore,
        gameLogStore: logStore,
        gameStatsStore: GameStatsStore(fileURL: root.appendingPathComponent("stats.json"))
    )
    model.startNewGame(setup: setup(seats: 3, humans: [0], target: 8))
    let firstMove = try #require(RulesEngine.legalMoves(for: model.state, seat: model.humanPlayer).first)
    try model.apply(firstMove)
    let originalPhase = model.state.phase
    let originalLogID = try #require(model.checkpointDocument?.activeMatch?.id)

    try FileManager.default.removeItem(at: model.checkpointStore.fileURL)
    try FileManager.default.createDirectory(at: model.checkpointStore.fileURL, withIntermediateDirectories: false)
    model.startNewGame(setup: setup(seats: 3, humans: [0], target: 8))
    let retainedLogID = model.checkpointDocument?.activeMatch?.id

    #expect(model.persistenceErrorMessage != nil)
    #expect(model.state.phase == originalPhase)
    #expect(retainedLogID == originalLogID)
}
