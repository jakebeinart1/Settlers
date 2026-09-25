import Foundation
import Testing
@testable import Settlers

@Suite struct RatingStoreTests {

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("RatingStoreTests.\(UUID().uuidString)")
    }

    /// A resumed session can replay a completion that was committed but not
    /// acknowledged; the second record of the same match must change nothing.
    @Test func recordingTheSameMatchTwiceIsANoOp() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = RatingStore(directory: dir)
        let match = UUID()
        let seats: [RatedEntity] = [.person("Jake"), .classic, .classic, .ghost("jake")]
        try store.record(match: match, seats: seats, winner: 0)
        let once = store.load()
        try store.record(match: match, seats: seats, winner: 3)
        #expect(store.load() == once)
        #expect(once.games["person:Jake"] == 1)
    }

    @Test func survivesANewStoreAndKeepsHistory() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try RatingStore(directory: dir).record(match: UUID(), seats: [.person("Jake"), .expert, .expert, .expert], winner: 0)
        try RatingStore(directory: dir).record(match: UUID(), seats: [.person("Jake"), .expert, .expert, .expert], winner: 1)
        let ratings = RatingStore(directory: dir).load()
        #expect(ratings.games["person:Jake"] == 2)
        #expect(ratings.history.filter { $0.entity == "person:Jake" }.count == 2, "every update is kept")
        #expect(ratings.ratings["classic"] == nil)
    }

    /// A damaged file must never be overwritten silently: it is kept aside.
    @Test func aCorruptFileIsPreservedNotOverwritten() throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("ratings.json"))
        let store = RatingStore(directory: dir)
        #expect(store.load() == Ratings())
        try store.record(match: UUID(), seats: [.person("Jake"), .classic, .classic, .classic], winner: 0)
        #expect(try String(contentsOf: dir.appendingPathComponent("ratings.corrupt.json"), encoding: .utf8) == "not json")
    }
}
