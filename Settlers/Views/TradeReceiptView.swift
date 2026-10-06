import SwiftUI
import CatanEngine

/// A completed exchange, derived from the committed event rather than an offer
/// that a bot merely agreed to consider. Counts use the device player's view.
struct TradeReceipt: Equatable {
    let partner: PlayerID?
    let gave: [Resource: Int]
    let received: [Resource: Int]

    init?(event: GameEvent, player: PlayerID) {
        switch event {
        case .tradedWithBank(let actor, let gave, let got) where actor == player:
            partner = nil
            self.gave = gave
            received = got
        case .acceptedTrade(let actor, let proposer, let gave, let got) where actor == player:
            partner = proposer
            self.gave = gave
            received = got
        case .acceptedTrade(let actor, let proposer, let gave, let got) where proposer == player:
            partner = actor
            self.gave = got
            received = gave
        default:
            return nil
        }
    }
}

struct TradeReceiptView: View {
    let receipt: TradeReceipt
    let partnerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Trade complete", systemImage: "checkmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(CatanTheme.chipGold)
            Text("Traded with \(partnerName). Your hand is updated.")
                .font(.subheadline)
            resourceLine("You gave", counts: receipt.gave)
            resourceLine("You received", counts: receipt.received)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("trade.receipt")
    }

    private func resourceLine(_ title: String, counts: [Resource: Int]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Resource.allCases.filter { counts[$0, default: 0] > 0 }, id: \.self) { resource in
                HStack(spacing: 8) {
                    ResourceSquare(resource: resource, size: 20)
                    Text("\(counts[resource, default: 0]) \(resource.rawValue.capitalized)")
                        .font(.subheadline.bold())
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
