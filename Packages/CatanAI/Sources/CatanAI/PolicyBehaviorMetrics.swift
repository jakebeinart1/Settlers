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
    public private(set) var settlementCityOpportunities = 0
    public private(set) var settlementsChosenInMixedBuildOpportunities = 0
    public private(set) var citiesChosenInMixedBuildOpportunities = 0
    public private(set) var cityBuildOpportunities = 0
    public private(set) var citiesChosenWhenBuildable = 0
    public private(set) var developmentCardBuildOpportunities = 0
    public private(set) var developmentCardsChosenOverPermanentBuild = 0
    public private(set) var tradeResponseOpportunities = 0
    public private(set) var tradeResponsesAccepted = 0
    public private(set) var proposalCardsGiven = 0
    public private(set) var proposalCardsRequested = 0
    public private(set) var playableKnightOpportunities = 0
    public private(set) var knightsChosenWhenPlayable = 0
    public private(set) var differentiatedRobberTargetOpportunities = 0
    public private(set) var highestPublicVPRobberTargets = 0
    public private(set) var tradeProposalOpportunities = 0

    public init() {}

    /// Records only events attributable to `seat`.
    public mutating func observe(_ events: [GameEvent], for seat: PlayerID) {
        for event in events where event.actor == seat {
            observe(event)
        }
    }

    /// Records a choice against the exact action mask shown to the policy.
    ///
    /// Event totals alone conflate preference with opportunity: a bot cannot
    /// choose a city it could not afford or accept an offer it never saw.
    /// These paired denominators make personality claims about decisions.
    public mutating func observeDecision(_ observation: GameObservation, chosen: GameMove) {
        recordBuildChoices(observation, chosen: chosen)
        recordTradeChoices(observation, chosen: chosen)
        recordKnightChoice(observation, chosen: chosen)
        recordRobberTargetChoice(observation, chosen: chosen)
    }

    private mutating func recordBuildChoices(_ observation: GameObservation, chosen: GameMove) {
        let hasSettlement = observation.legalMoves.contains { if case .buildSettlement = $0 { true } else { false } }
        let hasCity = observation.legalMoves.contains { if case .buildCity = $0 { true } else { false } }
        if hasSettlement, hasCity {
            settlementCityOpportunities += 1
            if case .buildSettlement = chosen { settlementsChosenInMixedBuildOpportunities += 1 }
            if case .buildCity = chosen { citiesChosenInMixedBuildOpportunities += 1 }
        }

        if hasCity {
            cityBuildOpportunities += 1
            if case .buildCity = chosen { citiesChosenWhenBuildable += 1 }
        }

        let hasPermanentBuild = observation.legalMoves.contains { move in
            switch move {
            case .buildRoad, .buildSettlement, .buildCity: true
            default: false
            }
        }
        if hasPermanentBuild, observation.legalMoves.contains(.buyDevCard) {
            developmentCardBuildOpportunities += 1
            if chosen == .buyDevCard { developmentCardsChosenOverPermanentBuild += 1 }
        }
    }

    private mutating func recordTradeChoices(_ observation: GameObservation, chosen: GameMove) {
        let isTradeResponse = observation.legalMoves.contains {
            if case .respondToTrade(_, accept: true) = $0 { true } else { false }
        }
        if isTradeResponse {
            tradeResponseOpportunities += 1
            if case .respondToTrade(_, accept: true) = chosen { tradeResponsesAccepted += 1 }
        }

        if case .proposeTrade(let offer) = chosen {
            proposalCardsGiven += offer.give.values.reduce(0, +)
            proposalCardsRequested += offer.want.values.reduce(0, +)
        }

        if observation.legalMoves.contains(where: { if case .proposeTrade = $0 { true } else { false } }) {
            tradeProposalOpportunities += 1
        }
    }

    private mutating func recordKnightChoice(_ observation: GameObservation, chosen: GameMove) {
        if observation.legalMoves.contains(where: { if case .playKnight = $0 { true } else { false } }) {
            playableKnightOpportunities += 1
            if case .playKnight = chosen { knightsChosenWhenPlayable += 1 }
        }
    }

    private mutating func recordRobberTargetChoice(_ observation: GameObservation, chosen: GameMove) {
        func victim(of move: GameMove) -> PlayerID? {
            switch move {
            case .moveRobber(_, let victim), .playKnight(_, let victim): victim
            default: nil
            }
        }

        guard let chosenVictim = victim(of: chosen) else { return }
        let victims = Set(observation.legalMoves.compactMap(victim))
        guard victims.count > 1 else { return }
        let points = Dictionary(uniqueKeysWithValues: victims.map {
            ($0, observation.state.publicVictoryPoints(for: $0))
        })
        guard let low = points.values.min(), let high = points.values.max(), low < high else { return }
        differentiatedRobberTargetOpportunities += 1
        guard points[chosenVictim] == high else { return }
        highestPublicVPRobberTargets += 1
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
             .rejectedTrade(let seat, _), .endedTurn(let seat), .gameWon(let seat),
             .boughtArmyCard(let seat, _), .deployedArmy(let seat, _, _, _):
            return seat
        }
    }
}
