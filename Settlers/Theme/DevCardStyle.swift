import SwiftUI
import CatanEngine

/// How a development card is drawn: its symbol, its colour, and the two
/// lengths of name the UI needs.
///
/// This existed twice, byte-for-byte, in `PlayerHUDView` and
/// `DevCardPopupView` - including the hand-picked
/// `Color(red: 0.85, green: 0.65, blue: 0.1)` for a victory-point card. Two
/// copies meant a card could be red in the HUD strip and something else in the
/// popup that strip opens, and nothing would have caught it.
///
/// The two name lengths were the only real difference between the copies: the
/// HUD tile is 44pt wide and needs "Plenty", while the popup has a full row and
/// should say "Year of Plenty". They are both here so the pairing is visible
/// rather than inferred from which file you happen to be reading.
enum DevCardStyle {
    static func icon(for type: DevCardType) -> String {
        switch type {
        case .knight: return "shield.fill"
        case .roadBuilding: return "road.lanes"
        case .yearOfPlenty: return "sparkles"
        case .monopoly: return "crown.fill"
        case .victoryPoint: return "star.fill"
        }
    }

    static func color(for type: DevCardType) -> Color {
        switch type {
        case .knight: return .red
        case .roadBuilding: return .brown
        case .yearOfPlenty: return .green
        case .monopoly: return .purple
        case .victoryPoint: return Color(red: 0.85, green: 0.65, blue: 0.1)
        }
    }

    /// Fits the 44pt HUD tile.
    static func shortName(for type: DevCardType) -> String {
        switch type {
        case .knight: return "Knight"
        case .roadBuilding: return "Road"
        case .yearOfPlenty: return "Plenty"
        case .monopoly: return "Monopoly"
        case .victoryPoint: return "VP"
        }
    }

    /// The card's real name, for the popup.
    static func fullName(for type: DevCardType) -> String {
        switch type {
        case .knight: return "Knight"
        case .roadBuilding: return "Road Building"
        case .yearOfPlenty: return "Year of Plenty"
        case .monopoly: return "Monopoly"
        case .victoryPoint: return "Victory Point"
        }
    }
}

/// Fixed heights the bottom row and its alternates all have to agree on.
///
/// `GameView.actionRowHeight` and a bare `75.33` in `IncomingTradeCardView`
/// were the same measurement written twice, each with a comment asking the
/// next reader to keep them in sync by hand. The row swaps between the action
/// buttons, the robber-targeting panel and the incoming-offer card, and the
/// board is the only flexible element in the layout - so any disagreement
/// between them resizes the board as the row changes.
enum BottomRowMetrics {
    /// Measured from the tallest occupant: the action row's own buttons.
    static let height: CGFloat = 75.33
}
