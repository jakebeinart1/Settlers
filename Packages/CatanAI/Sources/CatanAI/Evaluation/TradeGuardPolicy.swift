import CatanEngine

/// The timing Expert, refusing trades that would let a rival build at once.
///
/// ## Why
/// Jake, 2026-10-25: "just reject those trades if the bot would know that it
/// would be more helpful for the opponent. But like no data leaking." On the
/// ladder's 63 games, 60 of the 140 offers Experts accepted from humans were
/// followed by a settlement or city that same turn.
///
/// ## What it reads
/// Public information only: the proposer's hand as this seat's `PublicLedger`
/// believes it, public points, and how many development cards they hold.
/// Never their real cards.
///
/// ## What it is worth
/// Against three timing Experts, held-out seeds 1110000-1110311 (1,248 games):
/// 25.6%, 90% bootstrap [24.0, 27.3]: no loss, no confirmed gain, among bots.
/// Against the ladder's real trades it refuses 75 of the 140, 37 of the 60 that
/// fed a build. Other rules screened alongside it (robbing the leader, pips
/// openings, refusing every leader trade) are on branch `exp/ladder-arms`; see
/// docs/AI_summaries/2026-10-25-ladder-games.md.
public struct TradeGuardPolicy: LedgerAwarePolicy {
    /// The brain `ExpertRevision.timingTradeGuardV1` names. Frozen: a change is a new revision.
    public static let v1 = TradeGuardPolicy()

    public let id = ExpertRevision.timingTradeGuardV1.policyID
    private let timing = TimingPolicy.oneAheadV1

    /// Cards a believed hand may be short of a building, in total, and still
    /// count as affording it: the ledger knows a rival's hand only in part.
    /// On the 140 ladder trades: half a card refused 30 (19 of the 60 that fed
    /// a build), one card 75 (37), two cards 102 (44).
    static let buildSlack = 1.0

    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        decide(observation, ledger: .fromPositionAlone(observation.state, observer: observation.seat), rng: &rng)
    }

    public func decide(_ observation: GameObservation, ledger: PublicLedger, rng: inout RandomSource) -> GameMove {
        let move = timing.decide(observation, ledger: ledger, rng: &rng)
        guard case .respondToTrade(let id, true) = move,
              refuses(move, seat: observation.seat, state: observation.state, ledger: ledger) else { return move }
        return .respondToTrade(offerID: id, accept: false)
    }

    /// Whether the guard turns down `accept`: some rival is level with this
    /// seat or ahead (hidden points estimated), the proposer is within a point
    /// of it, and their believed hand after the trade covers a settlement or a city.
    public func refuses(_ accept: GameMove, seat: PlayerID, state: GameState, ledger: PublicLedger) -> Bool {
        guard case .respondToTrade(let id, true) = accept,
              let offer = state.pendingTradeOffers.first(where: { $0.id == id }) else { return false }
        let mine = Double(state.victoryPoints(for: seat))
        let threats = state.players.map(\.id).filter { $0 != seat }.map { Self.threat(of: $0, for: seat, in: state, ledger: ledger) }
        return (threats.max() ?? 0) >= mine
            && Self.threat(of: offer.from, for: seat, in: state, ledger: ledger) >= mine - 1
            && Self.enablesBuilding(offer, ledger: ledger)
    }

    /// `rival`'s public points plus each unplayed development card times the
    /// share of the cards `seat` has not seen that are victory points.
    static func threat(of rival: PlayerID, for seat: PlayerID, in state: GameState, ledger: PublicLedger) -> Double {
        let printed = state.rules.devCardDeck[.victoryPoint] ?? 0
        let mineHidden = state.players[seat.index].devCards.filter { $0 == .victoryPoint }.count
        let others = state.players.map(\.id).filter { $0 != seat }
        let unseen = state.devCardDeck.count + others.map { ledger.belief(of: $0).devCardCount }.reduce(0, +)
        let share = unseen == 0 ? 0 : Double(max(0, printed - mineHidden)) / Double(unseen)
        return Double(state.publicVictoryPoints(for: rival)) + share * Double(ledger.belief(of: rival).devCardCount)
    }

    /// Whether the proposer's believed hand, after `offer`, covers a settlement or a city.
    static func enablesBuilding(_ offer: TradeOffer, ledger: PublicLedger) -> Bool {
        var holding = believedHolding(from: ledger.belief(of: offer.from))
        for resource in Resource.allCases {
            holding[resource, default: 0] += Double(offer.want[resource] ?? 0) - Double(offer.give[resource] ?? 0)
        }
        func covers(_ cost: [Resource: Int]) -> Bool {
            Resource.allCases.reduce(0.0) { $0 + max(0, Double(cost[$1] ?? 0) - holding[$1, default: 0]) } <= buildSlack
        }
        return covers(Building.settlementCost) || covers(Building.cityCost)
    }
}
