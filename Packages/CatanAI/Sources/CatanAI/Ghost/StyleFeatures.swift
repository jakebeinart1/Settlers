import CatanEngine

/// Habits Expert's position score cannot see: how a person trades, whom they
/// rob, what they do with a turn. Each is a number per candidate move, so the
/// person model can learn how much this person leans toward it.
///
/// Values are what the move *is*, not whether it is good. Goodness is the
/// score's job, and mixing the two would let a habit hide inside a value.
public enum StyleFeatures {

    public static let labels = [
        "propose", "proposeCardsGiven", "proposeLopsided", "proposeAfterRefusal",
        "bankTrade", "acceptOffer", "robberHitsLeader", "robberHitsBiggestHand",
        "buyDevCard", "playDevCard", "endTurn", "buildCity", "buildSettlement", "buildRoad",
    ]

    public static func of(_ move: GameMove, by seat: PlayerID, in state: GameState) -> [Double] {
        var features = [Double](repeating: 0, count: labels.count)
        func set(_ label: String, _ value: Double) { features[labels.firstIndex(of: label)!] = value }
        switch move {
        case .proposeTrade(let offer):
            let given = offer.give.values.reduce(0, +)
            set("propose", 1)
            set("proposeCardsGiven", Double(given))
            set("proposeLopsided", Double(given - offer.want.values.reduce(0, +)))
            set("proposeAfterRefusal", state.declinedTradeOffersThisTurn[seat, default: []].isEmpty ? 0 : 1)
        case .bankTrade: set("bankTrade", 1)
        case .respondToTrade(_, let accept): set("acceptOffer", accept ? 1 : 0)
        case .moveRobber(_, stealFrom: let victim), .playKnight(moveRobberTo: _, stealFrom: let victim):
            if case .playKnight = move { set("playDevCard", 1) }
            guard let victim else { break }
            set("robberHitsLeader", isLeader(victim, seat: seat, state: state) ? 1 : 0)
            set("robberHitsBiggestHand", hasBiggestHand(victim, seat: seat, state: state) ? 1 : 0)
        case .playRoadBuilding, .playYearOfPlenty, .playMonopoly: set("playDevCard", 1)
        case .buyDevCard: set("buyDevCard", 1)
        case .endTurn: set("endTurn", 1)
        case .buildCity: set("buildCity", 1)
        case .buildSettlement: set("buildSettlement", 1)
        case .buildRoad: set("buildRoad", 1)
        default: break
        }
        return features
    }

    /// Ties count as leading: robbing any co-leader is robbing the leader.
    private static func isLeader(_ victim: PlayerID, seat: PlayerID, state: GameState) -> Bool {
        let top = state.players.map(\.id).filter { $0 != seat }.map { state.publicVictoryPoints(for: $0) }.max() ?? 0
        return state.publicVictoryPoints(for: victim) == top
    }

    /// Hand size is public at a real table; composition is not, and is not used.
    private static func hasBiggestHand(_ victim: PlayerID, seat: PlayerID, state: GameState) -> Bool {
        func size(_ id: PlayerID) -> Int { state.players.first { $0.id == id }?.resources.values.reduce(0, +) ?? 0 }
        let top = state.players.map(\.id).filter { $0 != seat }.map(size).max() ?? 0
        return size(victim) == top
    }
}
