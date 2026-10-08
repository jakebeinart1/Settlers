import Foundation

/// Geographic families vary expedition choices while sharing land and production budgets.
public enum NavalMapFamily: String, Codable, CaseIterable, Sendable {
    case archipelago, peninsula, twinIslands

    public var displayName: String {
        switch self {
        case .archipelago: return "Archipelago"
        case .peninsula: return "Peninsula"
        case .twinIslands: return "Twin Islands"
        }
    }
}

/// Settings are saved with the match; toggles do not change its underlying seeded world.
public struct NavalOptions: Codable, Sendable, Equatable {
    public var fogEnabled: Bool
    public var resourceChoiceEnabled: Bool
    public var mapFamily: NavalMapFamily?
    /// Missing means the original always-enabled rule. Keep that distinction
    /// through active saves/replays, but normalize an old editable prefill to Off.
    private var shipStealingChoice: Bool?

    public var shipStealingEnabled: Bool {
        get { shipStealingChoice ?? true }
        set { shipStealingChoice = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case fogEnabled, resourceChoiceEnabled, mapFamily, shipStealingEnabled
    }

    public init(fogEnabled: Bool = true, resourceChoiceEnabled: Bool = true,
                mapFamily: NavalMapFamily? = nil, shipStealingEnabled: Bool = false) {
        self.fogEnabled = fogEnabled
        self.resourceChoiceEnabled = resourceChoiceEnabled
        self.mapFamily = mapFamily
        self.shipStealingChoice = shipStealingEnabled
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fogEnabled = try values.decodeIfPresent(Bool.self, forKey: .fogEnabled) ?? true
        resourceChoiceEnabled = try values.decodeIfPresent(Bool.self, forKey: .resourceChoiceEnabled) ?? true
        mapFamily = try values.decodeIfPresent(NavalMapFamily.self, forKey: .mapFamily)
        shipStealingChoice = try values.decodeIfPresent(Bool.self, forKey: .shipStealingEnabled)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(fogEnabled, forKey: .fogEnabled)
        try values.encode(resourceChoiceEnabled, forKey: .resourceChoiceEnabled)
        try values.encodeIfPresent(mapFamily, forKey: .mapFamily)
        try values.encodeIfPresent(shipStealingChoice, forKey: .shipStealingEnabled)
    }

    /// Called only for New Game drafts, never for Restart or resumed matches.
    public mutating func normalizeForNewGame() {
        if shipStealingChoice == nil { shipStealingChoice = false }
    }

    /// Defaults for an authoritative save that predates the options field.
    public static var legacyDefaults: Self {
        var options = Self()
        options.shipStealingChoice = nil
        return options
    }
}

/// Identity survives capture. Movement is local to the controlling player's current turn.
public struct Ship: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public var owner: PlayerID
    public var coordinate: HexCoordinate
    public var stepsRemaining: Int

    public init(id: Int, owner: PlayerID, coordinate: HexCoordinate,
                stepsRemaining: Int = Naval.movementPerTurn) {
        self.id = id
        self.owner = owner
        self.coordinate = coordinate
        self.stepsRemaining = stepsRemaining
    }
}

/// One durable production obligation. Cities contribute two individually resolved units.
public struct NavalResourceChoice: Codable, Sendable, Equatable {
    public var playerIndex: Int
    public var remaining: Int

    public init(playerIndex: Int, remaining: Int) {
        self.playerIndex = playerIndex
        self.remaining = remaining
    }
}

/// A view of the current harvest, derived from the unchanged board and roll.
/// Keeping its original yield separate from the durable remaining obligation
/// preserves city and mixed-building explanations after a partial cold resume.
public struct NavalHarvestProgress: Sendable, Equatable {
    public let settlements: Int
    public let cities: Int
    public let remaining: Int
    public var total: Int { settlements + cities * Self.cityYield }
    public var collected: Int { total - remaining }

    private static let cityYield = 2

    init(settlements: Int, cities: Int, remaining: Int? = nil) {
        self.settlements = settlements
        self.cities = cities
        self.remaining = remaining ?? settlements + cities * Self.cityYield
    }
}

