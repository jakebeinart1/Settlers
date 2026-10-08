import Foundation
import CatanEngine

/// A public ownership transfer owed to an involved human. It is saved beside
/// the match, not inside its engine state, so acknowledgement cannot change
/// rules or replay. Identity and location bind the receipt to the real hull.
public struct NavalShipCaptureReceipt: Codable, Sendable, Equatable {
    public let reader: PlayerID
    public let shipID: Int
    public let previousOwner: PlayerID
    public let newOwner: PlayerID
    public let coordinate: HexCoordinate

    static func committed(_ event: GameEvent, in state: GameState,
                          humanSeats: Set<PlayerID>) -> Self? {
        guard case .capturedShip(let owner, let id, let previous) = event,
              humanSeats.contains(previous) || humanSeats.contains(owner),
              let ship = state.naval?.ships.first(where: { $0.id == id }),
              ship.owner == owner else { return nil }
        return Self(reader: humanSeats.contains(previous) ? previous : owner,
                    shipID: id, previousOwner: previous, newOwner: owner, coordinate: ship.coordinate)
    }

    func matches(_ event: GameEvent, in state: GameState) -> Bool {
        event == .capturedShip(newOwner, shipID: shipID, from: previousOwner)
            && state.naval?.ships.contains {
                $0.id == shipID && $0.owner == newOwner && $0.coordinate == coordinate
            } == true
    }

    var title: String { reader == previousOwner ? "Your ship was stolen" : "You took control of a ship" }
}
