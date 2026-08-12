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

/// The real, composed game screen, top to bottom: `BotHUDRow` (the 3 bot
/// chips only), the dice chip (once there's been a roll) left-aligned in
/// its own row, `BoardView` filling the middle, `HumanPlayerPanel` (the
/// human's own spacious info
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

    private var state: GameState { viewModel.state }
    private var human: PlayerID { viewModel.humanPlayer }

    public var body: some View {
        ZStack {
            CatanTheme.waterBackground.ignoresSafeArea()

            VStack(spacing: 8) {
                BotHUDRow(state: state)

                // Its own row, below the opponent chips and above the
                // board, rather than pinned over the board's bottom-left
                // corner - overlaid there, it sat right where the incoming
                // trade card and other inline banners also come and go,
                // constantly nudging or getting crowded by them, and (once
                // the current-roll number got bigger) started overlapping
                // board content too.
                if let roll = state.lastDiceRoll {
                    HStack {
                        diceChip(roll)
                        Spacer(minLength: 0)
                    }
                }

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
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if isRoadBuildingActive {
                    Text(roadBuildingFirstEdge == nil ? "Road Building: pick the first free road" : "Road Building: pick the second free road")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                // Incoming bot trade offers get this exact spot, right
                // above `HumanPlayerPanel` - a floating overlay positioned
                // from the panel's tracked frame was tried instead (to
                // avoid this inline slot changing the VStack's total
                // height, which nudges the flexible board a little smaller
                // while it's showing), but that let the card overlap the
                // board above it instead. Inline here, its own transition
                // (a fade + slide) is the "flash" as it appears - a minor
                // board-size nudge is the trade-off for not overlapping
                // anything.
                if let currentOffer = incomingOfferQueue.first {
                    IncomingTradeCardView(
                        offer: currentOffer,
                        onAccept: { respond(to: currentOffer, accept: true) },
                        onReject: { respond(to: currentOffer, accept: false) }
                    )
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                HumanPlayerPanel(state: state, onTapDevCard: { devCardPopupType = $0 })

                bottomPanel
            }
            .padding(8)

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
