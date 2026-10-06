import CatanAI
import Foundation

/// Keeps this phone's ladder in step with everyone's.
///
/// ## A player is their iCloud account, never their name
/// Jake, 2026-09-29: "change your name and that resets your score and bot
/// score is no good ... nothing new is created unless the user specifies".
/// Every game, rating and ghost is filed under the player's CloudKit user id
/// (`PlayerDirectory`); a name is a label on it. Renaming rewrites one record
/// and moves nothing, and every phone signed into the same Apple ID is the
/// same player.
///
/// One pass (`sync()`):
/// 1. **Adopt the iCloud id** as this phone's player, bringing along what it
///    played before it knew it (`PlayerDirectory.adopt`).
/// 2. **Name the player**, only when they chose a name (Join, New Game, or a
///    first name): the name is claimed so nobody else can use it, then set on
///    their account. Otherwise this phone follows the name the account has.
/// 3. **Restore ghosts**, including the player's own, before any older local
///    copy can be published. A ghost is accepted only from the account it is
///    filed under.
/// 4. **Upload** every rated game of the player that has not gone up yet, and
///    their ghost if it has learned since. Games wait in the stats store until
///    they go, so a game played offline goes up later.
/// 5. **Download** every game changed since the last pass. Each is filed under
///    the account that uploaded it and kept only if its moves replay to the
///    result they claim (`SharedMatch.verified`).
/// 6. **Fetch names and rebuild every rating** from the games here, in one
///    fixed order, so every phone with the same games shows the same ladder.
///
/// ## When it runs
/// Once when a game finishes (and once more after its ghost has trained, to
/// send the ghost), and otherwise at most every `refreshInterval` while the
/// app is open (`refreshIfDue`). Jake, 2026-09-26: refresh "on a periodic
/// basis that stays within limits of needed, otherwise it should just refresh
/// once a game is completed". There are deliberately no push-triggered
/// passes: a push per game anyone finishes would wake every phone on the
/// ladder for every game, which grows with the square of the player count.
///
/// Every step is idempotent, so a pass cut off at any point is finished by
/// the next one. Passes never overlap: one requested while another runs is
/// folded into a second pass after it, so a game finished mid-pass is not
/// left waiting for the next refresh.
actor LiveSync {
    enum Status: Error, Equatable, Sendable {
        case never
        case online(Date)
        /// Nothing to sync as: no name chosen yet, or still the default "You".
        case noName
        /// The name is held by another Apple ID.
        case nameTaken(String)
        case noAccount
        case offline
        case failed(String)
    }

    struct Stores: Sendable {
        let seatStats: SeatStatsStore
        let ratings: RatingStore
        let ghosts: GhostStore
        let logs: GameLogStore
        let players: PlayerDirectory
        /// This phone's sync bookkeeping (`SyncState`).
        let stateFile: URL
    }

    /// Queries overlap the last one by this much. CloudKit's query index is
    /// eventually consistent: a game saved a moment before the last query
    /// can appear in the index after it, with an older modification date.
    static let queryOverlap: TimeInterval = 3600

    /// The fastest a phone checks for other people's games when it has not
    /// finished one itself. A pass is about seven CloudKit requests, so this
    /// is under two requests a minute per open app - far inside CloudKit's
    /// public-database allowance, which grows with active users - while a
    /// friend's game still shows up within five minutes.
    static let refreshInterval: TimeInterval = 300

    /// The seat name used when the player never typed one (`GameViewModel`).
    static let defaultName = "You"

    /// `nil` unless this build is configured for CloudKit, and never under
    /// tests, which must not reach a real database.
    static let shared: LiveSync? = {
        let process = ProcessInfo.processInfo
        guard process.environment["XCTestConfigurationFilePath"] == nil,
              !process.arguments.contains(UITestBootstrap.resetArgument),
              let backend = CloudKitBackend.configured() else { return nil }
        return LiveSync(backend: backend, stores: .standard, displayName: { PlayerNameStore.shared.load() },
                        followName: { PlayerNameStore.shared.save($0) })
    }()

    private let backend: any CloudBackend
    private let stores: Stores
    private let displayName: @Sendable () -> String
    /// Takes on the name the account goes by, when another phone renamed it.
    private let followName: @Sendable (String) -> Void
    private(set) var status: Status = .never
    private var running: Task<Status, Never>?
    private var rerunRequested = false
    private var renameRequested = false
    private var lastPass: Date?

    init(backend: any CloudBackend, stores: Stores, displayName: @escaping @Sendable () -> String,
         followName: @escaping @Sendable (String) -> Void) {
        self.backend = backend
        self.stores = stores
        self.displayName = displayName
        self.followName = followName
    }

    /// A pass, unless one finished within `refreshInterval`; then the status
    /// it left. Launch, returning to the app, the app's timer and the
    /// leaderboard all come through here, so none of them can add requests.
    @discardableResult
    func refreshIfDue(now: Date = Date()) async -> Status {
        if let lastPass, now.timeIntervalSince(lastPass) < Self.refreshInterval { return status }
        return await sync()
    }

    /// A pass now: for a game that just finished, or an explicit Join. Merely
    /// refreshing must not rename an account from another phone's cached name.
    @discardableResult
    func sync(renaming: Bool = false) async -> Status {
        renameRequested = renameRequested || renaming
        if let running {
            rerunRequested = true
            return await running.value
        }
        repeat {
            rerunRequested = false
            let renaming = renameRequested
            renameRequested = false
            let pass = Task { await self.pass(renaming: renaming) }
            running = pass
            status = await pass.value
            lastPass = Date()
            running = nil
        } while rerunRequested
        return status
    }

    // MARK: - One pass

    private func pass(renaming: Bool) async -> Status {
        do {
            var state = SyncState.load(from: stores.stateFile)
            let preferredName = displayName().trimmingCharacters(in: .whitespacesAndNewlines)
            let changedPreference = state.lastPreferredName.map { $0 != preferredName } ?? false
            if renaming || changedPreference {
                state.pendingRename = preferredName
                try state.save(to: stores.stateFile)
            }
            if state.filedByPlayerID != true {
                // Games downloaded under names are re-filed under their
                // uploaders' ids by downloading them all once more.
                state.lastModified = nil
                state.filedByPlayerID = true
                try state.save(to: stores.stateFile)
            }
            let me = try await backend.currentUser()
            if stores.players.me != me {
                try markRatingsDirty(state: &state)
                try stores.players.adopt(me, seatStats: stores.seatStats, ghosts: stores.ghosts)
            }
            let naming = try await nameSelf(me, preferredName: preferredName, state: &state)
            var changed = try await downloadGhosts()
            if naming.joined {
                changed = try await uploadGames(me: me, state: &state) || changed
                try await uploadGhost(me: me, state: &state)
            }
            changed = try await downloadGames(state: &state) || changed
            changed = try await joinSlugGhosts(state: &state) || changed
            try await refreshNames(me: me)
            if changed || !state.ratingsRebuilt {
                try stores.ratings.rebuild(from: stores.seatStats.all())
                state.ratingsRebuilt = true
                try state.save(to: stores.stateFile)
            }
            return naming.problem ?? .online(Date())
        } catch CloudSyncError.noAccount {
            return .noAccount
        } catch CloudSyncError.unavailable {
            return .offline
        } catch {
            return .failed(String(describing: error))
        }
    }

    // MARK: - Names

    /// Sets the player's name on their account when they chose one, or
    /// follows the account's name when they did not. `joined` once the
    /// account has a name: only then do its games go up, so nobody appears on
    /// the ladder before choosing to. A taken name leaves the account as it
    /// was, and keeps asking.
    private func nameSelf(_ me: String, preferredName: String,
                          state: inout SyncState) async throws -> (joined: Bool, problem: Status?) {
        let current = try await backend.names(of: [me])[me]
        guard let wanted = state.pendingRename ?? (current == nil ? preferredName : nil) else {
            // Another phone on this account renamed it; this one follows.
            if let current, current != preferredName {
                followName(current)
                state.lastPreferredName = current
                try state.save(to: stores.stateFile)
            }
            return (true, nil)
        }
        let slug = GhostTrainer.ghostID(forPerson: wanted)
        // "You" is what a seat is called when nobody typed a name. Claiming it
        // would hand one player every phone's default name for good.
        guard !slug.isEmpty, wanted.caseInsensitiveCompare(Self.defaultName) != .orderedSame else {
            try settle(preferredName, state: &state)
            return (current != nil, current == nil ? .noName : nil)
        }
        guard try await backend.claim(slug: slug, name: wanted).owner == me else {
            return (current != nil, .nameTaken(wanted))
        }
        if current != wanted { try await backend.setName(wanted) }
        try settle(preferredName, state: &state)
        return (true, nil)
    }

    private func settle(_ preferredName: String, state: inout SyncState) throws {
        state.pendingRename = nil
        state.lastPreferredName = preferredName
        try state.save(to: stores.stateFile)
    }

    /// Every other player's name as they set it, and each ghost called after
    /// its player. Ghosts carry a name because the picker and a seated ghost's
    /// chair show it; this keeps it current after a rename.
    private func refreshNames(me: String) async throws {
        let ghosts = stores.ghosts.all()
        let people = stores.seatStats.all().flatMap { $0.seats.compactMap(\.personID) }
        // `me` too: the row and ghost show the account's name, never a
        // preference the ladder refused because someone else holds it.
        let ids = Set(people + ghosts.map(\.id) + [me]).sorted()
        let names = try await backend.names(of: ids)
        var contents = stores.players.load()
        if contents.names.merging(names, uniquingKeysWith: { $1 }) != contents.names {
            contents.names.merge(names, uniquingKeysWith: { $1 })
            try stores.players.save(contents)
        }
        for var ghost in ghosts {
            guard let person = ghost.id == me ? stores.players.name(of: me, preferredName: displayName()) : names[ghost.id],
                  !person.isEmpty,
                  ghost.name != Self.ghostName(person) else { continue }
            ghost.name = Self.ghostName(person)
            try stores.ghosts.save(ghost)
        }
    }

    static func ghostName(_ person: String) -> String { "\(person)'s Ghost" }

    // MARK: - Games and ghosts

    /// Uploads this player's rated games not yet sent. A game whose log is
    /// gone cannot be verified by anyone else, so it stays local; one that
    /// fails its own verification is marked and never retried.
    private func uploadGames(me: String, state: inout SyncState) async throws -> Bool {
        let pending = stores.seatStats.all().filter { record in
            !state.uploaded.contains(record.match) && !state.unshareable.contains(record.match)
                && record.seats.contains { $0.personID == me }
        }
        guard !pending.isEmpty else { return false }
        let logs = Dictionary(((try? stores.logs.summaries()) ?? []).map { ($0.gameID, $0) }, uniquingKeysWith: { first, _ in first })
        for record in pending {
            guard let summary = logs[record.match], let log = try? stores.logs.detail(for: summary) else { continue }
            let shared = SharedMatch(record: record, log: log)
            guard (try? shared.verified(owner: me)) != nil else {
                state.unshareable.append(record.match)
                try state.save(to: stores.stateFile)
                continue
            }
            try await backend.upload(shared)
            state.uploaded.append(record.match)
            try state.save(to: stores.stateFile)
        }
        return false
    }

    private func uploadGhost(me: String, state: inout SyncState) async throws {
        guard let ghost = stores.ghosts.ghost(id: me), ghost.id == me else { return }
        var uploaded = state.ghostGamesUploadedByID ?? [:]
        guard ghost.gamesLearned > (uploaded[ghost.id] ?? -1) else { return }
        try await backend.upload(ghost)
        uploaded[ghost.id] = ghost.gamesLearned
        state.ghostGamesUploadedByID = uploaded
        try state.save(to: stores.stateFile)
    }

    /// A game already filed under its uploader is left alone: a game played
    /// here may have had its ghost seat re-filed (`PlayerDirectory`), which
    /// the uploaded copy does not know about.
    private func downloadGames(state: inout SyncState) async throws -> Bool {
        let since = state.lastModified.map { $0.addingTimeInterval(-Self.queryOverlap) }
        let downloaded = try await backend.matches(modifiedAfter: since)
        var changed = false
        for game in downloaded {
            guard let record = try? game.value.verified(owner: game.owner) else { continue }
            let held = stores.seatStats.record(for: record.match)
            guard held?.seats.compactMap(\.personID) != record.seats.compactMap(\.personID) else { continue }
            try markRatingsDirty(state: &state)
            try stores.seatStats.replace(record)
            changed = true
        }
        if let latest = downloaded.map(\.modified).max() {
            state.lastModified = max(latest, state.lastModified ?? latest)
            try state.save(to: stores.stateFile)
        }
        return changed
    }

    /// Ghosts and ghost seats still filed under a name slug - `jake`, the
    /// ghost bundled with the app, or one downloaded before 2026-09-29 - join
    /// the ghost of the account holding that name, so a person's ghost is one
    /// row with one rating on every phone, not "Jake's Ghost" twice. Only once
    /// that account's ghost is here: until then the old one stays playable.
    private func joinSlugGhosts(state: inout SyncState) async throws -> Bool {
        let ghosts = stores.ghosts
        let records = stores.seatStats.all()
        let filed = records.flatMap { $0.seats.compactMap(\.ghostID) } + ghosts.all().map(\.id)
        let slugs = Set(filed).filter { $0 == GhostTrainer.ghostID(forPerson: $0) && ghosts.resolve($0) == $0 }
        if !slugs.isEmpty {
            for (slug, owner) in try await backend.claimants(of: slugs.sorted()).sorted(by: { $0.key < $1.key })
            where owner != slug && ghosts.ghost(id: owner) != nil {
                try ghosts.alias(slug, to: owner)
            }
        }
        var changed = false
        for record in records {
            let refiled = SeatStatsRecord(match: record.match, date: record.date, seats: record.seats.map { entry in
                entry.ghostID.map { SeatStatsRecord.Entry(entity: RatedEntity.ghost(ghosts.resolve($0)).key, stats: entry.stats) }
                    ?? entry
            })
            guard refiled != record else { continue }
            try markRatingsDirty(state: &state)
            try stores.seatStats.replace(refiled)
            changed = true
        }
        return changed
    }

    /// Write-ahead invalidation: a pass can fail after persisting a match or
    /// re-filing games. The next process must rebuild even when that match is
    /// no longer fresh and its download cursor has already advanced.
    private func markRatingsDirty(state: inout SyncState) throws {
        guard state.ratingsRebuilt else { return }
        state.ratingsRebuilt = false
        try state.save(to: stores.stateFile)
    }

    /// Ghosts that have learned more than the copy here, including our own:
    /// a restored phone must fetch its newer server copy before publishing.
    /// A ghost is accepted only from the account it is filed under, and a
    /// model of the wrong shape is refused before it can reach `GhostPolicy`.
    private func downloadGhosts() async throws -> Bool {
        let shape = PersonModel.anchored(at: .forMode(.classic))
        var changed = false
        for item in try await backend.ghosts().sorted(by: { $0.value.id < $1.value.id }) {
            let ghost = item.value
            guard !ghost.id.isEmpty, ghost.id == item.owner,
                  ghost.person.weights.count == shape.weights.count, ghost.person.theta.count == shape.theta.count,
                  ghost.gamesLearned > (stores.ghosts.ghost(id: ghost.id)?.gamesLearned ?? -1) else { continue }
            try stores.ghosts.save(ghost)
            changed = true
        }
        return changed
    }
}

