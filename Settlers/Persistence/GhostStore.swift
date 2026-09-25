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
struct GhostStore: Sendable {
    /// A ghost joins the picker after this many of its person's games.
    static let minimumGamesToPlay = 10

    static let shared = GhostStore(
        localDirectory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ghosts"),
        bundledGhosts: Bundle.main.urls(forResourcesWithExtension: "ghost", subdirectory: nil) ?? []
    )

    let localDirectory: URL
    let bundledGhosts: [URL]

    /// Local wins over bundled for the same id. Sorted by name, then id, so
    /// the picker's order never depends on file-system order.
    func all() -> [GhostProfile] {
        var byID: [String: GhostProfile] = [:]
        for ghost in bundledGhosts.compactMap(Self.read) { byID[ghost.id] = ghost }
        for id in localIDs() {
            if let ghost = latest(of: id) { byID[id] = ghost }
        }
        return byID.values.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    func ghost(id: String) -> GhostProfile? {
        latest(of: id) ?? bundledGhosts.compactMap(Self.read).first { $0.id == id }
    }

    func pickable() -> [GhostProfile] {
        all().filter { $0.gamesLearned >= Self.minimumGamesToPlay }
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
        localDirectory.appendingPathComponent(id).appendingPathComponent("decisions")
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
