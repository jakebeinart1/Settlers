import CatanEngine

/// How often a seated policy makes the move a person made, moment by moment.
///
/// ## Why replay, not likelihood
/// `PersonModel.top1Accuracy` scores the linearised person model on the
/// fitter's own candidate list. A seated ghost decides differently: Expert's
/// options, the cascade's offers, a roll it may never have skipped. So this
/// pauses each recorded game at every choice the person made, hands the exact
/// state to the policy the app would seat, and compares answers. A policy is
/// deterministic at a given state, so agreeing here is agreeing every time.
public enum GhostFidelity {

    /// The pivotal moments, named by the state the person faced, never by what
    /// they did: tagging by the answer would grade the policy on easy cases only.
    public enum Situation: String, CaseIterable, Sendable, Codable {
        case openingSettlement, openingRoad
        /// A knight is playable before the dice.
        case knightBeforeRoll
        /// Main turn, a settlement, city or dev card is affordable.
        case canBuy
        /// Main turn, a knight is playable.
        case knightInHand
        /// Main turn, nothing but roads, trades or ending.
        case turnOther
        case robber, discard, tradeResponse
    }

    public struct Moment: Sendable, Encodable {
        public let game: String
        public let seat: PlayerID
        /// What the person faced, kept so a miss can be studied (`ghost fidelity --dump`).
        public let state: GameState
        public let situations: [Situation]
        public let person: GameMove
        public let policy: GameMove

        public var exact: Bool { GhostFidelity.matches(policy, person) }
        public var sameKind: Bool { GhostFidelity.kind(person) == GhostFidelity.kind(policy) }
    }

    /// The seat sees what `GameSession` shows a bot: enumerated offers, none
    /// after three refusals. A person's free-form offer is then a disagreement,
    /// which it is: the ghost could not have typed it.
    public static func moments(in game: LoggedGame, policy: any LedgerAwarePolicy) throws -> [Moment] {
        var rng = RandomSource(seed: 0)
        var result: [Moment] = []
        try forEachDecision(in: game) { observation, ledger, move in
            result.append(Moment(game: game.id, seat: observation.seat, state: observation.state,
                                 situations: situations(observation.state, legal: observation.legalMoves),
                                 person: move, policy: policy.decide(observation, ledger: ledger, rng: &rng)))
        }
        return result
    }

    /// Every real choice the person made: what they saw, as a bot seat sees
    /// it, and what they did.
    public static func forEachDecision(
        in game: LoggedGame, _ body: (GameObservation, PublicLedger, GameMove) throws -> Void
    ) throws {
        var session = GameSession(state: game.initialState, policies: [:], policySeed: 0)
        for event in game.events {
            if event.isHumanDecision, game.humanSeats.contains(event.player) {
                let legal = DecisionExtractor.options(for: event, in: session.state, humanTrading: false)
                if legal.count > 1 {
                    try body(GameObservation(seat: event.player, state: session.state, legalMoves: legal),
                             session.ledger(for: event.player), event.move)
                }
            }
            _ = try session.applyExternal(event.move, by: event.player)
        }
    }

    public static func situations(_ state: GameState, legal: [GameMove]) -> [Situation] {
        func any(_ test: (GameMove) -> Bool) -> Bool { legal.contains(where: test) }
        switch state.phase {
        case .setupForward, .setupBackward:
            return [any { if case .placeInitialSettlement = $0 { true } else { false } } ? .openingSettlement : .openingRoad]
        case .rollDice: return [.knightBeforeRoll]
        case .discarding: return [.discard]
        case .movingRobber: return [.robber]
        default: break
        }
        if legal.allSatisfy({ if case .respondToTrade = $0 { true } else { false } }) { return [.tradeResponse] }
        var tags: [Situation] = []
        if any(buys) { tags.append(.canBuy) }
        if any({ if case .playKnight = $0 { true } else { false } }) { tags.append(.knightInHand) }
        return tags.isEmpty ? [.turnOther] : tags
    }

    /// The same decision: the same move, or the first swap of a bank trade the
    /// person made several swaps at once in (the app takes "six wool for a
    /// grain and two ore" as one move; a bot seat makes it one swap at a time).
    public static func matches(_ move: GameMove, _ person: GameMove) -> Bool {
        if DecisionExtractor.same(move, person) { return true }
        guard case .bankTrade(let give, let get) = move, case .bankTrade(let allGive, let allGet) = person else { return false }
        return give.allSatisfy { allGive[$0.key, default: 0] >= $0.value } && get.allSatisfy { allGet[$0.key, default: 0] >= $0.value }
    }

    static func buys(_ move: GameMove) -> Bool {
        switch move {
        case .buildSettlement, .buildCity, .buyDevCard: true
        default: false
        }
    }

    /// What sort of move: the case name, except that a robber move is its hex
    /// (the choice that matters) and a trade reply is its answer.
    public static func kind(_ move: GameMove) -> String {
        switch move {
        case .moveRobber(let hex, _): return "robber \(hex.q),\(hex.r)"
        case .respondToTrade(_, let accept): return accept ? "accept" : "reject"
        default: return String(String(describing: move).prefix { $0 != "(" })
        }
    }
}
