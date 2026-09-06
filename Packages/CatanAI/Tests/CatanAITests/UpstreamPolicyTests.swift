import Foundation
import Testing
import CatanEngine
@testable import CatanAI

/// Records only the adapter's private state/context boundary. These tests supply
/// prescribed logits, so they neither test nor replicate numeric inference or
/// the feature encoder owned by the separate conformance suite.
private final class UpstreamPolicyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [(GameState, UpstreamDecisionContext)] = []
    let scores: [[Int: Float]]

    init(_ scores: [[Int: Float]] = []) { self.scores = scores }

    func encode(_ state: GameState, _ seat: PlayerID, _ context: UpstreamDecisionContext?) -> [Float] {
        lock.withLock {
            let index = snapshots.count
            snapshots.append((state, context ?? UpstreamDecisionContext(state: state, seat: seat)))
            return [Float(index)]
        }
    }

    func predict(_ features: [Float]) -> (logits: [Float], value: Float) {
        var logits = [Float](repeating: 0, count: 299)
        let index = Int(features[0])
        if scores.indices.contains(index) {
            for (action, value) in scores[index] { logits[action] = value }
        }
        return (logits, 0)
    }

    var calls: [(GameState, UpstreamDecisionContext)] { lock.withLock { snapshots } }

    func policy(fallback: HeuristicPolicy = upstreamFallback()) -> UpstreamPolicy {
        UpstreamPolicy(fallback: fallback, predict: { self.predict($0) }, encode: { self.encode($0, $1, $2) })
    }
}

private func upstreamFallback() -> HeuristicPolicy {
    HeuristicPolicy(personality: .balanced, id: "heuristic-balanced-default")
}

private func upstreamTestState(players: Int = 4, target: Int = 10, seat: Int = 0) -> GameState {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 73,
                                  playerCount: players, victoryPointTarget: target)
    state.phase = .mainTurn(playerIndex: seat)
    return state
}

private func upstreamObservation(_ state: GameState, seat: Int = 0) -> GameObservation {
    let player = state.players[seat].id
    return GameObservation(seat: player, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: player))
}

