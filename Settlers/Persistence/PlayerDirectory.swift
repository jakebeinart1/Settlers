import Foundation

/// Who this phone's player is, and what every player on the ladder is called.
///
/// ## A player is an id, never a name
/// Jake, 2026-09-29: changing your name must not reset your score or your
/// ghost's, and nothing new is created unless you ask for it. So every rating,
/// every rated game's seat and the player's ghost are filed under `me`, and a
/// name is only the label shown for it. A rename changes one string here.
///
/// `me` starts as a `local-` id made on this phone. The first sync signed into
/// iCloud replaces it with the Apple ID's CloudKit user id (`LiveSync`), which
/// every phone on that Apple ID shares, so they are one player on the ladder.
///
/// Before 2026-09-29 players were keyed by name ("person:Jake");
/// `migrateLegacyNames` converts this phone's own games once.
public struct PlayerDirectory: Sendable {
    struct Contents: Codable, Equatable, Sendable {
        var me: String
        /// The ladder's names for other players' ids, as their owners set them.
        var names: [String: String] = [:]
        /// Set once this phone's name-keyed games have been re-filed under `me`.
        var migratedLegacyNames = false
    }

    static let localPrefix = "local-"

    public static let shared = PlayerDirectory(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Players"))

    let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("players.json") }

    /// This phone's player. Made on first use, and never replaced except by
    /// `adopt`, so two early readers cannot end up with different ids.
    var me: String { load().me }

    func load() -> Contents {
        if let data = try? Data(contentsOf: fileURL), let contents = try? JSONDecoder().decode(Contents.self, from: data) {
            return contents
        }
        let fresh = Contents(me: Self.localPrefix + UUID().uuidString.lowercased())
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A racing first reader may have written already; its id wins.
        try? JSONEncoder().encode(fresh).write(to: fileURL, options: .withoutOverwriting)
        return (try? JSONDecoder().decode(Contents.self, from: Data(contentsOf: fileURL))) ?? fresh
    }

    func save(_ contents: Contents) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(contents).write(to: fileURL, options: .atomic)
    }

    /// The label for a player id: this phone's own preference for `me`, the
    /// ladder's name for anyone else, or the id itself. A game filed under a
    /// name before ids existed is keyed by that name, so it still reads right.
    func name(of id: String, preferredName: String = PlayerNameStore.shared.load()) -> String {
        let contents = load()
        if id == contents.me, !preferredName.isEmpty { return preferredName }
        return contents.names[id] ?? (id.hasPrefix(Self.localPrefix) ? LiveSync.defaultName : id)
    }

    /// Makes `id` (an iCloud user id) this phone's player. A phone still on
    /// its `local-` id brings its games and ghost along: they were this
    /// person's all along. A phone signed into a different Apple ID than
    /// before is a different person, and starts from that person's own games.
    /// Returns whether any game was re-filed, so ratings need a rebuild.
    @discardableResult
    func adopt(_ id: String, seatStats: SeatStatsStore, ghosts: GhostStore) throws -> Bool {
        var contents = load()
        guard contents.me != id else { return false }
        var refiled = false
        if contents.me.hasPrefix(Self.localPrefix) {
            refiled = try Self.refile(persons: [contents.me], ghostIDs: Set([contents.me]).filter { ghosts.isLocal($0) },
                                      onlyMatches: nil, to: id, seatStats: seatStats, ghosts: ghosts)
        }
        contents.me = id
        try save(contents)
        return refiled
    }

    /// Re-files this phone's own name-keyed games under `me`, once.
    ///
    /// A game is this phone's own when its log is here: only a game played on
    /// this phone has one. Its person seat is this player whatever name was
    /// typed, because a name typed into New Game has always been a rename, not
    /// a new player. Games downloaded from the ladder are left for `LiveSync`,
    /// which re-files each under its uploader's id when it next downloads it.
    /// Returns whether any game was re-filed, so ratings need a rebuild.
    func migrateLegacyNames(seatStats: SeatStatsStore, ghosts: GhostStore, logs: GameLogStore) throws -> Bool {
        var contents = load()
        guard !contents.migratedLegacyNames else { return false }
        let local = Set(((try? logs.summaries()) ?? []).map(\.gameID))
        let names = Set(seatStats.all().filter { local.contains($0.match) }.flatMap { record in
            record.seats.compactMap { entry -> String? in
                guard case .person(let name) = RatedEntity(key: entry.entity), name != contents.me else { return nil }
                return name
            }
        })
        // This person's ghost was filed under each name's slug (`jake`), and a
        // rename may have aliased one to another. Keep the one that learned most.
        let ghostIDs = Set(names.map { ghosts.resolve(GhostTrainer.ghostID(forPerson: $0)) })
            .filter { ghosts.isLocal($0) }
        let refiled = try Self.refile(persons: names, ghostIDs: ghostIDs, onlyMatches: local, to: contents.me,
                                      seatStats: seatStats, ghosts: ghosts)
        contents.migratedLegacyNames = true
        try save(contents)
        return refiled
    }

    /// Moves `persons` (in `onlyMatches`, or every game) and the ghosts
    /// `ghostIDs` (in every game) to player `id`. The ghost that learned most
    /// becomes `id`'s ghost; the others become its history.
    private static func refile(persons: Set<String>, ghostIDs: Set<String>, onlyMatches: Set<UUID>?, to id: String,
                               seatStats: SeatStatsStore, ghosts: GhostStore) throws -> Bool {
        let keep = ghostIDs.sorted().max { (ghosts.ghost(id: $0)?.gamesLearned ?? -1) < (ghosts.ghost(id: $1)?.gamesLearned ?? -1) }
        if let keep, keep != id { try ghosts.move(keep, to: id) }
        for other in ghostIDs.sorted() where other != keep && other != id { try ghosts.alias(other, to: id) }
        let personKeys = Set(persons.map { RatedEntity.person($0).key })
        let ghostKeys = Set(ghostIDs.map { RatedEntity.ghost($0).key })
        var changed = false
        for record in seatStats.all() {
            let refiled = SeatStatsRecord(match: record.match, date: record.date, seats: record.seats.map { entry in
                let own = onlyMatches.map { $0.contains(record.match) } ?? true
                if own, personKeys.contains(entry.entity) {
                    return SeatStatsRecord.Entry(entity: RatedEntity.person(id).key, stats: entry.stats)
                }
                if ghostKeys.contains(entry.entity) {
                    return SeatStatsRecord.Entry(entity: RatedEntity.ghost(id).key, stats: entry.stats)
                }
                return entry
            })
            guard refiled != record else { continue }
            try seatStats.replace(refiled)
            changed = true
        }
        return changed
    }
}
