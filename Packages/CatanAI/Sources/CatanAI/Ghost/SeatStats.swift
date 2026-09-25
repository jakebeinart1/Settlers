import CatanEngine

/// What one seat did in one game: the raw numbers behind a player's or a
/// ghost's spider graph (Jake, 2026-09-25: "a FIFA web graph showing how good
/// they are in different categories").
///
/// Lives in this package, not the app, so the `ghost baseline` command that
/// measures Expert's averages and the app that rates a player against them
/// share one definition of every number.
public struct SeatStats: Codable, Equatable, Sendable {
    public let seat: Int
    public var turns = 0
    /// Resource cards gained from dice rolls. There is no production event,
    /// so this is the seat's hand growth across each roll.
    public var productionCards = 0
    public var settlementsBuilt = 0
    public var citiesBuilt = 0
    /// Player trades completed, counted once for each side.
    public var tradesCompleted = 0
    public var devCardsPlayed = 0
    public var largestArmy = false
    /// Robber moves (a seven or a Knight) that stole from someone.
    public var robberMoves = 0
    /// Of those, the ones whose victim led on public points at the time.
    public var robberHitsLeader = 0
    public var finalVP = 0
    public let target: Int
    public var won = false

    public init(seat: Int, target: Int) {
        self.seat = seat
        self.target = target
    }

    /// Replays a game and counts, for every seat.
    public static func compute(initial: GameState, moves: [LoggedMove]) throws -> [SeatStats] {
        var stats = initial.players.map { SeatStats(seat: $0.id.index, target: initial.victoryPointTarget) }
        var session = GameSession(state: initial, policies: [:], policySeed: 0)
        for logged in moves {
            let before = session.state
            let step = try session.applyExternal(logged.move, by: logged.player)
            if logged.move == .rollDice { countProduction(before: before, after: session.state, into: &stats) }
            for event in step.events { count(event, before: before, into: &stats) }
        }
        let final = session.state
        for index in stats.indices {
            let id = final.players[index].id
            stats[index].finalVP = min(final.victoryPoints(for: id), final.victoryPointTarget)
            stats[index].largestArmy = final.largestArmyPlayer == id
            if case .gameOver(let winner) = final.phase { stats[index].won = winner == id }
        }
        return stats
    }

    private static func countProduction(before: GameState, after: GameState, into stats: inout [SeatStats]) {
        for index in stats.indices {
            let gained = after.players[index].resources.values.reduce(0, +)
                - before.players[index].resources.values.reduce(0, +)
            stats[index].productionCards += max(0, gained)
        }
    }

    private static func count(_ event: GameEvent, before: GameState, into stats: inout [SeatStats]) {
        switch event {
        case .rolled(let seat, _): stats[seat.index].turns += 1
        case .builtSettlement(let seat): stats[seat.index].settlementsBuilt += 1
        case .builtCity(let seat): stats[seat.index].citiesBuilt += 1
        case .acceptedTrade(let responder, let proposer, _, _):
            stats[responder.index].tradesCompleted += 1
            stats[proposer.index].tradesCompleted += 1
        case .playedKnight(let seat, let victim, _):
            stats[seat.index].devCardsPlayed += 1
            countRobbery(by: seat, of: victim, before: before, into: &stats)
        case .movedRobber(let seat, let victim, _):
            countRobbery(by: seat, of: victim, before: before, into: &stats)
        case .playedRoadBuilding(let seat), .playedYearOfPlenty(let seat, _), .playedMonopoly(let seat, _, _):
            stats[seat.index].devCardsPlayed += 1
        default: break
        }
    }

    /// The leader is judged on public points before the move, ties counting
    /// as leading - the same rule as `StyleFeatures`' robberHitsLeader.
    private static func countRobbery(by seat: PlayerID, of victim: PlayerID?, before: GameState,
                                     into stats: inout [SeatStats]) {
        guard let victim else { return }
        stats[seat.index].robberMoves += 1
        let top = before.players.map(\.id).filter { $0 != seat }.map { before.publicVictoryPoints(for: $0) }.max() ?? 0
        if before.publicVictoryPoints(for: victim) == top { stats[seat.index].robberHitsLeader += 1 }
    }
}

/// The spider graph's six measures, averaged over a player's games.
public struct RadarMeasures: Equatable, Sendable {
    /// Cards from rolls per turn.
    public let production: Double
    /// Settlements and cities built per game.
    public let expansion: Double
    /// Player trades completed per game.
    public let trading: Double
    /// Dev cards played per game, plus 2 for each game ending with Largest Army.
    public let development: Double
    /// Share of robber moves that hit the leader.
    public let robber: Double
    /// Final points as a share of the target.
    public let finishing: Double

    public init(games: [SeatStats]) {
        let count = Double(max(games.count, 1))
        let turns = games.map(\.turns).reduce(0, +)
        let robberMoves = games.map(\.robberMoves).reduce(0, +)
        production = turns == 0 ? 0 : Double(games.map(\.productionCards).reduce(0, +)) / Double(turns)
        expansion = Double(games.map { $0.settlementsBuilt + $0.citiesBuilt }.reduce(0, +)) / count
        trading = Double(games.map(\.tradesCompleted).reduce(0, +)) / count
        development = Double(games.map { $0.devCardsPlayed + ($0.largestArmy ? 2 : 0) }.reduce(0, +)) / count
        robber = robberMoves == 0 ? 0 : Double(games.map(\.robberHitsLeader).reduce(0, +)) / Double(robberMoves)
        finishing = games.map { Double($0.finalVP) / Double(max($0.target, 1)) }.reduce(0, +) / count
    }

    public init(production: Double, expansion: Double, trading: Double, development: Double,
                robber: Double, finishing: Double) {
        self.production = production
        self.expansion = expansion
        self.trading = trading
        self.development = development
        self.robber = robber
        self.finishing = finishing
    }
}
