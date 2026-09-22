import SwiftUI
import CatanEngine
import CatanAI

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

    public var body: some View {
        let identity = playerIdentity(offer.from)
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: totalSeconds > 0 ? remaining / totalSeconds : 1)
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                CivilizationCrest(civilization: identity.civilization, size: 27)
                if totalSeconds > 0 {
                    // The number, not just a draining arc. An arc alone says
                    // "something is running out" without saying how long you
                    // have, which is most of what makes a timed decision
                    // stressful rather than informative.
                    Text("\(Int(remaining.rounded(.up)))")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.88), in: Capsule())
                        .offset(y: 15)
                } else {
                    EmptyView()
                }
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                // The bot's own pitch line instead of a flat "X wants to
                // trade" label - deterministic per offer (see
                // `TradeMessages.pitch`), themed to the proposing empire,
                // and always shown (not just on accept) per the "message
                // should appear regardless" ask. Replaces the title outright
                // rather than adding a line, so the card's fixed height
                // never has to grow to fit it.
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
                //
                // The name is white rather than the seat's own colour: several
                // civilization colours are dark navy or near-black, which on
                // this card's blue ground read as greyed-out - the speaker
                // looked disabled. The ring on the left already carries colour.
                //
                // `.headline`, at full, unshrunk size - reported too small at
                // `.subheadline` with a `minimumScaleFactor(0.5)` floor,
                // and `.headline` alone was tried once before and reverted
                // because a long name+pitch combo truncated mid-word even
                // at that 0.5 floor ("...approve. Tr..."). `MarqueeText`
                // below is what breaks that tradeoff: it lays the line out
                // at its natural, unshrunk width and only scrolls
                // (ticker-style, looping) when that width doesn't fit the
                // row, instead of shrinking or truncating it. Short
                // lines - the common case, `TradeMessages`'s pools cap
                // every pitch at 38 characters - sit still at full size;
                // only a long name+pitch combo moves.
                MarqueeText(
                    Text("\(identity.displayName): ").font(.headline.bold())
                        + Text(TradeMessages.pitch(offer: offer,
                                                   empire: identity.civilization.tradeMessagesEmpire))
                        .font(.headline)
                )
                .frame(height: 22)
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
                // Expert composes bundles now (up to five cards across four
                // resource types), and the row is sized by the number of
                // *types*, not cards. At the original fixed metrics a four-type
                // side did not overflow visibly - SwiftUI compressed the only
                // flexible children, the count labels, to zero width. Measured
                // on the QA simulator with `-qaBundleOffer`: "Give [wheat] 3 ->
                // Get [] [] [] []", four colours and no quantities at all, so
                // the player could not tell one ore from three. A silently
                // dropped number on a two-way decision with no undo is worse
                // than a small one.
                //
                // `ViewThatFits` picks the widest density that actually fits,
                // and `.fixedSize()` inside every density makes the counts
                // incompressible - so the degradation is "tighter", never
                // "missing". Single-resource offers, the common case, still get
                // the first and largest set.
                ViewThatFits(in: .horizontal) {
                    exchangeRow(swatch: 14, font: 14, spacing: 6)
                    exchangeRow(swatch: 12, font: 12, spacing: 4)
                    exchangeRow(swatch: 10, font: 10, spacing: 3)
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
        // Vertical padding only, 8 -> 4. The card's height is fixed
        // below (`BottomRowMetrics.height`), so this padding is the only
        // thing eating into the room the pitch line's VStack has to
        // render at full size before `minimumScaleFactor` shrinks it -
        // trimming it here, not the horizontal padding, is what was
        // asked for. Horizontal stays at 8, unchanged.
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
        .overlay(RoundedRectangle(cornerRadius: 12).inset(by: 1).strokeBorder(identity.civilization.accentColor, lineWidth: 2))
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .accessibilityLabel("Trade offer from \(identity.displayName) of \(identity.civilization.displayName)")
        // Tap to hold the countdown while reading, tap again to let it run.
        // It used to only ever set this to `true` - nothing anywhere set it
        // back - so one tap stopped the timer permanently and left the tick
        // task spinning at 10 Hz doing nothing until the card went away.
        .onTapGesture {
            isPaused.toggle()
        }
        .onAppear {
            isExternallyHeld = isHeld
            startTicking()
        }
        .onChange(of: isHeld) { _, held in
            isExternallyHeld = held
        }
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
                guard !isPaused, !isExternallyHeld else { continue }
                remaining = max(0, remaining - 0.1)
            }
            onReject()
        }
    }

    /// One colored rounded square + count per held resource, sorted
    /// consistently - the same visual language `HumanPlayerPanel`'s hand
    /// row and `TradePopupView`'s chips already use, instead of a text
    /// sentence.
    private func resourceDots(_ resources: [Resource: Int],
                              swatch: CGFloat,
                              font: CGFloat,
                              spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(Resource.allCases.filter { (resources[$0] ?? 0) > 0 }, id: \.self) { resource in
                HStack(spacing: spacing > 4 ? 4 : 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(CatanTheme.color(for: resource))
                        .frame(width: swatch, height: swatch)
                    Text("\(resources[resource] ?? 0)")
                        .font(.system(size: font, weight: .bold))
                        // Without this the count is the only thing in the row
                        // SwiftUI can shrink, so it is the thing that vanishes.
                        .fixedSize()
                }
            }
        }
    }

    /// The "Give … → Get …" line at one density. `ViewThatFits` above picks the
    /// largest one that fits the card, which depends on how many resource types
    /// the offer spreads across.
    private func exchangeRow(swatch: CGFloat, font: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            Text("Give")
                .font(.system(size: font < 12 ? 10 : 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
            resourceDots(offer.want, swatch: swatch, font: font, spacing: spacing)
            Image(systemName: "arrow.right")
                .font(.system(size: font < 12 ? 10 : 12, weight: .bold))
                .foregroundStyle(.secondary)
            Text("Get")
                .font(.system(size: font < 12 ? 10 : 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
            resourceDots(offer.give, swatch: swatch, font: font, spacing: spacing)
        }
    }
}

/// A single-line `Text` that scrolls horizontally (ticker-style, looping)
/// instead of shrinking or truncating when it doesn't fit its row.
///
/// Built for `IncomingTradeCardView`'s bot-pitch line: shrinking it
/// (`minimumScaleFactor`) read too small, and the alternative -
/// truncating - reads worse (a joke cut off mid-word). Scrolling avoids
/// both: the text always renders at its real, full size, and only moves
/// when it doesn't fit. A line that already fits its row is left
/// completely still - no animation, no cost.
///
/// Two copies of the text sit side by side with a gap and slide left
/// together; the loop resets the instant the first copy has scrolled
/// fully past, at which point the second copy is already sitting exactly
/// where the first started, so the reset is invisible rather than a
/// visible jump.
private struct MarqueeText: View {
    private let text: Text
    /// Points per second the text moves. Picked by eye against how long
    /// this card actually stays on screen (`PacingPreferences`'s
    /// incoming-offer timer defaults to 15s) - fast enough that even a
    /// long line completes a full pass with room to spare, slow enough to
    /// still read while moving.
    private static let scrollSpeed: CGFloat = 65
    private static let gap: CGFloat = 24

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isAnimating = false

    init(_ text: Text) {
        self.text = text
    }

    var body: some View {
        GeometryReader { geo in
            layout
                .offset(x: offset)
                .onAppear {
                    containerWidth = geo.size.width
                    startIfNeeded()
                }
        }
        .clipped()
        .onChange(of: textWidth) { _, _ in startIfNeeded() }
    }

    /// Renders a second copy only once the first has reported a width
    /// wider than the row - `textWidth` starts at 0, so the very first
    /// layout pass is always the single-copy, static case.
    @ViewBuilder
    private var layout: some View {
        if textWidth > containerWidth, containerWidth > 0 {
            HStack(spacing: Self.gap) {
                measuredText
                measuredText
            }
        } else {
            measuredText
        }
    }

    private var measuredText: some View {
        text
            .lineLimit(1)
            .fixedSize()
            .background(
                GeometryReader { textGeo in
                    Color.clear
                        .preference(key: MarqueeWidthKey.self, value: textGeo.size.width)
                }
            )
            .onPreferenceChange(MarqueeWidthKey.self) { textWidth = $0 }
    }

    private func startIfNeeded() {
        guard !isAnimating, textWidth > containerWidth, containerWidth > 0 else { return }
        isAnimating = true
        let distance = textWidth + Self.gap
        let duration = Double(distance / Self.scrollSpeed)
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = -distance
        }
    }
}

private struct MarqueeWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
