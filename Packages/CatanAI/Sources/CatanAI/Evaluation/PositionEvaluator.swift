import CatanEngine
import Foundation

/// Scores a position as it stands, from public information.
///
/// ## Why this exists beside the planner
/// `AdvantageModel` answers "how many turns until I win, against how many
/// until the leader does". That is the right *objective* and the wrong thing
/// to compute at every decision: the answer needs a route search, the search
/// has to be bounded to be affordable, and the bounded answer turned out to be
/// too coarse to order moves - the planner measured 1.0% against a 25% null
/// while its tests stayed green, because the quantity it decided on was not
/// the quantity the design specified.
///
/// This computes something cheaper and checkable instead: a weighted sum of
/// features of the board as it is. No search, no horizon, no tail estimate. It
/// is the same shape as the evaluation under every strong Catan engine, and it
/// is cheap enough to sit underneath a real search rather than replacing one.
///
/// ## Relative, by construction
/// `evaluate` returns this seat's standing minus the strongest rival's, scaled
/// by `weights.rival`. A move that helps this seat and the leader equally
/// scores near zero; a move that helps this seat less than it helps the leader
/// scores negative. That is Jake's rule about net position, expressed as the
/// quantity being maximised rather than as a rule applied afterwards.
///
/// ## Public information only
/// Opponent hands are read from the `PublicLedger`, never from `GameState`.
/// The one asymmetry is deliberate and correct: this seat scores its own
/// hidden victory-point cards, because a player does know their own hand.
public struct PositionEvaluator: Sendable {

    public let seat: PlayerID
    public let weights: EvaluationWeights

    public init(seat: PlayerID, weights: EvaluationWeights = .default) {
        self.seat = seat
        self.weights = weights
    }

    /// This seat's standing less the strongest rival's.
    ///
    /// The caller is expected to have reconciled the ledger's view of this
    /// seat's own hand; `EvaluationPolicy` does it once per decision rather
    /// than once per candidate.
    public func evaluate(_ state: GameState, ledger: PublicLedger) -> Double {
        let board = BoardIndex(state: state)
        let mine = standing(of: seat, in: state, ledger: ledger, board: board)

        // Sorted so the maximum is taken over a fixed order. A tie between two
        // rivals must resolve the same way in every process.
        let rivals = state.players
            .map(\.id)
            .filter { $0 != seat }
            .sorted()
            .map { standing(of: $0, in: state, ledger: ledger, board: board) }

        guard let strongest = rivals.max() else { return mine }
        return mine - weights.rival * strongest
    }

    /// One seat's standing, on its own.
    ///
    /// Exposed for diagnostics and tests: a decision trace wants both halves
    /// of the difference, not just the difference.
    public func standing(
        of player: PlayerID,
        in state: GameState,
        ledger: PublicLedger,
        board: BoardIndex
    ) -> Double {
        let points = victoryPoints(of: player, in: state)
        if points >= state.victoryPointTarget { return weights.winning }

        let rate = ProductionModel.rate(for: player, in: state, tiles: board.tiles)
        let economy = economyTerms(of: player, rate: rate, in: state, board: board)
        let hand = handTerms(of: player, rate: rate, in: state, ledger: ledger)
        let bonuses = bonusTerms(of: player, in: state)
        return Double(points) * weights.victoryPoint + economy + hand + bonuses
    }

    // MARK: - Victory points

    /// Public points for a rival; own points including held victory-point
    /// cards for this seat, which a player legitimately knows about.
    private func victoryPoints(of player: PlayerID, in state: GameState) -> Int {
        player == seat ? state.victoryPoints(for: player) : state.publicVictoryPoints(for: player)
    }

    // MARK: - Economy

    /// Production, variety, room to expand, and the best expansion available.
    private func economyTerms(
        of player: PlayerID,
        rate: ProductionRate,
        in state: GameState,
        board: BoardIndex
    ) -> Double {
        let distinct = Resource.allCases.reduce(0.0) { $0 + (rate[$1] > 0 ? 1 : 0) }
        let sites = board.buildableSites(for: player, in: state)

        let bestGain = sites
            .map { ProductionModel.rateGain(at: $0, yield: 1, in: state, tiles: board.tiles).total }
            .max() ?? 0

        return rate.total * weights.production
            + distinct * weights.variety
            + bestGain * weights.expansion
            + bestApproach(for: player, in: state, board: board) * weights.approach
            + Double(sites.count) * weights.buildableSites
    }

    /// Roads beyond the current network the approach term looks, and what each
    /// one costs. Four, because a saturated Expanded board late in a 25-point
    /// game can leave the nearest free site that far out, and a site the term
    /// cannot see is a site no move is ever scored as approaching. Halving per
    /// road keeps an adjacent site worth more than any distant one while still
    /// making every step toward one worth taking.
    private static let approachRoadLimit = 4
    private static let approachDiscountPerRoad = 0.5

