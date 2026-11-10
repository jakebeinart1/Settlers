import CatanAI
import CatanEngine
import Foundation

enum OnlineGameplayError: Error, Sendable, Equatable {
    case invalidConfiguration
    case invalidCheckpoint
    case notActing
    case illegalMove
    case bankStockUnavailable
    case unexpectedBot
}

/// The authoritative engine and policy checkpoint. This value is persisted
/// on the service only. Clients receive a separate, viewer-scoped projection.
struct OnlineGameplay: Codable, Sendable {
    private static let maximumDirectedOffersPerTurn = 3

    private var session: GameSession
    private var roles: [OnlineSeatRole]
    private(set) var turnGeneration = 0

    var winner: PlayerID? {
        if case .gameOver(let winner) = session.state.phase { return winner }
        return nil
    }

    var actors: [PlayerID] {
        if let recipient = directedOffer?.recipient { return [recipient] }
        if case .discarding(let pending) = session.state.phase { return pending.sorted() }
        return session.state.phase.awaitingSeatIndex.map { [PlayerID(index: $0)] } ?? []
    }

    var turnOwner: PlayerID? {
        let state = session.state
        let index: Int?
        switch state.phase {
        case .discarding: index = state.robberMoverIndex
        case .choosingResource: index = state.naval?.productionRollerIndex
        default: index = state.phase.awaitingSeatIndex
        }
        return index.map { PlayerID(index: $0) }
    }

    var deadlineKind: OnlineDeadlineKind {
        if directedOffer != nil { return .trade }
        switch session.state.phase {
        case .setupForward, .setupBackward: return .setup
        case .discarding, .movingRobber, .choosingResource, .capturingShip: return .response
        case .rollDice, .mainTurn, .gameOver: return .turn
        }
    }

    var actionScope: String {
        if let offer = directedOffer { return "trade-\(offer.id)" }
        switch session.state.phase {
        case .setupForward, .setupBackward:
            let moves = RulesEngine.legalMoves(for: session.state)
            if case .placeInitialRoad? = moves.first { return "road" }
            return "settlement"
        case .rollDice, .mainTurn: return "turn"
        case .discarding: return "discard"
        case .movingRobber: return "robber"
        case .choosingResource: return "harvest"
        case .capturingShip: return "capture"
        case .gameOver: return "finished"
        }
    }

    var acceptsIndependentResponses: Bool {
        if case .discarding = session.state.phase { return true }
        return false
    }

    private var directedOffer: TradeOffer? {
        guard case .mainTurn = session.state.phase else { return nil }
        return session.state.pendingTradeOffers.first { $0.recipient != nil }
    }

    init(configuration: OnlineConfiguration, seats: [OnlineSeat]) throws {
        let roles = seats.map(\.role)
        guard GameSetup.supportedPlayerCounts.contains(roles.count),
              roles.filter({ $0 == .human }).count >= 2, !roles.contains(.open),
              GameMode.newGameChoices.contains(configuration.mode),
              configuration.mode != .naval || configuration.rules == .standard else {
            throw OnlineGameplayError.invalidConfiguration
        }
        let state = Self.newState(configuration: configuration, seats: roles.count)
        self.roles = roles
        session = GameSession(state: state, policies: Self.policies(for: roles, mode: state.mode),
                              policySeed: Self.privateSeed())
    }

    private static func newState(configuration: OnlineConfiguration, seats: Int) -> GameState {
        let mode = configuration.mode
        if mode == .naval { return Naval.newGame(seed: privateSeed(), playerCount: seats) }
        let board = BoardGenerator.randomized(seed: privateSeed(), shape: Ruleset.forMode(mode).board)
        return GameSetup.newGame(board: board, seed: privateSeed(), playerCount: seats,
                                 mode: mode, variant: configuration.rules)
    }

    private struct Storage: Codable {
        static let currentVersion = 1

        let version: Int
        let rulesVersion: Int
        let roles: [OnlineSeatRole]
        let turnGeneration: Int
        let checkpoint: GameSession.Checkpoint
    }

    init(from decoder: any Decoder) throws {
        let saved = try Storage(from: decoder)
        guard saved.version == Storage.currentVersion, saved.rulesVersion == RulesEngine.currentRulesVersion,
              saved.turnGeneration >= 0, saved.turnGeneration < Int.max,
              saved.roles.count == saved.checkpoint.state.players.count, !saved.roles.contains(.open) else {
            throw OnlineGameplayError.invalidCheckpoint
        }
        roles = saved.roles
        turnGeneration = saved.turnGeneration
        session = try GameSession(checkpoint: saved.checkpoint,
                                  policies: Self.policies(for: roles, mode: saved.checkpoint.state.mode))
    }

    func encode(to encoder: any Encoder) throws {
        try Storage(version: Storage.currentVersion, rulesVersion: RulesEngine.currentRulesVersion,
                    roles: roles, turnGeneration: turnGeneration, checkpoint: session.checkpoint).encode(to: encoder)
    }

