import Foundation
import Testing
@testable import CatanEngine

@Suite struct TerminalTradeBookkeepingTests {
    enum Restoration: CaseIterable, Sendable { case freshInitialization, replacement }

    private let human = PlayerID(index: 0)
    private let responder = PlayerID(index: 1)
    private let policySeed: UInt64 = 817

    @Test(arguments: Restoration.allCases)
    func terminalOfferDoesNotRequestAnotherDecision(restoration: Restoration) throws {
        let (terminal, offer) = try winningPosition()
        let policy = TerminalRecordingPolicy(offerID: offer.id)
        let policies = botPolicies(in: terminal, policy: policy)
        var session: GameSession
        switch restoration {
        case .freshInitialization:
            session = GameSession(state: terminal, policies: policies, policySeed: policySeed)
        case .replacement:
            session = GameSession(state: newQuickGame(), policies: policies, policySeed: policySeed)
            session.replace(state: terminal)
        }

        #expect(policy.decisionCount == 0)
        #expect(session.policyEvaluationCount == 0)
        #expect(session.policyRNG == RandomSource(seed: policySeed))
        #expect(session.state == terminal, "Restoration must preserve offers and the engine RNG, not normalize the winning state")
        #expect(session.state.pendingTradeOffers == [offer])
        #expect(session.nextActor() == .gameOver(winner: human))
    }

    @Test func aLiveHumanOfferStillQueuesAndAppliesAPolicyResponse() throws {
        let (live, offer) = try liveOfferPosition()
        let policy = TerminalRecordingPolicy(offerID: offer.id)
        var session = GameSession(state: live, policies: botPolicies(in: live, policy: policy), policySeed: policySeed)

        #expect(policy.decisionCount == live.players.count - 1)
        #expect(session.policyEvaluationCount == live.players.count - 1)
        #expect(session.policyRNG != RandomSource(seed: policySeed))
        #expect(session.state == live, "Queuing a live response must not apply it early")
        #expect(session.nextActor() == .seat(responder))
        let chosen = session.decideNext()
        let decision = try #require(chosen)
        #expect(decision.seat == responder)
        #expect(decision.move == .respondToTrade(offerID: offer.id, accept: false))
        _ = try session.commit(seat: decision.seat, move: decision.move)
        #expect(session.state.pendingTradeOffers.isEmpty)
        #expect(session.state.rng == live.rng)
        #expect(session.nextActor() == .awaitingExternalSeat(human))
    }

    private func newQuickGame() -> GameState {
        GameSetup.newGame(board: BoardGenerator.standard(), seed: 92, playerCount: 3, victoryPointTarget: 8)
    }

    /// Both settlements and roads are genuine legal setup moves. The first
    /// turn is entered by rolling (and legally moving the robber if needed),
    /// never by assigning a phase or inventing adjacent buildings.
    private func completedSetup() throws -> GameState {
        var state = newQuickGame()
        let setupMovesPerSeat = 4 // Two settlements and their two roads.
        for _ in 0..<(state.players.count * setupMovesPerSeat) {
            let index = try #require(state.phase.awaitingSeatIndex)
            let actor = state.players[index].id
            let move = try #require(RulesEngine.legalMoves(for: state, seat: actor).first)
            try RulesEngine.apply(move, by: actor, to: &state)
        }
        try #require(state.phase == .rollDice(playerIndex: human.index))
        try RulesEngine.apply(.rollDice, by: human, to: &state)
        if case .movingRobber = state.phase {
            let move = try #require(RulesEngine.legalMoves(for: state, seat: human).first)
            try RulesEngine.apply(move, by: human, to: &state)
        }
        try #require(state.phase == .mainTurn(playerIndex: human.index))
        return state
    }

    /// Earlier history is constructed: move the ACTUAL five VP cards from
    /// the shuffled deck into the human hand and transfer funding from the
    /// bank, representing earlier purchases/production without replaying them.
    /// Cards/resources remain conserved. This is not a full game trajectory.
    /// The final proposal and winning upgrade ARE actual legal engine moves.
    private func liveOfferPosition() throws -> (GameState, TradeOffer) {
        var state = try completedSetup()
        let victoryCards = state.devCardDeck.filter { $0 == .victoryPoint }
        try #require(victoryCards.count == 5)
        state.devCardDeck.removeAll { $0 == .victoryPoint }
        state.players[human.index].devCards.append(contentsOf: victoryCards)
        try moveFromBank([.ore: 3, .grain: 6], to: human, in: &state)
        try moveFromBank([.brick: 1], to: responder, in: &state)
        try #require(state.victoryPoints(for: human) == 7)
        let offer = TradeOffer.enumerated(from: human, give: [.grain: 4], want: [.brick: 1])
        let engineRNG = state.rng
        try RulesEngine.apply(.proposeTrade(offer), by: human, to: &state)
        try #require(state.rng == engineRNG)
        try #require(state.pendingTradeOffers == [offer])
        try requireConservation(state)
        return (state, offer)
    }

    private func winningPosition() throws -> (GameState, TradeOffer) {
        var (state, offer) = try liveOfferPosition()
        let settlement = try #require(state.players[human.index].settlements.sorted().first)
        let move = GameMove.buildCity(settlement)
        try #require(RulesEngine.legalMoves(for: state, seat: human).contains(move))
        let engineRNG = state.rng
        try RulesEngine.apply(move, by: human, to: &state)
        try #require(state.phase == .gameOver(winner: human))
        try #require(state.victoryPoints(for: human) == 8)
        try #require(state.pendingTradeOffers == [offer])
        try #require(Trading.bothSidesCanHonour(offer, responder: responder, state: state))
        try #require(state.rng == engineRNG)
        try requireConservation(state)
        return (state, offer)
    }

    private func moveFromBank(_ amounts: [Resource: Int], to player: PlayerID, in state: inout GameState) throws {
        for resource in Resource.allCases {
            let amount = amounts[resource, default: 0]
            guard amount > 0 else { continue }
            try #require(state.bank[resource, default: 0] >= amount)
            state.bank[resource, default: 0] -= amount
            state.players[player.index].resources[resource, default: 0] += amount
        }
    }

    private func requireConservation(_ state: GameState) throws {
        for resource in Resource.allCases {
            let held = state.players.reduce(0) { $0 + $1.resources[resource, default: 0] }
            try #require(state.bank[resource, default: 0] + held == state.rules.bankPerResource)
        }
        let heldCards = state.players.reduce(0) { $0 + $1.devCards.count }
        try #require(state.devCardDeck.count + heldCards == state.rules.devCardDeckSize)
    }

    private func botPolicies(in state: GameState, policy: TerminalRecordingPolicy) -> [PlayerID: any Policy] {
        Dictionary(uniqueKeysWithValues: state.players.filter { $0.id != human }.map {
            ($0.id, policy as any Policy)
        })
    }
}

/// Policy is a Sendable boundary. The lock protects every mutable access;
/// the responder records illegal terminal calls instead of trapping like Bot.
/// Consuming policy RNG makes accidental resampling observable as well.
private final class TerminalRecordingPolicy: Policy, @unchecked Sendable {
    let id = "terminal-recording"
    private let offerID: UUID
    private let lock = NSLock()
    private var recordedDecisions = 0

    init(offerID: UUID) { self.offerID = offerID }

    var decisionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedDecisions
    }

    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        lock.lock()
        recordedDecisions += 1
        lock.unlock()
        _ = rng.next()
        return .respondToTrade(offerID: offerID, accept: false)
    }
}