@Test func upstreamPolicyAtomicActionIDsMatchFrozenCodec() throws {
    let state = upstreamTestState()
    let layout = try UpstreamBoardLayout(board: state.board)
    let mappings: [(GameMove, Int)] = [
        (.placeInitialSettlement(layout.vertices[7]), 7), (.buildSettlement(layout.vertices[7]), 7),
        (.buildCity(layout.vertices[7]), 61), (.placeInitialRoad(layout.edges[8]), 116),
        (.buildRoad(layout.edges[8]), 116), (.moveRobber(layout.tiles[9], stealFrom: nil), 189),
        (.playKnight(moveRobberTo: layout.tiles[9], stealFrom: nil), 296),
        (.playRoadBuilding(layout.edges[8], layout.edges[9]), 297),
        (.playMonopoly(.ore), 212), (.playYearOfPlenty(.grain, .grain), 213),
        (.playYearOfPlenty(.ore, .ore), 227), (.playYearOfPlenty(.wool, .grain), 214),
        (.bankTrade(give: [.grain: 4], get: [.ore: 1]), 231),
        (.rollDice, 294), (.buyDevCard, 295), (.endTurn, 298),
    ]
    for (move, expected) in mappings { #expect(UpstreamActions.root(move, layout: layout, state: state) == expected) }
    #expect(UpstreamActions.root(.bankTrade(give: [.grain: 8], get: [.ore: 2]), layout: layout, state: state) == nil)
    let offer = TradeOffer.enumerated(from: state.players[0].id, give: [.grain: 1], want: [.ore: 1])
    #expect(UpstreamActions.root(.proposeTrade(offer), layout: layout, state: state) == nil)
    #expect(UpstreamActions.root(.respondToTrade(offerID: offer.id, accept: true), layout: layout, state: state) == nil)
}

@Test func upstreamPolicyUsesLowestActionIDForTiesWithoutAdvancingRNG() throws {
    var state = upstreamTestState()
    state.phase = .setupForward(playerIndex: 0)
    let layout = try UpstreamBoardLayout(board: state.board)
    let legal = Array(RulesEngine.legalMoves(for: state).reversed())
    let observation = GameObservation(seat: state.players[0].id, state: state, legalMoves: legal)
    let probe = UpstreamPolicyProbe()
    var rng = RandomSource(seed: 34)
    let originalRNG = rng
    let result = probe.policy().scoredDecision(observation, rng: &rng)
    #expect(result.move == .placeInitialSettlement(layout.vertices[0]))
    #expect(result.source == .neural)
    #expect(result.fallbackReason == nil)
    #expect(rng == originalRNG)
}

@Test func upstreamPolicyDoesNotSumCompoundLogitsAtRoot() throws {
    var state = upstreamTestState()
    state.players[0].devCards = [.knight]
    let probe = UpstreamPolicyProbe([[296: 1, 298: 2, 180: 1_000, 199: 1_000]])
    var rng = RandomSource(seed: 3)
    let result = probe.policy().scoredDecision(upstreamObservation(state), rng: &rng)
    #expect(result.move == .endTurn)
    #expect(probe.calls.count == 1)
}

@Test func upstreamPolicyRoadBuildingScoresPrivateSequentialStatesAndCommitsOnePair() throws {
    var state = upstreamTestState()
    let seat = state.players[0].id
    state.players[0].settlements = [state.board.onBoardVertices.sorted()[20]]
    state.players[0].devCards = [.roadBuilding]
    let pairs = DevCards.legalRoadBuildingPairs(by: seat, in: state)
    let first = try #require(pairs.first?.first)
    let second = try #require(pairs.last(where: { $0.first == first })?.second)
    let layout = try UpstreamBoardLayout(board: state.board)
    let firstID = try #require(UpstreamActions.road(first, layout: layout))
    let secondID = try #require(UpstreamActions.road(second, layout: layout))
    let probe = UpstreamPolicyProbe([[297: 10], [firstID: 20], [secondID: 30, firstID: 100]])
    let observation = upstreamObservation(state)
    var rng = RandomSource(seed: 44)
    let originalRNG = rng
    let result = probe.policy().scoredDecision(observation, rng: &rng)
    #expect(result.move == .playRoadBuilding(first, second))
    #expect(observation.legalMoves.contains(result.move))
    #expect(result.source == .neural)
    #expect(rng == originalRNG)
    let calls = probe.calls
    #expect(calls.count == 3)
    #expect(calls[1].1.turnPhase == 6 && calls[1].1.roadsToPlace == 2)
    #expect(calls[1].0.players[0].devCards.isEmpty)
    #expect(calls[1].0.devCardPlayedThisTurn == seat)
    #expect(calls[2].1.roadsToPlace == 1)
    #expect(calls[2].0.players[0].roads == [first])
    #expect(state.players[0].roads.isEmpty)
    #expect(state.players[0].devCards == [.roadBuilding])
    try RulesEngine.apply(result.move, by: seat, to: &state)
    #expect(state.players[0].roads == [first, second])
    #expect(state.players[0].resources.values.reduce(0, +) == 0)
}

@Test func upstreamPolicyRoadBuildingNeverReturnsAOneRoadCompletion() throws {
    var state = upstreamTestState()
    state.players[0].settlements = [state.board.onBoardVertices.sorted()[0]]
    state.players[0].roads = Set(state.board.onBoardEdges.sorted().prefix(14))
    state.players[0].devCards = [.roadBuilding]
    let observation = upstreamObservation(state)
    #expect(!observation.legalMoves.contains { if case .playRoadBuilding = $0 { true } else { false } })
    var rng = RandomSource(seed: 5)
    let result = UpstreamPolicyProbe([[297: 100]]).policy().scoredDecision(observation, rng: &rng)
    #expect(result.move == .endTurn)
}

@Test(arguments: [3, 4], [8, 10, 12])
func upstreamPolicyKnightKeepsActorAndTurnContextAcrossSupportedTables(players: Int, target: Int) throws {
    let actor = players - 1
    var state = upstreamTestState(players: players, target: target, seat: actor)
    let layout = try UpstreamBoardLayout(board: state.board)
    let tile = try #require(layout.tiles.first { $0 != state.board.robberTile })
    let corners = layout.vertices.filter { $0.touchingTiles.contains(tile) }
    let secondCorner = try #require(corners.first {
        $0 != corners[0] && !state.board.adjacentVertices(of: corners[0]).contains($0)
    })
    state.players[0].settlements = [corners[0]]
    state.players[1].settlements = [secondCorner]
    state.players[0].resources = [.grain: 2]
    state.players[1].resources = [.ore: 2]
    state.players[actor].playedKnights = 2
    state.players[actor].devCards = [.knight]
    let seat = state.players[actor].id
    let tileID = try #require(UpstreamActions.robber(tile, layout: layout))
    let probe = UpstreamPolicyProbe([[296: 10], [tileID: 20], [200: 30, 201: 100]])
    var rng = RandomSource(seed: 99)
    let originalRNG = rng
    let result = probe.policy().scoredDecision(upstreamObservation(state, seat: actor), rng: &rng)
    #expect(result.move == .playKnight(moveRobberTo: tile, stealFrom: state.players[1].id))
    #expect(rng == originalRNG)
    let calls = probe.calls
    #expect(calls.count == 3)
    #expect(calls[1].0.players[actor].playedKnights == 3)
    #expect(calls[1].0.largestArmyPlayer == seat)
    #expect(calls[1].0.players[actor].devCards.isEmpty)
    #expect(calls[1].0.board.robberTile == state.board.robberTile)
    #expect(calls[1].1.turnPhase == 3 && calls[1].1.turnOwner == seat)
    #expect(calls[2].0.board.robberTile == tile && calls[2].1.turnPhase == 4)
    try RulesEngine.apply(result.move, by: seat, to: &state)
    #expect(state.players[actor].playedKnights == 3)
    #expect(state.players[actor].resources[.ore] == 1)
}

