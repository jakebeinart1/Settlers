import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

/// One serialized writer owns its pool, samples, and cancellation. The pool
/// has a hard allocation ceiling; the producer awaits each position before
/// rendering another, so long games cannot accumulate images or buffers.
actor ReplayMovieWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let configuration: ReplayVideoConfiguration
    private var frameIndex: Int64 = 0
    private static let maximumBuffers = 3
    private static let readinessTimeout: Duration = .seconds(30)
    private static let readinessPoll: Duration = .milliseconds(10)

    init(url: URL, configuration: ReplayVideoConfiguration) throws {
        guard configuration.width > 0, configuration.height > 0,
              configuration.width.isMultiple(of: 2), configuration.height.isMultiple(of: 2),
              configuration.framesPerSecond > 0, configuration.bitRate > 0 else {
            throw ReplayVideoExportError.invalidConfiguration
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: configuration.bitRate]
        ]
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw ReplayVideoExportError.unsupportedEncoding
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                         sourcePixelBufferAttributes: Self.attributes(configuration))
        guard writer.canAdd(input) else { throw ReplayVideoExportError.unsupportedEncoding }
        writer.add(input)
        guard writer.startWriting() else {
            throw ReplayVideoExportError.writerFailed(writer.error?.localizedDescription ?? "Encoding could not start.")
        }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        self.configuration = configuration
    }

    func append(_ image: CGImage, repeating count: Int) async throws {
        guard image.width == configuration.width, image.height == configuration.height, count > 0 else {
            throw ReplayVideoExportError.invalidConfiguration
        }
        let buffer = try await makeBuffer()
        try Self.draw(image, into: buffer)
        for _ in 0..<count {
            try await waitUntilReady()
            let time = CMTime(value: frameIndex, timescale: configuration.framesPerSecond)
            guard adaptor.append(buffer, withPresentationTime: time) else { throw failure() }
            frameIndex += 1
        }
    }

    func finish() async throws -> TimeInterval {
        try Task.checkCancellation()
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: frameIndex, timescale: configuration.framesPerSecond))
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        try Task.checkCancellation()
        guard writer.status == .completed else { throw failure() }
        return Double(frameIndex) / Double(configuration.framesPerSecond)
    }

    /// Called only after the producer has stopped appending. cancelWriting
    /// can block, so it belongs on this actor rather than on the UI actor.
    func cancel() { writer.cancelWriting() }

    private func waitUntilReady() async throws {
        let deadline = ContinuousClock.now + Self.readinessTimeout
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            guard writer.status == .writing else { throw failure() }
            guard ContinuousClock.now < deadline else { throw ReplayVideoExportError.writerTimedOut }
            try await Task.sleep(for: Self.readinessPoll)
        }
        try Task.checkCancellation()
    }

    private func makeBuffer() async throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else { throw ReplayVideoExportError.bufferAllocationFailed }
        let deadline = ContinuousClock.now + Self.readinessTimeout
        while true {
            try Task.checkCancellation()
            var buffer: CVPixelBuffer?
            let attributes = [kCVPixelBufferPoolAllocationThresholdKey as String: Self.maximumBuffers] as CFDictionary
            let result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, attributes, &buffer)
            if result == kCVReturnSuccess, let buffer { return buffer }
            guard result == kCVReturnWouldExceedAllocationThreshold else {
                throw ReplayVideoExportError.bufferAllocationFailed
            }
            guard writer.status == .writing else { throw failure() }
            guard ContinuousClock.now < deadline else { throw ReplayVideoExportError.writerTimedOut }
            try await Task.sleep(for: Self.readinessPoll)
        }
    }

    private func failure() -> ReplayVideoExportError {
        .writerFailed(writer.error?.localizedDescription ?? "Encoding was interrupted.")
    }

    private static func attributes(_ configuration: ReplayVideoConfiguration) -> [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferWidthKey as String: configuration.width,
         kCVPixelBufferHeightKey as String: configuration.height,
         kCVPixelBufferCGImageCompatibilityKey as String: true,
         kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
    }

    private static func draw(_ image: CGImage, into buffer: CVPixelBuffer) throws {
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else {
            throw ReplayVideoExportError.bufferAllocationFailed
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let address = CVPixelBufferGetBaseAddress(buffer),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: address, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: colorSpace, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                                        | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            throw ReplayVideoExportError.bufferAllocationFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
    }
}
