import CatanAI
import CatanEngine
import Foundation

/// Separate from the historical schema-5 sim: naval topology and settings are
/// explicit provenance, never labels inferred from an older board generator.
private struct Result: Encodable {
    let schemaVersion = 4
    let protocolVersion = EvaluationProtocol.version
    let rulesVersion = Naval.currentRulesVersion
    let engineRulesVersion = RulesEngine.currentRulesVersion
    let mapVersion: Int
    let buildID: String
    let arm: String
    let focalChair: Int
    let playerCount: Int
    let family: NavalMapFamily
    let fogEnabled: Bool
    let resourceChoiceEnabled: Bool
    let shipStealingEnabled: Bool
    let navalAIRevision: NavalPolicy.Revision
    let policies: [String]
    let seed: UInt64
    let actionLimit = EvaluationProtocol.actionLimit
    let victoryPointTarget: Int
    let moves: Int
    let winner: Int?
    let victoryPoints: [Int]
    let fingerprint: String
    let forcedEnds: Int
    let sailingCycles: Int
    let idleSailingCycles: Int
    let tradeCycles: Int
    let duplicateProposals: Int
    let behavior: [SeatDiagnostics]
}

private func play(seed: UInt64, options: Options) throws -> Result {
    let state = Naval.newGame(seed: seed, playerCount: options.players,
        options: NavalOptions(fogEnabled: options.fog, resourceChoiceEnabled: options.wild,
                              mapFamily: options.family, shipStealingEnabled: options.shipStealing))
    let policies = Dictionary(uniqueKeysWithValues: state.players.map {
        ($0.id, options.policy(at: $0.id.index, in: state))
    })
    var session = GameSession(state: state, policies: policies, policySeed: seed &* 31 &+ 7)
    var diagnostics = Diagnostics(players: options.players)
    var trace: [String] = []
    var audits: [AuditRow] = []
    let clock = ContinuousClock()
    for action in 0..<EvaluationProtocol.actionLimit {
        guard case .seat = session.nextActor() else { break }
        let start = clock.now
        guard let decision = session.decideNextDetailed() else {
            failureArtifact(session.checkpoint, trace: trace, seed: seed, options: options,
                reason: "No decision at action \(action)")
            throw RunFailure(description: "seed \(seed) action \(action): automated session has no decision")
        }
        let elapsed = start.duration(to: clock.now).components
        diagnostics.decision(decision, milliseconds: Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
        let before = session.state
        let beforeLedger = options.auditDirectory == nil ? nil : session.ledger(for: decision.seat)
        let step: GameSession.Step
        do {
            step = try session.commit(seat: decision.seat, move: decision.move)
            try verifyCheckpoint(session.checkpoint)
        } catch {
            let reason = "Action \(action), P\(decision.seat.index):\(Rendering.canonical(decision.move)): \(error)"
            failureArtifact(session.checkpoint, trace: trace, seed: seed, options: options, reason: reason)
            throw RunFailure(description: "seed \(seed): \(reason)")
        }
        diagnostics.applied(step, before: before, after: session.state)
        trace.append("P\(step.actor.index):\(Rendering.canonical(step.move))")
        if let beforeLedger, decision.seat.index == options.focalChair,
           options.seats[decision.seat.index] != "land-control" {
            audits.append(AuditRow(seed: seed, action: trace.count - 1, decision: decision, ledger: beforeLedger,
                after: session.state, tier: options.seats[decision.seat.index] == "expert" ? .expert : .traditional,
                revision: options.revision(in: state)))
        }
    }
    let winner: Int?
    if case .gameOver(let seat) = session.state.phase { winner = seat.index } else { winner = nil }
    if winner == nil || diagnostics.forcedEnds > 0 || diagnostics.sailingCycles > 0 || diagnostics.tradeCycles > 0 {
        let reason = "Completion/revisit evidence: winner=\(String(describing: winner)), forced=\(diagnostics.forcedEnds), "
            + "raw sailing=\(diagnostics.sailingCycles), idle sailing=\(diagnostics.idleSailingCycles), trading=\(diagnostics.tradeCycles)"
        failureArtifact(session.checkpoint, trace: trace, seed: seed, options: options,
            reason: reason)
    }
    if let directory = options.traceDirectory {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = URL(fileURLWithPath: directory).appendingPathComponent("\(seed)-\(options.focalChair)-\(options.arm).txt")
        try trace.joined(separator: "\n").appending("\n").write(to: path, atomically: true, encoding: .utf8)
    }
    if let directory = options.auditDirectory {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = URL(fileURLWithPath: directory).appendingPathComponent("\(seed)-\(options.focalChair)-\(options.arm).jsonl")
        let rows = try audits.map { try Rendering.json($0) }.joined(separator: "\n") + "\n"
        try rows.write(to: path, atomically: true, encoding: .utf8)
    }
    latency(diagnostics.decisionMilliseconds, seed: seed)
    return Result(mapVersion: Naval.currentMapVersion, buildID: options.buildID, arm: options.arm,
        focalChair: options.focalChair, playerCount: options.players, family: options.family,
        fogEnabled: options.fog, resourceChoiceEnabled: options.wild,
        shipStealingEnabled: options.shipStealing, navalAIRevision: options.revision(in: state),
        policies: state.players.map { policies[$0.id]!.id }, seed: seed,
        victoryPointTarget: state.victoryPointTarget, moves: trace.count, winner: winner,
        victoryPoints: session.state.players.map { session.state.victoryPoints(for: $0.id) },
        fingerprint: Rendering.fingerprint(trace), forcedEnds: diagnostics.forcedEnds,
        sailingCycles: diagnostics.sailingCycles, idleSailingCycles: diagnostics.idleSailingCycles, tradeCycles: diagnostics.tradeCycles,
        duplicateProposals: diagnostics.duplicateProposals, behavior: diagnostics.seats)
}

/// Matches the app's persistence boundary. A legal trajectory whose durable
/// queue cannot reload is a failed match, never a headless success.
private func verifyCheckpoint(_ checkpoint: GameSession.Checkpoint) throws {
    try checkpoint.validate()
    let data = try JSONEncoder().encode(checkpoint)
    let decoded = try JSONDecoder().decode(GameSession.Checkpoint.self, from: data)
    try decoded.validate()
    guard decoded == checkpoint else { throw RunFailure(description: "Checkpoint round-trip changed session state") }
}

private struct RunFailure: Error, CustomStringConvertible { let description: String }

/// Failure evidence is small and unconditional; long held-out runs do not need
/// thousands of successful traces to preserve every rejection for inspection.
private func failureArtifact(_ checkpoint: GameSession.Checkpoint, trace: [String], seed: UInt64,
                             options: Options, reason: String) {
    let directory = options.traceDirectory ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("naval-sim-failures").path
    let name = "\(seed)-\(options.players)-\(options.focalChair)-\(options.arm)-\(options.family.rawValue)-\(options.fog)-\(options.wild)"
    let base = URL(fileURLWithPath: directory).appendingPathComponent(name)
    do {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(checkpoint).write(to: base.appendingPathExtension("json"), options: .atomic)
        try trace.joined(separator: "\n").appending("\n").write(to: base.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        try "build=\(options.buildID)\n\(reason)\n".write(to: base.appendingPathExtension("failure"), atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data("naval-sim rejection evidence: \(base.path)\n".utf8))
    } catch {
        FileHandle.standardError.write(Data("naval-sim could not save rejection evidence: \(error)\n".utf8))
    }
}

private func latency(_ samples: [Double], seed: UInt64) {
    let sorted = samples.sorted()
    guard !sorted.isEmpty else { return }
    let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
    let p99 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))]
    let over50 = sorted.filter { $0 > 50 }.count
    let over150 = sorted.filter { $0 > 150 }.count
    let line = String(format: "naval-sim seed=%llu decisions=%d p95=%.3fms p99=%.3fms over50=%d over150=%d\n",
                      seed, sorted.count, p95, p99, over50, over150)
    FileHandle.standardError.write(Data(line.utf8))
}

private let options = Options.parse(CommandLine.arguments)
do {
    for offset in 0..<options.games {
        let result = try play(seed: options.seed + UInt64(offset), options: options)
        FileHandle.standardOutput.write(Data((try Rendering.json(result) + "\n").utf8))
    }
} catch { Options.fail("seeded naval run failed: \(error)") }
