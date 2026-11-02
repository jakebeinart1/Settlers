import CatanEngine
import Foundation

/// A separate competition for each board, rule layer and computer tier.
///
/// A Voyages result must not change a Classic rating, and beating Classic AI
/// must not change the Expert record. These axes describe the match that was
/// actually played, rather than today's New Game preferences. Expanded stays
/// representable so an older saved match can finish without losing its record.
struct RatingPool: Codable, Hashable, Identifiable, Sendable {
    let mode: GameMode
    let variant: GameVariant
    let difficulty: BotDifficulty

    init(mode: GameMode, variant: GameVariant = .standard, difficulty: BotDifficulty) {
        self.mode = mode
        self.variant = variant
        self.difficulty = difficulty
    }

    var id: String { "\(mode.rawValue):\(variant.rawValue):\(difficulty.rawValue)" }

    var displayName: String {
        variant == .standard ? mode.displayName : "\(mode.displayName) \(variant.displayName)"
    }

    /// Naval Conquest is not a supported game; accepting it would file a
    /// malformed imported record as a competition a player cannot play.
    var isSupported: Bool { mode != .naval || variant == .standard }

    /// One person against ordinary computers is a game against an AI tier.
    /// Ghosts keep their existing ladder instead: silently calling a fitted
    /// person's ghost "Expert AI" would mix two different competitions.
    static func eligible(for setup: MatchSetup) -> RatingPool? {
        guard setup.isValidMatch, setup.humanSeats.count == 1,
              setup.seats.allSatisfy({ $0.ghostID == nil && $0.opponentProfile?.ghostID == nil }) else { return nil }
        let pool = RatingPool(mode: setup.mode, variant: setup.variant, difficulty: setup.difficulty)
        return pool.isSupported ? pool : nil
    }

    /// Every competition offered by New Game, including unplayed ones.
    /// Keep this derived from the engine's mode list so a retired board is
    /// not accidentally offered again by the ratings screen.
    static let available: [RatingPool] = GameMode.newGameChoices.flatMap { mode in
        GameVariant.allCases.flatMap { variant in
            BotDifficulty.allCases.map { RatingPool(mode: mode, variant: variant, difficulty: $0) }
                .filter(\.isSupported)
        }
    }
}
