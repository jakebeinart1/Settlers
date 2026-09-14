import Testing
import CatanEngine
@testable import CatanAI

/// The correctness gate for the route search.
///
/// The beam is the runtime path and it prunes, so on its own there is no way
/// to tell a good route from a plausible one. `planExactly` searches the same
/// graph without pruning, so on a problem small enough for it to finish, the
/// two must agree. That is a real gate; "the numbers look sensible" is not.
@Suite struct RoutePlannerTests {

    /// A truncated target keeps the exact search tractable while leaving the
    /// beam enough room to prune something it should not.
    private func expansion(target: Int, seed: UInt64 = 7) -> RouteExpansion {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        state.victoryPointTarget = state.rules.victoryPointTargets.lowerBound
        playOpeningPlacements(in: &state, seed: seed)

        let seat = state.players[0].id
        let ledger = PublicLedger.fromPositionAlone(state, observer: seat)
        var context = RouteContext.build(for: seat, in: state, ledger: ledger)
        context = context.retargeted(to: context.startingVictoryPoints + target)
        return RouteExpansion(
            context: context,
            startingHand: ClockModel.holding(from: ledger.belief(of: seat))
        )
    }

    @Test(arguments: [1, 2, 3])
    func beamMatchesTheExactSearchOnTruncatedTargets(extraPoints: Int) {
        let problem = expansion(target: extraPoints)
        let exact = RoutePlanner.planExactly(problem)
        let beam = RoutePlanner.planByBeam(problem)

        #expect(exact.expectedTurns < ClockModel.unreachable, "the oracle must actually solve this")
        #expect(
            abs(beam.expectedTurns - exact.expectedTurns) < 1e-6,
            "beam found \(beam.expectedTurns) turns, exact found \(exact.expectedTurns)"
        )
    }

    @Test func aRouteIsAlwaysAffordableInOrder() {
        let problem = expansion(target: 3)
        let route = RoutePlanner.planByBeam(problem)
        #expect(!route.purchases.isEmpty)

        // Replaying the route through the same transition function must never
        // hit an unavailable purchase: a plan that cannot be walked is not a
        // plan.
        var node = RouteNode.start(from: problem.context)
        for purchase in route.purchases {
            guard let next = problem.apply(purchase, to: node) else {
                Issue.record("route proposed \(purchase), which is not available at this point")
                return
            }
            node = next
        }
        #expect(node.victoryPoints >= Double(problem.context.victoryPointTarget))
    }

    @Test func planningIsAPureFunctionOfThePosition() {
        let first = RoutePlanner.planByBeam(expansion(target: 3))
        let second = RoutePlanner.planByBeam(expansion(target: 3))
        #expect(first == second, "two plans over the same position must be identical")
    }

    @Test func aSeatThatHasAlreadyWonNeedsNoRoute() {
        var problem = expansion(target: 3)
        problem = RouteExpansion(
            context: problem.context.retargeted(to: 0),
            startingHand: problem.startingHand
        )
        #expect(RoutePlanner.planByBeam(problem).expectedTurns == 0)
    }
}

/// Plays both setup rounds with the shipping heuristic so the planner has a
/// real position to work from. The planner's own placement is exercised
/// elsewhere; here the opening only needs to be legal and typical.
func playOpeningPlacements(in state: inout GameState, seed: UInt64) {
    var policies: [PlayerID: any Policy] = [:]
    for player in state.players {
        policies[player.id] = HeuristicPolicy(personality: .balanced, id: "heuristic-balanced")
    }
    var session = GameSession(state: state, policies: policies, policySeed: seed)
    while case .seat = session.nextActor() {
        switch session.state.phase {
        case .setupForward, .setupBackward:
            _ = try? session.step()
        default:
            state = session.state
            return
        }
    }
    state = session.state
}

extension RouteContext {
    /// The same context aimed at a different victory-point total.
    ///
    /// Only the exact planner needs this, to keep its frontier small enough to
    /// finish. Shrinking the target is the one knob that makes the same graph
    /// tractable without changing its shape, which is what makes the oracle
    /// comparable to the beam rather than a different problem.
    func retargeted(to target: Int) -> RouteContext {
        RouteContext(
            seat: seat,
            rules: rules,
            victoryPointTarget: target,
            startingRate: startingRate,
            startingVictoryPoints: startingVictoryPoints,
            bankRates: bankRates,
            settlementCandidates: settlementCandidates,
            cityCandidates: cityCandidates,
            settlementsRemaining: settlementsRemaining,
            citiesRemaining: citiesRemaining,
            roadsRemaining: roadsRemaining,
            roadLength: roadLength,
            knightsPlayed: knightsPlayed,
            holdsLongestRoad: holdsLongestRoad,
            holdsLargestArmy: holdsLargestArmy,
            longestRoadToBeat: longestRoadToBeat,
            largestArmyToBeat: largestArmyToBeat,
            devCardVictoryPointChance: devCardVictoryPointChance,
            devCardKnightChance: devCardKnightChance,
            devCardsAvailable: devCardsAvailable,
            devCardsHeld: devCardsHeld
        )
    }
}
