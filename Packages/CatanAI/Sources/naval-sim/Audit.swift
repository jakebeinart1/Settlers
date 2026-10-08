import CatanAI
import CatanEngine
import Foundation

/// Optional development evidence uses the actual masked decision and ledger.
/// It never samples or serializes the future deck, PRNG or concealed terrain.
struct AuditRow: Encodable {
    struct Alternative: Encodable {
        let move: String
        let score: Double
        let reason: String
    }

    let seed: UInt64
    let action: Int
    let seat: Int
    let phase: String
    let move: String
    let publicPointsBefore: [Int]
    let publicPointsAfter: [Int]
    let ownPointsBefore: Int
    let ownPointsAfter: Int
    let resourceOrder: [String]
    let resourcesBefore: [Int]
    let resourcesAfter: [Int]
    let ownVictoryCards: Int
    let ownShipsBefore: [Ship]
    let ownShipsAfter: [Ship]
    let colonyPoints: Int
    let fogRemaining: Int
    let maxDiscoveryFromLegalSailing: Int
    let bestSailingScore: Double?
    let alternatives: [Alternative]

    init(seed: UInt64, action: Int, decision: GameSession.Decision,
         ledger: PublicLedger, after: GameState, tier: NavalPolicy.Tier, revision: NavalPolicy.Revision) {
        let state = decision.observation.state
        let actor = decision.seat
        self.seed = seed
        self.action = action
        self.seat = actor.index
        self.phase = String(describing: state.phase)
        self.move = Rendering.canonical(decision.move)
        self.publicPointsBefore = state.players.map { state.publicVictoryPoints(for: $0.id) }
        self.publicPointsAfter = after.players.map { after.publicVictoryPoints(for: $0.id) }
        self.ownPointsBefore = state.victoryPoints(for: actor)
        self.ownPointsAfter = after.victoryPoints(for: actor)
        self.resourceOrder = Resource.allCases.map { String(describing: $0) }
        self.resourcesBefore = Resource.allCases.map { state.players[actor.index].resources[$0, default: 0] }
        self.resourcesAfter = Resource.allCases.map { after.players[actor.index].resources[$0, default: 0] }
        self.ownVictoryCards = state.players[actor.index].devCards.filter { $0 == .victoryPoint }.count
        self.ownShipsBefore = (state.naval?.ships ?? []).filter { $0.owner == actor }
        self.ownShipsAfter = (after.naval?.ships ?? []).filter { $0.owner == actor }
        self.colonyPoints = Naval.colonyPoints(for: actor, in: state)
        let scores = NavalPolicy(tier: tier, revision: revision).assess(decision.observation, ledger: ledger)
        self.fogRemaining = state.board.tiles.filter { $0.kind == .fog }.count
        self.maxDiscoveryFromLegalSailing = Self.maxDiscovery(in: decision.observation)
        self.bestSailingScore = scores.compactMap { assessment in
            if case .sailShip = assessment.move { return assessment.score }
            return nil
        }.max()
        self.alternatives = scores.enumerated().sorted {
            $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset
        }.prefix(6).map { Alternative(move: Rendering.canonical($0.element.move), score: $0.element.score, reason: $0.element.reason) }
    }

    private static func maxDiscovery(in observation: GameObservation) -> Int {
        let state = observation.state
        let fog = state.board.tiles.filter { $0.kind == .fog }
        return observation.legalMoves.compactMap { move -> Int? in
            guard case .sailShip(let id, let destination) = move,
                  let ship = state.naval?.ships.first(where: { $0.id == id }),
                  let route = Naval.sailingRoute(for: ship, to: destination, in: state) else { return nil }
            return fog.filter { tile in route.contains { tile.coordinate.distance(to: $0) <= Naval.viewingRange } }.count
        }.max() ?? 0
    }
}
