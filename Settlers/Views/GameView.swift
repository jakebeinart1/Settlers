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

/// Reports each player's HUD chip/panel frame (in the `"game"` coordinate
/// space `GameView` establishes) so a resource-production flight animation
/// can land on the right spot - see `PlayerHUDView`'s chips/panel, which tag
/// themselves via this key.
struct PlayerFrameKey: PreferenceKey {
    static var defaultValue: [PlayerID: CGRect] { [:] }
    static func reduce(value: inout [PlayerID: CGRect], nextValue: () -> [PlayerID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Reports the board's own frame (same coordinate space as `PlayerFrameKey`)
/// - used as the roll-production flight animation's fallback launch point
/// when a producing tile's own center (`TileCenterKey`) isn't available yet.
private struct BoardFrameKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Reports each board tile's on-screen center (same coordinate space as
/// `PlayerFrameKey`/`BoardFrameKey`), from `BoardView`, so the roll-
/// production flight animation can launch each flying resource badge from
/// the actual tile that produced it.
struct TileCenterKey: PreferenceKey {
    static var defaultValue: [HexCoordinate: CGPoint] { [:] }
    static func reduce(value: inout [HexCoordinate: CGPoint], nextValue: () -> [HexCoordinate: CGPoint]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// One resource unit (or stack) animating from the board to a player's HUD
/// spot after a dice roll - see `GameView.animateProduction(for:)`.
private struct ResourceFlight: Identifiable {
    let id = UUID()
    let resource: Resource
    let count: Int
    let start: CGPoint
    let end: CGPoint
}

/// Small badge that flies from `flight.start` to `flight.end` and fades out,
/// calling `onComplete` once its animation has fully played - `GameView`
/// uses that to drop it from `resourceFlights`.
private struct ResourceFlightBadge: View {
    let flight: ResourceFlight
    let onComplete: () -> Void

    @State private var position: CGPoint
    @State private var opacity: Double = 1
    @State private var scale: CGFloat = 0.6

    init(flight: ResourceFlight, onComplete: @escaping () -> Void) {
        self.flight = flight
        self.onComplete = onComplete
        _position = State(initialValue: flight.start)
    }

    var body: some View {
        // Just the resource's own color as a plain dot - no icon - matching
        // how resources are shown everywhere else that favors a quick
        // glance (the HUD's hand rows, trade offer cards) over needing to
        // read a symbol while it's mid-flight.
        ZStack {
            Circle()
                .fill(CatanTheme.color(for: flight.resource))
                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
            if flight.count > 1 {
                Text("\(flight.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 18, height: 18)
        .shadow(radius: 3)
        .scaleEffect(scale)
        .position(position)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                scale = 1
            }
            withAnimation(.easeInOut(duration: 1.3)) {
                position = flight.end
            }
            withAnimation(.easeIn(duration: 0.3).delay(1.0)) {
                opacity = 0
            }
            Task {
                try? await Task.sleep(for: .milliseconds(1350))
                onComplete()
            }
        }
    }
}

/// The real, composed game screen, top to bottom: `BotHUDRow` (the 3 bot
/// chips only), `BoardView` filling the middle - with the dice pinned to its
/// bottom-left corner - `HumanPlayerPanel` (the human's own spacious info
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
/// trade offers surface as a small `IncomingTradeCardView` above the action
/// row with a 5-second accept window.
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
    /// Mid-game access to `SettingsView` (civilization picker) - there was
    /// previously no way to reach it once a game started, only from
    /// `MainMenuView`'s gear icon before "New Game". Changes still only take
    /// effect on the *next* new game (see `SettingsView`'s own docs), but
    /// being able to see/adjust them without abandoning the current game is
    /// worth the small top-corner button.
    @State private var isShowingSettings = false

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

    /// Bookkeeping for the roll production animation: tiles matching the
    /// most recent roll (briefly outlined on the board), the in-flight
    /// resource badges themselves, and the last count of `state.log` we've
    /// already scanned (so a growth of exactly the lines added since then
    /// can be checked for a "rolled N" line without re-scanning the whole
    /// log every render).
    @State private var rollHighlightTiles: Set<HexCoordinate> = []
    @State private var resourceFlights: [ResourceFlight] = []
    @State private var lastSeenLogCount = 0
    @State private var resourcesSnapshot: [PlayerID: [Resource: Int]] = [:]

    /// Player HUD chip/panel frames and the board's own frame, both in the
    /// `"game"` coordinate space this view establishes - populated via
    /// `PlayerFrameKey`/`BoardFrameKey` preferences from `PlayerHUDView`'s
    /// chips/panel and the board container below, purely to give
    /// `animateProduction(for:)` launch/landing points.
    @State private var playerAnchors: [PlayerID: CGRect] = [:]
    @State private var boardFrame: CGRect = .zero
    @State private var tileCenters: [HexCoordinate: CGPoint] = [:]

    private var state: GameState { viewModel.state }
    private var human: PlayerID { viewModel.humanPlayer }

    public var body: some View {
        ZStack {
            CatanTheme.waterBackground.ignoresSafeArea()

            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    BotHUDRow(state: state)
                        .padding(.trailing, 30)

                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                ZStack(alignment: .bottomLeading) {
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
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: BoardFrameKey.self, value: geo.frame(in: .named("game")))
                        }
                    )

                    if let roll = state.lastDiceRoll {
                        diceChip(roll)
                            .padding(10)
                    }
                }
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if isRoadBuildingActive {
                    Text(roadBuildingFirstEdge == nil ? "Road Building: pick the first free road" : "Road Building: pick the second free road")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                HumanPlayerPanel(state: state, onTapDevCard: { devCardPopupType = $0 })

                if let currentOffer = incomingOfferQueue.first {
                    IncomingTradeCardView(
                        offer: currentOffer,
                        onAccept: { respond(to: currentOffer, accept: true) },
                        onReject: { respond(to: currentOffer, accept: false) }
                    )
                }

                bottomPanel
            }
            .padding(8)

            ForEach(resourceFlights) { flight in
                ResourceFlightBadge(flight: flight) {
                    resourceFlights.removeAll { $0.id == flight.id }
                }
            }
            .allowsHitTesting(false)

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
        .coordinateSpace(name: "game")
        .onPreferenceChange(PlayerFrameKey.self) { playerAnchors = $0 }
        .onPreferenceChange(BoardFrameKey.self) { boardFrame = $0 }
        .onPreferenceChange(TileCenterKey.self) { tileCenters = $0 }
        .onAppear {
            seenTradeOfferIDs = Set(state.pendingTradeOffers.map(\.id))
            lastSeenLogCount = state.log.count
            resourcesSnapshot = currentResourcesByPlayer()
        }
        .onChange(of: state.pendingTradeOffers.map(\.id)) { _, _ in
            handleTradeOffersChange()
        }
        .onChange(of: state.lastDiceRoll) { _, newValue in
            guard newValue != nil else { return }
            animateDiceRoll()
        }
        .onChange(of: state.log.count) { _, newCount in
            handleLogGrowth(newCount: newCount)
        }
        .onChange(of: isRobberTargetingActive) { _, isActive in
            if !isActive { robberTargetTile = nil }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(onDismiss: { isShowingSettings = false })
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

    private func diceChip(_ roll: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "die.face.\(min(max(roll, 1), 6)).fill")
            Text("Rolled \(roll)")
                .font(.caption.bold())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.45), in: Capsule())
        .scaleEffect(diceScale)
        .rotationEffect(.degrees(diceRotation))
    }

    // MARK: - Bottom panel: one uniform action row (or the inline
    // robber-targeting panel while a robber move is pending) over a
    // lighter water panel

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            if isRobberTargetingActive {
                robberTargetingPanel
            } else {
                actionRow
            }
        }
        .padding(8)
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
            UniformActionButton(
                title: "Trade", systemImage: "arrow.left.arrow.right",
                isEnabled: isTradeAvailable
            ) {
                showTradePopup = true
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
            errorMessage = "\(error)"
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
            errorMessage = "\(error)"
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
            errorMessage = "\(error)"
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

        for offer in state.pendingTradeOffers where offer.from != human && !seenTradeOfferIDs.contains(offer.id) {
            seenTradeOfferIDs.insert(offer.id)
            incomingOfferQueue.append(offer)
        }
    }

    private func respond(to offer: TradeOffer, accept: Bool) {
        do {
            try viewModel.apply(.respondToTrade(offerID: offer.id, accept: accept))
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
        incomingOfferQueue.removeAll { $0.id == offer.id }
    }

    // MARK: - Roll production animation

    /// Watches `state.log` growth purely to notice "X rolled N" lines (the
    /// exact phrasing `RulesEngine.apply(.rollDice, ...)` appends - a small,
    /// disclosed coupling to log wording, same tradeoff `GameView`'s old
    /// notification-classifier made) so a roll can be animated regardless of
    /// whether the human or a bot rolled it. `resourcesSnapshot` is always
    /// refreshed afterward so the *next* roll's diff isn't polluted by
    /// builds/trades/discards that happened in between.
    private func handleLogGrowth(newCount: Int) {
        defer {
            lastSeenLogCount = newCount
            resourcesSnapshot = currentResourcesByPlayer()
        }
        guard newCount > lastSeenLogCount, newCount <= state.log.count else { return }
        guard state.log[lastSeenLogCount..<newCount].contains(where: { $0.contains(" rolled ") }),
              let roll = state.lastDiceRoll else { return }
        animateProduction(for: roll)
    }

    private func currentResourcesByPlayer() -> [PlayerID: [Resource: Int]] {
        Dictionary(uniqueKeysWithValues: state.players.map { ($0.id, $0.resources) })
    }

    /// Briefly outlines every tile matching `roll` (mirrors `MainPhase
    /// .rollDice`'s own "which tiles produce" rule: matches the roll and
    /// isn't under the robber) and, for each player whose hand grew since
    /// `resourcesSnapshot`, spawns a small flying badge per gained resource -
    /// launched from the specific producing tile's own on-screen spot
    /// (`tileCenters`), not just the board's center, so a card visibly
    /// "comes from" the tile that produced it. The *totals* still come from
    /// diffing actual resource counts (correct even when the bank couldn't
    /// cover full demand); tile position is only used to decide where each
    /// unit of that already-correct total visually launches from - purely a
    /// presentation flourish over `MainPhase`'s already-applied production,
    /// not a second source of truth for it.
    private func animateProduction(for roll: Int) {
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

        let boardOrigin = boardFrame == .zero ? nil : CGPoint(x: boardFrame.midX, y: boardFrame.midY)

        for player in state.players {
            guard let anchor = playerAnchors[player.id], anchor != .zero else { continue }
            let destination = CGPoint(x: anchor.midX, y: anchor.midY)
            let before = resourcesSnapshot[player.id] ?? [:]

            for resource in Resource.allCases {
                var remaining = (player.resources[resource] ?? 0) - (before[resource] ?? 0)
                guard remaining > 0 else { continue }

                // Which of this roll's producing tiles of this resource does
                // the player actually touch? (Usually one; a randomized
                // board could repeat a resource on two tiles sharing the
                // rolled number, or the bank could have partly covered a
                // multi-tile demand - either way, split the already-correct
                // total across them rather than assuming a single source.)
                let sourceTiles = producingTiles.filter { $0.kind == .resource(resource) }
                let touchedSourceTiles = sourceTiles.filter { touchesTile($0.coordinate, player: player) }
                let tilesToUse = touchedSourceTiles.isEmpty ? sourceTiles : touchedSourceTiles
                guard !tilesToUse.isEmpty else { continue }

                let share = max(1, remaining / tilesToUse.count)
                for tile in tilesToUse {
                    guard remaining > 0 else { break }
                    guard let origin = tileCenters[tile.coordinate] ?? boardOrigin else { continue }
                    let amount = min(share, remaining)
                    resourceFlights.append(ResourceFlight(resource: resource, count: amount, start: origin, end: destination))
                    remaining -= amount
                }
            }
        }
    }

    /// Whether `player` has a settlement or city on any vertex touching
    /// `coordinate` - used only to attribute a roll's already-computed
    /// resource gain back to the right tile for the flight animation.
    private func touchesTile(_ coordinate: HexCoordinate, player: Player) -> Bool {
        state.board.onBoardVertices.contains { vertex in
            vertex.touchingTiles.contains(coordinate)
                && (player.settlements.contains(vertex) || player.cities.contains(vertex))
        }
    }
}

#Preview {
    GameView(viewModel: GameViewModel())
}
