import SwiftUI
import CatanEngine

/// Uses the civilization subtitle's existing line. Detailed wording yields to
/// a short receipt at narrow widths; VoiceOver always has the complete receipt.
struct ResourceProductionReceiptView: View {
    let feedback: ResourceProductionFeedback

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(feedback.summary).fixedSize()
            if let sources = feedback.sourceSummary {
                Text(sources).fixedSize()
            }
            Text(feedback.compactSummary).fixedSize()
            Text("\(feedback.roll) rolled · +\(feedback.total)")
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 12, weight: .semibold, design: .serif))
        .foregroundStyle(CatanTheme.onWaterText)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(feedback.accessibilitySummary)
        .accessibilityIdentifier("production.receipt")
        .allowsHitTesting(false)
    }
}

/// Overlays the existing swatch, leaving its count and all row dimensions alone.
/// Gold echoes the board's number tokens; the numeral carries meaning without
/// relying on color. No translation, scale, repeating pulse, or card flight.
struct ResourceProductionBadge: View {
    let amount: Int

    var body: some View {
        Text("+\(amount)")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(CatanTheme.waterBackground)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(CatanTheme.numberTokenBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(CatanTheme.chipGold, lineWidth: 1))
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// Two scheduled redraws, with no task that can delay a rule, pause bots, or
/// leave a stale dismissal racing a later receipt. The absolute deadline also
/// stops an expired receipt replaying when the HUD is temporarily removed.
struct ResourceProductionFeedbackPresenter<Content: View>: View {
    let feedback: ResourceProductionFeedback?
    let viewer: PlayerID
    @ViewBuilder let content: (ResourceProductionFeedback?) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.explicit(feedback.map { [$0.occurredAt, $0.expiresAt] } ?? [])) { context in
            let visible = scenePhase == .active ? feedback?.visible(to: viewer, at: context.date) : nil
            content(visible)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: visible?.id)
                // Seat changes must never cross-fade somebody else's receipt.
                .transaction { transaction in
                    if reduceMotion || feedback?.owner != viewer || scenePhase != .active {
                        transaction.animation = nil
                    }
                }
        }
    }
}
