import CatanAI
import CatanEngine
import Foundation

/// The app's `GameLogStore` lines, as far as a replay needs them. Kept apart
/// from the app type on purpose: the app target cannot be imported here, and
/// this reader needs only the start state, the roster's human seats, and the
/// moves with their training provenance. Timestamps are not read.
private struct LogLine: Decodable {
    struct Roster: Decodable {
        let humanSeats: Set<PlayerID>?
        let humanSeat: PlayerID?
    }
    let kind: String
    let initialState: GameState?
    let roster: Roster?
    let player: PlayerID?
    let move: GameMove?
    let isHumanDecision: Bool?
}

enum LogFileError: Error {
    case noStart(String)
    case malformed(String, line: Int)
}

/// A ranked game fetched from CloudKit (`scripts/cloudkit-games.py`): the
/// app's `SharedMatch` plus its uploader. The person seat is the uploader's.
private struct CloudGame: Decodable {
    struct Game: Decodable {
        struct Move: Decodable {
            let player: PlayerID
            let move: GameMove
            let isHumanDecision: Bool?
        }
        let seats: [String]
        let initialState: GameState
        let moves: [Move]
    }
    let owner: String
    let game: Game
}

func loadGame(_ url: URL) throws -> LoggedGame {
    if url.pathExtension == "json" { return try loadCloudGame(url) }
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    let decoder = JSONDecoder()
    var start: LogLine?
    var events: [LoggedMove] = []
    for (number, line) in lines.enumerated() {
        guard let parsed = try? decoder.decode(LogLine.self, from: Data(line.utf8)) else {
            throw LogFileError.malformed(url.lastPathComponent, line: number + 1)
        }
        if parsed.kind == "start" { start = parsed }
        if parsed.kind == "move", let player = parsed.player, let move = parsed.move {
            events.append(LoggedMove(player: player, move: move,
                                     isHumanDecision: parsed.isHumanDecision ?? true))
        }
    }
    guard let start, let initial = start.initialState else { throw LogFileError.noStart(url.lastPathComponent) }
    let humans = start.roster?.humanSeats ?? start.roster?.humanSeat.map { [$0] } ?? []
    return LoggedGame(id: url.deletingPathExtension().lastPathComponent, initialState: initial,
                      humanSeats: humans, events: events)
}

func loadCloudGame(_ url: URL) throws -> LoggedGame {
    let cloud = try JSONDecoder().decode(CloudGame.self, from: Data(contentsOf: url))
    let people = cloud.game.seats.indices.filter { cloud.game.seats[$0].hasPrefix("person:") }
    return LoggedGame(id: url.deletingPathExtension().lastPathComponent, initialState: cloud.game.initialState,
                      humanSeats: Set(people.map { cloud.game.initialState.players[$0].id }),
                      events: cloud.game.moves.map {
                          LoggedMove(player: $0.player, move: $0.move, isHumanDecision: $0.isHumanDecision ?? true)
                      })
}
