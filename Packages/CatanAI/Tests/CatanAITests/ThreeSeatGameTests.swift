import Testing
import CatanEngine
@testable import CatanAI

/// A three-seat game must actually finish, played by the bots that ship.
///
/// The engine suite can only check that a three-seat game is *structurally*
/// sound - setup visits three chairs, turns cycle 0-1-2 - because random-legal
/// play almost never assembles ten victory points on purpose and would time
/// out at any table size. Whether the game reaches a winner is a question
/// about the bots, so it belongs here, where real policies play.

@Test func threeSeatGamesReachAWinner() throws {
    var finished = 0
    for seed: UInt64 in [101, 102, 103, 104] {
        let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed),
                                      seed: seed, playerCount: 3)
        #expect(state.players.count == 3)

        var seats: [PlayerID: any Policy] = [:]
        for (index, player) in state.players.enumerated() {
            let personality: BotPersonality = [.balanced, .aggressive, .cautious][index]
            seats[player.id] = HeuristicPolicy(personality: personality, id: "heuristic-\(personality)")
        }
        var session = GameSession(state: state, policies: seats, policySeed: seed &* 31 &+ 7)
        // `try`, not `try?`. A rules error thrown out of `run` is a different
        // failure from "the bots did not assemble ten points in time", and
        // swallowing it reported the first as the second - so a genuine engine
        // break on a three-seat table would have read as "3/4 games finished".
        if case .gameOver(let winner) = try session.run(limit: 20_000) {
            finished += 1
            #expect(session.state.victoryPoints(for: winner) >= session.state.victoryPointTarget)
            #expect(winner.index < 3, "the winner must be a seat that exists")
        }
    }
    #expect(finished == 4, "three-seat games must reach a winner; \(finished)/4 did")
}

@Test func aShortGameEndsSooner() throws {
    // A shorter target ends a real game sooner. Note carefully what this does
    // NOT show: the bots do not yet reason about the target, so an 8-point
    // game's trace is a prefix of the 12-point one - identical play, stopped
    // earlier. This asserts the engine's win check reaches a bot-driven game,
    // which is worth pinning; making the BOTS value the target is deferred
    // (see A4.4 in the acceptance-criteria spec) because it is a
    // bot-strength change needing a measured evaluation, not a settings one.
    func moves(target: Int) throws -> Int {
        let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 7),
                                      seed: 7, victoryPointTarget: target)
        var seats: [PlayerID: any Policy] = [:]
        for player in state.players {
            seats[player.id] = HeuristicPolicy(personality: .balanced, id: "heuristic-balanced")
        }
        var session = GameSession(state: state, policies: seats, policySeed: 7)
        var count = 0
        // `try`, same reason as above: a rules error must fail the test rather
        // than quietly end the game and be read as a shorter one.
        while case .seat = session.nextActor(), count < 20_000 {
            guard try session.step() != nil else { break }
            count += 1
        }
        return count
    }
    let short = try moves(target: 8)
    let long = try moves(target: 12)
    #expect(short < long, "an 8-point game (\(short) moves) should finish before a 12-point one (\(long))")
}
