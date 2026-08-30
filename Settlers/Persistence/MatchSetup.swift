import Foundation
import CatanEngine

/// Everything chosen on the New Game screen: the match contract.
///
/// ## Why this is one value and not five stores
/// Per-game state was previously split across `HumanSeatStore` (an `Int`) and
/// `CivilizationAssignmentStore` (a file), with two different lifecycles and a
/// live inconsistency: `EndGameView` clears the assignment store and the saved
/// game but *not* the human seat. Adding table size, victory target and
/// per-seat names as three more separate stores would multiply that. One
/// `Codable` value, written once when a game starts and cleared when the game
/// is cleared, cannot get out of step with itself.
///
/// ## Why it is not in `GameState`
/// Because the engine must not learn which seat is a human. That assumption
/// has produced a real bug every time it has been made here - most recently
/// `GameSession.nextActor()` guessing seat 0. The engine knows there are seats
/// and whose turn it is; who is a person and what they are called is the app's
/// business. The one exception is `victoryPointTarget`, which is a *rule* and
/// therefore lives in `GameState` - it is duplicated here only as the value
/// the next game will be started with.
public struct MatchSetup: Codable, Equatable, Sendable {

    /// One chair at the table.
    public struct Seat: Codable, Equatable, Sendable, Identifiable {
        public var id: Int { index }
        /// Seat index, 0-based, matching `PlayerID.index`.
        public var index: Int
        public var isHuman: Bool
        /// The name a human plays under. Empty is invalid for a human seat and
        /// is what `validationProblem` refuses to start on; an AI seat ignores
        /// this and uses its civilization's general.
        public var name: String
        /// `nil` means "draw one at random from the eligible pool at start".
        public var civilization: Civilization?

        public init(index: Int, isHuman: Bool, name: String, civilization: Civilization?) {
            self.index = index
            self.isHuman = isHuman
            self.name = name
            self.civilization = civilization
        }
    }

    public var seats: [Seat]
    public var victoryPointTarget: Int
    public var randomizedBoard: Bool
    public var randomizeSeatOrder: Bool

    public init(seats: [Seat], victoryPointTarget: Int,
                randomizedBoard: Bool, randomizeSeatOrder: Bool) {
        self.seats = seats
        self.victoryPointTarget = victoryPointTarget
        self.randomizedBoard = randomizedBoard
        self.randomizeSeatOrder = randomizeSeatOrder
    }

    // MARK: - Validity

    /// Why this setup cannot start a game, or `nil` if it can.
    ///
    /// One function rather than a scatter of `isValid` flags, because the
    /// button needs to say *what* is wrong, not merely go grey. A control that
    /// is disabled without saying why is the same failure as a setting that
    /// silently does nothing.
    public var validationProblem: String? {
        guard GameSetup.supportedPlayerCounts.contains(seats.count) else {
            return "A game needs \(GameSetup.supportedPlayerCounts.lowerBound) or "
                + "\(GameSetup.supportedPlayerCounts.upperBound) players."
        }
        guard humanSeats.contains(where: { _ in true }) else {
            return "At least one seat must be a human player."
        }
        if let unnamed = humanSeats.first(where: { $0.name.trimmed.isEmpty }) {
            return "Seat \(unnamed.index + 1) needs a name."
        }
        let names = humanSeats.map { $0.name.trimmed.lowercased() }
        if Set(names).count != names.count {
            return "Two players share a name."
        }
        let chosen = seats.compactMap(\.civilization)
        if Set(chosen).count != chosen.count {
            return "Two seats share a civilization."
        }
        guard WinCondition.supportedTargets.contains(victoryPointTarget) else {
            return "That match length is not available."
        }
        return nil
    }

    public var isStartable: Bool { validationProblem == nil }

    public var humanSeats: [Seat] { seats.filter(\.isHuman) }
    public var aiSeats: [Seat] { seats.filter { !$0.isHuman } }

    /// Civilizations a picker must show as already taken, excluding `seat`'s
    /// own choice so re-opening a picker does not grey out the current pick.
    public func civilizationsTaken(excluding seat: Int) -> Set<Civilization> {
        Set(seats.filter { $0.index != seat }.compactMap(\.civilization))
    }

    // MARK: - Defaults

    /// A setup a first-time player can start without touching anything except
    /// their name: four seats, one human, standard everything.
    public static func `default`(preferredName: String, preferredCivilization: Civilization) -> MatchSetup {
        var setup = MatchSetup(
            seats: [],
            victoryPointTarget: WinCondition.standardTarget,
            randomizedBoard: true,
            randomizeSeatOrder: true
        )
        setup.resize(to: GameSetup.standardPlayerCount,
                     preferredName: preferredName,
                     preferredCivilization: preferredCivilization)
        return setup
    }

    /// Grows or shrinks the table, preserving what the player already chose.
    ///
    /// Shrinking drops the highest seats, which is why the New Game screen
    /// marks seat 4 "optional" - it is the one that disappears. Growing adds AI
    /// seats, since a human who wants that chair can flip it and the reverse
    /// would silently add a seat nobody is sitting in.
    public mutating func resize(to count: Int, preferredName: String, preferredCivilization: Civilization) {
        precondition(GameSetup.supportedPlayerCounts.contains(count))
        if seats.count > count {
            seats = Array(seats.prefix(count))
            // Shrinking must not leave a table with no human in it.
            if !seats.contains(where: \.isHuman) { seats[0].isHuman = true }
            if seats[0].name.trimmed.isEmpty { seats[0].name = preferredName }
            return
        }
        while seats.count < count {
            let index = seats.count
            seats.append(Seat(
                index: index,
                isHuman: index == 0,
                name: index == 0 ? preferredName : "",
                civilization: index == 0 ? preferredCivilization : nil
            ))
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Persists the setup the current game was started with, and the one to
/// prefill the New Game screen with next time.
///
/// `UserDefaults`, matching every other preference store here. It is small,
/// it is not sensitive, and a lost setup costs one screen of re-entry.
public final class MatchSetupStore: @unchecked Sendable {
    public static let shared = MatchSetupStore()

    /// Overridable so a test can point at its own container rather than
    /// trampling the developer's simulator, which an app test has done before.
    public var defaults: UserDefaults = .standard

    private let key = "matchSetup"

    public func load() -> MatchSetup? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MatchSetup.self, from: data)
    }

    public func save(_ setup: MatchSetup) {
        guard let data = try? JSONEncoder().encode(setup) else { return }
        defaults.set(data, forKey: key)
    }

    public func clear() { defaults.removeObject(forKey: key) }
}
