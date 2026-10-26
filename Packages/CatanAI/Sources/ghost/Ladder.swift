import CatanAI
import CatanEngine
import Foundation

/// One seat of one ranked game, as `ghost ladder` prints it (JSON lines):
/// who sat there, whether they won, and how their points were made.
struct LadderSeat: Encodable {
    let game: String
    let owner: String
    let ownerName: String
    /// The game's seat label: `person:<id>`, `expert`, `classic`, `ghost:<id>`...
    let label: String
    let seat: Int
    let won: Bool
    let finalVP: Int
    /// Rolls in the whole game, all seats.
    let gameTurns: Int
    let turns: Int
    let production: Int
    let openingPips: Int
    let openingResources: Int
    let settlements: Int
    let cities: Int
    let devBought: Int
    let knights: Int
    let progressPlayed: Int
    let vpCards: Int
    let largestArmy: Bool
    let longestRoad: Bool
    let discarded: Int
    let robbedTimes: Int
    let playerTrades: Int
    let bankTrades: Int
    /// Rolls (whole game) at which this seat first had 5 and 8 public points.
    let turnAt5: Int?
    let turnAt8: Int?
}

private struct CloudHeader: Decodable {
    let ownerName: String?
    let owner: String
    struct Game: Decodable { let seats: [String] }
    let game: Game
}

private struct Tally {
    var turns = 0, production = 0, settlements = 0, cities = 0, devBought = 0, knights = 0
    var progress = 0, discarded = 0, robbed = 0, playerTrades = 0, bankTrades = 0
    var turnAt5: Int?, turnAt8: Int?
}

func ladderSeats(_ url: URL) throws -> [LadderSeat] {
    let header = try JSONDecoder().decode(CloudHeader.self, from: Data(contentsOf: url))
    return try ladderSeats(try loadCloudGame(url), labels: header.game.seats, owner: header.owner,
                           ownerName: header.ownerName ?? header.owner)
}

/// Replays `game` and tallies every seat; `labels` names each seat.
func ladderSeats(_ game: LoggedGame, labels: [String], owner: String, ownerName: String) throws -> [LadderSeat] {
    var tallies = game.initialState.players.map { _ in Tally() }
    var session = GameSession(state: game.initialState, policies: [:], policySeed: 0)
    var rolls = 0
    var opening: [Int: [VertexID]] = [:]
    for logged in game.events {
        let before = session.state
        if case .placeInitialSettlement(let vertex) = logged.move { opening[logged.player.index, default: []].append(vertex) }
        let step = try session.applyExternal(logged.move, by: logged.player)
        if logged.move == .rollDice {
            rolls += 1
            for index in tallies.indices {
                let gained = session.state.players[index].resources.values.reduce(0, +)
                    - before.players[index].resources.values.reduce(0, +)
                tallies[index].production += max(0, gained)
            }
        }
        for event in step.events { tally(event, into: &tallies) }
        for index in tallies.indices {
            let points = session.state.publicVictoryPoints(for: session.state.players[index].id)
            if points >= 5, tallies[index].turnAt5 == nil { tallies[index].turnAt5 = rolls }
            if points >= 8, tallies[index].turnAt8 == nil { tallies[index].turnAt8 = rolls }
        }
    }
    let final = session.state
    let pips: (HexCoordinate) -> Int = { hex in
        final.board.tiles.first { $0.coordinate == hex }?.numberToken.map(DiceOdds.pips(for:)) ?? 0
    }
    let kind: (HexCoordinate) -> TileKind? = { hex in final.board.tiles.first { $0.coordinate == hex }?.kind }
    return final.players.indices.map { index in
        let player = final.players[index]
        let tally = tallies[index]
        let corners = opening[index] ?? []
        var winner: PlayerID?
        if case .gameOver(let id) = final.phase { winner = id }
        return LadderSeat(
            game: game.id, owner: owner, ownerName: ownerName,
            label: labels[index], seat: index, won: winner == player.id,
            finalVP: final.victoryPoints(for: player.id), gameTurns: rolls, turns: tally.turns,
            production: tally.production,
            openingPips: corners.flatMap(\.touchingTiles).map(pips).reduce(0, +),
            openingResources: Set(corners.flatMap(\.touchingTiles).compactMap { pips($0) > 0 ? kind($0) : nil }).count,
            settlements: tally.settlements, cities: tally.cities, devBought: tally.devBought,
            knights: tally.knights, progressPlayed: tally.progress,
            vpCards: player.devCards.filter { $0 == .victoryPoint }.count,
            largestArmy: final.largestArmyPlayer == player.id, longestRoad: final.longestRoadPlayer == player.id,
            discarded: tally.discarded, robbedTimes: tally.robbed, playerTrades: tally.playerTrades,
            bankTrades: tally.bankTrades, turnAt5: tally.turnAt5, turnAt8: tally.turnAt8)
    }
}

