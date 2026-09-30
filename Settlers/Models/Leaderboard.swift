import CatanAI
import Foundation

/// The spider graph's six axes.
enum RadarAxis: String, CaseIterable, Sendable {
    case production, expansion, trading, development, robber, finishing

    var title: String { rawValue.capitalized }
}

/// Ratings 1-99 against Expert: **Expert is 75** on every axis, so a number
/// reads "better or worse than Expert at this" (Jake liked the 1-99 scale).
enum RadarBaseline {
    /// Expert self-play means, measured with
    /// `ghost baseline --games 200` (seeds 910000..., 800 seats). Re-measured
    /// 2026-09-28 once Expert stopped ending turns over seven cards
    /// (`HandDiscipline`), so Expert stays exactly 75: development rose from
    /// 2.604, expansion fell from 3.731, the rest moved in the third digit.
    static let expert = RadarMeasures(production: 3.166, expansion: 3.646,
                                      trading: 6.258, development: 2.772,
                                      robber: 0.944, finishing: 0.728)
    static let expertRating = 75.0
    /// Classic (`balanced`) self-play means, same command with
    /// `--policy classic` (seeds 910000..., 800 seats, 2026-09-28): the AI
    /// rows' graph until a tier has games of its own.
    static let classic = RadarMeasures(production: 2.908, expansion: 3.234,
                                       trading: 14.492, development: 4.974,
                                       robber: 0.822, finishing: 0.741)

    static func ratings(for measures: RadarMeasures) -> [RadarAxis: Int] {
        var result: [RadarAxis: Int] = [:]
        for axis in RadarAxis.allCases {
            let reference = value(axis, in: expert)
            let scaled = reference > 0 ? expertRating * value(axis, in: measures) / reference : expertRating
            result[axis] = min(99, max(1, Int(scaled.rounded())))
        }
        return result
    }

    static func value(_ axis: RadarAxis, in measures: RadarMeasures) -> Double {
        switch axis {
        case .production: return measures.production
        case .expansion: return measures.expansion
        case .trading: return measures.trading
        case .development: return measures.development
        case .robber: return measures.robber
        case .finishing: return measures.finishing
        }
    }
}

struct LeaderboardRow: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case player = "Player", ghost = "Ghost", ai = "AI" }

    var id: String { key }
    let key: String
    let name: String
    let kind: Kind
    let elo: Double
    let games: Int
    /// Only Classic: the ladder's one anchor.
    let isFixed: Bool
}

enum LeaderboardModel {
    /// Everyone rated, every ghost on the phone (rated or not), and both tiers.
    /// Highest Elo first; ties by name so the order never depends on storage.
    /// `name` labels a player id (`PlayerDirectory.name(of:)`).
    static func rows(ratings: Ratings, ghosts: [GhostProfile], name: (String) -> String) -> [LeaderboardRow] {
        var rows: [LeaderboardRow] = [
            LeaderboardRow(key: "classic", name: "Classic AI", kind: .ai, elo: Elo.classicAnchor,
                           games: ratings.games["classic"] ?? 0, isFixed: true),
            LeaderboardRow(key: "expert", name: "Expert AI", kind: .ai, elo: ratings.ratings["expert"] ?? Elo.expertStart,
                           games: ratings.games["expert"] ?? 0, isFixed: false),
        ]
        for key in ratings.ratings.keys.sorted() where key.hasPrefix("person:") {
            rows.append(LeaderboardRow(key: key, name: name(String(key.dropFirst("person:".count))), kind: .player,
                                       elo: ratings.ratings[key] ?? Elo.start, games: ratings.games[key] ?? 0, isFixed: false))
        }
        for ghost in ghosts {
            let key = RatedEntity.ghost(ghost.id).key
            rows.append(LeaderboardRow(key: key, name: ghost.name, kind: .ghost, elo: ratings.ratings[key] ?? Elo.start,
                                       games: ratings.games[key] ?? 0, isFixed: false))
        }
        return rows.sorted { ($1.elo, $0.name) < ($0.elo, $1.name) }
    }
}

/// A ghost's (or a person's) page, as Jake specified it: games learned from
/// its human, games played against humans with self-play on its own line,
/// the spider graph, and style. No recent-games list.
struct EntityDetail: Equatable, Sendable {
    struct Record: Equatable, Sendable {
        var played = 0
        var won = 0
        var winRate: Double { played == 0 ? 0 : Double(won) / Double(played) }
    }

    /// Three games of its own before a ghost's graph stops borrowing its person's.
    static let minimumGamesForOwnGraph = 3

    let name: String
    let subtitle: String
    let elo: Double
    let gamesLearned: Int?
    let record: Record
    let selfPlay: Record?
    let radar: [RadarAxis: Int]?
    let radarIsLearnedFrom: Bool
    /// Under the graph: where its numbers came from.
    let radarCaption: String
    let style: [String]

