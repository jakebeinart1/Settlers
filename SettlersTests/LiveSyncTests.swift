import CatanAI
import CatanEngine
import Foundation
import Testing
@testable import Settlers

/// The online ladder, end to end, with an in-memory CloudKit: two phones,
/// each with its own stores and Apple ID, sharing one database.
///
/// A player is their Apple ID's user id ("apple-jake" here), never their name
/// (Jake, 2026-09-29): renaming must keep the score and the ghost.
@Suite(.serialized) struct LiveSyncTests {

    /// A shared database with CloudKit's one guarantee: only a record's
    /// creator may change it.
    final class FakeCloud: @unchecked Sendable {
        private let lock = NSLock()
        private var clock = Date(timeIntervalSince1970: 1_000_000)
        private(set) var claims: [String: NameClaim] = [:]
        private(set) var accounts: [String: String] = [:]
        private(set) var matches: [UUID: Downloaded<SharedMatch>] = [:]
        private(set) var ghosts: [String: Downloaded<GhostProfile>] = [:]
        var failNextSetName = false
        var failNextAccountLookup = false

        func locked<T>(_ body: (FakeCloud) throws -> T) rethrows -> T {
            lock.lock()
            defer { lock.unlock() }
            return try body(self)
        }

        fileprivate func tick() -> Date {
            clock = clock.addingTimeInterval(1)
            return clock
        }

        fileprivate func setClaim(_ slug: String, _ claim: NameClaim) { claims[slug] = claim }
        fileprivate func setAccount(_ id: String, _ name: String) { accounts[id] = name }
        fileprivate func setMatch(_ match: Downloaded<SharedMatch>) { matches[match.value.match] = match }
        fileprivate func setGhost(_ ghost: Downloaded<GhostProfile>) { ghosts[ghost.value.id] = ghost }
    }

    struct Phone: CloudBackend {
        let cloud: FakeCloud
        let user: String

        func currentUser() async throws -> String {
            try cloud.locked { cloud in
                if cloud.failNextAccountLookup {
                    cloud.failNextAccountLookup = false
                    throw CloudSyncError.unavailable
                }
                return user
            }
        }

        func claim(slug: String, name: String) async throws -> NameClaim {
            cloud.locked { cloud in
                if let existing = cloud.claims[slug] { return existing }
                let claim = NameClaim(name: name, owner: user)
                cloud.setClaim(slug, claim)
                return claim
            }
        }

        func setName(_ name: String) async throws {
            try cloud.locked { cloud in
                if cloud.failNextSetName {
                    cloud.failNextSetName = false
                    throw CloudSyncError.unavailable
                }
                cloud.setAccount(user, name)
            }
        }

        func names(of ids: [String]) async throws -> [String: String] {
            cloud.locked { cloud in cloud.accounts.filter { ids.contains($0.key) } }
        }

