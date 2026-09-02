import CatanEngine
import Foundation

/// Observable decisions made by one policy during a game.
///
/// These counters describe style, not strength. Keeping them beside the policy
/// layer lets the simulator, future trainers, and replay analysis use the same
/// definitions without teaching the rules engine about evaluation concerns.
public struct PolicyBehaviorMetrics: Codable, Sendable, Equatable {
    public private(set) var roadsBuilt = 0
    public private(set) var settlementsBuilt = 0
    public private(set) var citiesBuilt = 0
    public private(set) var developmentCardsBought = 0
    public private(set) var knightsPlayed = 0
    public private(set) var robberMoves = 0
    public private(set) var bankTrades = 0
    public private(set) var tradesProposed = 0
    public private(set) var resolvedTradeAcceptances = 0
    public private(set) var resolvedTradeRejections = 0
    public private(set) var turnsEnded = 0

    public init() {}

    /// Records only events attributable to `seat`.
    public mutating func observe(_ events: [GameEvent], for seat: PlayerID) {
        for event in events where event.actor == seat {
            observe(event)
        }
    }

    private mutating func observe(_ event: GameEvent) {
        switch event {
        case .builtRoad: roadsBuilt += 1
        case .playedRoadBuilding:
            roadsBuilt += 2
        case .builtSettlement: settlementsBuilt += 1
        case .builtCity: citiesBuilt += 1
        case .boughtDevCard: developmentCardsBought += 1
        case .playedKnight:
            knightsPlayed += 1
            robberMoves += 1
        case .movedRobber: robberMoves += 1
        case .tradedWithBank: bankTrades += 1
        case .proposedTrade: tradesProposed += 1
        case .acceptedTrade: resolvedTradeAcceptances += 1
        case .rejectedTrade: resolvedTradeRejections += 1
        case .endedTurn: turnsEnded += 1
        default: break
        }
    }
}

private extension GameEvent {
    var actor: PlayerID {
        switch self {
        case .placedInitialSettlement(let seat), .placedInitialRoad(let seat),
             .rolled(let seat, _), .discarded(let seat, _), .builtRoad(let seat),
             .builtSettlement(let seat), .builtCity(let seat), .boughtDevCard(let seat),
             .movedRobber(let seat, _, _), .playedKnight(let seat, _, _),
             .playedRoadBuilding(let seat), .playedYearOfPlenty(let seat, _),
             .playedMonopoly(let seat, _, _), .tradedWithBank(let seat, _, _),
             .proposedTrade(let seat, _, _), .acceptedTrade(let seat, _, _, _),
             .rejectedTrade(let seat, _), .endedTurn(let seat), .gameWon(let seat):
            return seat
        }
    }
}
