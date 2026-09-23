import Foundation

/// Something the rules did, reported structurally rather than as prose.
///
/// ## Why this replaced `GameState.log: [String]`
/// The engine used to append a human-readable sentence to an array carried
/// *inside* `GameState`. Three problems came out of that, and this type is one
/// change that fixes all three:
///
/// 1. **It made the state expensive to copy.** The array grew to roughly one
///    entry per move - some six thousand by the end of a long game - and
///    `GameState` is a value type that search, simulation and every
///    `GameStore.save` copy or re-encode wholesale. Copy-and-apply measured
///    0.16 microseconds without it and 20.28 with: a 127x tax paid on every
///    move, for text nothing in the engine reads.
/// 2. **It made presentation an engine concern.** Writing "You"/"Player N"
///    forced the engine to have an opinion about which seat a human occupies,
///    which it has no way to know - and that assumption was wrong in three
///    games out of four once seats were randomised.
/// 3. **It coupled the UI to prose.** The board's roll highlight worked by
///    substring-matching `" rolled "` in the log, so rewording a sentence
///    silently broke a visual feature. Matching on `.rolled` cannot break that
///    way.
///
/// Events are returned from `RulesEngine.apply` rather than accumulated in
/// state, so a caller that wants a transcript keeps one and a caller that does
/// not - a search, a self-play harness - pays nothing.
///
/// The seat is carried as a `PlayerID`; rendering it as a name is the UI's job
/// (`CatanTheme.playerLabel(for:)` already resolves the player's real
/// display name, which the engine could never do).
public enum GameEvent: Codable, Sendable, Hashable {
    case placedInitialSettlement(PlayerID)
    case placedInitialRoad(PlayerID)
    case rolled(PlayerID, total: Int)
    case discarded(PlayerID, count: Int)
    case builtRoad(PlayerID)
    case builtSettlement(PlayerID)
    case builtCity(PlayerID)
    case boughtDevCard(PlayerID)
    /// Conquest. Public: everyone sees that a card was bought, never its strength.
    case boughtArmyCard(PlayerID)
    /// Conquest. `result` is the hex's garrison afterwards; `nil` = unoccupied.
    case deployedArmy(PlayerID, hex: HexCoordinate, total: Int, result: Garrison?)
    /// `stealing` is the resource actually taken, which only the engine knows;
    /// `from` is nil when the robber moved with nobody to rob.
    case movedRobber(PlayerID, from: PlayerID?, stealing: Resource?)
    case playedKnight(PlayerID, from: PlayerID?, stealing: Resource?)
    case playedRoadBuilding(PlayerID)
    case playedYearOfPlenty(PlayerID, taken: [Resource: Int])
    case playedMonopoly(PlayerID, resource: Resource, gained: Int)
    case tradedWithBank(PlayerID, gave: [Resource: Int], got: [Resource: Int])
    case proposedTrade(PlayerID, give: [Resource: Int], want: [Resource: Int])
    case acceptedTrade(PlayerID, from: PlayerID, gave: [Resource: Int], got: [Resource: Int])
    case rejectedTrade(PlayerID, from: PlayerID)
    case endedTurn(PlayerID)
    case gameWon(PlayerID)
}

/// Information produced by a move that belongs only to the acting player.
///
/// These values deliberately never enter `GameEvent` or `GameState`: either
/// would expose the face of a development card to every observer. A session
/// hands them to the owning app so it can durably acknowledge the private
/// result before continuing play.
public enum PrivateGameEvent: Sendable, Equatable {
    case boughtDevCard(owner: PlayerID, card: DevCardType)
}

/// One authoritative result from applying a move.
///
/// Keeping public and private events in the same return value means the card
/// placed in a player's hand and the card named by its private receipt can
/// never be inferred by two different callers that later drift apart.
public struct AppliedMoveResult: Sendable, Equatable {
    public let events: [GameEvent]
    public let privateEvents: [PrivateGameEvent]

    public init(events: [GameEvent], privateEvents: [PrivateGameEvent] = []) {
        self.events = events
        self.privateEvents = privateEvents
    }
}

extension GameEvent {
    /// This event as `observer` is entitled to see it.
    ///
    /// ## Why this exists
    /// `movedRobber` and `playedKnight` carry `stealing:` - a resource the
    /// doc comment above describes as one "only the engine knows". Handing
    /// that to every seat makes a card-counting observer strictly better
    /// informed than a human at the same table, which turns any strength
    /// measured against it into a measurement of the leak rather than of the
    /// policy.
    ///
    /// Two seats are entitled to it and no others: the thief, who takes the
    /// card into their own hand, and the victim, who watches it leave theirs.
    /// For everyone else the resource becomes `nil`, which is exactly what a
    /// player at the table observes - a card moved, identity unknown.
    ///
    /// Every other case is already public by construction. A bought
    /// development card reports only that it was bought (`PrivateGameEvent`
    /// carries the face), and a discard reports only a count.
    public func masked(for observer: PlayerID) -> GameEvent {
        switch self {
        case .movedRobber(let actor, let victim, _):
            guard observer != actor, observer != victim else { return self }
            return .movedRobber(actor, from: victim, stealing: nil)
        case .playedKnight(let actor, let victim, _):
            guard observer != actor, observer != victim else { return self }
            return .playedKnight(actor, from: victim, stealing: nil)
        default:
            return self
        }
    }

    /// Whether this event hides something from `observer` that it reveals to
    /// someone else. Used by tests to prove the mask covers every leaking case.
    public var carriesPrivateDetail: Bool {
        switch self {
        case .movedRobber(_, _, let stolen), .playedKnight(_, _, let stolen):
            return stolen != nil
        default:
            return false
        }
    }
}
