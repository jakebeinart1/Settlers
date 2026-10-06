import SwiftUI
import CatanEngine

/// In-screen popup for building and proposing a trade.
///
/// Two named quantity rows keep the local player's perspective throughout:
/// You give and You receive. Tapping commodity art/+ adds; minus removes.
/// Availability lives inside give cells instead of a separate inventory tray.
///
/// ## Two modes, because they are two different trades
/// The popup used to run both trades at once: one Give/Get pair, both "Propose
/// to Bots" and "Trade with Bank" always visible, and the bank's exchange rates
/// permanently on display underneath. That last part is actively misleading -
/// the rates govern trading with the *bank* and have nothing to do with what a
/// bot will accept, so showing them while you compose an offer to a player
/// invites you to think a 4:1 rule applies to it. It does not; a bot will take
/// 1-for-1 if it wants the card.
///
/// So the two are now separate modes behind a segmented control, and each shows
/// only what governs it. `Trading.bankTradeProblem` still decides whether a
/// bank trade is legal - the popup asks the engine rather than re-deriving the
/// rule, which is how the bug Jake reported (validating the exchange rate but
/// not the bank's stock) got in the first time.
///
/// ## The proposal goes to every bot at once
/// There is no "trade with this player" picker, because `TradeOffer` carries no
/// recipient - `proposeTrade` is broadcast to the table and each bot answers
/// for itself. When more than one says yes, `pendingConfirmationBanner` is
/// where you choose between them, which is the only point at which picking a
/// partner is a real decision.
public struct TradePopupView: View {
    public let viewModel: GameViewModel
    public let onDismiss: () -> Void
    private let initialReceipt: TradeReceipt?

    public init(viewModel: GameViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        initialReceipt = nil
    }

    init(viewModel: GameViewModel, completedTrade: TradeReceipt?, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        initialReceipt = completedTrade
    }

    /// Which trade is being composed. Give/Get carry across a switch on
    /// purpose: having built "2 ore for 1 wheat" and found no bot wants it,
    /// checking whether the bank will take it should not mean building it
    /// again.
    private enum Mode: String, CaseIterable {
        case players = "Players"
        case bank = "Bank"

        var systemImage: String { self == .players ? "person.2.fill" : "building.columns.fill" }
    }

    /// Starts on Bank when there is no bot to trade with - an all-human table
    /// has nobody to answer a proposal (see `GameViewModel.hasBotSeats`).
    @State private var mode: Mode = .players
    @State private var give: [Resource: Int] = [:]
    @State private var want: [Resource: Int] = [:]
    @State private var errorMessage: String?
    @State private var proposalOutcome: GameViewModel.TradeOutcome?
    @State private var receipt: TradeReceipt?
    @State private var isShowingBankHelp = false

    private static let bankGold = CatanTheme.chipGold
    private static let problemColor = Color(red: 1, green: 0.68, blue: 0.58)

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture {
                    if receipt == nil { onDismiss() }
                }
                // Hug ordinary content; scroll only the middle on short screens.
                // The footer never scrolls away, even with help or three replies.
                ViewThatFits(in: .vertical) {
                    panel(scrolling: false, height: nil)
                    panel(scrolling: true, height: max(0, geometry.size.height - 24))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .onAppear {
            if !viewModel.hasBotSeats { mode = .bank }
            receipt = initialReceipt
        }
    }

