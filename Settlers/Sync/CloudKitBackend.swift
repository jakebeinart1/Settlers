import CatanAI
import CloudKit
import Foundation

/// The shared database: CloudKit's public database in the container this
/// build names.
///
/// ## Record types (docs/live-sync.md has the console setup)
/// - `Player`, id `name-<slug>`: `name`. Who holds a name.
/// - `Match`, id = match UUID: `payload` (asset, `SharedMatch` JSON),
///   `date`, `version`, `seats`. The seats are duplicated outside the payload
///   only so a training job can query by them.
/// - `Ghost`, id `ghost-<id>`: `payload` (asset, `GhostProfile` JSON),
///   `gamesLearned`.
///
/// Payloads are assets rather than fields because a game log (20-50 KB)
/// crowds CloudKit's 1 MB per-record limit once a long game's moves are in it.
final class CloudKitBackend: CloudBackend, @unchecked Sendable {
    /// The Info.plist key the container id arrives under. Empty in every
    /// build that has not been given one (`Settlers/Signing.xcconfig`), which
    /// is what keeps sync off for Jake's builds, the simulator and every test.
    static let containerInfoKey = "EmpiresCloudKitContainer"

    private let container: CKContainer
    private var database: CKDatabase { container.publicCloudDatabase }

    init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
    }

    /// The backend this build is configured for, or `nil`.
    ///
    /// `CKContainer(identifier:)` traps when the app lacks the iCloud
    /// entitlement for it, so this must never construct one on a guess.
    static func configured(bundle: Bundle = .main) -> CloudKitBackend? {
        guard let id = bundle.object(forInfoDictionaryKey: containerInfoKey) as? String,
              !id.isEmpty, !id.hasPrefix("$(") else { return nil }
        return CloudKitBackend(containerIdentifier: id)
    }

    func currentUser() async throws -> String {
        try await mapped {
            guard try await container.accountStatus() == .available else { throw CloudSyncError.noAccount }
            return try await container.userRecordID().recordName
        }
    }

    func claim(slug: String, name: String) async throws -> NameClaim {
        try await mapped {
            let id = CKRecord.ID(recordName: "name-\(slug)")
            if let existing = try await record(id) { return try await claim(from: existing) }
            let record = CKRecord(recordType: "Player", recordID: id)
            record["name"] = name
            do {
                return try await claim(from: database.save(record))
            } catch let error as CKError where error.code == .serverRecordChanged {
                // Someone claimed it between the read and the write.
                guard let existing = try await self.record(id) else { throw error }
                return try await claim(from: existing)
            }
        }
    }

    func claims(slugs: [String]) async throws -> [String: NameClaim] {
        guard !slugs.isEmpty else { return [:] }
        return try await mapped {
            let results = try await database.records(for: slugs.map { CKRecord.ID(recordName: "name-\($0)") })
            var claims: [String: NameClaim] = [:]
            for (id, result) in results {
                guard case .success(let record) = result else { continue }
                claims[String(id.recordName.dropFirst("name-".count))] = try await claim(from: record)
            }
            return claims
        }
    }

    func upload(_ match: SharedMatch) async throws {
        try await mapped {
            let record = CKRecord(recordType: "Match", recordID: CKRecord.ID(recordName: match.match.uuidString))
            record["date"] = match.date
            record["version"] = match.version
            record["seats"] = match.seats
            let file = try Self.temporaryFile(JSONEncoder().encode(match))
            defer { try? FileManager.default.removeItem(at: file) }
            record["payload"] = CKAsset(fileURL: file)
            do {
                _ = try await database.save(record)
            } catch let error as CKError where error.code == .serverRecordChanged {
                // Already uploaded: an earlier sync saved it and was cut off
                // before it could note that.
            }
        }
    }

    func matches(modifiedAfter date: Date?) async throws -> [Downloaded<SharedMatch>] {
        try await mapped { try await query("Match", modifiedAfter: date) }
    }

    func upload(_ ghost: GhostProfile) async throws {
        try await mapped {
            let id = CKRecord.ID(recordName: "ghost-\(ghost.id)")
            let record = try await self.record(id) ?? CKRecord(recordType: "Ghost", recordID: id)
            record["gamesLearned"] = ghost.gamesLearned
            let file = try Self.temporaryFile(JSONEncoder().encode(ghost))
            defer { try? FileManager.default.removeItem(at: file) }
            record["payload"] = CKAsset(fileURL: file)
            _ = try await database.save(record)
        }
    }

    func ghosts() async throws -> [Downloaded<GhostProfile>] {
        // ponytail: every ghost on every sync; one record per player, so this
        // stays small until the ladder has thousands of people.
        try await mapped { try await query("Ghost", modifiedAfter: nil) }
    }

    // MARK: - Helpers

    private func record(_ id: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func claim(from record: CKRecord) async throws -> NameClaim {
        guard let name = record["name"] as? String else { throw CloudSyncError.failed("A name record has no name.") }
        return NameClaim(name: name, owner: try await owner(of: record))
    }

    /// A record this user created reports its creator as
    /// `CKCurrentUserDefaultName`, not the user's id; translate it, or the
    /// user's own records would look like someone else's.
    private func owner(of record: CKRecord) async throws -> String {
        let creator = record.creatorUserRecordID?.recordName ?? ""
        return creator == CKCurrentUserDefaultName ? try await container.userRecordID().recordName : creator
    }

    /// Every record of `type` changed after `date`. A record whose payload
    /// cannot be read (a newer app's format) is skipped, never fatal.
    private func query<Value: Decodable & Sendable>(_ type: String, modifiedAfter date: Date?) async throws -> [Downloaded<Value>] {
        let predicate = NSPredicate(format: "modificationDate > %@", (date ?? .distantPast) as NSDate)
        var (results, cursor) = try await database.records(matching: CKQuery(recordType: type, predicate: predicate),
                                                           resultsLimit: CKQueryOperation.maximumResults)
        var records = results.compactMap { try? $0.1.get() }
        while let next = cursor {
            (results, cursor) = try await database.records(continuingMatchFrom: next, resultsLimit: CKQueryOperation.maximumResults)
            records += results.compactMap { try? $0.1.get() }
        }
        var downloaded: [Downloaded<Value>] = []
        for record in records {
            guard let url = (record["payload"] as? CKAsset)?.fileURL,
                  let data = try? Data(contentsOf: url),
                  let value = try? JSONDecoder().decode(Value.self, from: data) else { continue }
            downloaded.append(Downloaded(value: value, owner: try await owner(of: record),
                                         modified: record.modificationDate ?? .distantPast))
        }
        return downloaded
    }

    private static func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// CloudKit's errors, reduced to the three a player can act on.
    private func mapped<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as CKError {
            switch error.code {
            case .notAuthenticated:
                throw CloudSyncError.noAccount
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                throw CloudSyncError.unavailable
            default:
                throw CloudSyncError.failed(error.localizedDescription)
            }
        }
    }
}