        func claimants(of slugs: [String]) async throws -> [String: String] {
            cloud.locked { cloud in cloud.claims.filter { slugs.contains($0.key) }.mapValues(\.owner) }
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

    /// The name preference on one phone (`PlayerNameStore` in the app).
    final class NameBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = ""
        var name: String {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    struct Device {
        let root: URL
        let stores: LiveSync.Stores
        let preference = NameBox()

        init(_ name: String, in root: URL, bundledGhosts: [URL] = []) {
            let dir = root.appendingPathComponent(name)
            self.root = dir
            stores = LiveSync.Stores(
                seatStats: SeatStatsStore(directory: dir.appendingPathComponent("stats")),
                ratings: RatingStore(directory: dir.appendingPathComponent("ratings")),
                ghosts: GhostStore(localDirectory: dir.appendingPathComponent("ghosts"), bundledGhosts: bundledGhosts),
                logs: GameLogStore(directoryURL: dir.appendingPathComponent("logs"), maxKeptLogs: 10),
                players: PlayerDirectory(directory: dir.appendingPathComponent("players")),
                stateFile: dir.appendingPathComponent("sync/state.json"))
        }

        var me: String { stores.players.me }

        func liveSync(_ backend: any CloudBackend, name: String) -> LiveSync {
            preference.name = name
            let preference = preference
            return LiveSync(backend: backend, stores: stores, displayName: { preference.name },
                            followName: { preference.name = $0 })
        }

        /// A sync as the app runs one, with the player's name preference set
        /// to `name` first.
        func sync(_ cloud: FakeCloud, as user: String, name: String) async -> LiveSync.Status {
            await liveSync(Phone(cloud: cloud, user: user), name: name).sync()
        }

        /// Plays one whole rated game on this device as `name`, with
        /// `ghost` in seat 2 if given.
        @MainActor
        func play(as name: String, against ghost: String? = nil) async throws {
            let suite = "LiveSyncTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let setupStore = MatchSetupStore()
            setupStore.defaults = defaults
            let model = GameViewModel(
                checkpointStore: MatchCheckpointStore(fileURL: root.appendingPathComponent("match_checkpoint.json")),
                gameStore: GameStore(fileURL: root.appendingPathComponent("save.json")),
                civilizationStore: CivilizationAssignmentStore(fileURL: root.appendingPathComponent("civs.json")),
                matchSetupStore: setupStore, gameLogStore: stores.logs,
                gameStatsStore: GameStatsStore(fileURL: root.appendingPathComponent("gamestats.json")),
                ghostStore: stores.ghosts, ratingStore: stores.ratings, seatStatsStore: stores.seatStats,
                playerDirectory: stores.players, makeGhostTrainer: completionBookkeepingTrainer)
            // A second game first restores the previous completed checkpoint;
            // finish that bounded work before replacing the table or its files.
            await model.lastFinishedMatchWork?.value
            var setup = MatchSetup.default(preferredName: name, preferredCivilization: .greece)
            setup.randomizeSeatOrder = false
            setup.seats[2].ghostID = ghost
            #expect(setup.newGameProblem(knownGhosts: Set(stores.ghosts.pickable().map(\.id))) == nil)
            model.startNewGame(setup: setup)
            try model.qaPlayToEnd()
            await model.lastFinishedMatchWork?.value
            guard case .gameOver = model.state.phase else { throw CancellationError() }
        }

        /// This device's first game in shared form.
        func sharedGame() throws -> SharedMatch {
            let record = try #require(stores.seatStats.all().first)
            let summary = try #require(try stores.logs.summaries().first { $0.gameID == record.match })
            return SharedMatch(record: record, log: try stores.logs.detail(for: summary))
        }

        /// The ladder's label for a player id on this phone.
        func name(of id: String) -> String { stores.players.name(of: id, preferredName: preference.name) }
    }

    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LiveSyncTests.\(UUID().uuidString)")
    }

    private func trainedGhost(_ id: String, _ name: String, games: Int = 12) -> GhostProfile {
        GhostProfile(id: id, name: name, person: .anchored(at: .forMode(.classic)), lambda: 0.01, gamesLearned: games)
    }

    // MARK: - Tests

    @MainActor
    @Test func aGamePlayedOnOnePhoneGivesAnotherPhoneTheSameLadder() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let jake = Device("jake", in: dir)
        let alex = Device("alex", in: dir)
        try await jake.play(as: "Jake")

        guard case .online = await jake.sync(cloud, as: "apple-jake", name: "Jake") else {
            Issue.record("Jake's phone did not come online")
            return
        }
        #expect(jake.me == "apple-jake", "the phone's player is its Apple ID")
        #expect(cloud.locked { $0.matches.count } == 1)
        guard case .online = await alex.sync(cloud, as: "apple-alex", name: "Alex") else {
            Issue.record("Alex's phone did not come online")
            return
        }
        #expect(alex.stores.seatStats.all() == jake.stores.seatStats.all(), "the replayed stats match the player's own")
        let ladder = alex.stores.ratings.load()
        #expect(ladder.games["person:apple-jake"] == 1)
        #expect(alex.name(of: "apple-jake") == "Jake")
        #expect(ladder.ratings == jake.stores.ratings.load().ratings, "both phones show the same Elo")
    }

    @Test func aClaimedNameCannotBeTakenByAnotherAppleID() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        _ = await Device("jake", in: dir).sync(cloud, as: "apple-jake", name: "Jake")
        let status = await Device("impostor", in: dir).sync(cloud, as: "apple-other", name: "jake ")
        #expect(status == .nameTaken("jake"))
        #expect(await Device("blank", in: dir).sync(cloud, as: "apple-blank", name: "  ") == .noName)
        #expect(await Device("default", in: dir).sync(cloud, as: "apple-default", name: "You") == .noName)
        #expect(cloud.locked { $0.accounts } == ["apple-jake": "Jake"])
    }

