import Foundation

/// `Hashable` is synthesized: every payload (`VertexID`, `EdgeID`,
/// `HexCoordinate`, `Resource`, `PlayerID`, `UUID`, and dictionaries of those)
/// already conforms. It exists so moves can be compared and de-duplicated
/// structurally rather than through hand-written case-by-case matchers - there
/// were three of those in the codebase, two byte-identical, and comparing
/// moves by their `description` string is unsafe because a `[Resource: Int]`
/// payload prints its keys in a per-process order.
public enum GameMove: Codable, Sendable, Hashable {
    case placeInitialSettlement(VertexID)
    case placeInitialRoad(EdgeID)
    case rollDice
    case buildRoad(EdgeID)
    case buildSettlement(VertexID)
    case buildCity(VertexID)
    case buyDevCard
    case playKnight(moveRobberTo: HexCoordinate, stealFrom: PlayerID?)
    case playRoadBuilding(EdgeID, EdgeID)
    case playYearOfPlenty(Resource, Resource)
    case playMonopoly(Resource)
    case moveRobber(HexCoordinate, stealFrom: PlayerID?)
    case discard([Resource: Int])
    case bankTrade(give: [Resource: Int], get: [Resource: Int])
    case proposeTrade(TradeOffer)
    case respondToTrade(offerID: UUID, accept: Bool)
    case endTurn
}

public struct TradeOffer: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let from: PlayerID
    public let give: [Resource: Int]
    public let want: [Resource: Int]

    public init(id: UUID = UUID(), from: PlayerID, give: [Resource: Int], want: [Resource: Int]) {
        self.id = id
        self.from = from
        self.give = give
        self.want = want
    }

    /// Builds a candidate offer whose `id` is derived from its own contents
    /// rather than randomly generated.
    ///
    /// ## Why this exists
    /// `RulesEngine.legalMoves` enumerates `.proposeTrade` candidates, and
    /// with the random `UUID()` default above it minted **fresh ids on every
    /// call** - so `legalMoves` was not a pure function of the game state.
    /// Two calls over the identical state returned offers that compared
    /// unequal, which meant a seeded self-play run produced a different game
    /// on every launch even once the dice were made reproducible, and it
    /// ruled out hashing a state for a search transposition table.
    ///
    /// The id is a 16-byte FNV-1a digest over the proposer and the sorted
    /// give/want pairs, so the same offer always carries the same id and
    /// different offers effectively never collide. Offers the *player*
    /// creates through the UI keep the random default - they are real
    /// distinct proposals, not enumerated candidates.
    public static func enumerated(from: PlayerID, give: [Resource: Int], want: [Resource: Int]) -> TradeOffer {
        var descriptor = "\(from.index)|"
        for (label, table) in [("g", give), ("w", want)] {
            descriptor += label
            for resource in Resource.allCases where (table[resource] ?? 0) != 0 {
                descriptor += ":\(resource.rawValue)=\(table[resource] ?? 0)"
            }
            descriptor += "|"
        }

        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        var bytes: [UInt8] = []
        for byte in descriptor.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
            bytes.append(UInt8(truncatingIfNeeded: hash >> 56))
        }
        // Pad or trim to exactly the 16 bytes a UUID needs.
        while bytes.count < 16 {
            hash = (hash ^ UInt64(bytes.count)) &* 0x0000_0100_0000_01B3
            bytes.append(UInt8(truncatingIfNeeded: hash >> 56))
        }
        let b = Array(bytes.suffix(16))
        let uuid = UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                               b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
        return TradeOffer(id: uuid, from: from, give: give, want: want)
    }
}

public enum MoveError: Error, Sendable, Equatable {
    case notYourTurn
    case illegalPlacement
    case insufficientResources
    case wrongPhase
    case invalidTradeTarget
    /// The *bank* has run out of the named resource. Distinct from
    /// `insufficientResources`, which is about the player's own hand -
    /// reporting a depleted bank as "you don't have enough resources" told
    /// the player the opposite of what was true, while they sat holding the
    /// cards they were trying to spend.
    case bankCannotSupply(Resource)
    case other(String)
}

/// Human-readable messages for every case, rather than leaving UI layers to
/// interpolate the error directly (`"\(error)"`, which - with no
/// `CustomStringConvertible`/`LocalizedError` conformance - just prints the
/// bare case name, e.g. a literal "wrongPhase" shown to the player). Callers
/// should read `error.localizedDescription`, which on Apple platforms
/// resolves through this conformance.
extension MoveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notYourTurn: return "It's not your turn."
        case .illegalPlacement: return "That's not a legal move."
        case .insufficientResources: return "You don't have enough resources for that."
        case .wrongPhase: return "You can't do that right now."
        case .invalidTradeTarget: return "That trade isn't available."
        case .bankCannotSupply(let resource): return "The bank is out of \(resource.rawValue)."
        case .other(let message): return message
        }
    }
}
