#if DEBUG
import Foundation
import CatanEngine

/// A process-termination probe, isolated from player saves and enabled only by
/// explicit Debug launch arguments. The host kills the app after observing the
/// boundary marker, then launches another process to read the committed state.
@MainActor
enum CheckpointProcessProbe {
    static func runIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let flag = arguments.firstIndex(of: "-checkpoint-process-probe") else { return }
        do {
            guard arguments.indices.contains(flag + 2), UUID(uuidString: arguments[flag + 2]) != nil else {
                throw ProbeError.invalidArguments
            }
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("CheckpointProcessProbes").appendingPathComponent(arguments[flag + 2])
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try run(mode: arguments[flag + 1], directory: directory)
        } catch {
            preconditionFailure("Checkpoint process probe failed: \(error)")
        }
    }

    private enum ProbeError: Error { case invalidArguments, missingDocument, missingMove }

    private static func run(mode: String, directory: URL) throws {
        let file = directory.appendingPathComponent("checkpoint.json")
        let store = MatchCheckpointStore(fileURL: file)
        if mode == "initialize" {
            let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 471)
            let setup = MatchSetup.default(preferredName: "Probe", preferredCivilization: Civilization.allCases[0])
            let match = MatchCheckpoint(id: UUID(), initialState: state, setup: setup)
            try store.commit(MatchCheckpointDocument(activeMatch: match), replacingRevision: nil)
            try Data("initialized".utf8).write(to: directory.appendingPathComponent("initialized"), options: .atomic)
        } else if mode == "read" {
            guard let document = try store.load(), let match = document.activeMatch else {
                throw ProbeError.missingDocument
            }
            let report = "\(document.revision),\(match.moves.count),\(match.state.players[0].settlements.count)"
            try Data(report.utf8).write(to: directory.appendingPathComponent("result"), options: .atomic)
        } else {
            guard mode == "before" || mode == "after" else { throw ProbeError.invalidArguments }
            try advanceAndHold(store: store, mode: mode, directory: directory)
        }
    }

    private static func advanceAndHold(store: MatchCheckpointStore, mode: String, directory: URL) throws {
        guard let document = try store.load(), let match = document.activeMatch else { throw ProbeError.missingDocument }
        var session = GameSession(state: match.state, policies: [:], policySeed: 99)
        let seat = PlayerID(index: 0)
        guard let move = RulesEngine.legalMoves(for: match.state, seat: seat).first else { throw ProbeError.missingMove }
        let step = try session.applyExternal(move, by: seat)
        let next = try document.recording(step, session: session.checkpoint, elapsedSeconds: 12)
        let interruptible = MatchCheckpointStore(fileURL: store.fileURL, atCommitStage: { stage in
            let reachedTarget = mode == "before" ? stage == .beforeReplace : stage == .afterReplace
            guard reachedTarget else { return }
            try Data(mode.utf8).write(to: directory.appendingPathComponent("ready"), options: .atomic)
            // Deliberately stay inside the write boundary until the host sends
            // process termination. No cleanup handler or thrown error runs.
            while true { Thread.sleep(forTimeInterval: 1) }
        })
        try interruptible.commit(next, replacingRevision: document.revision)
    }
}
#endif
