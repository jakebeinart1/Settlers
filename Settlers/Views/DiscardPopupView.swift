import SwiftUI
import CatanEngine

/// Popup presented when the human must discard half their hand after a
/// 7-roll (`state.phase == .discarding` with `humanPlayer` in `pending`).
/// Same tap-to-move interaction and card chrome as `TradePopupView` (per
/// request, so the two feel like one family) rather than the old `Form`-
/// based `DiscardView`: tap a card in "Your hand" to move it into the
/// Discard slot, tap it there to move it back. "Your hand" always shows the
/// count still held of each resource, so it's clear what you have left to
/// pick from as you go.
public struct DiscardPopupView: View {
    public let viewModel: GameViewModel

    public init(viewModel: GameViewModel) {
        self.viewModel = viewModel
    }

    @State private var discard: [Resource: Int] = [:]
    @State private var errorMessage: String?

    private var human: Player? { viewModel.state.players.first { $0.id == viewModel.humanPlayer } }
    private var requiredCount: Int { human.map { Robber.discardCount(for: $0) } ?? 0 }
    private var selectedCount: Int { discard.values.reduce(0, +) }

    public var body: some View {
        // No dismiss-by-tapping-outside here (`onDismiss: {}`) - discarding
        // is mandatory, matching the old sheet's `interactiveDismissDisabled`.
        PopupCard(onDismiss: {}, content: {
            VStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text("Discard \(selectedCount) of \(requiredCount)")
                        .font(.headline)
                    Text("Rolled a 7 - you're holding more than 7 cards.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("Discarding")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ResourceSlotRow(counts: discard, emptyText: "Tap a card from your hand below") { resource in
                    discard[resource] = (discard[resource] ?? 0) - 1
                    if discard[resource] == 0 { discard[resource] = nil }
                }

                Divider().overlay(Color.white.opacity(0.2))

                Text("Your hand")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                handTray

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                Button("Discard") {
                    perform(.discard(discard))
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCount != requiredCount)
                .frame(maxWidth: .infinity)
            }
            .padding(16)
            .frame(maxWidth: 320)
        })
    }

    /// Your hand, minus whatever's already moved into the discard slot -
    /// tap a resource to move one more unit into it (only enabled while an
    /// un-discarded unit remains).
    private var handTray: some View {
        HStack(spacing: 8) {
            ForEach(Resource.allCases, id: \.self) { resource in
                let owned = human?.resources[resource] ?? 0
                let remaining = owned - (discard[resource] ?? 0)
                ResourceChip(resource: resource, count: remaining, isEnabled: remaining > 0) {
                    discard[resource] = (discard[resource] ?? 0) + 1
                }
            }
        }
    }

    private func perform(_ move: GameMove) {
        do {
            try viewModel.apply(move)
            errorMessage = nil
            discard = [:]
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
