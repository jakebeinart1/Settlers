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

/// Plays `games` games with `hero` at each seat in turn, returning how many it
/// won. Rotating the seat matters: seat order confers a real advantage in
/// Catan, so a single-seat measurement cannot separate skill from turn order.
private func winRate(hero: @autoclosure () -> any Policy, foil: @autoclosure () -> any Policy,
                     games: Int) -> (wins: Int, played: Int) {
    var wins = 0
    for offset in 0..<games {
        let seat = offset % 4
        var policies: [Int: any Policy] = [:]
        for index in 0..<4 { policies[index] = index == seat ? hero() : foil() }
        let winner = playToCompletion(seed: UInt64(7000 + offset), policies: policies)
        if winner?.index == seat { wins += 1 }
    }
    // Games that hit the move cap count as losses rather than being dropped:
    // failing to finish is a property of the policy being measured, and
    // discarding them would flatter whichever side stalls more.
    return (wins, games)
}

/// The strength ladder: random < greedy < heuristic.
///
/// This is the measurement `GreedyPolicy` was added to make possible. Against
/// `RandomPolicy` the shipped heuristic wins 200 games out of 200, and a
/// statistic pinned at 100% cannot move - so it could no longer answer the one
/// question an anchor exists to answer, which is whether a change made the bot
/// better or worse.
///
/// Measured over 40 games per arm with the seat rotated:
///
/// | arm | win rate |
/// |---|---|
/// | greedy vs 3x random | 55.0% |
/// | heuristic vs 3x greedy | 90.0% |
/// | heuristic vs 3x random | 100.0% (saturated) |
/// | random vs 3x greedy | 7.5% |
///
/// The bars below sit far under those figures, on purpose. This test is here
/// to catch the ladder *inverting* - a change that makes the heuristic worse
/// than a policy that cannot trade is a serious regression - not to pin a
/// number that honest tuning should be free to move.
@Test func theGreedyAnchorSitsBetweenRandomAndTheHeuristic() {
    let againstRandom = winRate(hero: GreedyPolicy(), foil: RandomPolicy(), games: 12)
    let randomDetail = "greedy won \(againstRandom.wins)/\(againstRandom.played) against random; "
        + "25% is the no-skill null, so at or below it means the anchor has stopped playing Catan"
    #expect(againstRandom.wins >= 4, "\(randomDetail)")

    let heuristicAgainstGreedy = winRate(
        hero: HeuristicPolicy(personality: .balanced, id: "heuristic-balanced"),
        foil: GreedyPolicy(), games: 12)
    let greedyDetail = "the heuristic won \(heuristicAgainstGreedy.wins)/"
        + "\(heuristicAgainstGreedy.played) against greedy; it must stay clearly ahead of a "
        + "policy that never trades"
    #expect(heuristicAgainstGreedy.wins >= 6, "\(greedyDetail)")
}

/// The anchor must finish the games it plays, which the old one does not.
///
/// Four random seats reach the 3,000-move cap in 15 games out of 20 - random
/// players almost never assemble ten victory points on purpose - so most of
/// what a random-anchored arm measures is a timeout rather than a loss. Four
/// greedy seats finished 20 out of 20, median 368 moves. An anchor whose games
/// mostly do not end is not measuring play.
@Test func greedySeatsActuallyFinishTheirGames() {
    var finished = 0
    for seed: UInt64 in [11, 12, 13, 14, 15, 16] {
        let policies = (0..<4).reduce(into: [Int: any Policy]()) { $0[$1] = GreedyPolicy() }
        if playToCompletion(seed: seed, policies: policies) != nil { finished += 1 }
    }
    #expect(finished == 6, "greedy games must reach a winner; \(finished)/6 did")
}

@Test func greedyRefusesEveryTradeItIsOffered() {
    // Withholding trade is what keeps this policy below the heuristic, so it
    // is a property worth pinning rather than an incidental detail.
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 3)
    let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.brick: 1], want: [.ore: 1])
    let moves: [GameMove] = [
        .respondToTrade(offerID: offer.id, accept: true),
        .respondToTrade(offerID: offer.id, accept: false),
        .endTurn,
    ]
    var rng = RandomSource(seed: 1)
    let chosen = GreedyPolicy().decide(
        GameObservation(seat: state.players[0].id, state: state, legalMoves: moves), rng: &rng)
    #expect(chosen == .respondToTrade(offerID: offer.id, accept: false))
}
