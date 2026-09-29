import CatanAI
import CatanEngine
import Foundation
import Testing
@testable import Settlers

/// The online ladder, end to end, with an in-memory CloudKit: two phones,
/// each with its own stores and Apple ID, sharing one database.
@Suite(.serialized) struct LiveSyncTests {

    /// A shared database with CloudKit's one guarantee: only a record's
    /// creator may change it.
    final class FakeCloud: @unchecked Sendable {
        private let lock = NSLock()
        private var clock = Date(timeIntervalSince1970: 1_000_000)
        private(set) var names: [String: NameClaim] = [:]
        private(set) var matches: [UUID: Downloaded<SharedMatch>] = [:]
        private(set) var ghosts: [String: Downloaded<GhostProfile>] = [:]

        func locked<T>(_ body: (FakeCloud) throws -> T) rethrows -> T {
            lock.lock()
            defer { lock.unlock() }
            return try body(self)
        }

        fileprivate func tick() -> Date {
            clock = clock.addingTimeInterval(1)
            return clock
        }

        fileprivate func setName(_ slug: String, _ claim: NameClaim) { names[slug] = claim }
        fileprivate func setMatch(_ match: Downloaded<SharedMatch>) { matches[match.value.match] = match }
        fileprivate func setGhost(_ ghost: Downloaded<GhostProfile>) { ghosts[ghost.value.id] = ghost }
    }

    struct Phone: CloudBackend {
        let cloud: FakeCloud
        let user: String

        func currentUser() async throws -> String { user }

        func claim(slug: String, name: String) async throws -> NameClaim {
            cloud.locked { cloud in
                if let existing = cloud.names[slug] { return existing }
                let claim = NameClaim(name: name, owner: user)
                cloud.setName(slug, claim)
                return claim
            }
        }

        func rename(slug: String, to name: String) async throws {
            try cloud.locked { cloud in
                guard let existing = cloud.names[slug] else { return }
                guard existing.owner == user else { throw CloudSyncError.failed("not creator") }
                cloud.setName(slug, NameClaim(name: name, owner: user))
            }
        }

        func claims(slugs: [String]) async throws -> [String: NameClaim] {
            cloud.locked { cloud in cloud.names.filter { slugs.contains($0.key) } }
        }

        func upload(_ match: SharedMatch) async throws {
            cloud.locked { cloud in
                guard cloud.matches[match.match] == nil else { return }
                cloud.setMatch(Downloaded(value: match, owner: user, modified: cloud.tick()))
            }
        }

        func matches(modifiedAfter date: Date?) async throws -> [Downloaded<SharedMatch>] {
            cloud.locked { cloud in cloud.matches.values.filter { $0.modified > (date ?? .distantPast) } }
        }

        func upload(_ ghost: GhostProfile) async throws {
            try cloud.locked { cloud in
                if let existing = cloud.ghosts[ghost.id], existing.owner != user { throw CloudSyncError.failed("not creator") }
                cloud.setGhost(Downloaded(value: ghost, owner: user, modified: cloud.tick()))
            }
        }

        func ghosts() async throws -> [Downloaded<GhostProfile>] {
            cloud.locked { cloud in Array(cloud.ghosts.values) }
        }
    }

    struct Device {
        let root: URL
        let stores: LiveSync.Stores

        init(_ name: String, in root: URL) {
            let dir = root.appendingPathComponent(name)
            self.root = dir
            stores = LiveSync.Stores(
                seatStats: SeatStatsStore(directory: dir.appendingPathComponent("stats")),
                ratings: RatingStore(directory: dir.appendingPathComponent("ratings")),
                ghosts: GhostStore(localDirectory: dir.appendingPathComponent("ghosts"), bundledGhosts: []),
                logs: GameLogStore(directoryURL: dir.appendingPathComponent("logs"), maxKeptLogs: 10),
                stateFile: dir.appendingPathComponent("sync/state.json"))
        }

        func sync(_ cloud: FakeCloud, as user: String, name: String) async -> LiveSync.Status {
            await LiveSync(backend: Phone(cloud: cloud, user: user), stores: stores, displayName: { name }).sync()
        }

