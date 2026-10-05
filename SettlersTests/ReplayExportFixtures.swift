import CatanEngine
import Foundation
@testable import Settlers

/// Small production-shaped move recordings, without touching the app's stores
/// or starting bot experiments. The complete marker can deliberately disagree
/// with the engine ending to exercise the export's honesty guard.
enum ReplayExportFixtures {
    static func recording(moves: Int = 4) throws -> GameLogDetail {
        let initial = GameSetup.newGame(board: BoardGenerator.standard(), seed: 41)
        var state = initial
        var entries: [GameLogEvent] = []
        for index in 0..<moves {
            guard let actor = state.phase.awaitingSeatIndex.map({ PlayerID(index: $0) }),
                  let move = RulesEngine.legalMoves(for: state, seat: actor).first else { break }
            try RulesEngine.apply(move, by: actor, to: &state)
            entries.append(GameLogEvent(timestamp: Date(timeIntervalSince1970: Double(index)), player: actor, move: move))
        }
        return detail(initial: initial, events: entries)
    }

    /// A version-1 nil-victim robber move is rejected by current rules but
    /// must still move the public robber in an archived game. The next move
    /// uses current rules, exercising exact versions through the JSONL seam.
    static func mixedRulesRecording(directory: URL) throws -> GameLogDetail {
        var initial = GameSetup.newGame(board: BoardGenerator.standard(), seed: 912)
        guard let target = initial.board.tiles.map(\.coordinate).first(where: { $0 != initial.board.robberTile }),
              let vertex = initial.board.corners(of: target).first else {
            throw ReplayVideoExportError.invalidRecording
        }
        initial.phase = .movingRobber(playerIndex: 0)
        initial.robberMoverIndex = 0
        initial.players[1].settlements.insert(vertex)
        initial.players[1].resources = [.lumber: 1]
        let setup = MatchSetup(seats: initial.players.map { player in
            MatchSetup.Seat(index: player.id.index, isHuman: true, name: "Player \(player.id.index + 1)",
                            civilization: Civilization.allCases[player.id.index])
        }, victoryPointTarget: initial.victoryPointTarget, randomizedBoard: false, randomizeSeatOrder: false)
        var match = MatchCheckpoint(id: UUID(), initialState: initial, setup: setup)
        try match.apply(.moveRobber(target, stealFrom: nil), by: PlayerID(index: 0),
                        rulesVersion: RulesEngine.oldestSupportedRulesVersion)
        try match.apply(.endTurn, by: PlayerID(index: 0), rulesVersion: RulesEngine.currentRulesVersion)
        let logs = GameLogStore(directoryURL: directory, maxKeptLogs: 1)
        let url = try logs.export(checkpoint: match)
        return try logs.detail(for: url)
    }

    static func detail(initial: GameState, events: [GameLogEvent] = [],
                       complete: Bool = false, winner: PlayerID? = nil) -> GameLogDetail {
        let id = UUID()
        let names = Dictionary(uniqueKeysWithValues: initial.players.map { ($0.id.index, "PRIVATE_NAME_\($0.id.index)") })
        let roster = GameLogStore.SeatRoster(humanSeats: [PlayerID(index: 0)], humanNames: [0: "PRIVATE_NAME_0"],
                                             botProfiles: [1: "PRIVATE_GHOST_ID"], botProfileNames: names,
                                             botPersonalities: [:], civilizations: [:])
        let summary = GameLogSummary(gameID: id, fileURL: URL(fileURLWithPath: "/diagnostic/\(id).jsonl"),
                                     startedAt: Date(timeIntervalSince1970: 1_234), duration: 42,
                                     playerCount: initial.players.count, mode: initial.mode,
                                     victoryPointTarget: initial.victoryPointTarget, humanSeats: roster.humanSeats,
                                     winner: winner, moveCount: events.count, civilizations: [:],
                                     playerNames: names, isComplete: complete)
        return GameLogDetail(initialState: initial, summary: summary, roster: roster, events: events)
    }
}
