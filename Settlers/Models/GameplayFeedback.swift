import Foundation
import SwiftUI
import CatanEngine

/// Public, post-commit table news. Never infer a card's face from a purchase,
/// or an opponent's score from their private hand. Net before/after scores also
/// prevent counting a city upgrade as +2 instead of its actual +1.
struct GameplayFeedback: Identifiable, Equatable {
    enum Kind: Equatable {
        case card(PlayerID, DevCardType)
        case longestRoad(previous: PlayerID?, holder: PlayerID?)
        case largestArmy(previous: PlayerID?, holder: PlayerID?)
        case points(PlayerID)
        /// A robber or Knight steal. `resource` is set only when the viewer
        /// is the thief or the victim - nobody else at a real table sees it.
        case robbed(thief: PlayerID, victim: PlayerID, resource: Resource?)
        case launched(PlayerID, Int)
        case captured(PlayerID, Int, PlayerID)
        case colony(PlayerID)
        case harvest(PlayerID, Resource)
        case traded(PlayerID, PlayerID)
    }

    let id = UUID()
    let kind: Kind
    let pointChanges: [PlayerID: Int]
    let occurredAt: Date
    /// Public cards that changed hands with a card play (Monopoly's haul,
    /// Year of Plenty's picks), drawn as squares after the title.
    var detail: [Resource: Int] = [:]

    static func committed(events: [GameEvent], before: GameState, after: GameState,
                          viewer: PlayerID, now: Date = Date()) -> [Self] {
        guard !events.isEmpty, before != after else { return [] }
        let changes = pointChanges(before: before, after: after, viewer: viewer)
        var kinds = events.flatMap { news(for: $0, viewer: viewer) } + events.compactMap(navalKind)
            + events.compactMap { tradeKind($0, viewer: viewer) }
        if before.longestRoadPlayer != after.longestRoadPlayer {
            kinds.append(.longestRoad(previous: before.longestRoadPlayer, holder: after.longestRoadPlayer))
        }
        if before.largestArmyPlayer != after.largestArmyPlayer {
            kinds.append(.largestArmy(previous: before.largestArmyPlayer, holder: after.largestArmyPlayer))
        }
        if kinds.isEmpty, let seat = changes.keys.sorted().first { kinds.append(.points(seat)) }
        let details = Dictionary(events.compactMap(cardDetail), uniquingKeysWith: { first, _ in first })
        // Show the exact net score changes once, on the final notice for this
        // move: e.g. Knight, then Largest Army with +2 (and the old holder -2).
        return kinds.enumerated().map { index, kind in
            var notice = Self(kind: kind, pointChanges: index == kinds.count - 1 ? changes : [:], occurredAt: now)
            if case .card(_, let card) = kind { notice.detail = details[card] ?? [:] }
            return notice
        }
    }

    func title(name: (PlayerID) -> String) -> String {
        switch kind {
        case .card(let player, let card): return "\(name(player)) played \(DevCardStyle.fullName(for: card))"
        case .longestRoad(let previous, let holder): return bonusTitle("Longest Road", previous, holder, name)
        case .largestArmy(let previous, let holder): return bonusTitle("Largest Army", previous, holder, name)
        case .points(let player):
            let change = pointChanges[player, default: 0]
            return "\(name(player)) \(change > 0 ? "gained" : "lost") \(abs(change)) VP"
        case .robbed(let thief, let victim, let resource):
            let taken = resource.map { "1 \($0.rawValue.capitalized)" } ?? "a card"
            return "\(name(thief)) stole \(taken) from \(name(victim))"
        case .launched(let player, _): return "\(name(player)) launched a ship"
        case .captured(let player, _, let previous):
            return "\(name(player)) captured \(name(previous))’s ship"
        case .colony(let player): return "\(name(player)) established a new colony"
        case .harvest(let player, let resource): return "\(name(player)) harvested \(resource.rawValue.capitalized)"
        case .traded(let proposer, let recipient): return "\(name(proposer)) traded with \(name(recipient))"
        }
    }

    /// `title` with every named resource drawn beside its colour square.
    func label(name: (PlayerID) -> String) -> Text {
        switch kind {
        case .robbed(let thief, let victim, let resource?):
            return Text("\(name(thief)) stole ") + ResourceText.term(resource, count: 1) + Text(" from \(name(victim))")
        case .card where !detail.isEmpty:
            return Text(title(name: name) + " · ") + ResourceText.list(detail)
        case .harvest(let player, let resource):
            return Text("\(name(player)) harvested ") + ResourceText.term(resource, count: 1)
        default:
            return Text(title(name: name))
        }
    }

    func scoreSummary(name: (PlayerID) -> String) -> String {
        pointChanges.keys.sorted().map { "\(name($0)) \(Self.signed(pointChanges[$0]!)) VP" }.joined(separator: ", ")
    }

    var symbol: String {
        switch kind {
        case .card: "rectangle.stack.fill"
        case .longestRoad: "road.lanes"
        case .largestArmy: "shield.fill"
        case .points: "star.fill"
        case .robbed: "hand.raised.fill"
        case .launched, .captured: "sailboat.fill"
        case .colony: "flag.fill"
        case .harvest: "sun.max.fill"
        case .traded: "arrow.left.arrow.right"
        }
    }

