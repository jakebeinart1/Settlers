import Foundation
import CatanEngine

/// Which seat (0-3) the human occupies in the *current* game - persisted
/// alongside `GameStore`'s save so a resumed game keeps the same seat
/// instead of assuming seat 0 (the fixed default before "Randomize Seat"
/// existed). Written once, when `GameViewModel.startNewGame` picks a seat;
/// read back on relaunch.
public struct HumanSeatStore: Sendable {
    public static let shared = HumanSeatStore()

    private let key = "humanSeatIndex"

    init() {}

    /// The saved seat, or `PlayerID(index: 0)` if none has been recorded yet
    /// - covers both a genuinely fresh install and a save file written
    /// before this store existed (those games were always seat 0 anyway).
    public func load() -> PlayerID {
        let index = UserDefaults.standard.object(forKey: key) as? Int ?? 0
        return PlayerID(index: index)
    }

    public func save(_ seat: PlayerID) {
        UserDefaults.standard.set(seat.index, forKey: key)
    }
}