    /// `resolve` maps a person's id to their ghost's id (`GhostStore.resolve`),
    /// which differs only for a ghost filed before player ids existed.
    static func ghost(_ ghost: GhostProfile, ratings: Ratings, stats: [SeatStatsRecord],
                      resolve: @escaping (String) -> String = { $0 }) -> EntityDetail {
        let key = RatedEntity.ghost(ghost.id).key
        let own = stats.compactMap { game in game.seats.first { $0.entity == key }.map { (game, $0.stats) } }
        let isOwner: (String) -> Bool = { entity in
            entity.hasPrefix("person:")
                && resolve(String(entity.dropFirst("person:".count))) == ghost.id
        }
        var record = Record()
        var selfPlay = Record()
        for (game, seat) in own {
            record.played += 1
            if seat.won { record.won += 1 }
            if game.seats.contains(where: { isOwner($0.entity) }) {
                selfPlay.played += 1
                if seat.won { selfPlay.won += 1 }
            }
        }
        let ownerGames = stats.flatMap { $0.seats.filter { isOwner($0.entity) }.map(\.stats) }
        let learnedFrom = own.count < minimumGamesForOwnGraph
        let graphGames = learnedFrom ? ownerGames : own.map(\.1)
        return EntityDetail(
            name: ghost.name, subtitle: "Learned from \(ghost.gamesLearned) of its player's games",
            elo: ratings.ratings[key] ?? Elo.start, gamesLearned: ghost.gamesLearned, record: record,
            selfPlay: selfPlay.played > 0 ? selfPlay : nil,
            radar: graphGames.isEmpty ? nil : RadarBaseline.ratings(for: RadarMeasures(games: graphGames)),
            radarIsLearnedFrom: learnedFrom,
            radarCaption: learnedFrom ? "Learned from its player's games · Expert is 75" : "1–99 · Expert is 75",
            style: styleLines(for: ghost.person)
        )
    }

    /// An AI tier's page: its record against people, and its graph from the
    /// games it played here, or from its own self-play until it has
    /// `minimumGamesForOwnGraph` (Jake, 2026-09-28: "I want spider graphs for
    /// them too, just like the users").
    static func ai(_ entity: RatedEntity, name: String, elo: Double, stats: [SeatStatsRecord]) -> EntityDetail {
        let games = stats.flatMap { $0.seats.filter { $0.entity == entity.key }.map(\.stats) }
        var record = Record()
        for game in games {
            record.played += 1
            if game.won { record.won += 1 }
        }
        let own = games.count >= minimumGamesForOwnGraph
        let selfPlay = entity == .classic ? RadarBaseline.classic : RadarBaseline.expert
        return EntityDetail(name: name, subtitle: entity == .classic ? "AI · fixed reference" : "AI", elo: elo,
                            gamesLearned: nil, record: record, selfPlay: nil,
                            radar: RadarBaseline.ratings(for: own ? RadarMeasures(games: games) : selfPlay),
                            radarIsLearnedFrom: !own,
                            radarCaption: own ? "1–99 · Expert is 75" : "From its own self-play · Expert is 75",
                            style: [])
    }

    static func person(_ id: String, name: String, ratings: Ratings, stats: [SeatStatsRecord]) -> EntityDetail {
        let key = RatedEntity.person(id).key
        let games = stats.flatMap { $0.seats.filter { $0.entity == key }.map(\.stats) }
        var record = Record()
        for game in games {
            record.played += 1
            if game.won { record.won += 1 }
        }
        return EntityDetail(name: name, subtitle: "Player", elo: ratings.ratings[key] ?? Elo.start, gamesLearned: nil,
                            record: record, selfPlay: nil,
                            radar: games.isEmpty ? nil : RadarBaseline.ratings(for: RadarMeasures(games: games)),
                            radarIsLearnedFrom: false, radarCaption: "1–99 · Expert is 75", style: [])
    }

    /// The three strongest habits, as words. Section 7 of the research doc:
    /// fitted habit sizes are directions, not amounts, so no number is shown.
    static func styleLines(for person: PersonModel) -> [String] {
        let ranked = effectiveHabits(person)
            .filter { $0.1 != 0 && phrases[$0.0] != nil }
            .sorted { (abs($1.1), $0.0) < (abs($0.1), $1.0) }
        return ranked.prefix(3).map { label, value in value > 0 ? phrases[label]!.more : phrases[label]!.less }
    }

    /// The habits as they act. `proposeLopsided` is cards given minus cards
    /// wanted, so it and `proposeCardsGiven` are one habit seen twice, and
    /// read alone they contradicted each other on Jake's page ("offers few
    /// cards" beside "makes lopsided offers"). Recombined: the pull per card
    /// given is their sum, and the pull per card asked for is minus lopsided.
    static func effectiveHabits(_ person: PersonModel) -> [(String, Double)] {
        var habits = Dictionary(uniqueKeysWithValues: zip(StyleFeatures.labels, person.theta))
        let given = habits.removeValue(forKey: "proposeCardsGiven") ?? 0
        let lopsided = habits.removeValue(forKey: "proposeLopsided") ?? 0
        habits["proposeGive"] = given + lopsided
        habits["proposeWant"] = -lopsided
        return habits.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private static let phrases: [String: (more: String, less: String)] = [
        "propose": ("Offers trades often", "Rarely offers trades"),
        "proposeGive": ("Gives generously in offers", "Offers few cards"),
        "proposeWant": ("Asks for a lot in return", "Asks for little in return"),
        "proposeAfterRefusal": ("Keeps offering after a refusal", "Gives up after a refusal"),
        "bankTrade": ("Trades with the bank", "Avoids bank trades"),
        "acceptOffer": ("Accepts offers readily", "Turns down most offers"),
        "robberHitsLeader": ("Robs the leader", "Spares the leader"),
        "robberHitsBiggestHand": ("Robs the biggest hand", "Ignores hand size when robbing"),
        "buyDevCard": ("Buys development cards", "Rarely buys development cards"),
        "playDevCard": ("Plays development cards quickly", "Sits on development cards"),
        "endTurn": ("Ends turns early", "Uses every turn fully"),
        "buildCity": ("Builds cities", "Holds off on cities"),
        "buildSettlement": ("Loves settlements", "Rarely settles"),
        "buildRoad": ("Builds roads", "Builds few roads"),
    ]
}
