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

    /// Player-facing rules copy. This is presentation text only; legality
    /// comes from `DevCards.playStatus`, never from parsing these sentences.
    static func effect(for type: DevCardType) -> String {
        switch type {
        case .knight:
            "Move the robber to a new tile, then steal one random resource from an adjacent rival."
        case .roadBuilding:
            "Place two legal roads for free. Both roads are committed together."
        case .yearOfPlenty:
            "Take any two resource cards the bank can supply. You may choose the same resource twice."
        case .monopoly:
            "Name one resource. Every rival gives you all cards of that resource they hold."
        case .victoryPoint:
            "Worth one hidden victory point. It counts automatically and is never played."
        }
    }

    static func statusTitle(for status: DevCardPlayStatus) -> String {
        switch status {
        case .playable: "Ready to play"
        case .passiveVictoryPoint: "Counts automatically"
        case .notOwned: "Not in your hand"
        case .boughtThisTurn: "New this turn"
        case .alreadyPlayedThisTurn: "One card already played"
        case .waitingForYourTurn: "Waiting for your turn"
        case .resolveRequiredAction: "Finish the required action first"
        case .noLegalChoices: "No legal choices"
        case .gameOver: "Match complete"
        }
    }

    static func statusDetail(for status: DevCardPlayStatus, type: DevCardType) -> String {
        switch status {
        case .playable:
            "This card can be used now."
        case .passiveVictoryPoint:
            "Its point is already included in your private total."
        case .notOwned:
            "You do not currently hold this card."
        case .boughtThisTurn:
            "Development cards become playable on a later turn."
        case .alreadyPlayedThisTurn:
            "Only one development card may be played during a turn."
        case .waitingForYourTurn:
            "You can inspect it now and play it during your turn."
        case .resolveRequiredAction:
            "Complete setup, a discard, or the current robber move before playing a card."
        case .noLegalChoices where type == .roadBuilding:
            "There is no legal pair of roads available from your network."
        case .noLegalChoices where type == .yearOfPlenty:
            "The bank has fewer than two resource cards available."
        case .noLegalChoices:
            "This card has no legal target in the current position."
        case .gameOver:
            "The match has already ended."
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
