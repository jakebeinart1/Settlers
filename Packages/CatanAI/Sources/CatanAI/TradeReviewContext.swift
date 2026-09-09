import CatanEngine
import Foundation

/// Offline evidence, never consulted by a policy. Applies acceptance to a copy
/// using the native rules and describes both sides of the atomic exchange.
/// Future-turn opportunities freeze the current board: they are NOT forecasts.
public struct TradeReviewContext: Codable, Sendable, Equatable {
    public let acceptInRecordedMask: Bool
    public let nativeAcceptanceError: String?
    public let before: [TradeSeatFacts]
    public let afterAcceptance: [TradeSeatFacts]?

    public static func make(observation: GameObservation, offerID: UUID) throws -> Self {
        guard observation.state.pendingTradeOffers.contains(where: { $0.id == offerID }) else {
            throw MoveError.invalidTradeTarget
        }
        let move = GameMove.respondToTrade(offerID: offerID, accept: true)
        let before = facts(in: observation.state)
        var copy = observation.state
        do {
            try RulesEngine.apply(move, by: observation.seat, to: &copy)
        } catch let error as MoveError {
            return Self(acceptInRecordedMask: observation.legalMoves.contains(move),
                        nativeAcceptanceError: String(describing: error), before: before, afterAcceptance: nil)
        }
        return Self(acceptInRecordedMask: observation.legalMoves.contains(move),
                    nativeAcceptanceError: nil, before: before, afterAcceptance: facts(in: copy))
    }

    private static func facts(in state: GameState) -> [TradeSeatFacts] {
        state.players.map { player in
            var ownTurn = state
            // Explicit counterfactual: otherwise an off-turn receiver would
            // appear to have no possible builds regardless of its inventory.
            ownTurn.phase = .mainTurn(playerIndex: player.id.index)
            let moves = RulesEngine.legalMoves(for: ownTurn)
            return TradeSeatFacts(
                seat: player.id.index, mainTurnNow: state.phase.isMainTurn(of: player.id.index),
                publicVP: state.publicVictoryPoints(for: player.id), totalVP: state.victoryPoints(for: player.id),
                hand: resources(player.resources),
                bankRates: Dictionary(uniqueKeysWithValues: Resource.allCases.map {
                    ($0.rawValue, Trading.bestRate(for: $0, player: player.id, state: state))
                }),
                expectedCardsPerRoll: production(player: player, state: state),
                mainTurnOptionsOnFrozenBoard: TradeBuildOptions(moves: moves))
        }
    }

    private static func resources(_ values: [Resource: Int]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: Resource.allCases.map { ($0.rawValue, values[$0] ?? 0) })
    }

    /// Expected payout on the next roll with this robber and bank stock held
    /// fixed. Native payout handles cities and bank shortages; no second rules
    /// implementation, future dice, or shuffled deck is consulted. Seven's
    /// production is zero; discard/robbery losses are not included.
    private static func production(player: Player, state: GameState) -> [String: Double] {
        var totals = Dictionary(uniqueKeysWithValues: Resource.allCases.map { ($0.rawValue, 0.0) })
        for roll in 2...12 where roll != 7 {
            var rolled = state
            MainPhase.rollDice(state: &rolled, roll: roll)
            for resource in Resource.allCases {
                let gained = (rolled.players[player.id.index].resources[resource] ?? 0)
                    - (player.resources[resource] ?? 0)
                totals[resource.rawValue, default: 0] += Double(gained * DiceOdds.pips(for: roll)) / 36
            }
        }
        return totals
    }
}

public struct TradeSeatFacts: Codable, Sendable, Equatable {
    public let seat: Int
    public let mainTurnNow: Bool
    public let publicVP: Int
    public let totalVP: Int
    public let hand: [String: Int]
    public let bankRates: [String: Int]
    public let expectedCardsPerRoll: [String: Double]
    public let mainTurnOptionsOnFrozenBoard: TradeBuildOptions
}

/// Counts are drawn from native legal actions, so resource costs, remaining
/// pieces and placement constraints all apply. They do not rank usefulness or
/// enumerate multi-action sequences (roads then settlements, bank trades, etc.).
public struct TradeBuildOptions: Codable, Sendable, Equatable {
    public let roads: Int
    public let settlements: Int
    public let cities: Int
    public let developmentCard: Bool
    public let bankExchanges: Int

    init(moves: [GameMove]) {
        roads = moves.filter { if case .buildRoad = $0 { true } else { false } }.count
        settlements = moves.filter { if case .buildSettlement = $0 { true } else { false } }.count
        cities = moves.filter { if case .buildCity = $0 { true } else { false } }.count
        developmentCard = moves.contains(.buyDevCard)
        bankExchanges = moves.filter { if case .bankTrade = $0 { true } else { false } }.count
    }
}
