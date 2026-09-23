import Testing
import CatanEngine
@testable import CatanAI

private func conquestMainTurn(seed: UInt64 = 1) -> GameState {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: seed, variant: .conquest)
    // Finish setup the way bots would, so buildings exist.
    var session = GameSession(state: state, policies: Dictionary(uniqueKeysWithValues:
        state.players.map { ($0.id, HeuristicPolicy(personality: .balanced, id: "balanced") as any Policy) }), policySeed: seed)
    while case .setupForward = session.state.phase { _ = try? session.step() }
    while case .setupBackward = session.state.phase { _ = try? session.step() }
    state = session.state
    state.phase = .mainTurn(playerIndex: 0)
    return state
}

@Test func aBotTakesAHexWhenItHoldsEnoughToWinIt() {
    var state = conquestMainTurn()
    state.armyHands[state.players[0].id] = [9]
    let legal = RulesEngine.legalMoves(for: state)
    let move = ConquestHeuristics.chooseDeploy(state: state, player: state.players[0].id, legal: legal)
    guard case .deployArmy(let hex, let strengths)? = move else {
        Issue.record("expected a deploy, got \(String(describing: move))"); return
    }
    let after = Conquest.outcome(of: strengths.reduce(0, +), against: state.garrisons[hex], by: state.players[0].id)
    #expect(after?.owner == state.players[0].id)
}

@Test func aBotDoesNotThrowCardsAtAHexItCannotTake() {
    var state = conquestMainTurn()
    state.armyHands[state.players[0].id] = [1]
    for (hex, _) in state.garrisons { state.garrisons[hex] = Garrison(owner: nil, strength: 5) }
    let legal = RulesEngine.legalMoves(for: state)
    #expect(ConquestHeuristics.chooseDeploy(state: state, player: state.players[0].id, legal: legal) == nil)
}

@Test func aStandardGameNeverAsksForArmyMoves() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    state.phase = .mainTurn(playerIndex: 0)
    #expect(!ConquestHeuristics.shouldBuyArmyCard(state: state, player: state.players[0].id))
}

@Test func seededConquestGamesFinishWithOnlyLegalMoves() throws {
    for seed: UInt64 in 1...3 {
        let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed, variant: .conquest)
        var session = GameSession(state: state, policies: Dictionary(uniqueKeysWithValues:
            state.players.map { ($0.id, HeuristicPolicy(personality: .balanced, id: "balanced") as any Policy) }), policySeed: seed)
        var armyMoves = 0
        for _ in 0..<6_000 {
            guard let step = try session.step() else { break }
            if case .deployArmy = step.move { armyMoves += 1 }
        }
        #expect({ if case .gameOver = session.state.phase { true } else { false } }(), "seed \(seed) did not finish")
        #expect(armyMoves > 0, "seed \(seed): bots never deployed")
    }
}
