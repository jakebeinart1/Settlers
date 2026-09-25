import CatanAI
import CatanEngine
import Foundation
import Testing
@testable import Settlers

@Suite(.serialized) struct GhostSeatTests {

    private struct Fixture {
        let root: URL
        let defaults: UserDefaults
        let suite: String
        let ghosts: GhostStore

        @MainActor
        func model(ghosts store: GhostStore? = nil) -> GameViewModel {
            let setupStore = MatchSetupStore()
            setupStore.defaults = defaults
            return GameViewModel(
                gameStore: GameStore(fileURL: root.appendingPathComponent("save.json")),
                civilizationStore: CivilizationAssignmentStore(fileURL: root.appendingPathComponent("civs.json")),
                matchSetupStore: setupStore,
                gameLogStore: GameLogStore(directoryURL: root.appendingPathComponent("logs"), maxKeptLogs: 10),
                gameStatsStore: GameStatsStore(fileURL: root.appendingPathComponent("stats.json")),
                ghostStore: store ?? ghosts,
                ratingStore: RatingStore(directory: root.appendingPathComponent("ratings")),
                seatStatsStore: SeatStatsStore(directory: root.appendingPathComponent("stats"))
            )
        }

        func tearDown() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GhostSeatTests.\(UUID().uuidString)")
        let bundled = root.appendingPathComponent("bundle")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        let file = bundled.appendingPathComponent("jake.ghost")
        let ghost = GhostProfile(id: "jake", name: "Jake's Ghost", person: .anchored(at: .forMode(.classic)),
                                 lambda: 0.5, gamesLearned: 24)
        try JSONEncoder().encode(ghost).write(to: file)
        let suite = "GhostSeatTests.\(UUID().uuidString)"
        return Fixture(root: root, defaults: try #require(UserDefaults(suiteName: suite)), suite: suite,
                       ghosts: GhostStore(localDirectory: root.appendingPathComponent("local"), bundledGhosts: [file]))
    }

    private func ghostTable() -> MatchSetup {
        var setup = MatchSetup.default(preferredName: "Jake", preferredCivilization: .greece)
        setup.randomizeSeatOrder = false
        setup.seats[2].ghostID = "jake"
        return setup
    }

    @MainActor
    @Test func aGhostSeatIsPlayedByTheGhostUnderItsName() throws {
        let f = try fixture()
        defer { f.tearDown() }
        let model = f.model()
        model.startNewGame(setup: ghostTable())
        let seat = PlayerID(index: 2)
        let policy = try #require(model.session.policies[seat] as? GhostPolicy)
        #expect(policy.lambda == 0.5)
        #expect(model.playerIdentity(for: seat).displayName == "Jake's Ghost")
        #expect(model.checkpointDocument?.activeMatch?.setup.seats[2].ghostID == "jake")
        #expect(model.session.policies[PlayerID(index: 1)] is HeuristicPolicy, "the other AI seats are the chosen tier")
    }

    @MainActor
    @Test func aResumedGameKeepsItsGhost() throws {
        let f = try fixture()
        defer { f.tearDown() }
        f.model().startNewGame(setup: ghostTable())
        let restored = f.model()
        #expect(restored.session.policies[PlayerID(index: 2)] is GhostPolicy)
        #expect(restored.playerIdentity(for: PlayerID(index: 2)).displayName == "Jake's Ghost")
    }

