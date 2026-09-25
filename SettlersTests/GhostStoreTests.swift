import CatanAI
import Foundation
import Testing
@testable import Settlers

@Suite struct GhostStoreTests {

    private func ghost(_ id: String, name: String, games: Int) -> GhostProfile {
        GhostProfile(id: id, name: name, person: .anchored(at: .forMode(.classic)), lambda: 0.5, gamesLearned: games)
    }

    private func fixture() throws -> (store: GhostStore, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GhostStoreTests.\(UUID().uuidString)")
        let bundled = root.appendingPathComponent("bundle")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        let file = bundled.appendingPathComponent("jake.ghost")
        try JSONEncoder().encode(ghost("jake", name: "Jake's Ghost", games: 24)).write(to: file)
        return (GhostStore(localDirectory: root.appendingPathComponent("local"), bundledGhosts: [file]), root)
    }

    @Test func aBundledGhostIsAvailable() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(store.all().map(\.id) == ["jake"])
        #expect(store.ghost(id: "jake")?.gamesLearned == 24)
    }

    /// Jake's own phone retrains his ghost; the fresher local copy wins.
    @Test func aLocalGhostWinsOverTheBundledOne() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(ghost("jake", name: "Jake's Ghost", games: 25))
        #expect(store.ghost(id: "jake")?.gamesLearned == 25)
        #expect(store.all().count == 1)
    }

    /// "All the data needs to be saved": every version stays on disk.
    @Test func savingKeepsEveryVersion() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(ghost("sam", name: "Sam's Ghost", games: 1))
        try store.save(ghost("sam", name: "Sam's Ghost", games: 2))
        #expect(store.versions(of: "sam").count == 2)
        #expect(store.ghost(id: "sam")?.gamesLearned == 2)
    }

    @Test func anUnreadableLocalFileFallsBackToTheBundledGhost() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("local/jake")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("v1.json"))
        #expect(store.ghost(id: "jake")?.gamesLearned == 24)
    }

    /// Spec default: a ghost appears in the picker at 10 learned games.
    @Test func onlyGhostsWithTenGamesArePickable() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(ghost("sam", name: "Sam's Ghost", games: 9))
        #expect(store.pickable().map(\.id) == ["jake"])
        try store.save(ghost("sam", name: "Sam's Ghost", games: 10))
        #expect(store.pickable().map(\.id) == ["jake", "sam"])
    }
}
