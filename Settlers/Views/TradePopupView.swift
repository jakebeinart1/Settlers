import SwiftUI
import CatanEngine

/// In-screen popup for building and proposing a trade.
///
/// Tap-to-move, colonist.io style: your hand sits in a tray, tapping a card
/// moves one unit into "Give"; tapping a card in the "Ask for" palette adds one
/// to "Get". Tapping a card already in a slot moves it back out.
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

    public init(viewModel: GameViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
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
    @State private var isShowingBankHelp = false

    private static let bankGold = CatanTheme.chipGold

    private var human: Player? { viewModel.state.players.first { $0.id == viewModel.humanPlayer } }

    public var body: some View {
        PopupCard(onDismiss: onDismiss, alignment: .top) {
            VStack(spacing: 14) {
                header
                // While a bot's answer is on screen the builder is hidden
                // rather than pushed below it. Two reasons, one of them a bug:
                //
                // The bug: this popup does NOT scroll. `PopupCard` says so
                // explicitly - an earlier version scrolled and that was
                // reverted because the overflow was the actual defect, not
                // something to scroll around. A previous revision here removed
                // the fixed 260pt status reservation on the stated grounds
                // that "PopupCard scrolls when tall", which was never true, and
                // with three bots accepting, "Close" went off the bottom edge
                // with no way to reach it.
                //
                // The reason it is also better: a player looking at three bots'
                // answers is deciding on an offer, not composing one. The
                // builder is noise at that moment, and reserving 260pt of blank
                // space for a banner that is absent most of the time was most
                // of why this card read as empty.
                if isShowingBotResponse {
                    statusRegion
                } else {
                    modePicker
                    tradeBuilder
                    actionButton
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // A resolved outcome ("No one accepted" / "X accepted!")
                // used to leave Close as the only way out - fine after a
                // trade actually goes through, but proposing again meant
                // closing the whole popup and reopening it from the Trade
                // button just to clear the banner. `proposalOutcome` (as
                // opposed to `pendingTradeConfirmation`, which still has its
                // own Decline/Confirm pair below) is specifically the
                // "nothing left to decide" state, so that is the one that
                // gets a way back into the builder instead of only a way out.
                if proposalOutcome != nil {
                    GoldRowButton(title: "New Offer", systemImage: "arrow.counterclockwise") {
                        proposalOutcome = nil
                        give = [:]
                        want = [:]
                        errorMessage = nil
                    }
                }
                GoldRowButton(title: "Close", systemImage: "xmark", action: onDismiss)
            }
            .padding(16)
            .frame(maxWidth: 360)
            .onAppear {
                // An all-human table has no Players tab to select.
                if !viewModel.hasBotSeats { mode = .bank }
            }
        }
    }

    private var header: some View {
        Text("Trade")
            .font(.title2.bold())
            .frame(maxWidth: .infinity, alignment: .center)
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
                    .foregroundStyle(isSelected ? CatanTheme.chipGold : Color.secondary)
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

    @ViewBuilder
    private var tradeBuilder: some View {
        switch mode {
        case .players: playerBuilder
        case .bank: bankBuilder
        }
    }

    // MARK: Trading with players

    /// Four rows, because a player trade is genuinely open-ended: any pile for
    /// any pile. Give and Want are what you have staged (tap to take back);
    /// Your hand and Ask for are where you add from.
    private var playerBuilder: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("You give")
            ResourceSlotRow(counts: give) { resource in
                give[resource] = (give[resource] ?? 0) - 1
                if give[resource] == 0 { give[resource] = nil }
            }

            sectionLabel("You want")
            ResourceSlotRow(counts: want) { resource in
                want[resource] = (want[resource] ?? 0) - 1
                if want[resource] == 0 { want[resource] = nil }
            }

            Divider().overlay(Color.white.opacity(0.2))

            sectionLabel("Your hand")
            handTray

            sectionLabel("Ask for")
            wantPalette
        }
    }

    /// Your hand. Every resource is shown, including ones you hold none of, so
    /// the row never reflows as cards come and go and "I have no ore" is
    /// visible rather than inferred from an absence.
    private var handTray: some View {
        HStack(spacing: 8) {
            ForEach(Resource.allCases, id: \.self) { resource in
                let owned = human?.resources[resource] ?? 0
                // Floored at zero because the staged pile can outlive the cards
                // backing it: stage three ore, have a bot play a knight and
                // steal one, and `give` now exceeds what is held. Rendering the
                // difference raw showed "-3", which is not a hand anyone has.
                // The stale pile is left alone rather than silently trimmed -
                // `Trading` rejects it and `perform` surfaces the reason, which
                // beats quietly altering an offer the player composed.
                let remaining = max(0, owned - (give[resource] ?? 0))
                ResourceChip(resource: resource, count: remaining, isEnabled: remaining > 0) {
                    give[resource] = (give[resource] ?? 0) + 1
                }
                .accessibilityIdentifier(AccessibilityID.Trade.giveChip(resource))
            }
        }
    }

    /// All five resources, tap to add one to Want. No ownership constraint -
    /// you are asking someone else for it.
    private var wantPalette: some View {
        HStack(spacing: 8) {
            ForEach(Resource.allCases, id: \.self) { resource in
                ResourceChip(resource: resource, count: nil) {
                    want[resource] = (want[resource] ?? 0) + 1
                }
                .accessibilityIdentifier(AccessibilityID.Trade.wantChip(resource))
            }
        }
    }

    // MARK: Trading with the bank

    /// Two rows, because a bank trade is not open-ended: you hand over a whole
    /// multiple of a card's rate and get cards back, one for one.
    ///
    /// ## Why this is not the player layout
    /// It used to be. That gave the bank tab five rows of the same five
    /// hexagons - You give, You get, Your hand, Ask for, Your rate - which is
    /// four ways of saying the same thing plus a rate table nobody asked for.
    ///
    /// Everything those rows carried now lives on the give card itself: the
    /// rate is printed under it, the number you hold is its badge, and one tap
    /// stages a whole bundle at that rate. So the trade is legal by
    /// construction rather than by the player working out the arithmetic, and
    /// the "each Give resource must be a multiple of its rate" instruction -
    /// which was the app explaining its own validation rule to the player -
    /// stops being necessary.
    private var bankBuilder: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                sectionLabel("You give")
                Button { isShowingBankHelp.toggle() } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(CatanTheme.chipGold.opacity(0.9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("How bank trading works"))
                Spacer(minLength: 0)
                if !give.isEmpty || !want.isEmpty {
                    Button("Clear") { give = [:]; want = [:] }
                        .font(.caption.bold())
                        .foregroundStyle(CatanTheme.chipGold)
                        .buttonStyle(.plain)
                }
            }

            if isShowingBankHelp {
                Text("The bank swaps cards at a fixed rate. Four of a kind buys one "
                     + "of anything - or three, or two, if you have built on that port. "
                     + "Tap a card below to hand over one full trade at its rate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            bankGiveRow
            sectionLabel("You get")
            bankGetRow

            Text(bankHintText)
                .font(.caption)
                .foregroundStyle(isValidBankTrade ? Self.bankGold : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 34, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One tap stages a whole bundle - four wheat, or two if you hold the wheat
    /// port - so the pile is always a legal multiple and the player never does
    /// the division. The rate is printed under the card because it is a
    /// property of that card for that player, not a table to read elsewhere.
    private var bankGiveRow: some View {
        HStack(spacing: 8) {
            ForEach(Resource.allCases, id: \.self) { resource in
                let owned = human?.resources[resource] ?? 0
                let staged = give[resource] ?? 0
                let bundle = rate(for: resource)
                VStack(spacing: 4) {
                    ResourceChip(resource: resource,
                                 count: staged > 0 ? staged : owned,
                                 isEnabled: owned - staged >= bundle,
                                 isSelected: staged > 0) {
                        give[resource] = staged + bundle
                    }
                    Text("\(bundle):1")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(bundle < 4 ? CatanTheme.chipGold : Color.secondary)
                }
            }
        }
    }

    /// How many cards the staged give pile actually buys - one per whole
    /// bundle handed over.
    private var bundlesStaged: Int {
        give.reduce(0) { $0 + $1.value / max(rate(for: $1.key), 1) }
    }

    /// Locked until the give pile has paid for another card.
    ///
    /// Asking for something you have not paid for is not a trade the bank will
    /// take, and letting it be staged only to bounce off `Trading` makes the
    /// player discover the rate rule by failing. Gating the row teaches the
    /// same rule by making the illegal thing simply not tappable: hand over
    /// four wheat and one card unlocks; hand over eight and two do.
    private var bankGetRow: some View {
        let unspent = bundlesStaged - want.values.reduce(0, +)
        return HStack(spacing: 8) {
            ForEach(Resource.allCases, id: \.self) { resource in
                let staged = want[resource] ?? 0
                ResourceChip(resource: resource, count: staged > 0 ? staged : nil,
                             isEnabled: unspent > 0 || staged > 0,
                             isSelected: staged > 0) {
                    // A card already asked for always REMOVES one on tap, and
                    // an unasked one adds. Previously a tap added while any
                    // bundle was unspent and only removed once none were, so
                    // undoing a mis-tap gave you a second of the thing you did
                    // not want - and the only escape was Clear, which also
                    // threw away the cards you had staged to pay with.
                    if staged > 0 {
                        want[resource] = staged == 1 ? nil : staged - 1
                    } else {
                        want[resource] = 1
                    }
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .kerning(0.8)
            .foregroundStyle(.secondary)
    }

    // MARK: - The one action for the current mode

    @ViewBuilder
    private var actionButton: some View {
        switch mode {
        case .players:
            GoldRowButton(
                title: "Propose to Bots",
                systemImage: "person.2.fill",
                isEnabled: !give.isEmpty && !want.isEmpty
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
                isEnabled: isValidBankTrade
            ) {
                perform(.bankTrade(give: give, get: want))
            }
        }
    }

    // MARK: - Status region

    /// Shows a bot's answer.
    ///
    /// Only ever rendered in place of the builder (see `body`), never below
    /// it - this popup cannot scroll, so anything that does not fit is simply
    /// unreachable.
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

            VStack(spacing: 10) {
                GoldRowButton(title: "Decline", systemImage: "xmark", action: {
                    viewModel.declinePendingTrade()
                    proposalOutcome = viewModel.lastTradeOutcome
                })

                GoldRowButton(title: "Confirm Trade", systemImage: "checkmark", iconColor: .green, titleColor: .green, action: {
                    // A failed confirm used to silently do nothing - no error,
                    // no changed cards, no indication why - because `try?`
                    // swallowed the failure. Now it is reported like any other
                    // failed move.
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
                    case .persistenceFailed:
                        errorMessage = "The trade could not be saved. Please try again."
                    }
                })
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
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

    // MARK: - Bank trade

    private func rate(for resource: Resource) -> Int {
        Trading.bestRate(for: resource, player: viewModel.humanPlayer, state: viewModel.state)
    }

    /// Asks the engine rather than re-deriving the rule. A previous local copy
    /// checked the exchange rates but not the bank's stock, so a trade the
    /// engine would reject still lit the button up and produced a misleading
    /// error on tap - see `Trading.bankTradeProblem`.
    private var bankTradeProblem: MoveError? {
        guard !give.isEmpty, !want.isEmpty else { return .illegalPlacement }
        return Trading.bankTradeProblem(give: give, get: want,
                                        by: viewModel.humanPlayer, state: viewModel.state)
    }

    private var isValidBankTrade: Bool { bankTradeProblem == nil }

    private var bankHintText: String {
        if give.isEmpty && want.isEmpty {
            return "Tap a card to hand over one trade's worth."
        }
        if give.isEmpty { return "Pick a card to give first - what you get unlocks once it is paid for." }
        if want.isEmpty {
            let buys = bundlesStaged
            return "That buys \(buys) card\(buys == 1 ? "" : "s"). Now pick what you want."
        }
        switch bankTradeProblem {
        case nil:
            let total = want.values.reduce(0, +)
            return "Ready to trade for \(total) card\(total == 1 ? "" : "s")."
        case .bankCannotSupply(let resource):
            // Name the real obstacle. This used to surface as "you don't have
            // enough resources", which is about the player's hand and is the
            // opposite of what has gone wrong.
            return "The bank has no \(resource.rawValue) left. Ask for something else."
        case .insufficientResources:
            return "You do not hold that many cards to give."
        case .illegalPlacement:
            // What `Trading` returns when the piles do not balance.
            let asked = want.values.reduce(0, +)
            return "That buys \(bundlesStaged) card\(bundlesStaged == 1 ? "" : "s"), but you asked for \(asked)."
        case .some(let problem):
            // Anything else is not about rates, and saying it is would be the
            // same misreport `.bankCannotSupply` was split out to fix.
            return problem.localizedDescription
        }
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