        /// Plays one whole rated game on this device as `name`, with
        /// `ghost` in seat 2 if given.
        @MainActor
        func play(as name: String, against ghost: String? = nil) throws {
            let suite = "LiveSyncTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let setupStore = MatchSetupStore()
            setupStore.defaults = defaults
            let model = GameViewModel(
                gameStore: GameStore(fileURL: root.appendingPathComponent("save.json")),
                civilizationStore: CivilizationAssignmentStore(fileURL: root.appendingPathComponent("civs.json")),
                matchSetupStore: setupStore, gameLogStore: stores.logs,
                gameStatsStore: GameStatsStore(fileURL: root.appendingPathComponent("gamestats.json")),
                ghostStore: stores.ghosts, ratingStore: stores.ratings, seatStatsStore: stores.seatStats)
            // Ghost training is covered elsewhere and takes minutes here.
            model.makeGhostTrainer = { store in
                var trainer = GhostTrainer(store: store)
                trainer.extract = { _, _ in [] }
                return trainer
            }
            var setup = MatchSetup.default(preferredName: name, preferredCivilization: .greece)
            setup.randomizeSeatOrder = false
            setup.seats[2].ghostID = ghost
            #expect(setup.newGameProblem(knownGhosts: Set(stores.ghosts.pickable().map(\.id))) == nil)
            model.startNewGame(setup: setup)
            model.qaPlayToEnd()
            guard case .gameOver = model.state.phase else { throw CancellationError() }
        }

