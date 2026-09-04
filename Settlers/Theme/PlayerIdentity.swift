import Foundation
import CatanEngine

/// The complete presentation identity for one occupied chair.
///
/// A seat used to be resolved piecemeal at each view: the name came from one
/// closure, the civilization from a process-global array, the color from a
/// theme helper, and the icon from an unrelated SF Symbol. That made a
/// visually impossible combination representable — a card could say Egypt,
/// look green, and show a sun while the board used an orange pyramid.
///
/// Views receive this value instead. The civilization is the root of the
/// color, painted piece and dialogue voice, while the controller decides
/// whether the visible name is a person's match name or an opponent profile.
/// The engine still knows none of this; identity remains an app-layer concern.
public struct PlayerIdentity: Identifiable, Sendable, Equatable {
    public enum Controller: Sendable, Equatable {
        case human
        case computer
    }

    public var id: PlayerID { seat }
    public let seat: PlayerID
    public let displayName: String
    public let civilization: Civilization
    public let controller: Controller

    public init(seat: PlayerID, displayName: String,
                civilization: Civilization, controller: Controller) {
        precondition(!displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                     "A visible player identity needs a name")
        self.seat = seat
        self.displayName = displayName
        self.civilization = civilization
        self.controller = controller
    }

    /// The exact settlement artwork used for this civilization on the board.
    /// UI crests use this rather than a second, symbolic logo vocabulary.
    public var pieceImageName: String? {
        civilization.paintedPieceImageName(isCity: false)
    }

    public var accessibilityLabel: String {
        let role = controller == .human ? "human player" : "computer player"
        return "\(displayName), \(civilization.displayName), \(role)"
    }
}

/// The complete, match-scoped presentation roster.
///
/// `MatchSetup` is the durable source and this is its validated runtime view.
/// Keeping the whole map together makes it impossible for a screen to combine
/// a name from an opponent snapshot with a color or crest from a stale global
/// seat assignment. `seatAtDevice` deliberately does not live here: passing a
/// phone changes who may interact, never who is sitting at the table.
struct PlayerRoster: Sendable, Equatable {
    private let identities: [PlayerID: PlayerIdentity]
    let opponentProfiles: [PlayerID: OpponentProfile]

    var humanSeats: Set<PlayerID> {
        Set(identities.values.filter { $0.controller == .human }.map(\.seat))
    }

    var humanNames: [PlayerID: String] {
        Dictionary(uniqueKeysWithValues: identities.values.compactMap { identity in
            identity.controller == .human ? (identity.seat, identity.displayName) : nil
        })
    }

    init(realizedSetup setup: MatchSetup) {
        precondition(setup.realizedIdentityProblem == nil,
                     "A player roster needs a complete realized identity setup")
        var identities: [PlayerID: PlayerIdentity] = [:]
        var profiles: [PlayerID: OpponentProfile] = [:]
        for chair in setup.seats {
            let seat = PlayerID(index: chair.index)
            guard let civilization = chair.civilization else {
                preconditionFailure("Every realized chair needs a civilization")
            }
            if chair.isHuman {
                precondition(chair.opponentProfile == nil,
                             "A human chair cannot also contain an opponent profile")
                identities[seat] = PlayerIdentity(
                    seat: seat, displayName: chair.name,
                    civilization: civilization, controller: .human
                )
            } else {
                guard let profile = chair.opponentProfile else {
                    preconditionFailure("Every realized computer chair needs an opponent profile")
                }
                precondition(profile.civilization == civilization,
                             "A computer profile and chair civilization must agree")
                profiles[seat] = profile
                identities[seat] = PlayerIdentity(
                    seat: seat, displayName: profile.name,
                    civilization: profile.civilization, controller: .computer
                )
            }
        }
        self.identities = identities
        self.opponentProfiles = profiles
    }

    init(playerIDs: [PlayerID], humanSeats: Set<PlayerID>,
         humanNames: [PlayerID: String], civilizations: [Civilization],
         opponentProfiles: [PlayerID: OpponentProfile]) {
        precondition(humanSeats.isDisjoint(with: opponentProfiles.keys),
                     "A chair cannot be both human and computer controlled")
        precondition(Set(playerIDs) == humanSeats.union(opponentProfiles.keys),
                     "Every occupied chair must have exactly one controller")
        precondition(civilizations.count == playerIDs.count,
                     "Every occupied chair needs a civilization")
        let chairs = playerIDs.map { seat -> MatchSetup.Seat in
            let civilization = civilizations[seat.index]
            if humanSeats.contains(seat) {
                guard let name = humanNames[seat] else {
                    preconditionFailure("Every human chair needs a match name")
                }
                return MatchSetup.Seat(
                    index: seat.index, isHuman: true, name: name,
                    civilization: civilization
                )
            }
            guard let profile = opponentProfiles[seat] else {
                preconditionFailure("Every computer chair needs an opponent profile")
            }
            return MatchSetup.Seat(
                index: seat.index, isHuman: false, name: "",
                civilization: civilization, opponentProfile: profile
            )
        }
        self.init(realizedSetup: MatchSetup(
            seats: chairs, victoryPointTarget: WinCondition.standardTarget,
            randomizedBoard: false, randomizeSeatOrder: false
        ))
    }

    func identity(for seat: PlayerID) -> PlayerIdentity {
        guard let identity = identities[seat] else {
            preconditionFailure("Only occupied chairs have player identities")
        }
        return identity
    }
}
