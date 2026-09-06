import Foundation
import Testing
import CatanEngine
import CatanAI

private let upstreamCompletionSeeds: [UInt64] = [101, 202, 303]
private let upstreamCompletionActionLimit = 3_000
private let upstreamCompletionWallLimit: Duration = .seconds(45)

/// Functional integration, not a strength comparison. Every seat runs the real
/// bundled checkpoint with its named heuristic fallback, through GameSession.
/// Run this Release suite in two separate processes and compare the emitted
/// UPSTREAM_COMPLETION records excluding elapsedSeconds. No fingerprint is
/// blessed during concurrent implementation; raw traces remain reviewable.
@Suite(.serialized)
struct UpstreamGameCompletionTests {
    @Test(.timeLimit(.minutes(12)))
    func bundledHybridsCompleteTheSupportedAppMatrix() throws {
        let network = try UpstreamNetwork.bundled()
        var outcomes: [String: Int] = [:]
        for players in [3, 4] {
            for target in players == 3 ? [8, 10, 12] : [8, 10] {
                for seed in upstreamCompletionSeeds {
                    let result = runUpstreamCompletion(network: network, players: players, target: target, seed: seed)
                    try emitUpstreamCompletion(result)
                    outcomes[result.status, default: 0] += 1
                    assertUpstreamCompletion(result)
                }
            }
        }
        let data = try JSONEncoder().encode(outcomes)
        FileHandle.standardOutput.write(Data("UPSTREAM_COMPLETION_TOTAL ".utf8) + data + Data("\n".utf8))
    }
}

private struct UpstreamCompletionResult: Encodable {
    let players: Int
    let target: Int
    let seed: UInt64
    let actionLimit = upstreamCompletionActionLimit
    let wallLimitSeconds = 45
    var status = "running"
    var failure: String?
    var actions = 0
    var evaluations = 0
    var sessionEvaluations = 0
    var illegalSelections = 0
    var missingTraces = 0
    var winner: Int?
    var vp: [Int] = []
    var sources: [String: Int] = [:]
    var fallbacks: [String: Int] = [:]
    var committedSources: [String: Int] = [:]
    var committedFallbacks: [String: Int] = [:]
    var overrides: [String: Int] = [:]
    var moves: [String: Int] = [:]
    var policyIDs: [String] = []
    var fingerprint = ""
    var elapsedSeconds = 0.0
}

/// Counts at the actual selection boundary, including responder consultations
/// that GameSession evaluates but does not commit. This avoids both omitted
/// fallback decisions and a second inference for telemetry.
private final class UpstreamCompletionLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var sources: [String: Int] = [:]
    private var fallbacks: [String: Int] = [:]
    private var illegal = 0

    func record(_ selection: PolicySelection, observation: GameObservation) {
        lock.withLock {
            sources[selection.source, default: 0] += 1
            if let reason = selection.fallbackReason { fallbacks[reason, default: 0] += 1 }
            if !observation.legalMoves.contains(selection.move) { illegal += 1 }
        }
    }

    func snapshot(into result: inout UpstreamCompletionResult) {
        lock.withLock {
            result.sources = sources
            result.fallbacks = fallbacks
            result.illegalSelections = illegal
            result.evaluations = sources.values.reduce(0, +)
        }
    }
}

private struct AuditedUpstreamHybrid: Policy {
    let hybrid: UpstreamPolicy
    let ledger: UpstreamCompletionLedger
    var id: String { hybrid.id }

    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        select(observation, rng: &rng).move
    }

    func select(_ observation: GameObservation, rng: inout RandomSource) -> PolicySelection {
        let selection = hybrid.select(observation, rng: &rng)
        ledger.record(selection, observation: observation)
        return selection
    }
}

private func completionPolicies(network: UpstreamNetwork, state: GameState,
                                ledger: UpstreamCompletionLedger) -> [PlayerID: any Policy] {
    let personalities: [(BotPersonality, String)] = [
        (.balanced, "balanced"), (.aggressive, "aggressive"), (.cautious, "cautious"), (.balanced, "balanced"),
    ]
    var policies: [PlayerID: any Policy] = [:]
    for (index, player) in state.players.enumerated() {
        let (personality, name) = personalities[index]
        let fallback = HeuristicPolicy(personality: personality, id: "heuristic-\(name)-default")
        policies[player.id] = AuditedUpstreamHybrid(hybrid: UpstreamPolicy(network: network, fallback: fallback), ledger: ledger)
    }
    return policies
}

private func runUpstreamCompletion(network: UpstreamNetwork, players: Int,
                                   target: Int, seed: UInt64) -> UpstreamCompletionResult {
    let started = ContinuousClock.now
    let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed,
                                  playerCount: players, victoryPointTarget: target)
    let ledger = UpstreamCompletionLedger()
    let policies = completionPolicies(network: network, state: state, ledger: ledger)
    var session = GameSession(state: state, policies: policies, policySeed: seed &* 31 &+ 7)
    var result = UpstreamCompletionResult(players: players, target: target, seed: seed)
    result.policyIDs = state.players.map { policies[$0.id]!.id }
    var trace = UpstreamCompletionTrace()
    do {
        try advanceUpstreamCompletion(session: &session, result: &result, trace: &trace, started: started)
    } catch {
        result.status = "failure"
        result.failure = String(describing: error)
    }
    ledger.snapshot(into: &result)
    result.sessionEvaluations = session.policyEvaluationCount
    result.vp = session.state.players.map { session.state.victoryPoints(for: $0.id) }
    result.fingerprint = trace.fingerprint
    let elapsed = started.duration(to: .now).components
    result.elapsedSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    return result
}

