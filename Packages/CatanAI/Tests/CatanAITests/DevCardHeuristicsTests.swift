import Testing
import CatanEngine
@testable import CatanAI

/// Player 0 is one card short of both a settlement (missing wool) and a
/// city (missing ore) - a Year of Plenty could complete either. Which one
/// `choosePlay` targets should follow the acting personality's own
/// expansion preference (settlement-first for `.aggressive`, city-first for
/// `.cautious`), not always `.balanced`'s.
private func makeAmbiguousYearOfPlentyState() -> GameState {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.players[0].resources = [.brick: 1, .lumber: 1, .grain: 3, .wool: 0, .ore: 2]
    state.players[0].devCards = [.yearOfPlenty]
    return state
}

@Test func choosePlayFollowsAggressivePersonalitysSettlementPriority() {
    let state = makeAmbiguousYearOfPlentyState()
    let move = DevCardHeuristics.choosePlay(state: state, player: PlayerID(index: 0), personality: .aggressive)
    #expect(move.map { "\($0)" } == "\(GameMove.playYearOfPlenty(.wool, .wool))")
}

@Test func choosePlayFollowsCautiousPersonalitysCityPriority() {
    let state = makeAmbiguousYearOfPlentyState()
    let move = DevCardHeuristics.choosePlay(state: state, player: PlayerID(index: 0), personality: .cautious)
    #expect(move.map { "\($0)" } == "\(GameMove.playYearOfPlenty(.ore, .ore))")
}

/// Two opponents hold an equal raw stash (3 each) of two different
/// resources the nearest build target still needs - Monopoly should target
/// whichever resource the *more threatening* of the two holds, not just
/// pick arbitrarily between equal totals.
@Test func monopolyTargetsResourceHeldByTheHigherThreatOpponent() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    // Settlement (the nearest target) is missing both wool and ore.
    state.players[0].resources = [.brick: 1, .lumber: 1, .grain: 1, .wool: 0, .ore: 0]
    state.players[0].devCards = [.monopoly]

    state.players[1].resources = [.wool: 3]
    state.players[2].resources = [.ore: 3]

    // Player 1 is dramatically more threatening than player 2 despite the
    // identical raw resource count.
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[1].settlements.insert(vertex)
    state.players[1].cities.insert(vertex)
    state.players[1].devCards.append(contentsOf: Array(repeating: DevCardType.knight, count: 10))

    let move = DevCardHeuristics.choosePlay(state: state, player: player, personality: .balanced)
    #expect(move.map { "\($0)" } == "\(GameMove.playMonopoly(.wool))")
}
