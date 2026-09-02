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

@Test func decisionMetricsRecordChoiceOpportunities() {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
    let seat = state.players[0].id
    let vertices = state.board.onBoardVertices.sorted()
    let settlement = GameMove.buildSettlement(vertices[0])
    let city = GameMove.buildCity(vertices[1])
    let buyCard = GameMove.buyDevCard
    var metrics = PolicyBehaviorMetrics()

    metrics.observeDecision(
        GameObservation(seat: seat, state: state, legalMoves: [settlement, city, buyCard, .endTurn]),
        chosen: city
    )

    #expect(metrics.settlementCityOpportunities == 1)
    #expect(metrics.settlementsChosenInMixedBuildOpportunities == 0)
    #expect(metrics.citiesChosenInMixedBuildOpportunities == 1)
    #expect(metrics.developmentCardBuildOpportunities == 1)
    #expect(metrics.developmentCardsChosenOverPermanentBuild == 0)
}

@Test func decisionMetricsRecordTradeResponsesAndProposalShape() {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 11)
    let seat = state.players[1].id
    let offer = TradeOffer(
        from: seat,
        give: [.brick: 2, .lumber: 1],
        want: [.ore: 1]
    )
    let offerID = offer.id
    var metrics = PolicyBehaviorMetrics()

    metrics.observeDecision(
        GameObservation(
            seat: seat,
            state: state,
            legalMoves: [
                .respondToTrade(offerID: offerID, accept: true),
                .respondToTrade(offerID: offerID, accept: false),
            ]
        ),
        chosen: .respondToTrade(offerID: offerID, accept: true)
    )
    metrics.observeDecision(
        GameObservation(seat: seat, state: state, legalMoves: [.proposeTrade(offer), .endTurn]),
        chosen: .proposeTrade(offer)
    )

    #expect(metrics.tradeResponseOpportunities == 1)
    #expect(metrics.tradeResponsesAccepted == 1)
    #expect(metrics.proposalCardsGiven == 3)
    #expect(metrics.proposalCardsRequested == 1)
}

@Test func decisionMetricsRecordDisruptionAndProposalOpportunities() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 13)
    let seat = state.players[0].id
    let leader = state.players[1].id
    let trailer = state.players[2].id
    let vertices = state.board.onBoardVertices.sorted()
    state.players[1].settlements = [vertices[0], vertices[1]]
    state.players[2].settlements = [vertices[2]]
    let tiles = state.board.tiles.map(\.coordinate)
    let attackLeader = GameMove.playKnight(moveRobberTo: tiles[0], stealFrom: leader)
    let attackTrailer = GameMove.playKnight(moveRobberTo: tiles[1], stealFrom: trailer)
    let proposal = TradeOffer(from: seat, give: [.brick: 1], want: [.ore: 1])
    var metrics = PolicyBehaviorMetrics()

    metrics.observeDecision(
        GameObservation(
            seat: seat,
            state: state,
            legalMoves: [attackLeader, attackTrailer, .proposeTrade(proposal), .endTurn]
        ),
        chosen: attackLeader
    )

    #expect(metrics.playableKnightOpportunities == 1)
    #expect(metrics.knightsChosenWhenPlayable == 1)
    #expect(metrics.differentiatedRobberTargetOpportunities == 1)
    #expect(metrics.highestPublicVPRobberTargets == 1)
    #expect(metrics.tradeProposalOpportunities == 1)

    metrics.observeDecision(
        GameObservation(seat: seat, state: state, legalMoves: [attackLeader, attackTrailer, .endTurn]),
        chosen: .endTurn
    )
    #expect(metrics.playableKnightOpportunities == 2)
    #expect(metrics.differentiatedRobberTargetOpportunities == 1)

    metrics.observeDecision(
        GameObservation(
            seat: seat,
            state: state,
            legalMoves: [.respondToTrade(offerID: proposal.id, accept: false)]
        ),
        chosen: .respondToTrade(offerID: proposal.id, accept: false)
    )
    #expect(metrics.tradeResponseOpportunities == 0)
}
