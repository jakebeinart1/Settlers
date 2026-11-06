import CatanAI
import CatanEngine
import Foundation
import Testing
@testable import Settlers

@Suite struct PlayerRatingsTests {
    private let expert = RatingPool(mode: .classic, difficulty: .expert)

    /// One of four equal-rated seats wins a game. The person therefore gains
    /// 32 × (1 − 1/4) = 24 for winning and loses 32 × 1/4 = 8 for losing.
    @Test(arguments: [true, false])
    func oneGameHasOneOutcomeAndOneSharedAIChange(won: Bool) {
        let ledger = PlayerRatings(records: [game(1, won: won)])
        let person = ledger.standing(for: "alex", in: expert)
        let ai = ledger.aiStanding(in: expert)
        #expect(person.rating == (won ? 1024 : 992))
        #expect(ai.rating == (won ? 976 : 1008))
        #expect(person.games == 1 && ai.games == 1, "three computer chairs still play one game")
        #expect(person.wins == (won ? 1 : 0))
        #expect(person.losses == (won ? 0 : 1))
        #expect(ai.wins == person.losses && ai.losses == person.wins)
        #expect(ledger.changes.count == 1)
        #expect(ledger.changes[0].displayedDelta == (won ? 24 : -8))
    }

    @Test(arguments: [true, false])
    func aSavedThreeSeatTableUsesItsActualWinProbability(won: Bool) {
        let ledger = PlayerRatings(records: [game(1, won: won, bots: 2)])
        let expected = won ? 1000 + 64.0 / 3 : 1000 - 32.0 / 3
        #expect(abs(ledger.standing(for: "alex", in: expert).rating - expected) < 1e-9)
        #expect(ledger.aiStanding(in: expert).games == 1)
    }

    @Test(arguments: RatingPool.available)
    func everyBoardRuleAndDifficultyHasAnIndependentRecord(pool: RatingPool) {
        let ledger = PlayerRatings(records: [game(1, pool: pool)])
        #expect(ledger.standing(for: "alex", in: pool).rating == 1024)
        for other in RatingPool.available where other != pool {
            let untouched = ledger.standing(for: "alex", in: other)
            #expect(untouched.rating == 1000 && !untouched.isRated)
            #expect(ledger.aiStanding(in: other).games == 0)
        }
        #expect(ledger.overallRecord(for: "alex").games == 1)
    }

    /// An AI tier is one shared reference across people, not three private
    /// opponents per person. A second Alex device uses the same account ID.
    @Test func accountsShareOneAIEntryAndKeepSeparatePersonalRecords() {
        let ledger = PlayerRatings(records: [game(1), game(2, player: "jake", won: false),
                                             game(3, player: "kyle"), game(4, won: false)])
        #expect(ledger.playerIDs == ["alex", "jake", "kyle"])
        #expect(ledger.standing(for: "alex", in: expert).games == 2)
        #expect(ledger.standing(for: "jake", in: expert).games == 1)
        #expect(ledger.standing(for: "kyle", in: expert).games == 1)
        #expect(ledger.aiStanding(in: expert).games == 4)
        let total = ledger.playerIDs.map { ledger.standing(for: $0, in: expert).rating }
            .reduce(ledger.aiStanding(in: expert).rating, +)
        #expect(abs(total - 4000) < 1e-9, "each game transfers one equal and opposite change")
    }

    @Test func chronologicalRebuildIgnoresArrivalOrderAndDuplicateDeliveries() {
        let records = [game(1), game(2, player: "jake", won: false), game(3, won: false), game(4)]
        let chronological = PlayerRatings(records: records)
        #expect(PlayerRatings(records: Array(records.reversed())) == chronological)
        #expect(PlayerRatings(records: [records[3], records[1], records[0], records[2], records[0]]) == chronological)
        #expect(chronological.changes.map(\.match) == records.map(\.match))
    }

    @Test func simultaneousGamesUseMatchIDAsTheSameTieBreakOnEveryDevice() {
        let first = game(1)
        let second = game(2, won: false)
        let tied = SeatStatsRecord(match: second.match, date: first.date, seats: second.seats,
                                   ratingPool: expert)
        let forward = PlayerRatings(records: [first, tied])
        #expect(PlayerRatings(records: [tied, first]) == forward)
        #expect(forward.changes.map(\.match) == [first.match, tied.match])
    }

    @Test func conflictingCopiesCannotLetArrivalOrderChooseAWin() {
        let win = game(1)
        let loss = game(1, won: false)
        let remaining = game(2)
        #expect(PlayerRatings(records: [win, loss, remaining]) == PlayerRatings(records: [remaining]))
        #expect(PlayerRatings(records: [remaining, loss, win]) == PlayerRatings(records: [remaining]))
    }

    @Test func restartCountsAsOneLossAndRetainsItsExplanation() {
        let record = game(1, won: false, abandoned: true)
        let ledger = PlayerRatings(records: [record, record])
        #expect(ledger.overallRecord(for: "alex") == PlayerRatingRecord(wins: 0, losses: 1, forfeits: 1))
        #expect(ledger.standing(for: "alex", in: expert).rating == 992)
        #expect(ledger.changes.first?.abandoned == true)
        #expect(ledger.aiStanding(in: expert).forfeits == 0)
    }

