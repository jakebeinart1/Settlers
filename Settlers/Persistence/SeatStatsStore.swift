import CatanAI
import Foundation

/// Every rated game's per-seat stats, one file per match, never deleted
/// (Jake, 2026-09-25: "All the data needs to be saved").
struct SeatStatsRecord: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        /// `RatedEntity.key`: "person:Jake", "ghost:jake", "classic", "expert".
        let entity: String
        let stats: SeatStats
    }

    let match: UUID
    let date: Date
    let seats: [Entry]
}

public struct SeatStatsStore: Sendable {
    public static let shared = SeatStatsStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SeatStats"))

    let directory: URL

    /// Idempotent by match: a resumed game that re-reports its completion
    /// writes nothing new.
    func record(_ record: SeatStatsRecord) throws {
        let file = directory.appendingPathComponent("\(record.match.uuidString).json")
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: file, options: .atomic)
    }

    /// Oldest first; an unreadable file is skipped, never deleted.
    func all() -> [SeatStatsRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(SeatStatsRecord.self, from: Data(contentsOf: $0)) }
            .sorted { ($0.date, $0.match.uuidString) < ($1.date, $1.match.uuidString) }
    }
}
