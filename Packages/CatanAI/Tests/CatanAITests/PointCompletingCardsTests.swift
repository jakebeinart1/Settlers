import Testing
import CatanEngine
@testable import CatanAI

/// Conserved supplies and native legal moves prove the retained mechanism,
/// not its strength. The independent B-002 result supplies that evidence.
@Suite struct PointCompletingCardsTests {
    private let grainPair = GameMove.playYearOfPlenty(.grain, .grain)
    private let mixedPair = GameMove.playYearOfPlenty(.grain, .wool)

    @Test func plentyCompletesACityInsteadOfKeepingTheCardOrTakingAMixedPair() throws {
        let state = try position(holding: [.ore: 3])
        let seat = state.players[0].id
        let ledger = PublicLedger.fromPositionAlone(state, observer: seat)
        let moves: [GameMove] = [.endTurn, grainPair, mixedPair]
        #expect(moves.allSatisfy { RulesEngine.legalMoves(for: state, seat: seat).contains($0) })
        #expect(EvaluationPolicy(revision: .cityProductionV1)
            .best(among: moves, state: state, ledger: ledger) == .endTurn)
        #expect(EvaluationPolicy(revision: .pointCompletingCardsV1)
            .best(among: moves, state: state, ledger: ledger) == grainPair)
        var next = state
        _ = try RulesEngine.apply(grainPair, by: seat, to: &next)
        let vertex = try #require(next.players[0].settlements.sorted().first)
        _ = try RulesEngine.apply(.buildCity(vertex), by: seat, to: &next)
        #expect(next.victoryPoints(for: seat) == state.victoryPoints(for: seat) + 1)
    }

    @Test func freeRoadsOpenOnlyAnAffordableLegalSettlement() throws {
        let state = try position(card: .roadBuilding, holding: Building.settlementCost)
        #expect(BoardIndex(state: state).buildableSites(for: state.players[0].id, in: state).isEmpty)
        let (move, site) = try roadPairOpeningSite(in: state)
        #expect(try adjustment(move, in: state) == 1)
        var next = try projected(move, in: state).next
        _ = try RulesEngine.apply(.buildSettlement(site), by: next.players[0].id, to: &next)
        #expect(next.players[0].settlements.contains(site))
        var unfunded = state
        try fund([.grain: 1, .wool: 1], in: &unfunded)
        #expect(try adjustment(move, in: unfunded) == 0)
    }

    @Test func anAlreadyAffordablePurchaseOrExhaustedCitySupplyEarnsNoNewCredit() throws {
        var state = try position(holding: Building.cityCost)
        #expect(try adjustment(.playYearOfPlenty(.ore, .ore), in: state) == 0)
        state.victoryPointTarget = 12
        while state.players[0].cities.count < state.rules.pieceLimit(for: .city) {
            if state.players[0].settlements.isEmpty { try addSettlement(in: &state) }
            let vertex = try #require(state.players[0].settlements.sorted().first)
            try fund(Building.cityCost, in: &state)
            _ = try RulesEngine.apply(.buildCity(vertex), by: state.players[0].id, to: &state)
        }
        try fund([.ore: 3], in: &state)
        #expect(try adjustment(grainPair, in: state) == 0)
    }

    @Test func winningReadinessClosesTheExistingTerminalGap() throws {
        var state = try position(holding: [:])
        try addSettlement(in: &state)
        let vertex = try #require(state.players[0].settlements.sorted().first)
        try fund(Building.cityCost, in: &state)
        _ = try RulesEngine.apply(.buildCity(vertex), by: state.players[0].id, to: &state)
        for _ in 0..<5 { try acquire(.victoryPoint, in: &state) }
        try fund([.ore: 3], in: &state)
        #expect(state.victoryPoints(for: state.players[0].id) == 9)
        let projection = try projected(grainPair, in: state)
        let evaluator = PositionEvaluator(seat: state.players[0].id, revision: .pointCompletingCardsV1)
        let credit = try adjustment(grainPair, in: state)
        var won = projection.next
        let upgrade = try #require(won.players[0].settlements.sorted().first)
        _ = try RulesEngine.apply(.buildCity(upgrade), by: won.players[0].id, to: &won)
        var wonLedger = projection.after
        wonLedger.reconcileObserverHand(from: won)
        #expect(abs(evaluator.evaluate(projection.next, ledger: projection.after) + credit
            - evaluator.evaluate(won, ledger: wonLedger)) < 1e-10)
    }

    @Test func oldRevisionsPreRollAndDiscardRemainUnchanged() throws {
        var state = try position(holding: [.ore: 3])
        let seat = state.players[0].id
        let observation = GameObservation(seat: seat, state: state, legalMoves: [grainPair])
        let ledger = PublicLedger.fromPositionAlone(state, observer: seat)
        let old = EvaluationPolicy(revision: .cityProductionV1).candidateScores(observation, ledger: ledger)
        let current = EvaluationPolicy(revision: .pointCompletingCardsV1).candidateScores(observation, ledger: ledger)
        #expect(try #require(current.first?.score) - #require(old.first?.score) == 1)
        state.phase = .rollDice(playerIndex: 0)
        let evaluator = PositionEvaluator(seat: seat, revision: .pointCompletingCardsV1)
        #expect(PointCompletingCards.adjustment(for: grainPair, from: state, to: state,
            ledger: ledger, nextLedger: ledger, evaluator: evaluator) == 0)
        try fund([.ore: 3, .grain: 3, .wool: 2, .lumber: 2], in: &state)
        MainPhase.rollDice(state: &state, roll: 7)
        let discard = GameMove.discard([.grain: 1, .wool: 2, .lumber: 2])
        #expect(try adjustment(discard, in: state) == 0)
    }

    @Test func hiddenHandsCardFacesDeckOrderAndRNGDoNotChangeCredit() throws {
        var state = try position(holding: [.ore: 3])
        try acquire(.knight, at: 1, in: &state)
        try acquire(.victoryPoint, at: 2, in: &state)
        try fund([.ore: 2], at: 1, in: &state)
        try fund([.wool: 2], at: 2, in: &state)
        state.phase = .mainTurn(playerIndex: 0)
        var scrambled = state
        scrambled.players[1].resources = state.players[2].resources
        scrambled.players[2].resources = state.players[1].resources
        scrambled.players[1].devCards = state.players[2].devCards
        scrambled.players[2].devCards = state.players[1].devCards
        scrambled.devCardDeck.reverse()
        scrambled.rng = RandomSource(seed: 9_999)
        #expect(try adjustment(grainPair, in: state) == adjustment(grainPair, in: scrambled))
    }

    private func roadPairOpeningSite(in state: GameState) throws -> (GameMove, VertexID) {
        for pair in DevCards.legalRoadBuildingPairs(by: state.players[0].id, in: state) {
            var probe = state
            probe.players[0].roads.formUnion([pair.first, pair.second])
            if let site = BoardIndex(state: probe).buildableSites(for: probe.players[0].id, in: probe).first {
                return (.playRoadBuilding(pair.first, pair.second), site)
            }
        }
        throw MoveError.other("fixture has no legal two-road settlement approach")
    }

    private func addSettlement(in state: inout GameState) throws {
        let (move, site) = try roadPairOpeningSite(in: state)
        guard case .playRoadBuilding(let first, let second) = move else {
            preconditionFailure("road-pair fixture returned a different move")
        }
        for edge in [first, second] {
            try fund(Building.roadCost, in: &state)
            _ = try RulesEngine.apply(.buildRoad(edge), by: state.players[0].id, to: &state)
        }
        try fund(Building.settlementCost, in: &state)
        _ = try RulesEngine.apply(.buildSettlement(site), by: state.players[0].id, to: &state)
    }

    private func projected(_ move: GameMove, in state: GameState)
        throws -> (next: GameState, before: PublicLedger, after: PublicLedger) {
        let seat = state.players[0].id
        #expect(RulesEngine.legalMoves(for: state, seat: seat).contains(move))
        let before = PublicLedger.fromPositionAlone(state, observer: seat)
        var next = state
        let events = try RulesEngine.apply(move, by: seat, to: &next)
        var after = before
        for event in events { after.apply(event.masked(for: seat), stateBefore: state) }
        after.reconcileObserverHand(from: next)
        return (next, before, after)
    }

    private func adjustment(_ move: GameMove, in state: GameState) throws -> Double {
        let projection = try projected(move, in: state)
        let evaluator = PositionEvaluator(seat: state.players[0].id, revision: .pointCompletingCardsV1)
        return PointCompletingCards.adjustment(for: move, from: state, to: projection.next,
            ledger: projection.before, nextLedger: projection.after, evaluator: evaluator)
    }

    private func position(card: DevCardType = .yearOfPlenty, holding: [Resource: Int]) throws -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 81), seed: 81)
        playOpeningPlacements(in: &state, seed: 81)
        for index in state.players.indices { try fund([:], at: index, in: &state) }
        try acquire(card, in: &state)
        state.phase = .mainTurn(playerIndex: 0)
        try fund(holding, in: &state)
        return state
    }

    /// Staged hands preserve the printed bank rather than inventing resources.
    private func fund(_ hand: [Resource: Int], at index: Int = 0, in state: inout GameState) throws {
        for resource in Resource.allCases {
            state.bank[resource, default: 0] += state.players[index].resources[resource] ?? 0
        }
        state.players[index].resources = [:]
        for resource in Resource.allCases {
            let count = hand[resource] ?? 0
            guard (state.bank[resource] ?? 0) >= count else {
                throw MoveError.other("fixture funding exceeds printed bank supply")
            }
            state.bank[resource, default: 0] -= count
            if count > 0 { state.players[index].resources[resource] = count }
        }
    }

    /// Reorder the printed deck, buy legally and end the turn to age the card.
    private func acquire(_ card: DevCardType, at index: Int = 0, in state: inout GameState) throws {
        let deckIndex = try #require(state.devCardDeck.firstIndex(of: card))
        let drawn = state.devCardDeck.remove(at: deckIndex)
        state.devCardDeck.insert(drawn, at: 0)
        state.phase = .mainTurn(playerIndex: index)
        try fund(Building.devCardCost, at: index, in: &state)
        _ = try RulesEngine.apply(.buyDevCard, by: state.players[index].id, to: &state)
        _ = try RulesEngine.apply(.endTurn, by: state.players[index].id, to: &state)
        state.phase = .mainTurn(playerIndex: 0)
    }
}
