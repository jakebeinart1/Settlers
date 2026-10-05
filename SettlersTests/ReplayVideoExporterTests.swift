import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import Settlers

/// These tests cross the real rendering/encoding seam: SwiftUI's actual board
/// becomes an MP4, then AVFoundation decodes its first, middle, and last frames.
/// They intentionally do not treat a writer's success flag as visual proof.
@Suite struct ReplayVideoExporterTests {
    @Test func actualBoardExportsADecodableSilentMP4WithChangingPieces() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let detail = try ReplayExportFixtures.recording(moves: 4)
        let configuration = ReplayVideoConfiguration.standard

        let result = try await ReplayVideoExporter.export(detail: detail, directory: root) { _ in }

        #expect(result.url.pathExtension == "mp4")
        #expect(result.isPartial, "The short fixture did not actually finish a game")
        #expect(result.notice.contains("Current rules are used only for those moves"))
        #expect(result.notice.contains("Recorded rules versions are unavailable"))
        let asset = AVURLAsset(url: result.url)
        let duration = try await asset.load(.duration)
        let expectedFrames = configuration.openingFrames + detail.events.count * configuration.framesPerMove
            + configuration.closingFrames
        #expect(abs(duration.seconds - Double(expectedFrames) / Double(configuration.framesPerSecond)) < 0.04)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        #expect(tracks.count == 1)
        let track = try #require(tracks.first)
        let size = try await track.load(.naturalSize)
        #expect(size == CGSize(width: 720, height: 1280))
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        #expect(try await asset.load(.metadata).isEmpty, "No identities, archive payload, or timestamps belong in metadata")

        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let first = try await generator.image(at: .zero).image
        let middleTime = CMTime(value: Int64(configuration.openingFrames + configuration.framesPerMove),
                                timescale: configuration.framesPerSecond)
        let middle = try await generator.image(at: middleTime).image
        let lastTime = CMTime(value: Int64(expectedFrames - 1), timescale: configuration.framesPerSecond)
        let last = try await generator.image(at: lastTime).image
        #expect([first, middle, last].allSatisfy { $0.width == 720 && $0.height == 1280 })

        // Crop out the caption/score regions: text changing cannot make this
        // assertion pass while the actual board stays blank or frozen.
        let boardCrop = CGRect(x: 0, y: 160, width: 720, height: 700)
        #expect(try Self.pixels(first, crop: boardCrop) != Self.pixels(middle, crop: boardCrop))
        #expect(try Self.pixels(first, crop: boardCrop) != Self.pixels(last, crop: boardCrop))
        var sequence = try ReplayExportSequence(detail: detail)
        let frame = try #require(try sequence.next())
        let reference = try await ReplayVideoRenderer.image(for: frame, configuration: configuration)
        let expected = try Self.pixels(reference)
        let decoded = try Self.pixels(first)
        let difference = zip(expected, decoded).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        #expect(Double(difference) / Double(expected.count) < 20,
                "Decoded output differs from the renderer; check pixel orientation and color format")

        try ReplayVideoExporter.discard(result)
        #expect(!FileManager.default.fileExists(atPath: result.url.path))
    }

    @Test func cancellationRemovesThePartialMovieAndAllowsARetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let detail = try ReplayExportFixtures.recording(moves: 2)
        let cancelled = Task {
            try await ReplayVideoExporter.export(detail: detail, directory: root) { progress in
                if case .rendering(completed: 1, total: _) = progress {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        do {
            _ = try await cancelled.value
            Issue.record("Cancelled export returned a shareable movie")
        } catch is CancellationError {
            let exportRoot = root.appendingPathComponent(ReplayVideoExporter.temporaryFolderName)
            #expect(try FileManager.default.contentsOfDirectory(atPath: exportRoot.path).isEmpty)
        }

        let retry = try await ReplayVideoExporter.export(detail: detail, directory: root) { _ in }
        let asset = AVURLAsset(url: retry.url)
        #expect(try await asset.load(.isPlayable))
        try ReplayVideoExporter.discard(retry)
    }

    @Test func cleanupCannotDeleteADiagnosticArchive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathComponent("recording.jsonl")
        let bytes = Data("private diagnostic recording".utf8)
        try bytes.write(to: archive)
        let result = ReplayVideoResult(url: archive, isPartial: false, notice: "", duration: 0)

        #expect(throws: ReplayVideoExportError.self) { try ReplayVideoExporter.discard(result) }
        #expect(try Data(contentsOf: archive) == bytes)
    }

    /// Normalize both images to the same small RGBA bitmap. This keeps decoded
    /// comparison independent of the decoder's provider layout and color model.
    private static func pixels(_ image: CGImage, crop: CGRect? = nil) throws -> [UInt8] {
        let source: CGImage
        if let crop { source = try #require(image.cropping(to: crop)) } else { source = image }
        let width = 180
        let height = 320
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { storage in
            let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try #require(CGContext(data: storage.baseAddress, width: width, height: height,
                                                 bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                                                 bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                                                    | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        return bytes
    }
}
