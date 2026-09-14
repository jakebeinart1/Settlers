import CatanEngine

/// The planner's objective.
///
/// `advantage` is the whole design in one expression: not how fast this seat
/// can win, but how much faster than the seat closest to winning. Every
/// behaviour the planner is meant to have follows from that difference rather
/// than from a rule written for it.
///
/// - A trade that saves this seat one turn and the leader two scores negative.
/// - The same trade offered to a trailing seat scores positive.
/// - A road that costs a turn but costs an opponent three beats a city that
///   saves two and costs nobody anything.
///
/// A bot that maximises its own clock instead builds the city, which is the
/// behaviour this replaces.
public enum AdvantageModel {

    /// Expected turns for `seat` to reach the target, including the standing
    /// cost of being robbed while holding a large hand.
    public static func clock(
        for seat: PlayerID,
        in state: GameState,
        ledger: PublicLedger,
        settings: RoutePlannerSettings = .default,
        contest: RouteContext.ContestPricing = .discountContestedSites,
        rivalDistances: [[VertexID: Int]]? = nil
    ) -> Double {
        let context = RouteContext.build(
            for: seat, in: state, ledger: ledger, contest: contest, rivalDistances: rivalDistances
        )
        let belief = ledger.belief(of: seat)
        let expansion = RouteExpansion(context: context, startingHand: ClockModel.holding(from: belief))

        // A bounded estimate, not a full plan: this is called for every seat
        // a candidate move can affect, for every candidate. See
        // `RoutePlanner.estimate`.
        let turns = RoutePlanner.estimate(expansion, settings: settings)
        guard turns < ClockModel.unreachable else { return ClockModel.unreachable }

        let seven = ClockModel.sevenCost(
            handSize: belief.maxTotal,
            rate: context.startingRate,
            rules: state.rules
        )
        return turns + seven
    }

    /// The seat's committed route - the full-depth plan, not the bounded
    /// estimate the clock uses.
    ///
    /// Not consulted during move selection, which reaches the same conclusion
    /// through the clock. It exists so a route can be inspected, logged and
    /// tested as the object the design says it is.
    public static func route(
        for seat: PlayerID,
        in state: GameState,
        ledger: PublicLedger,
        settings: RoutePlannerSettings = .default
    ) -> Route {
        let context = RouteContext.build(for: seat, in: state, ledger: ledger)
        let expansion = RouteExpansion(
            context: context, startingHand: ClockModel.holding(from: ledger.belief(of: seat))
        )
        return RoutePlanner.planByBeam(expansion, settings: settings)
    }

    /// Every seat's clock, in seat order.
    public static func clocks(
        in state: GameState,
        ledger: PublicLedger,
        settings: RoutePlannerSettings = .default,
        contest: RouteContext.ContestPricing = .discountContestedSites,
        rivalDistances: [[VertexID: Int]]? = nil
    ) -> [PlayerID: Double] {
        var result: [PlayerID: Double] = [:]
        for player in state.players.sorted(by: { $0.id < $1.id }) {
            result[player.id] = clock(
                for: player.id, in: state, ledger: ledger, settings: settings,
                contest: contest, rivalDistances: rivalDistances
            )
        }
        return result
    }

    /// How many turns ahead of the nearest rival `seat` is. Higher is better;
    /// negative means someone is expected to win first.
    ///
    /// Both terms are capped at `ClockModel.unreachable`, so a table where
    /// nobody can reach the target yields zero rather than a `NaN` from
    /// subtracting one infinity from another.
    public static func advantage(of seat: PlayerID, given clocks: [PlayerID: Double]) -> Double {
        let mine = min(clocks[seat] ?? ClockModel.unreachable, ClockModel.unreachable)
        let best = clocks
            .filter { $0.key != seat }
            .values
            .min() ?? ClockModel.unreachable
        return min(best, ClockModel.unreachable) - mine
    }

    /// Convenience: compute every clock and return `seat`'s advantage.
    public static func advantage(
        of seat: PlayerID,
        in state: GameState,
        ledger: PublicLedger,
        settings: RoutePlannerSettings = .default
    ) -> Double {
        advantage(of: seat, given: clocks(in: state, ledger: ledger, settings: settings))
    }

    /// The seat expected to win soonest, excluding `seat`. The planner's
    /// reference opponent for robber, blocking and trade decisions.
    public static func leadingRival(of seat: PlayerID, given clocks: [PlayerID: Double]) -> PlayerID? {
        clocks
            .filter { $0.key != seat }
            .sorted { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }
            .first?
            .key
    }
}
