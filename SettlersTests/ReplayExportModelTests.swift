import AVFoundation
import Foundation
import Testing
@testable import Settlers

/// Exercise the sheet's actual lifetime owner, not a mocked export task.
/// Every test owns its archive and movie directories; no shared exports are
/// scanned or removed. Waiting yields the UI actor and has a finite deadline.
@MainActor
@Suite(.serialized)
struct ReplayExportModelTests {
    @Test func closingDuringActualEncodingCleansUpBeforeAllowingRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (summary, store) = try Self.recording(in: root)
        let original = try Data(contentsOf: summary.fileURL)
        let output = root.appendingPathComponent("movies")
        let model = ReplayExportModel(summary: summary, store: store, directory: output)
        defer { model.close() }
        model.start(includeNames: false)
        try await Self.waitUntil {
            guard let progress = model.progress else { return !model.isBusy }
            if case .rendering = progress { return true }
            return false
        }
        let progress = try #require(model.progress, "Encoding finished or failed before its lifetime could be exercised")
        guard case .rendering = progress else {
            Issue.record("The model did not reach the real writer: \(model.errorMessage ?? "no error")")
            return
        }

        model.close()
        #expect(model.isCancelling)
        model.start(includeNames: true) // Must not replace the still-cleaning task.
        try await Self.waitUntil { !model.isBusy }
        #expect(model.result == nil, "Closing must never publish a shareable movie")
        #expect(model.progress == nil && !model.isCancelling)
        #expect(model.errorMessage?.contains("cancelled") == true)
        let exportRoot = output.appendingPathComponent(ReplayVideoExporter.temporaryFolderName)
        #expect(try FileManager.default.contentsOfDirectory(atPath: exportRoot.path).isEmpty)
        #expect(try Data(contentsOf: summary.fileURL) == original)

        model.start(includeNames: false)
        try await Self.waitUntil { !model.isBusy }
        let retry = try #require(model.result, "Retry failed: \(model.errorMessage ?? "no error")")
        #expect(try await AVURLAsset(url: retry.url).load(.isPlayable))
        model.close()
        #expect(model.result == nil)
        #expect(!FileManager.default.fileExists(atPath: retry.url.path))
    }

    @Test func closingWhilePreparingDoesNotCreateAnOutputOrDeleteTheRecording() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (summary, store) = try Self.recording(in: root)
        let output = root.appendingPathComponent("movies")
        let model = ReplayExportModel(summary: summary, store: store, directory: output)
        defer { model.close() }
        model.start(includeNames: false)
        #expect(model.progress == .preparing)
        model.close()
        try await Self.waitUntil { !model.isBusy }

        #expect(model.result == nil)
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(FileManager.default.fileExists(atPath: summary.fileURL.path))
    }

    private static func recording(in root: URL) throws -> (GameLogSummary, GameLogStore) {
        let detail = try ReplayExportFixtures.recording(moves: 40)
        let store = GameLogStore(directoryURL: root.appendingPathComponent("recordings"), maxKeptLogs: 1)
        let id = try store.startNewGame(initialState: detail.initialState, roster: detail.roster)
        for entry in detail.events { try store.appendMove(gameID: id, player: entry.player, move: entry.move) }
        let summary = try store.summary(for: id)
        return (try #require(summary), store)
    }

    private static func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(predicate(), "Replay export did not reach the expected lifecycle state within 60 seconds")
    }
}
