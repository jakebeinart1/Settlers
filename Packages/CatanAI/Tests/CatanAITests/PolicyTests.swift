import Testing
import CatanEngine
@testable import CatanAI

/// Covers the two policies and, more importantly, establishes the first
/// absolute statement about how good the shipped bot is.
///
/// A bot-vs-bot win rate is 25% by construction at a four-seat table and says
/// nothing at all about strength - which is why every "the bots got better"
/// claim before this had nothing to stand on. `RandomPolicy` is the floor that
/// makes "better" mean something.

private func playToCompletion(
    seed: UInt64,
    policies: [Int: any Policy],
    limit: Int = 20_000
) -> PlayerID? {
    let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
    var mapped: [PlayerID: any Policy] = [:]
    for (index, policy) in policies { mapped[state.players[index].id] = policy }
    var session = GameSession(state: state, policies: mapped, policySeed: seed &* 31 &+ 7)
    guard case .gameOver(let winner) = (try? session.run(limit: limit)) else { return nil }
    return winner
}

@Test func randomPolicyOnlyEverPlaysLegalMoves() throws {
    // It picks from `GameObservation.legalMoves` and nothing else, so this is
    // really a test that the session hands it a correct action list - which it
    // did not, before `legalMoves(for:seat:)`: the unscoped list is a union
    // across pending players in `.discarding`, and applying another seat's
    // discard threw immediately.
    for seed: UInt64 in [1, 2, 3] {
        let winner = playToCompletion(seed: seed, policies: [
            0: RandomPolicy(), 1: RandomPolicy(), 2: RandomPolicy(), 3: RandomPolicy(),
        ])
        #expect(winner != nil, "seed \(seed): random-legal play must reach a winner without an illegal move")
    }
}

@Test func heuristicPolicyCarriesAnIdentifierNamingItsPersonality() {
    // Two heuristic seats with different personalities are genuinely different
    // opponents, so an evaluation record that calls both "heuristic" cannot be
    // interpreted afterwards.
    #expect(HeuristicPolicy(personality: .aggressive, id: "heuristic-aggressive").id == "heuristic-aggressive")
    #expect(RandomPolicy().id == "random")
}

/// The anchor measurement: one heuristic bot against three that play legally
/// and think not at all.
///
/// Seat is rotated so a seat advantage cannot be mistaken for skill. The bar
/// is deliberately far below the observed result - measured at 200/200 across
/// all four seats - because this test exists to catch the heuristic becoming
/// *broken*, not to pin a number that honest tuning might move.
@Test func theHeuristicBotBeatsRandomPlayFromEverySeat() {
    var wins = 0
    var played = 0
    for offset in 0..<12 {
        let seat = offset % 4
        var policies: [Int: any Policy] = [:]
        for index in 0..<4 {
            policies[index] = index == seat
                ? HeuristicPolicy(personality: .balanced, id: "heuristic-balanced")
                : RandomPolicy()
        }
        guard let winner = playToCompletion(seed: UInt64(4000 + offset), policies: policies) else { continue }
        played += 1
        if winner.index == seat { wins += 1 }
    }

    #expect(played == 12, "every game must finish")
    let detail = "the heuristic won \(wins)/\(played) against random play; 25% is the no-skill "
        + "null, so anything near it means the heuristic has stopped working"
    #expect(wins >= 10, "\(detail)")
}
