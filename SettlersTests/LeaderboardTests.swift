import CatanAI
import Foundation
import Testing
@testable import Settlers

@Suite struct LeaderboardTests {

    private func ghost(_ id: String, _ name: String, games: Int = 24, theta: [Int: Double] = [:]) -> GhostProfile {
        var person = PersonModel.anchored(at: .forMode(.classic))
        for (index, value) in theta { person.theta[index] = value }
        return GhostProfile(id: id, name: name, person: person, lambda: 0.5, gamesLearned: games)
    }

    private func seat(_ index: Int, won: Bool = false, vp: Int = 6) -> SeatStats {
        var stats = SeatStats(seat: index, target: 10)
        stats.turns = 20
        stats.productionCards = 60
        stats.won = won
        stats.finalVP = vp
        return stats
    }

    /// One rated game: Jake at seat 0, his ghost at seat 1, two Classic bots.
    private func record(ghostWins: Bool, date: Date = Date()) -> SeatStatsRecord {
        SeatStatsRecord(match: UUID(), date: date, seats: [
            .init(entity: "person:Jake", stats: seat(0, won: !ghostWins, vp: ghostWins ? 7 : 10)),
            .init(entity: "ghost:jake", stats: seat(1, won: ghostWins, vp: ghostWins ? 10 : 7)),
            .init(entity: "classic", stats: seat(2)),
            .init(entity: "classic", stats: seat(3)),
        ])
    }

    @Test func rowsSortByEloWithClassicFixed() {
        var ratings = Ratings()
        ratings.ratings = ["person:Jake": 1040, "ghost:jake": 1010, "expert": 1200]
        ratings.games = ["person:Jake": 3, "ghost:jake": 3, "expert": 5]
        let rows = LeaderboardModel.rows(ratings: ratings, ghosts: [ghost("jake", "Jake's Ghost"), ghost("sam", "Sam's Ghost")])
        #expect(rows.map(\.name) == ["Expert AI", "Jake", "Jake's Ghost", "Classic AI", "Sam's Ghost"], "ties at 1000 go by name")
        #expect(rows.first { $0.name == "Classic AI" }?.isFixed == true)
        #expect(rows.first { $0.name == "Classic AI" }?.elo == 1000)
        #expect(rows.first { $0.name == "Sam's Ghost" }?.games == 0, "an unrated ghost is still listed")
        #expect(rows.filter(\.isFixed).count == 1)
    }

    @Test func aFreshInstallShowsBothTiers() {
        let rows = LeaderboardModel.rows(ratings: Ratings(), ghosts: [])
        #expect(rows.map(\.name) == ["Expert AI", "Classic AI"])
        #expect(rows.first?.elo == 1229)
    }

    /// Jake's page items: games learned from its human, games against humans
    /// (self-play on its own line), the spider graph, style. No recent games.
    @Test func aGhostsPageSummarisesItsGames() {
        let records = [record(ghostWins: true), record(ghostWins: false), record(ghostWins: true)]
        let detail = EntityDetail.ghost(ghost("jake", "Jake's Ghost"), ratings: Ratings(), stats: records)
        #expect(detail.gamesLearned == 24)
        #expect(detail.record.played == 3)
        #expect(detail.record.won == 2)
        #expect(detail.selfPlay?.played == 3, "every game here was against its own person")
        #expect(detail.selfPlay?.won == 2)
        #expect(detail.radar != nil)
        #expect(!detail.radarIsLearnedFrom, "three games of its own are enough")
    }

    /// Under three games of its own, the graph shows its person's games.
    @Test func aNewGhostsGraphComesFromItsPerson() {
        let records = [record(ghostWins: false)]
        let personOnly = records.map { SeatStatsRecord(match: $0.match, date: $0.date, seats: [$0.seats[0], $0.seats[2]]) }
        let detail = EntityDetail.ghost(ghost("jake", "Jake's Ghost"), ratings: Ratings(), stats: personOnly + personOnly + personOnly)
        #expect(detail.record.played == 0)
        #expect(detail.radarIsLearnedFrom)
        #expect(detail.radar != nil)
    }

    /// Expert maps to 75; everything is clamped to 1...99.
    @Test func ratingsAreOneToNinetyNineWithExpertAtSeventyFive() {
        let expert = RadarBaseline.expert
        let atExpert = RadarBaseline.ratings(for: expert)
        #expect(RadarAxis.allCases.allSatisfy { atExpert[$0] == 75 })
        let doubled = RadarMeasures(production: expert.production * 2, expansion: 0, trading: expert.trading * 10,
                                    development: expert.development, robber: expert.robber, finishing: expert.finishing)
        let rated = RadarBaseline.ratings(for: doubled)
        #expect(rated[.production] == 99)
        #expect(rated[.expansion] == 1)
        #expect(rated[.trading] == 99)
    }

    /// Style is words, never the fitted sizes (section 7 of the research doc:
    /// sizes are not reliable), top three by strength.
    @Test func styleLinesAreTheStrongestThreeHabitsInWords() {
        let labels = StyleFeatures.labels
        let theta = [labels.firstIndex(of: "acceptOffer")!: -4.5, labels.firstIndex(of: "buildSettlement")!: 6.4,
                     labels.firstIndex(of: "robberHitsLeader")!: 1.6, labels.firstIndex(of: "bankTrade")!: -0.2]
        let lines = EntityDetail.styleLines(for: ghost("jake", "Jake's Ghost", theta: theta).person)
        #expect(lines == ["Loves settlements", "Turns down most offers", "Robs the leader"])
        #expect(lines.allSatisfy { !$0.contains(where: \.isNumber) })
    }

    @Test func statsAreRecordedOncePerMatch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SeatStatsStore.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SeatStatsStore(directory: dir)
        let game = record(ghostWins: true)
        try store.record(game)
        try store.record(game)
        #expect(store.all() == [game])
    }
}
