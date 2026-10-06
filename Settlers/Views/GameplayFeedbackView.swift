import SwiftUI
import CatanEngine

/// Uses the already-reserved information row. No new panel, layout height,
/// sound, or repeating animation: the words and signed score badges do the work.
struct GameplayFeedbackView: View {
    let feedback: GameplayFeedback
    let playerIdentity: (PlayerID) -> PlayerIdentity

    var body: some View {
        let name: (PlayerID) -> String = { playerIdentity($0).displayName }
        HStack(spacing: 4) {
            Image(systemName: feedback.symbol).foregroundStyle(CatanTheme.chipGold)
            feedback.label(name: name)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 11, weight: .semibold, design: .serif))
        .foregroundStyle(CatanTheme.onWaterText)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CatanTheme.waterBackground.opacity(0.9))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(feedback.title(name: name))
        .accessibilityValue(feedback.scoreSummary(name: name))
        .accessibilityIdentifier(AccessibilityID.Feedback.notice)
        .allowsHitTesting(false)
    }
}

/// Overlay rather than another badge in the HStack: the standings never grow
/// or shift when the score changes. Both + and minus are explicit, not color-only.
struct VictoryPointChangeBadge: View {
    let amount: Int
    let seat: PlayerID

    var body: some View {
        if amount != 0 {
            Text(GameplayFeedback.signed(amount))
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(CatanTheme.waterBackground)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(CatanTheme.numberTokenBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(CatanTheme.chipGold, lineWidth: 1))
                .fixedSize()
                .accessibilityLabel("\(GameplayFeedback.signed(amount)) victory points")
                .accessibilityIdentifier(AccessibilityID.Feedback.points(seat))
                .allowsHitTesting(false)
                .offset(x: 4, y: -7)
        }
    }
}
