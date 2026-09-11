public enum DevCardType: String, Codable, CaseIterable, Sendable {
    case knight, roadBuilding, yearOfPlenty, monopoly, victoryPoint
}

public extension DevCardType {
    /// The order card types are stacked before the deck is shuffled.
    ///
    /// Pinned to the historical append order - knight, victory point, road
    /// building, year of plenty, monopoly - because `SeededGameFingerprintTests`
    /// depends on it: the same multiset stacked in a different order yields a
    /// different Fisher-Yates permutation for the same seed, so changing this
    /// changes what deck every seeded Classic game deals.
    ///
    /// Deliberately NOT `allCases` order. `StateEncoding` iterates `allCases`
    /// to lay out feature slots, so the declaration order is load-bearing
    /// elsewhere and the two must be free to differ.
    ///
    /// The switch is exhaustive on purpose: a new card type cannot compile
    /// until it is given a position here, so it can never be silently absent
    /// from the deck.
    var deckBuildOrder: Int {
        switch self {
        case .knight: return 0
        case .victoryPoint: return 1
        case .roadBuilding: return 2
        case .yearOfPlenty: return 3
        case .monopoly: return 4
        }
    }
}
