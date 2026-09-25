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

    /// Found in Jake's own games: holding a single ore, he offered it 1-for-1.
    /// `legalMoves` enumerates only gives of a resource held twice, so it listed
    /// no proposals at all, while the app lets a person offer anything they can
    /// afford on their own turn. Under human rules the offer is a candidate;
    /// under bot rules (the ghost's) it is not.
    @Test func aPersonMayOfferTheirLastCardOfAKind() {
        var (state, me) = table()
        state.players[0].resources = [.ore: 1, .grain: 1, .wool: 1]
        let obs = observation(state, me)
        #expect(!obs.legalMoves.contains { if case .proposeTrade = $0 { true } else { false } })
        let offer = TradeOffer(from: me, give: [.ore: 1], want: [.lumber: 1])
        let ledger = PublicLedger.fromPositionAlone(state, observer: me)
        func proposes(_ scored: [ScoredCandidate]) -> Bool {
            scored.contains { if case .proposeTrade(let o) = $0.move { o.sameProposition(as: offer) } else { false } }
        }
        #expect(proposes(EvaluationPolicy().candidateScores(obs, ledger: ledger, extraProposals: [offer], humanTrading: true)))
        #expect(!proposes(EvaluationPolicy().candidateScores(obs, ledger: ledger, extraProposals: [offer])))
    }

    /// Also Jake's: 6 ore for a grain and a wool. The engine caps a composed
    /// give at `maxComposedTradeGive` (5); the app does not cap a person.
    @Test func aPersonMayOfferMoreThanTheBotLimit() {
        var (state, me) = table()
        state.players[0].resources = [.ore: 7, .brick: 2]
        let offer = TradeOffer(from: me, give: [.ore: 6], want: [.grain: 1, .wool: 1])
        let scored = EvaluationPolicy().candidateScores(observation(state, me), ledger: .fromPositionAlone(state, observer: me),
                                                        extraProposals: [offer], humanTrading: true)
        #expect(scored.contains { if case .proposeTrade(let o) = $0.move { o.sameProposition(as: offer) } else { false } })
    }

    /// Jake again: one bank trade of 6 ore for a grain and a wool - two 3:1
    /// swaps in one move, which the app accepts and `legalMoves` never lists.
    /// Any move the person made that replays is a candidate, scored like the rest.
    @Test func aMoveTheEngineAcceptsButNeverListsIsScored() {
        var (state, me) = table()
        state.players[0].resources = [.ore: 8]
        let combined = GameMove.bankTrade(give: [.ore: 8], get: [.grain: 1, .wool: 1])
        let obs = observation(state, me)
        #expect(!obs.legalMoves.contains(combined))
        let scored = EvaluationPolicy().candidateScores(obs, ledger: .fromPositionAlone(state, observer: me), extraMoves: [combined])
        #expect(scored.contains { $0.move == combined })
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
