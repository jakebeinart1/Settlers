import Foundation

/// Owns the complete local export. An immutable archive snapshot is replayed
/// off the UI actor; only rendering crosses to it. Each image is fully handed
/// to the writer before the next is created. There is no upload or live state.
enum ReplayVideoExporter {
    static let temporaryFolderName = "EmpiresReplayExports"

    static func export(detail: GameLogDetail, includeNames: Bool = false,
                       configuration: ReplayVideoConfiguration = .standard,
                       directory: URL = FileManager.default.temporaryDirectory,
                       progress: @escaping @MainActor @Sendable (ReplayExportProgress) -> Void) async throws -> ReplayVideoResult {
        guard configuration.framesPerMove > 0, configuration.openingFrames > 0, configuration.closingFrames > 0 else {
            throw ReplayVideoExportError.invalidConfiguration
        }
        await progress(.preparing)
        var sequence = try ReplayExportSequence(detail: detail, includeNames: includeNames)
        try Task.checkCancellation()
        let folder = directory.appendingPathComponent(temporaryFolderName, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(sequence.analysis.isPartial ? "Empires-partial-replay.mp4" : "Empires-replay.mp4")
        var writer: ReplayMovieWriter?
        do {
            let movie = try ReplayMovieWriter(url: url, configuration: configuration)
            writer = movie
            try await encode(sequence: &sequence, writer: movie, configuration: configuration, progress: progress)
            await progress(.finalizing)
            let duration = try await movie.finish()
            try Task.checkCancellation()
            return ReplayVideoResult(url: url, isPartial: sequence.analysis.isPartial,
                                     notice: sequence.analysis.notice, duration: duration)
        } catch {
            if let writer { await writer.cancel() }
            // Cleanup cannot replace the error which explains the failed export.
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private static func encode(sequence: inout ReplayExportSequence, writer: ReplayMovieWriter,
                               configuration: ReplayVideoConfiguration,
                               progress: @escaping @MainActor @Sendable (ReplayExportProgress) -> Void) async throws {
        let total = sequence.analysis.lastMove + 1
        var lastFrame: ReplayExportFrame?
        while let frame = try sequence.next() {
            try Task.checkCancellation()
            let image = try await ReplayVideoRenderer.image(for: frame, configuration: configuration)
            let repeats = frame.position == 0 ? configuration.openingFrames : configuration.framesPerMove
            try await writer.append(image, repeating: repeats)
            lastFrame = frame
            await progress(.rendering(completed: frame.position + 1, total: total))
            await Task.yield()
        }
        guard let lastFrame else { throw ReplayVideoExportError.invalidRecording }
        let ending = sequence.closingFrame(from: lastFrame)
        let image = try await ReplayVideoRenderer.image(for: ending, configuration: configuration)
        try await writer.append(image, repeating: configuration.closingFrames)
    }

    /// Remove only the UUID export directory created by this module. The raw
    /// GameLogs file is never moved, rewritten, or removed by video cleanup.
    static func discard(_ result: ReplayVideoResult) throws {
        let directory = result.url.deletingLastPathComponent()
        guard UUID(uuidString: directory.lastPathComponent) != nil,
              directory.deletingLastPathComponent().lastPathComponent == temporaryFolderName else {
            throw ReplayVideoExportError.invalidConfiguration
        }
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    /// Recover leftovers from process termination when the export sheet next
    /// opens. Use movie modification time so a writer still producing samples
    /// cannot be mistaken for an abandoned directory merely because it is old.
    static func discardExpired(directory: URL = FileManager.default.temporaryDirectory, now: Date = Date()) throws {
        let root = directory.appendingPathComponent(temporaryFolderName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let retention: TimeInterval = 24 * 60 * 60
        for folder in folders where UUID(uuidString: folder.lastPathComponent) != nil {
            let files = try FileManager.default.contentsOfDirectory(at: folder,
                                                                   includingPropertiesForKeys: [.contentModificationDateKey])
            let dates = try files.map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            let folderDate = try folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let latest = dates.compactMap { $0 }.max() ?? folderDate
            if let latest, now.timeIntervalSince(latest) > retention {
                try FileManager.default.removeItem(at: folder)
            }
        }
    }
}
