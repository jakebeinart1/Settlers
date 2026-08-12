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

    public static let desert = Color(red: 0.87, green: 0.80, blue: 0.60) // sand beige
    /// Slightly deeper sand tone stroked around each tile's full-size frame
    /// hex, so the manila "grout" band between tiles - and the island's
    /// outer coastline - reads as a crisp, even edge instead of a raw fill
    /// boundary that anti-aliases unevenly against the water.
    public static let desertEdge = Color(red: 0.74, green: 0.65, blue: 0.44)

    /// One SF Symbol per resource, standing in for a hand-drawn colonist.io-
    /// style icon set (Task 13/16 follow-up: the trade UI previously showed
    /// resource *names* only). Paired with `color(for:)` wherever a resource
    /// needs a compact, at-a-glance identity - e.g. `TradePopupView`'s give/
    /// want pickers - rather than a full custom vector icon set, which is
    /// deferred (see the design doc's "Open Items for Later").
    public static func symbolName(for resource: Resource) -> String {
        switch resource {
        case .brick: return "cube.fill" // clay brick
        case .lumber: return "tree.fill"
        case .ore: return "mountain.2.fill"
        case .grain: return "basket.fill" // wheat harvest
        case .wool: return "cloud.fill" // sheep's wool
        }
    }

    public static func color(for kind: TileKind) -> Color {
        switch kind {
        case .resource(let resource): return color(for: resource)
        case .desert: return desert
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

    /// Human-readable seat label: "You" for the human seat, otherwise that
    /// seat's civilization general (e.g. "Caesar") - see `Civilization
    /// .forSeat`. Replaces the old generic "Player N" now that every bot
    /// seat has a fixed empire identity.
    public static func playerLabel(for player: PlayerID) -> String {
        player.index == 0 ? "You" : Civilization.forSeat(player.index).generalName
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
    // Crisp border between tiles - deep umber-brown rather than flat black,
    // so the hex grid reads as defined without the harsher cutout look a
    // pure black stroke gave every tile edge.
    public static let tileBorder = Color(red: 0.30, green: 0.20, blue: 0.11).opacity(0.85)
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
