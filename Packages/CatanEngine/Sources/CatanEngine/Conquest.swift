/// The Conquest variant: tribes hold every producing hex, army cards take them.
///
/// One file so the whole variant can be read in one place; `RulesEngine`,
/// `SetupPhase` and `MainPhase` each call in at exactly one seam.
public enum Conquest {
    public static let armyCardCost: [Resource: Int] = [.brick: 1, .lumber: 1, .wool: 1, .grain: 1, .ore: 1]

    /// Every producing hex held by a tribe at its number's pip count. The
    /// desert gets no entry, which is what makes it un-deployable.
    public static func initialGarrisons(board: Board) -> [HexCoordinate: Garrison] {
        var garrisons: [HexCoordinate: Garrison] = [:]
        for tile in board.tiles {
            guard let token = tile.numberToken else { continue }
            garrisons[tile.coordinate] = Garrison(owner: nil, strength: DiceOdds.pips(for: token))
        }
        return garrisons
    }

    /// The unshuffled deck, ascending. Driven off sorted keys, never dictionary
    /// order, so a seeded shuffle deals the same deck in every process.
    public static func buildArmyDeck(_ counts: [Int: Int]) -> [Int] {
        counts.keys.sorted().flatMap { repeatElement($0, count: counts[$0, default: 0]) }
    }
}

/// Who holds a hex and how strongly. `owner == nil` is a tribe.
public struct Garrison: Codable, Sendable, Hashable {
    public var owner: PlayerID?
    public var strength: Int

    public init(owner: PlayerID?, strength: Int) {
        self.owner = owner
        self.strength = strength
    }
}
