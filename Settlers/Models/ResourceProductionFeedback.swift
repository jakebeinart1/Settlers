import Foundation
import CatanEngine

/// A short-lived receipt for one committed roll and the seat holding the device.
/// Create this from a single step AFTER its checkpoint succeeds, using the state
/// before that step and its committed state. Aggregated UI batches or observing
/// hand counts alone can confuse a trade, a card play, or two equal rolls.
/// This is presentation data: never persist it or wait for it before advancing play.
public struct ResourceProductionFeedback: Equatable, Identifiable, Sendable {
    public static let displaySeconds: TimeInterval = 3

    public let id: UUID
    public let owner: PlayerID
    public let roll: Int
    public let gains: [Gain]
    public let occurredAt: Date

    public var expiresAt: Date { occurredAt.addingTimeInterval(Self.displaySeconds) }
    public var total: Int { gains.reduce(0) { $0 + $1.amount } }

    /// Only unambiguously paid hexes. A bank shortage across several matching
    /// hexes has no per-hex allocation in the engine, so those hexes are omitted.
    public var sourceTiles: Set<HexCoordinate> { Set(gains.flatMap(\.sources).map(\.hex)) }

    public struct Gain: Equatable, Sendable {
        public let resource: Resource
        public let amount: Int
        public let sources: [Source]

        var receiptText: String {
            let origin = sources.count == 1 ? "\(sources[0].origin) " : ""
            return "\(origin)+\(amount) \(resource.rawValue)"
        }
    }

    public struct Source: Equatable, Sendable {
        public let hex: HexCoordinate
        public let amount: Int
        public let settlements: Int
        public let cities: Int
        public let hasOccupationBonus: Bool

        /// Counts describe the public buildings; they never calculate a payout.
        public var origin: String {
            let building: String
            if cities > 0, settlements > 0 {
                building = "Buildings"
            } else if cities > 0 {
                building = cities == 1 ? "City" : "Cities"
            } else if settlements > 0 {
                building = settlements == 1 ? "Settlement" : "Settlements"
            } else {
                return "Occupation"
            }
            return hasOccupationBonus ? "\(building) + occupation" : building
        }
    }

    /// A missing viewer means the device is covered/unclaimed. A mismatched
    /// delta means these aren't the before/after states of this one roll: do not
    /// guess, show a projected payout, or read the depleted post-roll bank.
    public init?(events: [GameEvent], before: GameState, after: GameState,
                 viewer: PlayerID?, occurredAt: Date = Date()) {
        guard let viewer, let roll = Self.singleRoll(in: events, before: before),
              after.lastDiceRoll == roll,
              let index = before.players.firstIndex(where: { $0.id == viewer }),
              let received = after.players.first(where: { $0.id == viewer }) else { return nil }
        let paid = MainPhase.payouts(for: roll, in: before)[index, default: [:]]
        guard Resource.allCases.allSatisfy({ resource in
            received.resources[resource, default: 0] - before.players[index].resources[resource, default: 0]
                == paid[resource, default: 0]
        }) else { return nil }
        let gains = Self.gains(paid: paid, roll: roll, before: before, index: index)
        guard !gains.isEmpty else { return nil }
        self.id = UUID()
        self.owner = viewer
        self.roll = roll
        self.gains = gains
        self.occurredAt = occurredAt
    }

    /// Check at render time, not only when receiving the event: a seat change
    /// must hide the outgoing receipt in that same frame. The caller also clears
    /// the stored value on seat, match, background, and recovery boundaries.
    public func visible(to viewer: PlayerID?, at date: Date) -> Self? {
        viewer == owner && date >= occurredAt && date < expiresAt ? self : nil
    }

    public func amount(for resource: Resource) -> Int {
        gains.first { $0.resource == resource }?.amount ?? 0
    }

    public var summary: String {
        "\(roll) rolled · " + gains.map(\.receiptText).joined(separator: ", ")
    }

    public var compactSummary: String {
        "\(roll) rolled · +\(total) \(total == 1 ? "card" : "cards")"
    }

    /// Keep the city/settlement distinction visible when the resource names
    /// don't fit. The hand's individual +N badges still identify the resources.
    public var sourceSummary: String? {
        let sources = gains.flatMap(\.sources)
        guard sources.reduce(0, { $0 + $1.amount }) == total else { return nil }
        return "\(roll) · " + sources.map { "\($0.origin) +\($0.amount)" }.joined(separator: " · ")
    }

    public var accessibilitySummary: String {
        let received = gains.map { gain in
            let sources = gain.sources.map { "\($0.origin), +\($0.amount), on a \(roll) hex" }
            let detail = sources.isEmpty ? "" : " (\(sources.joined(separator: "; ")))"
            return "\(gain.amount) \(gain.resource.rawValue)\(detail)"
        }
        return "\(roll) rolled. Received " + received.joined(separator: ", ") + "."
    }

    private static func singleRoll(in events: [GameEvent], before: GameState) -> Int? {
        var result: Int?
        for event in events {
            switch event {
            case .rolled(let actor, let total):
                guard result == nil, before.phase == .rollDice(playerIndex: actor.index) else { return nil }
                result = total
            case .gameWon: break
            default: return nil
            }
        }
        return result
    }

    private static func gains(paid: [Resource: Int], roll: Int, before: GameState, index: Int) -> [Gain] {
        Resource.allCases.compactMap { resource in
            let amount = paid[resource, default: 0]
            guard amount > 0 else { return nil }
            let sources = before.board.tiles.sorted { $0.coordinate < $1.coordinate }.compactMap { tile in
                source(for: tile, resource: resource, roll: roll, before: before, index: index)
            }
            // Isolating tiles removes competition between hexes for the bank.
            // Only use that attribution when its sum equals what was paid.
            let exactSources = sources.reduce(0) { $0 + $1.amount } == amount ? sources : []
            return Gain(resource: resource, amount: amount, sources: exactSources)
        }
    }

    /// Ask the SAME engine rule about a single hex. It already understands
    /// robber blocking, cities, Conquest occupation and the available bank.
    /// Copying a 1x/2x formula here would drift as variants change.
    private static func source(for tile: Tile, resource: Resource, roll: Int,
                               before: GameState, index: Int) -> Source? {
        guard tile.numberToken == roll, tile.kind == .resource(resource) else { return nil }
        var isolated = before
        isolated.board = Board(tiles: [tile], ports: [], onBoardVertices: before.board.onBoardVertices,
                               onBoardEdges: before.board.onBoardEdges, robberTile: before.board.robberTile)
        let amount = MainPhase.payouts(for: roll, in: isolated)[index]?[resource] ?? 0
        guard amount > 0 else { return nil }
        let player = before.players[index]
        let corners = Set(before.board.corners(of: tile.coordinate))
        return Source(hex: tile.coordinate, amount: amount,
                      settlements: player.settlements.intersection(corners).count,
                      cities: player.cities.intersection(corners).count,
                      hasOccupationBonus: before.garrisons[tile.coordinate]?.owner == player.id)
    }
}
