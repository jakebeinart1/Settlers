import SwiftUI
import CatanEngine
import CatanAI

/// Which kind of build placement the human has armed via `BuildPopupView`.
/// While non-nil, `BoardView` is put into placement mode: only legal targets
/// for that move are tappable, everything else dims out.
public enum PlacementMode: Equatable {
    case road
    case settlement
    case city

    var label: String {
        switch self {
        case .road: return "Road"
        case .settlement: return "Settlement"
        case .city: return "City"
        }
    }
}

private struct SlotHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Reserves the tallest height its content has ever measured instead of
/// collapsing to zero when nothing's shown - inserting/removing a banner
/// row (the road-building hint, an incoming trade card, a build/move error)
/// changed the `VStack`'s total content height, and since the board is the
/// one flexible element absorbing that change (`.frame(maxHeight:
/// .infinity)`), every appearance/disappearance nudged the board's own
/// size - most noticeably every time a bot's trade offer showed up.
/// `content` should render `Color.clear.frame(height: 0)` for its "nothing
/// to show" case rather than being wrapped in an `if`, so this can measure
/// and reserve a stable height regardless of which state is current. The
/// `.frame(height: 0)` is required, not optional decoration: a bare
/// `Color.clear` has no intrinsic size and greedily fills all available
/// space in a `VStack`, which - before this slot has measured a real
/// height yet - competes with the board's own `.frame(maxHeight: .infinity)`
/// for the same flexible space and squeezes it down to a fraction of the
/// screen. (Shipped once without this, caught immediately after - see the
/// call sites below for the concrete fix.)
private struct StableHeightSlot<Content: View>: View {
    @Binding var height: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: SlotHeightKey.self, value: geo.size.height)
                }
            )
            .onPreferenceChange(SlotHeightKey.self) { measured in
                if measured > height { height = measured }
            }
            .frame(height: height > 0 ? height : nil, alignment: .top)
    }
}

