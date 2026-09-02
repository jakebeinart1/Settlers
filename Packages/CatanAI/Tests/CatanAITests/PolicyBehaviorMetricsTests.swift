import CatanEngine
import Testing
@testable import CatanAI

@Test func behaviorMetricsCountOnlyTheObservedSeat() {
    let hero = PlayerID(index: 1)
    let other = PlayerID(index: 2)
    var metrics = PolicyBehaviorMetrics()

    metrics.observe([
        .builtRoad(hero),
        .builtRoad(other),
        .playedRoadBuilding(hero),
        .builtCity(hero),
        .boughtDevCard(hero),
        .playedKnight(hero, from: other, stealing: .ore),
        .movedRobber(hero, from: nil, stealing: nil),
        .tradedWithBank(hero, gave: [.brick: 4], got: [.ore: 1]),
        .proposedTrade(hero, give: [.wool: 1], want: [.grain: 1]),
        .acceptedTrade(hero, from: other, gave: [.grain: 1], got: [.wool: 1]),
        .rejectedTrade(hero, from: other),
        .endedTurn(hero),
    ], for: hero)

    #expect(metrics.roadsBuilt == 3)
    #expect(metrics.settlementsBuilt == 0)
    #expect(metrics.citiesBuilt == 1)
    #expect(metrics.developmentCardsBought == 1)
    #expect(metrics.knightsPlayed == 1)
    #expect(metrics.robberMoves == 2)
    #expect(metrics.bankTrades == 1)
    #expect(metrics.tradesProposed == 1)
    #expect(metrics.resolvedTradeAcceptances == 1)
    #expect(metrics.resolvedTradeRejections == 1)
    #expect(metrics.turnsEnded == 1)
}
