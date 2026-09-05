import CatanEngine

/// A buyer-private card reveal published only after the move's checkpoint is
/// durable. It is presentation state, never part of `GameState` or public game
/// history.
public struct DevCardReveal: Codable, Sendable, Equatable {
    public let owner: PlayerID
    public let card: DevCardType

    public init(owner: PlayerID, card: DevCardType) {
        self.owner = owner
        self.card = card
    }
}

/// The private, acknowledged result of a human development-card play.
///
/// `GameEvent` remains the engine's public structural transcript. This value
/// is deliberately stored beside the match checkpoint instead of in
/// `GameState`: it exists only so a successful play cannot disappear between
/// the durable write and the player reading what happened.
public enum DevCardResolution: Codable, Sendable, Equatable {
    case knight(owner: PlayerID, from: PlayerID?, stolen: Resource?)
    case roadBuilding(owner: PlayerID)
    case yearOfPlenty(owner: PlayerID, taken: [Resource: Int])
    case monopoly(owner: PlayerID, resource: Resource, gained: Int)

    public var owner: PlayerID {
        switch self {
        case .knight(let owner, _, _), .roadBuilding(let owner),
             .yearOfPlenty(let owner, _), .monopoly(let owner, _, _):
            owner
        }
    }

    public var card: DevCardType {
        switch self {
        case .knight: .knight
        case .roadBuilding: .roadBuilding
        case .yearOfPlenty: .yearOfPlenty
        case .monopoly: .monopoly
        }
    }
}

/// One stable row in the owner's private development-card shelf.
struct DevCardInventoryItem: Equatable, Identifiable {
    let type: DevCardType
    let held: Int
    let boughtThisTurn: Int
    let status: DevCardPlayStatus

    var id: String { type.rawValue }
    var ready: Int { max(held - boughtThisTurn, 0) }

    static func all(for player: PlayerID, in state: GameState) -> [Self] {
        guard let owner = state.players.first(where: { $0.id == player }) else { return [] }
        let newCards = state.devCardsBoughtThisTurn[player] ?? []
        return DevCardType.allCases.compactMap { type in
            let held = owner.devCards.filter { $0 == type }.count
            guard held > 0 else { return nil }
            return Self(
                type: type,
                held: held,
                boughtThisTurn: newCards.filter { $0 == type }.count,
                status: DevCards.playStatus(type, by: player, in: state)
            )
        }
    }
}