    static func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "−\(abs(value))" }

    private func bonusTitle(_ bonus: String, _ previous: PlayerID?, _ holder: PlayerID?,
                            _ name: (PlayerID) -> String) -> String {
        if let holder, let previous { return "\(name(holder)) took \(bonus) from \(name(previous))" }
        if let holder { return "\(name(holder)) earned \(bonus)" }
        return previous.map { "\(name($0)) lost \(bonus)" } ?? bonus
    }

    private static func pointChanges(before: GameState, after: GameState, viewer: PlayerID) -> [PlayerID: Int] {
        var changes: [PlayerID: Int] = [:]
        for player in after.players {
            let old = player.id == viewer ? before.victoryPoints(for: viewer) : before.publicVictoryPoints(for: player.id)
            let new = player.id == viewer ? after.victoryPoints(for: viewer) : after.publicVictoryPoints(for: player.id)
            if old != new { changes[player.id] = new - old }
        }
        return changes
    }

    private static func news(for event: GameEvent, viewer: PlayerID) -> [Kind] {
        switch event {
        case .playedKnight(let player, let victim, let stolen):
            [.card(player, .knight)] + robbery(player, victim, stolen, viewer: viewer)
        case .movedRobber(let player, let victim, let stolen): robbery(player, victim, stolen, viewer: viewer)
        case .playedRoadBuilding(let player): [.card(player, .roadBuilding)]
        case .playedYearOfPlenty(let player, _): [.card(player, .yearOfPlenty)]
        case .playedMonopoly(let player, _, _): [.card(player, .monopoly)]
        default: []
        }
    }

    private static func robbery(_ thief: PlayerID, _ victim: PlayerID?, _ stolen: Resource?,
                                viewer: PlayerID) -> [Kind] {
        guard let victim else { return [] }
        let isParty = viewer == thief || viewer == victim
        return [.robbed(thief: thief, victim: victim, resource: isParty ? stolen : nil)]
    }

    private static func cardDetail(_ event: GameEvent) -> (DevCardType, [Resource: Int])? {
        switch event {
        case .playedYearOfPlenty(_, let taken): (.yearOfPlenty, taken)
        case .playedMonopoly(_, let resource, let gained) where gained > 0: (.monopoly, [resource: gained])
        default: nil
        }
    }

    private static func navalKind(_ event: GameEvent) -> Kind? {
        switch event {
        case .builtShip(let player, let id, _): .launched(player, id)
        case .capturedShip(let player, let id, let previous): .captured(player, id, previous)
        case .earnedColonyPoint(let player, _): .colony(player)
        case .choseResource(let player, let resource): .harvest(player, resource)
        default: nil
        }
    }

    /// A player who lost an acceptance draw still needs the table's outcome.
    /// Their own completed exchange already has a detailed trade receipt.
    private static func tradeKind(_ event: GameEvent, viewer: PlayerID) -> Kind? {
        guard case .acceptedTrade(let recipient, let proposer, _, _) = event,
              recipient != viewer, proposer != viewer else { return nil }
        return .traded(proposer, recipient)
    }
}

/// A small FIFO, not a log and not a gameplay gate. Rapid bot actions cannot
/// replace the currently readable notice. A bounded tail and age limit prevent
/// an old turn's news resurfacing after a lengthy modal or mandatory decision.
/// The view drives its single deadline; tests use an explicit clock.
struct GameplayFeedbackQueue {
    static let displaySeconds: TimeInterval = 4
    static let maximumAge: TimeInterval = 24
    static let maximumPending = 5

    private(set) var current: GameplayFeedback?
    private(set) var pending: [GameplayFeedback] = []
    private(set) var deadline: Date?
    private(set) var isSuspended = false
    private var remaining = displaySeconds

    var visible: GameplayFeedback? { isSuspended ? nil : current }

    mutating func enqueue(_ items: [GameplayFeedback], now: Date = Date()) {
        pending += items
        pending = Array(pending.suffix(Self.maximumPending))
        advance(now: now)
    }

    mutating func advance(now: Date = Date()) {
        pending.removeAll { now.timeIntervalSince($0.occurredAt) >= Self.maximumAge }
        if let current, now.timeIntervalSince(current.occurredAt) >= Self.maximumAge {
            self.current = nil
        }
        if let deadline, now >= deadline { current = nil }
        guard !isSuspended else { deadline = nil; return }
        if current == nil {
            current = pending.isEmpty ? nil : pending.removeFirst()
            remaining = Self.displaySeconds
            deadline = readingDeadline(now: now)
        }
    }

    mutating func suspend(_ value: Bool, now: Date = Date()) {
        guard value != isSuspended else { return }
        if value { remaining = max(0, deadline?.timeIntervalSince(now) ?? Self.displaySeconds) }
        isSuspended = value
        deadline = value ? nil : readingDeadline(now: now)
        advance(now: now)
    }

    /// Reading time can pause, but the age limit cannot. Cap the scheduled wake
    /// itself so stale news disappears without requiring another game event.
    private func readingDeadline(now: Date) -> Date? {
        current.map { min(now.addingTimeInterval(remaining), $0.occurredAt.addingTimeInterval(Self.maximumAge)) }
    }

    /// Forget news, not the view's hold. Backgrounding can leave the same card
    /// surface open, so its unchanged hold predicate will not fire onChange.
    mutating func clear() {
        current = nil
        pending = []
        deadline = nil
        remaining = Self.displaySeconds
    }
}
