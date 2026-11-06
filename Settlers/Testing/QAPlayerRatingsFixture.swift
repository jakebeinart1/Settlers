#if DEBUG
import CatanAI
import CatanEngine
import Foundation

/// Summary fixtures for typography, charts and filter interactions only.
/// They have no legal-move recording and prove no sync or played outcome.
/// Native completion and fake-cloud integration tests provide those proofs.
enum QAPlayerRatingsFixture {
    static let playerID = "ratings-preview-alex"
    private static let epoch = Date(timeIntervalSince1970: 1_790_812_800)

    static func seedIfRequested() {
        guard QALaunchFlag.seedPlayerRatings.isSet else { return }
        do {
            var players = PlayerDirectory.shared.load()
            players.me = playerID
            players.names = [playerID: "Alex", "ratings-preview-jake": "Jake", "ratings-preview-kyle": "Kyle"]
            if QALaunchFlag.playerRatingsWideNames.isSet {
                players.names = [playerID: "WWWWWWWWWWWW", "ratings-preview-jake": "Maximilian W",
                                 "ratings-preview-kyle": "ChristopherW"]
            }
            players.migratedLegacyNames = true
            try PlayerDirectory.shared.save(players)
            PlayerNameStore.shared.save(players.names[playerID] ?? "Alex")
            try seedRecords()
            if QALaunchFlag.playerRatingsBusyMenu.isSet { try seedMenuStatistics() }
            try RatingStore.shared.rebuild(from: SeatStatsStore.shared.all())
            RatingPoolPreference.save(RatingPool(mode: .classic, difficulty: .expert))
        } catch {
            preconditionFailure("Could not seed the ratings layout fixture: \(error)")
        }
    }

    /// Layout data, never evidence of a completed legal match. Resume in the
    /// UI test is created by actually starting and leaving a separate game.
    private static func seedMenuStatistics() throws {
        let statistics = GameStats(gamesPlayed: 22, gamesWon: 13, totalFinalVP: 198, totalDurationSeconds: 26_400)
        try JSONEncoder().encode(statistics).write(to: GameStatsStore.shared.fileURL, options: .atomic)
    }

    private static func seedRecords() throws {
        let expert = RatingPool(mode: .classic, difficulty: .expert)
        for (person, wins) in [(playerID, 8), ("ratings-preview-jake", 6), ("ratings-preview-kyle", 4)] {
            for game in 0..<12 {
                try SeatStatsStore.shared.record(record(person: person, pool: expert,
                    won: game < wins, serial: serial(person: person, game: game)))
            }
        }
        for game in 0..<6 {
            try SeatStatsStore.shared.record(record(person: playerID,
                pool: RatingPool(mode: .naval, difficulty: .expert), won: game % 3 != 0, serial: 100 + game))
        }
        for game in 0..<4 {
            try SeatStatsStore.shared.record(record(person: playerID,
                pool: RatingPool(mode: .classic, variant: .conquest, difficulty: .classic),
                won: game == 2, serial: 200 + game))
        }
    }

    private static func serial(person: String, game: Int) -> Int {
        let offset = person == playerID ? 0 : person == "ratings-preview-jake" ? 20 : 40
        return offset + game
    }

    static func record(person: String, pool: RatingPool, won: Bool, serial: Int,
                       match: UUID? = nil) -> SeatStatsRecord {
        let id = match ?? UUID(uuidString: String(format: "A1100000-0000-0000-0000-%012d", serial))!
        let entities: [RatedEntity] = [.person(person)] + Array(
            repeating: pool.difficulty == .expert ? .expert : .classic, count: 3)
        let seats = entities.enumerated().map { index, entity in
            var stats = SeatStats(seat: index, target: pool.mode == .naval ? 14 : 10)
            stats.won = won ? index == 0 : index == 1
            stats.finalVP = stats.won ? stats.target : 7 + index % 2
            stats.turns = 25 + serial % 6
            return SeatStatsRecord.Entry(entity: entity.key, stats: stats)
        }
        return SeatStatsRecord(match: id, date: epoch.addingTimeInterval(Double(serial) * 3600),
                               seats: seats, ratingPool: pool)
    }
}

extension GameViewModel {
    /// An explicit layout preview: the game result and summary are seeded,
    /// not played. The real completion path is exercised separately.
    func qaShowPlayerRatingResult(won: Bool) {
        qaForceRatingResult(won: won)
        guard let match = currentGameLogID else { preconditionFailure("A preview needs a match") }
        do {
            let pool = RatingPool(mode: state.mode, variant: state.variant, difficulty: .expert)
            try seatStatsStore.record(QAPlayerRatingsFixture.record(
                person: playerDirectory.me, pool: pool, won: won, serial: 300, match: match))
        } catch { preconditionFailure("Could not seed rating result preview: \(error)") }
    }
}
#endif