    private func panel(scrolling: Bool, height: CGFloat?) -> some View {
        VStack(spacing: 14) {
            header
            if scrolling {
                ScrollView { panelContent }
                    .accessibilityIdentifier(AccessibilityID.Trade.content)
            } else {
                panelContent.fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(16)
        .frame(maxWidth: 400, maxHeight: height)
        .background(PaintedChromeBackground(fill: .color(CatanTheme.panelBackground), cornerRadius: 16))
        .foregroundStyle(CatanTheme.onWaterText)
        .fontDesign(.serif)
        .shadow(radius: 20)
    }

    private var panelContent: some View {
        VStack(spacing: 14) {
            if let receipt {
                TradeReceiptView(receipt: receipt, partnerName: receipt.partner.map {
                    viewModel.playerIdentity(for: $0).displayName
                } ?? "the Bank")
            } else if isShowingBotResponse {
                statusRegion
            } else {
                modePicker
                tradeBuilder
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(Self.problemColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if receipt == nil, viewModel.pendingTradeConfirmation != nil {
                pendingConfirmationActions
            } else if (receipt != nil && viewModel.state.phase.isMainTurn(of: viewModel.humanPlayer.index)) || proposalOutcome != nil {
                GoldRowButton(title: receipt != nil ? "Trade again" : "New Offer",
                              systemImage: "arrow.counterclockwise", action: resetDraft)
            } else if receipt == nil && !isShowingBotResponse {
                actionButton
            }
            GoldRowButton(title: receipt != nil ? "Close trade" : "Close", systemImage: "xmark", action: onDismiss)
        }
    }

    private func resetDraft() {
        receipt = nil
        proposalOutcome = nil
        give = [:]
        want = [:]
        errorMessage = nil
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(CatanTheme.chipGold)
            Text("Trade").font(.title2.bold())
            Spacer(minLength: 0)
        }
    }

    /// Height of a tab. Fixed rather than derived from the label, for the
    /// reason spelled out on `modePicker`.
    private static let tabHeight: CGFloat = 42

    /// Segmented Players/Bank control.
    ///
    /// Hand-rolled rather than a `Picker(.segmented)`: the system control
    /// renders in its own grey-on-grey palette, which sits badly against the
    /// painted chrome everywhere else in this app.
    ///
    /// ## Why the sizing is pinned so carefully
    /// The first version set the selected tab's font to `.bold` and the other
    /// to `.regular`, and let each tab size itself. Bold text is very slightly
    /// taller, so the two tabs had different intrinsic heights, the row's
    /// height depended on *which* tab was selected, and SwiftUI animated
    /// between the two layouts on every switch. The visible result was the
    /// gold highlight sliding vertically - the tabs bobbing up and down past
    /// each other before settling - instead of simply moving across.
    ///
    /// So both tabs are always bold and always exactly `tabHeight` tall.
    /// Selection changes colour and background only, never metrics, which is
    /// what makes the highlight move horizontally and nothing else move at
    /// all.
    /// The Players tab is absent entirely when no bot can answer a proposal,
    /// rather than present-but-disabled: a tab that cannot ever be selected in
    /// this game is not a state worth explaining.
    private var availableModes: [Mode] {
        viewModel.hasBotSeats ? Mode.allCases : [.bank]
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(availableModes, id: \.self) { candidate in
                let isSelected = candidate == mode
                Button {
                    // Clearing the error is the point: "the bank has no ore
                    // left" is meaningless once you have switched to bots.
                    errorMessage = nil
                    mode = candidate
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: candidate.systemImage)
                        Text(candidate.rawValue)
                    }
                    // Bold on both, always: the weight is what changed the
                    // height, and colour alone carries the selection.
                    .font(.subheadline.bold())
                    .foregroundStyle(isSelected ? CatanTheme.chipGold : CatanTheme.onWaterText.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.tabHeight)
                    // The whole cell is the target, not just the glyphs.
                    .contentShape(Rectangle())
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(CatanTheme.chipGold.opacity(0.7), lineWidth: 1)
                                )
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(height: Self.tabHeight + 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.25)))
        // Explicit and horizontal-only. Without naming the animation, the
        // implicit one animated the layout change described above.
        .animation(.easeInOut(duration: 0.18), value: mode)
    }

    // MARK: - Building the offer

    private var draftFeedback: TradeDraftFeedback {
        TradeDraftFeedback(give: give, receive: want, mode: mode == .bank ? .bank : .players,
                           player: viewModel.humanPlayer, state: viewModel.state)
    }

