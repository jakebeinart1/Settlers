import SwiftUI
import CatanEngine

/// Flat, saturated colonist.io-style color palette used throughout the board
/// and (later) HUD: one color per `Resource` (plus desert) and one per seat.
public enum CatanTheme {
    public static func color(for resource: Resource) -> Color {
        switch resource {
        case .brick: return Color(red: 0.80, green: 0.36, blue: 0.20) // terracotta orange
        case .lumber: return Color(red: 0.13, green: 0.42, blue: 0.20) // forest green
        case .ore: return Color(red: 0.42, green: 0.45, blue: 0.48) // slate gray
        case .grain: return Color(red: 0.93, green: 0.73, blue: 0.16) // gold/wheat yellow
        case .wool: return Color(red: 0.62, green: 0.80, blue: 0.32) // lime/light green
        }
    }

    public static let desert = Color(red: 0.914, green: 0.749, blue: 0.416) // sand beige - matches tile-desert.png exactly (233,191,106)

    public static func color(for kind: TileKind) -> Color {
        switch kind {
        case .resource(let resource): return color(for: resource)
        case .desert: return desert
        }
    }

    /// Asset catalog name of the painted tile texture for `kind` - see
    /// `design-references/STATUS.md` for how these were produced (an
    /// OpenRouter/GPT-Image-2 generation matched to a real crop of the
    /// approved "Avatar" full-screen mockup, one solid dominant color with
    /// a subtle painterly canvas texture, no illustrated scenery). Used by
    /// `TileDrawing.drawTile` in place of a flat `color(for:)` fill.
    public static func textureImageName(for kind: TileKind) -> String {
        switch kind {
        case .resource(.lumber): return "tile-forest"
        case .resource(.grain): return "tile-grain"
        case .resource(.wool): return "tile-pasture"
        case .resource(.ore): return "tile-mountain"
        case .resource(.brick): return "tile-clay"
        case .desert: return "tile-desert"
        }
    }

    /// One distinguishable color per seat - that seat's fixed civilization
    /// material color (see `Civilization.accentColor`), not user-
    /// customizable: with exactly one civilization per seat, the
    /// civilization already uniquely identifies the owner, so its own
    /// material color doubles as the ownership cue. Centralized here so
    /// every call site - `BoardView`, `PlayerHUDView`, `EndGameView`, etc. -
    /// stays in sync automatically.
    public static func color(for player: PlayerID) -> Color {
        Civilization.forSeat(player.index).accentColor
    }

    /// Human-readable seat label: the player's own custom name (set in
    /// Settings) for the human seat, falling back to "You" if none is set,
    /// otherwise that seat's civilization general (e.g. "Caesar") - see
    /// `Civilization.forSeat`. Replaces the old generic "Player N" now that
    /// every bot seat has a fixed empire identity.
    public static func playerLabel(for player: PlayerID) -> String {
        guard player == CivilizationAssignment.humanSeat else { return Civilization.forSeat(player.index).generalName }
        let name = PlayerNameStore.shared.load()
        return name.isEmpty ? "You" : name
    }

    /// City marker's pennant-on-a-pole flag, flown above a `CivilizationBadge`
    /// once a settlement is upgraded - replaces the old plain white ring
    /// (see `CivilizationBadge`) with something that reads as an actual
    /// upgrade rather than just a highlight.
    public static let cityPennantGold = Color(red: 0.831, green: 0.686, blue: 0.216)

    public static let robber = Color(red: 0.15, green: 0.15, blue: 0.17)
    public static let numberTokenBackground = Color(red: 0.97, green: 0.94, blue: 0.85)
    /// Warm umber ring around each number token - swapped in for a flat
    /// black stroke, which read as a harsh cutout against the token's cream
    /// face; this stays dark enough for definition while matching the
    /// board's warm sand/wood palette instead of fighting it.
    public static let numberTokenEdge = Color(red: 0.42, green: 0.30, blue: 0.16)
    public static let hotNumber = Color(red: 0.80, green: 0.10, blue: 0.10) // 6 & 8, in red
    public static let coolNumber = Color(red: 0.15, green: 0.15, blue: 0.15)
    public static let portIcon = Color.white

    /// Deep water-blue fill behind `BoardView`'s hex board, so the tiles
    /// read as an island sitting in the sea rather than floating on the
    /// app's plain dark background.
    public static let waterBackground = Color(red: 0.06, green: 0.22, blue: 0.42)

    /// Lighter blue fill behind the bottom build/trade button rows -
    /// distinguishes the "shore"/UI area from the deeper `waterBackground`
    /// behind the board while keeping the same blue family.
    public static let panelBackground = Color(red: 0.13, green: 0.32, blue: 0.52)

    /// Readable light text for use on both `waterBackground` and
    /// `panelBackground` - `.secondary`'s default gray is too dark against
    /// these mid-tone blues to read comfortably.
    public static let onWaterText = Color(white: 0.95)

    /// `PlayerHUDView`'s chip backgrounds. Originally near-black grays
    /// (`Color(white: 0.20/0.12)`), which read as too dark to comfortably
    /// scan at a glance; these sit in the same blue family as
    /// `waterBackground`/`panelBackground` but noticeably lighter, so the
    /// chips read as part of the same water theme while staying legible.
    public static let hudChipBackground = Color(red: 0.18, green: 0.40, blue: 0.60)
    public static let hudChipBackgroundActive = Color(red: 0.25, green: 0.52, blue: 0.74)
}
