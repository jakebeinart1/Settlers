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
        /// Snapshot of the computer opponent actually occupying this chair.
        /// Nil on a human seat and on old/new-game prefills; populated in the
        /// realized active-match record after Random choices are resolved.
        public var opponentProfile: OpponentProfile?
        /// The ghost playing this chair, by `GhostProfile.id`, or `nil` for an
        /// ordinary AI or the human. Optional, so every setup saved before
        /// ghosts existed decodes as "no ghost".
        public var ghostID: String?

        public init(index: Int, isHuman: Bool, name: String, civilization: Civilization?,
                    opponentProfile: OpponentProfile? = nil, ghostID: String? = nil) {
            self.index = index
            self.isHuman = isHuman
            self.name = name
            self.civilization = civilization
            self.opponentProfile = opponentProfile
            self.ghostID = ghostID
        }
    }

    public var seats: [Seat]
    /// The rule set this match is played under. Duplicated from `GameState`
    /// for the same reason `victoryPointTarget` is: it is the value the next
    /// game will be started with, and the running game owns its own copy.
    public var mode: GameMode
    public var victoryPointTarget: Int
    public var randomizedBoard: Bool
    public var randomizeSeatOrder: Bool
    /// How strong the computer opponents play.
    ///
    /// Stored with the match rather than as a global preference, for the same
    /// reason `mode` and `victoryPointTarget` are: it decides how the game is
    /// played, so a running game must keep the opponents it was started with.
    /// A preference read live would swap every bot's brain mid-match on the
    /// next resume, which is a rule change disguised as a setting.
    public var difficulty: BotDifficulty
    /// The rule layer - Standard or Conquest - over the chosen board. Stored with
    /// the match for the same reason `mode` is: a running game keeps its rules.
    public var variant: GameVariant

    public init(seats: [Seat], mode: GameMode = .classic, victoryPointTarget: Int,
                randomizedBoard: Bool, randomizeSeatOrder: Bool,
                difficulty: BotDifficulty = .default, variant: GameVariant = .standard) {
        self.seats = seats
        self.mode = mode
        self.victoryPointTarget = victoryPointTarget
        self.randomizedBoard = randomizedBoard
        self.randomizeSeatOrder = randomizeSeatOrder
        self.difficulty = difficulty
        self.variant = variant
    }

    /// Hand-written for one field. `MatchSetup` is written to disk beside a
    /// running game, so a setup saved before modes existed must still decode -
    /// the synthesized initializer would throw on the missing key and take the
    /// player's configured table with it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seats = try container.decode([Seat].self, forKey: .seats)
        mode = try container.decodeIfPresent(GameMode.self, forKey: .mode) ?? .classic
        victoryPointTarget = try container.decode(Int.self, forKey: .victoryPointTarget)
        randomizedBoard = try container.decode(Bool.self, forKey: .randomizedBoard)
        randomizeSeatOrder = try container.decode(Bool.self, forKey: .randomizeSeatOrder)
        // Absent in every setup written before difficulty existed. Those games
        // were played against the heuristic and must resume against it.
        difficulty = try container.decodeIfPresent(BotDifficulty.self, forKey: .difficulty) ?? .default
        // Absent in every setup written before Conquest. Those were standard games.
        variant = try container.decodeIfPresent(GameVariant.self, forKey: .variant) ?? .standard
    }

    // MARK: - Validity

    /// Restoration uses array positions for identities and stored indices for
    /// human seats. Reject disagreement rather than sorting or renumbering it,
    /// which could silently assign a saved person's chair to a different player.
    var hasOrderedSeatIndices: Bool {
        seats.map(\.index).elementsEqual(seats.indices)
    }

    /// Why this setup is not a coherent match, or `nil` if it is.
    ///
    /// This deliberately excludes product-level restrictions on creating a
    /// *new* match. A checkpoint written by an older build must remain
    /// resumable even when the current New Game screen no longer offers that
    /// exact rules combination.
    public var matchProblem: String? {
        guard GameSetup.supportedPlayerCounts.contains(seats.count) else {
            return "A game needs \(GameSetup.supportedPlayerCounts.lowerBound) or "
                + "\(GameSetup.supportedPlayerCounts.upperBound) players."
        }
        guard hasOrderedSeatIndices else {
            return "Seat indices must match their table positions."
        }
        guard !humanSeats.isEmpty else {
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
        guard Ruleset.forMode(mode).victoryPointTargets.contains(victoryPointTarget) else {
            return "That match length is not available in \(mode.displayName)."
        }
        return nil
    }

    /// Why this setup cannot start a new game, or `nil` if it can.
    ///
    /// One function rather than a scatter of `isValid` flags, because the
    /// button needs to say *what* is wrong, not merely go grey. A control that
    /// is disabled without saying why is the same failure as a setting that
    /// silently does nothing.
    public var validationProblem: String? {
        if let matchProblem { return matchProblem }
        if let identityConflictProblem { return identityConflictProblem }
        guard Self.newGameVictoryPointTargets(for: seats.count, mode: mode).contains(victoryPointTarget) else {
            // Named by mode, not by table size: the target is a consequence of
            // the mode now, and the table is fixed at four.
            return "\(mode.displayName) is played to "
                + "\(Self.newGameVictoryPointTargets(for: seats.count, mode: mode).map(String.init).joined(separator: " or "))."
        }
        return nil
    }

    /// Why the New Game screen cannot start this table, or `nil` if it can.
    ///
    /// Stricter than `validationProblem`, which a restart also uses: Jake
    /// removed pass-and-play (2026-09-25), so a new game has exactly one
    /// human, in seat 1. `matchProblem` still accepts several humans, so an
    /// old pass-and-play save resumes and finishes.
    ///
    /// Ghosts are fitted on Classic standard games, so they play only there.
    /// `knownGhosts` is what the phone can seat right now; a ghost that has
    /// gone (an update dropped a bundled one) is refused by seat.
    public func newGameProblem(knownGhosts: Set<String>) -> String? {
        if let validationProblem { return validationProblem }
        guard humanSeats.count == 1, seats.first?.isHuman == true else {
            return "Pass-and-play has been removed. Seat 1 is you."
        }
        if let seat = seats.first(where: { $0.isHuman && $0.ghostID != nil }) {
            return "Seat \(seat.index + 1) cannot be both you and a ghost."
        }
        let ghostSeats = seats.filter { $0.ghostID != nil }
        guard !ghostSeats.isEmpty else { return nil }
        guard mode == .classic, variant == .standard else { return "Ghosts play Classic only." }
        let ids = ghostSeats.compactMap(\.ghostID)
        guard Set(ids).count == ids.count else { return "A ghost can only take one seat." }
        if let seat = ghostSeats.first(where: { !knownGhosts.contains($0.ghostID ?? "") }) {
            return "Seat \(seat.index + 1)'s ghost is no longer on this phone."
        }
        return nil
    }

    public var isValidMatch: Bool { matchProblem == nil }
    public var isStartable: Bool { validationProblem == nil }

    /// Why this setup cannot be the realized identity roster stored beside a
    /// running match. New-game input may leave civilizations and profiles
    /// unresolved; a checkpoint may not. Keeping this validation on the value
    /// prevents persistence, recovery, logging and presentation from each
    /// inventing a slightly different definition of a complete roster.
    var realizedIdentityProblem: String? {
        if let matchProblem { return matchProblem }
        if let seat = seats.first(where: { $0.civilization == nil }) {
            return "Seat \(seat.index + 1) has no realized civilization."
        }
        if let identityConflictProblem { return identityConflictProblem }
        if let seat = seats.first(where: { !$0.isHuman && $0.opponentProfile == nil }) {
            return "Seat \(seat.index + 1) has no realized AI opponent."
        }
        return nil
    }

    /// Contradictions are invalid in both editable setup and realized saves;
    /// keeping their wording and coverage here prevents the two validators
    /// from drifting apart.
    private var identityConflictProblem: String? {
        if let seat = seats.first(where: { $0.isHuman && $0.opponentProfile != nil }) {
            return "Seat \(seat.index + 1) cannot be both Human and AI."
        }
        if let seat = seats.first(where: {
            guard let profile = $0.opponentProfile else { return false }
            return profile.civilization != $0.civilization
        }) {
            return "Seat \(seat.index + 1)'s AI and civilization do not match."
        }
        if let seat = seats.first(where: {
            $0.opponentProfile?.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
        }) {
            return "Seat \(seat.index + 1)'s AI profile has no identifier."
        }
        if let seat = seats.first(where: {
            $0.opponentProfile?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
        }) {
            return "Seat \(seat.index + 1)'s AI needs a name."
        }
        return nil
    }

    /// The victory-point target a new game in `mode` is played to.
    ///
    /// Returns a list, and every mode now returns exactly one, so the New Game
    /// screen renders match length as a label instead of a chip row. The shape
    /// is kept as a list because the screen already branches on `count == 1`
    /// and because a mode offering a choice again is a data change here rather
    /// than a control change there.
    ///
    /// The 12-point target this used to offer at three-player tables is gone
    /// with the three-player table. It was always the fragile one: four-player
    /// 12-point self-play reached a fully developed 11/11/11/10 position and
    /// stayed there through 10,000 moves, the scoring supply exhausted with
    /// nobody able to reach 12 - the same defect, in miniature, that retired
    /// Expanded. Existing checkpoints keep engine support through
    /// `isValidMatch`; the New Game screen must not create a match that can
    /// have no winner.
    public static func newGameVictoryPointTargets(for playerCount: Int, mode: GameMode) -> [Int] {
        guard GameSetup.supportedPlayerCounts.contains(playerCount) else { return [] }
        switch mode {
        // One target per mode (Jake, 2026-09-16): "get rid of the 8 VP versus
        // 10 VP, it's useless, we should always do 10... it just depends on the
        // mode for the VP." So match length stops being a dial and becomes a
        // consequence of the mode, and the row renders as a label.
        //
        // This governs *new* games only. `isValidMatch`, which is what a resume
        // consults, does not read this list, so a saved 8- or 12-point game
        // still loads and still finishes at the target it started with.
        case .classic: return [10]
        case .expanded: return [25]
        // Like Expanded, the target is part of the rule set rather than a dial:
        // 26 is derived from how much of a 61-tile board a player can actually
        // claim, so an 18 or a 34 beside it would not be the same game.
        case .vast: return [26]
        }
    }

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
            victoryPointTarget: Ruleset.forMode(.classic).defaultVictoryPointTarget,
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
            normalizeNewGameOptions()
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
        normalizeNewGameOptions()
    }

    /// Retired modes fall back only when prefilling New Game. Decoding and
    /// restarting an existing match must retain the rules it was saved with.
    func normalizedForNewGame() -> MatchSetup {
        var setup = self
        if !GameMode.newGameChoices.contains(setup.mode) { setup.mode = .classic }
        setup.normalizeNewGameOptions()
        return setup
    }

    /// Normalizes the target within the chosen mode, including legacy modes
    /// used by restart. Mode retirement belongs only to `normalizedForNewGame`.
    mutating func normalizeNewGameOptions() {
        if !Self.newGameVictoryPointTargets(for: seats.count, mode: mode).contains(victoryPointTarget) {
            victoryPointTarget = Ruleset.forMode(mode).defaultVictoryPointTarget
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Persists two different things, and the difference between them matters.
///
/// - `save`/`load` hold the **prefill**: the configuration the player last laid
///   out on the New Game screen, in the order they laid it out, so the screen
///   opens on it next time (A6.4).
/// - `saveActiveMatch`/`loadActiveMatch` hold the **realised match**: the same
///   seats renumbered into the turn order actually drawn, so seat *i* of that
///   value is `PlayerID(index: i)` in the game on disk.
///
/// They are separate because "Random" seating shuffles the chairs, after which
/// the prefill's indices no longer say who is sitting where. Only the realised
/// record can answer "which seats are people, and what are they called" when a
/// hot-seat game is resumed after a relaunch - and without it that question was
/// answered by `HumanSeatStore`, which holds a single seat, so every human seat
/// but the lowest silently came back as a bot.
///
/// `UserDefaults`, matching every other preference store here. It is small,
/// it is not sensitive, and a lost setup costs one screen of re-entry.
public final class MatchSetupStore: @unchecked Sendable {
    public static let shared = MatchSetupStore()

    /// Overridable so a test can point at its own container rather than
    /// trampling the developer's simulator, which an app test has done before.
    public var defaults: UserDefaults = .standard

    private let key = "matchSetup"
    private let activeKey = "activeMatchSetup"

    public enum LoadResult: Equatable {
        case none
        case loaded(MatchSetup)
        case unreadable

        public var value: MatchSetup? {
            guard case .loaded(let setup) = self else { return nil }
            return setup
        }
    }

    public func load() -> LoadResult { decode(forKey: key) }

    public func save(_ setup: MatchSetup) throws { try encode(setup, forKey: key) }

    /// The chair layout the game currently on disk is being played on.

    public func loadActiveMatch() -> LoadResult { decode(forKey: activeKey) }

    public func saveActiveMatch(_ setup: MatchSetup) throws { try encode(setup, forKey: activeKey) }

    /// Forgets who was sitting where, without touching the prefill. Used by the
    /// one-human entry point, whose game is fully described by
    /// `HumanSeatStore`'s single seat.
    public func clearActiveMatch() { defaults.removeObject(forKey: activeKey) }

    /// Clears both records. The prefill goes with them deliberately: this is
    /// called when the game is thrown away, and a prefill for a match nobody is
    /// playing is exactly as stale as the match record beside it.
    public func clear() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: activeKey)
    }

    func data(forActiveMatch: Bool) -> Data? {
        defaults.data(forKey: forActiveMatch ? activeKey : key)
    }

    func restore(_ data: Data?, forActiveMatch: Bool) {
        let targetKey = forActiveMatch ? activeKey : key
        if let data { defaults.set(data, forKey: targetKey) } else { defaults.removeObject(forKey: targetKey) }
    }

    private func decode(forKey key: String) -> LoadResult {
        guard let data = defaults.data(forKey: key) else { return .none }
        do {
            let setup = try JSONDecoder().decode(MatchSetup.self, from: data)
            // A prefill may still need a name, so full startability is not a
            // decoding requirement. Index integrity is: consumers must never
            // receive conflicting seat identities. Keep rejected bytes intact.
            guard setup.hasOrderedSeatIndices else { return .unreadable }
            return .loaded(setup)
        } catch {
            return .unreadable
        }
    }

    private func encode(_ setup: MatchSetup, forKey key: String) throws {
        defaults.set(try JSONEncoder().encode(setup), forKey: key)
    }
}
