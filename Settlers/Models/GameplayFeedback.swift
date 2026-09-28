import Foundation
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
    }

    let id = UUID()
    let kind: Kind
    let pointChanges: [PlayerID: Int]
    let occurredAt: Date

    static func committed(events: [GameEvent], before: GameState, after: GameState,
                          viewer: PlayerID, now: Date = Date()) -> [Self] {
        guard !events.isEmpty, before != after else { return [] }
        let changes = pointChanges(before: before, after: after, viewer: viewer)
        var kinds = events.compactMap(cardKind)
        if before.longestRoadPlayer != after.longestRoadPlayer {
            kinds.append(.longestRoad(previous: before.longestRoadPlayer, holder: after.longestRoadPlayer))
        }
        if before.largestArmyPlayer != after.largestArmyPlayer {
            kinds.append(.largestArmy(previous: before.largestArmyPlayer, holder: after.largestArmyPlayer))
        }
        if kinds.isEmpty, let seat = changes.keys.sorted().first { kinds.append(.points(seat)) }
        // Show the exact net score changes once, on the final notice for this
        // move: e.g. Knight, then Largest Army with +2 (and the old holder -2).
        return kinds.enumerated().map { index, kind in
            Self(kind: kind, pointChanges: index == kinds.count - 1 ? changes : [:], occurredAt: now)
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

    private static func cardKind(_ event: GameEvent) -> Kind? {
        switch event {
        case .playedKnight(let player, _, _): .card(player, .knight)
        case .playedRoadBuilding(let player): .card(player, .roadBuilding)
        case .playedYearOfPlenty(let player, _): .card(player, .yearOfPlenty)
        case .playedMonopoly(let player, _, _): .card(player, .monopoly)
        default: nil
        }
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
            deadline = current.map { _ in now.addingTimeInterval(remaining) }
        }
    }

    mutating func suspend(_ value: Bool, now: Date = Date()) {
        guard value != isSuspended else { return }
        if value { remaining = max(0, deadline?.timeIntervalSince(now) ?? Self.displaySeconds) }
        isSuspended = value
        deadline = value ? nil : current.map { _ in now.addingTimeInterval(remaining) }
        advance(now: now)
    }

    mutating func clear() { self = Self() }
}
