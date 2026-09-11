import Foundation
import CatanEngine
import CatanAI
import FrozenCatanAI
let games = Int(CommandLine.arguments.dropFirst().first ?? "12")!
for arm in ["old", "new", "mixed"] {
 for offset in 0..<games {
  let seed = UInt64(11001 + offset)
  let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed, shape: .expanded), seed: seed, mode: .expanded)
  let hero = offset % 4
  var policies: [PlayerID: any Policy] = [:]
  for player in state.players {
   if arm == "new" || (arm == "mixed" && player.id.index == hero) {
    policies[player.id] = CatanAI.HeuristicPolicy(personality: .balanced, id: "new")
   } else {
    policies[player.id] = FrozenCatanAI.HeuristicPolicy(personality: .balanced, id: "old")
   }
  }
  var session = GameSession(state: state, policies: policies, policySeed: seed &* 31 &+ 7)
  var moves = 0, turns = 0, earlyCards = 0, earlyRoads = 0
  var earlyBuildings = 0
  let start = Date()
  for _ in 0..<3000 {
   guard case .seat = session.nextActor(), let step = try session.step() else { break }
   moves += 1
   if turns < 40 {
    switch step.move {
    case .buyDevCard: earlyCards += 1
    case .buildRoad: earlyRoads += 1
    case .buildSettlement, .buildCity: earlyBuildings += 1
    default: break
    }
   }
   if case .endTurn = step.move { turns += 1 }
  }
  let winner: Int
  if case .gameOver(let player) = session.state.phase { winner = player.index } else { winner = -1 }
  let record: [String: Any] = [
   "arm": arm, "seed": seed, "hero": hero, "winner": winner, "moves": moves, "turns": turns,
   "earlyCards": earlyCards, "earlyRoads": earlyRoads, "earlyBuildings": earlyBuildings,
   "scores": session.state.players.map { session.state.victoryPoints(for: $0.id) },
   "seconds": Date().timeIntervalSince(start)
  ]
  print(String(data: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), encoding: .utf8)!)
 }
}