private func tally(_ event: GameEvent, into tallies: inout [Tally]) {
    switch event {
    case .rolled(let seat, _): tallies[seat.index].turns += 1
    case .builtSettlement(let seat): tallies[seat.index].settlements += 1
    case .builtCity(let seat): tallies[seat.index].cities += 1
    case .boughtDevCard(let seat): tallies[seat.index].devBought += 1
    case .discarded(let seat, let count): tallies[seat.index].discarded += count
    case .playedKnight(let seat, let victim, _):
        tallies[seat.index].knights += 1
        if let victim { tallies[victim.index].robbed += 1 }
    case .movedRobber(_, let victim, _): if let victim { tallies[victim.index].robbed += 1 }
    case .playedRoadBuilding(let seat), .playedYearOfPlenty(let seat, _), .playedMonopoly(let seat, _, _):
        tallies[seat.index].progress += 1
    case .acceptedTrade(let responder, let proposer, _, _):
        tallies[responder.index].playerTrades += 1
        tallies[proposer.index].playerTrades += 1
    case .tradedWithBank(let seat, _, _): tallies[seat.index].bankTrades += 1
    default: break
    }
}

struct CloudSeats: Decodable {
    struct Game: Decodable { let seats: [String] }
    let game: Game
}

/// At each Expert seat's robber placement in a ranked game: who Expert
/// believed was the strongest rival, who truly led (hidden cards counted),
/// who it robbed, and who went on to win. `ghost leader`.
func leaderDiagnosis(_ url: URL) throws -> [String] {
    let seats = try JSONDecoder().decode(CloudSeats.self, from: Data(contentsOf: url)).game.seats
    let game = try loadCloudGame(url)
    var replay = GameSession(state: game.initialState, policies: [:], policySeed: 0)
    for event in game.events { _ = try replay.applyExternal(event.move, by: event.player) }
    guard case .gameOver(let winner) = replay.state.phase else { return [] }
    var lines: [String] = []
    var session = GameSession(state: game.initialState, policies: [:], policySeed: 0)
    for event in game.events {
        let state = session.state
        let victim: PlayerID?? = {
            switch event.move {
            case .moveRobber(_, let from): return .some(from)
            case .playKnight(_, let from): return .some(from)
            default: return nil
            }
        }()
        if let victim, seats[event.player.index] == "expert" {
            let ledger = session.ledger(for: event.player)
            let evaluator = PositionEvaluator(seat: event.player, weights: .forMode(state.mode),
                                              revision: .pointCompletingCardsV1)
            let board = BoardIndex(state: state)
            let rivals = state.players.map(\.id).filter { $0 != event.player }.sorted()
            let believed = rivals.max { evaluator.standing(of: $0, in: state, ledger: ledger, board: board)
                < evaluator.standing(of: $1, in: state, ledger: ledger, board: board) }!
            let trueLeader = rivals.max { state.victoryPoints(for: $0) < state.victoryPoints(for: $1) }!
            let publicLeader = rivals.max { state.publicVictoryPoints(for: $0) < state.publicVictoryPoints(for: $1) }!
            func tag(_ id: PlayerID?) -> String {
                guard let id else { return "none" }
                return seats[id.index].hasPrefix("person") ? "person" : seats[id.index]
            }
            lines.append([game.id, tag(believed), tag(trueLeader), tag(publicLeader), tag(victim ?? nil),
                          tag(winner), String(state.victoryPoints(for: trueLeader)),
                          String(state.publicVictoryPoints(for: trueLeader))].joined(separator: "\t"))
        }
        _ = try session.applyExternal(event.move, by: event.player)
    }
    return lines
}

/// Every trade an Expert seat accepted from the person in a ranked game,
/// and whether `TradeGuardPolicy` would have refused it: what the guard
/// changes against a real human, which self-play cannot show (bots do not
/// propose what people do). `ghost refusals`.
func refusalAudit(_ url: URL) throws -> [String] {
    let seats = try JSONDecoder().decode(CloudSeats.self, from: Data(contentsOf: url)).game.seats
    let game = try loadCloudGame(url)
    guard let person = seats.firstIndex(where: { $0.hasPrefix("person") }) else { return [] }
    var lines: [String] = []
    var session = GameSession(state: game.initialState, policies: [:], policySeed: 0)
    for (index, event) in game.events.enumerated() {
        let state = session.state
        if case .respondToTrade(let id, true) = event.move, seats[event.player.index] == "expert",
           state.pendingTradeOffers.first(where: { $0.id == id })?.from.index == person {
            var ledger = session.ledger(for: event.player)
            ledger.reconcileObserverHand(from: state)
            let refused = TradeGuardPolicy.v1.refuses(event.move, seat: event.player, state: state, ledger: ledger)
            let built = game.events[(index + 1)...].prefix { !($0.move == .endTurn && $0.player.index == person) }
                .contains { logged in
                    guard logged.player.index == person else { return false }
                    switch logged.move {
                    case .buildSettlement, .buildCity: return true
                    default: return false
                    }
                }
            lines.append([game.id, built ? "built" : "-", refused ? "refuse" : "accept"].joined(separator: "\t"))
        }
        _ = try session.applyExternal(event.move, by: event.player)
    }
    return lines
}
