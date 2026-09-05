import SwiftUI
import CatanEngine
import CatanAI
/// The composed game screen: opponent HUD, board, private player panel, and
/// one Build/Trade/turn-action row over a continuous scenic background.
///
/// `TradePopupView`/`DevCardPopupView`/`DiscardPopupView` are overlays driven
/// by view state; the mandatory post-7-roll robber move *and* the voluntary
/// knight-card robber move both happen inline on this same `BoardView` (see
/// `isRobberTargetingActive`) rather than as a separate modal. Incoming bot
/// trade offers surface as a small `IncomingTradeCardView` right above
/// `HumanPlayerPanel`, with a countdown set by `PacingPreferences` and
/// defaulting to 15 seconds - or none at all, if the player chose No Limit.
///
/// A roll used to also spawn small resource badges flying from each
/// producing tile to the gaining player's HUD spot - dropped in favor of
/// just the dice chip and the board's own roll-matching tile highlight,
/// which already say the same thing with far less visual noise to track.
public struct GameView: View {
    public let viewModel: GameViewModel
    /// Called when the player confirms "Main Menu" from the pause menu -
    /// `ContentView` is responsible for actually switching screens (mirrors
    /// `EndGameView`'s own exit-to-menu callback), since the current game
    /// stays saved either way and `GameView` has no notion of "menu" itself.
    public let onExitToMenu: () -> Void

    public init(viewModel: GameViewModel, onExitToMenu: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onExitToMenu = onExitToMenu
    }

    // `-qaShowPauseMenu`: same escape hatch as `-qaAutoStart` (see
    // `ContentView`) - lets QA screenshot the in-game settings screen without
    // a real tap. The flag keeps its original name because the run-settlers
    // skill documents it under that name; what it opens is now
    // `InGameSettingsView`, which absorbed the old pause menu.
    @State var isShowingInGameSettings = QALaunchFlag.showPauseMenu.isSet
    @State private var placementMode: PlacementMode?
    // `-qaShowTradePopup`: same escape hatch pattern - lets QA screenshot
    // the trade popup without a real tap.
    @State private var showTradePopup = QALaunchFlag.showTradePopup.isSet
    // `-qaShowBuildPopup`: same escape hatch pattern - lets QA screenshot
    // the build popup without a real tap.
    @State private var showBuildPopup = QALaunchFlag.showBuildPopup.isSet
    // `-qaShowMonopolyPopup` remains the visual fixture for the longest card
    // detail state. The production path opens the same surface from the
    // permanent shelf, including when a card is not currently playable.
    @State private var showDevCardHand = QALaunchFlag.showMonopolyPopup.isSet
        || QALaunchFlag.showDevCardHand.isSet
    @State private var devCardPopupType: DevCardType? =
        (QALaunchFlag.showMonopolyPopup.isSet ? .monopoly : nil)
    @State private var errorMessage: String?

    // Legacy keys, kept only as the last-resort Restart fallback for a save
    // started before New Game Setup existed. `MainMenuView` used to write them
    // from two toggles; those toggles are gone and the match contract lives in
    // `MatchSetupStore` now, so nothing writes these any more and Restart
    // reaches them only when no stored setup exists at all.
    @AppStorage("randomizedBoardSetting") private var randomizedBoardSetting = true
    @AppStorage("randomizeSeatSetting") private var randomizeSeatSetting = true

    /// Road-building sub-flow: `nil` when inactive; once armed, the first
    /// tapped edge is held here while the second is picked, then both are
    /// applied together as `.playRoadBuilding(first, second)`.
    @State private var roadBuildingFirstEdge: EdgeID?
    @State private var isRoadBuildingActive = false

    /// Robber-move sub-flow, inline on the main board - covers both the
    /// mandatory post-7-roll move (`isMandatoryRobberActive`) and the
    /// voluntary knight-card move (`isKnightRobberActive`): once the human
    /// taps a legal tile, it's held here while an eligible victim (if any)
    /// is picked from the inline picker in `bottomPanel`; committing (or a
    /// tile with no eligible victims) applies the matching move directly.
    @State private var robberTargetTile: HexCoordinate?
    @State private var isKnightRobberActive = false

    /// Drives the dice chip's brief scale/rotate pulse on a new roll -
    /// bumped in `onChange(of: state.lastDiceRoll)`.
    @State var diceScale: CGFloat = 1.0
    @State var diceRotation: Double = 0

    /// Drives a slow glow pulse on the "Roll Dice" button so it's obvious
    /// that's the one thing to do right now - starts as soon as that button
    /// appears (see its `.onAppear` below) and just stops mattering once
    /// the phase moves on and a different button takes its place.
    @State private var rollDicePulse = false

    /// Queued incoming bot trade offers, shown one at a time via
    /// `IncomingTradeCardView`. Seeded/grown by diffing
    /// `state.pendingTradeOffers` on each render.
    @State private var incomingOfferQueue: [TradeOffer] = []
    @State private var seenTradeOfferIDs: Set<UUID> = []

    /// Tiles matching the most recent roll, briefly outlined on the board.
    /// Driven by the engine's `.rolled` event - see `handleEvents`.
    @State private var rollHighlightTiles: Set<HexCoordinate> = []

    /// The dice chip's own small history line - up to the 3 rolls before
    /// the current one, oldest last, shown in a faded caption so someone
    /// glancing at the screen mid-conversation can catch up on recent rolls
    /// without the drama of a live animation demanding their attention.
    @State var rollHistory: [Int] = []

    // Seeded with the row's actual measured height (rendered a
    // faithful reproduction and read off its real size) rather than 0 -
    // `StableHeightSlot` still grows to fit if real content ever needs more,
    // but starting from a real estimate means there's no gap between "app
    // just launched" and "something has measured once" for the board to
    // flicker through. That gap - not the measure-after-the-fact approach
    // itself - was the actual hole in the previous fix: this was 0 until the
    // first real occurrence, and a bare `Color.clear` placeholder (now fixed
    // separately) was what turned that brief 0 into a collapsed board.
    /// Reserved height for the road-building hint / error message row - see
    /// `StableHeightSlot`. Shared by the road-building hint and the error
    /// message, the only two occupants now that the incoming-trade card lives
    /// in `bottomPanel` instead - seeded at one caption line's height (~20pt).
    @State private var infoBannerHeight: CGFloat = 20

