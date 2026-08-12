import Foundation

public enum GameMove: Codable, Sendable {
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

public struct TradeOffer: Codable, Sendable, Identifiable {
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
}

public enum MoveError: Error, Sendable, Equatable {
    case notYourTurn
    case illegalPlacement
    case insufficientResources
    case wrongPhase
    case invalidTradeTarget
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
        case .other(let message): return message
        }
    }
}