/// Persistent naval bookkeeping. Hidden component IDs exist only in authoritative state.
///
/// Purchased hull counts belong to builders, not controllers, so capture cannot manufacture
/// replacement pieces. Colony bonuses are public, while full land connectivity is concealed.
public struct NavalState: Codable, Sendable, Equatable {
    public var options: NavalOptions
    public var revealed: Set<HexCoordinate>
    public var ships: [Ship]
    public var mapFamily: NavalMapFamily
    public var rulesVersion: Int
    public var mapVersion: Int
    public var generationAttempts: Int
    public var usedFallback: Bool
    public var nextShipID: Int
    public var hullsBuilt: [PlayerID: Int]
    public var islandByHex: [HexCoordinate: Int]
    public var colonizedIslands: [PlayerID: Set<Int>]
    public var colonyPoints: [PlayerID: Int]
    public var pendingResourceChoices: [NavalResourceChoice]
    public var productionRollerIndex: Int?
    public var capturePending: Bool

    public init(options: NavalOptions = NavalOptions(), revealed: Set<HexCoordinate> = [],
                ships: [Ship] = [], mapFamily: NavalMapFamily = .archipelago) {
        self.options = options
        self.revealed = revealed
        self.ships = ships
        self.mapFamily = mapFamily
        self.rulesVersion = Naval.currentRulesVersion
        self.mapVersion = Naval.currentMapVersion
        self.generationAttempts = 0
        self.usedFallback = false
        self.nextShipID = Self.nextID(after: ships)
        self.hullsBuilt = Dictionary(grouping: ships, by: \.owner).mapValues(\.count)
        self.islandByHex = [:]
        self.colonizedIslands = [:]
        self.colonyPoints = [:]
        self.pendingResourceChoices = []
        self.productionRollerIndex = nil
        self.capturePending = false
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        options = try values.decodeIfPresent(NavalOptions.self, forKey: .options) ?? .legacyDefaults
        revealed = try values.decodeIfPresent(Set<HexCoordinate>.self, forKey: .revealed) ?? []
        ships = try values.decodeIfPresent([Ship].self, forKey: .ships) ?? []
        mapFamily = try values.decodeIfPresent(NavalMapFamily.self, forKey: .mapFamily) ?? .archipelago
        // Missing versions describe the original naval behavior, never whichever rules this binary creates today.
        rulesVersion = try values.decodeIfPresent(Int.self, forKey: .rulesVersion) ?? Naval.oldestSupportedRulesVersion
        mapVersion = try values.decodeIfPresent(Int.self, forKey: .mapVersion) ?? Naval.currentMapVersion
        generationAttempts = try values.decodeIfPresent(Int.self, forKey: .generationAttempts) ?? 0
        usedFallback = try values.decodeIfPresent(Bool.self, forKey: .usedFallback) ?? false
        nextShipID = try values.decodeIfPresent(Int.self, forKey: .nextShipID) ?? Self.nextID(after: ships)
        hullsBuilt = try values.decodeIfPresent([PlayerID: Int].self, forKey: .hullsBuilt) ?? [:]
        islandByHex = try values.decodeIfPresent([HexCoordinate: Int].self, forKey: .islandByHex) ?? [:]
        colonizedIslands = try values.decodeIfPresent([PlayerID: Set<Int>].self, forKey: .colonizedIslands) ?? [:]
        colonyPoints = try values.decodeIfPresent([PlayerID: Int].self, forKey: .colonyPoints) ?? [:]
        pendingResourceChoices = try values.decodeIfPresent([NavalResourceChoice].self, forKey: .pendingResourceChoices) ?? []
        productionRollerIndex = try values.decodeIfPresent(Int.self, forKey: .productionRollerIndex)
        capturePending = try values.decodeIfPresent(Bool.self, forKey: .capturePending) ?? false
    }
    /// Malformed IDs remain rejectable by checkpoint validation instead of overflowing decode.
    private static func nextID(after ships: [Ship]) -> Int {
        let highest = ships.map(\.id).max() ?? -1
        return highest == Int.max ? Int.max : highest + 1
    }

}