    /// Both trade modes edit the same two local-perspective piles. Bank changes
    /// the quantity step and availability, never the meaning or position of a row.
    private var tradeBuilder: some View {
        VStack(alignment: .leading, spacing: 12) {
            builderTools
            if mode == .bank, isShowingBankHelp {
                Text("One give bundle buys one card. Your ports set each rate. Tap a square to add; minus removes a bundle.")
                    .font(.caption)
                    .foregroundStyle(CatanTheme.onWaterText.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            TradeResourceRow(draft: draftFeedback, isGive: true,
                             onAdd: { add($0, toGive: true) }, onRemove: { remove($0, fromGive: true) })
            Divider().overlay(CatanTheme.chipGold.opacity(0.4))
            TradeResourceRow(draft: draftFeedback, isGive: false,
                             onAdd: { add($0, toGive: false) }, onRemove: { remove($0, fromGive: false) })
            Label(draftFeedback.message,
                  systemImage: draftFeedback.canSubmit ? "checkmark.circle" : draftFeedback.hasProblem ? "exclamationmark.circle" : "info.circle")
                .font(.caption)
                .foregroundStyle(draftFeedback.hasProblem ? Self.problemColor : CatanTheme.onWaterText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .accessibilityIdentifier("trade.feedback")
        }
    }

    private var builderTools: some View {
        HStack(spacing: 8) {
            if mode == .bank {
                Button { isShowingBankHelp.toggle() } label: {
                    Label("Bank rates", systemImage: "info.circle")
                }
                .accessibilityLabel("How bank trading works")
            } else {
                Text("Tap a square to add. Minus removes.")
                    .foregroundStyle(CatanTheme.onWaterText.opacity(0.8))
            }
            Spacer(minLength: 4)
            Button("Clear") {
                give = [:]
                want = [:]
                errorMessage = nil
            }
            .disabled(give.isEmpty && want.isEmpty)
            .accessibilityIdentifier("trade.clear")
        }
        .font(.caption)
        .foregroundStyle(CatanTheme.chipGold)
        .buttonStyle(.plain)
        .frame(minHeight: 32)
    }

    private func add(_ resource: Resource, toGive: Bool) {
        guard draftFeedback.canAdd(resource, toGive: toGive) else { return }
        let step = draftFeedback.addStep(resource)
        if toGive {
            give[resource, default: 0] += step
        } else {
            want[resource, default: 0] += 1
        }
        errorMessage = nil
    }

    private func remove(_ resource: Resource, fromGive: Bool) {
        if fromGive {
            let remaining = give[resource, default: 0] - draftFeedback.removeStep(resource)
            give[resource] = remaining > 0 ? remaining : nil
        } else {
            let remaining = want[resource, default: 0] - 1
            want[resource] = remaining > 0 ? remaining : nil
        }
        errorMessage = nil
    }

    // MARK: - The one action for the current mode

    @ViewBuilder
    private var actionButton: some View {
        switch mode {
        case .players:
            GoldRowButton(
                title: "Propose to Bots",
                systemImage: "person.2.fill",
                isEnabled: draftFeedback.canSubmit
            ) {
                let offer = TradeOffer(from: viewModel.humanPlayer, give: give, want: want)
                proposalOutcome = nil
                perform(.proposeTrade(offer))
                // Every bot's willingness is evaluated synchronously inside
                // `apply` (see `GameViewModel.resolveHumanProposedTrade`), so by
                // the time `perform` returns either `pendingTradeConfirmation`
                // is set (somebody would accept - the banner takes over, and
                // nothing is applied until the human confirms) or
                // `lastTradeOutcome` already reflects that nobody would.
                // Neither applies if the proposal itself failed.
                if errorMessage == nil, viewModel.pendingTradeConfirmation == nil {
                    proposalOutcome = viewModel.lastTradeOutcome
                }
            }
        case .bank:
            GoldRowButton(
                title: "Trade with Bank",
                systemImage: "building.columns.fill",
                iconColor: Self.bankGold,
                titleColor: Self.bankGold,
                isEnabled: draftFeedback.canSubmit
            ) {
                perform(.bankTrade(give: give, get: want))
            }
        }
    }

    // MARK: - Status region

    /// Shows a bot's answer.
    ///
    /// Rendered in place of the builder: composing and deciding are separate
    /// tasks, not two panels competing for the phone's limited space.
    /// Whether a bot's answer is occupying the card.
    private var isShowingBotResponse: Bool {
        viewModel.pendingTradeConfirmation != nil || proposalOutcome != nil
    }

    @ViewBuilder
    private var statusRegion: some View {
        if let pendingConfirmation = viewModel.pendingTradeConfirmation {
            pendingConfirmationBanner(pendingConfirmation)
        } else if let proposalOutcome {
            proposalOutcomeBanner(proposalOutcome)
        }
    }

    /// A bot said yes - shown until the human goes through with it or backs
    /// out, so accepting never just happens the instant a bot agrees. See
    /// `GameViewModel.pendingTradeConfirmation`.
    private func pendingConfirmationBanner(_ pending: GameViewModel.PendingTradeConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let offer = viewModel.state.pendingTradeOffers.first(where: { $0.id == pending.offerID }) {
                TradeTermsView(give: offer.give, receive: offer.want)
            }
            // One row per bot, each with its own message (see
            // `GameViewModel.tradeResponseMessage` - a bot always has something
            // to say, whether or not it took the deal). An accepting bot's row
            // is tappable to switch `selectedBot`; this is the point at which
            // choosing a partner is a real decision, so it is the only place a
            // partner can be chosen.
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Terms and partner replies may scroll on short phones. The actions live
    /// in the fixed footer so confirming never depends on that scroll position.
    private var pendingConfirmationActions: some View {
        VStack(spacing: 10) {
            GoldRowButton(title: "Decline", systemImage: "xmark") {
                viewModel.declinePendingTrade()
                proposalOutcome = viewModel.lastTradeOutcome
            }
            GoldRowButton(title: "Confirm Trade", systemImage: "checkmark",
                          iconColor: .green, titleColor: .green, action: confirmTrade)
        }
    }

    private func confirmTrade() {
        let previousSequence = viewModel.eventBatch.sequence
        switch viewModel.confirmPendingTrade() {
        case .succeeded:
            errorMessage = nil
            captureReceipt(after: previousSequence)
            proposalOutcome = viewModel.lastTradeOutcome
        case .offerNoLongerAvailable:
            errorMessage = "That trade is no longer available."
            proposalOutcome = viewModel.lastTradeOutcome
        case .resourcesNoLongerAvailable:
            errorMessage = "That trade could no longer go through - resources changed since you proposed it."
            proposalOutcome = viewModel.lastTradeOutcome
        case .persistenceFailed:
            errorMessage = "The trade could not be saved. Please try again."
        }
    }

    /// Every bot's answer and its message, not just whoever took the offer (or,
    /// if nobody did, a bare "no one accepted") - so a fully-declined proposal
    /// still comes back with real reactions instead of a silent wall.
    private func proposalOutcomeBanner(_ outcome: GameViewModel.TradeOutcome) -> some View {
        let headline = outcome.acceptedBy.map { "\(viewModel.playerIdentity(for: $0).displayName) accepted!" }
            ?? "No one accepted that trade."
        let headlineColor: Color = outcome.acceptedBy != nil ? .green : .red

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: outcome.acceptedBy != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                Text(headline)
                    .font(.subheadline.bold())
            }
            .foregroundStyle(headlineColor)

            ForEach(outcome.decisions, id: \.bot) { decision in
                tradeMessageRow(decision, systemImage: decision.accepted ? "checkmark.circle.fill" : "xmark")
                    .foregroundStyle(decision.accepted ? .green : .red.opacity(0.7))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    /// One bot's name and message, shared between the pending banner and the
    /// resolved one - only the leading icon and the caller's colour differ.
    private func tradeMessageRow(_ decision: (bot: PlayerID, accepted: Bool, message: String), systemImage: String) -> some View {
        let identity = viewModel.playerIdentity(for: decision.bot)
        return HStack(alignment: .top, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                CivilizationCrest(civilization: identity.civilization, size: 30)
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(decision.accepted ? Color.green : Color.red, in: Circle())
            }
            // `TradeMessages`'s pools are capped at 38 characters (see its own
            // doc comment) so a line fits on one row at this size within the
            // popup's width, with no `lineLimit` or shrinking needed.
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(identity.displayName)
                        .font(.subheadline.bold())
                    Text(identity.civilization.displayName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                }
                Text(decision.message)
                    .font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func perform(_ move: GameMove) {
        do {
            let previousSequence = viewModel.eventBatch.sequence
            try viewModel.apply(move)
            captureReceipt(after: previousSequence)
            errorMessage = nil
            give = [:]
            want = [:]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func captureReceipt(after previousSequence: Int) {
        // A duplicate confirmation is an intentional no-op in the view model.
        // It must not redisplay a receipt from an older event batch.
        guard viewModel.eventBatch.sequence != previousSequence else { return }
        receipt = viewModel.eventBatch.events.compactMap {
            TradeReceipt(event: $0, player: viewModel.humanPlayer)
        }.last
    }
}