@Test func upstreamPolicyRobberWithoutVictimsProducesNilWithoutAStealDecision() throws {
    var state = upstreamTestState(players: 3, seat: 2)
    state.phase = .movingRobber(playerIndex: 2)
    let probe = UpstreamPolicyProbe()
    var rng = RandomSource(seed: 9)
    let result = probe.policy().scoredDecision(upstreamObservation(state, seat: 2), rng: &rng)
    guard case .moveRobber(_, let victim) = result.move else { Issue.record("expected robber move"); return }
    #expect(victim == nil)
    #expect(probe.calls.count == 1)
    try RulesEngine.apply(result.move, by: state.players[2].id, to: &state)
    #expect(state.phase == .mainTurn(playerIndex: 2))
}

@Test func upstreamPolicyDiscardUsesOriginalQuotaAndCallerNarrowedBundles() throws {
    var state = upstreamTestState(players: 3, seat: 2)
    let seat = state.players[1].id
    state.players[1].resources = [.grain: 4, .ore: 4]
    state.phase = .discarding(pending: [seat, state.players[0].id])
    state.robberMoverIndex = 2
    let legal: [GameMove] = [.discard([.grain: 1, .ore: 3]), .discard([.grain: 2, .ore: 2])]
    let observation = GameObservation(seat: seat, state: state, legalMoves: legal)
    let probe = UpstreamPolicyProbe([[203: 20], [203: 20]])
    var rng = RandomSource(seed: 4)
    let result = probe.policy().scoredDecision(observation, rng: &rng)
    #expect(result.move == .discard([.grain: 2, .ore: 2]))
    let calls = probe.calls
    #expect(calls.count == 2, "remaining ore picks are forced by the supplied mask")
    #expect(calls[0].1.discardsRemaining == 4 && calls[1].1.discardsRemaining == 3)
    #expect(calls[1].0.players[1].resources[.grain] == 3)
    #expect(calls[1].0.bank[.grain] == state.bank[.grain]! + 1)
    #expect(calls[1].1.turnOwner.index == 2)
    #expect(state.players[1].resources[.grain] == 4)
    try RulesEngine.apply(result.move, by: seat, to: &state)
    #expect(state.players[1].resources == [.grain: 2, .ore: 2])
}

