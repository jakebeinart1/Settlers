import SwiftUI

/// A curated palette of flat, saturated colors a player can pick as their
/// piece color in `SettingsView`. Kept as a small `Codable` enum rather than
/// persisting arbitrary `Color` values (not reliably `Codable`) - each case
/// carries its own fixed RGB so the palette reads consistently regardless of
/// system theme. Chosen to (a) stay visually distinct from one another and
/// (b) not be confusable with `CatanTheme`'s resource tile colors or the
/// `waterBackground`/`panelBackground` blues the board sits on.
public enum PieceColor: String, Codable, CaseIterable, Sendable {
    case blue
    case red
    case orange
    case cream
    case green
    case purple
    case teal
    case yellow

    public var color: Color {
        switch self {
        case .blue: return Color(red: 0.16, green: 0.45, blue: 0.91)
        case .red: return Color(red: 0.86, green: 0.20, blue: 0.20)
        case .orange: return Color(red: 0.94, green: 0.55, blue: 0.13)
        case .cream: return Color(red: 0.95, green: 0.95, blue: 0.95)
        case .green: return Color(red: 0.20, green: 0.62, blue: 0.31)
        case .purple: return Color(red: 0.58, green: 0.35, blue: 0.85)
        case .teal: return Color(red: 0.16, green: 0.62, blue: 0.63)
        case .yellow: return Color(red: 0.93, green: 0.82, blue: 0.20)
        }
    }

    public var displayName: String {
        rawValue.capitalized
    }

    /// The default palette assignment for a seat index (0 = human), matching
    /// `CatanTheme`'s original hardcoded human=blue, bot1=red, bot2=orange,
    /// bot3=white/cream scheme.
    public static func defaultColor(forSeatIndex index: Int) -> PieceColor {
        switch index {
        case 0: return .blue
        case 1: return .red
        case 2: return .orange
        default: return .cream
        }
    }
}
