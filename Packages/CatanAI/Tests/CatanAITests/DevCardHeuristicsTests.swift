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

/// Regression test for bot feedback: with a real shot at Largest Army (two
/// knights already played, one more in hand - enough to reach 3, and
/// nobody's ahead of us), the bot must actually play the knight rather than
/// only ever doing so reactively when the robber happens to sit on its own
/// tile. Largest Army has to be *pursued* to ever be held, not stumbled
/// into.
@Test func choosePlayPursuesLargestArmyWithARealShotEvenWithoutRobberOnOwnTile() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    state.players[0].playedKnights = 1
    state.players[0].devCards = [.knight, .knight]
    // Robber is nowhere near player 0's holdings - the only reason to play
    // here is the army race itself.
    state.players[0].settlements = []
    state.players[0].cities = []

    let move = DevCardHeuristics.choosePlay(state: state, player: player, personality: .balanced)
    guard case .playKnight = move else {
        Issue.record("expected a knight play, got \(String(describing: move))")
        return
    }
}

/// A bot with no realistic path to 3 knights (only one ever obtainable)
/// shouldn't burn its one dev-card play chasing a bonus it can't reach.
@Test func choosePlayDoesNotPursueLargestArmyWithoutARealShot() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    state.players[0].playedKnights = 0
    state.players[0].devCards = [.knight] // ceiling of 1 - can never reach 3
    state.players[0].settlements = []
    state.players[0].cities = []

    let move = DevCardHeuristics.choosePlay(state: state, player: player, personality: .balanced)
    #expect(move == nil)
}

/// Once a rival already holds Largest Army with a commanding lead our
/// current hand can't plausibly overtake, and the deck still has plenty of
/// cards left (no endgame urgency), there's no rush to burn the knight now -
/// holding it a bit longer costs nothing and keeps options open.
@Test func choosePlayDoesNotRushLargestArmyAgainstAFarAheadHolderMidGame() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let holder = PlayerID(index: 1)
    state.players[0].playedKnights = 1
    state.players[0].devCards = [.knight, .knight] // ceiling 3, ties the holder at best
    state.players[1].playedKnights = 4
    state.largestArmyPlayer = holder
    state.players[0].settlements = []
    state.players[0].cities = []
    // Plenty of deck left - no last-call pressure.
    #expect(state.devCardDeck.count > 5)

    let move = DevCardHeuristics.choosePlay(state: state, player: player, personality: .balanced)
    #expect(move == nil)
}
