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

    /// One SF Symbol per resource, standing in for a hand-drawn colonist.io-
    /// style icon set (Task 13/16 follow-up: the trade UI previously showed
    /// resource *names* only). Paired with `color(for:)` wherever a resource
    /// needs a compact, at-a-glance identity - e.g. `TradeSheetView`'s give/
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

    /// One distinguishable color per seat, customizable per-player from
    /// `SettingsView` (defaults: human=blue, bot1=red, bot2=orange,
    /// bot3=cream/white, matching `PieceColor.defaultColor(forSeatIndex:)`).
    /// Centralized here so every call site - `BoardView`, `PlayerHUDView`,
    /// `EndGameView`, etc. - automatically reflects the player's choice.
    @MainActor
    public static func color(for player: PlayerID) -> Color {
        SettingsStore.shared.color(forSeatIndex: player.index).color
    }

    /// Human-readable seat label, matching `RulesEngine`'s internal
    /// `state.log` phrasing ("You" for the human seat, "Player N" for bots).
    public static func playerLabel(for player: PlayerID) -> String {
        player.index == 0 ? "You" : "Player \(player.index)"
    }

    public static let robber = Color(red: 0.15, green: 0.15, blue: 0.17)
    public static let numberTokenBackground = Color(red: 0.97, green: 0.94, blue: 0.85)
    public static let hotNumber = Color(red: 0.80, green: 0.10, blue: 0.10) // 6 & 8, in red
    public static let coolNumber = Color(red: 0.15, green: 0.15, blue: 0.15)
    public static let tileBorder = Color.black.opacity(0.35)
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
