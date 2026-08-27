import SwiftUI
import CatanEngine

/// In-screen popup for building and proposing a trade (replaces the old
/// `TradeSheetView` navigation sheet). Two-pane, colonist.io-style: your
/// hand sits in a tray at the bottom, tapping a hand icon moves one unit
/// into the "Give" slot above it; tapping a resource in the "Want" palette
/// adds one unit to the "Want" slot. Tapping an item already in a slot moves
/// it back out.
///
/// There's no separate "Bank/Port mode" to switch into - Give/Want double
/// as the bank trade's give/get piles too. As soon as they form a legal
/// bank trade (every Give resource is a multiple of its own best rate, and
/// the total converts exactly to Want's total - see `isValidBankTrade`), a
/// "Trade with Bank" button lights up next to "Propose to Bots"; it stays in
/// place either way so nothing shifts, and it fires `.bankTrade` with the
/// same Give/Want dictionaries a player-to-player proposal would use,
/// including mixed-resource piles (e.g. 4 brick + 4 wood -> 1 ore + 1 wheat)
/// since `Trading.bankTrade` already validates and settles those per-
/// resource. Below that, one fixed-height status slot always occupies the
/// same space whether it's showing nothing, a pending-confirmation banner,
/// an outcome banner, or an error - so a bot accepting/declining never
/// reflows the rest of the card (see `statusRegion`).
public struct TradePopupView: View {
    public let viewModel: GameViewModel
    public let onDismiss: () -> Void

    public init(viewModel: GameViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
    }

    @State private var give: [Resource: Int] = [:]
    @State private var want: [Resource: Int] = [:]
    @State private var errorMessage: String?
    @State private var proposalOutcome: GameViewModel.TradeOutcome?

    private static let bankGold = Color(red: 0.85, green: 0.68, blue: 0.32)
    /// Tall enough to fit `pendingConfirmationBanner`, the largest of the
    /// three things that can occupy `statusRegion` - reserved unconditionally
    /// so the card never grows/shrinks when a bot responds. Bumped from the
    /// original 104 (measured against the actual rendered banner - see
    /// chat) - that was sized for `pendingConfirmationBanner`'s old compact
    /// side-by-side Decline/Confirm Trade pair; once those became full-width
    /// stacked `GoldRowButton`s (to fix the mid-word wrapping bug - see
    /// `GoldRowButton.swift`'s doc comment), the banner grew taller than
    /// this reserved slot without this constant following it, so the
    /// un-clipped overflow visually landed on top of - and hid - "Confirm
    /// Trade" itself (reproduced via `-qaShowPendingTradeConfirmation`).
    /// Kept close to the banner's real height rather than padded generously
    /// - `PopupCard`'s own scroll-when-tall fix (see its doc comment) is
    /// what actually protects against overflow now, so there's no need to
    /// over-reserve here at the cost of pushing "Close" further down/
    /// off-screen than it needs to be. Bumped from 165 once accepting bots
    /// in `pendingConfirmationBanner` grew from a single name-only row to a
    /// two-line "X: message" row each - worst case is all 3 bots accepting,
    /// each a 2-line row. Bumped from 210 once that row's text grew from
    /// `.caption2` to `.subheadline` (see `tradeMessageRow`) - the smaller
    /// value under-reserved the new row height enough that `PopupCard`'s
    /// scroll-when-tall clipping ate the normal gap before "Close",
    /// crowding it flush against "Confirm Trade" (see chat).
    private static let statusRegionHeight: CGFloat = 260

    private var human: Player? { viewModel.state.players.first { $0.id == viewModel.humanPlayer } }

