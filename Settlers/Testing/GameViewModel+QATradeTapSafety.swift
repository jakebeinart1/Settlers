#if DEBUG
import Foundation
import CatanEngine

/// DEBUG-only modifier for `-qaBotTradeAfterPause`:
/// `-qaTradeCompetitionWinner=human` or `=rival` selects a policy seed whose
/// actual funded rival accepts the four-Brick-for-one-Grain proposal. This
/// chooses a starting cursor, never injects an answer or an exchange. Omitting
/// the modifier keeps every existing Skip/No Limit fixture unchanged.
nonisolated enum TradeCompetitionQAWinner: String {
    case human, rival

    static var requested: Self? {
        let prefix = "-qaTradeCompetitionWinner="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        guard let winner = Self(rawValue: String(argument.dropFirst(prefix.count))) else {
            preconditionFailure("Trade competition QA winner must be human or rival")
        }
        return winner
    }
}

extension GameViewModel {
    /// Constructs the boundary before an offer, rather than displaying an
    /// already pending card. The UI still cancels a real pacing wait and the
    /// production session commits the policy's proposal, history and save.
    /// The policy keeps its production ID so this fixture remains resumable;
    /// cold resume restores the ordinary policy after the proposal is stored.
    func qaPrepareBotTradeAfterPause(
        bundled: Bool = QALaunchFlag.bundleOffer.isSet,
        competitionWinner: TradeCompetitionQAWinner? = TradeCompetitionQAWinner.requested
    ) {
        let human = humanPlayer
        guard let bot = state.players.first(where: { !humanSeats.contains($0.id) })?.id else {
            preconditionFailure("Trade-tap QA requires a bot")
        }
        let offer = competitionWinner == nil ? qaTradeTapOffer(from: bot, bundled: bundled)
            : TradeOffer.enumerated(from: bot, give: [.brick: 4], want: [.grain: 1])
        var fixture = state
        for index in fixture.players.indices {
            for resource in Resource.allCases {
                fixture.bank[resource, default: 0] += fixture.players[index].resources[resource, default: 0]
            }
            fixture.players[index].resources = [:]
        }
        if QALaunchFlag.threePlayerTable.isSet { fixture.players = Array(fixture.players.prefix(3)) }
        qaFundTradeHand(offer.want, for: human, in: &fixture)
        let rival = fixture.players.first { $0.id != bot && $0.id != human }?.id
        if competitionWinner != nil {
            guard let rival else { preconditionFailure("Competition QA requires another recipient") }
            qaFundTradeHand(offer.want, for: rival, in: &fixture)
        }
        // The policy mask permits proposals only when the proposer can keep
        // a card of an offered type. One Brick alone is affordable to apply
        // externally but is deliberately absent from a bot's action mask.
        var proposerHand = offer.give
        proposerHand[.brick, default: 0] += 1
        qaFundTradeHand(proposerHand, for: bot, in: &fixture)
        fixture.phase = .mainTurn(playerIndex: bot.index)
        let legal = RulesEngine.legalMoves(for: fixture, seat: bot)
        precondition(legal.contains(.proposeTrade(offer)) || RulesEngine.isPermittedComposedProposal(
            .proposeTrade(offer), by: bot, in: fixture, legal: legal), "QA proposal must pass the real policy action mask")
        let difficulty = competitionWinner == nil ? BotDifficulty.default
            : checkpointDocument?.activeMatch?.setup.difficulty ?? .default
        replaceStateForTesting(fixture, humanSeat: human, difficulty: difficulty)
        if let competitionWinner, let rival {
            session = qaCompetitionSession(offer: offer, winner: competitionWinner == .human ? human : rival, rival: rival)
        }
        guard let policyID = session.policies[bot]?.id else { preconditionFailure("Missing QA proposer policy") }
        session.policies[bot] = TradeAfterPauseQAPolicy(id: policyID, offer: offer)
        lastBotActionAt = nil
    }

    /// Search a bounded starting policy cursor against the seated policies.
    /// Only the proposer gets the existing one-proposal QA selector afterward;
    /// the funded rival retains its actual Traditional/Expert policy. A cold
    /// resume after the real proposal restores these same IDs and cursor.
    private func qaCompetitionSession(offer: TradeOffer, winner: PlayerID, rival: PlayerID) -> GameSession {
        let seedLimit = 64
        for seed in 0..<seedLimit {
            let baseline = GameSession(state: state, policies: session.policies, policySeed: UInt64(seed))
            var preview = baseline
            do {
                _ = try preview.commit(seat: offer.from, move: .proposeTrade(offer))
                let response = try preview.acceptTrade(offerID: offer.id, by: humanPlayer)
                precondition(preview.lastPolicyDecisions.contains {
                    $0.seat == rival && $0.move == .respondToTrade(offerID: offer.id, accept: true)
                }, "The actual seated rival must accept the funded QA offer")
                if response.actor == winner { return baseline }
            } catch { preconditionFailure("Competition QA preview rejected a legal transaction: \(error)") }
        }
        preconditionFailure("Competition QA did not find the requested winner within its seed limit")
    }

    private func qaTradeTapOffer(from bot: PlayerID, bundled: Bool) -> TradeOffer {
        let give: [Resource: Int] = bundled
            ? [.brick: 2, .lumber: 1, .wool: 1, .ore: 1] : [.brick: 1]
        return TradeOffer.enumerated(from: bot, give: give,
            want: [.grain: bundled ? 3 : 1])
    }

    private func qaFundTradeHand(_ counts: [Resource: Int], for player: PlayerID, in fixture: inout GameState) {
        for resource in Resource.allCases where counts[resource, default: 0] > 0 {
            let count = counts[resource, default: 0]
            precondition(fixture.bank[resource, default: 0] >= count, "QA cards must come from the bank")
            fixture.players[player.index].resources[resource] = count
            fixture.bank[resource, default: 0] -= count
        }
    }
}

/// Only the explicit QA baseline overrides selection. One affordable proposal
/// travels through the usual action mask and rules; after a response the
/// proposer ends its turn, avoiding a second synthetic interruption.
private struct TradeAfterPauseQAPolicy: Policy {
    let id: String
    let offer: TradeOffer

    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        let alreadyAnswered = observation.state.declinedTradeOffersThisTurn[offer.from]?.isEmpty == false
            || observation.state.tradesAcceptedThisTurn[offer.from, default: 0] > 0
        let canGive = offer.give.allSatisfy {
            observation.state.players[offer.from.index].resources[$0.key, default: 0] >= $0.value
        }
        return !alreadyAnswered && canGive ? .proposeTrade(offer) : .endTurn
    }
}
#endif