    @Test func oldOrdinaryGamesKeepTheirClassicStandardHistory() throws {
        let old = game(1, pool: nil)
        let decoded = try JSONDecoder().decode(SeatStatsRecord.self, from: JSONEncoder().encode(old))
        #expect(decoded.ratingPool == nil)
        let ledger = PlayerRatings(records: [decoded])
        #expect(ledger.standing(for: "alex", in: expert).rating == 1024)
        #expect(ledger.changes.first?.pool == expert)
    }

    @Test func unsupportedOrAmbiguousTablesNeverBecomeOrdinaryAIResults() {
        let valid = game(1)
        var cases: [SeatStatsRecord] = [
            game(2, pool: RatingPool(mode: .naval, variant: .conquest, difficulty: .expert)),
            game(3, won: true, abandoned: true),
            game(4, bots: 1),
        ]
        for entity in ["ghost:jake", "classic", "person:kyle", "person:", "unknown"] {
            var seats = valid.seats
            seats[1] = .init(entity: entity, stats: seats[1].stats)
            cases.append(SeatStatsRecord(match: valid.match, date: valid.date, seats: seats, ratingPool: expert))
        }
        #expect(cases.allSatisfy { PlayerRatings(records: [$0]).changes.isEmpty })
    }

    @Test func noWinnerTwoWinnersOrMisnumberedSeatsCannotChangeRatings() {
        let valid = game(1)
        var noWinner = valid.seats
        var losingPerson = noWinner[0].stats
        losingPerson.won = false
        noWinner[0] = .init(entity: "person:alex", stats: losingPerson)
        var twoWinners = valid.seats
        var winningAI = twoWinners[1].stats
        winningAI.won = true
        twoWinners[1] = .init(entity: "expert", stats: winningAI)
        var wrongSeat = valid.seats
        wrongSeat[1] = .init(entity: "expert", stats: SeatStats(seat: 0, target: 10))
        for seats in [noWinner, twoWinners, wrongSeat] {
            let invalid = SeatStatsRecord(match: valid.match, date: valid.date, seats: seats, ratingPool: expert)
            #expect(PlayerRatings(records: [invalid]).changes.isEmpty)
        }
    }

    /// At high ratings a loss must still cost Elo; at low ratings a loss must
    /// not gain Elo from drawing against the other losing computer chairs.
    @Test func winningAlwaysRaisesAndLosingAlwaysLowersThePlayersRating() {
        let wins = (1...160).map { game($0) }
        let losses = (161...320).map { game($0, won: false) }
        let changes = PlayerRatings(records: wins + losses).changes
        #expect(changes.count == 320)
        #expect(changes.allSatisfy { $0.won ? $0.after > $0.before : $0.after < $0.before })
        #expect(changes.allSatisfy { $0.displayedDelta == Int($0.after.rounded()) - Int($0.before.rounded()) })
    }

    @Test func anOverallRecordSumsGamesWithoutInventingAnOverallElo() {
        let naval = RatingPool(mode: .naval, difficulty: .classic)
        let ledger = PlayerRatings(records: [game(1), game(2, pool: naval, won: false),
                                             game(3, pool: naval, won: false, abandoned: true)])
        #expect(ledger.overallRecord(for: "alex") == PlayerRatingRecord(wins: 1, losses: 2, forfeits: 1))
        #expect(abs(ledger.overallRecord(for: "alex").winRate - 1.0 / 3) < 1e-9)
        #expect(ledger.overallRecord(for: "unknown").games == 0)
    }

    @Test func onlySupportedNewGameCompetitionsAreOfferedUntilAnOldBoardHasARecord() {
        #expect(RatingPool.available.count == 10)
        #expect(!RatingPool.available.contains { $0.mode == .expanded })
        #expect(!RatingPool.available.contains { $0.mode == .naval && $0.variant == .conquest })
        let expanded = RatingPool(mode: .expanded, difficulty: .expert)
        let ledger = PlayerRatings(records: [game(1, pool: expanded)])
        #expect(ledger.pools == RatingPool.available + [expanded])
    }

    @Test func newGameEligibilityFollowsTheActualSetupAndRejectsGhostsOrHotSeat() {
        var setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: .rome)
        #expect(RatingPool.eligible(for: setup) == RatingPool(mode: .classic, difficulty: .classic))
        setup.seats[1].ghostID = "jake"
        #expect(RatingPool.eligible(for: setup) == nil)
        setup.seats[1].ghostID = nil
        setup.seats[1].isHuman = true
        setup.seats[1].name = "Kyle"
        #expect(RatingPool.eligible(for: setup) == nil)
    }

    private func game(_ number: Int, pool: RatingPool? = RatingPool(mode: .classic, difficulty: .expert),
                      player: String = "alex", won: Bool = true, bots: Int = 3, abandoned: Bool = false) -> SeatStatsRecord {
        let entity = pool?.difficulty == .classic ? "classic" : "expert"
        let entries = (0...bots).map { seat -> SeatStatsRecord.Entry in
            var stats = SeatStats(seat: seat, target: 10)
            stats.won = won ? seat == 0 : seat == 1
            return .init(entity: seat == 0 ? "person:\(player)" : entity, stats: stats)
        }
        return SeatStatsRecord(match: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!,
                               date: Date(timeIntervalSince1970: Double(number)), seats: entries,
                               ratingPool: pool, abandoned: abandoned)
    }
}
