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
) throws -> PlayerID? {
    let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
    var mapped: [PlayerID: any Policy] = [:]
    for (index, policy) in policies { mapped[state.players[index].id] = policy }
    var session = GameSession(state: state, policies: mapped, policySeed: seed &* 31 &+ 7)
    guard case .gameOver(let winner) = try session.run(limit: limit) else { return nil }
    return winner
}

@Test func randomPolicyOnlyEverPlaysLegalMoves() throws {
    // It picks from `GameObservation.legalMoves` and nothing else, so this is
    // really a test that the session hands it a correct action list - which it
    // did not, before `legalMoves(for:seat:)`: the unscoped list is a union
    // across pending players in `.discarding`, and applying another seat's
    // discard threw immediately.
    for seed: UInt64 in [1, 2, 3] {
        let winner = try playToCompletion(seed: seed, policies: [
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

@Test func standardDifficultyIsExactlyTheShippingHeuristic() {
    let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 91), seed: 91)
    let seat = state.players[0].id
    let observation = GameObservation(
        seat: seat,
        state: state,
        legalMoves: RulesEngine.legalMoves(for: state, seat: seat)
    )
    var expectedRNG = RandomSource(seed: 117)
    var actualRNG = expectedRNG

    let expected = HeuristicPolicy(personality: .aggressive, id: "shipping").decide(
        observation, rng: &expectedRNG)
    let actual = DifficultyPolicy(
        personality: .aggressive,
        difficulty: .standard,
        id: "standard-aggressive"
    ).decide(observation, rng: &actualRNG)

    #expect(actual == expected)
    #expect(actualRNG == expectedRNG, "Standard must not add an RNG draw or silently change replay")
}

@Test func standardDifficultyPreservesAWholeShippingGameTrajectory() throws {
    let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 92), seed: 92)
    let shipping = Dictionary(uniqueKeysWithValues: state.players.map {
        ($0.id, HeuristicPolicy(personality: .balanced, id: "shipping") as any Policy)
    })
    let standard = Dictionary(uniqueKeysWithValues: state.players.map {
        ($0.id, DifficultyPolicy(
            personality: .balanced,
            difficulty: .standard,
            id: "standard-balanced"
        ) as any Policy)
    })
    var expected = GameSession(state: state, policies: shipping, policySeed: 92 &* 31 &+ 7)
    var actual = GameSession(state: state, policies: standard, policySeed: 92 &* 31 &+ 7)

    for _ in 0..<3_000 {
        #expect(actual.nextActor() == expected.nextActor())
        guard case .seat = expected.nextActor() else {
            #expect(actual.state == expected.state)
            #expect(actual.policyRNG == expected.policyRNG)
            return
        }
        let expectedCandidate = expected.decideNext()
        let actualCandidate = actual.decideNext()
        let expectedDecision = try #require(expectedCandidate)
        let actualDecision = try #require(actualCandidate)
        #expect(actualDecision.seat == expectedDecision.seat)
        #expect(actualDecision.move == expectedDecision.move)
        _ = try expected.commit(seat: expectedDecision.seat, move: expectedDecision.move)
        _ = try actual.commit(seat: actualDecision.seat, move: actualDecision.move)
        #expect(actual.state == expected.state)
        #expect(actual.policyRNG == expected.policyRNG)
    }

    Issue.record("shipping and Standard trajectories did not finish within 3,000 moves")
}

@Test func easyDifficultyMakesPlausibleSpatialMistakesWithoutChangingMoveKind() {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 12)
    let seat = state.players[0].id
    let legal = RulesEngine.legalMoves(for: state, seat: seat)
    let observation = GameObservation(seat: seat, state: state, legalMoves: legal)
    let standard = DifficultyPolicy(
        personality: .balanced,
        difficulty: .standard,
        id: "standard-balanced"
    )
    let easy = DifficultyPolicy(
        personality: .balanced,
        difficulty: .easy,
        id: "easy-balanced"
    )
    var sawDifferentTarget = false

    for seed: UInt64 in 1...32 {
        var standardRNG = RandomSource(seed: seed)
        var easyRNG = RandomSource(seed: seed)
        let preferred = standard.decide(observation, rng: &standardRNG)
        let chosen = easy.decide(observation, rng: &easyRNG)

        #expect(legal.contains(chosen))
        guard case .placeInitialSettlement(let chosenVertex) = chosen else {
            Issue.record("Easy changed the action category instead of softening the target")
            continue
        }
        if chosen != preferred {
            sawDifferentTarget = true
            guard case .placeInitialSettlement(let preferredVertex) = preferred else {
                Issue.record("Standard returned an unexpected setup move")
                continue
            }
            let preferredScore = PlacementHeuristics.score(vertex: preferredVertex, board: state.board)
            let chosenScore = PlacementHeuristics.score(vertex: chosenVertex, board: state.board)
            #expect(chosenScore < preferredScore, "An Easy lapse must be a real, bounded downgrade")
            #expect(
                chosenScore <= preferredScore * 0.80,
                "Easy should not disguise a near-tied placement as a meaningful difficulty gap"
            )
        }
    }

    #expect(sawDifferentTarget, "Easy never exercised its bounded spatial lapse")
}

