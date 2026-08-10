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