    var state: GameState { viewModel.state }
    private var human: PlayerID { viewModel.humanPlayer }

    public var body: some View {
        ZStack {
            // The scenic Ghibli/Frieren-influenced seaside painting behind
            // everything, replacing the old flat waterBackground color -
            // see design-references/STATUS.md. Every HUD chip/panel drawn
            // on top of it (BotHUDRow, HumanPlayerPanel, the dice/deck
            // chips) already fills its own solid background color, so
            // legibility isn't affected by swapping what's behind them.
            GeometryReader { geo in
                // Fit the painting to a *shorter* target height than the
                // screen (see `backgroundZoomOut` below), then pin that
                // shorter block to the top - `.scaledToFill()` always picks
                // the smallest scale that still covers its target frame, so
                // handing it a shorter target height means a smaller overall
                // scale, which shows more of the painting on every axis (a
                // deliberate "zoom out a touch" versus a plain full-bleed
                // fill, which was cropping in tight enough to lose most of
                // the sky/mountains and the far side of the painting).
                // Pinning to `.top` (rather than the default vertical
                // center) means the shortfall at the bottom - the painting's
                // own water/foreground, not the sky - lands behind the
                // opaque bottom UI (HumanPlayerPanel + action row), never a
                // visible gap. `waterBackground` behind it is just a safety
                // net in case that math is ever off on some other device's
                // aspect ratio - it matches the painting's own water tone.
                let backgroundZoomOut: CGFloat = 0.90
                Image("board-background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height * backgroundZoomOut, alignment: .leading)
                    .clipped()
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
            .background(CatanTheme.waterBackground)
            .ignoresSafeArea()

            // `spacing: 0` rather than a uniform 8pt everywhere - board,
            // banner slot, and `HumanPlayerPanel` need to sit genuinely
            // flush against each other (no gap at all), while the rows
            // above the board still want *some* visual separation. Spacing
            // is added explicitly with `.padding(.bottom:)` only where it's
            // actually wanted, instead of uniformly.
            VStack(spacing: 0) {
                // Horizontal margin here (not on `boardArea` below, which
                // stays exactly as wide as it's always been - see chat) so
                // the cards read as sitting a little off the screen's edge
                // rather than flush against it, same as the reference.
                BotHUDRow(state: state, human: human, playerIdentity: viewModel.playerIdentity)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 3)

                boardArea

                // The road-building hint and a build/move error share one
                // slot (see `StableHeightSlot`) - the incoming-trade card
                // used to live here too, but a bot can only ever propose one
                // while it's *not* the human's turn (see `bottomPanel`'s own
                // comment), the same window where the action row below has
                // nothing real to do anyway - so it now takes over that row
                // directly instead of adding a whole extra reserved banner
                // just for itself.
                StableHeightSlot(height: $infoBannerHeight) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else {
                        // `.frame(height: 0)` is load-bearing here, not
                        // decoration: a bare `Color.clear` has no intrinsic
                        // size and greedily fills all available space in a
                        // `VStack` - on first launch, before any slot has
                        // measured a real height yet, that made this
                        // "nothing to show" placeholder compete with the
                        // board for the same flexible space and squeeze it
                        // down to a fraction of the screen. Caught by
                        // rendering the exact structure in isolation - see
                        // chat - after it shipped once already.
                        Color.clear.frame(height: 0)
                    }
                }

                // No top padding here - this needs to sit genuinely flush
                // against the banner slot above it (board -> banner ->
                // here reads as one continuous stack, not three separate
                // boxes with gaps between them).
                if !isDiscardPresented {
                    HumanPlayerPanel(
                        state: state,
                        human: human,
                        playerIdentity: viewModel.playerIdentity,
                        onOpenDevCards: { type in
                            devCardPopupType = type
                            showDevCardHand = true
                        }
                    )
                    .padding(.horizontal, 12)
                }

                bottomPanel
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .allowsHitTesting(!isDiscardPresented)
                    .accessibilityHidden(isDiscardPresented)
            }
            // A full-screen card/popup visually blocks the board; it must do
            // the same for VoiceOver. Leaving the private shelf in the
            // accessibility tree produced two elements with identical card
            // identifiers and let an assistive-technology user activate the
            // hidden board beneath the modal.
            .allowsHitTesting(!isBlockingOverlayPresented)
            .accessibilityHidden(isBlockingOverlayPresented)

            if !isDiscardPresented && showBuildPopup {
                BuildPopupView(viewModel: viewModel, placementMode: $placementMode, onDismiss: { showBuildPopup = false })
                    .accessibilityHidden(viewModel.needsHandoff)
            }

            if !isDiscardPresented && showTradePopup {
                TradePopupView(viewModel: viewModel, onDismiss: { showTradePopup = false })
                    .accessibilityHidden(viewModel.needsHandoff)
            }

            if !isDiscardPresented,
               let reveal = viewModel.pendingDevCardReveal, reveal.owner == human {
                DevelopmentCardOverlay(
                    // A winning receipt remains while its hand is inspected;
                    // clearing it would mount EndGame immediately.
                    mode: showDevCardHand ? .hand : .reveal(reveal),
                    state: state,
                    player: human,
                    selectedType: $devCardPopupType,
                    onBeginBoardCard: handleDevCardPlay,
                    onCommit: commitDevCard,
                    onViewCards: { card in
                        if case .gameOver = state.phase {
                            devCardPopupType = card
                            showDevCardHand = true
                            return
                        }
                        guard viewModel.dismissDevCardReveal() else { return }
                        devCardPopupType = card
                        showDevCardHand = true
                    },
                    onDismiss: {
                        if showDevCardHand {
                            showDevCardHand = false
                            devCardPopupType = nil
                        } else {
                            _ = viewModel.dismissDevCardReveal()
                        }
                    }
                )
                .accessibilityHidden(viewModel.needsHandoff)
            } else if !isDiscardPresented,
                      let resolution = viewModel.pendingDevCardResolution,
                      resolution.owner == human {
                DevelopmentCardResultOverlay(
                    resolution: resolution,
                    playerIdentity: viewModel.playerIdentity,
                    isWinningResult: {
                        if case .gameOver = state.phase { return true }
                        return false
                    }()
                ) {
                    _ = viewModel.dismissDevCardResolution()
                }
                .accessibilityHidden(viewModel.needsHandoff)
            } else if !isDiscardPresented && showDevCardHand {
                DevelopmentCardOverlay(
                    mode: .hand,
                    state: state,
                    player: human,
                    selectedType: $devCardPopupType,
                    onBeginBoardCard: handleDevCardPlay,
                    onCommit: commitDevCard,
                    onViewCards: { _ in },
                    onDismiss: {
                        showDevCardHand = false
                        devCardPopupType = nil
                    }
                )
                .accessibilityHidden(viewModel.needsHandoff)
            }

            // The draft lives in the view model, so removing this surface
            // while Settings is open loses nothing. Keeping it mounted and
            // merely painting Settings above it left the hidden dock in the
            // VoiceOver tree, where it could still be activated through a
            // visually opaque screen.
            if isDiscardPresented && !isShowingInGameSettings {
                DiscardPopupView(viewModel: viewModel)
                    .accessibilityHidden(viewModel.needsHandoff)
            }

            if isShowingInGameSettings {
                // Surface B: painted pacing, trade-timer, and match controls.
                InGameSettingsView(
                    onResume: { isShowingInGameSettings = false },
                    onRestart: {
                        isShowingInGameSettings = false
                        // Replays the match the player configured on New Game
                        // Setup - table size, victory target, who is a person
                        // and what they are called. Calling the two-flag entry
                        // point directly rebuilt a four-seat, ten-point,
                        // one-human game instead, discarding all of it without
                        // saying so. The flags are only reached when no setup
                        // has ever been stored.
                        viewModel.restartCurrentMatch(
                            fallbackRandomizedBoard: randomizedBoardSetting,
                            fallbackRandomizeSeat: randomizeSeatSetting
                        )
                    },
                    onMainMenu: {
                        isShowingInGameSettings = false
                        onExitToMenu()
                    }
                )
                .accessibilityHidden(viewModel.needsHandoff)
            }

            // Last in the stack, so it covers every popup as well as the
            // board. A hot-seat handoff has to hide a trade popup or an open
            // discard sheet just as much as it hides the hand behind them.
            // `?? humanPlayer` because `needsHandoff` is now also true when
            // nobody holds the phone and no human is owed a turn - a resumed
            // game during a bot's move. The cover names whoever will play next.
            if viewModel.needsHandoff {
                let owed = viewModel.seatOwedATurn ?? viewModel.humanPlayer
                HandoffCoverView(
                    seat: owed,
                    handSize: viewModel.state.players
                        .first { $0.id == owed }?.resources.values.reduce(0, +) ?? 0,
                    playerIdentity: viewModel.playerIdentity
                ) {
                    clearSeatInteractionState()
                    viewModel.claimDeviceForSeatOwedATurn()
                }
                .zIndex(100)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Screen.game)
        // Serif everywhere on the board screen - HUD, popups, buttons,
        // pause menu - to match the reference's painted-book serif type
        // instead of the system San Francisco default. Every popup above
        // lives inside this same ZStack, so one modifier here covers them
        // all; `Text` drawn directly into `Canvas` (the hex numbers, robber
        // number, port ratio labels in `TileDrawing`) doesn't inherit this
        // environment value the normal way and needs its own explicit
        // `design: .serif` on each `Font.system(...)` call instead - see
        // `TileView.swift`.
        .fontDesign(.serif)
        // Mirrors this view's blocking presentation state into the view model,
        // which is what the bot loop stops on: the game must not advance behind
        // settings or the private card hand while the player reads it.
        // `initial: true` covers launch fixtures that begin already open. The dismissal kick is
        // guarded on an actual open -> closed transition so a normal launch
        // doesn't fire a second, redundant `runBotTurnIfNeeded` alongside the
        // `.task` below.
        .onChange(of: isBotBlockingSurfaceOpen, initial: true) { wasOpen, isOpen in
            viewModel.isBlockingSurfaceOpen = isOpen
            if wasOpen && !isOpen {
                Task { await viewModel.runBotTurnIfNeeded() }
            }
        }
        .onAppear {
            // NOT `seenTradeOfferIDs = Set(state.pendingTradeOffers.map(\.id))`
            // - that blindly marked every currently-pending offer as already
            // shown, including one that was pending but had never actually
            // been displayed as a card yet (a bot proposed it, then the app
            // was closed/backgrounded before the human saw it). Since
            // `handleTradeOffersChange`'s ingestion loop skips anything in
            // `seenTradeOfferIDs`, that offer could never be queued, so its
            // card could never appear - yet `GameViewModel.openIncomingOffer`
            // (the bot loop's own gate, a live computed property with no
            // such bookkeeping) still saw it as unanswered and parked the
            // bot loop on it forever. A real deadlock with nothing on screen
            // to explain it - reported as "the game just stops advancing",
            // reproduced by `GameplayBoundaryFlowTests.
            // testIncomingOfferSurvivesAppRelaunch`. Calling the real
            // ingestion path here instead correctly queues anything
            // genuinely still unanswered (and correctly leaves out anything
            // not currently fulfillable, same as every other call site).
            handleTradeOffersChange()
            // `-qaShowPendingTradeConfirmation`: same escape hatch pattern
            // as `-qaShowTradePopup` - opens the trade popup straight into
            // its "a bot will accept" confirmation step for QA
            // screenshotting, since that step depends on state
            // (`GameViewModel.pendingTradeConfirmation`) a real tap can't
            // reliably reach in the simulator.
            #if DEBUG
            if QALaunchFlag.showPendingTradeConfirmation.isSet {
                showTradePopup = true
                viewModel.qaSeedPendingTradeConfirmation()
            }
            #endif
            // `-qaShowRobberTargeting`: same escape hatch pattern - arms
            // `isKnightRobberActive` directly so `robberTargetingPanel` can
            // be screenshotted without a real Knight card/7-roll.
            if QALaunchFlag.showRobberTargeting.isSet {
                isKnightRobberActive = true
            }
        }
        .task {
            #if DEBUG
            if QALaunchFlag.showDiscard.isSet {
                viewModel.qaPrepareMandatoryDiscard()
            } else if QALaunchFlag.devCardPurchase.isSet {
                viewModel.qaPrepareDevCardPurchase(.monopoly)
            } else if QALaunchFlag.showDevCardHand.isSet || QALaunchFlag.showMonopolyPopup.isSet {
                viewModel.qaPrepareMixedDevCardHand()
                if QALaunchFlag.showDevCardHand.isSet { devCardPopupType = .knight }
            } else if QALaunchFlag.showDevCardReveal.isSet {
                viewModel.qaPrepareDevCardPurchase(.yearOfPlenty)
                do {
                    try viewModel.apply(.buyDevCard)
                    if QALaunchFlag.twoHumans.isSet {
                        viewModel.qaClearSeatAtDeviceForTesting()
                    }
                } catch {
                    assertionFailure("QA development-card reveal failed: \(error)")
                }
            } else if QALaunchFlag.showWinningDevCardReveal.isSet {
                viewModel.qaPrepareWinningDevCardPurchase()
                do {
                    try viewModel.apply(.buyDevCard)
                } catch {
                    assertionFailure("QA winning-card reveal failed: \(error)")
                }
            }
            #endif
            await qaFastForwardToRollDiceIfRequested()
            // Seed a real engine-backed offer after any fast-forwarding. The
            // UI test accepts and rejects this exact pending offer and checks
            // the human hand, so a card that merely disappears on an engine
            // error can no longer produce a green result.
            if QALaunchFlag.showIncomingOffer.isSet {
                #if DEBUG
                incomingOfferQueue = [viewModel.qaSeedIncomingTrade()]
                // `qaSeedIncomingTrade` goes through `replaceStateForTesting`,
                // which persists via `persistTestingPosition()` on its own -
                // so a UI test can `app.terminate()` right after this and
                // still find the offer pending on the next launch.
                #endif
            }
            // `-qaShowRobberVictimPicker`: same escape hatch pattern, one
            // step further than `-qaShowRobberTargeting` - arms
            // `robberTargetTile` too (to the first tile that actually has an
            // eligible victim, found by scanning the real post-setup board
            // state) so the "Steal from:" step can be screenshotted, not
            // just the "tap a tile" message before it. Runs after
            // `qaFastForwardToRollDiceIfRequested` (needs real settlements
            // on the board to find a victim from) rather than in `onAppear`.
            if QALaunchFlag.showRobberVictimPicker.isSet {
                isKnightRobberActive = true
                robberTargetTile = state.board.tiles
                    .map(\.coordinate)
                    .first { !Robber.eligibleVictims(for: $0, thief: human, in: state).isEmpty }
            }
        }
        .onChange(of: state.pendingTradeOffers.map(\.id)) { _, _ in
            handleTradeOffersChange()
        }
        .onChange(of: isDiscardPresented, initial: true) { _, isPresented in
            guard isPresented else { return }
            showBuildPopup = false
            showTradePopup = false
            showDevCardHand = false
        }
        .onChange(of: state.lastDiceRoll) { oldValue, newValue in
            guard newValue != nil else { return }
            if let oldValue {
                rollHistory = ([oldValue] + rollHistory).prefix(3).map { $0 }
            }
            animateDiceRoll()
        }
        .onChange(of: viewModel.eventBatch) { _, batch in
            handleEvents(batch.events)
        }
        .onChange(of: isRobberTargetingActive) { _, isActive in
            if !isActive { robberTargetTile = nil }
        }
    }

    /// Brief scale + rotation pulse so a dice roll reads as an event rather
    /// than the chip's text just changing - a quick overshoot-and-settle
    /// spring rather than anything more elaborate (e.g. cycling through
    /// intermediate die faces), per the "tasteful and brief beats elaborate
    /// and janky" guidance for this pass.
    private func animateDiceRoll() {
        diceScale = 0.6
        diceRotation = -12
        withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) {
            diceScale = 1.3
            diceRotation = 10
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.65).delay(0.16)) {
            diceScale = 1.0
            diceRotation = 0
        }
    }

    /// The board itself plus its overlaid chips (dice roll top-left,
    /// bank/deck counts + `pauseButton` top-right) - pulled out of `body`
    /// into its own property since `body`'s single expression got large
    /// enough to push the SwiftUI type-checker over its time limit;
    /// splitting large ViewBuilder bodies into named subexpressions like
    /// this is the standard fix.
    /// Height the top chips occupy, reported by the chips themselves.
    ///
    /// Seeded at the last hand-tuned value so the very first frame - drawn
    /// before any preference has been reported - is not visibly wrong.
    @State private var topChipInset: CGFloat = 38

    /// The chip band's own height, reported by the chip.
    ///
    /// Measured on `deckCountChip` alone, not on the whole top-trailing stack:
    /// the pause button beneath it sits in the board's top-right corner, where
    /// a hex grid has no tiles, so reserving its height would cost the board
    /// space for a collision that cannot happen. Measuring the stack did
    /// exactly that and pushed the board most of the way off screen.
    private var chipHeightReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: TopChipHeightKey.self, value: proxy.size.height)
        }
    }

    private var boardArea: some View {
        // Back to overlaying the board's top-left corner (not its own row)
        // - that reclaims the whole row's height for the board. It used to
        // sit in the bottom-left corner specifically, which is where it
        // kept colliding with the incoming trade card and other inline
        // banners below the board; the top-left corner is never where any
        // of that renders, so nothing to collide with up here even though
        // it's overlapping board content.
        ZStack(alignment: .topLeading) {
            BoardView(
                state: state,
                playerIdentity: viewModel.playerIdentity,
                onTapVertex: handleTapVertex,
                onTapEdge: handleTapEdge,
                onTapTile: handleTapTile,
                highlightedVertices: highlightedVertices,
                highlightedEdges: highlightedEdges,
                stagedRoads: roadBuildingFirstEdge.map { Set([$0]) } ?? [],
                stagedRoadOwner: roadBuildingFirstEdge == nil ? nil : human,
                isPlacementModeActive: isPlacementModeActive || isRobberTargetingActive,
                highlightedTiles: highlightedTilesForRobber,
                isTileTargetingActive: isRobberTargetingActive,
                allowsGameCommands: !isDiscardPresented,
                rollHighlightTiles: rollHighlightTiles
            )
            // Clears the dice and bank/deck chips that float over this area.
            //
            // MEASURED, not guessed. This was a constant that grew 18 -> 30 ->
            // 50 -> 38 as port badges kept surfacing under the bank chip, and
            // every one of those revisions was someone eyeballing a screenshot
            // - which is why it kept coming back. The chips are `.overlay`s on
            // this whole area, so they float above the board wherever it is;
            // the only number that is correct by construction is the height
            // they actually occupy, so the board asks them.
            //
            // It self-corrects for the cases a constant never could: a larger
            // Dynamic Type setting, a fourth digit in the bank counts, or
            // anything else that makes the chip taller.
            .padding(.top, topChipInset)

            if let roll = state.lastDiceRoll {
                diceChip(roll)
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Top-right corner, the same `.padding(8)` as the dice chip so the
        // two sit flush on one shared top line - the bank's per-resource
        // remaining counts and the dev-card deck's remaining count, the
        // same two piles a physical Catan board keeps face-down next to the
        // board itself. `pauseButton` stacks directly beneath, in the same
        // corner rather than top-left (out of the way of `BotHUDRow`'s
        // chips).
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 6) {
                deckCountChip
                    .background(chipHeightReader)
                pauseButton
            }
            .padding(8)
        }
        .onPreferenceChange(TopChipHeightKey.self) { measured in
            // The chip's own height, plus the 8pt inset it is padded by and an
            // 8pt breathing gap below it.
            topChipInset = measured + 16
        }
    }

    // MARK: - Bottom panel: one uniform action row (or the inline
    // robber-targeting panel while a robber move is pending) over a
    // lighter water panel

    private var bottomPanel: some View {
        // `actionRow`, every `robberTargetingPanel` state, and
        // `IncomingTradeCardView` all share the same plain static height
        // floor (`actionRowHeight`, applied at each one's own call
        // site/root, not here) - not a measured/reserved slot. Two earlier
        // attempts at a *dynamically measured* shared height here (see git
        // history) both backfired: reserving one height across all three
        // let whichever state was rare-but-tall permanently inflate it (a
        // `StableHeightSlot` only ever grows), and even narrowing that down
        // still left a visible dead gap under the ordinary action row -
        // both read as regressions, worse than the small resize during a
        // robber move/incoming offer they were meant to fix (see chat). A
        // plain hardcoded constant, sized to the tallest of the real
        // measured heights and used nowhere else, doesn't have either
        // failure mode - there's nothing left to over-measure or grow
        // unexpectedly.
        VStack(spacing: 8) {
            if isDiscardPresented {
                Color.clear.frame(height: Self.actionRowHeight)
            } else if isRobberTargetingActive {
                robberTargetingPanel
            } else if isRoadBuildingActive {
                roadBuildingPanel
            } else if let currentOffer = currentIncomingOffer {
                // Takes over this row for as long as the offer stays live
                // (its own up-to-6s countdown, or until accepted/rejected) -
                // including into the human's *own* turn if the proposing
                // bot's turn ended before it resolved, since that's the
                // only UI that can ever resolve a pending incoming offer
                // (`TradePopupView` only ever proposes new trades, it
                // doesn't surface existing `pendingTradeOffers`). Briefly
                // gating Build/Trade/Roll-or-End behind resolving this first
                // is an acceptable trade for that - it self-clears within
                // the same window the fairness delay in
                // `GameViewModel.waitForFairAcceptWindow` is built around.
                IncomingTradeCardView(
                    offer: currentOffer,
                    // Same signal the bot loop already holds on.
                    isHeld: isShowingInGameSettings,
                    playerIdentity: viewModel.playerIdentity,
                    onAccept: { respond(to: currentOffer, accept: true) },
                    onReject: { respond(to: currentOffer, accept: false) }
                )
            } else {
                actionRow
                    .frame(height: Self.actionRowHeight)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(CatanTheme.panelBackground)
        )
    }

    /// Build / Trade / turn action (Roll Dice or End Turn) - dev cards are
    /// played by tapping their tile in `HumanPlayerPanel` now, so this row
    /// only needs three slots. Build opens `BuildPopupView` (matching
    /// Trade's popup-card look) unless a placement mode is already armed, in
    /// which case tapping the button just cancels it directly.
    private var actionRow: some View {
        HStack(spacing: 10) {
            UniformActionButton(
                title: "Trade", systemImage: "arrow.left.arrow.right",
                isEnabled: isHumanMainTurn,
                backgroundImageName: "button-fill-trade"
            ) {
                showTradePopup = true
            }
            UniformActionButton(
                title: placementMode == nil ? "Build" : placementMode!.label,
                systemImage: placementMode == nil ? "hammer.fill" : "hammer.circle.fill",
                // `|| placementMode != nil` deliberately, not just
                // `isHumanMainTurn`: while a placement is armed this button is
                // the only way to cancel it, so disabling it mid-placement
                // would strand the player in targeting mode. In practice a
                // placement can only be armed during the human's main turn
                // anyway, so this is belt-and-braces rather than a real second
                // condition.
                isEnabled: isHumanMainTurn || placementMode != nil,
                isArmed: placementMode != nil,
                backgroundImageName: "button-fill-build"
            ) {
                if placementMode != nil {
                    placementMode = nil
                } else {
                    showBuildPopup = true
                }
            }
            turnActionButton
        }
    }

    /// Replaces the action row while a robber move is active. The extracted
    /// panel owns its exact height so the flexible board never resizes between
    /// destination selection and victim selection.
    private var robberTargetingPanel: some View {
        GameRobberTargetingPanel(
            targetSelected: robberTargetTile != nil,
            victims: robberVictims,
            identity: viewModel.playerIdentity,
            resourceCount: resourceCount,
            isKnight: isKnightRobberActive,
            errorMessage: errorMessage,
            onChooseVictim: chooseRobberVictim,
            onRepick: { robberTargetTile = nil },
            onCancel: cancelKnightFlow
        )
    }

    private var roadBuildingPanel: some View {
        GameRoadBuildingPanel(
            hasFirstRoad: roadBuildingFirstEdge != nil,
            onUndo: { roadBuildingFirstEdge = nil },
            onCancel: {
                roadBuildingFirstEdge = nil
                isRoadBuildingActive = false
            }
        )
    }

    private func resourceCount(for player: PlayerID) -> Int {
        state.players.first { $0.id == player }?.resources.values.reduce(0, +) ?? 0
    }

    private func chooseRobberVictim(_ victim: PlayerID) {
        guard let robberTargetTile else { return }
        performRobberMove(tile: robberTargetTile, victim: victim)
    }

    /// The common measured height for normal, trade, card, and robber rows.
    private static let actionRowHeight: CGFloat = BottomRowMetrics.height

    /// True exactly when the game is waiting for the human to take a main-turn
    /// action - the only phase in which building, trading or buying a
    /// development card is legal.
    ///
    /// Asked through `GamePhase.isMainTurn(of:)` rather than unpacking the
    /// phase here, because this question had six hand-written copies in this
    /// file and they did not agree: **the Build button had no copy at all.**
    /// It was hardcoded `isEnabled: true`, so it stayed lit through the setup
    /// phase, where the only legal moves are placing a settlement and a road.
    /// Tapping it there opened a popup with every row disabled, on top of the
    /// board the player was being asked to tap.
    ///
    /// Named for what it *is* rather than for one of its callers - it was
    /// `isTradeAvailable`, which is why nobody thought to give Build one.
    private var isHumanMainTurn: Bool {
        state.phase.isMainTurn(of: human.index)
    }

    @ViewBuilder
    private var turnActionButton: some View {
        switch state.phase {
        case .rollDice(let playerIndex) where playerIndex == human.index:
            UniformActionButton(title: "Roll Dice", systemImage: "die.face.5.fill", isEnabled: true, isArmed: true, backgroundImageName: "button-fill-turn") {
                perform(.rollDice)
            }
            .overlay(
                // Traces the same notched shape the button's own border
                // does (`FrameCornerRect`, not a plain `RoundedRectangle`) -
                // otherwise this pulse ring sits just outside the button's
                // actual notched outline as a mismatched plain rounded
                // rectangle instead of following it.
                FrameCornerRect(cornerRadius: 10)
                    .strokeBorder(Color.yellow, lineWidth: rollDicePulse ? 3 : 1)
                    .opacity(rollDicePulse ? 1 : 0.35)
            )
            .onAppear {
                rollDicePulse = false
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    rollDicePulse = true
                }
            }
            .onDisappear {
                rollDicePulse = false
            }
        case .mainTurn(let playerIndex) where playerIndex == human.index:
            UniformActionButton(title: "End Turn", systemImage: "arrow.uturn.right.circle.fill", isEnabled: true, backgroundImageName: "button-fill-turn") {
                perform(.endTurn)
            }
        default:
            UniformActionButton(title: "Turn", systemImage: "hourglass", isEnabled: false, backgroundImageName: "button-fill-turn") {}
        }
    }
}