@Test func upstreamPolicyDiscardCanExceedTheExistingFlatActionSpaceCap() throws {
    var state = upstreamTestState()
    let seat = state.players[0].id
    state.players[0].resources = [.grain: 12, .ore: 12]
    state.phase = .discarding(pending: [seat])
    state.robberMoverIndex = 0
    let observation = upstreamObservation(state)
    var rng = RandomSource(seed: 4)
    let result = UpstreamPolicyProbe().policy().scoredDecision(observation, rng: &rng)
    #expect(result.move == .discard([.grain: 12]))
    #expect(result.source == .neural)
    try RulesEngine.apply(result.move, by: seat, to: &state)
    #expect(state.players[0].resources[.ore] == 12)
}

@Test func upstreamPolicyUnknownHistoryAndPreRollDifferencesHaveNamedFallbacks() {
    var state = upstreamTestState()
    state.completedTurnCount = nil
    let probe = UpstreamPolicyProbe()
    var rng = RandomSource(seed: 5)
    let unknown = probe.policy().scoredDecision(upstreamObservation(state), rng: &rng)
    #expect(unknown.source == .heuristic && unknown.fallbackReason == .unknownTurnHistory)
    state.completedTurnCount = 0
    state.phase = .rollDice(playerIndex: 0)
    state.players[0].devCards = [.yearOfPlenty]
    let preRoll = probe.policy().scoredDecision(upstreamObservation(state), rng: &rng)
    #expect(preRoll.move == .rollDice)
    #expect(preRoll.fallbackReason == .unsupportedPreRollDevelopmentCard)
    #expect(probe.calls.isEmpty)
}

@Test func upstreamPolicyRichPlayerTradeResponsesUseHeuristicAndExactOfferID() {
    var state = upstreamTestState()
    let seat = state.players[1].id
    let offer = TradeOffer.enumerated(from: state.players[0].id,
                                      give: [.grain: 2, .ore: 1], want: [.lumber: 2])
    state.pendingTradeOffers = [offer]
    let reject = GameMove.respondToTrade(offerID: offer.id, accept: false)
    let observation = GameObservation(seat: seat, state: state, legalMoves: [reject])
    let probe = UpstreamPolicyProbe([[288: 100]])
    var rng = RandomSource(seed: 2)
    let result = probe.policy().scoredDecision(observation, rng: &rng)
    #expect(result.move == reject)
    #expect(result.source == .heuristic && result.fallbackReason == .playerTradeNegotiation)
    #expect(probe.calls.isEmpty)
}

@Test func upstreamPolicyPreservesExistingHeuristicTradeProposalScheduling() throws {
    var state = upstreamTestState()
    state.players[0].resources = [.brick: 1, .lumber: 1, .grain: 1, .ore: 3]
    let observation = upstreamObservation(state)
    let fallback = upstreamFallback()
    var heuristicRNG = RandomSource(seed: 46)
    let expected = fallback.decide(observation, rng: &heuristicRNG)
    guard case .proposeTrade = expected else { Issue.record("fixture must schedule a real heuristic proposal"); return }
    let probe = UpstreamPolicyProbe([[298: 1_000]])
    let policy = probe.policy(fallback: fallback)
    var rng = RandomSource(seed: 46)
    let result = policy.scoredDecision(observation, rng: &rng)
    #expect(result.move == expected)
    #expect(result.source == .heuristic && result.fallbackReason == .heuristicTradeProposal)
    #expect(rng == heuristicRNG)
    #expect(probe.calls.isEmpty)
    #expect(policy.id.hasPrefix("upstream-r2-hybrid-"))
    #expect(policy.id.contains(fallback.id) && policy.fallbackProfile == fallback.id)
}

