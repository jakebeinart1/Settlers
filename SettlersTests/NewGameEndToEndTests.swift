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
/// This is the gap the screenshots could not close. There is no touch
/// injection on this machine, so every screen state was reached by a launch
/// flag; "pressing Start starts the match you configured" was verified by
/// reading the code, which is exactly the kind of claim that turns out to be
/// wrong. These drive the real entry point instead.

/// Starts a real game, with the developer's own saved game and match setup put
/// back afterwards.
///
/// `startNewGame` writes through `GameStore`, `MatchSetupStore` and
/// `HumanSeatStore`, all of which resolve the SIMULATOR'S REAL APP CONTAINER -
/// and `gate.sh` runs this suite on every push. Without this, a routine gate
/// run silently destroyed whatever game was in progress on that simulator,
/// twenty-nine times per run. `PersistenceTests` carries the same guard and the
/// same note: making the stores' directory injectable is the real fix, and it
/// is a change to all seven stores.
@MainActor
private func started(_ setup: MatchSetup) -> GameViewModel {
    let container = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let save = container.appendingPathComponent("catan_save.json")
    let savedGame = try? Data(contentsOf: save)
    let savedSetup = UserDefaults.standard.data(forKey: "matchSetup")
    let savedSeat = UserDefaults.standard.object(forKey: "humanSeat")
    defer {
        if let savedGame { try? savedGame.write(to: save) } else { try? FileManager.default.removeItem(at: save) }
        if let savedSetup {
            UserDefaults.standard.set(savedSetup, forKey: "matchSetup")
        } else {
            UserDefaults.standard.removeObject(forKey: "matchSetup")
        }
        if let savedSeat {
            UserDefaults.standard.set(savedSeat, forKey: "humanSeat")
        } else {
            UserDefaults.standard.removeObject(forKey: "humanSeat")
        }
    }
    let model = GameViewModel()
    model.startNewGame(setup: setup)
    return model
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

@MainActor
@Test func startingAMatchProducesTheTableThatWasConfigured() {
    let model = started(setup(seats: 3, humans: [0, 1], target: 8))

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
            for target in [8, 10, 12] {
                let model = started(setup(seats: seats,
                                          humans: Array(0..<humanCount),
                                          target: target))
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
    let solo = started(setup(seats: 4, humans: [0], target: 10))
    #expect(solo.humanSeats.count == 1)

    let full = started(setup(seats: 4, humans: [0, 1, 2, 3], target: 10))
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
    let model = started(config)

    #expect(CatanTheme.playerLabel(for: PlayerID(index: 0)) == "Alex")
    #expect(CatanTheme.playerLabel(for: PlayerID(index: 1)) == "Sam")
    // A bot seat keeps its general's name.
    #expect(!CatanTheme.playerLabel(for: PlayerID(index: 2)).isEmpty)
    #expect(model.humanSeats.count == 2)
}

@MainActor
@Test func chosenCivilizationsAreTheOnesDealt() {
    let wanted: [Int: Civilization] = [0: .norse, 1: .egypt, 2: .japan, 3: .rome]
    _ = started(setup(seats: 4, humans: [0], target: 10, civilizations: wanted))
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
    _ = started(config)

    let dealt = (0..<4).map { Civilization.forSeat($0) }
    #expect(Set(dealt).count == 4, "the seat colour IS the civilization's colour; duplicates are unreadable")
}

@MainActor
@Test func aShortGameEndsAtItsOwnTarget() {
    // The end-to-end version of the engine's win-condition test: configure a
    // short match through the real entry point, then reach the target.
    let model = started(setup(seats: 4, humans: [0], target: 8))
    var state = model.state
    state.players[0].settlements = Set(state.board.onBoardVertices.sorted().prefix(8))
    WinCondition.checkForWinner(&state)
    guard case .gameOver(let winner) = state.phase else {
        Issue.record("an 8-point game did not end at 8")
        return
    }
    #expect(winner.index == 0)
}
