import SwiftUI
import CatanEngine

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
/// `HumanPlayerPanel`, with a 5-second accept window.
///
/// A roll used to also spawn small resource badges flying from each
/// producing tile to the gaining player's HUD spot - dropped in favor of
/// just the dice chip and the board's own roll-matching tile highlight,
/// which already say the same thing with far less visual noise to track.
public struct GameView: View {
    public let viewModel: GameViewModel

    public init(viewModel: GameViewModel) {
        self.viewModel = viewModel
    }

    @State private var placementMode: PlacementMode?
    @State private var showTradePopup = false
    @State private var showBuildPopup = false
    @State private var devCardPopupType: DevCardType?
    @State private var errorMessage: String?

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

    /// Reserved height for the road-building hint / error message row - see
    /// `StableHeightSlot`.
    // Seeded with the row's actual measured height (see chat: rendered a
    // faithful reproduction and read off its real size) rather than 0 -
    // `StableHeightSlot` still grows to fit if real content ever needs more,
    // but starting from a real estimate means there's no gap between "app
    // just launched" and "something has measured once" for the board to
    // flicker through. That gap - not the measure-after-the-fact approach
    // itself - was the actual hole in the previous fix: this was 0 until the
    // first real occurrence, and a bare `Color.clear` placeholder (now fixed
    // separately) was what turned that brief 0 into a collapsed board.
    /// Shared by the road-building hint and the error message, the only two
    /// occupants now that the incoming-trade card lives in `bottomPanel`
    /// instead - seeded at one caption line's height (~20pt).
    @State private var infoBannerHeight: CGFloat = 20

    private var state: GameState { viewModel.state }
    private var human: PlayerID { viewModel.humanPlayer }

