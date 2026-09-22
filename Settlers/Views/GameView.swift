import SwiftUI
import CatanEngine
import CatanAI
/// The composed game screen: opponent HUD, board, private player panel, and
/// one Build/Trade/turn-action row over a continuous scenic background.
///
/// `TradePopupView`/`DevCardPopupView`/`DiscardPopupView` are overlays driven
/// by view state. Every spatial action uses the view model's shared board
/// decision: choose or drag a preview, reconsider it, then explicitly confirm
/// before canonical state changes. Incoming bot
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
                    .dynamicTypeSize(...DynamicTypeSize.large)

                boardArea

                belowBoard
            }
            // Spend the home-indicator band on the board. Negative padding
            // rather than `.ignoresSafeArea(edges: .bottom)`: this column must
            // reach a MEASURED distance past the safe area, not all the way to
            // the glass, and the amount is zero on a device whose inset is
            // zero. `boardArea` is the only flexible row here, so every point
            // this adds to the column's height lands on the board and nowhere
            // else. See `reclaimedBottomBand`.
            .padding(.bottom, -reclaimedBottomBand)
            // A full-screen card/popup visually blocks the board; it must do
            // the same for VoiceOver. Leaving the private shelf in the
            // accessibility tree produced two elements with identical card
            // identifiers and let an assistive-technology user activate the
            // hidden board beneath the modal.
            .allowsHitTesting(!isBlockingOverlayPresented)
            .accessibilityHidden(isBlockingOverlayPresented)

            if !isDiscardPresented, viewModel.boardDecisionPresentation == nil, showBuildPopup {
                BuildPopupView(viewModel: viewModel, onDismiss: { showBuildPopup = false })
                    .accessibilityHidden(viewModel.needsHandoff)
            }

            if !isDiscardPresented, viewModel.boardDecisionPresentation == nil, showTradePopup {
                TradePopupView(viewModel: viewModel, onDismiss: { showTradePopup = false })
                    .accessibilityHidden(viewModel.needsHandoff)
            }

            if interactionPriority.winner == .privateReceipt,
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
            } else if interactionPriority.winner == .privateReceipt,
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
            } else if !isDiscardPresented,
                      viewModel.boardDecisionPresentation == nil,
                      showDevCardHand {
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
            if isDiscardPresented && !interactionPriority.isSettingsCoverPresented {
                DiscardPopupView(viewModel: viewModel)
                    .accessibilityHidden(viewModel.needsHandoff)
            }

            if interactionPriority.isSettingsCoverPresented {
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
                        viewModel.clearBoardDecisionForBoundary()
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
                    // Rebuild the queue only after ownership changes. Doing it
                    // before this point evaluates affordability against the
                    // outgoing hand and can permanently hide the incoming
                    // player's first offer.
                    handleTradeOffersChange()
                }
                .zIndex(100)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Screen.game)
        // Measured from a reader that still SITS in the safe area, because
        // that is the only kind that reports one: a reader inside the
        // background layer, which ignores the safe area, was handed the whole
        // screen and dutifully reported an inset of zero (measured).
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: BottomSafeInsetKey.self,
                                       value: proxy.safeAreaInsets.bottom)
            }
        }
        // BELOW the background that emits it, and not above: preferences
        // travel outwards through the modifier chain, so a reader attached
        // after this line is invisible to it. Written the other way round
        // first, and the whole screen simply did not move.
        .onPreferenceChange(BottomSafeInsetKey.self) { bottomSafeInset = $0 }
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
            viewModel.reconcileBoardDecision()
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
        }
        .task {
            #if DEBUG
            if QALaunchFlag.showPaidRoadDecision.isSet {
                viewModel.qaPreparePaidBuildPosition(starting: .buildRoad)
            } else if QALaunchFlag.showPaidSettlementDecision.isSet {
                viewModel.qaPreparePaidBuildPosition(starting: .buildSettlement)
            } else if QALaunchFlag.showPaidCityDecision.isSet {
                viewModel.qaPreparePaidBuildPosition(starting: .buildCity)
            } else if QALaunchFlag.paidBuildPosition.isSet {
                viewModel.qaPreparePaidBuildPosition()
            } else if QALaunchFlag.showRoadBuildingDecision.isSet {
                viewModel.qaPrepareRoadBuildingDecision()
            } else if QALaunchFlag.showMandatoryRobberDecision.isSet {
                viewModel.qaPrepareMandatoryRobberDecision()
            } else if QALaunchFlag.showDiscard.isSet {
                viewModel.qaPrepareMandatoryDiscard()
            } else if let card = QALaunchOption.devCardPurchase {
                viewModel.qaPrepareDevCardPurchase(card)
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
            #if DEBUG
            if QALaunchFlag.showRobberTargeting.isSet {
                viewModel.qaPrepareKnightBoardDecision(selectDestinationWithVictim: false)
            } else if QALaunchFlag.showRobberVictimPicker.isSet {
                viewModel.qaPrepareMandatoryRobberDecision(selectDestination: true)
            }
            #endif
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
    /// Seeded *deliberately high* rather than at the last hand-tuned value.
    /// The seed exists only for the one frame drawn before the chips have
    /// reported: too large draws that frame's board a little small and then
    /// corrects, while too small draws it up underneath the bank chip. Over-
    /// reserving self-corrects; under-reserving is a visible collision.
    @State private var topChipInset: CGFloat = 64

    /// The home-indicator band, reported by the background layer.
    @State private var bottomSafeInset: CGFloat = 0

    /// How much of the bottom safe area this screen draws into.
    ///
    /// ## Why take it at all
    /// It was the only unspent space on the screen. Measured on an iPhone 17
    /// Pro at Dynamic Type `.large`: 59pt of safe top, 94 of `BotHUDRow`, 63
    /// of chip band, **362 of board**, 257 of `belowBoardReserve` - and then
    /// 34.67 points of nothing, because the column stopped at the safe area
    /// while the painting behind it ran to the glass. `boardArea` is the only
    /// row here that flexes, so that band was the board's to have.
    ///
    /// ## Why it makes the board *fill* its frame rather than merely grow
    /// The board is solved to fit everything it draws - port badges included -
    /// inside its frame, so the frame's aspect ratio decides which axis binds.
    /// Everything drawn is 1.035 wide for every 1 tall; the old 402x362 frame
    /// was 1.111, so height bound the fit and the difference sat as water down
    /// the two sides - 27.8pt of it, over and above the 6pt margin the fit
    /// keeps on every side. Height was therefore the *only* dimension that
    /// could help: at 402x382.67 the frame is 1.051, the board comes out 5.9%
    /// larger, and that 27.8 falls to 7.7 - under 4pt a side. Zooming instead
    /// would have cost the outer port badges; `BoardFitTests` says so.
    ///
    /// ## Why a clearance rather than the whole band
    /// The action row is a row of buttons, and the home indicator is drawn
    /// over the bottom ~13 points of the screen. `homeIndicatorClearance`
    /// keeps the buttons above it; the rest is board. The remaining 7.7pt of
    /// side water is deliberately *not* pursued: spending it needs another
    /// 6pt of frame height, which is the buttons' clearance, and that is a
    /// worse trade than four points of sea.
    ///
    /// Nothing here varies with the phase, so the board's frame is still the
    /// same rectangle in every one of them - `BoardViewportInvarianceTests`
    /// is unaffected and still passes on its own terms.
    private var reclaimedBottomBand: CGFloat {
        max(0, bottomSafeInset - Self.homeIndicatorClearance)
    }

    /// Left clear below the action row for the home indicator, which is drawn
    /// about 5 points tall, 8 above the bottom of the screen.
    static let homeIndicatorClearance: CGFloat = 14

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
                decision: viewModel.boardDecisionPresentation,
                onSelectTarget: { _ = viewModel.selectBoardTarget($0) },
                allowsGameCommands: !isDiscardPresented && !isBlockingOverlayPresented,
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
        .frame(maxWidth: .infinity, minHeight: 250, maxHeight: .infinity)
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

    // MARK: - Below the board: a fixed reserve, never a flexible remainder

    /// Everything under the board, in a frame whose height does NOT depend on
    /// what is currently in it.
    ///
    /// ## The bug this shape exists to kill, and why the obvious shapes do not
    /// These panels used to sit directly in the outer `VStack` as ordinary
    /// flexible rows, with `boardArea` taking `maxHeight: .infinity`. That
    /// makes the board's height *the remainder*, so every panel that appears
    /// or disappears silently re-solves the board's fit. Measured on an
    /// iPhone 17 Pro at width 402, the board's own container came out at:
    ///
    /// | state | container height |
    /// |---|---|
    /// | main turn with an incoming trade card | 362.67 |
    /// | setup / roll / robber decision | 382.67 |
    /// | discarding (this whole stack is replaced by the sheet) | 503.67 |
    ///
    /// A 141-point, 39% spread on one device in one game. The board visibly
    /// re-zoomed and re-centered on a 7, on an incoming offer, and on a
    /// discard.
    ///
    /// `BoardView` used to paper over that by locking its fit to the TALLEST
    /// container it had been given. That is strictly worse than it sounds and
    /// is why the bug came back: it made the board's size depend on the
    /// *history* of the session rather than on the frame. A game that rolled a
    /// seven locked to 503.67 and kept a board 39% too big for every later
    /// screen - drawn correctly but hanging ~70pt below its container, which
    /// is what clipped the bottom port badges - while a game that never rolled
    /// one locked to 382.67. Two games, two different board sizes, and a
    /// visible jump the moment the first seven landed.
    ///
    /// **No rule that observes the container can fix this.** Tallest-seen is
    /// history-dependent; shortest-seen shrinks the board mid-game the first
    /// time a tall panel appears; first-seen locks to the untrustworthy first
    /// frame. The height has to stop varying, which is what this frame does.
    ///
    /// ## The rule
    /// This region is `belowBoardReserve` points tall in every phase. Panels
    /// inside it may still come and go freely - that is now invisible to the
    /// board, because none of it is the board's remainder any more. Anything
    /// that wants more room than the reserve must compress or scroll inside
    /// it; it may not take height from the board.
    ///
    /// `BoardFitInvarianceTests` is what holds this: it fails if the reserve
    /// stops covering a real state, and `BoardStabilityTests` fails if the
    /// board's solved fit differs between any two phases.
    private var belowBoard: some View {
        VStack(spacing: 0) {
            // The road-building hint and a build/move error share one
            // fixed-height slot - the incoming-trade card
            // used to live here too, but a bot can only ever propose one
            // while it's *not* the human's turn (see `bottomPanel`'s own
            // comment), the same window where the action row below has
            // nothing real to do anyway - so it now takes over that row
            // directly instead of adding a whole extra reserved banner
            // just for itself.
            // A board decision reports its own errors and instructions in
            // the command dock, so it never fills this banner - but the slot
            // is still RESERVED while one is up. See below.
            //
            // A FIXED height, not a measured, grow-only slot. Such a slot
            // only ever grows, so the first error message of the session
            // silently made this band taller for the rest of it - one more
            // height that depended on the session's history rather than on
            // the frame, which is the exact family of bug this file is being
            // fixed for.
            // One `.caption2` line is all this band has ever needed; a longer
            // message shrinks to fit rather than reflowing and taking room
            // from its neighbours.
            //
            // The slot is reserved UNCONDITIONALLY, and only its *content* is
            // conditional. It used to be omitted outright during a board
            // decision, on the reasoning that the dock could have the room -
            // and that omission was plainly visible: the player nameplate and
            // the command dock under it jumped 20 points up the screen the
            // moment a settlement placement, a knight, or a rolled seven
            // began, then dropped back when it ended. The board itself never
            // moved (`belowBoardReserve` is fixed either way), but this is the
            // same bug one level in - a row whose height depends on the phase
            // moves every row after it - and the dock did not need the room:
            // `BoardDecisionDockView` is pinned to the same
            // `BottomRowMetrics.height` as the action row it replaces.
            //
            // Do not make this row conditional again. If some future state
            // genuinely needs more height than the reserve, take it from
            // inside the reserve, never by deleting a row other rows are
            // positioned against.
            Group {
                if let errorMessage, viewModel.boardDecisionPresentation == nil {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else {
                    Color.clear
                }
            }
            .frame(height: Self.infoBannerHeight)
            .dynamicTypeSize(...DynamicTypeSize.large)

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
                // This is a dense graphical inventory, not prose. Letting
                // Accessibility Large scale its symbols to 3x scale its
                // symbols pushed the board below its minimum and clipped VP
                // off-screen. VoiceOver still exposes every value; the fixed
                // canvas stays whole.
                .dynamicTypeSize(...DynamicTypeSize.large)
                .allowsHitTesting(viewModel.boardDecisionPresentation == nil)
                .accessibilityHidden(viewModel.boardDecisionPresentation != nil)
            }

            bottomPanel
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .allowsHitTesting(!isDiscardPresented)
                .accessibilityHidden(isDiscardPresented)
        }
        // Top-aligned, so a state with less in it leaves its slack at the
        // bottom rather than floating its panels into the middle of the gap.
        .frame(height: Self.belowBoardReserve, alignment: .top)
    }

    // MARK: - Bottom panel: one uniform command row over a lighter water panel

    private var bottomPanel: some View {
        // `actionRow`, every `BoardDecisionDockView` state, and
        // `IncomingTradeCardView` all share the same plain static height
        // floor (`actionRowHeight`, applied at each one's own call
        // site/root, not here) - not a measured/reserved slot. Two earlier
        // attempts at a *dynamically measured* shared height here (see git
        // history) both backfired: reserving one height across all three
        // let whichever state was rare-but-tall permanently inflate it (a
        // measured slot like that only ever grows), and even narrowing it down
        // still left a visible dead gap under the ordinary action row -
        // both read as regressions, worse than the small resize during a
        // robber move/incoming offer they were meant to fix (see chat). A
        // plain hardcoded constant, sized to the tallest of the real
        // measured heights and used nowhere else, doesn't have either
        // failure mode - there's nothing left to over-measure or grow
        // unexpectedly.
        VStack(spacing: 8) {
            switch interactionPriority.winner {
            case .handoff, .recoveryFailure, .mandatoryDiscard, .privateReceipt:
                Color.clear.frame(height: Self.actionRowHeight)
            case .mandatoryBoardDecision, .optionalBoardDecision:
                if let decision = viewModel.boardDecisionPresentation {
                    BoardDecisionDockView(
                        presentation: decision,
                        identity: viewModel.playerIdentity,
                        resourceCount: resourceCount,
                        onSelectVictim: { _ = viewModel.selectBoardTarget(.victim($0)) },
                        onUndo: { _ = viewModel.undoBoardDecisionSelection() },
                        onClear: viewModel.clearBoardDecisionSelection,
                        onCancel: { _ = viewModel.cancelBoardDecision() },
                        onConfirm: { _ = viewModel.confirmBoardDecision() }
                    )
                }
            case .incomingTrade:
                // Takes over this row for as long as the offer stays live
                // (its own up-to-6s countdown, or until accepted/rejected) -
                // including into the human's *own* turn if the proposing
                // bot's turn ended before it resolved, since that's the
                // only UI that can ever resolve a pending incoming offer
                // (`TradePopupView` only ever proposes new trades, it
                // doesn't surface existing `pendingTradeOffers`). Briefly
                // gating Build/Trade/Roll-or-End behind resolving this first
                // is an acceptable trade for that - it self-clears within
                // the offer's own countdown.
                if let currentOffer = currentIncomingOffer {
                    IncomingTradeCardView(
                        offer: currentOffer,
                        // Same signal the bot loop already holds on.
                        isHeld: interactionPriority.isSettingsCoverPresented,
                        playerIdentity: viewModel.playerIdentity,
                        onAccept: { respond(to: currentOffer, accept: true) },
                        onReject: { respond(to: currentOffer, accept: false) }
                    )
                    .dynamicTypeSize(...DynamicTypeSize.large)
                }
            case .ordinaryActions:
                actionRow
                    .frame(height: Self.actionRowHeight)
                    .dynamicTypeSize(...DynamicTypeSize.large)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(CatanTheme.panelBackground)
        )
        .background(commandRowFrameMarker)
    }

    /// An empty, Debug-only element whose only job is to give
    /// `BelowBoardInvarianceTests` this row's frame to measure - it is the row
    /// Jake saw jump 20 points when a placement or a seven started.
    ///
    /// It is a `.background` - a SIBLING of the row's content - rather than an
    /// identifier on the row itself, and that is the whole point. The obvious
    /// spelling, `.accessibilityElement(children: .contain)` plus an
    /// identifier on `bottomPanel`, makes this row an accessibility ANCESTOR
    /// of the board-decision dock, and that absorbed the dock's own container:
    /// `app.otherElements["board-decision.dock"]` stopped resolving and took
    /// ELEVEN board-decision UI tests down with it, every one reporting
    /// nothing but a bare `XCTAssertTrue failed`. A sibling leaf cannot do
    /// that. If you need to measure a container here, add another sibling.
    ///
    /// `#if DEBUG` because an element with no label is a VoiceOver stop that
    /// announces nothing. UI tests run Debug; players never get this.
    @ViewBuilder
    private var commandRowFrameMarker: some View {
        #if DEBUG
        Color.clear
            .accessibilityElement()
            .accessibilityIdentifier(AccessibilityID.Game.commandRow)
        #else
        Color.clear
        #endif
    }

    /// Build / Trade / turn action (Roll Dice or End Turn) - dev cards are
    /// played by tapping their tile in `HumanPlayerPanel` now, so this row
    /// only needs three slots. Build opens `BuildPopupView` (matching
    /// Trade's popup-card look). Choosing a piece there starts a board
    /// decision, whose own dock owns cancellation and confirmation.
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
                title: "Build",
                systemImage: "hammer.fill",
                isEnabled: isHumanMainTurn,
                backgroundImageName: "button-fill-build"
            ) {
                showBuildPopup = true
            }
            turnActionButton
        }
    }

    private func resourceCount(for player: PlayerID) -> Int {
        state.players.first { $0.id == player }?.resources.values.reduce(0, +) ?? 0
    }

    /// The common measured height for normal, trade, card, and robber rows.
    private static let actionRowHeight: CGFloat = BottomRowMetrics.height

    /// One `.caption2` line. See `belowBoard` for why this is a constant.
    private static let infoBannerHeight: CGFloat = 20

    /// The height reserved for everything under the board, in every phase.
    ///
    /// MEASURED, not chosen. Every component below caps its Dynamic Type at
    /// `.large`, so what it reports at `.large` is its worst case and a
    /// constant here is genuinely safe rather than merely convenient.
    /// Measured on an iPhone 17 Pro at width 402, Dynamic Type `.large`:
    ///
    ///     HumanPlayerPanel   141.00
    ///     info banner         20.00   (`infoBannerHeight`, now fixed)
    ///     gap above the dock   8.00   (`.padding(.top, 8)`)
    ///     bottomPanel         87.33   (identical in every winner state)
    ///                       -------
    ///                        256.33
    ///
    /// Rounded up to 257: every state must be <= this, never merely close to
    /// it, and a fractional constant buys nothing.
    ///
    /// `BoardViewportInvarianceTests` is the guard - it launches every phase
    /// fixture and fails if the board's own frame differs between any two of
    /// them, which is exactly what a too-small reserve would cause.
    static let belowBoardReserve: CGFloat = 257

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

    private var interactionPriority: GameInteractionPriorityResolution {
        let decision = viewModel.boardDecisionPresentation
        let hasPrivateReceipt = showDevCardHand
            || viewModel.pendingDevCardReveal?.owner == human
            || viewModel.pendingDevCardResolution?.owner == human
        return GameInteractionPriority.resolve(GameInteractionPriorityInput(
            needsHandoff: viewModel.needsHandoff,
            hasRecoveryFailure: viewModel.persistenceErrorMessage != nil,
            hasMandatoryDiscard: isDiscardPresented,
            hasMandatoryBoardDecision: decision?.canCancel == false,
            hasPrivateReceipt: hasPrivateReceipt,
            hasOptionalBoardDecision: decision?.canCancel == true,
            hasIncomingTrade: currentIncomingOffer != nil,
            isSettingsPresented: isShowingInGameSettings
        ))
    }

    private var isBlockingOverlayPresented: Bool {
        let winnerBlocksBoard = switch interactionPriority.winner {
        case .handoff, .recoveryFailure, .privateReceipt: true
        default: false
        }
        return showBuildPopup || showTradePopup || showDevCardHand
            || (isDiscardPresented && !viewModel.isDiscardEditorMinimized)
            || interactionPriority.isSettingsCoverPresented || winnerBlocksBoard
    }

    /// Surfaces that can remain open while a bot otherwise has work.
    private var isBotBlockingSurfaceOpen: Bool {
        interactionPriority.blocksBotProgress
    }

    private func handleDevCardPlay(_ type: DevCardType) {
        let intent: BoardDecisionIntent?
        switch type {
        case .knight:
            intent = .knight
        case .roadBuilding:
            intent = .roadBuilding
        case .yearOfPlenty, .monopoly, .victoryPoint:
            intent = nil
        }
        guard let intent, viewModel.beginBoardDecision(intent) else { return }
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

    /// Drops every ephemeral surface owned by the outgoing player. Spatial
    /// proposals are cleared through the coordinator, so adding another board
    /// action cannot create a new handoff leak here.
    private func clearSeatInteractionState() {
        viewModel.clearBoardDecisionForBoundary()
        showTradePopup = false
        showBuildPopup = false
        showDevCardHand = false
        devCardPopupType = nil
        incomingOfferQueue = []
        // The new owner has not seen any of these offers. The handoff callback
        // rebuilds the queue after `seatAtDevice` changes, against that hand.
        seenTradeOfferIDs = []
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
