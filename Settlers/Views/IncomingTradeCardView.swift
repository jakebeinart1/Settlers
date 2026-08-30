import SwiftUI
import CatanEngine
import CatanAI

/// Small card that slides in above `HumanPlayerPanel` when a bot proposes a
/// trade to the human - replaces the old "wants to trade" toast (which just
/// jumped to the trade sheet) with a self-contained Accept/Reject card and a
/// 6-second countdown ring. Every offer that reaches this card is already
/// one the human can actually fulfill (see `GameView
/// .handleTradeOffersChange`'s `humanCanAfford` filter), and
/// `GameViewModel.waitForFairAcceptWindow` holds any other bot back from
/// accepting the same offer for a randomized 2-4s, so 6s leaves real
/// decide-and-tap time even in the worst case. The countdown only runs
/// while the card is untouched; tapping anywhere on the card (to read it)
/// pauses the timer so reviewing an offer never causes it to auto-decline
/// out from under you. Timing out untouched counts as a Reject
/// (`respondToTrade(accept: false)`).
public struct IncomingTradeCardView: View {
    public let offer: TradeOffer
    public let onAccept: () -> Void
    public let onReject: () -> Void

    public init(offer: TradeOffer, onAccept: @escaping () -> Void, onReject: @escaping () -> Void) {
        self.offer = offer
        self.onAccept = onAccept
        self.onReject = onReject
    }

    /// Seconds before the card answers for you. **Zero means never**, which is
    /// the shipped default.
    ///
    /// This was a hardcoded 6. Six seconds is not a decision window - a bot
    /// proposes, you read who it is and what it wants, and the card
    /// auto-declines while you are still reading. It was reported as offers
    /// vanishing before they could be answered. A trade you did not answer is
    /// not a trade you declined, so the timer is off unless someone
    /// deliberately turns it on in `pacing.yml`.
    private var totalSeconds: Double { PacingSettingsStore.current.incomingOfferTimeoutSeconds }
    @State private var remaining: Double = 0
    @State private var isPaused = false
    /// A monotonically increasing tick source (0.1s) rather than a single
    /// `Task.sleep(for: totalSeconds)`, so pausing on tap genuinely halts
    /// the countdown instead of just hiding a timer that fires anyway.
    @State private var tickTask: Task<Void, Never>?

