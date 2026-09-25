import CatanAI
import CatanEngine
import Foundation

/// The app's `GameLogStore` lines, as far as a replay needs them. Kept apart
/// from the app type on purpose: the app target cannot be imported here, and
/// this reader needs only the start state, the roster's human seats, and the
/// moves. Timestamps are not read.
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
}

enum LogFileError: Error {
    case noStart(String)
    case malformed(String, line: Int)
}

func loadGame(_ url: URL) throws -> LoggedGame {
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
            events.append(LoggedMove(player: player, move: move))
        }
    }
    guard let start, let initial = start.initialState else { throw LogFileError.noStart(url.lastPathComponent) }
    let humans = start.roster?.humanSeats ?? start.roster?.humanSeat.map { [$0] } ?? []
    return LoggedGame(id: url.deletingPathExtension().lastPathComponent, initialState: initial,
                      humanSeats: humans, events: events)
}
