import CatanAI
import Foundation

/// Keeps this phone's ladder in step with everyone's.
///
/// One pass (`sync()`):
/// 1. **Claim the player's name** for this Apple ID. The first Apple ID to
///    claim a name holds it for good, so nobody else can play as "Jake".
/// 2. **Restore ghosts**, including the owner's, before any older local copy
///    can be published. Claims, not payload names, establish ownership.
/// 3. **Upload** every rated game of the claimed person that has not gone up
///    yet, and the person's ghost if it has learned since. Games wait in the
///    stats store until they go, so a game played offline goes up later.
/// 4. **Download** every game changed since the last pass. Each one is kept
///    only if its person seat is the uploader's own claimed name and its moves
///    replay to the result they claim (`SharedMatch.verified`).
/// 5. **Apply claimed names and rebuild every rating** from the games here, in one
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
        return LiveSync(backend: backend, stores: .standard, displayName: { PlayerNameStore.shared.load() })
    }()

    private let backend: any CloudBackend
    private let stores: Stores
    private let displayName: @Sendable () -> String
    private(set) var status: Status = .never
    private var running: Task<Status, Never>?
    private var rerunRequested = false
    private var renameRequested = false
    private var lastPass: Date?

    init(backend: any CloudBackend, stores: Stores, displayName: @escaping @Sendable () -> String) {
        self.backend = backend
        self.stores = stores
        self.displayName = displayName
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
            let me = try await backend.currentUser()
            let claim = try await claimName(for: me, name: state.pendingRename ?? preferredName,
                                            renaming: state.pendingRename != nil, state: &state)
            var changed = try await downloadGhosts()
            if case .success(let mine) = claim {
                try await carryOverRename(to: mine, me: me, state: &state)
                state.lastPreferredName = preferredName
                state.pendingRename = nil
                try state.save(to: stores.stateFile)
                changed = try await uploadGames(as: mine, state: &state) || changed
                try await uploadGhost(as: mine, state: &state)
            }
            changed = try await downloadGames(state: &state) || changed
            changed = try await applyClaimedNames(state: &state) || changed
            if changed || !state.ratingsRebuilt {
                try stores.ratings.rebuild(from: stores.seatStats.all())
                state.ratingsRebuilt = true
                try state.save(to: stores.stateFile)
            }
            switch claim {
            case .success: return .online(Date())
            case .failure(let status): return status
            }
        } catch CloudSyncError.noAccount {
            return .noAccount
        } catch CloudSyncError.unavailable {
            return .offline
        } catch {
            return .failed(String(describing: error))
        }
    }

    /// A claim held by this user, with the slug it sits under.
    struct OwnClaim: Sendable {
        let slug: String
        /// The accepted server name before an explicit rename; a second
        /// phone may not yet know that this account also owns its slug.
        let previousSlug: String
        let claim: NameClaim
    }

    private func claimName(for me: String, name: String, renaming: Bool,
                           state: inout SyncState) async throws -> Result<OwnClaim, Status> {
        let slug = GhostTrainer.ghostID(forPerson: name)
        // "You" is what a seat is called when nobody typed a name. Claiming it
        // would hand one player every phone's default name for good.
        guard !slug.isEmpty, name.caseInsensitiveCompare(Self.defaultName) != .orderedSame else { return .failure(.noName) }
        var claim = try await backend.claim(slug: slug, name: name)
        // Taken: say so in the name the player typed, not the holder's
        // current name, which after a rename is a different word entirely.
        guard claim.owner == me else {
            return .failure(.nameTaken(GhostTrainer.ghostID(forPerson: claim.name) == slug ? claim.name : name))
        }
        let previousSlug = GhostTrainer.ghostID(forPerson: claim.name)
        // Write ahead of changing the claim: after a partial rename the server
        // no longer tells a restored process which previous slug to finish.
        let ownedSlugs = Set(state.ownSlugs ?? []).union([slug, previousSlug]).sorted()
        if state.ownSlugs != ownedSlugs {
            state.ownSlugs = ownedSlugs
            try state.save(to: stores.stateFile)
        }
        // An unchanged preference on another phone must follow a server rename,
        // not undo it. Join (or a changed local preference) is explicit intent.
        if renaming, claim.name != name {
            try await backend.rename(slug: slug, to: name)
            claim = NameClaim(name: name, owner: me)
        }
        return .success(OwnClaim(slug: slug, previousSlug: previousSlug, claim: claim))
    }

    // MARK: - Renames

    /// Makes a new name a rename rather than a new player (Jake, 2026-09-28:
    /// he changed his name and his row and his ghost's name stayed "Jake").
    ///
    /// Every slug this Apple ID has held is renamed to the new name on the
    /// server, so every phone rewrites its games under it
    /// (`applyClaimedNames`), and this phone's ghost keeps training under the
    /// id it already has. Old slugs stay held: nobody else can become "Jake".
    ///
    /// A phone from before renames were tracked has no `claimedSlug`; its
    /// earlier names are the people in its own games whose slug this Apple ID
    /// holds.
    private func carryOverRename(to mine: OwnClaim, me: String, state: inout SyncState) async throws {
        var candidates = Set(state.ownSlugs ?? []).union([mine.slug, mine.previousSlug])
        // A restored or previously renamed phone may have no own-game history.
        // Downloaded ghosts identify earlier slugs; ownership is still checked
        // against the server below, so another player's ghost is never adopted.
        candidates.formUnion(stores.ghosts.all().map(\.id))
        if state.claimedSlug == nil {
            candidates.formUnion(stores.seatStats.all().flatMap { $0.seats.compactMap { Self.slug(ofPersonKey: $0.entity) } })
        }
        let claims = try await backend.claims(slugs: candidates.sorted())
        let own = candidates.filter { claims[$0]?.owner == me }.sorted()
        for slug in own where slug != mine.slug && claims[slug]?.name != mine.claim.name {
            try await backend.rename(slug: slug, to: mine.claim.name)
        }
        if stores.ghosts.ghost(id: mine.slug) == nil,
           let earlier = own.first(where: { $0 != mine.slug && stores.ghosts.ghost(id: $0) != nil }) {
            try stores.ghosts.alias(mine.slug, to: stores.ghosts.resolve(earlier))
        }
        guard state.claimedSlug != mine.slug || state.ownSlugs != own else { return }
        state.claimedSlug = mine.slug
        state.ownSlugs = own
        try state.save(to: stores.stateFile)
    }

    /// Every person and ghost on this phone under the name its holder goes by
    /// now. Games are rewritten in place (they were verified under the slug,
    /// which does not change), and a ghost is saved again under its new name.
    private func applyClaimedNames(state: inout SyncState) async throws -> Bool {
        let records = stores.seatStats.all()
        let ghosts = stores.ghosts.all()
        let slugs = Set(records.flatMap { $0.seats.compactMap { Self.slug(ofPersonKey: $0.entity) } } + ghosts.map(\.id))
        let claims = try await backend.claims(slugs: slugs.sorted())
        var changed = false
        for record in records {
            let renamed = SeatStatsRecord(match: record.match, date: record.date, seats: record.seats.map { entry in
                guard let slug = Self.slug(ofPersonKey: entry.entity), let claim = claims[slug] else { return entry }
                return SeatStatsRecord.Entry(entity: RatedEntity.person(claim.name).key, stats: entry.stats)
            })
            guard renamed != record else { continue }
            try markRatingsDirty(state: &state)
            try stores.seatStats.replace(renamed)
            changed = true
        }
        for var ghost in ghosts {
            guard let claim = claims[ghost.id] else { continue }
            let ownerSlug = GhostTrainer.ghostID(forPerson: claim.name)
            if stores.ghosts.resolve(ownerSlug) != ghost.id {
                try stores.ghosts.alias(ownerSlug, to: ghost.id)
            }
            guard ghost.name != Self.ghostName(claim.name) else { continue }
            ghost.name = Self.ghostName(claim.name)
            try stores.ghosts.save(ghost)
            changed = true
        }
        return changed
    }

    static func ghostName(_ person: String) -> String { "\(person)'s Ghost" }

    /// Uploads this person's rated games not yet sent. A game whose log is
    /// gone cannot be verified by anyone else, so it stays local; one that
    /// fails its own verification is marked and never retried.
    private func uploadGames(as mine: OwnClaim, state: inout SyncState) async throws -> Bool {
        // A game played as "Jake" before renaming to "Bein" is still this
        // player's, and goes up under "Bein".
        let held = Set(state.ownSlugs ?? []).union([mine.slug])
        let pending = stores.seatStats.all().filter { record in
            !state.uploaded.contains(record.match) && !state.unshareable.contains(record.match)
                && record.seats.contains { Self.slug(ofPersonKey: $0.entity).map(held.contains) ?? false }
        }
        guard !pending.isEmpty else { return false }
        let logs = Dictionary(((try? stores.logs.summaries()) ?? []).map { ($0.gameID, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        for record in pending {
            guard let summary = logs[record.match], let log = try? stores.logs.detail(for: summary) else { continue }
            let shared = SharedMatch(record: record, log: log, name: mine.claim.name)
            guard let verified = try? shared.verified(uploader: mine.claim.name) else {
                state.unshareable.append(record.match)
                try state.save(to: stores.stateFile)
                continue
            }
            try await backend.upload(shared)
            if verified != record {
                try markRatingsDirty(state: &state)
                try stores.seatStats.replace(verified)
                changed = true
            }
            state.uploaded.append(record.match)
            try state.save(to: stores.stateFile)
        }
        return changed
    }

    private func uploadGhost(as mine: OwnClaim, state: inout SyncState) async throws {
        guard let ghost = stores.ghosts.ghost(id: mine.slug) else { return }
        var uploaded = state.ghostGamesUploadedByID ?? [:]
        guard ghost.gamesLearned > (uploaded[ghost.id] ?? -1) else { return }
        try await backend.upload(ghost)
        uploaded[ghost.id] = ghost.gamesLearned
        state.ghostGamesUploadedByID = uploaded
        try state.save(to: stores.stateFile)
    }

    private func downloadGames(state: inout SyncState) async throws -> Bool {
        let since = state.lastModified.map { $0.addingTimeInterval(-Self.queryOverlap) }
        let downloaded = try await backend.matches(modifiedAfter: since)
        let fresh = downloaded.filter { !stores.seatStats.contains(match: $0.value.match) }
        let slugs = Set(fresh.flatMap { $0.value.seats.compactMap(Self.slug(ofPersonKey:)) })
        let claims = try await backend.claims(slugs: slugs.sorted())
        var changed = false
        for game in fresh {
            guard let slug = game.value.seats.lazy.compactMap(Self.slug(ofPersonKey:)).first,
                  let claim = claims[slug], claim.owner == game.owner,
                  let record = try? game.value.verified(uploader: claim.name, holding: slug) else { continue }
            try markRatingsDirty(state: &state)
            try stores.seatStats.record(record)
            changed = true
        }
        if let latest = downloaded.map(\.modified).max() {
            state.lastModified = max(latest, state.lastModified ?? latest)
            try state.save(to: stores.stateFile)
        }
        return changed
    }

    /// Write-ahead invalidation: a pass can fail after persisting a match or
    /// its renamed seat keys. The next process must rebuild even when that
    /// match is no longer fresh and its download cursor has already advanced.
    private func markRatingsDirty(state: inout SyncState) throws {
        guard state.ratingsRebuilt else { return }
        state.ratingsRebuilt = false
        try state.save(to: stores.stateFile)
    }

    /// Ghosts that have learned more than the copy here, including our own:
    /// a restored phone must fetch its newer server copy before publishing.
    /// Only the ghost's owner can publish it, its name is rebuilt from the claim
    /// rather than trusted, and a model of the wrong shape is refused before
    /// it can reach `GhostPolicy`.
    private func downloadGhosts() async throws -> Bool {
        let downloaded = try await backend.ghosts().filter { !$0.value.id.isEmpty }
        let claims = try await backend.claims(slugs: downloaded.map(\.value.id).sorted())
        let shape = PersonModel.anchored(at: .forMode(.classic))
        var changed = false
        for item in downloaded.sorted(by: { $0.value.id < $1.value.id }) {
            var ghost = item.value
            guard let claim = claims[ghost.id], claim.owner == item.owner,
                  ghost.person.weights.count == shape.weights.count, ghost.person.theta.count == shape.theta.count,
                  ghost.gamesLearned > (stores.ghosts.ghost(id: ghost.id)?.gamesLearned ?? -1) else { continue }
            ghost.name = Self.ghostName(claim.name)
            try stores.ghosts.save(ghost)
            changed = true
        }
        return changed
    }

    /// "person:Jake" -> "jake"; `nil` for any seat that is not a person.
    static func slug(ofPersonKey key: String) -> String? {
        guard case .person(let name) = RatedEntity(key: key) else { return nil }
        return GhostTrainer.ghostID(forPerson: name)
    }
}

extension LiveSync.Stores {
    static let standard = LiveSync.Stores(
        seatStats: .shared, ratings: .shared, ghosts: .shared, logs: .shared,
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
    /// Clear only after every known owned claim carries the requested name.
    var pendingRename: String?
    /// The slug this phone last held, and every slug its Apple ID has held:
    /// how a new name is recognised as a rename. Optional so a state file
    /// from before renames decodes rather than resetting.
    var claimedSlug: String?
    var ownSlugs: [String]?
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
