import CatanEngine
import Testing
@testable import CatanAI

/// Plays the two setup rounds with four balanced heuristics and hands back the
/// position at the start of the first main turn.
///
/// Shared by every suite that needs a *plausible* mid-game board rather than an
/// empty one. It lived in `RoutePlannerTests` until the route beam was deleted;
/// it is here now because four suites depend on it and none of them own it.
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
