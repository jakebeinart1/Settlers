#if DEBUG
import Foundation
import CatanEngine

/// Exercises durability with real app termination. Each probe uses an
/// isolated directory; the shell harness kills the writer after a boundary
/// marker and launches a different process to inspect durable artifacts.
@MainActor
enum CheckpointProcessProbe {
    private enum Scenario: String { case human, bot, automaticTrade, export }
    private enum Boundary: String { case before, after, exported }
    private enum ProbeError: Error { case invalidArguments, missingDocument, missingMove }

    private struct ProbePolicy: Policy {
        let id = "checkpoint-probe"

        func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
            observation.legalMoves.first(where: {
                if case .respondToTrade(_, true) = $0 { return true }
                return false
            }) ?? observation.legalMoves[0]
        }
    }

    static func runIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let flag = arguments.firstIndex(of: "-checkpoint-process-probe") else { return }
        do {
            guard arguments.indices.contains(flag + 3),
                  let scenario = Scenario(rawValue: arguments[flag + 2]),
                  UUID(uuidString: arguments[flag + 3]) != nil else {
                throw ProbeError.invalidArguments
            }
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("CheckpointProcessProbes").appendingPathComponent(arguments[flag + 3])
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try run(mode: arguments[flag + 1], scenario: scenario, directory: directory)
        } catch {
            preconditionFailure("Checkpoint process probe failed: \(error)")
        }
    }

    private static func run(mode: String, scenario: Scenario, directory: URL) throws {
        let store = MatchCheckpointStore(fileURL: directory.appendingPathComponent("checkpoint.json"))
        switch mode {
        case "initialize":
            try initialize(scenario, store: store)
            try write("initialized", named: "initialized", in: directory)
        case "read":
            try writeReport(store: store, directory: directory)
        case Boundary.before.rawValue, Boundary.after.rawValue:
            guard let boundary = Boundary(rawValue: mode) else { throw ProbeError.invalidArguments }
            if scenario == .export {
                try exportAndAcknowledge(store: store, boundary: boundary, directory: directory)
            } else {
                try advance(store: store, scenario: scenario, boundary: boundary, directory: directory)
            }
        case Boundary.exported.rawValue where scenario == .export:
            try exportAndHold(store: store, directory: directory)
        default:
            throw ProbeError.invalidArguments
        }
    }

    private static func initialize(_ scenario: Scenario, store: MatchCheckpointStore) throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
        let setup = probeSetup()
        var session = GameSession(state: state, policies: policies(for: scenario), policySeed: 99)
        var match = MatchCheckpoint(id: UUID(), initialState: state, setup: setup)
        if scenario == .automaticTrade {
            state.phase = .mainTurn(playerIndex: 0)
            state.players[0].resources[.brick] = 1
            state.players[1].resources[.lumber] = 1
            session = GameSession(state: state, policies: policies(for: scenario), policySeed: 99)
            match = MatchCheckpoint(id: UUID(), initialState: state, setup: setup)
            let offer = TradeOffer.enumerated(from: PlayerID(index: 0), give: [.brick: 1], want: [.lumber: 1])
            let step = try session.commit(seat: PlayerID(index: 0), move: .proposeTrade(offer))
            try match.apply(step.move, by: step.actor)
        }
        try match.attachSession(session.checkpoint)
        try store.commit(MatchCheckpointDocument(activeMatch: match), replacingRevision: nil)
        if scenario == .export {
            let document = try requireDocument(store)
            try store.commit(try document.replacingActiveMatch(with: nil), replacingRevision: document.revision)
        }
    }

    private static func advance(store: MatchCheckpointStore, scenario: Scenario,
                                boundary: Boundary, directory: URL) throws {
        let document = try requireDocument(store)
        guard let match = document.activeMatch else { throw ProbeError.missingDocument }
        var session = try GameSession(checkpoint: try requireSession(match), policies: policies(for: scenario))
        let step: GameSession.Step
        if scenario == .human {
            let seat = PlayerID(index: 0)
            guard let move = RulesEngine.legalMoves(for: match.state, seat: seat).first else {
                throw ProbeError.missingMove
            }
            step = try session.applyExternal(move, by: seat)
        } else {
            guard let decided = try session.step() else { throw ProbeError.missingMove }
            step = decided
        }
        let next = try document.recording(step, session: session.checkpoint, elapsedSeconds: 12)
        try interruptibleStore(from: store, boundary: boundary, directory: directory)
            .commit(next, replacingRevision: document.revision)
    }

    private static func exportAndHold(store: MatchCheckpointStore, directory: URL) throws {
        let match = try requirePendingExport(store)
        _ = try logStore(in: directory).export(checkpoint: match)
        try write(Boundary.exported.rawValue, named: "ready", in: directory)
        holdUntilTerminated()
    }

    private static func exportAndAcknowledge(store: MatchCheckpointStore, boundary: Boundary,
                                             directory: URL) throws {
        let document = try requireDocument(store)
        let match = try requirePendingExport(store)
        _ = try logStore(in: directory).export(checkpoint: match)
        let next = try document.acknowledgingExport(of: match)
        try interruptibleStore(from: store, boundary: boundary, directory: directory)
            .commit(next, replacingRevision: document.revision)
    }

    private static func writeReport(store: MatchCheckpointStore, directory: URL) throws {
        let document = try requireDocument(store)
        let match = document.activeMatch ?? document.pendingExports.values.first
        let settlements = match?.state.players[0].settlements.count ?? 0
        let offers = match?.state.pendingTradeOffers.count ?? 0
        let archive = logStore(in: directory)
        let files = try archive.logFiles()
        let logMoves = try files.first.map { try archive.detail(for: $0).events.count } ?? 0
        let report = [document.revision, match?.moves.count ?? 0, settlements,
                      offers, document.pendingExports.count, files.count, logMoves]
            .map(String.init).joined(separator: ",")
        try write(report, named: "result", in: directory)
    }

    private static func policies(for scenario: Scenario) -> [PlayerID: any Policy] {
        switch scenario {
        case .human, .export: return [:]
        case .bot: return [PlayerID(index: 0): ProbePolicy()]
        case .automaticTrade:
            return [PlayerID(index: 0): ProbePolicy(), PlayerID(index: 1): ProbePolicy()]
        }
    }

    private static func probeSetup() -> MatchSetup {
        let seats = (0..<GameSetup.standardPlayerCount).map {
            MatchSetup.Seat(index: $0, isHuman: true, name: "Probe \($0 + 1)",
                            civilization: Civilization.allCases[$0])
        }
        return MatchSetup(seats: seats, victoryPointTarget: Ruleset.forMode(.classic).defaultVictoryPointTarget,
                          randomizedBoard: false, randomizeSeatOrder: false)
    }

    private static func interruptibleStore(from store: MatchCheckpointStore, boundary: Boundary,
                                           directory: URL) -> MatchCheckpointStore {
        MatchCheckpointStore(fileURL: store.fileURL, atCommitStage: { stage in
            let reached = boundary == .before ? stage == .beforeReplace : stage == .afterReplace
            guard reached else { return }
            try write(boundary.rawValue, named: "ready", in: directory)
            holdUntilTerminated()
        })
    }

    private static func requireDocument(_ store: MatchCheckpointStore) throws -> MatchCheckpointDocument {
        guard let document = try store.load() else { throw ProbeError.missingDocument }
        return document
    }

    private static func requirePendingExport(_ store: MatchCheckpointStore) throws -> MatchCheckpoint {
        guard let match = try requireDocument(store).pendingExports.values.first else {
            throw ProbeError.missingDocument
        }
        return match
    }

    private static func requireSession(_ match: MatchCheckpoint) throws -> GameSession.Checkpoint {
        guard let checkpoint = match.sessionCheckpoint else { throw ProbeError.missingDocument }
        return checkpoint
    }

    private static func logStore(in directory: URL) -> GameLogStore {
        GameLogStore(directoryURL: directory.appendingPathComponent("logs"), maxKeptLogs: 10)
    }

    private static func write(_ value: String, named name: String, in directory: URL) throws {
        try Data(value.utf8).write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    private static func holdUntilTerminated() -> Never {
        while true { Thread.sleep(forTimeInterval: 1) }
    }
}
#endif