@Test func easyDifficultyKeepsTheHeuristicsRoadPlan() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 12)
    let seat = state.players[0].id
    let settlementObservation = GameObservation(
        seat: seat,
        state: state,
        legalMoves: RulesEngine.legalMoves(for: state, seat: seat)
    )
    var setupRNG = RandomSource(seed: 8)
    let settlement = HeuristicPolicy(personality: .balanced, id: "shipping").decide(
        settlementObservation,
        rng: &setupRNG
    )
    _ = try RulesEngine.apply(settlement, by: seat, to: &state)
    let roadObservation = GameObservation(
        seat: seat,
        state: state,
        legalMoves: RulesEngine.legalMoves(for: state, seat: seat)
    )

    for seed: UInt64 in 1...32 {
        var expectedRNG = RandomSource(seed: seed)
        var actualRNG = expectedRNG
        let expected = HeuristicPolicy(personality: .balanced, id: "shipping").decide(
            roadObservation,
            rng: &expectedRNG
        )
        let actual = DifficultyPolicy(
            personality: .balanced,
            difficulty: .easy,
            id: "easy-balanced"
        ).decide(roadObservation, rng: &actualRNG)

        #expect(actual == expected, "Easy should weaken site selection, not strand its road network")
        #expect(actualRNG == expectedRNG)
    }
}

@Test func easyDifficultyPreservesPersonalityBearingTradeDecisions() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4)
    state.phase = .mainTurn(playerIndex: 0)
    let responder = state.players[1].id
    state.players[1].resources[.ore] = 1
    let offer = TradeOffer.enumerated(from: state.players[0].id, give: [.brick: 1], want: [.ore: 1])
    state.pendingTradeOffers = [offer]
    let legal: [GameMove] = [
        .respondToTrade(offerID: offer.id, accept: true),
        .respondToTrade(offerID: offer.id, accept: false),
    ]
    let observation = GameObservation(seat: responder, state: state, legalMoves: legal)
    var expectedRNG = RandomSource(seed: 7)
    var actualRNG = expectedRNG

    let expected = HeuristicPolicy(personality: .cautious, id: "shipping").decide(
        observation, rng: &expectedRNG)
    let actual = DifficultyPolicy(
        personality: .cautious,
        difficulty: .easy,
        id: "easy-cautious"
    ).decide(observation, rng: &actualRNG)

    #expect(actual == expected)
    #expect(actualRNG == expectedRNG, "A trade decision is personality behavior, not an Easy mistake site")
}

@Test func heuristicHonoursATradeResponseOnlyActionMask() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4)
    state.phase = .mainTurn(playerIndex: 0)
    let responder = state.players[1].id
    let offer = TradeOffer.enumerated(from: state.players[0].id, give: [.brick: 1], want: [.ore: 1])
    state.pendingTradeOffers = [offer]
    let reject = GameMove.respondToTrade(offerID: offer.id, accept: false)
    let observation = GameObservation(seat: responder, state: state, legalMoves: [reject])
    var rng = RandomSource(seed: 1)

    let move = HeuristicPolicy(personality: .balanced, id: "masked").decide(observation, rng: &rng)

    #expect(move == reject)
}

@Test func heuristicHonoursANarrowedRollPhaseActionMask() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4)
    state.phase = .rollDice(playerIndex: 0)
    let player = state.players[0].id
    let knight = GameMove.playKnight(moveRobberTo: state.board.tiles[0].coordinate, stealFrom: nil)
    var rng = RandomSource(seed: 1)

    let move = Bot(personality: .balanced).decide(
        for: state,
        player: player,
        legalMoves: [knight],
        rng: &rng
    )

    #expect(move == knight)
}

