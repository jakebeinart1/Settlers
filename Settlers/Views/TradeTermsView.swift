import SwiftUI
import CatanEngine

/// Complete, stationary terms reused by incoming review and bot confirmation.
/// Vertical named entries never compress counts or require a color legend.
struct TradeTermsView: View {
    let give: [Resource: Int]
    let receive: [Resource: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            pile("You give", counts: give, accent: CatanTheme.chipGold)
            pile("You receive", counts: receive, accent: TradeResourceRow.receiveAccent)
        }
    }

    private func pile(_ title: String, counts: [Resource: Int], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(accent)
            ForEach(Resource.allCases.filter { counts[$0, default: 0] > 0 }, id: \.self) { resource in
                HStack(spacing: 8) {
                    Image(CatanTheme.iconImageName(for: resource))
                        .resizable().scaledToFit().frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    Text("\(counts[resource, default: 0]) \(resource.rawValue.capitalized)")
                        .font(.subheadline.bold())
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if counts.isEmpty { Text("No cards").font(.subheadline) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Self-contained review leaves GameView's command row and viewport untouched.
/// The presenter holds its existing timer for the lifetime of this sheet.
struct IncomingTradeReviewView: View {
    let summary: IncomingTradeSummary
    let identity: PlayerIdentity
    let onAccept: () -> Void
    let onReject: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        CivilizationCrest(civilization: identity.civilization, size: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Trade offer from \(identity.displayName)")
                                .font(.title2.bold())
                                .fixedSize(horizontal: false, vertical: true)
                            Text(identity.civilization.displayName).font(.subheadline)
                        }
                    }
                    Text("The timer is paused while you review.")
                        .font(.caption)
                        .foregroundStyle(CatanTheme.onWaterText.opacity(0.8))
                    TradeTermsView(give: summary.give, receive: summary.receive)
                }
            }
            VStack(spacing: 10) {
                GoldRowButton(title: "Accept trade", systemImage: "checkmark", action: onAccept)
                    .accessibilityIdentifier(AccessibilityID.IncomingTrade.accept)
                GoldRowButton(title: "Decline trade", systemImage: "xmark", action: onReject)
                    .accessibilityIdentifier(AccessibilityID.IncomingTrade.reject)
                GoldRowButton(title: "Back to offer", systemImage: "arrow.uturn.backward", action: onBack)
                    .accessibilityIdentifier("incoming-trade.review.close")
            }
        }
        .padding(20)
        .foregroundStyle(CatanTheme.onWaterText)
        .fontDesign(.serif)
        .background(CatanTheme.waterBackground.ignoresSafeArea())
    }
}
