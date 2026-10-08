import CatanAI
import Foundation

/// Every ghost this phone knows: the ones bundled with the app, and the ones
/// trained here.
///
/// ## Layout
/// A local ghost is `<localDirectory>/<id>/v<n>.json`, one file per
/// retraining, never overwritten (Jake, 2026-09-25: "All the data needs to be
/// saved"). The highest readable version is the ghost. Its person's decision
/// records sit beside it in `<id>/decisions/`.
///
/// ## Bundled versus local
/// Jake's ghost ships in the app (`*.ghost`, JSON inside, found by that
/// extension so no other bundled JSON can be mistaken for one). On Jake's own
/// phone the same ghost is also trained locally, and the local copy wins: it
/// has seen more of his games. An unreadable local file never hides the
/// bundled ghost.
public struct GhostStore: Sendable {
    /// A ghost joins the picker after this many of its person's games.
    static let minimumGamesToPlay = 10

    public static let shared = GhostStore(
        localDirectory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ghosts"),
        bundledGhosts: Bundle.main.urls(forResourcesWithExtension: "ghost", subdirectory: nil) ?? []
    )

    let localDirectory: URL
    let bundledGhosts: [URL]

    /// Local wins over bundled for the same id. Sorted by name, then id, so
    /// the picker's order never depends on file-system order. An id that was
    /// moved (`move`) is its old history, not a second ghost: on Jake's phone
    /// the bundled `jake` is the ghost now filed under his player id.
    func all() -> [GhostProfile] {
        var byID: [String: GhostProfile] = [:]
        for ghost in bundledGhosts.compactMap(Self.read) { byID[ghost.id] = ghost }
        for id in localIDs() {
            if let ghost = latest(of: id) { byID[id] = ghost }
        }
        let moved = aliases()
        return byID.values.filter { moved[$0.id] == nil && !$0.isRemoved }.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    /// The ghost behind `id`, following a rename (`alias`). A removed ghost
    /// (a tombstone) answers `nil`, so a save seating it refuses to resume
    /// through `missingGhostProblem` rather than seating a ghost that is gone.
    func ghost(id: String) -> GhostProfile? {
        ghost(id: id, includingRemoved: false)
    }

    func ghost(id: String, includingRemoved: Bool) -> GhostProfile? {
        let id = resolve(id)
        let found = latest(of: id) ?? bundledGhosts.compactMap(Self.read).first { $0.id == id }
        return includingRemoved || found?.isRemoved != true ? found : nil
    }

    // MARK: - Renames

    /// The id a person's ghost is stored under.
    ///
    /// A ghost keeps the id it was first trained under for good: Jake renamed
    /// himself "Bein" (2026-09-28) and his next game would otherwise have
    /// started a blank ghost `bein`, leaving the one that learned 25 of his
    /// games behind as "Jake's Ghost". The rename records `bein -> jake`.
    func resolve(_ id: String) -> String {
        var current = id
        var seen: Set<String> = []
        while let next = aliases()[current], seen.insert(current).inserted { current = next }
        return current
    }

    /// Points `slug` at the ghost stored as `id`. The owner uses this for
    /// continued training; observers use the same claim-derived mapping to
    /// connect the ghost's stable id with its person's renamed statistics.
    func alias(_ slug: String, to id: String) throws {
        guard slug != id else { return }
        var map = aliases()
        map[slug] = id
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(map).write(to: aliasFile, options: .atomic)
    }

    /// Re-files the ghost stored as `old` under `new`, the player id it
    /// belongs to (`PlayerDirectory`). Its latest model and its decision
    /// records (the "already learned" markers) move; its earlier versions stay
    /// under `old` as history, and `old` resolves to `new` from then on.
    func move(_ old: String, to new: String) throws {
        guard let ghost = ghost(id: old) else { return }
        let from = decisionsDirectory(for: old)
        try save(GhostProfile(id: new, name: ghost.name, person: ghost.person, lambda: ghost.lambda,
                              gamesLearned: ghost.gamesLearned, decisionsLearned: ghost.decisionsLearned,
                              civilization: ghost.civilization, revision: ghost.revision,
                              isNameCustom: ghost.isNameCustom, isTrainingPaused: ghost.isTrainingPaused))
        if FileManager.default.fileExists(atPath: from.path) {
            let to = localDirectory.appendingPathComponent(new).appendingPathComponent("decisions")
            try? FileManager.default.removeItem(at: to)
            try FileManager.default.moveItem(at: from, to: to)
        }
        try alias(old, to: new)
    }

    /// Whether any ghost, trained here or bundled, is stored as `id`.
    func isLocal(_ id: String) -> Bool {
        latest(of: id) != nil || bundledGhosts.compactMap(Self.read).contains { $0.id == id }
    }

    private var aliasFile: URL { localDirectory.appendingPathComponent("aliases.json") }

    func aliases() -> [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: aliasFile))) ?? [:]
    }

    func pickable() -> [GhostProfile] {
        let hidden = hiddenIDs()
        return all().filter { $0.gamesLearned >= Self.minimumGamesToPlay && !hidden.contains($0.id) }
    }

    /// Writes the next version; earlier versions stay.
    func save(_ ghost: GhostProfile) throws {
        let dir = localDirectory.appendingPathComponent(ghost.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let next = (versions(of: ghost.id).map(\.number).max() ?? 0) + 1
        try JSONEncoder().encode(ghost).write(to: dir.appendingPathComponent("v\(next).json"), options: .atomic)
    }

    func versions(of id: String) -> [(number: Int, url: URL)] {
        let dir = localDirectory.appendingPathComponent(id)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "json", name.hasPrefix("v"), let number = Int(name.dropFirst()) else { return nil }
            return (number, url)
        }.sorted { $0.number < $1.number }
    }

    func decisionsDirectory(for id: String) -> URL {
        localDirectory.appendingPathComponent(resolve(id)).appendingPathComponent("decisions")
    }

    // MARK: - Management (Jake, 2026-10-08)
    //
    // Every owner edit is a new version with `revision + 1`, which is what
    // carries it to other phones (`LiveSync.accepts`). Nothing is deleted:
    // replaced versions move to `archiveDirectory`.

    enum ManagementError: Error, Equatable { case emptyName, noSuchGhost }

    var archiveDirectory: URL {
        localDirectory.deletingLastPathComponent().appendingPathComponent("GhostArchive")
    }

    func rename(_ id: String, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ManagementError.emptyName }
        try update(id) {
            $0.name = trimmed
            $0.isNameCustom = true
        }
    }

    /// Resuming training also brings a removed ghost back, as a fresh one.
    func setTrainingPaused(_ id: String, _ paused: Bool) throws {
        try update(id) {
            $0.isTrainingPaused = paused
            if !paused { $0.isRemoved = false }
        }
    }

    func setRemoved(_ id: String) throws {
        try update(id) {
            $0.isRemoved = true
            $0.isTrainingPaused = true
        }
    }

    /// Fresh start. The decision records stay under `id`: they are the
    /// "already taught" markers, so launch catch-up never re-teaches a game
    /// from before the reset.
    @discardableResult
    func reset(_ id: String, keepingOld: Bool) throws -> GhostProfile {
        let id = resolve(id)
        guard let current = ghost(id: id, includingRemoved: true) else { throw ManagementError.noSuchGhost }
        if keepingOld {
            let number = (localIDs().filter { $0.hasPrefix("\(id)~") }.compactMap { Int($0.split(separator: "~").last ?? "") }.max() ?? 0) + 1
            try save(GhostProfile(id: "\(id)~\(number)", name: "\(current.name) (old \(number))", person: current.person,
                                  lambda: current.lambda, gamesLearned: current.gamesLearned,
                                  decisionsLearned: current.decisionsLearned, civilization: current.civilization,
                                  isNameCustom: true, isTrainingPaused: true))
        }
        try archiveVersions(of: id)
        let fresh = GhostProfile(id: id, name: current.name, person: .anchored(at: .forMode(.classic)),
                                 lambda: current.lambda, gamesLearned: 0, civilization: current.civilization,
                                 revision: current.revision + 1, isNameCustom: current.isNameCustom,
                                 isTrainingPaused: current.isTrainingPaused)
        try save(fresh)
        return fresh
    }

    /// Earlier generations of `id`, kept by `reset`. They never sync.
    func oldGhosts(of id: String) -> [GhostProfile] {
        let id = resolve(id)
        return localIDs().filter { $0.hasPrefix("\(id)~") }.compactMap { ghost(id: $0) }
    }

    func removeOld(_ oldID: String) throws {
        guard oldID.contains("~"), latest(of: oldID) != nil else { throw ManagementError.noSuchGhost }
        try archiveVersions(of: oldID)
        try FileManager.default.removeItem(at: localDirectory.appendingPathComponent(oldID))
    }

    private var hiddenFile: URL { localDirectory.appendingPathComponent("hidden.json") }

    /// Other players' ghosts this phone keeps out of the picker.
    func hiddenIDs() -> Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(contentsOf: hiddenFile))) ?? [])
    }

    func setHidden(_ id: String, _ hidden: Bool) throws {
        var ids = hiddenIDs()
        if hidden { ids.insert(id) } else { ids.remove(id) }
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(ids.sorted()).write(to: hiddenFile, options: .atomic)
    }

    private func update(_ id: String, _ change: (inout GhostProfile) -> Void) throws {
        guard var ghost = ghost(id: id, includingRemoved: true) else { throw ManagementError.noSuchGhost }
        change(&ghost)
        ghost.revision += 1
        try save(ghost)
    }

    /// Moves `v*.json` to `archiveDirectory/<id>-<timestamp>/`. Decision
    /// records stay where they are.
    private func archiveVersions(of id: String) throws {
        let versions = versions(of: id)
        guard !versions.isEmpty else { return }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let target = archiveDirectory.appendingPathComponent("\(id)-\(stamp)")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for version in versions {
            try FileManager.default.moveItem(at: version.url, to: target.appendingPathComponent(version.url.lastPathComponent))
        }
    }

    private func latest(of id: String) -> GhostProfile? {
        versions(of: id).reversed().lazy.compactMap { Self.read($0.url) }.first
    }

    private func localIDs() -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: localDirectory, includingPropertiesForKeys: nil)) ?? []
        return entries.filter(\.hasDirectoryPath).map(\.lastPathComponent).sorted()
    }

    private static func read(_ url: URL) -> GhostProfile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GhostProfile.self, from: data)
    }
}
