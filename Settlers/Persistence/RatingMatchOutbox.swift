import Foundation

/// Replay evidence waiting for CloudKit, independent of UI archive exports.
/// Keeping full matches here makes a completed offline game shareable even
/// if its derived recording fails to export or an archive policy later changes.
enum RatingMatchOutboxError: Error, Equatable {
    case identityMismatch

    static func isRejectedEvidence(_ error: any Error) -> Bool {
        error is DecodingError || error is Self || error is SharedMatch.Rejection
    }
}

extension SeatStatsStore {
    var pendingUploadsDirectory: URL { directory.appendingPathComponent("PendingUploads") }

    @discardableResult
    func queueForUpload(_ match: SharedMatch) throws -> SharedMatch {
        guard !match.containsArchivedGhost else { return match }
        let file = pendingFile(for: match)
        if FileManager.default.fileExists(atPath: file.path) {
            // A malformed item is evidence to retain, never permission to
            // overwrite a game whose upload status is not known.
            return try queuedMatch(at: file)
        }
        try writePending(match, at: file)
        return match
    }

    /// Validate before queuing. A checkpoint can repair the same replay
    /// previously queued without its move versions. Keep the old bytes.
    func queueVerifiedMatch(
        _ match: SharedMatch, resolveOwner: (String) -> String, verify: (SharedMatch) throws -> SeatStatsRecord
    ) throws -> SeatStatsRecord {
        let verified = try verify(match)
        guard !match.containsArchivedGhost else { return verified }
        let file = pendingFile(for: match)
        if FileManager.default.fileExists(atPath: file.path) {
            if let held = try verifiedPendingRecord(at: file, for: match, resolveOwner: resolveOwner, verify: verify) {
                return held
            }
            try preserveRejectedCopy(of: file)
        }
        try writePending(match, at: file)
        return verified
    }

    private func verifiedPendingRecord(
        at file: URL, for match: SharedMatch, resolveOwner: (String) -> String,
        verify: (SharedMatch) throws -> SeatStatsRecord
    ) throws -> SeatStatsRecord? {
        let held: SharedMatch
        do {
            held = try queuedMatch(at: file)
        } catch where error is DecodingError || error is RatingMatchOutboxError {
            return nil
        }
        do {
            return try verify(held)
        } catch SharedMatch.Rejection.replayFailed where held.isUnversionedCopy(of: match, resolveOwner: resolveOwner) {
            return nil
        }
    }

    private func pendingFile(for match: SharedMatch) -> URL {
        pendingUploadsDirectory.appendingPathComponent("\(match.match.uuidString).json")
    }

    private func writePending(_ match: SharedMatch, at file: URL) throws {
        try FileManager.default.createDirectory(at: pendingUploadsDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(match).write(to: file, options: .atomic)
    }

    private func preserveRejectedCopy(of file: URL) throws {
        let rejected = directory.appendingPathComponent("RejectedUploads")
        let copy = rejected.appendingPathComponent("\(file.deletingPathExtension().lastPathComponent)-\(UUID()).json")
        try FileManager.default.createDirectory(at: rejected, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: file, to: copy)
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

private extension SharedMatch {
    func isUnversionedCopy(of recorded: SharedMatch, resolveOwner: (String) -> String) -> Bool {
        func canonicalSeat(_ key: String) -> String {
            guard case .person(let id) = RatedEntity(key: key) else { return key }
            return RatedEntity.person(resolveOwner(id)).key
        }
        return initialState == recorded.initialState && seats.map(canonicalSeat) == recorded.seats.map(canonicalSeat)
            && ratingPool == recorded.ratingPool && abandoned == recorded.abandoned && moves.count == recorded.moves.count
            && zip(moves, recorded.moves).allSatisfy { old, fresh in
                old.rulesVersion == nil && fresh.rulesVersion != nil
                    && old.player == fresh.player && old.move == fresh.move
            }
    }
}
