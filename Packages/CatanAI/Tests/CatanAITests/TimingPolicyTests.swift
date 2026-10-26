import Testing
import CatanEngine
@testable import CatanAI

/// The timing rules change *when* the Expert plays. These pin each trigger;
/// the strength evidence is the held-out run in `TimingPolicy`'s doc comment.
@Suite struct TimingPolicyTests {
    private let me = PlayerID(index: 0)

    @Test func revisionSeatsTheFrozenTimingBrainAndOthersTheirEvaluationPolicy() {
        #expect(ExpertRevision.timingOneAheadV1.policy.id == "evaluation-timing-one-ahead-v1")
        #expect(TimingPolicy.oneAheadV1.rules == [.margin, .preroll, .lean])
        for revision in ExpertRevision.allCases where revision != .timingOneAheadV1 && revision != .timingTradeGuardV1 {
            #expect(revision.policy is EvaluationPolicy)
            #expect(revision.policy.id == revision.policyID)
        }
        #expect(TimingPolicy(rules: [.hold, .preroll]).id == "evaluation-timing-preroll+hold")
    }

    @Test func aBlockedSeatPlaysItsKnightBeforeRollingAndAnUnblockedOneRolls() throws {
        var state = try position(knightsInHand: 1)
        state.phase = .rollDice(playerIndex: 0)
        #expect(!TimingPolicy.robberBlocks(me, in: state))
        #expect(decide(TimingPolicy.oneAheadV1, state) == .rollDice)

        state.board.robberTile = try ownTile(in: state)
        #expect(TimingPolicy.robberBlocks(me, in: state))
        guard case .playKnight(let tile, _) = decide(TimingPolicy.oneAheadV1, state) else {
            Issue.record("expected a knight before the roll")
            return
        }
        #expect(tile != state.board.robberTile)
        #expect(decide(TimingPolicy(rules: [.lean]), state) == .rollDice, "without preroll it rolls")
    }

    @Test func aKnightThatTakesTheArmyWithAOneKnightLeadIsPlayedAtOnce() throws {
        var state = try position(knightsInHand: 1)
        state.players[0].playedKnights = 2
        state.players[1].playedKnights = 2
        let knights = RulesEngine.legalMoves(for: state, seat: me).filter(TimingPolicy.isKnight)
        let knight = try #require(knights.first)
        #expect(TimingPolicy.restoresLead(knight, me, state))
        #expect(TimingPolicy.isKnight(decide(TimingPolicy.oneAheadV1, state)))

        state.players[0].playedKnights = 3
        state.largestArmyPlayer = me
        #expect(TimingPolicy.leadsArmy(me, state, by: 1))
        #expect(!TimingPolicy.restoresLead(knight, me, state), "already one ahead")
        #expect(TimingPolicy.knightIsTimely(knight, me, state) == false)
    }

    @Test func leanSpendsAHandOverFiveThatWouldOtherwiseEndTheTurn() throws {
        var state = try position(knightsInHand: 0)
        state.players[0].resources = [.wool: 6]
        let trade = GameMove.bankTrade(give: [.wool: 4], get: [.ore: 1])
        let legal: [GameMove] = [.endTurn, trade]
        #expect(legal.allSatisfy { RulesEngine.legalMoves(for: state, seat: me).contains($0) })
        #expect(decide(TimingPolicy(rules: [.lean]), state, legal: legal) == trade)

        state.players[0].resources = [.wool: 5]
        let base = EvaluationPolicy(revision: .pointCompletingCardsV1)
        #expect(decide(TimingPolicy(rules: [.lean]), state, legal: legal) == decide(base, state, legal: legal))
    }

    /// One full game between four timing Experts: it finishes, and every
    /// tenth position's road weight follows the one-ahead rule.
    @Test func timingExpertsFinishAndPriceTheRoadOneAhead() throws {
        let opening = try position(knightsInHand: 0)
        let shipped = EvaluationWeights.forMode(opening.mode).roadLength
        #expect(TimingPolicy.marginBase(me, opening).weightsOverride?.roadLength == shipped, "no race yet")

        let positions = try selfPlayPositions(seed: 975)
        let last = try #require(positions.last)
        guard case .gameOver = last.phase else {
            Issue.record("timing Experts did not finish")
            return
        }
        var seen: Set<Double> = []
        for state in positions.enumerated().filter({ $0.offset % 10 == 0 }).map(\.element) {
            for player in state.players {
                let mine = LongestRoad.length(for: player, in: state)
                let rival = state.players.filter { $0.id != player.id }
                    .map { LongestRoad.length(for: $0, in: state) }.max() ?? 0
                let weight = try #require(TimingPolicy.marginBase(player.id, state).weightsOverride?.roadLength)
                let expected = state.longestRoadPlayer == player.id && mine >= rival + 2 ? 0
                    : abs(mine - rival) <= 1 && max(mine, rival) >= 4 ? 2 * shipped : shipped
                #expect(weight == expected)
                seen.insert(weight)
            }
        }
        #expect(seen == [0, shipped, 2 * shipped], "the game reached a runaway road and a close race")
    }

    // MARK: - Fixtures

    private func decide(_ policy: some LedgerAwarePolicy, _ state: GameState, legal: [GameMove]? = nil) -> GameMove {
        var rng = RandomSource(seed: 1)
        let observation = GameObservation(seat: me, state: state,
                                          legalMoves: legal ?? RulesEngine.legalMoves(for: state, seat: me))
        return policy.decide(observation, ledger: .fromPositionAlone(state, observer: me), rng: &rng)
    }

    /// Seat 0 to move with one settlement, `knightsInHand` mature knights and an empty hand.
    private func position(knightsInHand: Int) throws -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 33)
        let vertex = try #require(state.board.onBoardVertices.sorted().first {
            !$0.touchingTiles.contains(state.board.robberTile)
                && $0.touchingTiles.contains { tile in state.board.tiles.contains { $0.coordinate == tile } }
        })
        state.players[0].settlements = [vertex]
        let rival = try #require(state.board.onBoardVertices.sorted().last {
            Set($0.touchingTiles).isDisjoint(with: vertex.touchingTiles)
        })
        state.players[1].settlements = [rival]
        state.players[0].devCards = Array(repeating: .knight, count: knightsInHand)
        state.phase = .mainTurn(playerIndex: 0)
        return state
    }

    private func ownTile(in state: GameState) throws -> HexCoordinate {
        let vertex = try #require(state.players[0].settlements.first)
        return try #require(vertex.touchingTiles.sorted().first { tile in
            state.board.tiles.contains { $0.coordinate == tile && $0.kind != .desert }
        })
    }

    /// Every position of one seeded game between four timing Experts.
    private func selfPlayPositions(seed: UInt64) throws -> [GameState] {
        let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        let policies = Dictionary(uniqueKeysWithValues: state.players.map {
            ($0.id, TimingPolicy.oneAheadV1 as any Policy)
        })
        var session = GameSession(state: state, policies: policies, policySeed: seed)
        var positions: [GameState] = []
        while positions.count < 3000, try session.step() != nil { positions.append(session.state) }
        return positions
    }
}
