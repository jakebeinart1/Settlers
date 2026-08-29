import Testing
import Foundation
@testable import Settlers
@testable import CatanEngine

/// First tests the app target has ever had.
///
/// The persistence layer is where they start deliberately: it is pure,
/// dependency-light, and it is where the two most expensive defects lived - a
/// save that could not be decoded vanished with no message, and every cold
/// launch wrote a junk game-log file that then evicted real games.
///
/// ## A caveat worth knowing
/// The stores are singletons that resolve their own directory from
/// `FileManager`, so these tests read and write the *simulator's* real app
/// container rather than a temporary directory. That is survivable - the
/// container is per-simulator and disposable - but it means a test must clean
/// up after itself and must not assume it starts from an empty state. Making
/// the directory injectable would fix that properly and is worth doing; it is
/// a change to all seven stores, so it is not bundled in here.
@Suite(.serialized)
struct GameStoreTests {

    private func withCleanSave<T>(_ body: () throws -> T) rethrows -> T {
        GameStore.shared.clear()
        defer { GameStore.shared.clear() }
        return try body()
    }

    @Test func loadReportsNoneWhenNothingHasBeenSaved() {
        withCleanSave {
            guard case .none = GameStore.shared.load() else {
                Issue.record("expected .none with no save on disk")
                return
            }
            #expect(!GameStore.shared.hasSave())
        }
    }

    @Test func aSavedGameRoundTrips() throws {
        try withCleanSave {
            var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
            state.players[0].resources = [.brick: 3, .ore: 1]
            try GameStore.shared.save(state)

            #expect(GameStore.shared.hasSave())
            guard case .loaded(let loaded) = GameStore.shared.load() else {
                Issue.record("expected .loaded after a save")
                return
            }
            #expect(loaded.players[0].resources == state.players[0].resources)
            #expect(loaded.board.tiles.count == state.board.tiles.count)
            #expect(loaded.schemaVersion == state.schemaVersion)
        }
    }

    /// The behaviour that used to lose games silently. `load()` returned
    /// `GameState?`, so "no save" and "save we failed to read" were the same
    /// answer and the app started a new game either way, saying nothing.
    @Test func anUndecodableSaveIsReportedAndLeftOnDisk() throws {
        try withCleanSave {
            let url = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("catan_save.json")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(#"{"board":"not a board"}"#.utf8).write(to: url)

            guard case .unreadable = GameStore.shared.load() else {
                Issue.record("a corrupt save must report .unreadable, not .none")
                return
            }
            #expect(FileManager.default.fileExists(atPath: url.path),
                    "the file must be left in place so it can still be recovered")
        }
    }

    /// A save written before a field existed must still load. Synthesized
    /// `Codable` would throw here; `GameState` hand-writes `init(from:)` for
    /// exactly this reason.
    @Test func aSaveMissingLaterFieldsStillLoads() throws {
        try withCleanSave {
            let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 3)
            let encoded = try JSONEncoder().encode(state)
            var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            for key in ["schemaVersion", "rng", "tradesAcceptedThisTurn", "devCardsBoughtThisTurn"] {
                object.removeValue(forKey: key)
            }
            let url = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("catan_save.json")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: object).write(to: url)

            guard case .loaded(let loaded) = GameStore.shared.load() else {
                Issue.record("an older save shape must still load")
                return
            }
            #expect(loaded.schemaVersion == 0, "a save with no version marker reads as v0")
        }
    }
}

@Suite(.serialized)
struct GameStatsStoreTests {

    @Test func recordingAGameUpdatesTheRunningTotals() {
        GameStatsStore.shared.clear()
        defer { GameStatsStore.shared.clear() }

        GameStatsStore.shared.recordGameEnd(won: true, finalVP: 10, duration: 300)
        GameStatsStore.shared.recordGameEnd(won: false, finalVP: 7, duration: 500)

        let stats = GameStatsStore.shared.load()
        #expect(stats.gamesPlayed == 2)
        #expect(stats.gamesWon == 1)
        #expect(stats.winRate == 0.5)
        #expect(stats.averageFinalVP == 8.5)
        #expect(stats.averageDurationSeconds == 400)
    }

    @Test func statsStartEmptyAfterAReset() {
        GameStatsStore.shared.recordGameEnd(won: true, finalVP: 10, duration: 1)
        GameStatsStore.shared.clear()
        #expect(GameStatsStore.shared.load().gamesPlayed == 0)
    }
}
