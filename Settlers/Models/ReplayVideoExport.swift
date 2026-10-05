import Foundation

/// Fixed output timing makes encoding independent of playback speed and wall
/// clock time. Only compressed samples, never a movie's raster frames, persist.
struct ReplayVideoConfiguration: Sendable {
    var width = 720
    var height = 1280
    var framesPerSecond: Int32 = 30
    var framesPerMove = 20
    var openingFrames = 60
    var closingFrames = 90
    var bitRate = 2_000_000
    static let standard = ReplayVideoConfiguration()
}

enum ReplayExportProgress: Sendable, Equatable {
    case preparing
    case rendering(completed: Int, total: Int)
    case finalizing

    var fraction: Double? {
        guard case .rendering(let completed, let total) = self else { return nil }
        return Double(completed) / Double(max(1, total))
    }

    var label: String {
        switch self {
        case .preparing: return "Checking the recording…"
        case .rendering(let completed, let total): return "Creating video · \(completed) of \(total) positions"
        case .finalizing: return "Finishing the MP4…"
        }
    }
}

struct ReplayVideoResult: Sendable, Equatable {
    let url: URL
    let isPartial: Bool
    let notice: String
    let duration: TimeInterval
}

enum ReplayVideoExportError: Error, LocalizedError {
    case invalidRecording
    case invalidConfiguration
    case renderingFailed
    case bufferAllocationFailed
    case unsupportedEncoding
    case writerFailed(String)
    case writerTimedOut

    var errorDescription: String? {
        switch self {
        case .invalidRecording: return "This recording does not contain a supported three- or four-player table."
        case .invalidConfiguration: return "The video output settings are invalid."
        case .renderingFailed: return "The replay board could not be rendered into a video frame."
        case .bufferAllocationFailed: return "There was not enough memory to create the video."
        case .unsupportedEncoding: return "This device could not create an H.264 MP4."
        case .writerFailed(let message): return "The video could not be saved. \(message)"
        case .writerTimedOut: return "Video encoding stopped responding. Please try again."
        }
    }
}