    /// Review Focus 2: the ghost's file is gone on resume. The checkpoint
    /// records every chair's policy and `GameSession` refuses a different one,
    /// which is what keeps a resumed game a replay of itself. So the save is
    /// held, untouched, and the player is told which seat's ghost is missing.
    @MainActor
    @Test func aMissingGhostHoldsTheSaveAndSaysWhere() throws {
        let f = try fixture()
        defer { f.tearDown() }
        f.model().startNewGame(setup: ghostTable())
        let empty = GhostStore(localDirectory: f.root.appendingPathComponent("none"), bundledGhosts: [])
        let restored = f.model(ghosts: empty)
        let message = restored.savedGameAvailability.recoveryMessage ?? ""
        #expect(message.contains("Seat 3"), "got: \(message)")
        #expect(message.contains("ghost"))
        #expect(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("match_checkpoint.json").path),
                "the save must be kept")
    }

    /// A finished game is rated for every seat and teaches the human's ghost.
    /// Jake's rule: the ghost's own moves never teach it - here seat 3 is
    /// Jake's ghost and seat 1 is Jake, and the ghost learns only from seat 1.
    @MainActor
    @Test func aFinishedGameIsRatedAndTeachesThePersonsGhost() async throws {
        let f = try fixture()
        defer { f.tearDown() }
        let model = f.model()
        // Real training replays the game and scores every candidate - about 4
        // minutes of an unoptimised Debug build, and 22 under a full parallel
        // suite. GhostTrainerTests cover training itself; here one recorded
        // decision stands in, and the test checks the hook teaches the right
        // person's ghost from the human seat only.
        let seats = LockedSeats()
        model.makeGhostTrainer = { store in
            var trainer = GhostTrainer(store: store)
            trainer.extract = { game, anchor in
                seats.record(game.humanSeats)
                return [DecisionRecord(game: game.id, facet: .turn, anchor: anchor.vector, candidates: [
                    CandidateRecord(move: .endTurn, score: 0, gradient: Array(repeating: 0, count: anchor.vector.count),
                                    style: Array(repeating: 0, count: StyleFeatures.labels.count)),
                    CandidateRecord(move: .rollDice, score: 0, gradient: Array(repeating: 0, count: anchor.vector.count),
                                    style: Array(repeating: 0, count: StyleFeatures.labels.count)),
                ], chosen: 0)]
            }
            return trainer
        }
        model.startNewGame(setup: ghostTable())
        model.qaPlayToEnd()
        guard case .gameOver = model.state.phase else {
            Issue.record("the game did not finish")
            return
        }
        await model.lastFinishedMatchWork?.value
        let ratings = RatingStore(directory: f.root.appendingPathComponent("ratings")).load()
        #expect(ratings.games["person:Jake"] == 1)
        #expect(ratings.games["ghost:jake"] == 1)
        #expect(ratings.ratings["classic"] == nil, "Classic is the fixed anchor")
        #expect(ratings.ratedMatches.count == 1)
        let taught = try #require(f.ghosts.ghost(id: "jake"))
        #expect(taught.gamesLearned == 25, "the bundled ghost's 24 games plus this one")
        let stats = SeatStatsStore(directory: f.root.appendingPathComponent("stats")).all()
        #expect(stats.count == 1)
        #expect(stats.first?.seats.map(\.entity) == ["person:Jake", "classic", "ghost:jake", "classic"])
        #expect(stats.first?.seats.filter(\.stats.won).count == 1)
        #expect(f.ghosts.versions(of: "jake").count == 1)
        #expect(seats.all == [[PlayerID(index: 0)]], "only Jake's own seat is read, never the ghost's")
    }

    /// Review Focus 1: pass-and-play is gone, but an old two-human save still
    /// plays. Whoever the game waits on acts - no hand-off cover, no claim.
    @MainActor
    @Test func anOldTwoHumanGameStillPlays() throws {
        let f = try fixture()
        defer { f.tearDown() }
        var setup = MatchSetup.default(preferredName: "Jake", preferredCivilization: .greece)
        setup.randomizeSeatOrder = false
        setup.seats[1].isHuman = true
        setup.seats[1].name = "Sam"
        f.model().startNewGame(setup: setup)
        let restored = f.model()
        #expect(restored.humanPlayer == PlayerID(index: 0))
        for _ in 0..<2 {
            let move = try #require(RulesEngine.legalMoves(for: restored.state, seat: PlayerID(index: 0)).first)
            try restored.apply(move)
        }
        #expect(restored.state.phase.awaitingSeatIndex == 1)
        #expect(restored.humanPlayer == PlayerID(index: 1), "the second person acts without claiming the phone")
    }
}

/// Which seats the stand-in extractor was asked to read, across threads.
private final class LockedSeats: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [Set<PlayerID>] = []
    var all: [Set<PlayerID>] { lock.withLock { seen } }
    func record(_ seats: Set<PlayerID>) { lock.withLock { seen.append(seats) } }
}
