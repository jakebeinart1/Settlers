import Foundation

/// Replay evidence waiting for CloudKit, independent of UI archive exports.
/// Keeping full matches here makes a completed offline game shareable even
/// if its derived recording fails to export or an archive policy later changes.
enum RatingMatchOutboxError: Error, Equatable {
    case identityMismatch
}

extension SeatStatsStore {
    var pendingUploadsDirectory: URL { directory.appendingPathComponent("PendingUploads") }

    @discardableResult
    func queueForUpload(_ match: SharedMatch) throws -> SharedMatch {
        guard !match.containsArchivedGhost else { return match }
        let file = pendingUploadsDirectory.appendingPathComponent("\(match.match.uuidString).json")
        if FileManager.default.fileExists(atPath: file.path) {
            // A malformed item is evidence to retain, never permission to
            // overwrite a game whose upload status is not known.
            return try queuedMatch(at: file)
        }
        try FileManager.default.createDirectory(at: pendingUploadsDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(match).write(to: file, options: .atomic)
        return match
    }

    /// A decodable payload under another match's filename is still corrupt.
    /// Reject it before acknowledging any checkpoint or deleting evidence.
    func queuedMatch(at file: URL) throws -> SharedMatch {
        let match = try JSONDecoder().decode(SharedMatch.self, from: Data(contentsOf: file))
        guard UUID(uuidString: file.deletingPathExtension().lastPathComponent) == match.match else {
            throw RatingMatchOutboxError.identityMismatch
        }
        return match
    }

    func pendingUploadFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: pendingUploadsDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: pendingUploadsDirectory,
                                                          includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