    /// Jake, 2026-09-29: "nothing new is created unless the user specifies".
    /// A phone that never chose a name puts nothing on the ladder.
    @MainActor
    @Test func nothingGoesUpBeforeThePlayerChoosesAName() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let phone = Device("phone", in: dir)
        try await phone.play(as: "You")
        #expect(await phone.sync(cloud, as: "apple-new", name: "You") == .noName)
        #expect(cloud.locked { $0.matches.isEmpty && $0.accounts.isEmpty && $0.claims.isEmpty })
        #expect(phone.stores.ratings.load().games["person:apple-new"] == 1, "the game still counts on the phone")

        guard case .online = await phone.liveSync(Phone(cloud: cloud, user: "apple-new"), name: "Sam").sync(renaming: true) else {
            Issue.record("Joining did not come online")
            return
        }
        #expect(cloud.locked { $0.matches.count } == 1, "the game played before joining goes up once they join")
    }

    /// A game its moves do not finish never reaches anyone's ladder, and a
    /// game is always filed under the account that uploaded it: nobody can
    /// post one as someone else.
    @MainActor
    @Test func forgedGamesAreRejected() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let source = Device("source", in: dir)
        try await source.play(as: "Jake")
        let game = try source.sharedGame()
        let truncated = SharedMatch(version: game.version, match: UUID(), date: game.date, seats: game.seats,
                                    initialState: game.initialState, moves: Array(game.moves.dropLast(40)))
        try await Phone(cloud: cloud, user: "apple-other").upload(truncated)

        let observer = Device("observer", in: dir)
        #expect(await observer.sync(cloud, as: "apple-observer", name: "Observer") != .noAccount)
        #expect(observer.stores.seatStats.all().isEmpty)
        #expect(throws: SharedMatch.Rejection.notFinished) { try truncated.verified(owner: "apple-other") }
        let filed = try game.verified(owner: "apple-other")
        #expect(filed.seats.compactMap(\.personID) == ["apple-other"])
    }

    @Test func ghostsSyncFromTheirOwnerOnly() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let jake = Device("jake", in: dir)
        try jake.stores.ghosts.save(trainedGhost(jake.me, "Jake's Ghost"))
        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")
        #expect(cloud.locked { $0.ghosts["apple-jake"]?.value.gamesLearned } == 12, "the ghost went up under the Apple ID")
        // A ghost filed under someone else's account is ignored.
        try await Phone(cloud: cloud, user: "apple-other").upload(trainedGhost("apple-alex", "Fake", games: 99))

        let alex = Device("alex", in: dir)
        _ = await alex.sync(cloud, as: "apple-alex", name: "Alex")
        let ghost = try #require(alex.stores.ghosts.ghost(id: "apple-jake"))
        #expect(ghost.gamesLearned == 12)
        #expect(ghost.name == "Jake's Ghost")
        #expect(alex.stores.ghosts.all().map(\.id) == ["apple-jake"])
    }

    @Test(arguments: [true, false])
    func aFreshOwnerRestoresTheNewerCloudGhostWithoutDowngradingIt(hasOlderCopy: Bool) async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let owner = Phone(cloud: cloud, user: "apple-jake")
        try await owner.setName("Jake")
        try await owner.upload(trainedGhost("apple-jake", "Jake's Ghost", games: 25))
        let fresh = Device("fresh", in: dir)
        if hasOlderCopy {
            try fresh.stores.ghosts.save(trainedGhost(fresh.me, "Jake's Ghost", games: 24))
        }

        guard case .online = await fresh.sync(cloud, as: "apple-jake", name: "Jake") else {
            Issue.record("The restored owner did not come online")
            return
        }
        #expect(cloud.locked { $0.ghosts["apple-jake"]?.value.gamesLearned } == 25)
        #expect(fresh.stores.ghosts.ghost(id: "apple-jake")?.gamesLearned == 25)
        #expect(fresh.stores.ghosts.all().count == 1)
    }

    @MainActor
    @Test func aFailedRatingWriteIsRebuiltAfterRelaunchWithoutRedownloadingTheMatch() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let observer = Device("observer", in: dir)
        _ = await observer.sync(cloud, as: "apple-observer", name: "Observer")
        let source = Device("source", in: dir)
        try await source.play(as: "Jake")
        _ = await source.sync(cloud, as: "apple-jake", name: "Jake")
        let match = try #require(source.stores.seatStats.all().first?.match)
        // The pass can persist stats and its download cursor, but writing the
        // derived ladder fails. These paths belong to this test's temp root.
        let ratingsDirectory = observer.root.appendingPathComponent("ratings")
        try FileManager.default.removeItem(at: ratingsDirectory)
        try Data("not a directory".utf8).write(to: ratingsDirectory)
        let failed = await observer.sync(cloud, as: "apple-observer", name: "Observer")
        guard case .failed = failed else {
            Issue.record("Expected a rating-write failure, got \(failed)")
            return
        }
        #expect(observer.stores.seatStats.contains(match: match))
        try FileManager.default.removeItem(at: ratingsDirectory)

        // Device.sync constructs a new LiveSync, so this checks the durable
        // retry after a process restart, not an in-memory changed flag.
        guard case .online = await observer.sync(cloud, as: "apple-observer", name: "Observer") else {
            Issue.record("The recovered device did not come online")
            return
        }
        #expect(observer.stores.ratings.load().ratedMatches == [match])
        #expect(observer.stores.ratings.load().games["person:apple-jake"] == 1)
    }

    /// A phone signed into another Apple ID is another person: nothing of the
    /// first person's is moved to them.
    @MainActor
    @Test func switchingAppleAccountsStartsTheNewPersonFromTheirOwnGames() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let device = Device("shared-phone", in: dir)
        try device.stores.ghosts.save(trainedGhost(device.me, "Jake's Ghost", games: 25))
        try await device.play(as: "Jake")
        _ = await device.sync(cloud, as: "apple-jake", name: "Jake")

        guard case .online = await device.sync(cloud, as: "apple-alex", name: "Alex") else {
            Issue.record("The new account did not come online")
            return
        }
        #expect(device.me == "apple-alex")
        #expect(device.stores.ratings.load().games["person:apple-jake"] == 1)
        #expect(device.stores.ratings.load().games["person:apple-alex"] == nil)
        #expect(cloud.locked { $0.ghosts["apple-jake"]?.value.gamesLearned } == 25)
        #expect(cloud.locked { $0.ghosts["apple-alex"] } == nil)
    }

    @Test func legacySyncStateRetainsItsMatchReceipts() throws {
        let json = #"{"uploaded":["00000000-0000-0000-0000-000000000001"],"unshareable":[],"ghostGamesUploaded":25,"lastModified":123,"ratingsRebuilt":true,"claimedSlug":"jake","ownSlugs":["jake"]}"#
        let state = try JSONDecoder().decode(SyncState.self, from: Data(json.utf8))

        #expect(state.uploaded == [UUID(uuidString: "00000000-0000-0000-0000-000000000001")!])
        #expect(state.lastModified == Date(timeIntervalSince1970: 978_307_323))
        #expect(state.ratingsRebuilt)
        #expect(state.filedByPlayerID == nil, "so its downloads are fetched once more and re-filed by uploader")
        #expect(state.ghostGamesUploadedByID == nil)
    }

    // MARK: - Renames (Jake, 2026-09-29: "you change your name and that
    // resets your score and bot score is no good")

    @MainActor
    @Test func aRenameKeepsTheScoreAndTheGhostOnEveryPhone() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let jake = Device("jake", in: dir)
        let alex = Device("alex", in: dir)
        try jake.stores.ghosts.save(trainedGhost(jake.me, "Jake's Ghost"))
        try await jake.play(as: "Jake", against: jake.me)
        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")
        _ = await alex.sync(cloud, as: "apple-alex", name: "Alex")
        let before = jake.stores.ratings.load()

        guard case .online = await jake.sync(cloud, as: "apple-jake", name: "Bein") else {
            Issue.record("the rename did not come online")
            return
        }
        _ = await alex.sync(cloud, as: "apple-alex", name: "Alex")
        for device in [jake, alex] {
            let ladder = device.stores.ratings.load()
            #expect(ladder.ratings == before.ratings && ladder.games == before.games, "nothing about the score moved")
            #expect(device.name(of: "apple-jake") == "Bein")
            #expect(device.stores.ghosts.ghost(id: "apple-jake")?.name == "Bein's Ghost")
            #expect(device.stores.ghosts.ghost(id: "apple-jake")?.gamesLearned == 12, "the same ghost, still trained")
            #expect(device.stores.ghosts.all().count == 1, "no second ghost")
        }
        #expect(cloud.locked { $0.accounts["apple-jake"] } == "Bein")

        // The old name stays his: nobody else can become "Jake", and he can go back.
        #expect(await Device("impostor", in: dir).sync(cloud, as: "apple-other", name: "Jake") == .nameTaken("Jake"))
        guard case .online = await jake.sync(cloud, as: "apple-jake", name: "Jake") else {
            Issue.record("renaming back did not come online")
            return
        }
        #expect(cloud.locked { $0.accounts["apple-jake"] } == "Jake")
    }

    /// Without the ladder (Jake's own builds): a name typed into New Game is
    /// the same player, not a new row.
    @MainActor
    @Test func aRenameWithoutSyncKeepsTheSameRow() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let phone = Device("phone", in: dir)
        try await phone.play(as: "Jake")
        try await phone.play(as: "Bein")
        let people = phone.stores.ratings.load().games.keys.filter { $0.hasPrefix(RatedEntity.personPrefix) }
        #expect(people == ["person:\(phone.me)"])
        #expect(phone.stores.ratings.load().games["person:\(phone.me)"] == 2)
    }

    /// Two phones on one Apple ID are one player: games from both land on one
    /// row, on both phones.
    @MainActor
    @Test func twoPhonesOnOneAppleIDAreOnePlayer() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let phone = Device("phone", in: dir)
        let ipad = Device("ipad", in: dir)
        try await phone.play(as: "Jake")
        try await ipad.play(as: "Jake")
        _ = await phone.sync(cloud, as: "apple-jake", name: "Jake")
        _ = await ipad.sync(cloud, as: "apple-jake", name: "Jake")
        _ = await phone.sync(cloud, as: "apple-jake", name: "Jake")
        for device in [phone, ipad] {
            let people = device.stores.ratings.load().games.filter { $0.key.hasPrefix(RatedEntity.personPrefix) }
            #expect(people == ["person:apple-jake": 2])
        }
    }

    /// Another phone on the account follows a rename rather than undoing it
    /// with its older cached name; choosing a name there is a rename too.
    @Test func anotherPhoneFollowsARenameAndCanMakeItsOwn() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let first = Device("first", in: dir)
        let second = Device("second", in: dir)
        _ = await first.sync(cloud, as: "apple-jake", name: "Jake")
        _ = await second.sync(cloud, as: "apple-jake", name: "Jake")
        _ = await first.sync(cloud, as: "apple-jake", name: "Bein")
        _ = await second.sync(cloud, as: "apple-jake", name: "Jake")

        #expect(cloud.locked { $0.accounts["apple-jake"] } == "Bein")
        #expect(second.preference.name == "Bein", "the other phone took on the new name")
        _ = await second.liveSync(Phone(cloud: cloud, user: "apple-jake"), name: "Jake").sync(renaming: true)
        #expect(cloud.locked { $0.accounts["apple-jake"] } == "Jake")
    }

    @Test(arguments: [true, false])
    func anExplicitRenameRetriesAfterFailureAndRelaunch(failingAccountLookup: Bool) async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let phone = Device("phone", in: dir)
        _ = await phone.sync(cloud, as: "apple-jake", name: "Jake")
        cloud.locked {
            $0.failNextAccountLookup = failingAccountLookup
            $0.failNextSetName = !failingAccountLookup
        }
        let join = phone.liveSync(Phone(cloud: cloud, user: "apple-jake"), name: "Bein")
        #expect(await join.sync(renaming: true) == .offline)
        guard case .online = await phone.sync(cloud, as: "apple-jake", name: "Bein") else {
            Issue.record("The requested rename was not retried after relaunch")
            return
        }
        #expect(cloud.locked { $0.accounts["apple-jake"] } == "Bein")
        #expect(SyncState.load(from: phone.stores.stateFile).pendingRename == nil)
    }

    // MARK: - Before player ids (games filed under typed names)

    /// A phone from before 2026-09-29 holds its games as "person:Jake" and
    /// "person:Bein" and its ghost as `jake`. All of it becomes one player,
    /// once; a downloaded game of someone else's is left for sync to re-file.
    @MainActor
    @Test func namedGamesFromBeforePlayerIDsBecomeOnePlayer() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let phone = Device("phone", in: dir)
        try phone.stores.ghosts.save(trainedGhost("jake", "Jake's Ghost", games: 25))
        try phone.stores.ghosts.save(trainedGhost("bein", "Bein's Ghost", games: 3))
        try await phone.play(as: "Jake")
        try await phone.play(as: "Bein")
        let me = phone.me
        let legacy = ["person:Jake", "person:Bein"]
        for (record, name) in zip(phone.stores.seatStats.all(), legacy) {
            try phone.stores.seatStats.replace(SeatStatsRecord(match: record.match, date: record.date, seats: record.seats.map {
                $0.personID == me ? .init(entity: name, stats: $0.stats) : $0
            }))
        }
        var alexs = try #require(phone.stores.seatStats.all().first)
        alexs = SeatStatsRecord(match: UUID(), date: alexs.date, seats: alexs.seats.enumerated().map { index, entry in
            .init(entity: index == 0 ? "person:Alex" : index == 1 ? "ghost:jake" : entry.entity, stats: entry.stats)
        })
        try phone.stores.seatStats.record(alexs)
        try PlayerDirectory(directory: phone.root.appendingPathComponent("players")).save(.init(me: me))

        let players = phone.stores.players
        #expect(try players.migrateLegacyNames(seatStats: phone.stores.seatStats, ghosts: phone.stores.ghosts,
                                               logs: phone.stores.logs))
        let people = phone.stores.seatStats.all().flatMap { $0.seats.compactMap(\.personID) }
        #expect(people.sorted() == ["Alex", me, me].sorted())
        #expect(phone.stores.ghosts.all().map(\.id) == [me], "one ghost, the one that learned most")
        #expect(phone.stores.ghosts.ghost(id: me)?.gamesLearned == 25)
        #expect(phone.stores.ghosts.ghost(id: "jake")?.id == me, "a save seating `jake` still finds it")
        #expect(phone.stores.seatStats.record(for: alexs.match)?.seats[1].entity == "ghost:\(me)")
        #expect(try !players.migrateLegacyNames(seatStats: phone.stores.seatStats, ghosts: phone.stores.ghosts,
                                                logs: phone.stores.logs), "once")
    }

    /// Refreshes stay within `refreshInterval`; a finished game still syncs
    /// at once (Jake, 2026-09-26).
    @Test func refreshesAreThrottledButAFinishedGameSyncsAtOnce() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let counter = CountingPhone(inner: Phone(cloud: FakeCloud(), user: "apple-jake"))
        let sync = Device("jake", in: dir).liveSync(counter, name: "Jake")
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
        func setName(_ name: String) async throws { try await inner.setName(name) }
        func names(of ids: [String]) async throws -> [String: String] { try await inner.names(of: ids) }
        func claimants(of slugs: [String]) async throws -> [String: String] { try await inner.claimants(of: slugs) }
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
        try jake.stores.ghosts.save(trainedGhost(jake.me, "Jake's Ghost"))
        try alex.stores.ghosts.save(trainedGhost(alex.me, "Alex's Ghost"))
        #expect(await jake.sync(cloud, as: "apple-jake", name: "Jake") != .noAccount)
        #expect(await alex.sync(cloud, as: "apple-alex", name: "Alex") != .noAccount)
        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")

        #expect(jake.stores.ghosts.pickable().map(\.name) == ["Alex's Ghost", "Jake's Ghost"])
        #expect(alex.stores.ghosts.pickable().map(\.name) == ["Alex's Ghost", "Jake's Ghost"])

        try await jake.play(as: "Jake", against: "apple-alex")
        try await alex.play(as: "Alex", against: "apple-jake")
        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")
        _ = await alex.sync(cloud, as: "apple-alex", name: "Alex")
        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")

        for device in [jake, alex] {
            let ladder = device.stores.ratings.load()
            #expect(ladder.games["ghost:apple-jake"] == 1 && ladder.games["ghost:apple-alex"] == 1)
            #expect(ladder.games["person:apple-jake"] == 1 && ladder.games["person:apple-alex"] == 1)
        }
        #expect(jake.stores.ratings.load().ratings == alex.stores.ratings.load().ratings)
    }

    // MARK: - One row per player

    /// Every name on a phone's ladder, which must not repeat.
    private func ladderNames(_ device: Device) -> [String] {
        LeaderboardModel.rows(ratings: device.stores.ratings.load(), ghosts: device.stores.ghosts.all(),
                              name: device.name(of:)).map(\.name)
    }

    /// Jake's ghost ships in the app as `jake`, and his phone uploads the same
    /// ghost under his Apple ID. Every other phone must show one Jake's Ghost,
    /// with the games against either copy rated as that one ghost.
    @MainActor
    @Test func theBundledGhostIsItsOwnersSyncedGhost() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bundled = dir.appendingPathComponent("jake.ghost")
        try JSONEncoder().encode(trainedGhost("jake", "Jake's Ghost", games: 24)).write(to: bundled)
        let jake = Device("jake", in: dir)
        let alex = Device("alex", in: dir, bundledGhosts: [bundled])
        try await alex.play(as: "Alex", against: "jake")
        try jake.stores.ghosts.save(trainedGhost(jake.me, "Jake's Ghost", games: 30))
        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")
        _ = await alex.sync(cloud, as: "apple-alex", name: "Alex")
        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")

        #expect(alex.stores.ghosts.all().map(\.id) == ["apple-jake"])
        #expect(alex.stores.ghosts.ghost(id: "jake")?.gamesLearned == 30, "the old id plays the newest ghost")
        for device in [jake, alex] {
            let ladder = device.stores.ratings.load()
            #expect(ladder.games["ghost:apple-jake"] == 1 && ladder.games["ghost:jake"] == nil)
            let names = ladderNames(device)
            #expect(Set(names).count == names.count, "\(names)")
        }
        #expect(jake.stores.ratings.load().ratings == alex.stores.ratings.load().ratings)
    }

    /// A name refused because another account holds it is never shown: not
    /// on the player's row, not on their ghost, and not on a phone that has
    /// not joined yet. Otherwise the ladder reads "Jake" twice.
    @Test func aRefusedNameIsNeverShownBesideItsHolder() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let jake = Device("jake", in: dir)
        let bob = Device("bob", in: dir)
        try jake.stores.ghosts.save(trainedGhost(jake.me, "Jake's Ghost"))
        try bob.stores.ghosts.save(trainedGhost(bob.me, "Bob's Ghost"))
        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")
        _ = await bob.sync(cloud, as: "apple-bob", name: "Bob")

        let refused = await bob.liveSync(Phone(cloud: cloud, user: "apple-bob"), name: "Jake").sync(renaming: true)
        #expect(refused == .nameTaken("Jake"))
        #expect(bob.name(of: "apple-bob") == "Bob")
        #expect(bob.stores.ghosts.ghost(id: "apple-bob")?.name == "Bob's Ghost")
        #expect(ladderNames(bob).filter { $0.contains("Jake") }.count == 1)

        let newcomer = Device("new", in: dir)
        #expect(await newcomer.sync(cloud, as: "apple-new", name: "jake") == .nameTaken("jake"))
        #expect(newcomer.name(of: "apple-new") == LiveSync.defaultName)
    }

    /// Jake's phone, 2026-10-06: a ghost downloaded before player ids as
    /// `immanuel`, renamed `chandy -> immanuel`, beside the same person's
    /// synced ghost. Only `chandy` is claimed online.
    @Test func aRenamedOldGhostJoinsItsOwnersSyncedGhost() async throws {
        let dir = root()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = FakeCloud()
        let chandy = Device("chandy", in: dir)
        try chandy.stores.ghosts.save(trainedGhost(chandy.me, "Chandy's Ghost", games: 3))
        _ = await chandy.sync(cloud, as: "apple-chandy", name: "Chandy")

        let jake = Device("jake", in: dir)
        try jake.stores.ghosts.save(trainedGhost("immanuel", "Chandy's Ghost", games: 2))
        try jake.stores.ghosts.alias("chandy", to: "immanuel")
        _ = await jake.sync(cloud, as: "apple-jake", name: "Jake")

        #expect(jake.stores.ghosts.all().map(\.id) == ["apple-chandy"])
        #expect(jake.stores.ghosts.ghost(id: "immanuel")?.gamesLearned == 3)
    }
}
