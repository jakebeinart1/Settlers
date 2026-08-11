import SwiftUI
import CatanEngine

/// One of the four playable empires - fixed per seat (not user-customizable)
/// so every game features the same four civilizations with the same
/// generals. Both the settlement/city look (`CivilizationBadge`: a flat
/// circle in this civilization's color with its emblem glyph, matching the
/// board's flat, straight-bordered, black-outlined style - detailed
/// isometric/illustrated building art was tried and dropped because it
/// either needed real size to stay legible or didn't rotate cleanly for
/// roads) and the *color* (`accentColor`) are fixed per civilization rather
/// than user-chosen: with exactly one civilization per seat, the
/// civilization already uniquely identifies the owner, so a constant color
/// works as the ownership cue without needing a separate customizable
/// per-player color layer on top of it.
///
/// Roads stay the plain `RoadShape` bar filled with `accentColor` for the
/// same reason real building art didn't work for them: a hex board's roads
/// run at several different angles, and anything with a fixed "up" looks
/// wrong rotated to most of them.
public enum Civilization: String, CaseIterable, Sendable {
    case medieval
    case greece
    case egypt
    case aztec

    /// Fixed seat assignment: 0 = human, 1-3 = bots, matching
    /// `GameViewModel`'s personality assignment order.
    public static func forSeat(_ index: Int) -> Civilization {
        switch index {
        case 0: return .medieval
        case 1: return .greece
        case 2: return .egypt
        default: return .aztec
        }
    }

    public var displayName: String {
        switch self {
        case .medieval: return "Britannia"
        case .greece: return "Greece"
        case .egypt: return "Egypt"
        case .aztec: return "Aztec"
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
        }
    }

}
