import CatanAI
import Foundation
import Testing
@testable import Settlers

/// A rename must preserve a remote ghost's detail page, not just its name
/// and Elo. One real game keeps the graph borrowed from its human while also
/// exercising the separate record against that same human.
@Suite(.serialized) struct LiveSyncRenameDetailTests {
    @MainActor
    @Test func anObserversGhostDetailKeepsItsOwnerGraphAndRecordAfterARename() async throws {
        // Literal external root: never use the app's real stores or workspace.
        let root = URL(fileURLWithPath: "/tmp/LiveSyncRenameDetailTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = LiveSyncTests.FakeCloud()
        let jake = LiveSyncTests.Device("jake", in: root)
        let alex = LiveSyncTests.Device("alex", in: root)
        try await seedJake(on: jake, cloud: cloud)
        try await sync(alex, cloud: cloud, user: "apple-alex", name: "Alex")
        let before = try ghostDetail(on: alex)
        try #require(before.record.played == 1 && before.radarIsLearnedFrom)
        try #require(before.radar != nil)
        try #require(before.selfPlay?.played == 1)
        let owner = EntityDetail.person("Jake", ratings: jake.stores.ratings.load(), stats: jake.stores.seatStats.all())
        #expect(before.radar == owner.radar, "the borrowed graph is Jake's actual play, not the ghost's")

        try await sync(jake, cloud: cloud, user: "apple-jake", name: "Bein")
        try await sync(alex, cloud: cloud, user: "apple-alex", name: "Alex")
        let after = try ghostDetail(on: alex)
        #expect(after.name == "Bein's Ghost")
        #expect(after.record == before.record, "renaming must not alter the ghost's played/won record")
        #expect(after.radarIsLearnedFrom)
        #expect(after.radar == before.radar, "the observer must still find the renamed owner's borrowed graph")
        #expect(after.radarCaption == before.radarCaption)
        #expect(after.selfPlay == before.selfPlay, "Against its own player must retain its played/won breakdown")
    }

    @MainActor
    private func seedJake(on device: LiveSyncTests.Device, cloud: LiveSyncTests.FakeCloud) async throws {
        try device.stores.ghosts.save(GhostProfile(
            id: "jake", name: "Jake's Ghost", person: .anchored(at: .forMode(.classic)), lambda: 0.01, gamesLearned: 12))
        try device.play(as: "Jake", against: "jake")
        try await sync(device, cloud: cloud, user: "apple-jake", name: "Jake")
        try #require(cloud.locked { $0.ghosts["jake"] != nil }, "the source ghost must reach the cloud")
    }

    private func sync(_ device: LiveSyncTests.Device, cloud: LiveSyncTests.FakeCloud,
                      user: String, name: String) async throws {
        let status = await device.sync(cloud, as: user, name: name)
        guard case .online = status else { throw status }
    }

    /// The same detail API and real resolver that LeaderboardView.open uses.
    private func ghostDetail(on device: LiveSyncTests.Device) throws -> EntityDetail {
        let ghost = try #require(device.stores.ghosts.ghost(id: "jake"))
        return EntityDetail.ghost(ghost, ratings: device.stores.ratings.load(), stats: device.stores.seatStats.all(),
                                  resolve: device.stores.ghosts.resolve)
    }
}
