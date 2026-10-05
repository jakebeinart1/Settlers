import SwiftUI
import CatanEngine

/// Small card that slides in above `HumanPlayerPanel` when a bot proposes a
/// trade to the human - a self-contained Accept/Reject card, replacing the old
/// "wants to trade" toast that just jumped to the trade sheet.
///
/// Every offer reaching this card is one the human can actually fulfil (see
/// `GameView.handleTradeOffersChange`'s affordability filter), and the bot
/// loop stays stopped while it is open (`GameViewModel.openIncomingOffer`), so
/// no other bot can snap up the same offer first.
///
/// ## It no longer answers for you in six seconds
/// This used to run a hardcoded six-second countdown and auto-Reject on
/// expiry, with a ring showing the time left. Six seconds is not a decision
/// window - a bot proposes, you read who it is and what it wants, and it
/// declines while you are still reading - and a trade you did not answer is
/// not a trade you declined. The window is now the player's own choice
/// (`PacingPreferences.incomingOfferTimer`, In-Game Settings), defaulting to
/// 15s and offering "No Limit". Tapping the card pauses whatever countdown is
/// running.
public struct IncomingTradeCardView: View {
    public let offer: TradeOffer
    public let onAccept: () -> Void
    public let onReject: () -> Void
    public let playerIdentity: (PlayerID) -> PlayerIdentity
    /// Halts the countdown without the player having to tap the card.
    ///
    /// The only pause condition used to be a tap, so the timer kept draining
    /// behind `InGameSettingsView` - a later sibling in the same `ZStack`,
    /// which never removes this view from the hierarchy - and auto-declined a
    /// real offer behind the very screen whose own copy says nothing moves
    /// while you decide, and which a player most plausibly opened in order to
    /// lengthen that timer.
    public var isHeld: Bool = false

    public init(offer: TradeOffer, isHeld: Bool = false,
                playerIdentity: @escaping (PlayerID) -> PlayerIdentity = CatanTheme.playerIdentity,
                onAccept: @escaping () -> Void, onReject: @escaping () -> Void) {
        self.isHeld = isHeld
        self.offer = offer
        self.playerIdentity = playerIdentity
        self.onAccept = onAccept
        self.onReject = onReject
    }

    /// Seconds this card is counting down from. **Zero means never** - what
    /// the player's "No Limit" choice resolves to.
    ///
    /// Read from `PacingPreferences` once, in `startTicking`, and held for the
    /// life of the card rather than recomputed on every render. It is the
    /// denominator of the ring below, and the player can now change the
    /// setting *while an offer is on screen* (In-Game Settings sits over the
    /// board, and the bots are held for the whole time it is open): a computed
    /// property let that change land mid-countdown, so the arc jumped, and
    /// switching to "No Limit" hid the number while the already-running tick
    /// task carried on to auto-decline the offer anyway. Capturing means a
    /// change applies to the next offer, which is the only coherent answer.
    ///
    /// It was a hardcoded 6 once: offers vanished before they could be
    /// answered, which is what got reported, and 15s is the default that
    /// replaced it.
    @State private var totalSeconds: Double = 0
    @State private var remaining: Double = 0
    @State private var isPaused = false
    @State private var isExternallyHeld = false
    /// A monotonically increasing tick source (0.1s) rather than a single
    /// `Task.sleep(for: totalSeconds)`, so pausing on tap genuinely halts
    /// the countdown instead of just hiding a timer that fires anyway.
    @State private var tickTask: Task<Void, Never>?

    @State private var isReviewPresented = false

