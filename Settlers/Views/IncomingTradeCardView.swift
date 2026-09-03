import SwiftUI
import CatanEngine
import CatanAI

/// Small card that slides in above `HumanPlayerPanel` when a bot proposes a
/// trade to the human - a self-contained Accept/Reject card, replacing the old
/// "wants to trade" toast that just jumped to the trade sheet.
///
/// Every offer reaching this card is one the human can actually fulfil (see
/// `GameView.handleTradeOffersChange`'s affordability filter), and
/// `GameViewModel.waitForFairAcceptWindow` holds other bots back from
/// snapping up the same offer for a randomized 2-4s.
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
    public let playerLabel: (PlayerID) -> String
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
                playerLabel: @escaping (PlayerID) -> String = CatanTheme.playerLabel,
                onAccept: @escaping () -> Void, onReject: @escaping () -> Void) {
        self.isHeld = isHeld
        self.offer = offer
        self.playerLabel = playerLabel
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
                if totalSeconds > 0 {
                    // The number, not just a draining arc. An arc alone says
                    // "something is running out" without saying how long you
                    // have, which is most of what makes a timed decision
                    // stressful rather than informative.
                    Text("\(Int(remaining.rounded(.up)))")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption2)
                }
            }
            .frame(width: 32, height: 32)

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
                // `.subheadline`, not `.headline`. The line now carries the
                // proposer's name as well as their pitch, and the row lost
                // width to 44pt answer buttons - at headline size that
                // combination truncated mid-word ("...approve. Tr..."), which
                // is worse than slightly smaller text on a line whose whole job
                // is to say who wants what.
                (
                    Text("\(playerLabel(offer.from)): ").font(.subheadline.bold())
                        + Text(TradeMessages.pitch(offer: offer,
                                                   empire: Civilization.forSeat(offer.from.index).tradeMessagesEmpire))
                        .font(.subheadline)
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

            // 44pt targets, 16pt apart. They were 7pt of padding around a
            // footnote glyph - roughly 28pt - sitting 8pt apart, which is
            // under Apple's 44pt minimum and close enough together to make
            // rejecting a trade you meant to accept an easy slip. This is a
            // two-way decision with no undo, so the two buttons should not be
            // adjacent thumb-sized targets.
            HStack(spacing: 16) {
                answerButton(
                    systemImage: "xmark",
                    tint: .red,
                    identifier: AccessibilityID.IncomingTrade.reject,
                    action: onReject
                )
                answerButton(
                    systemImage: "checkmark",
                    tint: .green,
                    identifier: AccessibilityID.IncomingTrade.accept,
                    action: onAccept
                )
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

    private func answerButton(
        systemImage: String,
        tint: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .frame(width: Self.answerButtonDiameter, height: Self.answerButtonDiameter)
                .background(tint.opacity(0.9), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// Apple's minimum comfortable touch target.
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
                guard !isPaused, !isHeld else { continue }
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