/// The anchor measurement: one heuristic bot against three that play legally
/// and think not at all.
///
/// Seat is rotated so a seat advantage cannot be mistaken for skill. The bar
/// is deliberately far below the observed result - measured at 200/200 across
/// all four seats - because this test exists to catch the heuristic becoming
/// *broken*, not to pin a number that honest tuning might move.
@Test func theHeuristicBotBeatsRandomPlayFromEverySeat() throws {
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
        guard let winner = try playToCompletion(seed: UInt64(4000 + offset), policies: policies) else { continue }
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
                     games: Int) throws -> (wins: Int, played: Int) {
    var wins = 0
    var played = 0
    for offset in 0..<games {
        let seat = offset % 4
        var policies: [Int: any Policy] = [:]
        for index in 0..<4 { policies[index] = index == seat ? hero() : foil() }
        let winner = try playToCompletion(seed: UInt64(7000 + offset), policies: policies)
        if let winner {
            played += 1
            if winner.index == seat { wins += 1 }
        }
    }
    // Callers assert the completion count separately so a timeout cannot be
    // mistaken for a decisive loss or silently disappear from the evidence.
    return (wins, played)
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
@Test func theGreedyAnchorSitsBetweenRandomAndTheHeuristic() throws {
    let againstRandom = try winRate(hero: GreedyPolicy(), foil: RandomPolicy(), games: 12)
    #expect(againstRandom.played == 12, "every greedy-vs-random game must finish")
    let randomDetail = "greedy won \(againstRandom.wins)/\(againstRandom.played) against random; "
        + "25% is the no-skill null, so at or below it means the anchor has stopped playing Catan"
    #expect(againstRandom.wins >= 4, "\(randomDetail)")

    let heuristicAgainstGreedy = try winRate(
        hero: HeuristicPolicy(personality: .balanced, id: "heuristic-balanced"),
        foil: GreedyPolicy(), games: 12)
    #expect(heuristicAgainstGreedy.played == 12, "every heuristic-vs-greedy game must finish")
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
@Test func greedySeatsActuallyFinishTheirGames() throws {
    var finished = 0
    for seed: UInt64 in [11, 12, 13, 14, 15, 16] {
        let policies = (0..<4).reduce(into: [Int: any Policy]()) { $0[$1] = GreedyPolicy() }
        if try playToCompletion(seed: seed, policies: policies) != nil { finished += 1 }
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

@Test func aBotProposalIsAnsweredBeforeTheProposerContinues() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 18)
    state.phase = .mainTurn(playerIndex: 0)
    state.players[0].resources[.brick] = 1
    state.players[1].resources[.ore] = 1
    let offer = TradeOffer.enumerated(
        from: state.players[0].id,
        give: [.brick: 1],
        want: [.ore: 1]
    )
    let accepter = FirstLegalResponsePolicy(id: "accept-first")
    var session = GameSession(
        state: state,
        policies: [state.players[0].id: GreedyPolicy(), state.players[1].id: accepter],
        policySeed: 7
    )

    _ = try session.commit(seat: state.players[0].id, move: .proposeTrade(offer))
    #expect(session.nextActor() == .seat(state.players[1].id))
    let applied = try session.step()
    let response = try #require(applied)

    #expect(response.actor == state.players[1].id)
    #expect(response.move == .respondToTrade(offerID: offer.id, accept: true))
    #expect(session.state.pendingTradeOffers.isEmpty)
    #expect(session.state.players[0].resources[.ore] == 1)
    #expect(session.state.players[1].resources[.brick] == 1)
}

@Test func anExternalResponderKeepsTheOfferForTheUI() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 18)
    state.phase = .mainTurn(playerIndex: 0)
    state.players[0].resources[.brick] = 1
    state.players[1].resources[.ore] = 1
    let offer = TradeOffer.enumerated(
        from: state.players[0].id,
        give: [.brick: 1],
        want: [.ore: 1]
    )
    var session = GameSession(
        state: state,
        policies: [state.players[0].id: GreedyPolicy()],
        policySeed: 7
    )

    _ = try session.commit(seat: state.players[0].id, move: .proposeTrade(offer))

    #expect(session.nextActor() == .seat(state.players[0].id))
    #expect(session.state.pendingTradeOffers == [offer])
}

