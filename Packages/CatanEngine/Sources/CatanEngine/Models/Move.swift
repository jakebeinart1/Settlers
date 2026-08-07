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