    func view(for seat: PlayerID) -> OnlineGameplayView {
        let state = session.state
        let discardCount = discardPlayer(seat).map(Robber.discardCount)
        return OnlineGameplayView(state: state, viewer: seat, turnOwner: turnOwner,
                                  legalMoves: projectedMoves(for: seat, discarding: discardCount != nil),
                                  discardCount: discardCount, tradeOffer: visibleTrade(for: seat),
                                  canProposeTrade: canProposeTrade(by: seat))
    }

    private func projectedMoves(for seat: PlayerID, discarding: Bool) -> [GameMove] {
        guard actors.contains(seat), !discarding else { return [] }
        return RulesEngine.legalMoves(for: session.state, seat: seat).filter { move in
            if case .proposeTrade = move { return false }
            return true
        }
    }

    private func visibleTrade(for seat: PlayerID) -> TradeOffer? {
        guard let offer = directedOffer, offer.from == seat || offer.recipient == seat else { return nil }
        return offer
    }

    mutating func apply(_ move: GameMove, by seat: PlayerID) throws {
        guard actors.contains(seat), roles[seat.index] == .human else { throw OnlineGameplayError.notActing }
        try validate(move, by: seat)
        try commit(move, by: seat)
    }

    /// Codable move payloads can carry arbitrary integers and coordinates.
    /// Validate custom drafts before engine arithmetic. Fixed moves must
    /// match a generated move, which also rejects forged board identifiers.
    private func validate(_ move: GameMove, by seat: PlayerID) throws {
        let state = session.state
        let limit = state.rules.bankPerResource
        let valid: Bool
        switch move {
        case .discard(let amounts):
            valid = acceptsIndependentResponses && Self.validAmounts(amounts, limit: limit)
        case .proposeTrade(let offer):
            valid = canProposeTrade(by: seat) && validTrade(offer, by: seat, limit: limit)
        case .buyArmyCard(let amounts):
            valid = state.phase.isMainTurn(of: seat.index) && Self.validAmounts(amounts, limit: limit)
        case .bankTrade(let give, let get):
            valid = state.phase.isMainTurn(of: seat.index) && Self.validAmounts(give, limit: limit)
                && Self.validAmounts(get, limit: limit)
        case .deployArmy(let tile, let cards):
            valid = state.phase.isMainTurn(of: seat.index) && Conquest.canDeploy(to: tile, by: seat, in: state)
                && !cards.isEmpty && cards.count <= state.armyHands[seat, default: []].count
        default:
            valid = !acceptsIndependentResponses && projectedMoves(for: seat, discarding: false).contains(move)
        }
        guard valid else { throw OnlineGameplayError.illegalMove }
    }

    private static func validAmounts(_ amounts: [Resource: Int], limit: Int) -> Bool {
        !amounts.isEmpty && amounts.values.allSatisfy { (1...limit).contains($0) }
    }

    private func canProposeTrade(by seat: PlayerID) -> Bool {
        let state = session.state
        guard state.phase.isMainTurn(of: seat.index), directedOffer == nil else { return false }
        let offersMade = state.tradesAcceptedThisTurn[seat, default: 0]
            + state.declinedTradeOffersThisTurn[seat, default: []].count
        return offersMade < Self.maximumDirectedOffersPerTurn
            && state.players[seat.index].resources.values.contains { $0 > 0 }
    }

    private func validTrade(_ offer: TradeOffer, by seat: PlayerID, limit: Int) -> Bool {
        guard offer.from == seat, let recipient = offer.recipient,
              roles.indices.contains(recipient.index), offer.canRespond(recipient),
              Set(offer.give.keys).isDisjoint(with: offer.want.keys) else { return false }
        return Self.validAmounts(offer.give, limit: limit) && Self.validAmounts(offer.want, limit: limit)
    }

    mutating func advanceBot(for seat: PlayerID) throws {
        guard session.nextActor() == .seat(seat) else { throw OnlineGameplayError.unexpectedBot }
        if let offer = directedOffer, !session.hasQueuedTradeResponse(for: seat) {
            // A former human may have resigned while deciding a trade after
            // the action backstop would preclude a normal bot turn.
            try commit(botTradeResponse(to: offer, by: seat), by: seat)
            return
        }
        if let player = discardPlayer(seat) {
            try commit(Self.discardMove(for: player), by: seat)
            return
        }
        var candidate = session
        candidate.reseedGameplayRandomness(Self.privateSeed())
        guard let step = try candidate.step(), step.actor == seat else { throw OnlineGameplayError.unexpectedBot }
        publish(candidate, after: step.move)
    }

    mutating func replaceWithBot(_ seat: PlayerID) throws {
        guard roles.indices.contains(seat.index), roles[seat.index] == .human else {
            throw OnlineGameplayError.unexpectedBot
        }
        roles[seat.index] = .classicAI
        session.installPolicy(Self.policy(for: .classicAI, mode: session.state.mode), for: seat)
    }

