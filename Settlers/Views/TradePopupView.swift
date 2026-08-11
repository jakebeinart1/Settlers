import SwiftUI
import CatanEngine

/// In-screen popup for building and proposing a trade (replaces the old
/// `TradeSheetView` navigation sheet). Two-pane, colonist.io-style: your
/// hand sits in a tray at the bottom, tapping a hand icon moves one unit
/// into the "Give" slot above it; tapping a resource in the "Want" palette
/// adds one unit to the "Want" slot. Tapping an item already in a slot moves
/// it back out.
///
/// There's no separate "Bank/Port mode" to switch into anymore - as soon as
/// Give holds a single resource in a bank/port-eligible multiple (4 with no
/// port, 3 on a generic port, 2 on that resource's own port), a bank/port
/// trade card appears automatically below "Propose to Bots", offering to
/// execute that same give pile as a bank trade instead. It defaults its
/// "get" side to whatever's already in Want (falling back to any other
/// resource), with a small menu to change it.
public struct TradePopupView: View {
    public let viewModel: GameViewModel
    public let onDismiss: () -> Void

    public init(viewModel: GameViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
    }

    @State private var give: [Resource: Int] = [:]
    @State private var want: [Resource: Int] = [:]
    @State private var bankGetOverride: Resource?
    @State private var errorMessage: String?
    @State private var proposalOutcome: GameViewModel.TradeOutcome?

    private var human: Player? { viewModel.state.players.first { $0.id == viewModel.humanPlayer } }

    public var body: some View {
        PopupCard(onDismiss: onDismiss) {
            VStack(spacing: 14) {
                Text("Trade")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                playerTradeCard

                if let proposalOutcome {
                    proposalOutcomeBanner(proposalOutcome)
                }

                if let bankSuggestion {
                    bankSuggestionCard(bankSuggestion)
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
                // A bot's response is resolved synchronously inside
                // `apply` (see `GameViewModel.resolveHumanProposedTrade`) -
                // by the time `perform` returns above, `lastTradeOutcome`
                // already reflects this exact proposal, as long as it
                // didn't fail (`errorMessage` would be set instead, and
                // `lastTradeOutcome` would still be stale from an earlier
                // proposal - don't show that as if it were this one's).
                if errorMessage == nil {
                    proposalOutcome = viewModel.lastTradeOutcome
                }
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

    // MARK: - Trade proposal outcome

    private func proposalOutcomeBanner(_ outcome: GameViewModel.TradeOutcome) -> some View {
        let (text, color, icon): (String, Color, String) = switch outcome {
        case .accepted(let bot):
            ("\(CatanTheme.playerLabel(for: bot)) accepted!", .green, "checkmark.circle.fill")
        case .declined:
            ("No one accepted that trade.", .red, "xmark.circle.fill")
        }
        return HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
                .font(.caption.bold())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Automatic bank/port suggestion

    private func rate(for resource: Resource) -> Int {
        Trading.bestRate(for: resource, player: viewModel.humanPlayer, state: viewModel.state)
    }

    private struct BankSuggestion {
        let give: Resource
        let giveCount: Int
        let rate: Int
        let get: Resource
        var getCount: Int { giveCount / rate }
    }

    /// Non-nil exactly when Give is a single resource in a quantity that's
    /// an exact multiple of that resource's bank/port rate - the only case
    /// a bank/port trade could actually execute this Give pile as-is.
    private var bankSuggestion: BankSuggestion? {
        guard give.count == 1, let (resource, count) = give.first else { return nil }
        let rate = rate(for: resource)
        guard count > 0, count % rate == 0 else { return nil }

        let overrideChoice = bankGetOverride != resource ? bankGetOverride : nil
        let get = overrideChoice
            ?? want.keys.first { $0 != resource }
            ?? Resource.allCases.first { $0 != resource }
        guard let get else { return nil }
        return BankSuggestion(give: resource, giveCount: count, rate: rate, get: get)
    }

    private func bankSuggestionCard(_ suggestion: BankSuggestion) -> some View {
        let bankGold = Color(red: 0.85, green: 0.68, blue: 0.32)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "building.columns.fill")
                Text("Bank / Port trade available")
                    .font(.caption.bold())
                Spacer()
                Text("\(suggestion.rate):1")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(bankGold)

            HStack(spacing: 12) {
                bankResourceTile(suggestion.give, count: suggestion.giveCount)

                Image(systemName: "arrow.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Menu {
                    ForEach(Resource.allCases.filter { $0 != suggestion.give }, id: \.self) { resource in
                        Button {
                            bankGetOverride = resource
                        } label: {
                            Label(resource.rawValue.capitalized, systemImage: CatanTheme.symbolName(for: resource))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        bankResourceTile(suggestion.get, count: suggestion.getCount)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            Button {
                perform(.bankTrade(give: [suggestion.give: suggestion.giveCount], get: [suggestion.get: suggestion.getCount]))
                bankGetOverride = nil
            } label: {
                Text("Trade with Bank/Port")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(bankGold)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(bankGold.opacity(0.16)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(bankGold.opacity(0.5), lineWidth: 1))
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: suggestion.giveCount)
    }

    private func bankResourceTile(_ resource: Resource, count: Int) -> some View {
        VStack(spacing: 1) {
            Image(systemName: CatanTheme.symbolName(for: resource))
                .font(.callout)
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(.white)
        .frame(width: 34, height: 34)
        .background(CatanTheme.color(for: resource), in: RoundedRectangle(cornerRadius: 8))
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
