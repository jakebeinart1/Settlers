import Foundation
import CatanEngine

/// Read-only travel information for a confirmed legal destination mask.
/// Routes come from the engine's versioned public-sea query; staging a route
/// never moves a ship, reveals terrain or spends its remaining allowance.
public struct NavalSailingPresentation: Sendable, Equatable {
    public let allowance: Int
    public let remaining: Int?
    public let routes: [HexCoordinate: [HexCoordinate]]
    public let selectedRoute: [HexCoordinate]

    init?(state: GameState, decision: BoardDecisionPresentation) {
        guard decision.intent == .sailShip, state.naval != nil else { return nil }
        allowance = Naval.movementPerTurn(in: state)
        let ship = state.naval?.ships.first { $0.id == decision.selectedShip }
        remaining = ship?.stepsRemaining
        let validRoutes = Self.routes(for: ship, destinations: decision.legalTiles, state: state)
        routes = validRoutes
        selectedRoute = decision.selectedTile.flatMap { validRoutes[$0] } ?? []
    }

    private static func routes(for ship: Ship?, destinations: [HexCoordinate],
                               state: GameState) -> [HexCoordinate: [HexCoordinate]] {
        guard let ship else { return [:] }
        return Dictionary(uniqueKeysWithValues: destinations.map { destination in
            guard let route = Naval.sailingRoute(for: ship, to: destination, in: state) else {
                preconditionFailure("legal sailing destination has no public route")
            }
            return (destination, route)
        })
    }

    var detail: String {
        guard let remaining else { return "Choose a ship. Up to \(NavalQuantityText.hexes(allowance)) per turn." }
        guard !selectedRoute.isEmpty else {
            return "\(NavalQuantityText.hexes(remaining)) left this turn. Numbers show travel cost."
        }
        return "Sail \(NavalQuantityText.hexes(selectedRoute.count)). \(remaining - selectedRoute.count) left afterward."
    }
}