/// The real, composed game screen, top to bottom: `BotHUDRow` (the 3 bot
/// chips only), `BoardView` filling the middle - with the dice chip (once
/// there's been a roll) overlaid on its top-left corner - `HumanPlayerPanel`
/// (the human's own spacious info
/// panel, now with a dev-card strip alongside the resources), then a single
/// uniform Build/Trade/turn-action row. Everything sits over one continuous
/// water-blue background rather than separate boxed panels - there's no
/// persistent log or toast feed anymore; the HUD (VP/tags/resource/dev-card
/// counts) already reflects every state change live.
///
/// `TradePopupView`/`DevCardPopupView`/`DiscardView` are popups/sheets driven
/// by view state; the mandatory post-7-roll robber move *and* the voluntary
/// knight-card robber move both happen inline on this same `BoardView` (see
/// `isRobberTargetingActive`) rather than as a separate modal. Incoming bot
/// trade offers surface as a small `IncomingTradeCardView` right above
/// `HumanPlayerPanel`, with a 6-second accept window.
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
    // `ContentView`) - lets QA screenshot the pause menu without a real tap.
    @State private var isShowingPauseMenu = QALaunchFlag.showPauseMenu.isSet
    @State private var placementMode: PlacementMode?
    // `-qaShowTradePopup`: same escape hatch pattern - lets QA screenshot
    // the trade popup without a real tap.
    @State private var showTradePopup = QALaunchFlag.showTradePopup.isSet
    // `-qaShowBuildPopup`: same escape hatch pattern - lets QA screenshot
    // the build popup without a real tap.
    @State private var showBuildPopup = QALaunchFlag.showBuildPopup.isSet
    // `-qaShowMonopolyPopup`: same escape hatch pattern - lets QA screenshot
    // the Monopoly resource-picker step of the dev-card popup (Year of
    // Plenty shares the same picker layout, just with a 2-pick limit
    // instead of 1, so one flag covers both visually).
    @State private var devCardPopupType: DevCardType? = QALaunchFlag.showMonopolyPopup.isSet ? .monopoly : nil
    @State private var errorMessage: String?

    // The same keys `MainMenuView` writes, so Restart plays the game the
    // player actually asked for rather than a fixed default.
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
    @State private var diceScale: CGFloat = 1.0
    @State private var diceRotation: Double = 0

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

    /// Tiles matching the most recent roll, briefly outlined on the board -
    /// and the last count of `state.log` already scanned for one, so a
    /// growth of exactly the lines added since then can be checked for a
    /// "rolled N" line without re-scanning the whole log every render.
    @State private var rollHighlightTiles: Set<HexCoordinate> = []
    @State private var lastSeenLogCount = 0

    /// The dice chip's own small history line - up to the 3 rolls before
    /// the current one, oldest last, shown in a faded caption so someone
    /// glancing at the screen mid-conversation can catch up on recent rolls
    /// without the drama of a live animation demanding their attention.
    @State private var rollHistory: [Int] = []

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

    private var state: GameState { viewModel.state }
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
                BotHUDRow(state: state, human: human)
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
                    if isRoadBuildingActive {
                        Text(roadBuildingFirstEdge == nil ? "Road Building: pick the first free road" : "Road Building: pick the second free road")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    } else if let errorMessage {
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
                HumanPlayerPanel(state: state, human: human, onTapDevCard: { devCardPopupType = $0 })
                    .padding(.horizontal, 12)

                bottomPanel
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            if showBuildPopup {
                BuildPopupView(viewModel: viewModel, placementMode: $placementMode, onDismiss: { showBuildPopup = false })
            }

            if showTradePopup {
                TradePopupView(viewModel: viewModel, onDismiss: { showTradePopup = false })
            }

            if let devCardPopupType {
                DevCardPopupView(
                    type: devCardPopupType,
                    onPlayBoardCard: handleDevCardPlay,
                    onPlayYearOfPlenty: { first, second in
                        performDevCard(.playYearOfPlenty(first, second))
                    },
                    onPlayMonopoly: { resource in
                        performDevCard(.playMonopoly(resource))
                    },
                    onCancel: { self.devCardPopupType = nil }
                )
            }

            if isDiscardPresented {
                DiscardPopupView(viewModel: viewModel)
            }

            if isShowingPauseMenu {
                // A themed `PopupCard` (the same card every other popup in
                // this app uses), not the native `confirmationDialog` this
                // replaced - a plain system action sheet was the one piece
                // of chrome in the whole game that didn't match the painted
                // gold-trim theme at all.
                PauseMenuView(
                    onResume: { isShowingPauseMenu = false },
                    onRestart: {
                        isShowingPauseMenu = false
                        // Reuse the player's own menu choices. These were
                        // hardcoded to `false`, so Restart silently handed back
                        // the fixed standard board with the human in seat 0 -
                        // discarding both toggles, which default to on.
                        viewModel.startNewGame(
                            randomizedBoard: randomizedBoardSetting,
                            randomizeSeat: randomizeSeatSetting
                        )
                    },
                    onMainMenu: {
                        isShowingPauseMenu = false
                        onExitToMenu()
                    }
                )
            }
        }
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
        .onAppear {
            seenTradeOfferIDs = Set(state.pendingTradeOffers.map(\.id))
            lastSeenLogCount = state.log.count
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
            await qaFastForwardToRollDiceIfRequested()
            // `-qaShowIncomingOffer`: same escape hatch pattern - seeds
            // `incomingOfferQueue` with a bogus but always-fulfillable offer
            // (empty give/want, so `isOfferCurrentlyFulfillable` is
            // vacuously true regardless of anyone's actual resources) so
            // `IncomingTradeCardView` can be screenshotted without a real
            // bot proposing one. Runs after
            // `qaFastForwardToRollDiceIfRequested`, not in `onAppear` - that
            // fast-forward's own moves fire `state.pendingTradeOffers`
            // changes, and `handleTradeOffersChange`'s
            // `onChange(of: state.pendingTradeOffers...)` handler purges any
            // queued offer that isn't backed by a real one, wiping this
            // fake one out again almost immediately if seeded any earlier.
            if QALaunchFlag.showIncomingOffer.isSet {
                incomingOfferQueue = [TradeOffer(from: PlayerID(index: 1), give: [:], want: [:])]
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
        .onChange(of: state.lastDiceRoll) { oldValue, newValue in
            guard newValue != nil else { return }
            if let oldValue {
                rollHistory = ([oldValue] + rollHistory).prefix(3).map { $0 }
            }
            animateDiceRoll()
        }
        .onChange(of: state.log.count) { _, newCount in
            handleLogGrowth(newCount: newCount)
        }
        .onChange(of: isRobberTargetingActive) { _, isActive in
            if !isActive { robberTargetTile = nil }
        }
    }

    /// `-qaFastForwardToRollDice`: same escape hatch pattern as
    /// `-qaAutoStart`/`-qaShowPauseMenu` - autoplays the human's own initial
    /// setup placements (using the same `Bot` logic real bot seats use),
    /// then rolls the dice too, so QA can screenshot the dice chip/`.rollDice`
    /// action row without two rounds of real board taps and a real tap on
    /// Roll Dice first. Capped at 20 moves (setup is always exactly 4 human
    /// moves - 2 settlements + 2 roads - plus the roll itself, so this is a
    /// generous safety margin, not a real budget) and silently gives up if
    /// something legal isn't found, rather than looping forever. Never fires
    /// without the literal launch argument, so this can't affect a real
    /// player.
    private func qaFastForwardToRollDiceIfRequested() async {
        guard QALaunchFlag.fastForwardToRollDice.isSet else { return }
        let bot = Bot(personality: .balanced)
        for _ in 0..<20 {
            switch viewModel.state.phase {
            case .rollDice(let playerIndex) where playerIndex == human.index:
                try? viewModel.apply(.rollDice)
                return
            // The `where` clause has to be repeated on BOTH patterns. Swift
            // applies it only to the pattern it directly follows, so the
            // previous single-clause spelling left `.setupForward` matching
            // *any* seat - including a bot's setup turn, which then ran
            // `bot.decide` for the human and applied a move the engine
            // rejected as out-of-turn. A `try?` swallowed the error, so the
            // hook looked like it worked while quietly doing nothing on those
            // iterations. The compiler warns about this; `-warnings-as-errors`
            // is what surfaced it.
            case .setupForward(let playerIndex) where playerIndex == human.index,
                 .setupBackward(let playerIndex) where playerIndex == human.index:
                // `viewModel.apply` always applies as the human seat, so
                // only the human's own setup turns can be driven this way -
                // any interleaved bot turns fall through to the
                // `runBotTurnIfNeeded()` below, same as a real game.
                let move = bot.decide(for: viewModel.state, player: human)
                try? viewModel.apply(move)
            default:
                break
            }
            await viewModel.runBotTurnIfNeeded()
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
                onTapVertex: handleTapVertex,
                onTapEdge: handleTapEdge,
                onTapTile: handleTapTile,
                highlightedVertices: highlightedVertices,
                highlightedEdges: highlightedEdges,
                isPlacementModeActive: isPlacementModeActive || isRobberTargetingActive,
                highlightedTiles: highlightedTilesForRobber,
                isTileTargetingActive: isRobberTargetingActive,
                rollHighlightTiles: rollHighlightTiles
            )
            // A hair of top clearance - the outermost hex row's own ports
            // (top-right in particular) sat close enough to the top edge to
            // graze the dice/deck chips overlaid up there. `BoardView`
            // re-fits and re-centers itself within whatever height it's
            // given, so this nudges the whole hex grid down slightly rather
            // than requiring the chips to shrink or move. Bumped again from
            // 18, then again from 30 to sit a bit lower in the space between
            // the HUD row and the human panel - purely spacing, doesn't
            // affect board scale/tap targets, which are still derived from
            // the same `geometry`.
            .padding(.top, 50)

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
                pauseButton
            }
            .padding(8)
        }
    }

    /// Stacked directly beneath `deckCountChip` in the board's top-trailing
    /// corner (see that overlay). Opens the Resume/Restart/Main Menu
    /// `confirmationDialog` - the actual pause is implicit: nothing in
    /// `GameViewModel` runs on a timer, so simply showing the dialog blocks
    /// further input until it's dismissed one way or another.
    private var pauseButton: some View {
        Button {
            isShowingPauseMenu = true
        } label: {
            Image("menu-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
        }
    }

    /// Bigger and plainer than before (no more flying resource badges to
    /// share attention with) - the current roll is the one thing this
    /// needs to say clearly, so it gets a large number front and center.
    /// `rollHistory` (up to the 3 rolls before this one) sits underneath in
    /// a small, faded line - enough to catch someone back up at a glance
    /// without competing with the current roll for attention.
    private func diceChip(_ roll: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                // A real die-face tile, not the old SF Symbol - that read as
                // a thin outline rather than an actual square against the
                // reference's bold ivory tile (see chat).
                DieFaceView(value: roll, size: 34)
                Text("\(roll)")
                    .font(.system(size: 32, weight: .heavy, design: .serif))
            }
            .foregroundStyle(.white)
            // Bumped from 10 - "7" (and other single digits) sat close
            // enough to the chip's own right edge/border to read as clipped,
            // especially once the digit's serif tail is included.
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(PaintedChromeBackground(textureImageName: "dice-fill", cornerRadius: 12, notchScale: 1.0))
            .scaleEffect(diceScale)
            .rotationEffect(.degrees(diceRotation))

            if !rollHistory.isEmpty {
                Text(rollHistory.map(String.init).joined(separator: "   "))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.leading, 14)
            }
        }
    }

    /// A physical six-sided die face - a rounded ivory square with black pip
    /// dots in the standard layout - used by `diceChip` in place of the old
    /// `Image(systemName: "die.face.N.fill")`, which read as a thin outline
    /// rather than an actual square at the size it was shown.
    private struct DieFaceView: View {
        let value: Int
        let size: CGFloat

        /// Fractional (x, y) pip centers within the tile, standard 6-face
        /// die layout, shared across every count via one 3x3 grid.
        private static let pipLayouts: [Int: [(CGFloat, CGFloat)]] = [
            1: [(0.5, 0.5)],
            2: [(0.25, 0.25), (0.75, 0.75)],
            3: [(0.25, 0.25), (0.5, 0.5), (0.75, 0.75)],
            4: [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)],
            5: [(0.25, 0.25), (0.75, 0.25), (0.5, 0.5), (0.25, 0.75), (0.75, 0.75)],
            6: [(0.25, 0.22), (0.75, 0.22), (0.25, 0.5), (0.75, 0.5), (0.25, 0.78), (0.75, 0.78)],
        ]

        var body: some View {
            let pips = Self.pipLayouts[min(max(value, 1), 6)] ?? []
            let pipSize = size * 0.16

            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(CatanTheme.onWaterText.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .strokeBorder(.black.opacity(0.55), lineWidth: max(1, size * 0.045))
                )
                .overlay(
                    ForEach(Array(pips.enumerated()), id: \.offset) { _, pip in
                        Circle()
                            .fill(.black.opacity(0.82))
                            .frame(width: pipSize, height: pipSize)
                            .position(x: pip.0 * size, y: pip.1 * size)
                    }
                )
                .frame(width: size, height: size)
        }
    }

    /// Top-right counterpart to `diceChip`: the bank's remaining count for
    /// each individual resource, plus the development-card deck's remaining
    /// count - both finite, shared piles in real Catan (19 of each resource,
    /// 25 development cards), so seeing them tick down explains things like
    /// "why can't I buy a dev card anymore" at a glance instead of a
    /// silently-disabled button. Broken out per-resource rather than one
    /// summed total, since "the bank is out of ore" and "the bank is out of
    /// brick" are different, useful pieces of information a single number
    /// would hide.
    private var deckCountChip: some View {
        HStack(spacing: 8) {
            ForEach(Resource.allCases, id: \.self) { resource in
                VStack(spacing: 1) {
                    // Rounded square, not a circle - matches the resource
                    // swatches in `MainMenuView`'s title block and
                    // `HumanPlayerPanel.resourceDot`, per Jake's ask to keep
                    // one consistent shape for "a resource" across the app.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(CatanTheme.color(for: resource))
                        .frame(width: 10, height: 10)
                    Text("\(state.bank[resource] ?? 0)")
                        .font(.system(size: 11, weight: .bold, design: .serif))
                }
            }

            Divider()
                .frame(height: 22)
                .overlay(Color.white.opacity(0.3))

            VStack(spacing: 1) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 10))
                Text("\(state.devCardDeck.count)")
                    .font(.system(size: 11, weight: .bold, design: .serif))
            }
        }
        .foregroundStyle(.white)
        // Widened from 10 - Jake wanted more breathing room on either side
        // of the resource-count digits than the tight original fit gave.
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(PaintedChromeBackground(textureImageName: "bank-fill", cornerRadius: 10, notchScale: 1.0))
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
            if isRobberTargetingActive {
                robberTargetingPanel
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
                isEnabled: isTradeAvailable,
                backgroundImageName: "button-fill-trade"
            ) {
                showTradePopup = true
            }
            UniformActionButton(
                title: placementMode == nil ? "Build" : placementMode!.label,
                systemImage: placementMode == nil ? "hammer.fill" : "hammer.circle.fill",
                isEnabled: true,
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

    /// Replaces `actionRow` while `isRobberTargetingActive`: instructs the
    /// human to tap a highlighted tile on the board above, then - once a
    /// tile with eligible victims is picked - an inline row of victim
    /// buttons (plus Cancel, to re-pick the tile) right here instead of a
    /// separate modal.
    ///
    /// `.frame(height: Self.actionRowHeight)` - an *exact* height, not
    /// `minHeight` - matters here: `UniformActionButton` fills whatever
    /// height it's given (see its own doc comment), so a `minHeight` on
    /// this container doesn't just pad short states up to the floor - it
    /// makes the whole row read as flexible to the outer `VStack` in
    /// `GameView.body`, which then splits its own leftover space between
    /// this row *and* `boardArea` (both now "wanting" more) instead of
    /// giving all of it to the board - the button row (and `actionRow`,
    /// same fix at its own call site) ballooned to take up most of the
    /// screen the first time this shipped (see chat). An exact height
    /// reports a fixed size upward, so `boardArea` stays the only flexible
    /// element, while `UniformActionButton` still fills that fixed height
    /// internally rather than leaving dead space in it.
    ///
    /// `actionRowHeight` itself is set to the tallest of the three
    /// robber-flow states this and `actionRow` (also fixed to it, at its
    /// own call site) can be in - the "Steal from:" label + victim-button
    /// row here, measured at 75.33pt, is the tallest; the "tap a tile"
    /// message (38pt) and `actionRow` itself (49.33pt, measured
    /// independently) are both shorter - see chat. Fixing all three to the
    /// same value means `bottomPanel`/`boardArea` never resize across a
    /// whole robber move (Knight card through the final steal), not just
    /// the first step of it.
    private var robberTargetingPanel: some View {
        VStack(spacing: 8) {
            if let robberTargetTile {
                Text("Steal from:")
                    .font(.subheadline.bold())
                    .foregroundStyle(CatanTheme.onWaterText)
                HStack(spacing: 10) {
                    ForEach(robberVictims, id: \.self) { victim in
                        UniformActionButton(
                            title: CatanTheme.playerLabel(for: victim),
                            systemImage: "person.fill.questionmark",
                            isEnabled: true
                        ) {
                            performRobberMove(tile: robberTargetTile, victim: victim)
                        }
                    }
                    UniformActionButton(title: "Cancel", systemImage: "xmark", isEnabled: true) {
                        self.robberTargetTile = nil
                    }
                }
            } else {
                Text("🏜️ Move the Robber — tap a highlighted tile above")
                    .font(.subheadline.bold())
                    .foregroundStyle(CatanTheme.onWaterText)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .frame(height: Self.actionRowHeight)
    }

    /// Shared floor for `actionRow` and every state of `robberTargetingPanel`
    /// - see `robberTargetingPanel`'s doc comment. The tallest of the three
    /// real measured heights (75.33pt, the "Steal from:" victim-picker
    /// state). Also duplicated (same literal, own doc comment) on
    /// `IncomingTradeCardView`'s own root frame, since that view lives in a
    /// separate file and takes over this same `bottomPanel` row - keep both
    /// in sync if this ever changes.
    private static let actionRowHeight: CGFloat = 75.33

    private var isTradeAvailable: Bool {
        if case .mainTurn(let index) = state.phase, index == human.index { return true }
        return false
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

    // MARK: - Popup presentation conditions

    private var isDiscardPresented: Bool {
        if case .discarding(let pending) = state.phase { return pending.contains(human) }
        return false
    }

    // MARK: - Dev card sub-flows

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
            break // Handled inline by `DevCardPopupView` itself.
        }
        devCardPopupType = nil
    }

    private func performDevCard(_ move: GameMove) {
        perform(move)
        devCardPopupType = nil
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
        } catch {
            errorMessage = error.localizedDescription
        }
        robberTargetTile = nil
        isKnightRobberActive = false
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
        } catch {
            errorMessage = error.localizedDescription
        }
        roadBuildingFirstEdge = nil
        isRoadBuildingActive = false
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
            if isRoadBuildingActive {
                if let first = roadBuildingFirstEdge {
                    return Set(legalMoves.compactMap {
                        if case .playRoadBuilding(let e1, let e2) = $0, e1 == first { return e2 }
                        return nil
                    })
                } else {
                    return Set(legalMoves.compactMap { if case .playRoadBuilding(let e1, _) = $0 { e1 } else { nil } })
                }
            }
            if placementMode == .road {
                return Set(legalMoves.compactMap { if case .buildRoad(let e) = $0 { e } else { nil } })
            }
            return []
        default:
            return []
        }
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
    private func isOfferCurrentlyFulfillable(_ offer: TradeOffer) -> Bool {
        guard let proposer = state.players.first(where: { $0.id == offer.from }),
              let responder = state.players.first(where: { $0.id == human })
        else { return false }
        let humanCanAfford = offer.want.allSatisfy { resource, amount in (responder.resources[resource] ?? 0) >= amount }
        let proposerCanAfford = offer.give.allSatisfy { resource, amount in (proposer.resources[resource] ?? 0) >= amount }
        return humanCanAfford && proposerCanAfford
    }

    private func respond(to offer: TradeOffer, accept: Bool) {
        do {
            try viewModel.apply(.respondToTrade(offerID: offer.id, accept: accept))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        incomingOfferQueue.removeAll { $0.id == offer.id }
    }

    // MARK: - Roll tile highlight

    /// Watches `state.log` growth purely to notice "X rolled N" lines (the
    /// exact phrasing `RulesEngine.apply(.rollDice, ...)` appends - a small,
    /// disclosed coupling to log wording, same tradeoff `GameView`'s old
    /// notification-classifier made) so the producing tiles can be
    /// highlighted regardless of whether the human or a bot rolled it.
    private func handleLogGrowth(newCount: Int) {
        defer { lastSeenLogCount = newCount }
        guard newCount > lastSeenLogCount, newCount <= state.log.count else { return }
        guard state.log[lastSeenLogCount..<newCount].contains(where: { $0.contains(" rolled ") }),
              let roll = state.lastDiceRoll else { return }
        highlightProducingTiles(for: roll)
    }

    /// Briefly outlines every tile matching `roll` (mirrors `MainPhase
    /// .rollDice`'s own "which tiles produce" rule: matches the roll and
    /// isn't under the robber) so it's clear at a glance where this roll's
    /// production came from.
    private func highlightProducingTiles(for roll: Int) {
        let producingTiles = state.board.tiles.filter { $0.numberToken == roll && $0.coordinate != state.board.robberTile }
        guard !producingTiles.isEmpty else { return }

        withAnimation(.easeIn(duration: 0.15)) {
            rollHighlightTiles = Set(producingTiles.map(\.coordinate))
        }
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            withAnimation(.easeOut(duration: 0.3)) {
                rollHighlightTiles = []
            }
        }
    }
}

#Preview {
    GameView(viewModel: GameViewModel(), onExitToMenu: {})
}
