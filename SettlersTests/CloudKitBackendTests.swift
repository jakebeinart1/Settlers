import CatanAI
import CloudKit
import Foundation
import Testing
@testable import Settlers

/// Exercises the record processing used by the live adapter without creating
/// a CKContainer or reaching an iCloud account.
@Suite struct CloudKitBackendTests {
    @Test(arguments: [false, true])
    func aMixedQueryBatchFailsInsteadOfReturningPartialRecords(failureFirst: Bool) throws {
        let record = CKRecord(recordType: "Match", recordID: CKRecord.ID(recordName: "finished-game"))
        let success: (CKRecord.ID, Result<CKRecord, any Error>) = (record.recordID, .success(record))
        let failure: (CKRecord.ID, Result<CKRecord, any Error>) = (
            CKRecord.ID(recordName: "unavailable-game"), .failure(CKError(.serviceUnavailable)))

        #expect(throws: CKError.self) {
            try CloudKitBackend.queryRecords(from: failureFirst ? [failure, success] : [success, failure])
        }
    }

    @Test func aSuccessfulQueryBatchKeepsAllItsRecords() throws {
        let first = CKRecord(recordType: "Match", recordID: CKRecord.ID(recordName: "first-game"))
        let second = CKRecord(recordType: "Match", recordID: CKRecord.ID(recordName: "second-game"))
        let records = try CloudKitBackend.queryRecords(from: [
            (first.recordID, .success(first)), (second.recordID, .success(second))
        ])

        #expect(records.map(\.recordID.recordName) == ["first-game", "second-game"])
    }

    @Test func aMixedClaimBatchFailsInsteadOfReturningPartialClaims() throws {
        let record = CKRecord(recordType: "Player", recordID: CKRecord.ID(recordName: "name-jake"))
        record["name"] = "Jake"
        let results: [CKRecord.ID: Result<CKRecord, any Error>] = [
            record.recordID: .success(record),
            CKRecord.ID(recordName: "name-alex"): .failure(CKError(.networkFailure))
        ]

        #expect(throws: CKError.self) { try CloudKitBackend.claimRecords(from: results) }
    }

    @Test func anUnknownClaimDoesNotDiscardClaimsThatExist() throws {
        let record = CKRecord(recordType: "Player", recordID: CKRecord.ID(recordName: "name-jake"))
        record["name"] = "Jake"
        let results: [CKRecord.ID: Result<CKRecord, any Error>] = [
            record.recordID: .success(record),
            CKRecord.ID(recordName: "name-unclaimed"): .failure(CKError(.unknownItem))
        ]
        let records = try CloudKitBackend.claimRecords(from: results)

        #expect(records.map(\.recordID.recordName) == ["name-jake"])
        #expect(records.first?["name"] as? String == "Jake")
    }

    @Test func anUnreadableAssetFailsInsteadOfSkippingTheRecord() throws {
        let asset = try assetRecord(data: Data("{\"moves\":7}".utf8))
        // The asset existed when CloudKit supplied it, then disappeared before
        // the adapter read it. No cloud operation is needed to reproduce this.
        try FileManager.default.removeItem(at: asset.file)

        #expect(throws: CocoaError.self) {
            let _: Payload? = try CloudKitBackend.decodedPayload(from: asset.record)
        }
    }

    @Test func aMissingPayloadAssetFailsInsteadOfSkippingTheRecord() throws {
        let record = CKRecord(recordType: "Match")

        #expect(throws: CKError.self) {
            let _: Payload? = try CloudKitBackend.decodedPayload(from: record)
        }
    }

    @Test func anIncompatibleReadablePayloadIsIntentionallySkipped() throws {
        let asset = try assetRecord(data: Data("{\"futureMoves\":[]}".utf8))
        defer { try? FileManager.default.removeItem(at: asset.file) }
        let payload: Payload? = try CloudKitBackend.decodedPayload(from: asset.record)

        #expect(payload == nil)
    }

    @Test func aCompatiblePayloadIsReadFromItsAsset() throws {
        let asset = try assetRecord(data: Data("{\"moves\":7}".utf8))
        defer { try? FileManager.default.removeItem(at: asset.file) }
        let payload: Payload? = try CloudKitBackend.decodedPayload(from: asset.record)

        #expect(payload?.moves == 7)
    }

    @Test func aNewerServerGhostIsNeitherPreparedNorMutated() throws {
        let serverGhost = ghost(gamesLearned: 25)
        let asset = try assetRecord(data: JSONEncoder().encode(serverGhost), type: "Ghost", recordName: "ghost-jake")
        defer { try? FileManager.default.removeItem(at: asset.file) }
        asset.record["gamesLearned"] = 25

        let upload = try CloudKitBackend.prepareGhostUpload(ghost(gamesLearned: 24), existing: asset.record)
        defer {
            if let upload { try? FileManager.default.removeItem(at: upload.assetFile) }
        }
        let retained: GhostProfile? = try CloudKitBackend.decodedPayload(from: asset.record)

        #expect(upload == nil)
        #expect(asset.record["gamesLearned"] as? Int == 25)
        #expect(retained == serverGhost)
    }

    @Test(arguments: [25, 26])
    func anEqualOrNewerLocalGhostKeepsTheFetchedRecord(gamesLearned: Int) throws {
        let server = CKRecord(recordType: "Ghost", recordID: CKRecord.ID(recordName: "ghost-jake"))
        server["gamesLearned"] = 25
        let upload = try #require(try CloudKitBackend.prepareGhostUpload(ghost(gamesLearned: gamesLearned), existing: server))
        defer { try? FileManager.default.removeItem(at: upload.assetFile) }
        let payload: GhostProfile? = try CloudKitBackend.decodedPayload(from: upload.record)

        // Reusing the fetched record keeps CloudKit's change tag and existing
        // serverRecordChanged retry semantics, rather than issuing a fresh save.
        #expect(upload.record === server)
        #expect(upload.record["gamesLearned"] as? Int == gamesLearned)
        #expect(payload?.gamesLearned == gamesLearned)
    }

    /// A reset ghost has fewer games than the server's copy but a higher
    /// revision, and the record field carries the revision.
    @Test func aResetGhostWithAHigherRevisionUploadsOverMoreGames() throws {
        let server = CKRecord(recordType: "Ghost", recordID: CKRecord.ID(recordName: "ghost-jake"))
        server["gamesLearned"] = 30
        var reset = ghost(gamesLearned: 0)
        reset.revision = 31
        let upload = try #require(try CloudKitBackend.prepareGhostUpload(reset, existing: server))
        defer { try? FileManager.default.removeItem(at: upload.assetFile) }
        #expect(upload.record["gamesLearned"] as? Int == 31)
    }

    @Test func aGhostWithoutAServerRecordCanStillBeUploaded() throws {
        let upload = try #require(try CloudKitBackend.prepareGhostUpload(ghost(gamesLearned: 1), existing: nil))
        defer { try? FileManager.default.removeItem(at: upload.assetFile) }
        let payload: GhostProfile? = try CloudKitBackend.decodedPayload(from: upload.record)

        #expect(upload.record.recordID.recordName == "ghost-jake")
        #expect(upload.record.recordType == "Ghost")
        #expect(payload?.gamesLearned == 1)
    }

    private struct Payload: Decodable {
        let moves: Int
    }

    private func assetRecord(data: Data, type: String = "Match", recordName: String = UUID().uuidString) throws -> (record: CKRecord, file: URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("CloudKitBackendTests.\(UUID().uuidString).json")
        try data.write(to: file, options: .atomic)
        let record = CKRecord(recordType: type, recordID: CKRecord.ID(recordName: recordName))
        record["payload"] = CKAsset(fileURL: file)
        return (record, file)
    }

    private func ghost(gamesLearned: Int) -> GhostProfile {
        GhostProfile(id: "jake", name: "Jake's Ghost", person: .anchored(at: .forMode(.classic)),
                     lambda: 0.01, gamesLearned: gamesLearned)
    }
}
