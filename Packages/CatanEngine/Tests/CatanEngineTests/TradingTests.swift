import Testing
import Foundation
@testable import CatanEngine

@Suite struct TradingTests {

    @Test func fourToOneBankTradeWithNoPort() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.players[0].resources = [.brick: 4]
        try Trading.bankTrade(give: [.brick: 4], get: [.ore: 1], by: PlayerID(index: 0), state: &state)
        #expect(state.players[0].resources[.brick] == 0)
        #expect(state.players[0].resources[.ore] == 1)
    }

    @Test func threeToOneBankTradeWithGenericPort() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        guard let port = state.board.ports.first(where: { $0.kind == .generic }) else {
            Issue.record("no generic port on standard board")
            return
        }
        state.players[0].settlements = [port.vertexA]
        state.players[0].resources = [.brick: 3]
        try Trading.bankTrade(give: [.brick: 3], get: [.ore: 1], by: PlayerID(index: 0), state: &state)
        #expect(state.players[0].resources[.brick] == 0)
        #expect(state.players[0].resources[.ore] == 1)
    }

    @Test func twoToOneBankTradeWithMatchingResourcePort() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        guard case .resource(let resource)? = state.board.ports.first(where: {
            if case .resource = $0.kind { return true }
            return false
        })?.kind, let port = state.board.ports.first(where: { $0.kind == .resource(resource) }) else {
            Issue.record("no resource port on standard board")
            return
        }
        state.players[0].settlements = [port.vertexA]
        state.players[0].resources = [resource: 2]
        let other: Resource = Resource.allCases.first { $0 != resource }!
        try Trading.bankTrade(give: [resource: 2], get: [other: 1], by: PlayerID(index: 0), state: &state)
        #expect(state.players[0].resources[resource] == 0)
        #expect(state.players[0].resources[other] == 1)
    }

    @Test func bankTradeRejectedWhenRatioWrong() {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.players[0].resources = [.brick: 3]
        #expect(throws: (any Error).self) {
            try Trading.bankTrade(give: [.brick: 3], get: [.ore: 1], by: PlayerID(index: 0), state: &state)
        }
    }

    @Test func bankTradeRejectedWhenBankLacksResource() {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.players[0].resources = [.brick: 4]
        state.bank[.ore] = 0
        #expect(throws: (any Error).self) {
            try Trading.bankTrade(give: [.brick: 4], get: [.ore: 1], by: PlayerID(index: 0), state: &state)
        }
    }

    @Test func proposeAndAcceptTradeSwapsCardsBetweenPlayers() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.players[0].resources = [.brick: 2]
        state.players[1].resources = [.ore: 1]
        let offer = TradeOffer(id: UUID(), from: PlayerID(index: 0), give: [.brick: 1], want: [.ore: 1])
        try Trading.proposeTrade(offer, state: &state)
        try Trading.respond(offerID: offer.id, accept: true, by: PlayerID(index: 1), state: &state)
        #expect(state.players[0].resources[.ore] == 1)
        #expect(state.players[0].resources[.brick] == 1)
        #expect(state.players[1].resources[.brick] == 1)
        #expect(state.players[1].resources[.ore] == 0)
        #expect(state.pendingTradeOffers.isEmpty)
    }

    @Test func proposeAndRejectLeavesResourcesUntouched() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.players[0].resources = [.brick: 2]
        state.players[1].resources = [.ore: 1]
        let offer = TradeOffer(id: UUID(), from: PlayerID(index: 0), give: [.brick: 1], want: [.ore: 1])
        try Trading.proposeTrade(offer, state: &state)
        try Trading.respond(offerID: offer.id, accept: false, by: PlayerID(index: 1), state: &state)
        #expect(state.players[0].resources[.brick] == 2)
        #expect(state.players[1].resources[.ore] == 1)
        #expect(state.pendingTradeOffers.isEmpty)
    }

    @Test func acceptingATradeIncrementsTheProposersAcceptedCountAndRejectingDoesNot() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.players[0].resources = [.brick: 2]
        state.players[1].resources = [.ore: 2]
        let proposer = PlayerID(index: 0)

        let first = TradeOffer(id: UUID(), from: proposer, give: [.brick: 1], want: [.ore: 1])
        try Trading.proposeTrade(first, state: &state)
        try Trading.respond(offerID: first.id, accept: true, by: PlayerID(index: 1), state: &state)
        #expect(state.tradesAcceptedThisTurn[proposer] == 1)

        let second = TradeOffer(id: UUID(), from: proposer, give: [.brick: 1], want: [.ore: 1])
        try Trading.proposeTrade(second, state: &state)
        try Trading.respond(offerID: second.id, accept: false, by: PlayerID(index: 1), state: &state)
        // A rejection doesn't add to the count - only genuinely-landed
        // trades should raise the next bot's suspicion.
        #expect(state.tradesAcceptedThisTurn[proposer] == 1)
    }

    @Test func endTurnClearsTradesAcceptedThisTurn() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].resources = [.brick: 1]
        state.players[1].resources = [.ore: 1]
        let proposer = PlayerID(index: 0)

        let offer = TradeOffer(id: UUID(), from: proposer, give: [.brick: 1], want: [.ore: 1])
        try Trading.proposeTrade(offer, state: &state)
        try Trading.respond(offerID: offer.id, accept: true, by: PlayerID(index: 1), state: &state)
        #expect(state.tradesAcceptedThisTurn[proposer] == 1)

        try RulesEngine.apply(.endTurn, by: proposer, to: &state)
        #expect(state.tradesAcceptedThisTurn.isEmpty)
    }

    @Test func proposeTradeFailsIfProposerLacksGiveCards() {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.players[0].resources = [.brick: 0]
        let offer = TradeOffer(id: UUID(), from: PlayerID(index: 0), give: [.brick: 1], want: [.ore: 1])
        #expect(throws: (any Error).self) {
            try Trading.proposeTrade(offer, state: &state)
        }
    }

    @Test func acceptFailsIfResponderLacksWantedCards() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.players[0].resources = [.brick: 2]
        state.players[1].resources = [:]
        let offer = TradeOffer(id: UUID(), from: PlayerID(index: 0), give: [.brick: 1], want: [.ore: 1])
        try Trading.proposeTrade(offer, state: &state)
        #expect(throws: (any Error).self) {
            try Trading.respond(offerID: offer.id, accept: true, by: PlayerID(index: 1), state: &state)
        }
        // Offer should still be pending since the accept failed.
        #expect(state.pendingTradeOffers.contains { $0.id == offer.id })
    }

    // MARK: - Review fix: positive-amount validation

    @Test func bankTradeRejectsNegativeGiveAmount() {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.players[0].resources = [.brick: 0, .grain: 20]
        let bankBrickBefore = state.bank[.brick]
        #expect(throws: (any Error).self) {
            // Would otherwise net the player +4 brick and +2 ore for 8 grain,
            // by exploiting the negative `.brick` entry in the mutation loop.
            try Trading.bankTrade(give: [.brick: -4, .grain: 8], get: [.ore: 2], by: PlayerID(index: 0), state: &state)
        }
        #expect(state.players[0].resources[.brick] == 0)
        #expect(state.players[0].resources[.grain] == 20)
        #expect(state.bank[.brick] == bankBrickBefore)
    }

    @Test func bankTradeRejectsNegativeGetAmount() {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.players[0].resources = [.brick: 4]
        #expect(throws: (any Error).self) {
            try Trading.bankTrade(give: [.brick: 4], get: [.ore: -1], by: PlayerID(index: 0), state: &state)
        }
        #expect(state.players[0].resources[.brick] == 4)
    }

    @Test func proposeTradeRejectsNegativeAmounts() {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.players[0].resources = [.brick: 5]
        let offer = TradeOffer(id: UUID(), from: PlayerID(index: 0), give: [.brick: -1], want: [.ore: 1])
        #expect(throws: (any Error).self) {
            try Trading.proposeTrade(offer, state: &state)
        }
        #expect(state.pendingTradeOffers.isEmpty)
    }

    // MARK: - Review fix: responder cannot be the proposer

    @Test func respondRejectsWhenResponderIsProposer() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.players[0].resources = [.brick: 2]
        let offer = TradeOffer(id: UUID(), from: PlayerID(index: 0), give: [.brick: 1], want: [.ore: 1])
        try Trading.proposeTrade(offer, state: &state)
        #expect(throws: (any Error).self) {
            try Trading.respond(offerID: offer.id, accept: true, by: PlayerID(index: 0), state: &state)
        }
        #expect(state.pendingTradeOffers.contains { $0.id == offer.id })
    }

    // MARK: - Review fix: proposer's cards re-validated at acceptance time

    @Test func acceptFailsIfProposerNoLongerHoldsGiveCards() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.players[0].resources = [.brick: 1]
        state.players[1].resources = [.ore: 1]
        let offer = TradeOffer(id: UUID(), from: PlayerID(index: 0), give: [.brick: 1], want: [.ore: 1])
        try Trading.proposeTrade(offer, state: &state)

        // Proposer spends the offered brick elsewhere before the offer is
        // answered (e.g. a bank trade), simulating cards spent in between.
        state.players[0].resources[.brick] = 0

        #expect(throws: (any Error).self) {
            try Trading.respond(offerID: offer.id, accept: true, by: PlayerID(index: 1), state: &state)
        }
        #expect(state.players[0].resources[.brick] == 0)
        #expect(state.players[1].resources[.ore] == 1)
        // Offer remains pending since acceptance failed.
        #expect(state.pendingTradeOffers.contains { $0.id == offer.id })
    }

    // MARK: - Review fix: RulesEngine.apply integration coverage

    @Test func rulesEngineAppliesBankTrade() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].resources = [.brick: 4]
        try RulesEngine.apply(.bankTrade(give: [.brick: 4], get: [.ore: 1]), by: PlayerID(index: 0), to: &state)
        #expect(state.players[0].resources[.brick] == 0)
        #expect(state.players[0].resources[.ore] == 1)
    }

    @Test func rulesEngineAppliesProposeTrade() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].resources = [.brick: 2]
        let offer = TradeOffer(id: UUID(), from: PlayerID(index: 0), give: [.brick: 1], want: [.ore: 1])
        try RulesEngine.apply(.proposeTrade(offer), by: PlayerID(index: 0), to: &state)
        #expect(state.pendingTradeOffers.contains { $0.id == offer.id })
    }

    @Test func rulesEngineProposeTradeRejectsWrongProposer() {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.phase = .mainTurn(playerIndex: 0)
        state.players[1].resources = [.brick: 2]
        let offer = TradeOffer(id: UUID(), from: PlayerID(index: 1), give: [.brick: 1], want: [.ore: 1])
        #expect(throws: (any Error).self) {
            try RulesEngine.apply(.proposeTrade(offer), by: PlayerID(index: 0), to: &state)
        }
    }

    @Test func rulesEngineAllowsNonActivePlayerToRespondToTrade() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].resources = [.brick: 2]
        state.players[1].resources = [.ore: 1]
        let offer = TradeOffer(id: UUID(), from: PlayerID(index: 0), give: [.brick: 1], want: [.ore: 1])
        try RulesEngine.apply(.proposeTrade(offer), by: PlayerID(index: 0), to: &state)

        // Player 1 is not the active turn player (player 0 is), but must
        // still be able to respond to a trade directed at them.
        try RulesEngine.apply(.respondToTrade(offerID: offer.id, accept: true), by: PlayerID(index: 1), to: &state)
        #expect(state.players[0].resources[.ore] == 1)
        #expect(state.players[1].resources[.brick] == 1)
        #expect(state.pendingTradeOffers.isEmpty)
    }

    // MARK: - Task 8 review fix: legalMoves must not advertise an unaffordable accept

    @Test func legalMovesExcludesAcceptWhenResponderCannotAffordWantedCards() {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.phase = .mainTurn(playerIndex: 1)
        state.players[0].resources = [.brick: 2]
        state.players[1].resources = [:] // can't afford the .ore the offer wants
        let offer = TradeOffer(id: UUID(), from: PlayerID(index: 0), give: [.brick: 1], want: [.ore: 1])
        state.pendingTradeOffers = [offer]

        let moves = RulesEngine.legalMoves(for: state)
        #expect(!moves.contains { if case .respondToTrade(offer.id, true) = $0 { return true }; return false })
        #expect(moves.contains { if case .respondToTrade(offer.id, false) = $0 { return true }; return false })
    }

    @Test func legalMovesExcludesAcceptWhenProposerNoLongerAffordsGiveCards() {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.phase = .mainTurn(playerIndex: 1)
        state.players[0].resources = [.brick: 0] // proposer already spent the offered brick
        state.players[1].resources = [.ore: 1]
        let offer = TradeOffer(id: UUID(), from: PlayerID(index: 0), give: [.brick: 1], want: [.ore: 1])
        state.pendingTradeOffers = [offer]

        let moves = RulesEngine.legalMoves(for: state)
        #expect(!moves.contains { if case .respondToTrade(offer.id, true) = $0 { return true }; return false })
        #expect(moves.contains { if case .respondToTrade(offer.id, false) = $0 { return true }; return false })
    }

    @Test func legalMovesIncludesAcceptWhenBothSidesCanAfford() {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.phase = .mainTurn(playerIndex: 1)
        state.players[0].resources = [.brick: 1]
        state.players[1].resources = [.ore: 1]
        let offer = TradeOffer(id: UUID(), from: PlayerID(index: 0), give: [.brick: 1], want: [.ore: 1])
        state.pendingTradeOffers = [offer]

        let moves = RulesEngine.legalMoves(for: state)
        #expect(moves.contains { if case .respondToTrade(offer.id, true) = $0 { return true }; return false })
        #expect(moves.contains { if case .respondToTrade(offer.id, false) = $0 { return true }; return false })
    }

    @Test func rulesEngineStillRejectsUnrelatedOutOfTurnMoves() {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        state.phase = .mainTurn(playerIndex: 0)
        state.players[1].resources = [.brick: 4]
        // Player 1 is not active; a non-trade move from them must still be
        // rejected, confirming the `.respondToTrade` bypass didn't loosen
        // the turn guard for anything else.
        #expect(throws: (any Error).self) {
            try RulesEngine.apply(.bankTrade(give: [.brick: 4], get: [.ore: 1]), by: PlayerID(index: 1), to: &state)
        }
    }
}
