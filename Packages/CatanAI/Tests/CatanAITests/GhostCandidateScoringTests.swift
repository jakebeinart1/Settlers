import Testing
import CatanEngine
@testable import CatanAI

@Suite struct GhostCandidateScoringTests {

    private func table(seed: UInt64 = 81) -> (GameState, PlayerID) {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        playOpeningPlacements(in: &state, seed: seed)
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].resources = [.ore: 3, .grain: 1, .brick: 2, .lumber: 2]
        return (state, state.players[0].id)
    }

    private func observation(_ state: GameState, _ seat: PlayerID) -> GameObservation {
        GameObservation(seat: seat, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: seat))
    }

    /// Every move the engine accepts, other than a proposal, is scored.
    @Test func everyNonProposalLegalMoveIsScored() {
        let (state, me) = table()
        let obs = observation(state, me)
        let scored = EvaluationPolicy().candidateScores(obs, ledger: .fromPositionAlone(state, observer: me))
        let nonProposals = obs.legalMoves.filter { if case .proposeTrade = $0 { false } else { true } }
        #expect(nonProposals.count > 1)
        for move in nonProposals where move != .rollDice {
            #expect(scored.contains { $0.move == move }, "missing \(move)")
        }
    }

    /// A person's offer that Expert would filter out still gets a value.
    @Test func aHumanOfferExpertWouldNeverMakeIsScored() {
        let (state, me) = table()
        let greedy = TradeOffer(from: me, give: [.brick: 1], want: [.ore: 2, .grain: 1])
        let scored = EvaluationPolicy().candidateScores(
            observation(state, me), ledger: .fromPositionAlone(state, observer: me), extraProposals: [greedy]
        )
        #expect(scored.contains { if case .proposeTrade(let o) = $0.move { o.sameProposition(as: greedy) } else { false } })
    }

    /// A person may accept an offer Expert would refuse; the accept still needs
    /// a value, or extraction cannot find the move they made. Expert's
    /// `acceptance` returned nil for exactly these, and whether it did moved
    /// with the weights, which crashed the re-linearised selftest.
    @Test func aBadOfferCanStillBeAccepted() {
        var (state, me) = table()
        let proposer = state.players[1].id
        state.phase = .mainTurn(playerIndex: 1)
        state.players[1].resources = [.wool: 1]
        let offer = TradeOffer.enumerated(from: proposer, give: [.wool: 1], want: [.ore: 3])
        state.pendingTradeOffers = [offer]
        let accept = GameMove.respondToTrade(offerID: offer.id, accept: true)
        let obs = GameObservation(seat: me, state: state,
                                  legalMoves: [accept, .respondToTrade(offerID: offer.id, accept: false)])
        let scored = EvaluationPolicy().candidateScores(obs, ledger: .fromPositionAlone(state, observer: me))
        #expect(scored.map(\.move).contains(accept))
        #expect(scored.count == 2)
    }

    /// Weights change scores, never the candidate list. The extractor's slopes depend on it.
    @Test func candidateOrderDoesNotDependOnWeights() {
        let (state, me) = table()
        let obs = observation(state, me)
        let ledger = PublicLedger.fromPositionAlone(state, observer: me)
        var shifted = EvaluationWeights.forMode(.classic).vector
        shifted[1] *= 1.5
        let a = EvaluationPolicy().candidateScores(obs, ledger: ledger).map(\.move)
        let b = EvaluationPolicy(weights: EvaluationWeights(vector: shifted)).candidateScores(obs, ledger: ledger).map(\.move)
        #expect(!a.isEmpty)
        #expect(a == b)
    }
}
