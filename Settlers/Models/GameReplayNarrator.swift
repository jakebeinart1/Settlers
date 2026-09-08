import Foundation
import CatanEngine

/// Turns a move's `GameEvent` transcript into the one line the replay screen
/// shows under the board.
///
/// ## Why events and not the move
/// `GameMove` is a request; `GameEvent` is what the rules actually did. Only
/// the events know the dice total behind `.rollDice`, the resource a Monopoly
/// took and how much of it, and whether a robber move found anybody to steal
/// from. Narrating the move instead would print "rolled the dice" for the one
/// event in the game a spectator most wants the number for.
///
/// ## Why it lives here and not in `CatanEngine`
/// This is prose about seats, and the engine has no notion of who a seat is -
/// deliberately, and at the cost of a bug that once had it calling bots "You"
/// (see `GameEvent`'s own doc comment). Names come from the recording's
/// roster, which is presentation data the engine never sees.
enum GameReplayNarrator {
    static func headline(for events: [GameEvent], move: GameMove, actor: PlayerID,
                         roster: GameLogStore.SeatRoster) -> String {
        let phrases = events.compactMap { phrase(for: $0, roster: roster) }
        guard !phrases.isEmpty else { return fallback(for: move, actor: actor, roster: roster) }
        return phrases.joined(separator: " · ")
    }

    private static func phrase(for event: GameEvent, roster: GameLogStore.SeatRoster) -> String? {
        switch event {
        case .placedInitialSettlement(let player):
            return "\(name(player, roster)) founded a settlement"
        case .placedInitialRoad(let player):
            return "\(name(player, roster)) laid a road"
        case .rolled(let player, let total):
            return "\(name(player, roster)) rolled \(total)"
        case .discarded(let player, let count):
            return "\(name(player, roster)) discarded \(count) \(cards(count))"
        case .builtRoad(let player):
            return "\(name(player, roster)) built a road"
        case .builtSettlement(let player):
            return "\(name(player, roster)) built a settlement"
        case .builtCity(let player):
            return "\(name(player, roster)) raised a city"
        case .boughtDevCard(let player):
            return "\(name(player, roster)) bought a development card"
        case .movedRobber(let player, let victim, let stolen):
            return "\(name(player, roster)) moved the robber" + theft(victim, stolen, roster)
        case .playedKnight(let player, let victim, let stolen):
            return "\(name(player, roster)) played a Knight" + theft(victim, stolen, roster)
        case .playedRoadBuilding(let player):
            return "\(name(player, roster)) played Road Building"
        case .playedYearOfPlenty(let player, let taken):
            return "\(name(player, roster)) played Year of Plenty for \(list(taken))"
        case .playedMonopoly(let player, let resource, let gained):
            return "\(name(player, roster)) monopolised \(resource.rawValue), taking \(gained)"
        case .tradedWithBank(let player, let gave, let got):
            return "\(name(player, roster)) traded \(list(gave)) to the bank for \(list(got))"
        case .proposedTrade(let player, let give, let want):
            return "\(name(player, roster)) offered \(list(give)) for \(list(want))"
        case .acceptedTrade(let player, let proposer, let gave, let got):
            return "\(name(player, roster)) gave \(list(gave)) to "
                + "\(name(proposer, roster)) for \(list(got))"
        case .rejectedTrade(let player, let proposer):
            return "\(name(player, roster)) declined \(name(proposer, roster))'s offer"
        case .endedTurn(let player):
            return "\(name(player, roster)) ended their turn"
        case .gameWon(let player):
            return "\(name(player, roster)) wins"
        }
    }

    /// A move that produced no events still happened, and a blank line under
    /// the board reads as a broken screen rather than a quiet move.
    private static func fallback(for move: GameMove, actor: PlayerID,
                                 roster: GameLogStore.SeatRoster) -> String {
        if case .respondToTrade(_, let accept) = move {
            return "\(name(actor, roster)) \(accept ? "accepted" : "declined") a trade"
        }
        return "\(name(actor, roster)) moved"
    }

    private static func theft(_ victim: PlayerID?, _ stolen: Resource?,
                              _ roster: GameLogStore.SeatRoster) -> String {
        guard let victim else { return "" }
        guard let stolen else { return " and robbed \(name(victim, roster))" }
        return " and took \(stolen.rawValue) from \(name(victim, roster))"
    }

    /// `Resource.allCases` order, never the dictionary's: `[Resource: Int]`
    /// iterates in a per-process order, so the same archived move would
    /// otherwise narrate differently between two launches.
    private static func list(_ table: [Resource: Int]) -> String {
        let parts = Resource.allCases.compactMap { resource -> String? in
            guard let count = table[resource], count > 0 else { return nil }
            return "\(count) \(resource.rawValue)"
        }
        return parts.isEmpty ? "nothing" : parts.joined(separator: ", ")
    }

    private static func cards(_ count: Int) -> String { count == 1 ? "card" : "cards" }

    private static func name(_ player: PlayerID, _ roster: GameLogStore.SeatRoster) -> String {
        roster.displayName(for: player)
    }
}