    public var body: some View {
        PopupCard(onDismiss: onDismiss) {
            VStack(spacing: 14) {
                Text("Trade")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                playerTradeCard

                statusRegion

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                GoldRowButton(title: "Close", systemImage: "xmark", action: onDismiss)
            }
            .padding(16)
            .frame(maxWidth: 360)
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

            bankHint

            // Stacked full-width rows, not side-by-side - `GoldRowButton`'s
            // icon+title row is wider than a plain `.borderedProminent`
            // button (see chat: "Trade with Bank" wrapped to 3 lines split
            // two-up in this popup's ~330pt width), so every multi-word
            // button pair in this popup stacks instead of sharing a row.
            VStack(spacing: 10) {
                GoldRowButton(
                    title: "Propose to Bots",
                    systemImage: "person.2.fill",
                    isEnabled: !give.isEmpty && !want.isEmpty
                ) {
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

                GoldRowButton(
                    title: "Trade with Bank",
                    systemImage: "building.columns.fill",
                    iconColor: Self.bankGold,
                    titleColor: Self.bankGold,
                    isEnabled: isValidBankTrade
                ) {
                    perform(.bankTrade(give: give, get: want))
                }
            }
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
    /// ownership constraint - you're asking someone else, or the bank, for
    /// it).
    private var wantPalette: some View {
        HStack(spacing: 8) {
            ForEach(Resource.allCases, id: \.self) { resource in
                ResourceChip(resource: resource, count: nil) {
                    want[resource] = (want[resource] ?? 0) + 1
                }
            }
        }
    }

    // MARK: - Status region (fixed height - see doc comment above)

    @ViewBuilder
    private var statusRegion: some View {
        Group {
            if let pendingConfirmation = viewModel.pendingTradeConfirmation {
                pendingConfirmationBanner(pendingConfirmation)
            } else if let proposalOutcome {
                proposalOutcomeBanner(proposalOutcome)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.statusRegionHeight, alignment: .top)
    }

    /// A bot said yes - shown instead of `proposalOutcomeBanner` until the
    /// human actually goes through with it (or backs out), so accepting a
    /// trade always takes an explicit confirmation rather than the swap
    /// just happening the instant a bot agrees. See
    /// `GameViewModel.pendingTradeConfirmation`.
    private func pendingConfirmationBanner(_ pending: GameViewModel.PendingTradeConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // One row per bot, every bot with its own message (see
            // `GameViewModel.tradeResponseMessage` - a bot always has
            // something to say, whether it took the deal or not). An
            // accepting bot's row is tappable to switch `selectedBot`; a
            // rejecting bot's row is plain, non-interactive text. No
            // `lineLimit` on the message itself - it wraps rather than
            // truncating, and `PopupCard`'s own scroll-when-tall handling
            // (see its doc comment) covers the rare case that pushes the
            // card past `statusRegionHeight`.
            ForEach(pending.decisions, id: \.bot) { decision in
                if decision.accepted {
                    Button {
                        viewModel.selectTradePartner(decision.bot)
                    } label: {
                        tradeMessageRow(decision, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(decision.bot == pending.selectedBot ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    tradeMessageRow(decision, systemImage: "xmark")
                        .foregroundStyle(.red.opacity(0.7))
                }
            }

            VStack(spacing: 10) {
                GoldRowButton(title: "Decline", systemImage: "xmark", action: {
                    viewModel.declinePendingTrade()
                    proposalOutcome = viewModel.lastTradeOutcome
                })

                GoldRowButton(title: "Confirm Trade", systemImage: "checkmark", iconColor: .green, titleColor: .green, action: {
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
                })
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Every bot's individual accept/reject answer *and* its own message,
    /// not just whoever ended up taking the offer (or, if nobody did, a
    /// bare "no one accepted") - so a fully-declined proposal still comes
    /// back with real reactions instead of a silent wall of rejections.
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

            ForEach(outcome.decisions, id: \.bot) { decision in
                tradeMessageRow(decision, systemImage: decision.accepted ? "checkmark.circle.fill" : "xmark")
                    .foregroundStyle(decision.accepted ? .green : .red.opacity(0.7))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    /// One bot's name + message, shared between `pendingConfirmationBanner`
    /// (still awaiting confirmation) and `proposalOutcomeBanner` (already
    /// resolved) - only the leading icon and the color applied by the
    /// caller differ between an accept and a reject.
    private func tradeMessageRow(_ decision: (bot: PlayerID, accepted: Bool, message: String), systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline)
            // `.subheadline` - bumped up from `.caption2`. `TradeMessages`'s
            // pools are capped at 38 characters (see `TradeMessages`'s own
            // doc comment) specifically so a line fits on one row at this
            // size within the popup's width, no `lineLimit`/shrink needed.
            VStack(alignment: .leading, spacing: 1) {
                Text("\(CatanTheme.playerLabel(for: decision.bot)):")
                    .font(.subheadline.bold())
                Text(decision.message)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Bank trade

    private func rate(for resource: Resource) -> Int {
        Trading.bestRate(for: resource, player: viewModel.humanPlayer, state: viewModel.state)
    }

    /// True exactly when the current Give/Want piles are a legal bank/port
    /// trade as-is: every Give resource is offered in a whole multiple of
    /// its own best rate, and those multiples convert to exactly Want's
    /// total - the same rule `Trading.bankTrade` itself enforces, mirrored
    /// here so the button can reflect it before it's tapped. Supports mixed
    /// Give/Want piles (e.g. 4 brick + 4 wood -> 1 ore + 1 wheat) since it
    /// checks each resource independently rather than requiring Give to be
    /// a single resource.
    private var isValidBankTrade: Bool {
        guard !give.isEmpty, !want.isEmpty else { return false }
        var convertedTotal = 0
        for (resource, amount) in give {
            let r = rate(for: resource)
            guard r > 0, amount % r == 0 else { return false }
            convertedTotal += amount / r
        }
        return convertedTotal == want.values.reduce(0, +)
    }

    /// A fixed-height hint under the palettes - shows the player's current
    /// best rates while Give is empty, then tracks whether the pile in
    /// progress is a legal bank trade yet. Always rendered (never
    /// conditionally inserted/removed) so its own presence never shifts the
    /// buttons below it - reserved at *two* lines' height, not one: the
    /// default "Bank rates: Brick 4:1 · Lumber 4:1 · ..." text (all 5
    /// resources) reliably wraps to 2 lines at this card's width, so a
    /// single-line reservation left the buttons below hopping up a hair the
    /// instant that text was replaced by a shorter one-line message (the
    /// "ready to trade" / "must be a multiple of its rate" hints) - see chat.
    private var bankHint: some View {
        Text(bankHintText)
            .font(.caption2)
            .foregroundStyle(isValidBankTrade ? Self.bankGold : .secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 32, alignment: .top)
    }

    private var bankHintText: String {
        if give.isEmpty {
            let rates = Resource.allCases.map { "\($0.rawValue.capitalized) \(rate(for: $0)):1" }
            return "Bank rates: " + rates.joined(separator: " \u{00B7} ")
        }
        if isValidBankTrade {
            let total = want.values.reduce(0, +)
            return "Ready to trade with the bank for \(total) card\(total == 1 ? "" : "s")."
        }
        return "For a bank trade, each Give resource must be a multiple of its rate, matching Want's total."
    }

    private func perform(_ move: GameMove) {
        do {
            try viewModel.apply(move)
            errorMessage = nil
            give = [:]
            want = [:]
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