@Test func upstreamPolicyReportsMalformedPredictionAndEncodingFallbacks() {
    var state = upstreamTestState()
    state.players[0].devCards = [.monopoly]
    let observation = upstreamObservation(state)
    var rng = RandomSource(seed: 33)
    let invalid = UpstreamPolicy(fallback: upstreamFallback(), predict: { _ in ([], 0) })
    let result = invalid.scoredDecision(observation, rng: &rng)
    #expect(result.source == .heuristic && result.fallbackReason == .invalidPrediction)
    #expect(observation.legalMoves.contains(result.move))
    let failing = UpstreamPolicy(fallback: upstreamFallback(), predict: { _ in ([], 0) },
                                 encode: { _, _, _ in throw UpstreamActionScorer.ScoringError.incompleteCompound })
    let failed = failing.scoredDecision(observation, rng: &rng)
    #expect(failed.source == .heuristic && failed.fallbackReason != nil)
    #expect(observation.legalMoves.contains(failed.move))
}

@Test func upstreamPolicySelectionCapturesDiagnosticsWithoutRepeatingInference() {
    var state = upstreamTestState()
    state.players[0].devCards = [.monopoly]
    let probe = UpstreamPolicyProbe([[208: 10]])
    let policy: any Policy = probe.policy()
    var rng = RandomSource(seed: 6)
    let selection = policy.select(upstreamObservation(state), rng: &rng)
    #expect(selection.move == .playMonopoly(.grain))
    #expect(selection.source == "neural" && selection.fallbackReason == nil)
    #expect(probe.calls.count == 1)
    state.completedTurnCount = nil
    let fallback = policy.select(upstreamObservation(state), rng: &rng)
    #expect(fallback.source == "heuristic" && fallback.fallbackReason == "unknown_turn_history")
    #expect(probe.calls.count == 1)
}

@Test func upstreamPolicyTradePreflightDoesNotAdvanceRNGWhenNeuralMoveWins() throws {
    var state = upstreamTestState()
    let layout = try UpstreamBoardLayout(board: state.board)
    state.players[0].settlements = [layout.vertices[20]]
    state.players[0].resources = [.brick: 3, .lumber: 3]
    let observation = upstreamObservation(state)
    #expect(observation.legalMoves.contains(where: UpstreamActions.isPlayerTrade))
    let probe = UpstreamPolicyProbe([[298: 1_000]])
    var rng = RandomSource(seed: 77)
    let before = rng
    let result = probe.policy().scoredDecision(observation, rng: &rng)
    #expect(result.source == .neural && result.move == .endTurn)
    #expect(rng == before)
}

@Test func upstreamPolicyPreRollKnightKeepsTheRollOwed() throws {
    var state = upstreamTestState()
    state.phase = .rollDice(playerIndex: 0)
    state.players[0].devCards = [.knight]
    let probe = UpstreamPolicyProbe([[296: 10]])
    var rng = RandomSource(seed: 2)
    let result = probe.policy().scoredDecision(upstreamObservation(state), rng: &rng)
    guard case .playKnight = result.move else { Issue.record("expected pre-roll Knight"); return }
    #expect(probe.calls.count == 2)
    #expect(probe.calls[1].1.turnPhase == 3 && !probe.calls[1].1.hasRolled)
    try RulesEngine.apply(result.move, by: state.players[0].id, to: &state)
    #expect(state.phase == .rollDice(playerIndex: 0))
    let next = upstreamObservation(state)
    #expect(next.legalMoves == [.rollDice])
}

@Test func upstreamPolicyWinningKnightStillReturnsACompleteSwiftMove() throws {
    var state = upstreamTestState(target: 8)
    // Six points before play, eight after largest army. Upstream would finish
    // at the root action; Swift requires the tile choice to complete first.
    state.players[0].devCards = [.knight] + Array(repeating: .victoryPoint, count: 5)
    state.players[0].settlements = [state.board.onBoardVertices.sorted()[0]]
    state.players[0].playedKnights = 2
    let probe = UpstreamPolicyProbe([[296: 10]])
    var rng = RandomSource(seed: 3)
    let result = probe.policy().scoredDecision(upstreamObservation(state), rng: &rng)
    guard case .playKnight = result.move else { Issue.record("expected complete winning Knight"); return }
    #expect(probe.calls.count == 2)
    #expect(probe.calls[1].1.gamePhase == 2)
    #expect(probe.calls[1].0.victoryPoints(for: state.players[0].id) == 8)
    try RulesEngine.apply(result.move, by: state.players[0].id, to: &state)
    #expect(state.phase == .gameOver(winner: state.players[0].id))
}