        /// This device's first game in shared form.
        func sharedGame(as name: String) throws -> SharedMatch {
            let record = try #require(stores.seatStats.all().first)
            let summary = try #require(try stores.logs.summaries().first { $0.gameID == record.match })
            return SharedMatch(record: record, log: try stores.logs.detail(for: summary), name: name)
        }
    }

    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LiveSyncTests.\(UUID().uuidString)")
    }

    // MARK: - Tests

    @MainActor
    @Test func aGamePlayedOnOnePhoneGivesAnotherPhoneTheSameLadder() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let jake = Device("jake", in: dir)
        let alex = Device("alex", in: dir)
        try jake.play(as: "Jake")

        guard case .online = await jake.sync(cloud, as: "apple-jake", name: "Jake") else {
            Issue.record("Jake's phone did not come online")
            return
        }
        #expect(cloud.locked { $0.matches.count } == 1)
        guard case .online = await alex.sync(cloud, as: "apple-alex", name: "Alex") else {
            Issue.record("Alex's phone did not come online")
            return
        }
        #expect(alex.stores.seatStats.all() == jake.stores.seatStats.all(), "the replayed stats match the player's own")
        let ladder = alex.stores.ratings.load()
        #expect(ladder.games["person:Jake"] == 1)
        #expect(ladder.ratings == jake.stores.ratings.load().ratings, "both phones show the same Elo")
    }

    @Test func aClaimedNameCannotBeTakenByAnotherAppleID() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        _ = await Device("jake", in: dir).sync(cloud, as: "apple-jake", name: "Jake")
        let status = await Device("impostor", in: dir).sync(cloud, as: "apple-other", name: "jake ")
        #expect(status == .nameTaken("Jake"))
        #expect(await Device("blank", in: dir).sync(cloud, as: "apple-blank", name: "  ") == .noName)
        #expect(await Device("default", in: dir).sync(cloud, as: "apple-default", name: "You") == .noName)
    }

    /// A game posted under someone else's name, or with a result its moves do
    /// not produce, never reaches anyone's ladder.
    @MainActor
    @Test func forgedGamesAreRejected() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let source = Device("source", in: dir)
        try source.play(as: "Jake")
        let game = try source.sharedGame(as: "Jake")
        _ = await Device("jake", in: dir).sync(cloud, as: "apple-jake", name: "Jake")
        // An impostor uploads Jake's game as if it were Jake's.
        try await Phone(cloud: cloud, user: "apple-other").upload(game)
        // And a truncated copy of it under their own claimed name.
        _ = await Device("other", in: dir).sync(cloud, as: "apple-other", name: "Other")
        let truncated = SharedMatch(version: game.version, match: UUID(), date: game.date,
                                    seats: game.seats.map { $0 == "person:Jake" ? "person:Other" : $0 },
                                    initialState: game.initialState, moves: Array(game.moves.dropLast(40)))
        try await Phone(cloud: cloud, user: "apple-other").upload(truncated)

        let observer = Device("observer", in: dir)
        #expect(await observer.sync(cloud, as: "apple-observer", name: "Observer") != .noAccount)
        #expect(observer.stores.seatStats.all().isEmpty)
        #expect(throws: SharedMatch.Rejection.notFinished) { try truncated.verified(uploader: "Other") }
        #expect(throws: SharedMatch.Rejection.personIsNotUploader) { try game.verified(uploader: "Other") }
    }

    @Test func ghostsSyncFromTheirOwnerOnly() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let jake = Device("jake", in: dir)
        try jake.stores.ghosts.save(GhostProfile(id: "jake", name: "Jake's Ghost",
                                                 person: .anchored(at: .forMode(.classic)), lambda: 0.01, gamesLearned: 12))
        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")
        // Someone else's ghost under a name they do not hold is ignored.
        try await Phone(cloud: cloud, user: "apple-other").upload(
            GhostProfile(id: "alex", name: "Fake", person: .anchored(at: .forMode(.classic)), lambda: 0.01, gamesLearned: 99))

        let alex = Device("alex", in: dir)
        _ = await alex.sync(cloud, as: "apple-alex", name: "Alex")
        let ghost = try #require(alex.stores.ghosts.ghost(id: "jake"))
        #expect(ghost.gamesLearned == 12)
        #expect(ghost.name == "Jake's Ghost")
        #expect(alex.stores.ghosts.all().map(\.id) == ["jake"])
    }

    @Test(arguments: [true, false])
    func aFreshOwnerRestoresTheNewerCloudGhostWithoutDowngradingIt(hasOlderCopy: Bool) async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let owner = Phone(cloud: cloud, user: "apple-jake")
        _ = try await owner.claim(slug: "jake", name: "Jake")
        let newer = GhostProfile(id: "jake", name: "Jake's Ghost",
                                 person: .anchored(at: .forMode(.classic)), lambda: 0.01, gamesLearned: 25)
        try await owner.upload(newer)
        let fresh = Device("fresh", in: dir)
        if hasOlderCopy {
            var older = newer
            older.gamesLearned = 24
            try fresh.stores.ghosts.save(older)
        }

        guard case .online = await fresh.sync(cloud, as: "apple-jake", name: "Jake") else {
            Issue.record("The restored owner did not come online")
            return
        }
        #expect(cloud.locked { $0.ghosts["jake"]?.value.gamesLearned } == 25)
        #expect(fresh.stores.ghosts.ghost(id: "jake")?.gamesLearned == 25)
    }

    /// Refreshes stay within `refreshInterval`; a finished game still syncs
    /// at once (Jake, 2026-09-26).
    @Test func refreshesAreThrottledButAFinishedGameSyncsAtOnce() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let counter = CountingPhone(inner: Phone(cloud: FakeCloud(), user: "apple-jake"))
        let sync = LiveSync(backend: counter, stores: Device("jake", in: dir).stores, displayName: { "Jake" })
        await sync.refreshIfDue()
        await sync.refreshIfDue()
        await sync.refreshIfDue(now: Date().addingTimeInterval(LiveSync.refreshInterval - 10))
        #expect(counter.passes == 1, "refreshes inside the interval reach the cloud once")
        await sync.sync()
        #expect(counter.passes == 2, "a finished game does not wait for the interval")
        await sync.refreshIfDue(now: Date().addingTimeInterval(LiveSync.refreshInterval + 10))
        #expect(counter.passes == 3)
    }

    /// Counts passes by their first request.
    final class CountingPhone: CloudBackend, @unchecked Sendable {
        let inner: Phone
        private let lock = NSLock()
        private var count = 0
        var passes: Int { lock.withLock { count } }

        init(inner: Phone) { self.inner = inner }

        func currentUser() async throws -> String {
            lock.withLock { count += 1 }
            return try await inner.currentUser()
        }
        func claim(slug: String, name: String) async throws -> NameClaim { try await inner.claim(slug: slug, name: name) }
        func rename(slug: String, to name: String) async throws { try await inner.rename(slug: slug, to: name) }
        func claims(slugs: [String]) async throws -> [String: NameClaim] { try await inner.claims(slugs: slugs) }
        func upload(_ match: SharedMatch) async throws { try await inner.upload(match) }
        func matches(modifiedAfter date: Date?) async throws -> [Downloaded<SharedMatch>] {
            try await inner.matches(modifiedAfter: date)
        }
        func upload(_ ghost: GhostProfile) async throws { try await inner.upload(ghost) }
        func ghosts() async throws -> [Downloaded<GhostProfile>] { try await inner.ghosts() }
    }

    /// Elo depends on order, so the ladder is replayed in one fixed order:
    /// the same games in any arrival order give the same ratings.
    @Test func ratingsDoNotDependOnTheOrderGamesArrive() throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let records = (0..<6).map { game in
            SeatStatsRecord(match: UUID(), date: Date(timeIntervalSince1970: Double(game)), seats:
                ["person:Jake", "ghost:alex", "expert", "classic"].enumerated().map { seat, key in
                    var stats = SeatStats(seat: seat, target: 10)
                    stats.won = seat == game % 3
                    return SeatStatsRecord.Entry(entity: key, stats: stats)
                })
        }
        let forward = RatingStore(directory: dir.appendingPathComponent("a"))
        let backward = RatingStore(directory: dir.appendingPathComponent("b"))
        try forward.rebuild(from: records)
        try backward.rebuild(from: records.reversed())
        #expect(forward.load() == backward.load())
        #expect(forward.load().games["person:Jake"] == 6)
    }

    // MARK: - Renames (Jake, 2026-09-28: "I tried to change my name and it
    // didn't update my name and my ghost's name")

    private func trainedGhost(_ id: String, _ name: String, games: Int = 12) -> GhostProfile {
        GhostProfile(id: id, name: name, person: .anchored(at: .forMode(.classic)), lambda: 0.01, gamesLearned: games)
    }

    /// A player and their ghost as seen by every phone after a rename.
    private func expectRenamed(_ device: Device, from old: String, to new: String, ghost: String,
                               sourceLocation: SourceLocation = #_sourceLocation) {
        let ladder = device.stores.ratings.load()
        #expect(ladder.ratings["person:\(old)"] == nil, "the old name is gone from the ladder", sourceLocation: sourceLocation)
        #expect((ladder.games["person:\(new)"] ?? 0) > 0, "the games moved to the new name", sourceLocation: sourceLocation)
        #expect(device.stores.ghosts.ghost(id: ghost)?.name == "\(new)'s Ghost", sourceLocation: sourceLocation)
        #expect(!device.stores.ghosts.all().contains { $0.name == "\(old)'s Ghost" }, sourceLocation: sourceLocation)
    }

    @MainActor
    @Test func aRenameMovesTheLadderRowAndTheGhostOnEveryPhone() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let jake = Device("jake", in: dir)
        let alex = Device("alex", in: dir)
        try jake.stores.ghosts.save(trainedGhost("jake", "Jake's Ghost"))
        try jake.play(as: "Jake")
        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")
        _ = await alex.sync(cloud, as: "apple-alex", name: "Alex")
        #expect(alex.stores.ratings.load().games["person:Jake"] == 1)

        guard case .online = await jake.sync(cloud, as: "apple-jake", name: "Bein") else {
            Issue.record("the rename did not come online")
            return
        }
        expectRenamed(jake, from: "Jake", to: "Bein", ghost: "jake")
        #expect(jake.stores.ghosts.ghost(id: "bein")?.id == "jake", "the new name trains the ghost it already has")
        #expect(cloud.locked { $0.names["jake"] } == NameClaim(name: "Bein", owner: "apple-jake"))

        _ = await alex.sync(cloud, as: "apple-alex", name: "Alex")
        expectRenamed(alex, from: "Jake", to: "Bein", ghost: "jake")
        #expect(alex.stores.ratings.load().ratings == jake.stores.ratings.load().ratings, "both phones agree")

        // The old name stays his: nobody else can become "Jake".
        #expect(await Device("impostor", in: dir).sync(cloud, as: "apple-other", name: "Jake") == .nameTaken("Jake"))
    }

    /// Jake's own phone: renamed before renames were tracked, so its sync
    /// state has no record of "jake" having been his. His games still are.
    @MainActor
    @Test func aPhoneThatRenamedBeforeRenamesWereTrackedCatchesUp() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let jake = Device("jake", in: dir)
        try jake.stores.ghosts.save(trainedGhost("jake", "Jake's Ghost"))
        try jake.play(as: "Jake")
        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")
        var state = SyncState.load(from: jake.stores.stateFile)
        state.claimedSlug = nil
        state.ownSlugs = nil
        try state.save(to: jake.stores.stateFile)

        _ = await jake.sync(cloud, as: "apple-jake", name: "Bein")
        expectRenamed(jake, from: "Jake", to: "Bein", ghost: "jake")
    }

    /// A game begun as "Jake" and finished after the rename is still his,
    /// goes up, and lands on the renamed row everywhere. Then he renames back.
    @MainActor
    @Test func gamesFromBeforeARenameAndRenamingBack() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let jake = Device("jake", in: dir)
        let alex = Device("alex", in: dir)
        try jake.stores.ghosts.save(trainedGhost("jake", "Jake's Ghost"))
        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")
        _ = await jake.sync(cloud, as: "apple-jake", name: "Bein")
        try jake.play(as: "Jake")
        _ = await jake.sync(cloud, as: "apple-jake", name: "Bein")
        #expect(cloud.locked { $0.matches.count } == 1, "the game played under the old name went up")
        _ = await alex.sync(cloud, as: "apple-alex", name: "Alex")
        #expect(alex.stores.ratings.load().games["person:Bein"] == 1)

        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")
        _ = await alex.sync(cloud, as: "apple-alex", name: "Alex")
        expectRenamed(jake, from: "Bein", to: "Jake", ghost: "jake")
        expectRenamed(alex, from: "Bein", to: "Jake", ghost: "jake")
    }

    // MARK: - Two players, each other's ghosts

    /// The whole online loop between two people: each gets on, each sees the
    /// other's ghost in their picker, each plays it, and each phone ends on
    /// the same ladder with both ghosts rated.
    @MainActor
    @Test func twoPlayersPlayEachOthersGhosts() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let jake = Device("jake", in: dir)
        let alex = Device("alex", in: dir)
        try jake.stores.ghosts.save(trainedGhost("jake", "Jake's Ghost"))
        try alex.stores.ghosts.save(trainedGhost("alex", "Alex's Ghost"))
        #expect(await jake.sync(cloud, as: "apple-jake", name: "Jake") != .noAccount)
        #expect(await alex.sync(cloud, as: "apple-alex", name: "Alex") != .noAccount)
        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")

        #expect(jake.stores.ghosts.pickable().map(\.name) == ["Alex's Ghost", "Jake's Ghost"])
        #expect(alex.stores.ghosts.pickable().map(\.name) == ["Alex's Ghost", "Jake's Ghost"])

        try jake.play(as: "Jake", against: "alex")
        try alex.play(as: "Alex", against: "jake")
        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")
        _ = await alex.sync(cloud, as: "apple-alex", name: "Alex")
        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")

        for device in [jake, alex] {
            let ladder = device.stores.ratings.load()
            #expect(ladder.games["ghost:jake"] == 1 && ladder.games["ghost:alex"] == 1)
            #expect(ladder.games["person:Jake"] == 1 && ladder.games["person:Alex"] == 1)
        }
        #expect(jake.stores.ratings.load().ratings == alex.stores.ratings.load().ratings)
    }
}
