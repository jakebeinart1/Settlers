import SwiftUI

/// The painting behind every full-screen surface. Each theme is ONE image,
/// restyled from `board-background` with its composition held fixed, so the
/// placement tuned against the HUD (ship and mountains clear of the player
/// cards - `design-references/STATUS.md`, "background composition tuning")
/// carries over without re-tuning. Sources: `design-references/approved/themes/`.
enum BackgroundTheme: String, CaseIterable, Identifiable {
    case goldenDawn, winterFjord, desertDunes, cherryBlossom, warTorn

    static let storageKey = "backgroundTheme"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .goldenDawn: return "Golden Dawn"
        case .winterFjord: return "Winter Fjord"
        case .desertDunes: return "Desert Dunes"
        case .cherryBlossom: return "Cherry Blossom"
        case .warTorn: return "War-Torn"
        }
    }

    var imageName: String {
        switch self {
        case .goldenDawn: return "board-background"
        case .winterFjord: return "bg-winter-fjord"
        case .desertDunes: return "bg-desert-dunes"
        case .cherryBlossom: return "bg-cherry-blossom"
        case .warTorn: return "bg-war-torn"
        }
    }

    /// The end screen's warmer grade was only ever painted for the original.
    var victoryImageName: String { self == .goldenDawn ? "win-background" : imageName }
}

/// Every full-bleed background goes through this. `@AppStorage` observes the
/// key, so a theme picked in Settings repaints every mounted screen at once.
struct ThemedBackgroundImage: View {
    var isVictory = false
    @AppStorage(BackgroundTheme.storageKey) private var theme: BackgroundTheme = .goldenDawn

    var body: some View {
        Image(isVictory ? theme.victoryImageName : theme.imageName).resizable()
    }
}