    /// Expiring an actor's deadline never picks a random target or starts a
    /// voluntary action. Setup and rule-required responses get stable legal
    /// choices. A directed trade expires as a rejection.
    mutating func resolveTimeout(for seat: PlayerID) throws {
        guard actors.contains(seat) else { throw OnlineGameplayError.notActing }
        try commit(timeoutMove(for: seat), by: seat)
    }

    private func timeoutMove(for seat: PlayerID) throws -> GameMove {
        if let offer = directedOffer { return .respondToTrade(offerID: offer.id, accept: false) }
        if let player = discardPlayer(seat) { return Self.discardMove(for: player) }
        switch session.state.phase {
        case .rollDice: return .rollDice
        case .mainTurn: return .endTurn
        case .capturingShip: return .skipShipCapture
        default:
            guard let first = RulesEngine.legalMoves(for: session.state, seat: seat).first else {
                throw OnlineGameplayError.illegalMove
            }
            return first
        }
    }

    private func discardPlayer(_ seat: PlayerID) -> Player? {
        guard case .discarding(let pending) = session.state.phase, pending.contains(seat) else { return nil }
        return session.state.players[seat.index]
    }

    private static func discardMove(for player: Player) -> GameMove {
        var remaining = Robber.discardCount(for: player)
        var amounts: [Resource: Int] = [:]
        for resource in Resource.allCases where remaining > 0 {
            let amount = min(remaining, player.resources[resource, default: 0])
            if amount > 0 { amounts[resource] = amount }
            remaining -= amount
        }
        return .discard(amounts)
    }

    private mutating func commit(_ move: GameMove, by seat: PlayerID) throws {
        var candidate = session
        candidate.reseedGameplayRandomness(Self.privateSeed())
        do {
            try candidate.applyExternal(move, by: seat)
        } catch MoveError.bankCannotSupply {
            throw OnlineGameplayError.bankStockUnavailable
        } catch is MoveError {
            throw OnlineGameplayError.illegalMove
        }
        publish(candidate, after: move)
    }

    private mutating func publish(_ candidate: GameSession, after move: GameMove) {
        session = candidate
        switch move {
        case .placeInitialRoad, .endTurn: turnGeneration += 1
        default: break
        }
    }

    private static func privateSeed() -> UInt64 {
        var generator = SystemRandomNumberGenerator()
        return generator.next()
    }
}

private extension OnlineGameplay {
    static func policies(for roles: [OnlineSeatRole], mode: GameMode) -> [PlayerID: any Policy] {
        var result: [PlayerID: any Policy] = [:]
        for (index, role) in roles.enumerated() where role.isBot {
            result[PlayerID(index: index)] = policy(for: role, mode: mode)
        }
        return result
    }

    static func policy(for role: OnlineSeatRole, mode: GameMode) -> any Policy {
        let base: any Policy
        if mode == .naval {
            base = NavalPolicy(tier: role == .expertAI ? .expert : .traditional, revision: .scoutingV2)
        } else if role == .expertAI {
            base = EvaluationPolicy(revision: .openingOreGrainV1)
        } else {
            base = HeuristicPolicy(personality: .balanced, id: "online-classic-v1")
        }
        return OnlineBotPolicy(base: base)
    }

    func botTradeResponse(to offer: TradeOffer, by seat: PlayerID) -> GameMove {
        let state = session.state
        let legal = RulesEngine.legalMoves(for: state, seat: seat)
        let decline = GameMove.respondToTrade(offerID: offer.id, accept: false)
        guard let policy = session.policies[seat] as? OnlineBotPolicy, legal.contains(decline) else {
            return decline
        }
        let view = GameObservation(seat: seat, state: state, legalMoves: legal)
        var rng = RandomSource(seed: Self.privateSeed())
        return policy.decide(view, ledger: session.ledger(for: seat), rng: &rng)
    }
}

/// Online offers have exactly one named responder. Existing bots can still
/// answer one, and can bank trade, but do not broadcast their solo offers.
private struct OnlineBotPolicy: LedgerAwarePolicy {
    let base: any Policy

    var id: String { "online-directed-v1-\(base.id)" }

    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        decide(observation, ledger: PublicLedger.fromPositionAlone(observation.state, observer: observation.seat),
               rng: &rng)
    }

    func decide(_ observation: GameObservation, ledger: PublicLedger, rng: inout RandomSource) -> GameMove {
        let legal = observation.legalMoves.filter {
            if case .proposeTrade = $0 { return false }
            return true
        }
        let scoped = observation.replacingLegalMoves(legal)
        if let policy = base as? any LedgerAwarePolicy {
            return policy.decide(scoped, ledger: ledger, rng: &rng)
        }
        return base.decide(scoped, rng: &rng)
    }
}