    /// The production of the best site within reach of a few more roads,
    /// discounted by how many. Zero when nothing is reachable.
    private func bestApproach(for player: PlayerID, in state: GameState, board: BoardIndex) -> Double {
        board.approachableSites(for: player, in: state, limit: Self.approachRoadLimit)
            .map { site in
                ProductionModel.rateGain(at: site.vertex, yield: 1, in: state, tiles: board.tiles).total
                    * pow(Self.approachDiscountPerRoad, Double(site.roads))
            }
            .max() ?? 0
    }

    // MARK: - Hand

    /// What the seat is holding, and how usable it is.
    ///
    /// ## Why cards past the discard threshold have their own weight
    /// Long Expanded games once stalled with four Expert bots holding 22, 22,
    /// 17 and 23 cards and nine settlements unbuilt each. A card over the
    /// threshold netted +0.008 at the fitted weights, so hoarding scored as
    /// correct. Crediting nothing past the threshold ended that stall.
    ///
    /// It also cost Classic **8.7 points**: 57.5% with that cap against 66.2%
    /// without it, same 1,248 held-out games. And removing it everywhere
    /// brought the Expanded stall back, 2 games in 40, even at the hand-set
    /// weights. The two modes want opposite answers, so the answer is a
    /// weight rather than a shape: `handCardOverflow` is the credit per card
    /// past the threshold, equal to `handCard` in Classic and zero in
    /// Expanded, where games run long enough for a large hand to be a trap.
    ///
    /// `handSynergy` is the part that stops a bot hoarding: a hand two ore
    /// short of a city scores better than the same number of cards spread
    /// across resources nothing needs.
    private func handTerms(
        of player: PlayerID,
        rate: ProductionRate,
        in state: GameState,
        ledger: PublicLedger
    ) -> Double {
        let belief = ledger.belief(of: player)
        let holding = ClockModel.holding(from: belief)
        let size = Double(belief.maxTotal)
        let threshold = Double(state.rules.discardThreshold)
        let overflow = max(0, size - threshold)

        return synergy(of: holding) * weights.handSynergy
            + min(size, threshold) * weights.handCard
            + overflow * weights.handCardOverflow
            + overflow * weights.discardExposure
            + expectedSevenLoss(hand: size, rate: rate.total, state: state) * weights.sevenLoss
            + Double(belief.devCardCount) * weights.devCardHeld
    }

    /// Cards a seat holding `hand` expects to lose to sevens before its next
    /// turn, counting what it will collect on the rolls in between.
    ///
    /// One roll per seat until this seat rolls again, each a seven one time in
    /// six. On the k-th roll the hand has grown by k rolls of production, and
    /// a seven then takes half of it if it is over the threshold. Approximate
    /// in one direction only: it ignores that an earlier seven would already
    /// have halved the hand, so it slightly overstates the loss, which errs
    /// toward spending rather than hoarding.
    private func expectedSevenLoss(hand: Double, rate: Double, state: GameState) -> Double {
        let threshold = Double(state.rules.discardThreshold)
        var loss = 0.0
        for roll in 0..<state.players.count {
            let held = (hand + Double(roll) * rate).rounded(.down)
            guard held > threshold else { continue }
            loss += Self.sevenChance * (held / 2).rounded(.down)
        }
        return loss
    }

    private static let sevenChance = 6.0 / 36.0

    /// How close `holding` is to affording the next settlement and the next
    /// city, on a 0...1 scale where 1 is "both affordable now".
    ///
    /// Only the two purchases that carry points are counted. A road is cheap
    /// enough that closeness to one says nothing.
    private func synergy(of holding: [Resource: Double]) -> Double {
        func closeness(to cost: [Resource: Int]) -> Double {
            var required = 0.0
            var short = 0.0
            for resource in Resource.allCases {
                let need = Double(cost[resource] ?? 0)
                guard need > 0 else { continue }
                required += need
                short += max(0, need - (holding[resource] ?? 0))
            }
            guard required > 0 else { return 1 }
            return 1 - short / required
        }
        return (closeness(to: Building.settlementCost) + closeness(to: Building.cityCost)) / 2
    }

    // MARK: - Bonuses

    /// Knights, road length, and ports - the standing progress toward the two
    /// bonuses, credited before either is actually held.
    ///
    /// The planner credited neither, which is why it bought 0.6 development
    /// cards a game against the heuristic's 6.9 and played 0.3 knights against
    /// 3.3. Progress toward a two- or four-point bonus has to be visible to
    /// the quantity being maximised, or the route to it is never taken.
    private func bonusTerms(of player: PlayerID, in state: GameState) -> Double {
        guard let owner = state.players.first(where: { $0.id == player }) else { return 0 }
        let length = LongestRoad.length(for: owner, in: state)
        let ports = portCount(for: owner, in: state)

        return Double(owner.playedKnights) * weights.knight
            + Double(length) * weights.roadLength
            + Double(ports) * weights.port
    }

    private func portCount(for owner: Player, in state: GameState) -> Int {
        let occupied = owner.settlements.union(owner.cities)
        return state.board.ports.count { occupied.contains($0.vertexA) || occupied.contains($0.vertexB) }
    }
}