private extension GameView {
    private var isDiscardPresented: Bool {
        viewModel.currentDiscardObligation != nil
    }

    private var isBlockingOverlayPresented: Bool {
        showBuildPopup || showTradePopup || showDevCardHand
            || (isDiscardPresented && !viewModel.isDiscardEditorMinimized)
            || isShowingInGameSettings || viewModel.pendingDevCardReveal?.owner == human
            || viewModel.pendingDevCardResolution?.owner == human || viewModel.needsHandoff
    }

    /// Surfaces that can remain open while a bot otherwise has work.
    private var isBotBlockingSurfaceOpen: Bool {
        isShowingInGameSettings || showDevCardHand
    }

    private func handleDevCardPlay(_ type: DevCardType) {
        switch type {
        case .knight:
            robberTargetTile = nil
            isKnightRobberActive = true
        case .roadBuilding:
            roadBuildingFirstEdge = nil
            isRoadBuildingActive = true
            placementMode = nil
        case .yearOfPlenty, .monopoly, .victoryPoint:
            break
        }
        showDevCardHand = false
        devCardPopupType = nil
    }

    /// Inline card effects keep the detail open on failure. The old helper
    /// swallowed the error and closed the popup unconditionally, forcing the
    /// player to rebuild their selection without knowing whether anything
    /// committed.
    private func commitDevCard(_ move: GameMove) -> String? {
        do {
            try viewModel.apply(move)
            errorMessage = nil
            showDevCardHand = false
            devCardPopupType = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Inline robber-move flow (mandatory post-7-roll case and the
    // voluntary knight-card case share this same on-board flow)

    /// True exactly while the human owes a mandatory robber move -
    /// `state.phase == .movingRobber(human.index)`. Drives `BoardView` into
    /// tile-targeting mode and swaps `bottomPanel`'s action row for
    /// `robberTargetingPanel`.
    private var isMandatoryRobberActive: Bool {
        if case .movingRobber(let playerIndex) = state.phase { return playerIndex == human.index }
        return false
    }

    /// True while the human has confirmed playing a Knight card from
    /// `DevCardPopupView` and is picking where to move the robber.
    private var isRobberTargetingActive: Bool {
        isMandatoryRobberActive || isKnightRobberActive
    }

    /// Every tile except the robber's current one - the only illegal target
    /// per `Robber.apply`/`RulesEngine.legalMoves`.
    private var highlightedTilesForRobber: Set<HexCoordinate> {
        guard isRobberTargetingActive else { return [] }
        return Set(state.board.tiles.map(\.coordinate)).subtracting([state.board.robberTile])
    }

    private var robberVictims: [PlayerID] {
        guard let robberTargetTile else { return [] }
        return Robber.eligibleVictims(for: robberTargetTile, thief: human, in: state)
    }

    private func handleTapTile(_ tile: HexCoordinate) {
        guard isRobberTargetingActive, tile != state.board.robberTile else { return }
        let victims = Robber.eligibleVictims(for: tile, thief: human, in: state)
        if victims.isEmpty {
            performRobberMove(tile: tile, victim: nil)
        } else {
            robberTargetTile = tile
        }
    }

    private func performRobberMove(tile: HexCoordinate, victim: PlayerID?) {
        let move: GameMove = isKnightRobberActive
            ? .playKnight(moveRobberTo: tile, stealFrom: victim)
            : .moveRobber(tile, stealFrom: victim)
        do {
            try viewModel.apply(move)
            errorMessage = nil
            robberTargetTile = nil
            isKnightRobberActive = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelKnightFlow() {
        robberTargetTile = nil
        isKnightRobberActive = false
        errorMessage = nil
    }

    // MARK: - Board tap routing

    private func handleTapVertex(_ vertex: VertexID) {
        switch state.phase {
        case .setupForward, .setupBackward:
            perform(.placeInitialSettlement(vertex))
        case .mainTurn:
            switch placementMode {
            case .settlement:
                perform(.buildSettlement(vertex))
                placementMode = nil
            case .city:
                perform(.buildCity(vertex))
                placementMode = nil
            case .road, nil:
                break
            }
        default:
            break
        }
    }

    private func handleTapEdge(_ edge: EdgeID) {
        switch state.phase {
        case .setupForward, .setupBackward:
            perform(.placeInitialRoad(edge))
        case .rollDice(let playerIndex) where playerIndex == human.index:
            if isRoadBuildingActive { handleRoadBuildingTap(edge) }
        case .mainTurn:
            if isRoadBuildingActive {
                handleRoadBuildingTap(edge)
            } else if placementMode == .road {
                perform(.buildRoad(edge))
                placementMode = nil
            }
        default:
            break
        }
    }

    private func handleRoadBuildingTap(_ edge: EdgeID) {
        guard let first = roadBuildingFirstEdge else {
            roadBuildingFirstEdge = edge
            return
        }
        do {
            try viewModel.apply(.playRoadBuilding(first, edge))
            errorMessage = nil
            roadBuildingFirstEdge = nil
            isRoadBuildingActive = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Highlighting

    /// True during setup exactly when it's the *human's* turn to place -
    /// `legalMoves` reflects whichever player is actually active, so
    /// without this check the board would highlight legal spots for a
    /// bot's own setup placement too, which the human can't act on anyway.
    private var isHumanSetupTurn: Bool {
        switch state.phase {
        case .setupForward(let index), .setupBackward(let index):
            return index == human.index
        default:
            return false
        }
    }

    private var isPlacementModeActive: Bool {
        switch state.phase {
        case .setupForward, .setupBackward:
            // Stays "active" (gating taps to only the highlighted set) even
            // during a bot's own setup turn, when that set is empty (see
            // `isHumanSetupTurn`) - so every vertex/edge is simply
            // untappable then, rather than ungating everything.
            return true
        case .mainTurn:
            return placementMode != nil || isRoadBuildingActive
        case .rollDice(let playerIndex):
            return playerIndex == human.index && isRoadBuildingActive
        default:
            return false
        }
    }

    private var highlightedVertices: Set<VertexID> {
        switch state.phase {
        case .setupForward, .setupBackward:
            guard isHumanSetupTurn else { return [] }
            return Set(legalMoves.compactMap { if case .placeInitialSettlement(let v) = $0 { v } else { nil } })
        case .mainTurn:
            // The setup arms above guard on whose turn it is; these did not.
            // `legalMoves` is the UNSCOPED overload, which returns the ACTING
            // player's moves whoever asks (see `RulesEngine.legalMoves`'s doc),
            // so with a placement mode still armed as the turn passed to a bot,
            // the board lit up that BOT's legal settlement spots as if they
            // were the human's.
            guard isHumanMainTurn else { return [] }
            switch placementMode {
            case .settlement:
                return Set(legalMoves.compactMap { if case .buildSettlement(let v) = $0 { v } else { nil } })
            case .city:
                return Set(legalMoves.compactMap { if case .buildCity(let v) = $0 { v } else { nil } })
            default:
                return []
            }
        default:
            return []
        }
    }

    private var highlightedEdges: Set<EdgeID> {
        switch state.phase {
        case .setupForward, .setupBackward:
            guard isHumanSetupTurn else { return [] }
            return Set(legalMoves.compactMap { if case .placeInitialRoad(let e) = $0 { e } else { nil } })
        case .mainTurn:
            // Same missing guard as `highlightedVertices` - see the note there.
            guard isHumanMainTurn else { return [] }
            if isRoadBuildingActive {
                return highlightedRoadBuildingEdges
            }
            if placementMode == .road {
                return Set(legalMoves.compactMap { if case .buildRoad(let e) = $0 { e } else { nil } })
            }
            return []
        case .rollDice(let playerIndex):
            guard playerIndex == human.index, isRoadBuildingActive else { return [] }
            return highlightedRoadBuildingEdges
        default:
            return []
        }
    }

    private var highlightedRoadBuildingEdges: Set<EdgeID> {
        if let first = roadBuildingFirstEdge {
            return Set(legalMoves.compactMap {
                if case .playRoadBuilding(let candidate, let second) = $0,
                   candidate == first { return second }
                return nil
            })
        }
        return Set(legalMoves.compactMap {
            if case .playRoadBuilding(let first, _) = $0 { return first }
            return nil
        })
    }

    private var legalMoves: [GameMove] { RulesEngine.legalMoves(for: state) }

    private func perform(_ move: GameMove) {
        do {
            try viewModel.apply(move)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Incoming trade offers

    /// Grows `incomingOfferQueue` with any bot-proposed offer not already
    /// seen - `IncomingTradeCardView` shows `incomingOfferQueue.first`, so
    /// multiple simultaneous offers queue and show one at a time. Offers
    /// that disappear from `state.pendingTradeOffers` (accepted/rejected/
    /// withdrawn elsewhere) are dropped from the queue too.
    private func handleTradeOffersChange() {
        let liveIDs = Set(state.pendingTradeOffers.map(\.id))
        incomingOfferQueue.removeAll { !liveIDs.contains($0.id) }

        // Offer IDs are content-derived (`TradeOffer.enumerated` hashes
        // proposer + sorted give/want, per the determinism contract in
        // `RulesEngine.legalMoves`), so a bot proposing the identical trade
        // shape twice in one session - same partner, same resources, which
        // a heuristic bot does often - reuses the exact UUID of an offer the
        // human already answered. Without this line `seenTradeOfferIDs` keeps
        // that ID forever, so the repeat offer fails `!seenTradeOfferIDs
        // .contains` and is silently never queued - yet `GameViewModel
        // .openIncomingOffer`, which has no such memory, still sees a live
        // pending offer and parks the bot loop on it forever: a real
        // deadlock with nothing on screen to explain it, reported as "the
        // game just stops advancing" (same signature as the relaunch bug
        // fixed in `.onAppear` above, different trigger). Intersecting with
        // `liveIDs` here mirrors what `incomingOfferQueue.removeAll` already
        // does two lines up: forget an ID the moment its offer is no longer
        // pending, so if that same content hashes to it again later, it
        // reads as unseen and gets shown.
        seenTradeOfferIDs.formIntersection(liveIDs)

        // Only ever surface an offer the human could actually accept right
        // now - one between two bots that doesn't involve resources the
        // human holds shouldn't interrupt them at all; bots still trade
        // freely amongst themselves either way, this only affects what
        // reaches this queue. This is just the ingestion-time gate, not the
        // whole story - see `currentIncomingOffer`, which re-checks
        // continuously, since either side's resources (not just the
        // human's) can change while an offer sits queued.
        for offer in state.pendingTradeOffers
        where offer.from != human && !seenTradeOfferIDs.contains(offer.id) && isOfferCurrentlyFulfillable(offer) {
            seenTradeOfferIDs.insert(offer.id)
            incomingOfferQueue.append(offer)
        }
    }

    /// The first queued offer that's still genuinely acceptable *right
    /// now* - a pure, non-mutating scan re-evaluated on every render (this
    /// view's `body` already re-renders on any relevant resource change,
    /// since it reads `state.players` throughout), so a stale offer
    /// disappears immediately rather than only the next time
    /// `handleTradeOffersChange` happens to run. Skips past (rather than
    /// removing) anything stale - `handleTradeOffersChange` is what
    /// actually prunes the underlying queue, on its own trigger.
    ///
    /// Regression fix: the queue used to only check affordability once, at
    /// the moment an offer first appeared - after that, neither the human
    /// spending the wanted cards on something else, nor the *proposing*
    /// bot spending what it offered (`offer.give`) before the human got to
    /// it, ever un-queued an offer that had gone stale. Tapping Accept on
    /// one then either silently failed via `Trading.respond`'s own
    /// affordability re-check, or (worse) looked like it accepted nothing.
    private var currentIncomingOffer: TradeOffer? {
        incomingOfferQueue.first { isOfferCurrentlyFulfillable($0) }
    }

    /// Whether `offer` could actually go through right now - the human
    /// currently holds `offer.want`, *and* the proposer still holds
    /// `offer.give` (mirrors `Trading.respond`'s own re-check, so a card
    /// shown to the human is always one `Trading.respond` will actually
    /// honor).
    /// Whether an offer is still honourable by both sides, per the engine.
    ///
    /// This used to re-derive the two affordability checks by hand. The engine
    /// enforces the same pair in `Trading.respond` and gates on them in
    /// `legalMoves`, so a local copy could only ever agree by luck - and the
    /// one other place a view re-derived a trade rule is where the reported
    /// bank-trade bug lived.
    private func isOfferCurrentlyFulfillable(_ offer: TradeOffer) -> Bool {
        Trading.bothSidesCanHonour(offer, responder: human, state: state)
    }

    private func respond(to offer: TradeOffer, accept: Bool) {
        do {
            try viewModel.apply(.respondToTrade(offerID: offer.id, accept: accept))
            errorMessage = nil
            incomingOfferQueue.removeAll { $0.id == offer.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Drops everything the previous player had half-done.
    ///
    /// Every piece of `@State` that belongs to the seat that armed it: an armed
    /// placement mode, an armed knight or road-building sub-flow, the first
    /// edge of a road-building pair, a robber target, an open popup, the set of
    /// trade offers this seat has already been shown.
    /// `ContentView`'s `.id(viewModel.gameGeneration)` resets them on restart
    /// only, so without this the incoming player inherits the outgoing player's
    /// half-finished move - and can complete it, as their own, on their own
    /// turn.
    ///
    /// `isKnightRobberActive` and `isRoadBuildingActive` are the two that are
    /// easiest to miss and the worst to leave: they are *armed targeting modes*,
    /// so an inherited one turns the next player's first tap on the board into
    /// a robber move or a road placement they did not ask for. Clearing the
    /// `roadBuildingFirstEdge` without clearing the flag that made it
    /// meaningful is half a fix.
    private func clearSeatInteractionState() {
        placementMode = nil
        roadBuildingFirstEdge = nil
        isRoadBuildingActive = false
        robberTargetTile = nil
        isKnightRobberActive = false
        showTradePopup = false
        showBuildPopup = false
        showDevCardHand = false
        devCardPopupType = nil
        incomingOfferQueue = []
        // This has the same class of bug as `.onAppear` did (see its fix
        // above and `GameplayBoundaryFlowTests.
        // testIncomingOfferSurvivesAppRelaunch`) - blindly marking every
        // currently-pending offer as seen can permanently swallow one the
        // incoming seat was never actually shown. Left as-is here rather
        // than applying the same fix blind: this runs *before*
        // `claimDeviceForSeatOwedATurn()` updates `seatAtDevice`, so `human`
        // (and therefore `isOfferCurrentlyFulfillable`) would still resolve
        // to the *outgoing* seat if this called `handleTradeOffersChange()`
        // directly - re-deriving the queue against the wrong player's
        // resources. Only single-human play (Jake's own setup) was
        // reproduced and verified; the hot-seat handoff path needs its own
        // repro and fix, not a copy-paste of this one.
        seenTradeOfferIDs = Set(state.pendingTradeOffers.map(\.id))
        errorMessage = nil
    }

    // MARK: - Roll tile highlight

    /// Highlights the producing tiles whenever a roll happens, whoever rolled.
    ///
    /// This used to watch `state.log` grow and look for the substring
    /// `" rolled "` - the exact sentence the engine happened to append - so
    /// rewording that sentence would have silently killed the highlight, and
    /// nothing would have failed to say so. Matching `.rolled` cannot break
    /// that way, and the roll total arrives in the event rather than being
    /// read back out of state.
    private func handleEvents(_ events: [GameEvent]) {
        for case .rolled(_, let total) in events {
            highlightProducingTiles(for: total)
        }
    }

    /// Briefly outlines every non-robbed producing tile matching `roll`.
    private func highlightProducingTiles(for roll: Int) {
        let producingTiles = state.board.tiles.filter { $0.numberToken == roll && $0.coordinate != state.board.robberTile }
        guard !producingTiles.isEmpty else { return }

        withAnimation(.easeIn(duration: 0.15)) {
            rollHighlightTiles = Set(producingTiles.map(\.coordinate))
        }
        Task {
            try? await Task.sleep(for: .seconds(PacingPreferences.rollHighlightSeconds))
            withAnimation(.easeOut(duration: 0.3)) {
                rollHighlightTiles = []
            }
        }
    }
}
#Preview {
    GameView(viewModel: GameViewModel(), onExitToMenu: {})
}
