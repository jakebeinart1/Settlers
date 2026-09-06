import CatanEngine
import Foundation

// Offline saved-state inspection only: no policy evaluation or move application.
struct Input: Decodable { let moveIndex: Int; let state: GameState }
struct Result: Encodable {
    let moveIndex: Int
    let points: Int
    let roadSites: Int
    let settlementSites: Int
    let citySites: Int
    let roadCount: Int
    let longestRoadLength: Int
    let devDeckCount: Int
}

let inputs = try JSONDecoder().decode([Input].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
guard let seatIndex = Int(CommandLine.arguments[2]) else { fatalError("expected seat index") }
let seat = PlayerID(index: seatIndex)
let results = inputs.map { input in
    let state = input.state
    let player = state.players[seatIndex]
    return Result(moveIndex: input.moveIndex, points: state.victoryPoints(for: seat),
                  roadSites: state.board.onBoardEdges.filter { Building.canBuildRoad($0, for: seat, in: state) }.count,
                  settlementSites: state.board.onBoardVertices.filter { Building.canBuildSettlement($0, for: seat, in: state) }.count,
                  citySites: player.settlements.filter { Building.canBuildCity($0, for: seat, in: state) }.count,
                  roadCount: player.roads.count, longestRoadLength: LongestRoad.length(for: player, in: state),
                  devDeckCount: state.devCardDeck.count)
}
try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(results))
