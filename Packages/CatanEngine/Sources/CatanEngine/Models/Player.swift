public enum BuildingKind: Codable, Sendable, CaseIterable, Hashable {
    case settlement, city
}

public struct Player: Codable, Sendable, Equatable {
    public let id: PlayerID
    public var resources: [Resource: Int]
    public var devCards: [DevCardType]
    public var playedKnights: Int
    public var settlements: Set<VertexID>
    public var cities: Set<VertexID>
    public var roads: Set<EdgeID>

    public init(
        id: PlayerID,
        resources: [Resource: Int] = [:],
        devCards: [DevCardType] = [],
        playedKnights: Int = 0,
        settlements: Set<VertexID> = [],
        cities: Set<VertexID> = [],
        roads: Set<EdgeID> = []
    ) {
        self.id = id
        self.resources = resources
        self.devCards = devCards
        self.playedKnights = playedKnights
        self.settlements = settlements
        self.cities = cities
        self.roads = roads
    }
}
