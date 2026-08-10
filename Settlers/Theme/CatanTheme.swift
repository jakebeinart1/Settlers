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

    public static func color(for kind: TileKind) -> Color {
        switch kind {
        case .resource(let resource): return color(for: resource)
        case .desert: return desert
        }
    }

    /// One distinguishable color per seat: human is blue, bots are
    /// red/orange/white (index 0...3, matching `PlayerID.index`).
    public static func color(for player: PlayerID) -> Color {
        switch player.index {
        case 0: return Color(red: 0.16, green: 0.45, blue: 0.91) // human: blue
        case 1: return Color(red: 0.86, green: 0.20, blue: 0.20) // bot: red
        case 2: return Color(red: 0.94, green: 0.55, blue: 0.13) // bot: orange
        default: return Color(red: 0.95, green: 0.95, blue: 0.95) // bot: white
        }
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
}