    public var body: some View {
        ZStack {
            CatanTheme.waterBackground.ignoresSafeArea()

            // `spacing: 0` rather than a uniform 8pt everywhere - board,
            // banner slot, and `HumanPlayerPanel` need to sit genuinely
            // flush against each other (no gap at all), while the rows
            // above the board still want *some* visual separation. Spacing
            // is added explicitly with `.padding(.bottom:)` only where it's
            // actually wanted, instead of uniformly.
            VStack(spacing: 0) {
                BotHUDRow(state: state)
                    .padding(.bottom, 3)

                // Back to overlaying the board's top-left corner (not its
                // own row) - that reclaims the whole row's height for the
                // board. It used to sit in the bottom-left corner
                // specifically, which is where it kept colliding with the
                // incoming trade card and other inline banners below the
                // board; the top-left corner is never where any of that
                // renders, so nothing to collide with up here even though
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
                    // A hair of top clearance - the outermost hex row's own
                    // ports (top-right in particular) sat close enough to
                    // the top edge to graze the dice/deck chips overlaid up
                    // there. `BoardView` re-fits and re-centers itself
                    // within whatever height it's given, so this nudges the
                    // whole hex grid down slightly rather than requiring the
                    // chips to shrink or move.
                    .padding(.top, 18)

                    if let roll = state.lastDiceRoll {
                        diceChip(roll)
                            .padding(8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                // Top-right corner, the same `.padding(8)` as the dice chip
                // so the two sit flush on one shared top line - the bank's
                // per-resource remaining counts and the dev-card deck's
                // remaining count, the same two piles a physical Catan board
                // keeps face-down next to the board itself.
                .overlay(alignment: .topTrailing) {
                    deckCountChip
                        .padding(8)
                }

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
                HumanPlayerPanel(state: state, onTapDevCard: { devCardPopupType = $0 })

                bottomPanel
                    .padding(.top, 8)
            }

            if viewModel.isBotThinking {
                VStack {
                    Text("Bot thinking…")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.7), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                    Spacer()
                }
                .allowsHitTesting(false)
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
        }
        .onAppear {
            seenTradeOfferIDs = Set(state.pendingTradeOffers.map(\.id))
            lastSeenLogCount = state.log.count
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
        // A trade offer is only really "live" during the turn it showed
        // up in - once the active player changes, it's stale from the
        // human's perspective (they had their window and it passed), even
        // though the offer itself may still sit in `state.pendingTradeOffers`
        // for a bot to pick up on some later turn of its own. Clearing only
        // the local queue here (not the engine-level offer) keeps that bot-
        // to-bot path working untouched.
        .onChange(of: activePlayerIndex) { _, _ in
            incomingOfferQueue.removeAll()
        }
    }

    /// The seat whose turn it currently is, or `nil` during `.discarding`
    /// (no single active player) or once the game's over. Used purely to
    /// notice when the turn has genuinely moved on, as opposed to every
    /// phase transition within the same player's turn (e.g. rollDice ->
    /// mainTurn, or mainTurn -> movingRobber -> mainTurn after a 7).
    private var activePlayerIndex: Int? {
        switch state.phase {
        case .setupForward(let index), .setupBackward(let index),
             .rollDice(let index), .mainTurn(let index), .movingRobber(let index):
            return index
        case .discarding, .gameOver:
            return nil
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

    /// Bigger and plainer than before (no more flying resource badges to
    /// share attention with) - the current roll is the one thing this
    /// needs to say clearly, so it gets a large number front and center.
    /// `rollHistory` (up to the 3 rolls before this one) sits underneath in
    /// a small, faded line - enough to catch someone back up at a glance
    /// without competing with the current roll for attention.
    private func diceChip(_ roll: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "die.face.\(min(max(roll, 1), 6)).fill")
                    .font(.title2)
                Text("\(roll)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.5), in: Capsule())
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
                    Circle()
                        .fill(CatanTheme.color(for: resource))
                        .frame(width: 10, height: 10)
                    Text("\(state.bank[resource] ?? 0)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
            }

            Divider()
                .frame(height: 22)
                .overlay(Color.white.opacity(0.3))

            VStack(spacing: 1) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 10))
                Text("\(state.devCardDeck.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Bottom panel: one uniform action row (or the inline
    // robber-targeting panel while a robber move is pending) over a
    // lighter water panel

    private var bottomPanel: some View {
        // Deliberately *not* a `StableHeightSlot` (unlike the banner/dice
        // rows above) - reserving its tallest possible state (the robber
        // victim-picker, ~95pt) permanently would mean paying that cost
        // during ordinary play too, where the plain action row only needs
        // ~73pt, and that's the vast majority of the game. A brief resize
        // during the comparatively rare robber-targeting flow is the
        // better trade against a permanently smaller board.
        VStack(spacing: 8) {
            if isRobberTargetingActive {
                robberTargetingPanel
            } else if let currentOffer = incomingOfferQueue.first {
                // A bot only ever proposes a trade during its own turn (see
                // `TradeHeuristics.proposeTrades`'s call site), which is
                // exactly the window where Build/Trade/Roll-or-End are all
                // inert for the human anyway - so this bar doing double duty
                // as the incoming-offer card instead of a separate row above
                // it costs nothing real: there's never a legal action this
                // is standing in front of.
                IncomingTradeCardView(
                    offer: currentOffer,
                    onAccept: { respond(to: currentOffer, accept: true) },
                    onReject: { respond(to: currentOffer, accept: false) }
                )
            } else {
                actionRow
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
                isEnabled: isTradeAvailable
            ) {
                showTradePopup = true
            }
            UniformActionButton(
                title: placementMode == nil ? "Build" : placementMode!.label,
                systemImage: placementMode == nil ? "hammer.fill" : "hammer.circle.fill",
                isEnabled: true,
                isArmed: placementMode != nil
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
    }

    private var isTradeAvailable: Bool {
        if case .mainTurn(let index) = state.phase, index == human.index { return true }
        return false
    }

    @ViewBuilder
    private var turnActionButton: some View {
        switch state.phase {
        case .rollDice(let playerIndex) where playerIndex == human.index:
            UniformActionButton(title: "Roll Dice", systemImage: "die.face.5.fill", isEnabled: true, isArmed: true) {
                perform(.rollDice)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
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
            UniformActionButton(title: "End Turn", systemImage: "arrow.uturn.right.circle.fill", isEnabled: true) {
                perform(.endTurn)
            }
        default:
            UniformActionButton(title: "Turn", systemImage: "hourglass", isEnabled: false) {}
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
        // reaches this queue.
        let humanResources = state.players.first(where: { $0.id == human })?.resources ?? [:]
        func humanCanAfford(_ offer: TradeOffer) -> Bool {
            offer.want.allSatisfy { resource, amount in (humanResources[resource] ?? 0) >= amount }
        }

        for offer in state.pendingTradeOffers
        where offer.from != human && !seenTradeOfferIDs.contains(offer.id) && humanCanAfford(offer) {
            seenTradeOfferIDs.insert(offer.id)
            incomingOfferQueue.append(offer)
        }
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
    GameView(viewModel: GameViewModel())
}
