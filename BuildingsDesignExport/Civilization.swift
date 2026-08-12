import SwiftUI
import CatanEngine

/// One of eight playable empires. Exactly one occupies each of the 4 seats
/// per game - which one is fixed for the *duration of a game* but no longer
/// fixed *forever*: `CivilizationAssignment` decides seat 0 (the human, from
/// `CivilizationSettingsStore.yourCivilization`) and seats 1-3 (3 distinct
/// random draws from `CivilizationSettingsStore.includedBotCivilizations`)
/// once per game, in `GameViewModel.startNewGame`/`init`. Both the
/// settlement/city look (`CivilizationBadge`: a flat silhouette in this
/// civilization's color with an etched detail, matching the board's flat,
/// straight-bordered, black-outlined style - detailed isometric/illustrated
/// building art was tried and dropped because it either needed real size to
/// stay legible or didn't rotate cleanly for roads) and the *color*
/// (`accentColor`) are fixed per civilization rather than user-chosen: with
/// exactly one civilization per seat, the civilization already uniquely
/// identifies the owner, so a constant color works as the ownership cue
/// without needing a separate customizable per-player color layer on top of
/// it.
///
/// Roads stay the plain `RoadShape` bar filled with `accentColor` for the
/// same reason real building art didn't work for them: a hex board's roads
/// run at several different angles, and anything with a fixed "up" looks
/// wrong rotated to most of them.
public enum Civilization: String, CaseIterable, Sendable, Codable {
    case medieval
    case greece
    case egypt
    case aztec
    case columbia
    case rome
    case japan
    case norse

    /// This game's seat 0-3 civilizations, set once per game by
    /// `CivilizationAssignment`. Falls back to the pre-picker default order
    /// (Britannia/Greece/Egypt/Aztec) if nothing has assigned it yet - e.g.
    /// a `#Preview` that never runs `GameViewModel`'s startup path.
    public static func forSeat(_ index: Int) -> Civilization {
        CivilizationAssignment.current[index]
    }

    public var displayName: String {
        switch self {
        case .medieval: return "Britannia"
        case .greece: return "Greece"
        case .egypt: return "Egypt"
        case .aztec: return "Aztec"
        case .columbia: return "Columbia"
        case .rome: return "Rome"
        case .japan: return "Japan"
        case .norse: return "Norse"
        }
    }

    /// The general leading this civilization's bot seat - shown in place of
    /// "Bot (Balanced)"-style labels. The human's own seat still just reads
    /// "You" everywhere (see `CatanTheme.playerLabel`), so this name is only
    /// ever surfaced for bot seats in practice.
    public var generalName: String {
        switch self {
        case .medieval: return "Charlemagne"
        case .greece: return "Alexander"
        case .egypt: return "Ramesses"
        case .aztec: return "Moctezuma"
        case .columbia: return "Washington"
        case .rome: return "Augustus"
        case .japan: return "Tokugawa"
        case .norse: return "Ragnar"
        }
    }

    /// Small SF Symbol standing in for this civilization's emblem - used
    /// next to its name in the HUD so each empire reads as a distinct
    /// faction at a glance, not just a color.
    public var emblemSymbol: String {
        switch self {
        case .medieval: return "shield.lefthalf.filled"
        case .greece: return "laurel.leading"
        case .egypt: return "sun.max.fill"
        case .aztec: return "flame.fill"
        case .columbia: return "star.fill"
        case .rome: return "crown.fill"
        case .japan: return "mountain.2.fill"
        case .norse: return "bolt.fill"
        }
    }

    /// This civilization's fixed material color, tested against the board's
    /// water-blue background before being locked in. Used for
    /// `CivilizationBadge`, the road bar, HUD dots/tags, and everywhere else
    /// `CatanTheme.color(for: player)` is read.
    public var accentColor: Color {
        switch self {
        case .medieval: return Color(red: 0.56, green: 0.35, blue: 0.68) // purple
        case .greece: return Color(red: 0.80, green: 0.81, blue: 0.80) // white/grey marble
        case .egypt: return Color(red: 0.77, green: 0.58, blue: 0.31) // sandstone
        case .aztec: return Color(red: 0.43, green: 0.61, blue: 0.79) // slate blue
        case .columbia: return Color(red: 0.42, green: 0.50, blue: 0.60) // slate blue-grey
        case .rome: return Color(red: 0.71, green: 0.40, blue: 0.29) // terracotta
        case .japan: return Color(red: 0.37, green: 0.55, blue: 0.46) // jade
        case .norse: return Color(red: 0.49, green: 0.58, blue: 0.64) // steel blue
        }
    }

}

/// This game's seat -> civilization mapping - set once per game (not a
/// per-app-launch constant) now that `CivilizationSettingsStore` lets the
/// player choose their own civilization and which others are in the mix.
/// A plain global var rather than something threaded through every view:
/// `Civilization.forSeat`/`CatanTheme.color(for: PlayerID)` are read from
/// ~10 call sites across the board/HUD/trade/settings views as pure-looking
/// static lookups, and re-plumbing all of them through an environment value
/// for a mapping that only actually changes once per game (at
/// `GameViewModel.startNewGame`/`init`) isn't worth the churn. `nonisolated
/// (unsafe)` rather than `@MainActor` for the same reason: this whole app is
/// single-threaded UI code, every read and write already happens on the
/// main thread in practice, and actor-isolating `current` would force
/// `@MainActor` down through every nonisolated helper property that reads
/// `Civilization.forSeat`/`CatanTheme.color(for: player:)` indirectly.
public enum CivilizationAssignment {
    /// Seat 0 = human, matching `GameViewModel.humanPlayer`. Defaults to the
    /// original fixed lineup so anything that reads this before
    /// `GameViewModel` has run (previews, tests) still gets a sensible
    /// answer instead of a crash. Only `GameViewModel` ever writes here.
    public nonisolated(unsafe) static var current: [Civilization] = [.medieval, .greece, .egypt, .aztec]
}
