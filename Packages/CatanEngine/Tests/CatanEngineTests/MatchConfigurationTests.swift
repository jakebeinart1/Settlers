import Testing
import Foundation
@testable import CatanEngine

// Covers the two things a match can now be configured with: how many seats
// are at the table, and how many victory points win it.
//
// Both are engine-level because both change what the rules do. The victory
// target in particular sits in `GameState` rather than in a preference, so a
// game started at eight still ends at eight after being saved, relaunched and
// resumed - a global would make `checkForWinner` depend on process state
// rather than on the position.

// MARK: - Table size

@Test func aThreeSeatGameHasThreeSeats() {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1, playerCount: 3)
    #expect(state.players.count == 3)
    #expect(state.players.map(\.id.index) == [0, 1, 2])
}

@Test func aThreeSeatGameCompletesSetupAcrossExactlyThreeSeats() throws {
    // The snake through setup is where the table size actually bites: it used
    // to hand the last placement to seat 3 unconditionally, so a three-player
    // game addressed a chair that does not exist and crashed on the next
    // `state.players[playerIndex]`.
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1, playerCount: 3)
    var driver = RandomSource(seed: 11)
    var seatsSeen: Set<Int> = []

    for _ in 0..<200 {
        guard case .setupForward(let index) = state.phase else {
            if case .setupBackward(let index) = state.phase { seatsSeen.insert(index) } else { break }
            guard let actor = actingPlayer(state),
                  let move = RulesEngine.legalMoves(for: state, seat: actor).randomElement(using: &driver)
            else { break }
            try RulesEngine.apply(move, by: actor, to: &state)
            continue
        }
        seatsSeen.insert(index)
        guard let actor = actingPlayer(state),
              let move = RulesEngine.legalMoves(for: state, seat: actor).randomElement(using: &driver)
        else { break }
        try RulesEngine.apply(move, by: actor, to: &state)
    }

    #expect(seatsSeen == [0, 1, 2], "setup must visit exactly the seats that exist, saw \(seatsSeen.sorted())")
    guard case .rollDice = state.phase else {
        Issue.record("setup did not complete; phase is \(state.phase)")
        return
    }
    for player in state.players {
        #expect(player.settlements.count == 2, "seat \(player.id.index) should hold two opening settlements")
        #expect(player.roads.count == 2, "seat \(player.id.index) should hold two opening roads")
    }
}

@Test func aThreeSeatGameCyclesTurnsAmongThreeSeats() throws {
    // Turn advancement is `(playerIndex + 1) % state.players.count`, so it
    // already respects the table - this pins that it stays that way.
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 2, playerCount: 3)
    var driver = RandomSource(seed: 22)
    var turnSeats: [Int] = []

    for _ in 0..<600 {
        if case .gameOver = state.phase { break }
        if case .mainTurn(let index) = state.phase, turnSeats.last != index { turnSeats.append(index) }
        guard let actor = actingPlayer(state),
              let move = RulesEngine.legalMoves(for: state, seat: actor).randomElement(using: &driver)
        else { break }
        try RulesEngine.apply(move, by: actor, to: &state)
    }

    #expect(turnSeats.count >= 6, "expected several turns, saw \(turnSeats.count)")
    #expect(Set(turnSeats) == [0, 1, 2], "every seat and only real seats must take turns")
    for (previous, next) in zip(turnSeats, turnSeats.dropFirst()) {
        #expect(next == (previous + 1) % 3, "turn order broke: \(previous) -> \(next)")
    }
}

@Test func anUnsupportedTableSizeIsRefusedAtConstruction() {
    // Two players is not a game this board is balanced for, and five has no
    // fifth set of pieces. Better to refuse than to produce a game that
    // half-works.
    #expect(!GameSetup.supportedPlayerCounts.contains(2))
    #expect(!GameSetup.supportedPlayerCounts.contains(5))
    #expect(GameSetup.supportedPlayerCounts.contains(3))
    #expect(GameSetup.supportedPlayerCounts.contains(4))
}

// MARK: - Victory target

@Test func theGameEndsAtItsOwnTarget() throws {
    for target in [8, 10, 12] {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4,
                                      victoryPointTarget: target)
        state.phase = .mainTurn(playerIndex: 0)
        // Give seat 0 exactly one point short, then the point that wins it.
        state.players[0].settlements = Set(state.board.onBoardVertices.sorted().prefix(target - 1))
        WinCondition.checkForWinner(&state)
        if case .gameOver = state.phase {
            Issue.record("target \(target): ended one point early")
        }

        state.players[0].settlements.insert(state.board.onBoardVertices.sorted()[target - 1])
        WinCondition.checkForWinner(&state)
        guard case .gameOver(let winner) = state.phase else {
            Issue.record("target \(target): did not end at the target")
            continue
        }
        #expect(winner.index == 0)
    }
}

@Test func aTwelvePointGameDoesNotEndAtTen() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 5, victoryPointTarget: 12)
    state.players[0].settlements = Set(state.board.onBoardVertices.sorted().prefix(10))
    WinCondition.checkForWinner(&state)
    if case .gameOver = state.phase {
        Issue.record("a 12-point game ended at 10 - the target is being ignored")
    }
}

@Test func anUnsupportedTargetIsRefused() {
    let targets = Ruleset.forMode(.classic).victoryPointTargets
    #expect(!targets.contains(7))
    #expect(!targets.contains(13))
    for target in [8, 10, 12] { #expect(targets.contains(target)) }
}

// MARK: - Saves written before either setting existed

@Test func aSaveWithoutATargetLoadsAndPlaysToTen() throws {
    // The failure this guards is not hypothetical: adding one non-optional
    // field to `GameState` once deleted every player's in-progress game,
    // because `GameStore.load()` swallows the decode error with `try?` and the
    // app silently starts a new one.
    let fresh = GameSetup.newGame(board: BoardGenerator.standard(), seed: 6)
    var json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(fresh)) as! [String: Any]
    json.removeValue(forKey: "victoryPointTarget")
    json["schemaVersion"] = 1

    let data = try JSONSerialization.data(withJSONObject: json)
    let restored = try JSONDecoder().decode(GameState.self, from: data)

    #expect(restored.victoryPointTarget == Ruleset.forMode(.classic).defaultVictoryPointTarget,
            "a v1 save must play to the target it was started under")
    #expect(restored.players.count == fresh.players.count)
}

@Test func aTargetSurvivesASaveAndReload() throws {
    let original = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7, victoryPointTarget: 8)
    let restored = try JSONDecoder().decode(GameState.self, from: try JSONEncoder().encode(original))
    #expect(restored.victoryPointTarget == 8, "a short game resumed must not revert to ten")
}

@Test func aSaveWithAnInvalidTargetIsRejectedAsCorrupt() throws {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 5)
    var json = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(state)
    ) as! [String: Any]
    json["victoryPointTarget"] = 0
    let corrupted = try JSONSerialization.data(withJSONObject: json)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(GameState.self, from: corrupted)
    }
}

@Test func aThreeSeatGameSurvivesASaveAndReload() throws {
    let original = GameSetup.newGame(board: BoardGenerator.standard(), seed: 8, playerCount: 3)
    let restored = try JSONDecoder().decode(GameState.self, from: try JSONEncoder().encode(original))
    #expect(restored.players.count == 3)
}
