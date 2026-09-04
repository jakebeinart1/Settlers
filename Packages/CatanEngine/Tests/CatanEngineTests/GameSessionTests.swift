import Testing
@testable import CatanEngine

/// Covers the loop that both the app and any headless harness now run.
///
/// This is the type that exists so there is only one of them. There used to be
/// two - the app drove bots from its view model with sleeps, a re-entrancy
/// guard, an action cap and its own trade resolution, while a harness called
/// the bot directly and executed none of that - which meant no measurement of
/// one told you anything reliable about the other. Everything asserted here is
/// therefore true of both by construction.

/// Always plays the first legal move. Deterministic, so a test can assert an
/// exact sequence without depending on any real policy's tuning.
private struct FirstLegalPolicy: Policy {
    let id = "first-legal"
    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        observation.legalMoves[0]
    }
}

/// Picks uniformly among legal moves. Unlike `FirstLegalPolicy` this actually
/// finishes games - the first legal move in `.mainTurn` is always `.endTurn`,
/// so a first-legal player never builds anything and never wins.
private struct RandomLegalPolicy: Policy {
    let id = "random-legal"
    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        observation.legalMoves.randomElement(using: &rng)!
    }
}

/// Always tries to end the turn. Used to reach `.mainTurn` states quickly.
private struct EndTurnPolicy: Policy {
    let id = "end-turn"
    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        observation.legalMoves.contains(.endTurn) ? .endTurn : observation.legalMoves[0]
    }
}

private func session(
    seed: UInt64 = 1,
    policies: [Int: any Policy]
) -> GameSession {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: seed)
    var mapped: [PlayerID: any Policy] = [:]
    for (index, policy) in policies { mapped[state.players[index].id] = policy }
    return GameSession(state: state, policies: mapped, policySeed: seed)
}

@Test func aSeatWithNoPolicyStopsTheLoop() throws {
    // Seat 0 is "the human" - no policy - so the session must hand control
    // back rather than playing for them.
    var game = session(policies: [1: FirstLegalPolicy(), 2: FirstLegalPolicy(), 3: FirstLegalPolicy()])

    #expect(game.nextActor() == .awaitingExternalSeat(game.state.players[0].id))
    #expect(try game.step() == nil, "a session must not move a seat it does not own")

    let stop = try game.run()
    #expect(stop == .awaitingExternalSeat(game.state.players[0].id))
}

@Test func anExternalMoveAdvancesTheSameGame() throws {
    var game = session(policies: [1: FirstLegalPolicy(), 2: FirstLegalPolicy(), 3: FirstLegalPolicy()])
    let human = game.state.players[0].id

    // Setup is a settlement AND its road from the same seat, so one move does
    // not hand control back - which is itself worth pinning.
    let settlement = try #require(RulesEngine.legalMoves(for: game.state, seat: human).first)
    let first = try game.applyExternal(settlement, by: human)
    #expect(first.actor == human)
    #expect(!first.events.isEmpty, "a placement reports itself")
    #expect(game.nextActor() == .awaitingExternalSeat(human), "the road is still owed")

    let road = try #require(RulesEngine.legalMoves(for: game.state, seat: human).first)
    _ = try game.applyExternal(road, by: human)
    #expect(game.nextActor() != .awaitingExternalSeat(human), "control passes once the road is placed")
}

@Test func aFullyOwnedGameRunsToCompletion() throws {
    var game = session(policies: [0: RandomLegalPolicy(), 1: RandomLegalPolicy(),
                                  2: RandomLegalPolicy(), 3: RandomLegalPolicy()])
    let stop = try game.run(limit: 20_000)

    guard case .gameOver(let winner) = stop else {
        Issue.record("a session owning every seat must reach a winner, got \(stop)")
        return
    }
    #expect(game.state.victoryPoints(for: winner) >= 10)
}

