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

    // MARK: - Management (Jake, 2026-10-08)

    @Test func renameIsCustomBumpsRevisionAndRefusesBlank() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(ghost("sam", name: "Sam's Ghost", games: 12))
        try store.rename("sam", to: "  The Wall  ")
        let renamed = try #require(store.ghost(id: "sam"))
        #expect(renamed.name == "The Wall" && renamed.isNameCustom && renamed.revision == 13)
        #expect(throws: GhostStore.ManagementError.emptyName) { try store.rename("sam", to: "   ") }
        #expect(store.ghost(id: "sam")?.name == "The Wall")
    }

    @Test func resetKeepsTheOldGhostAndStartsFresh() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(ghost("sam", name: "Sam's Ghost", games: 12))
        let fresh = try store.reset("sam", keepingOld: true)
        #expect(fresh.gamesLearned == 0 && fresh.decisionsLearned == 0 && fresh.revision == 13)
        #expect(store.ghost(id: "sam")?.gamesLearned == 0)
        let old = store.oldGhosts(of: "sam")
        #expect(old.map(\.id) == ["sam~1"] && old.first?.gamesLearned == 12)
        #expect(!store.pickable().contains { $0.id == "sam" }, "a fresh ghost leaves the picker until 10 games")
        #expect(store.pickable().contains { $0.id == "sam~1" }, "an old ghost can still be played")
    }

    @Test func removingLeavesATombstoneThatResumeTreatsAsGone() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(ghost("sam", name: "Sam's Ghost", games: 12))
        _ = try store.reset("sam", keepingOld: false)
        try store.setRemoved("sam")
        #expect(store.ghost(id: "sam") == nil)
        #expect(store.ghost(id: "sam", includingRemoved: true)?.isRemoved == true)
        #expect(store.oldGhosts(of: "sam").isEmpty)
        #expect(!store.all().contains { $0.id == "sam" })
    }

    @Test func removingAnOldGhostArchivesItsVersions() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(ghost("sam", name: "Sam's Ghost", games: 12))
        _ = try store.reset("sam", keepingOld: true)
        try store.removeOld("sam~1")
        #expect(store.oldGhosts(of: "sam").isEmpty)
        let archived = try FileManager.default.contentsOfDirectory(atPath: store.archiveDirectory.path)
        #expect(archived.contains { $0.hasPrefix("sam~1-") }, "removed data is archived, never deleted")
    }

    @Test func hiddenGhostsLeaveOnlyThePicker() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(ghost("sam", name: "Sam's Ghost", games: 12))
        try store.setHidden("sam", true)
        #expect(!store.pickable().contains { $0.id == "sam" })
        #expect(store.all().contains { $0.id == "sam" })
        try store.setHidden("sam", false)
        #expect(store.pickable().contains { $0.id == "sam" })
    }

    @Test func pauseBumpsRevision() throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(ghost("sam", name: "Sam's Ghost", games: 12))
        try store.setTrainingPaused("sam", true)
        #expect(store.ghost(id: "sam")?.isTrainingPaused == true)
        #expect(store.ghost(id: "sam")?.revision == 13)
    }
}
