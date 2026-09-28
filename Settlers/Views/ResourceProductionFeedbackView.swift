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
            .fixedSize()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// Receipt-keyed presentation lifetime, independent of game pacing. Replacing
/// a receipt cancels its dismissal; the ID also prevents a stale completion
/// from expiring a newer gain. Remounting never extends the absolute deadline.
struct ResourceProductionFeedbackPresenter<Content: View>: View {
    let feedback: ResourceProductionFeedback?
    let viewer: PlayerID
    @ViewBuilder let content: (ResourceProductionFeedback?) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var expiredReceiptID: UUID?

    var body: some View {
        let visible = scenePhase == .active && feedback?.id != expiredReceiptID
            ? feedback?.visible(to: viewer, at: Date()) : nil
        content(visible)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: visible?.id)
            // Seat changes must never cross-fade somebody else's receipt.
            .transaction { transaction in
                if reduceMotion || feedback?.owner != viewer || scenePhase != .active {
                    transaction.animation = nil
                }
            }
            .task(id: feedback?.id) {
                guard let receipt = feedback else { return }
                let remaining = max(0, receipt.expiresAt.timeIntervalSinceNow)
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
                guard !Task.isCancelled else { return }
                expiredReceiptID = receipt.id
            }
    }
}
