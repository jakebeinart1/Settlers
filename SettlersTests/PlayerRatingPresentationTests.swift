import CatanEngine
import Foundation
import Testing
@testable import Settlers

@Suite struct PlayerRatingPresentationTests {
    @Test func adoptedLocalIdentityAppearsOnceInStandings() {
        let snapshot = PlayerRatingSnapshot(me: "account-alex",
            names: ["local-alex": "Alex before sync", "account-alex": "Alex", "account-jake": "Jake"],
            ratings: PlayerRatings(records: []), localOwnerBindings: ["local-alex": "account-alex"])
        #expect(snapshot.playerIDs == ["account-alex", "account-jake"])
        #expect(snapshot.name(for: "local-alex") == "Alex")
    }

    @Test func historicalReceiptKeepsItsFirstAccountAfterAnotherAccountSignsIn() {
        let snapshot = PlayerRatingSnapshot(me: "account-kyle",
            names: ["account-alex": "Alex", "account-kyle": "Kyle"], ratings: PlayerRatings(records: []),
            localOwnerBindings: ["local-alex": "account-alex"])
        #expect(snapshot.resolvedPlayerID("local-alex") == "account-alex")
        #expect(snapshot.resolvedPlayerID("account-alex") == "account-alex")
        #expect(snapshot.resolvedPlayerID(snapshot.me) == "account-kyle")
    }

    @Test func interruptedAdoptionKeepsOneCompleteVisibleRecord() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RatingSnapshot.\(UUID())")
        // Temporary cleanup is best-effort; the durable-data assertions below
        // determine whether loading the snapshot changed the user's records.
        defer { try? FileManager.default.removeItem(at: root) }
        let players = PlayerDirectory(directory: root.appendingPathComponent("Players"))
        let stats = SeatStatsStore(directory: root.appendingPathComponent("Stats"))
        let directory = PlayerDirectory.Contents(me: "local-alex", names: ["local-alex": "Alex"],
            migratedLegacyNames: true, localOwnerBindings: ["local-alex": "account-alex"])
        try players.save(directory)
        let pool = RatingPool(mode: .classic, difficulty: .expert)
        let first = QAPlayerRatingsFixture.record(person: "account-alex", pool: pool, won: true, serial: 1)
        var second = QAPlayerRatingsFixture.record(person: "local-alex", pool: pool, won: false, serial: 2)
        second.abandoned = true
        try stats.record(first)
        try stats.record(second)
        let snapshot = await PlayerRatingSnapshot.load(stats: stats, players: players)
        #expect(snapshot.me == "account-alex")
        #expect(snapshot.playerIDs == ["account-alex"])
        #expect(snapshot.name(for: "account-alex") == "Alex")
        let standing = snapshot.ratings.standing(for: "account-alex", in: pool)
        #expect(standing.record == PlayerRatingRecord(wins: 1, losses: 1, forfeits: 1))
        #expect(snapshot.ratings.changes.map(\.playerID) == ["account-alex", "account-alex"])
        #expect(snapshot.ratings.changes.last?.before == snapshot.ratings.changes.first?.after)
        #expect(players.load() == directory)
        #expect(stats.all() == [first, second])
    }
}
