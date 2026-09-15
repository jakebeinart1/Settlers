import Testing
import CatanEngine
@testable import CatanAI

/// Jake, playing build 10: "the bot offers the same trade after I deny it on
/// the same term three times in a row... they should really focus on giving a
/// better trade or nothing."
///
/// Three was not a coincidence - it is `RulesEngine.maxTradeProposalsPerTurn`,
/// the engine backstop cutting the loop off. The policy itself had nothing to
/// say about a refusal.
@Suite struct EvaluationTradeRepeatTests {

    private func table(seed: UInt64 = 71) -> (GameState, PlayerID) {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        playOpeningPlacements(in: &state, seed: seed)
        state.phase = .mainTurn(playerIndex: 0)
        return (state, state.players[0].id)
    }

    private func refusing(_ offer: TradeOffer, in state: GameState) -> GameState {
        var next = state
        next.declinedTradeOffersThisTurn[offer.from, default: []].append(offer)
        return next
    }

    /// The reported bug, directly.
    @Test func theIdenticalOfferIsNeverAskedTwice() {
        let (state, me) = table()
        let policy = EvaluationPolicy()
        let offer = TradeOffer(from: me, give: [.ore: 2], want: [.lumber: 1])

        #expect(policy.improvesOnEveryRefusal(offer, in: state), "an untried offer must be allowed")
        #expect(
            !policy.improvesOnEveryRefusal(offer, in: refusing(offer, in: state)),
            "the bot re-asked a trade that was already refused"
        )
    }

    /// Two offers are the same proposition if they say the same thing, however
    /// each was built. Comparing by `id` would let a regenerated offer through.
    @Test func aRegeneratedOfferCountsAsTheSameProposition() {
        let (state, me) = table(seed: 72)
        let policy = EvaluationPolicy()
        let refused = TradeOffer(from: me, give: [.ore: 2], want: [.lumber: 1])
        let regenerated = TradeOffer.enumerated(from: me, give: [.ore: 2], want: [.lumber: 1])

        #expect(refused.id != regenerated.id, "the fixture must actually differ by id")
        #expect(!policy.improvesOnEveryRefusal(regenerated, in: refusing(refused, in: state)))
    }

    /// "A better trade or nothing": more on the table for the same ask is a new
    /// proposition and is allowed through.
    @Test func offeringMoreForTheSameAskIsAllowed() {
        let (state, me) = table(seed: 73)
        let policy = EvaluationPolicy()
        let refused = TradeOffer(from: me, give: [.ore: 2], want: [.lumber: 1])
        let better = TradeOffer(from: me, give: [.ore: 3], want: [.lumber: 1])

        #expect(policy.improvesOnEveryRefusal(better, in: refusing(refused, in: state)))
    }

    /// The two ways a re-ask can be worse, which are the ones that read as
    /// pestering: less on the table, or a bigger ask for the same goods.
    @Test func aWorseReAskIsRefused() {
        let (state, me) = table(seed: 74)
        let policy = EvaluationPolicy()
        let refused = TradeOffer(from: me, give: [.ore: 2], want: [.lumber: 1])
        let after = refusing(refused, in: state)

        #expect(
            !policy.improvesOnEveryRefusal(
                TradeOffer(from: me, give: [.ore: 1], want: [.lumber: 1]), in: after
            ),
            "less on the table for the same ask is worse, not a new offer"
        )
        #expect(
            !policy.improvesOnEveryRefusal(
                TradeOffer(from: me, give: [.ore: 2], want: [.lumber: 2]), in: after
            ),
            "a bigger ask for the same goods is worse, not a new offer"
        )
    }

    /// A different trade entirely is a new proposition, not a re-ask.
    @Test func aDifferentTradeIsStillAllowed() {
        let (state, me) = table(seed: 75)
        let policy = EvaluationPolicy()
        let refused = TradeOffer(from: me, give: [.ore: 2], want: [.lumber: 1])

        #expect(
            policy.improvesOnEveryRefusal(
                TradeOffer(from: me, give: [.wool: 2], want: [.brick: 1]),
                in: refusing(refused, in: state)
            )
        )
    }
}
