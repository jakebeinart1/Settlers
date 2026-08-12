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

                if let pendingConfirmation = viewModel.pendingTradeConfirmation {
                    pendingConfirmationBanner(pendingConfirmation)
                } else if let proposalOutcome {
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
                proposalOutcome = nil
                perform(.proposeTrade(offer))
                // Every bot's willingness is evaluated synchronously inside
                // `apply` (see `GameViewModel.resolveHumanProposedTrade`) -
                // by the time `perform` returns above, either
                // `pendingTradeConfirmation` is set (some bot would accept -
                // `pendingConfirmationBanner` takes over below, and this
                // proposal isn't actually applied until the human confirms
                // it there) or, if nobody would, `lastTradeOutcome` already
                // reflects that immediately. Neither applies if the
                // proposal itself failed (`errorMessage` set instead).
                if errorMessage == nil, viewModel.pendingTradeConfirmation == nil {
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

    // MARK: - Trade confirmation

    /// A bot said yes - shown instead of `proposalOutcomeBanner` until the
    /// human actually goes through with it (or backs out), so accepting a
    /// trade always takes an explicit confirmation rather than the swap
    /// just happening the instant a bot agrees. See
    /// `GameViewModel.pendingTradeConfirmation`.
    private func pendingConfirmationBanner(_ pending: GameViewModel.PendingTradeConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("\(CatanTheme.playerLabel(for: pending.acceptedBy)) will accept this trade")
                    .font(.caption.bold())
            }
            .foregroundStyle(.green)

            HStack(spacing: 10) {
                ForEach(pending.decisions, id: \.bot) { decision in
                    HStack(spacing: 3) {
                        Image(systemName: decision.accepted ? "checkmark" : "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(decision.accepted ? .green : .red)
                        Text(CatanTheme.playerLabel(for: decision.bot))
                            .font(.caption2)
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Decline") {
                    viewModel.declinePendingTrade()
                    proposalOutcome = viewModel.lastTradeOutcome
                }
                .buttonStyle(.bordered)

                Button("Confirm Trade") {
                    // A failed confirm used to just silently do nothing -
                    // no error, no changed cards, no indication why - since
                    // `try?` swallowed the underlying failure. Now it's
                    // reported like any other failed move.
                    switch viewModel.confirmPendingTrade() {
                    case .succeeded:
                        errorMessage = nil
                        proposalOutcome = viewModel.lastTradeOutcome
                    case .offerNoLongerAvailable:
                        errorMessage = "That trade is no longer available."
                        proposalOutcome = viewModel.lastTradeOutcome
                    case .resourcesNoLongerAvailable:
                        errorMessage = "That trade could no longer go through - resources changed since you proposed it."
                        proposalOutcome = viewModel.lastTradeOutcome
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Trade proposal outcome

    /// Every bot's individual accept/reject answer, not just whoever ended
    /// up taking the offer - so it's clear this wasn't a black box.
    private func proposalOutcomeBanner(_ outcome: GameViewModel.TradeOutcome) -> some View {
        let headline = outcome.acceptedBy.map { "\(CatanTheme.playerLabel(for: $0)) accepted!" }
            ?? "No one accepted that trade."
        let headlineColor: Color = outcome.acceptedBy != nil ? .green : .red

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: outcome.acceptedBy != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                Text(headline)
                    .font(.caption.bold())
            }
            .foregroundStyle(headlineColor)

            HStack(spacing: 10) {
                ForEach(outcome.decisions, id: \.bot) { decision in
                    HStack(spacing: 3) {
                        Image(systemName: decision.accepted ? "checkmark" : "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(decision.accepted ? .green : .red)
                        Text(CatanTheme.playerLabel(for: decision.bot))
                            .font(.caption2)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
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
                bankResourceTile(suggestion.get, count: suggestion.getCount)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                Spacer(minLength: 0)
            }

            // Every other resource, tap to choose what to receive instead -
            // a visible row of chips (matching how Give/Want are picked
            // above) rather than a dropdown menu, so the choice itself is
            // obvious rather than hidden behind a tap.
            Text("Choose what to receive")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Resource.allCases.filter { $0 != suggestion.give }, id: \.self) { resource in
                    Button {
                        bankGetOverride = resource
                    } label: {
                        bankResourceTile(resource, count: nil)
                            .overlay(
                                Circle()
                                    .strokeBorder(resource == suggestion.get ? bankGold : .clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
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

    private func bankResourceTile(_ resource: Resource, count: Int?) -> some View {
        ZStack {
            Circle()
                .fill(CatanTheme.color(for: resource))
            if let count {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 34, height: 34)
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