extension SeatStatsRecord.Entry {
    /// The player id of a person seat; `nil` for any other seat.
    var personID: String? {
        guard case .person(let id) = RatedEntity(key: entity) else { return nil }
        return id
    }

    /// The ghost id of a ghost seat; `nil` for any other seat.
    var ghostID: String? {
        guard case .ghost(let id) = RatedEntity(key: entity) else { return nil }
        return id
    }
}

extension LiveSync.Stores {
    static let standard = LiveSync.Stores(
        seatStats: .shared, ratings: .shared, ghosts: .shared, logs: .shared, players: .shared,
        stateFile: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiveSync").appendingPathComponent("state.json"))
}

/// What this phone has already sent and seen. Losing it costs a re-upload
/// (idempotent) and a full download, never data.
struct SyncState: Codable, Equatable, Sendable {
    var uploaded: [UUID] = []
    /// Games that failed their own verification: never offered again.
    var unshareable: [UUID] = []
    /// Scoped to the stable ghost id, not the current display name or device.
    /// Optional so legacy state files retain their cursors and match receipts.
    /// The old global counter is ignored; the first re-upload is idempotent.
    var ghostGamesUploadedByID: [String: Int]?
    /// The locally chosen preference last synced, so a periodic refresh can
    /// distinguish a new choice from another device's stale cached name.
    var lastPreferredName: String?
    /// Explicit rename intent survives a failed request and process restart.
    /// Cleared once the account carries the requested name.
    var pendingRename: String?
    /// Set once downloads are filed by uploader id rather than typed name
    /// (2026-09-29). A phone without it downloads everything once more.
    var filedByPlayerID: Bool?
    /// The newest server modification date seen.
    var lastModified: Date?
    /// False until the first rebuild, so a phone joining the ladder converts
    /// its local ratings even when there is nothing new to download.
    var ratingsRebuilt = false

    static func load(from url: URL) -> SyncState {
        (try? JSONDecoder().decode(SyncState.self, from: Data(contentsOf: url))) ?? SyncState()
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
