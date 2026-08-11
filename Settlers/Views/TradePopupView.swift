import SwiftUI
import CatanEngine

/// In-screen popup for building and proposing a trade (replaces the old
/// `TradeSheetView` navigation sheet). Two-pane, colonist.io-style: your
/// hand sits in a tray at the bottom, tapping a hand icon moves one unit
/// into the "Give" slot above it; tapping a resource in the "Want" palette
/// adds one unit to the "Want" slot. Tapping an item already in a slot moves
/// it back out. A Bank/Port toggle switches the same card into a bank-trade
/// layout (unchanged trade logic from before, just restyled).
public struct TradePopupView: View {
    public let viewModel: GameViewModel
    public let onDismiss: () -> Void

    public init(viewModel: GameViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
    }

    @State private var give: [Resource: Int] = [:]
    @State private var want: [Resource: Int] = [:]
    @State private var isBankMode = false
    @State private var bankGiveResource: Resource = .brick
    @State private var bankWantResource: Resource = .lumber
    @State private var bankMultiplier = 1
    @State private var errorMessage: String?

    private var human: Player? { viewModel.state.players.first { $0.id == viewModel.humanPlayer } }

    public var body: some View {
        PopupCard(onDismiss: onDismiss) {
            VStack(spacing: 14) {
                HStack {
                    Text("Trade")
                        .font(.headline)
                    Spacer()
                    Toggle("Bank / Port", isOn: $isBankMode.animation())
                        .toggleStyle(.button)
                        .font(.caption)
                }

                if isBankMode {
                    bankTradeCard
                } else {
                    playerTradeCard
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                Button("Close", action: onDismiss)
                    .buttonStyle(.bordered)
            }
            .padding(16)
            .frame(maxWidth: 340)
        }
    }

    // MARK: - Player trade (two-pane, tap-to-move)

    @ViewBuilder
    private var playerTradeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Give")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ResourceSlotRow(counts: give, emptyText: "Tap a card from your hand below") { resource in
                give[resource] = (give[resource] ?? 0) - 1
                if give[resource] == 0 { give[resource] = nil }
            }

            Text("Want")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ResourceSlotRow(counts: want, emptyText: "Tap a resource below to ask for it") { resource in
                want[resource] = (want[resource] ?? 0) - 1
                if want[resource] == 0 { want[resource] = nil }
            }

            Divider().overlay(Color.white.opacity(0.2))

            Text("Your hand")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            handTray

            Text("Ask for")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            wantPalette

            Button("Propose to Bots") {
                let offer = TradeOffer(from: viewModel.humanPlayer, give: give, want: want)
                perform(.proposeTrade(offer))
            }
            .buttonStyle(.borderedProminent)
            .disabled(give.isEmpty || want.isEmpty)
            .frame(maxWidth: .infinity)
        }
    }

    /// Your hand, minus whatever's already moved into Give - tap a resource
    /// to move one more unit into the Give slot (only enabled while you
    /// still hold an un-given unit of it).
    private var handTray: some View {
        HStack(spacing: 8) {
            ForEach(Resource.allCases, id: \.self) { resource in
                let owned = human?.resources[resource] ?? 0
                let remaining = owned - (give[resource] ?? 0)
                ResourceChip(resource: resource, count: remaining, isEnabled: remaining > 0) {
                    give[resource] = (give[resource] ?? 0) + 1
                }
            }
        }
    }

    /// All five resources, tap to add one more unit into the Want slot (no
    /// ownership constraint - you're asking someone else for it).
    private var wantPalette: some View {
        HStack(spacing: 8) {
            ForEach(Resource.allCases, id: \.self) { resource in
                ResourceChip(resource: resource, count: nil) {
                    want[resource] = (want[resource] ?? 0) + 1
                }
            }
        }
    }

    // MARK: - Bank trade (unchanged logic, restyled)

    private var bankRate: Int {
        Trading.bestRate(for: bankGiveResource, player: viewModel.humanPlayer, state: viewModel.state)
    }

    @ViewBuilder
    private var bankTradeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Give")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Picker("Give", selection: $bankGiveResource) {
                    ForEach(Resource.allCases, id: \.self) { resource in
                        Label(resource.rawValue.capitalized, systemImage: CatanTheme.symbolName(for: resource))
                            .tag(resource)
                    }
                }
                .labelsHidden()
                Spacer()
                Text("\(bankRate) : 1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Want")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Picker("Want", selection: $bankWantResource) {
                    ForEach(Resource.allCases.filter { $0 != bankGiveResource }, id: \.self) { resource in
                        Label(resource.rawValue.capitalized, systemImage: CatanTheme.symbolName(for: resource))
                            .tag(resource)
                    }
                }
                .labelsHidden()
                Stepper("x\(bankMultiplier)", value: $bankMultiplier, in: 1...5)
                    .fixedSize()
            }

            Text("Give \(bankRate * bankMultiplier) \(bankGiveResource.rawValue) for \(bankMultiplier) \(bankWantResource.rawValue)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("Trade with Bank") {
                perform(.bankTrade(
                    give: [bankGiveResource: bankRate * bankMultiplier],
                    get: [bankWantResource: bankMultiplier]
                ))
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
    }

    private func perform(_ move: GameMove) {
        do {
            try viewModel.apply(move)
            errorMessage = nil
            give = [:]
            want = [:]
        } catch {
            errorMessage = "\(error)"
        }
    }
}