@Test func theRunawayBackstopForcesATurnToEnd() throws {
    // A policy that never ends its turn would otherwise loop forever. The cap
    // exists because bots really did deadlock re-proposing the same trade.
    struct NeverEnds: Policy {
        let id = "never-ends"
        func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
            observation.legalMoves.first { $0 != .endTurn } ?? .endTurn
        }
    }
    var game = session(policies: [0: NeverEnds(), 1: NeverEnds(), 2: NeverEnds(), 3: NeverEnds()])

    // Reaching `.mainTurn` at all requires setup to complete first.
    var guardCount = 0
    while case .seat = game.nextActor(), guardCount < 2_000 {
        if case .mainTurn = game.state.phase { break }
        _ = try game.step()
        guardCount += 1
    }
    guard case .mainTurn(let index) = game.state.phase else {
        Issue.record("never reached a main turn")
        return
    }

    let seat = game.state.players[index].id
    var actions = 0
    while actions <= GameSession.maxActionsPerTurn + 2 {
        guard let step = try game.step(), step.actor == seat else { break }
        actions += 1
        if case .endTurn = step.move { break }
    }
    #expect(actions <= GameSession.maxActionsPerTurn + 1,
            "a seat must be forced to end its turn rather than acting without bound")
}

@Test func discardingOffersOnlyTheActingSeatsOwnCombinations() throws {
    // The seat-scoped list is the whole reason `legalMoves(for:seat:)` exists:
    // the unscoped one returns every pending player's combinations together,
    // so a policy picking from it can choose a discard computed from somebody
    // else's hand, which `apply` then rejects.
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4)
    state.players[0].resources = [.brick: 8]
    state.players[1].resources = [.ore: 8]
    let pending: Set<PlayerID> = [state.players[0].id, state.players[1].id]
    state.phase = .discarding(pending: pending)

    let union = RulesEngine.legalMoves(for: state)
    let seatZero = RulesEngine.legalMoves(for: state, seat: state.players[0].id)

    #expect(seatZero.count < union.count, "the union must be wider than one seat's options")
    for move in seatZero {
        guard case .discard(let amounts) = move else {
            Issue.record("only discards are legal in this phase")
            continue
        }
        #expect(amounts.keys.allSatisfy { $0 == .brick },
                "seat 0 holds only brick, so every option must be brick")
    }
    // And a seat that owes nothing is offered nothing.
    #expect(RulesEngine.legalMoves(for: state, seat: state.players[2].id).isEmpty)
}

@Test func replacingTheStateResetsTurnBookkeeping() throws {
    var game = session(policies: [0: EndTurnPolicy(), 1: EndTurnPolicy(),
                                  2: EndTurnPolicy(), 3: EndTurnPolicy()])
    _ = try game.step()
    let fresh = GameSetup.newGame(board: BoardGenerator.standard(), seed: 99)
    game.replace(state: fresh)

    #expect(game.state.phase == fresh.phase)
    // The backstop counts actions within a turn; carrying a count from a
    // replaced game across would end the new game's first turn early.
    #expect(try game.step() != nil, "the replaced game must be playable immediately")
}

@Test func theSameSeedProducesTheSameSession() throws {
    func play(_ seed: UInt64) -> [String] {
        var game = session(seed: seed, policies: [0: RandomLegalPolicy(), 1: RandomLegalPolicy(),
                                                  2: RandomLegalPolicy(), 3: RandomLegalPolicy()])
        var moves: [String] = []
        for _ in 0..<400 {
            guard let step = try? game.step(), step.actor.index >= 0 else { break }
            moves.append("P\(step.actor.index)")
        }
        return moves
    }
    #expect(play(7) == play(7))
}

@Test func proposeTradeStopsBeingLegalAtTheTurnRetryLimit() {
    func legalIncludesProposeTrade(declinedCount: Int) -> Bool {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
        let seat = state.players[0].id
        state.players[0].resources = [.lumber: 5, .ore: 1]
        state.phase = .mainTurn(playerIndex: 0)
        state.declinedTradeOffersThisTurn[seat] = Array(
            repeating: TradeOffer(from: seat, give: [.lumber: 1], want: [.ore: 1]),
            count: declinedCount
        )
        var game = GameSession(state: state, policies: [seat: FirstLegalPolicy()], policySeed: 1)
        let decision = game.decideNextDetailed()
        return decision?.observation.legalMoves.contains {
            if case .proposeTrade = $0 { return true }
            return false
        } ?? false
    }

    #expect(legalIncludesProposeTrade(declinedCount: 0))
    #expect(!legalIncludesProposeTrade(declinedCount: RulesEngine.maxTradeProposalsPerTurn))
}