private enum UpstreamCompletionFailure: Error {
    case missingDecision(GameSession.NextActor)
    case decisionOutsideMask
}

private func advanceUpstreamCompletion(session: inout GameSession, result: inout UpstreamCompletionResult,
                                       trace: inout UpstreamCompletionTrace, started: ContinuousClock.Instant) throws {
    while true {
        if case .gameOver(let winner) = session.nextActor() {
            result.status = "completed"
            result.winner = winner.index
            return
        }
        if result.actions >= upstreamCompletionActionLimit { result.status = "action_cap"; return }
        if started.duration(to: .now) >= upstreamCompletionWallLimit { result.status = "wall_clock_cap"; return }
        guard let decision = session.decideNextDetailed() else {
            throw UpstreamCompletionFailure.missingDecision(session.nextActor())
        }
        guard decision.observation.legalMoves.contains(decision.move) else {
            throw UpstreamCompletionFailure.decisionOutsideMask
        }
        let step = try session.commit(seat: decision.seat, move: decision.move)
        result.actions += 1
        recordCommittedStep(step, into: &result)
        trace.append(step: step, state: session.state)
    }
}

private func recordCommittedStep(_ step: GameSession.Step, into result: inout UpstreamCompletionResult) {
    result.moves[completionMoveKind(step.move), default: 0] += 1
    guard let trace = step.policyTrace else { result.missingTraces += 1; return }
    result.committedSources[trace.selection.source, default: 0] += 1
    if let reason = trace.selection.fallbackReason { result.committedFallbacks[reason, default: 0] += 1 }
    if let reason = trace.sessionOverride { result.overrides[reason, default: 0] += 1 }
}

private func assertUpstreamCompletion(_ result: UpstreamCompletionResult) {
    let label = "players=\(result.players) target=\(result.target) seed=\(result.seed)"
    #expect(result.status == "completed", "\(label): \(result.status); \(result.failure ?? "")")
    #expect(result.illegalSelections == 0, "\(label): a selection left its supplied action mask")
    #expect(result.missingTraces == 0, "\(label): committed moves lost selection provenance")
    #expect(result.evaluations == result.sessionEvaluations, "\(label): selection telemetry was omitted or duplicated")
    #expect(result.sources["neural", default: 0] > 0, "\(label): no neural decisions reached the game")
    let intentionalFallbacks: Set<String> = [
        "heuristic_trade_proposal", "player_trade_negotiation", "unsupported_pre_roll_development_card",
    ]
    let unexpected = result.fallbacks.keys.filter { !intentionalFallbacks.contains($0) }.sorted()
    #expect(unexpected.isEmpty, "\(label): unexpected fallback reasons \(unexpected)")
    if let winner = result.winner {
        #expect(result.vp.indices.contains(winner) && result.vp[winner] >= result.target, "\(label): invalid winner")
    }
}

private func emitUpstreamCompletion(_ result: UpstreamCompletionResult) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(result)
    FileHandle.standardOutput.write(Data("UPSTREAM_COMPLETION ".utf8) + data + Data("\n".utf8))
}

/// FNV-1a over the actual committed moves and post-move chance outcomes.
/// Dictionary payloads use Resource.allCases; no hash-seeded rendering reaches
/// this digest. Actor IDs, card/hand changes, dice and robber position are all
/// included, so matching just the strategic choices cannot hide different luck.
private struct UpstreamCompletionTrace {
    private var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    var fingerprint: String { String(format: "%016llx", hash) }

    mutating func append(step: GameSession.Step, state: GameState) {
        var text = "p\(step.actor.index):\(canonicalCompletionMove(step.move))|dice=\(state.lastDiceRoll ?? 0)"
        text += "|robber=\(state.board.robberTile)|bank=\(completionResourceTable(state.bank))"
        for player in state.players {
            text += "|p\(player.id.index):\(completionResourceTable(player.resources))"
            text += ":dev=\(player.devCards.map(\.rawValue).joined(separator: ","))"
            text += ":knights=\(player.playedKnights):vp=\(state.victoryPoints(for: player.id))"
        }
        text += "\n"
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
    }
}

private func canonicalCompletionMove(_ move: GameMove) -> String {
    switch move {
    case .discard(let cards): return "discard[\(completionResourceTable(cards))]"
    case .bankTrade(let give, let get): return "bank[\(completionResourceTable(give))>\(completionResourceTable(get))]"
    case .proposeTrade(let offer):
        return "offer[\(offer.id):p\(offer.from.index):\(completionResourceTable(offer.give))>\(completionResourceTable(offer.want))]"
    default: return String(describing: move)
    }
}

private func completionResourceTable(_ cards: [Resource: Int]) -> String {
    Resource.allCases.map { "\($0.rawValue)=\(cards[$0, default: 0])" }.joined(separator: ",")
}

private func completionMoveKind(_ move: GameMove) -> String {
    switch move {
    case .placeInitialSettlement: return "initial_settlement"
    case .placeInitialRoad: return "initial_road"
    case .rollDice: return "roll"
    case .buildRoad: return "road"
    case .buildSettlement: return "settlement"
    case .buildCity: return "city"
    case .buyDevCard: return "buy_dev"
    case .playKnight: return "knight"
    case .playRoadBuilding: return "road_building"
    case .playYearOfPlenty: return "year_of_plenty"
    case .playMonopoly: return "monopoly"
    case .moveRobber: return "robber"
    case .discard: return "discard"
    case .bankTrade: return "bank_trade"
    case .proposeTrade: return "propose_trade"
    case .respondToTrade(_, let accept): return accept ? "accept_trade" : "reject_trade"
    case .endTurn: return "end_turn"
    }
}