@Test func aResumedBotProposalStillReceivesAResponse() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 18)
    state.phase = .mainTurn(playerIndex: 0)
    state.players[0].resources[.brick] = 1
    state.players[1].resources[.ore] = 1
    let offer = TradeOffer.enumerated(
        from: state.players[0].id,
        give: [.brick: 1],
        want: [.ore: 1]
    )
    state.pendingTradeOffers = [offer]

    var resumed = GameSession(
        state: state,
        policies: [
            state.players[0].id: FirstProposalPolicy(),
            state.players[1].id: GreedyPolicy(),
        ],
        policySeed: 7
    )

    #expect(resumed.nextActor() == .seat(state.players[1].id))
    let applied = try resumed.step()
    let response = try #require(applied)
    #expect(response.move == .respondToTrade(offerID: offer.id, accept: false))
    #expect(resumed.decideNext()?.move == .endTurn)
}

@Test func replacingStateRestoresAPendingBotResponse() {
    var pending = GameSetup.newGame(board: BoardGenerator.standard(), seed: 18)
    pending.phase = .mainTurn(playerIndex: 0)
    pending.players[0].resources[.brick] = 1
    pending.players[1].resources[.ore] = 1
    let offer = TradeOffer.enumerated(
        from: pending.players[0].id,
        give: [.brick: 1],
        want: [.ore: 1]
    )
    pending.pendingTradeOffers = [offer]
    var session = GameSession(
        state: GameSetup.newGame(board: BoardGenerator.standard(), seed: 19),
        policies: [pending.players[0].id: GreedyPolicy(), pending.players[1].id: GreedyPolicy()],
        policySeed: 7
    )

    session.replace(state: pending)

    #expect(session.nextActor() == .seat(pending.players[1].id))
}

private struct FirstLegalResponsePolicy: Policy {
    let id: String

    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        observation.legalMoves.first!
    }
}

@Test func aRejectedOfferIsNotRepeatedInTheSameTurn() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 21)
    state.phase = .mainTurn(playerIndex: 0)
    state.players[0].resources = [.brick: 2]
    state.players[1].resources = [.ore: 2]
    let proposer = FirstProposalPolicy()
    var session = GameSession(
        state: state,
        policies: [state.players[0].id: proposer, state.players[1].id: GreedyPolicy()],
        policySeed: 9
    )

    let proposed = session.decideNext()
    let proposal = try #require(proposed)
    #expect({ if case .proposeTrade = proposal.move { true } else { false } }())
    _ = try session.commit(seat: proposal.seat, move: proposal.move)
    let rejected = session.decideNext()
    let rejection = try #require(rejected)
    #expect({ if case .respondToTrade(_, false) = rejection.move { true } else { false } }())
    _ = try session.commit(seat: rejection.seat, move: rejection.move)

    #expect(session.decideNext()?.move == .endTurn)
}

private struct FirstProposalPolicy: Policy {
    let id = "first-proposal"

    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        observation.legalMoves.first { if case .proposeTrade = $0 { true } else { false } }
            ?? .endTurn
    }
}

@Test func telemetryKeepsEveryEvaluatedTradeReplyWithoutCountingTheCommittedReplyTwice() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 23)
    state.phase = .mainTurn(playerIndex: 0)
    state.players[0].resources = [.brick: 2]
    let offer = TradeOffer(from: state.players[0].id, give: [.brick: 1], want: [.ore: 1])
    var policies: [PlayerID: any Policy] = [:]
    for player in state.players { policies[player.id] = GreedyPolicy() }
    var session = GameSession(state: state, policies: policies, policySeed: 9)

    _ = try session.commit(seat: state.players[0].id, move: .proposeTrade(offer))

    #expect(session.lastPolicyDecisions.map(\.seat) == state.players.dropFirst(2).map(\.id))
    #expect(session.lastPolicyDecisions.map(\.evaluationIndex) == [1, 2])
    #expect(session.policyEvaluationCount == 3)
    #expect(session.lastPolicyDecisions.allSatisfy { decision in
        decision.move == .respondToTrade(offerID: offer.id, accept: false)
            && decision.observation.legalMoves == [.respondToTrade(offerID: offer.id, accept: false)]
    })
    let queued = session.decideNextDetailed()
    #expect(queued?.seat == state.players[1].id)
    #expect(session.lastPolicyDecisions.map(\.seat) == [state.players[1].id])
    #expect(session.lastPolicyDecisions.map(\.evaluationIndex) == [0])
    #expect(session.policyEvaluationCount == 3)
}
