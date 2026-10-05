import CatanEngine
import Testing
@testable import CatanAI

@Suite struct GhostTrainingProvenanceTests {
    @Test(arguments: [false, true])
    func manualResponsesTrainButTheSameAutomaticMoveDoesNot(accept: Bool) throws {
        let (initial, offer) = position()
        let move = GameMove.respondToTrade(offerID: offer.id, accept: accept)
        let human = initial.players[0].id
        let manual = LoggedGame(id: "manual", initialState: initial, humanSeats: [human],
                                events: [LoggedMove(player: human, move: move)])
        let automatic = LoggedGame(id: "automatic", initialState: initial, humanSeats: [human],
                                   events: [LoggedMove(player: human, move: move, isHumanDecision: false)])
        let records = try DecisionExtractor.decisions(in: manual, anchor: .forMode(.classic))
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.facet == .tradeResponse)
        #expect(record.candidates[record.chosen].move == move)
        #expect(try DecisionExtractor.decisions(in: automatic, anchor: .forMode(.classic)).isEmpty)
    }

    @Test func automaticRejectionStillAppliesBeforeTheNextProposalAndHumanChoice() throws {
        let (initial, offer) = position()
        let human = initial.players[0].id
        let next = TradeOffer.enumerated(from: offer.from, give: [.ore: 1], want: [.lumber: 2])
        let events = [
            LoggedMove(player: human, move: .respondToTrade(offerID: offer.id, accept: false), isHumanDecision: false),
            LoggedMove(player: offer.from, move: .proposeTrade(next)),
            LoggedMove(player: human, move: .respondToTrade(offerID: next.id, accept: true)),
        ]
        let game = LoggedGame(id: "whole-trace", initialState: initial, humanSeats: [human], events: events)
        let anchor = EvaluationWeights.forMode(.classic)
        let records = try DecisionExtractor.decisions(in: game, anchor: anchor)
        #expect(records.count == 1, "The automatic affordable rejection is not a human preference")

        var reference = GameSession(state: initial, policies: [:], policySeed: 0)
        for event in events.dropLast() { try reference.applyExternal(event.move, by: event.player) }
        let last = try #require(events.last)
        let expected = try DecisionExtractor.decision(for: last, in: reference, game: game.id, anchor: anchor, humanTrading: true)
        let present = try #require(expected)
        #expect(records == [present], "Later learning must use the public ledger after the automatic move")
        try reference.applyExternal(last.move, by: last.player)
        #expect(reference.state.pendingTradeOffers.isEmpty)
        #expect(reference.state.players[0].resources[.ore] == 1)
    }

    @Test func invalidAutomaticMoveStillFailsExtractionWithItsIndex() throws {
        let (initial, offer) = position()
        let human = initial.players[0].id
        let reject = GameMove.respondToTrade(offerID: offer.id, accept: false)
        let events = [LoggedMove(player: human, move: reject, isHumanDecision: false),
                       LoggedMove(player: human, move: reject, isHumanDecision: false)]
        let game = LoggedGame(id: "bad-auto", initialState: initial, humanSeats: [human], events: events)
        #expect {
            try DecisionExtractor.decisions(in: game, anchor: .forMode(.classic))
        } throws: { error in
            guard case ExtractionError.divergedAt(let id, let index, _) = error else { return false }
            return id == game.id && index == 1
        }
    }

    private func position() -> (GameState, TradeOffer) {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 33, playerCount: 3)
        state.phase = .mainTurn(playerIndex: 1)
        state.players[0].resources = [.lumber: 3, .brick: 2]
        state.players[1].resources = [.ore: 2, .wool: 2]
        for resource in Resource.allCases {
            state.bank[resource] = 19 - state.players.reduce(0) { $0 + $1.resources[resource, default: 0] }
        }
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.ore: 1], want: [.lumber: 1])
        state.pendingTradeOffers = [offer]
        return (state, offer)
    }
}