    public var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: totalSeconds > 0 ? remaining / totalSeconds : 1)
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 4) {
                // The bot's own pitch line instead of a flat "X wants to
                // trade" label - deterministic per offer (see
                // `TradeMessages.pitch`), themed to the proposing empire,
                // and always shown (not just on accept) per the "message
                // should appear regardless" ask. Replaces the title outright
                // rather than adding a line, so the card's fixed height
                // never has to grow to fit it.
                // `.headline` - bumped up from `.subheadline`, readable at a
                // glance rather than squinted at. Room for it comes from two
                // places: the ring/buttons/spacing in this row were already
                // trimmed down (see below), and every line in
                // `TradeMessages`'s pools is capped at 38 characters
                // (`TradeMessagesTests.everyLineFitsTheIncomingCardsCharacterBudget`)
                // specifically so this text fits at full size without
                // relying on `minimumScaleFactor` to make room for it.
                // `minimumScaleFactor` is a real, load-bearing backstop
                // here (not just a rounding-error safety net) - the 38-char
                // cap alone wasn't tight enough to guarantee every line
                // fits `.headline` at full size (measured: a 37-char line
                // still truncated at a 0.75 floor), so 0.5 is kept as the
                // proven-safe floor from `.subheadline` testing rather than
                // narrowing the cap further and losing more of the joke.
                // The proposer's NAME leads, then their pitch. The pitch alone
                // was the whole headline, and with no speaker attached a line
                // like "Even Zeus approves this trade." reads as ambient
                // commentary about something that already happened - an FYI
                // you cannot act on - rather than as a player asking you for
                // something. The card then looks like a notification that
                // confusingly sprouted Accept and Reject buttons.
                //
                // Naming the speaker is what makes it a request, and the
                // request is what the two buttons are for.
                // Concatenated into ONE `Text`, not an `HStack` of two.
                // `minimumScaleFactor` shrinks a single text to fit; across two
                // views in a stack it cannot, so the pitch truncated mid-word
                // ("...or a bette...") while the name sat at full size. As one
                // string the whole line scales together and stays whole.
                //
                // The name is white rather than the seat's own colour: several
                // civilization colours are dark navy or near-black, which on
                // this card's blue ground read as greyed-out - the speaker
                // looked disabled. The ring on the left already carries colour.
                (
                    Text("\(CatanTheme.playerLabel(for: offer.from)): ").font(.headline.bold())
                        + Text(TradeMessages.pitch(offer: offer,
                                                   empire: Civilization.forSeat(offer.from.index).tradeMessagesEmpire))
                        .font(.headline)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // Colored dots instead of a resource-name sentence - reads
                // at a glance instead of having to parse "3 brick, 1 wool"
                // as text, matching how resources are shown everywhere else
                // (HUD hand rows, the trade builder's own chips). Explicit
                // "Give"/"Get" labels (from the human's own perspective,
                // since they're the one deciding) rather than a bare arrow
                // between two dot groups - which of `offer.give`/`.want`
                // meant "you give" vs. "you get" wasn't obvious at a
                // glance. Sized up from the original 9/11pt (the card only
                // had room for a single tight row before it was fixed to
                // match `actionRow`'s height - see chat) to actually use
                // that extra vertical space instead of leaving it as
                // padding around still-tiny text.
                HStack(spacing: 6) {
                    Text("Give")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    resourceDots(offer.want)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("Get")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    resourceDots(offer.give)
                }
            }

            Spacer(minLength: 4)

            Button {
                onReject()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.bold())
                    .padding(7)
                    .background(Color.red.opacity(0.85), in: Circle())
                    .foregroundStyle(.white)
            }
            Button {
                onAccept()
            } label: {
                Image(systemName: "checkmark")
                    .font(.footnote.bold())
                    .padding(7)
                    .background(Color.green.opacity(0.85), in: Circle())
                    .foregroundStyle(.white)
            }
        }
        .padding(8)
        // Fixed to the same height as `GameView.actionRow`/
        // `robberTargetingPanel` (`GameView.actionRowHeight`, 75.33pt,
        // duplicated here rather than shared across files for one
        // constant) - this card takes over `bottomPanel`'s row exactly
        // like those two do, so without matching their height it caused
        // the same "board resizes" issue whenever a bot's trade offer
        // appeared/cleared (see chat). Applied *before* `.background`, not
        // after, so the card's own background/border actually covers the
        // full fixed height (centered content) instead of staying its
        // smaller natural size inside a taller invisible box - see
        // `GameView.robberTargetingPanel`'s doc comment for why that
        // ordering matters.
        .frame(height: BottomRowMetrics.height)
        .background(CatanTheme.hudChipBackgroundActive, in: RoundedRectangle(cornerRadius: 12))
        // The proposing bot's own civ color, not the old flat white hairline
        // - `CatanTheme.color(for:)` is the same color used for that bot's
        // HUD card/settlements/roads, so this card reads as "from Alexander"
        // at a glance from the border alone, no name text needed. A thin
        // black keyline drawn just outside the color band (same idea as
        // `View.playerCardBorder`'s hairline/color/hairline sandwich used
        // on the HUD cards, kept to a plain `RoundedRectangle` here rather
        // than that modifier's notched-corner shape, to match this card's
        // own plain-rounded look) - several civ colors (Greece's marble,
        // Aztec/Norse/Columbia's slate-blue tones) are close enough to this
        // card's own blue background that the color alone nearly
        // disappeared without it.
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.55), lineWidth: 3.5))
        .overlay(RoundedRectangle(cornerRadius: 12).inset(by: 1).strokeBorder(CatanTheme.color(for: offer.from), lineWidth: 2))
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        // Tap to hold the countdown while reading, tap again to let it run.
        // It used to only ever set this to `true` - nothing anywhere set it
        // back - so one tap stopped the timer permanently and left the tick
        // task spinning at 10 Hz doing nothing until the card went away.
        .onTapGesture {
            isPaused.toggle()
        }
        .onAppear(perform: startTicking)
        .onDisappear { tickTask?.cancel() }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func startTicking() {
        tickTask?.cancel()
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
                guard !isPaused else { continue }
                remaining = max(0, remaining - 0.1)
            }
            onReject()
        }
    }

    /// One colored rounded square + count per held resource, sorted
    /// consistently - the same visual language `HumanPlayerPanel`'s hand
    /// row and `TradePopupView`'s chips already use, instead of a text
    /// sentence.
    private func resourceDots(_ resources: [Resource: Int]) -> some View {
        HStack(spacing: 6) {
            ForEach(Resource.allCases.filter { (resources[$0] ?? 0) > 0 }, id: \.self) { resource in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(CatanTheme.color(for: resource))
                        .frame(width: 14, height: 14)
                    Text("\(resources[resource] ?? 0)")
                        .font(.system(size: 14, weight: .bold))
                }
            }
        }
    }
}
