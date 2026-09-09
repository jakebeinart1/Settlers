import Foundation
import Testing
import CatanEngine
import CatanAI

@Suite struct TradeContributionTests {
    @Test func componentsReconstructTheActualReductions() throws {
        let state = tradeState()
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.lumber: 2, .grain: 1], want: [.ore: 2, .wool: 1])
        let result = try assessment(offer, state: state)
        let components = try #require(result.resourceContributions)
        #expect(components.map(\.resource) == Array(offer.give.keys) + Array(offer.want.keys))
        #expect(components.map(\.quantity) == Array(offer.give.values) + Array(offer.want.values))
        for component in components {
            #expect(component.targets.map(\.targetName) == ["settlement", "city", "devCard", "road"])
            #expect(component.targets.reduce(0.0) { $0 + $1.contribution } == component.unitValue)
            #expect(component.totalValue == component.unitValue * Double(component.quantity))
            for target in component.targets {
                #expect(target.held == state.players[0].resources[component.resource, default: 0])
                #expect(target.deficit == max(0, target.required - target.held))
                let expected = target.deficit > 0 ? target.weight * (1.0 / (1.0 + Double(target.otherDeficits))) : 0
                #expect(target.contribution == expected)
            }
        }
        #expect(components.filter { $0.direction == .gain }.reduce(0.0) { $0 + $1.totalValue } == result.gainValue)
        #expect(components.filter { $0.direction == .cost }.reduce(0.0) { $0 + $1.totalValue } == result.costValue)
        #expect(result.netGain == result.gainValue - result.costValue)
        #expect(try JSONDecoder().decode(TradeAssessment.self, from: JSONEncoder().encode(result)) == result)
    }

    @Test func workedTargetsExplainZeroAndPositiveMarginalValues() throws {
        let state = tradeState()
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.lumber: 2], want: [.ore: 1])
        let result = try assessment(offer, state: state)
        let components = try #require(result.resourceContributions)
        let lumber = try #require(components.first { $0.resource == .lumber })
        #expect(lumber.unitValue == 4)
        #expect(lumber.totalValue == 8, "quantity multiplies original-hand value; no sequential card repricing")
        #expect(lumber.targets.map(\.required) == [1, 0, 0, 1])
        #expect(lumber.targets.map(\.deficit) == [1, 0, 0, 1])
        #expect(lumber.targets.map(\.otherDeficits) == [0, 4, 1, 0])
        #expect(lumber.targets.map(\.weight) == [3, 2.5, 1.5, 1])
        #expect(lumber.targets.map(\.contribution) == [3, 0, 0, 1])
        let ore = try #require(components.first { $0.resource == .ore })
        #expect(ore.unitValue == 2.75)
        #expect(ore.targets.map(\.required) == [0, 3, 1, 0])
        #expect(ore.targets.map(\.otherDeficits) == [1, 1, 0, 1])
        #expect(ore.targets.map(\.contribution) == [0, 1.25, 1.5, 0])
    }

    @Test func costUsesOriginalHandNotTheDeficitCreatedByLosingCards() throws {
        let state = tradeState()
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.lumber: 1], want: [.brick: 1])
        let result = try assessment(offer, state: state)
        let cost = try #require(result.resourceContributions?.first { $0.direction == .cost })
        #expect(cost.resource == .brick)
        #expect(cost.unitValue == 0)
        #expect(cost.totalValue == 0)
        #expect(cost.targets.allSatisfy { $0.held == 1 && $0.deficit == 0 && $0.contribution == 0 })
        let settlement = try #require(cost.targets.first { $0.targetName == "settlement" })
        #expect(settlement.required == 1)
        #expect(settlement.held - cost.quantity < settlement.required, "loss would create a deficit, but is not repriced")
        #expect(result.costValue == 0)
    }

    @Test func diagnosticsAreOptInAndPreserveEveryRecordedScalar() throws {
        let state = tradeState()
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.lumber: 2, .grain: 1], want: [.ore: 2])
        for personality in [BotPersonality.balanced, .cautious, .aggressive] {
            let plain = try #require(TradeHeuristics.assessment(
                offer: offer, receiver: state.players[0].id, state: state, personality: personality
            ))
            let detailed = try #require(TradeHeuristics.assessment(
                offer: offer, receiver: state.players[0].id, state: state, personality: personality, includeContributions: true
            ))
            #expect(plain.resourceContributions == nil)
            #expect(try withoutContributions(detailed) == plain)
            #expect(detailed.accepted == TradeHeuristics.evaluate(
                offer: offer, receiver: state.players[0].id, state: state, personality: personality
            ))
            let firstTarget = personality.expansionBias < BotWeights.default.cityFirstExpansionBiasPivot ? "city" : "settlement"
            #expect(detailed.resourceContributions?.first?.targets.first?.targetName == firstTarget)
        }
    }

    @Test func offlineExplanationLeavesBotMovesAndRNGUnchanged() throws {
        var state = tradeState()
        state.phase = .mainTurn(playerIndex: 1)
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.lumber: 1], want: [.wool: 1])
        state.pendingTradeOffers = [offer]
        let accept = GameMove.respondToTrade(offerID: offer.id, accept: true)
        let legal = [accept, GameMove.respondToTrade(offerID: offer.id, accept: false)]
        let bot = Bot(personality: .balanced)
        var plainRNG = RandomSource(seed: 29)
        var tracedRNG = plainRNG
        let originalStateRNG = state.rng
        let plain = bot.decide(for: state, player: state.players[0].id, legalMoves: legal, rng: &plainRNG)
        let detailed = try assessment(offer, state: state)
        var recorded: [TradeAssessment] = []
        let traced = bot.decide(
            for: state, player: state.players[0].id, legalMoves: legal, rng: &tracedRNG, assessments: &recorded
        )
        #expect(plain == accept && traced == plain)
        #expect(tracedRNG == plainRNG && plainRNG == RandomSource(seed: 29))
        #expect(state.rng == originalStateRNG)
        #expect(recorded.count == 1)
        #expect(recorded.allSatisfy { $0.resourceContributions != nil })
        #expect(detailed == recorded.first)
    }

    @Test func oldJSONDecodesScalarsVerbatimWithoutInventingComponents() throws {
        let offer = TradeOffer.enumerated(from: PlayerID(index: 1), give: [.lumber: 1], want: [.ore: 1])
        let offerJSON = try #require(String(data: JSONEncoder().encode(offer), encoding: .utf8))
        let receiverJSON = try #require(String(data: JSONEncoder().encode(PlayerID(index: 0)), encoding: .utf8))
        // Deliberately inconsistent historic scalars must be decoded, never recomputed.
        let oldJSON = """
        {"offer":\(offerJSON),"receiver":\(receiverJSON),"gainValue":12.25,"costValue":3.5,
         "netGain":-99,"baseThreshold":0.125,"threatShift":0.25,"standingShift":-0.5,
         "suspicionShift":0.75,"unlockShift":1.5,"threshold":42,"accepted":true}
        """
        let decoded = try JSONDecoder().decode(TradeAssessment.self, from: Data(oldJSON.utf8))
        #expect(decoded.resourceContributions == nil)
        #expect(decoded.gainValue == 12.25 && decoded.costValue == 3.5 && decoded.netGain == -99)
        #expect(decoded.baseThreshold == 0.125 && decoded.threatShift == 0.25 && decoded.standingShift == -0.5)
        #expect(decoded.suspicionShift == 0.75 && decoded.unlockShift == 1.5 && decoded.threshold == 42)
        #expect(decoded.accepted)
        #expect(try JSONDecoder().decode(TradeAssessment.self, from: JSONEncoder().encode(decoded)) == decoded)
    }

    @Test func emptyOffersHaveAvailableEmptyComponentsAndMissingReceiversHaveNoAssessment() throws {
        let state = tradeState()
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [:], want: [:])
        let result = try assessment(offer, state: state)
        #expect(result.resourceContributions == [])
        #expect(result.gainValue == 0 && result.costValue == 0)
        #expect(TradeHeuristics.assessment(
            offer: offer, receiver: PlayerID(index: 99), state: state, personality: .balanced, includeContributions: true
        ) == nil)
    }

    private func tradeState() -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4)
        state.players[0].resources = [.brick: 1, .grain: 1, .wool: 1]
        return state
    }

    private func assessment(_ offer: TradeOffer, state: GameState) throws -> TradeAssessment {
        try #require(TradeHeuristics.assessment(
            offer: offer, receiver: state.players[0].id, state: state, personality: .balanced, includeContributions: true
        ))
    }

    private func withoutContributions(_ assessment: TradeAssessment) throws -> TradeAssessment {
        let data = try JSONEncoder().encode(assessment)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "resourceContributions")
        return try JSONDecoder().decode(TradeAssessment.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