    public var body: some View {
        let identity = playerIdentity(offer.from)
        let summary = IncomingTradeSummary(offer: offer)
        // Names and exact terms wrap at each density. If neither fits, only
        // the terms scroll vertically; accepting then requires complete review.
        // Nothing changes this row's height or the board's available viewport.
        ViewThatFits(in: .vertical) {
            offerRow(identity, summary: summary, fontSize: 12, scrolling: false)
            offerRow(identity, summary: summary, fontSize: 11, scrolling: false)
            offerRow(identity, summary: summary, fontSize: 12, scrolling: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .frame(height: BottomRowMetrics.height)
        .background(PaintedChromeBackground(fill: .tintedTexture(CatanTheme.waterBackground), cornerRadius: 12))
        .playerCardBorder(color: identity.civilization.accentColor, cornerRadius: 12, lineWidth: 2)
        .foregroundStyle(CatanTheme.onWaterText)
        .contentShape(Rectangle())
        .onTapGesture { isPaused.toggle() }
        .onAppear {
            isExternallyHeld = isHeld
            startTicking()
        }
        .onChange(of: isHeld) { _, held in isExternallyHeld = held }
        .onDisappear { tickTask?.cancel() }
        .sheet(isPresented: $isReviewPresented) {
            IncomingTradeReviewView(summary: summary, identity: identity,
                                    onAccept: { isReviewPresented = false; onAccept() },
                                    onReject: { isReviewPresented = false; onReject() },
                                    onBack: { isReviewPresented = false })
                .presentationDetents([.large])
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func offerRow(_ identity: PlayerIdentity, summary: IncomingTradeSummary,
                          fontSize: CGFloat, scrolling: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 4) {
                    CivilizationCrest(civilization: identity.civilization, size: 18)
                    Text("\(identity.displayName) offers a trade")
                        .font(.system(size: fontSize, weight: .bold, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("incoming-trade.proposer")
                }
                if scrolling {
                    ScrollView(.vertical) { exchangeSummary(summary, fontSize: fontSize) }
                } else {
                    exchangeSummary(summary, fontSize: fontSize)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(TradeSummarySizing(scrolling: scrolling))
            answerControls(requiresReview: scrolling || summary.requiresReview)
        }
    }

    private func exchangeSummary(_ summary: IncomingTradeSummary, fontSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.giveText)
                .foregroundStyle(CatanTheme.chipGold)
                .accessibilityIdentifier("incoming-trade.give")
            Text(summary.receiveText)
                .foregroundStyle(TradeResourceRow.receiveAccent)
                .accessibilityIdentifier("incoming-trade.receive")
        }
        .font(.system(size: fontSize, weight: .semibold))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func answerControls(requiresReview: Bool) -> some View {
        HStack(spacing: 8) {
            rejectButton
            if requiresReview {
                reviewButton
            } else {
                Button(action: onAccept) {
                    Image(systemName: "checkmark").font(.headline.bold())
                        .frame(width: Self.answerButtonDiameter, height: Self.answerButtonDiameter)
                        .background(Color.green.opacity(0.85), in: Circle())
                }
                .accessibilityLabel("Accept trade")
                .accessibilityIdentifier(AccessibilityID.IncomingTrade.accept)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .fixedSize()
    }

    private var rejectButton: some View {
        Button(action: onReject) {
            VStack(spacing: 1) {
                Image(systemName: "xmark").font(.headline.bold())
                if totalSeconds > 0 {
                    Text(isPaused || isExternallyHeld || isReviewPresented ? "Held" : "\(Int(remaining.rounded(.up)))s")
                        .font(.system(size: 9, weight: .bold)).monospacedDigit()
                }
            }
            .frame(width: Self.answerButtonDiameter, height: Self.answerButtonDiameter)
            .background(Color.red.opacity(0.85), in: Circle())
            .overlay(timerRing)
        }
        .accessibilityLabel("Decline trade")
        .accessibilityIdentifier(AccessibilityID.IncomingTrade.reject)
    }

    private var reviewButton: some View {
        Button { isReviewPresented = true } label: {
            VStack(spacing: 2) {
                Image(systemName: "doc.text.magnifyingglass").font(.headline)
                Text("Review").font(.system(size: 9, weight: .bold))
            }
            .frame(width: Self.answerButtonDiameter, height: Self.answerButtonDiameter)
            .background(CatanTheme.chipGold.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(CatanTheme.chipGold))
        }
        .accessibilityLabel("Review full trade")
        .accessibilityIdentifier("incoming-trade.review")
    }

    private var timerRing: some View {
        Circle()
            .trim(from: 0, to: totalSeconds > 0 ? remaining / totalSeconds : 1)
            .stroke(CatanTheme.chipGold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .accessibilityHidden(true)
    }

    private static let answerButtonDiameter: CGFloat = 44

    private func startTicking() {
        tickTask?.cancel()
        totalSeconds = PacingPreferences.shared.incomingOfferTimer.seconds
        // No countdown at all when the timeout is off - not a very long one.
        // A ticking task that never fires still spins at 10 Hz for as long as
        // the card is up, and the ring would drain toward an answer that is
        // never given.
        guard totalSeconds > 0 else {
            remaining = 0
            return
        }
        remaining = totalSeconds
        tickTask = Task {
            while remaining > 0 {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
                guard !isPaused, !isExternallyHeld, !isReviewPresented else { continue }
                remaining = max(0, remaining - 0.1)
            }
            onReject()
        }
    }
}

/// Non-scrolling candidates report their complete height to ViewThatFits.
/// The final candidate takes the fixed row's proposal and scrolls only terms.
private struct TradeSummarySizing: ViewModifier {
    let scrolling: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if scrolling {
            content
        } else {
            content.fixedSize(horizontal: false, vertical: true)
        }
    }
}
