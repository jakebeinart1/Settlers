import CatanEngine
import Foundation

struct ReplayExportAnalysis: Sendable, Equatable {
    static let reconstructionNotice = "Recorded rules are used when available. Missing rule versions use current rules; "
        + "older or mixed-version recordings may differ from the original."
    static let unknownRulesNotice = "Recorded rules versions are unavailable for some moves. Current rules are used only "
        + "for those moves; older or mixed-version games may differ from the original."

    let lastMove: Int
    let recordedMoves: Int
    let winner: PlayerID?
    let notice: String
    let hasUnknownRulesVersions: Bool

    var reconstructionLabel: String {
        hasUnknownRulesVersions ? "Current rules for unknown moves · Older rules unknown" : "Reconstructed with recorded rules"
    }

    var isPartial: Bool { winner == nil }
    var status: String {
        isPartial ? "Partial replay · \(lastMove) of \(recordedMoves) moves" : "Replay · \(recordedMoves) moves"
    }
}

/// Two linear walks, no array of states: preflight determines the valid prefix
/// so even the FIRST exported frame can say that a recording is partial.
/// The second walk yields one public position at a time to the movie writer.
/// Recorded versions use RulesEngine.replay in BOTH walks. Legacy JSONL can
/// lack per-move versions; only those moves use current apply, never a guessed
/// oldest version. Their current-rule reconstruction may succeed yet differ
/// from the original game, so every frame carries an explicit unknown label.
struct ReplayExportSequence: Sendable {
    let analysis: ReplayExportAnalysis
    private let detail: GameLogDetail
    private let presentation: ReplayExportPresentation
    private var state: GameState
    private var nextPosition = 0

    init(detail: GameLogDetail, includeNames: Bool = false) throws {
        let players = detail.initialState.players
        guard (3...4).contains(players.count),
              players.enumerated().allSatisfy({ $0.offset == $0.element.id.index }) else {
            throw ReplayVideoExportError.invalidRecording
        }
        analysis = try Self.inspect(detail)
        self.detail = detail
        presentation = ReplayExportPresentation(roster: detail.roster, players: players, includeNames: includeNames)
        state = detail.initialState
    }

    mutating func next() throws -> ReplayExportFrame? {
        try Task.checkCancellation()
        guard nextPosition <= analysis.lastMove else { return nil }
        var caption = "Opening position"
        if nextPosition > 0 {
            let entry = detail.events[nextPosition - 1]
            let events = try Self.applyRecorded(entry, to: &state)
            caption = presentation.caption(events: events, entry: entry)
        }
        let frame = presentation.frame(state: state, position: nextPosition, caption: caption, analysis: analysis)
        nextPosition += 1
        return frame
    }

    func closingFrame(from frame: ReplayExportFrame) -> ReplayExportFrame {
        let caption = analysis.winner.map { "\(presentation.identities[$0.index].displayName) wins" }
            ?? analysis.notice
        return presentation.frame(state: frame.boardState, position: analysis.lastMove,
                                  caption: caption, analysis: analysis)
    }

    private static func inspect(_ detail: GameLogDetail) throws -> ReplayExportAnalysis {
        var state = detail.initialState
        var lastMove = 0
        for entry in detail.events {
            try Task.checkCancellation()
            guard state.players.indices.contains(entry.player.index) else { break }
            // Failed application may have mutated its inout argument; only
            // publish a candidate after success, keeping the valid prefix exact.
            var candidate = state
            do { try applyRecorded(entry, to: &candidate) } catch { break }
            state = candidate
            lastMove += 1
        }
        let winner: PlayerID?
        if lastMove == detail.events.count, detail.isComplete,
           case .gameOver(let actualWinner) = state.phase, actualWinner == detail.summary.winner,
           state.players.indices.contains(actualWinner.index) {
            winner = actualWinner
        } else {
            winner = nil
        }
        let notice = lastMove < detail.events.count
            ? "Recording could not be reconstructed beyond move \(lastMove) of \(detail.events.count)."
            : "This recording does not contain a verified ending."
        let unknownRules = detail.events.isEmpty || detail.events.contains { $0.rulesVersion == nil }
        let rulesNotice = unknownRules ? ReplayExportAnalysis.unknownRulesNotice : "Reconstructed with recorded rules."
        return ReplayExportAnalysis(lastMove: lastMove, recordedMoves: detail.events.count, winner: winner,
                                    notice: winner == nil ? notice + " " + rulesNotice : rulesNotice,
                                    hasUnknownRulesVersions: unknownRules)
    }

    /// This is the only rule dispatch for inspection and emitted positions.
    /// Unsupported known versions fail normally and produce a partial prefix;
    /// they must not silently fall back to a different supported version.
    @discardableResult
    private static func applyRecorded(_ entry: GameLogEvent, to state: inout GameState) throws -> [GameEvent] {
        if let version = entry.rulesVersion {
            return try RulesEngine.replay(entry.move, by: entry.player, rulesVersion: version, to: &state)
        }
        return try RulesEngine.apply(entry.move, by: entry.player, to: &state)
    }
}
