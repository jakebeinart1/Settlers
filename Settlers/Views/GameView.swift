import SwiftUI
import CatanEngine

/// Which kind of build placement the human has armed via `BuildMenuView`.
/// While non-nil, `BoardView` is put into placement mode: only legal targets
/// for that move are tappable, everything else dims out.
public enum PlacementMode: Equatable {
    case road
    case settlement
    case city
}

/// The real, composed game screen, top to bottom: `BotHUDRow` (the 3 bot
/// chips only), `BoardView` filling the middle over a water-blue background,
/// `GameLogView`, `HumanPlayerPanel` (the human's own spacious info panel),
/// then the dice chip and a single uniform action row (Build/Trade/Dev
/// Cards/turn action) over a lighter-blue panel. `TradeSheetView`/
/// `DiscardView` are sheets driven by `viewModel.state.phase`; the mandatory
/// post-7-roll robber move happens inline on this same `BoardView` (see
/// `isMandatoryRobberActive`) rather than as a sheet, while the knight-card
/// robber sub-flow (from the dev-card panel) still uses `RobberTargetView`
/// as a sheet. A transient notification overlay surfaces bot trade offers
/// and build/dev-card/longest-road/largest-army events on top of everything
/// else.
public struct GameView: View {
    public let viewModel: GameViewModel

    public init(viewModel: GameViewModel) {
        self.viewModel = viewModel
    }

    @State private var placementMode: PlacementMode?
    @State private var showTradeSheet = false
    @State private var showDevCardPanel = false
    @State private var showKnightRobberSheet = false
    @State private var errorMessage: String?

    /// Road-building sub-flow: `nil` when inactive; once armed, the first
    /// tapped edge is held here while the second is picked, then both are
    /// applied together as `.playRoadBuilding(first, second)`.
    @State private var roadBuildingFirstEdge: EdgeID?
    @State private var isRoadBuildingActive = false

    /// Mandatory robber-move sub-flow, inline on the main board: once the
    /// human taps a legal tile, it's held here while an eligible victim (if
    /// any) is picked from the inline picker in `bottomPanel`; committing
    /// (or a tile with no eligible victims) applies `.moveRobber` directly.
    @State private var robberTargetTile: HexCoordinate?

    /// Drives the dice chip's brief scale/rotate pulse on a new roll -
    /// bumped in `onChange(of: state.lastDiceRoll)`.
    @State private var diceScale: CGFloat = 1.0
    @State private var diceRotation: Double = 0

    // MARK: - Notifications
    //
    // UI-layer-only, built by diffing `state.log`/`state.longestRoadPlayer`/
    // `state.largestArmyPlayer`/`state.pendingTradeOffers` on each render
    // rather than adding a structured event feed to `CatanEngine` - the log
    // strings (and the two "who holds this" fields) already carry everything
    // these need, so matching substrings here keeps the change UI-only
    // instead of touching `RulesEngine`'s many log call sites for what is,
    // in the end, a presentation concern.
    @State private var notifications: [GameNotification] = []
    @State private var lastSeenLogCount = 0
    @State private var lastLongestRoadPlayer: PlayerID?
    @State private var lastLargestArmyPlayer: PlayerID?
    @State private var seenTradeOfferIDs: Set<UUID> = []

    private var state: GameState { viewModel.state }
    private var human: PlayerID { viewModel.humanPlayer }

    public var body: some View {
        ZStack {
            VStack(spacing: 8) {
                BotHUDRow(state: state)

                BoardView(
                    state: state,
                    onTapVertex: handleTapVertex,
                    onTapEdge: handleTapEdge,
                    onTapTile: handleTapTile,
                    highlightedVertices: highlightedVertices,
                    highlightedEdges: highlightedEdges,
                    isPlacementModeActive: isPlacementModeActive || isMandatoryRobberActive,
                    highlightedTiles: highlightedTilesForRobber,
                    isTileTargetingActive: isMandatoryRobberActive
                )
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

                GameLogView(log: state.log)
                    .frame(height: 90)

                HumanPlayerPanel(state: state)

                bottomPanel
            }
            .padding(8)

            GameNotificationOverlay(notifications: notifications)
                .allowsHitTesting(!notifications.isEmpty)
                .frame(maxHeight: .infinity, alignment: .top)

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
        }
        .sheet(isPresented: $showTradeSheet) {
            TradeSheetView(viewModel: viewModel)
        }
        .sheet(isPresented: $showDevCardPanel) {
            NavigationStack {
                DevCardPanelView(viewModel: viewModel, onPlay: handleDevCardPlay)
                    .padding()
                    .navigationTitle("Development Cards")
            }
        }
        .sheet(isPresented: $showKnightRobberSheet) {
            RobberTargetView(viewModel: viewModel, mode: .knightCard) {
                showKnightRobberSheet = false
            }
        }
        .sheet(isPresented: isDiscardPresented) {
            DiscardView(viewModel: viewModel)
                .interactiveDismissDisabled(true)
        }
        .onAppear {
            lastSeenLogCount = state.log.count
            lastLongestRoadPlayer = state.longestRoadPlayer
            lastLargestArmyPlayer = state.largestArmyPlayer
            seenTradeOfferIDs = Set(state.pendingTradeOffers.map(\.id))
        }
        .onChange(of: state.log.count) { _, newCount in
            handleLogChange(newCount: newCount)
        }
        .onChange(of: state.longestRoadPlayer) { _, newValue in
            handleLongestRoadChange(newValue)
        }
        .onChange(of: state.largestArmyPlayer) { _, newValue in
            handleLargestArmyChange(newValue)
        }
        .onChange(of: state.pendingTradeOffers.map(\.id)) { _, _ in
            handleTradeOffersChange()
        }
        .onChange(of: state.lastDiceRoll) { _, newValue in
            guard newValue != nil else { return }
            animateDiceRoll()
        }
        .onChange(of: isMandatoryRobberActive) { _, isActive in
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

    // MARK: - Bottom panel: dice chip + one uniform action row (or the
    // inline robber-targeting panel while a mandatory robber move is
    // pending) over a lighter water panel

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            if let roll = state.lastDiceRoll {
                diceChip(roll)
            }
            if isMandatoryRobberActive {
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

    private func diceChip(_ roll: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "die.face.\(min(max(roll, 1), 6)).fill")
            Text("Rolled \(roll)")
                .font(.caption.bold())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.35), in: Capsule())
        .scaleEffect(diceScale)
        .rotationEffect(.degrees(diceRotation))
    }

    /// Build / Trade / Dev Cards / turn action (Roll Dice or End Turn), all
    /// in one uniform row - always showing all four slots so the row never
    /// jumps around as phase changes; options that don't apply right now
    /// disable+dim instead of disappearing.
    private var actionRow: some View {
        HStack(spacing: 10) {
            BuildMenuView(viewModel: viewModel, placementMode: $placementMode)
            UniformActionButton(
                title: "Trade", systemImage: "arrow.left.arrow.right",
                isEnabled: isTradeAvailable
            ) {
                showTradeSheet = true
            }
            UniformActionButton(
                title: "Dev Cards", systemImage: "rectangle.stack.badge.person.crop",
                isEnabled: isDevCardPanelAvailable
            ) {
                showDevCardPanel = true
            }
            turnActionButton
        }
    }

    /// Replaces `actionRow` while `isMandatoryRobberActive`: instructs the
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

    private var isDevCardPanelAvailable: Bool {
        if case .mainTurn(let index) = state.phase, index == human.index { return true }
        return false
    }

    @ViewBuilder
    private var turnActionButton: some View {
        switch state.phase {
        case .rollDice(let playerIndex) where playerIndex == human.index:
            UniformActionButton(title: "Roll Dice", systemImage: "die.face.5.fill", isEnabled: true) {
                perform(.rollDice)
            }
        case .mainTurn(let playerIndex) where playerIndex == human.index:
            UniformActionButton(title: "End Turn", systemImage: "arrow.uturn.right.circle.fill", isEnabled: true) {
                perform(.endTurn)
            }
        default:
            UniformActionButton(title: "Turn", systemImage: "hourglass", isEnabled: false) {}
        }
    }

    // MARK: - Sheet presentation bindings

    private var isDiscardPresented: Binding<Bool> {
        Binding(
            get: {
                if case .discarding(let pending) = state.phase { return pending.contains(human) }
                return false
            },
            set: { _ in }
        )
    }

    // MARK: - Dev card sub-flows

    private func handleDevCardPlay(_ type: DevCardType) {
        switch type {
        case .knight:
            showKnightRobberSheet = true
        case .roadBuilding:
            roadBuildingFirstEdge = nil
            isRoadBuildingActive = true
            placementMode = nil
        case .yearOfPlenty, .monopoly, .victoryPoint:
            break // Handled inside DevCardPanelView itself.
        }
        showDevCardPanel = false
    }

    // MARK: - Inline robber-move flow (mandatory post-7-roll case)

    /// True exactly while the human owes a mandatory robber move -
    /// `state.phase == .movingRobber(human.index)`. Drives `BoardView` into
    /// tile-targeting mode and swaps `bottomPanel`'s action row for
    /// `robberTargetingPanel`.
    private var isMandatoryRobberActive: Bool {
        if case .movingRobber(let playerIndex) = state.phase { return playerIndex == human.index }
        return false
    }

    /// Every tile except the robber's current one - the only illegal target
    /// per `Robber.apply`/`RulesEngine.legalMoves`.
    private var highlightedTilesForRobber: Set<HexCoordinate> {
        guard isMandatoryRobberActive else { return [] }
        return Set(state.board.tiles.map(\.coordinate)).subtracting([state.board.robberTile])
    }

    private var robberVictims: [PlayerID] {
        guard let robberTargetTile else { return [] }
        return Robber.eligibleVictims(for: robberTargetTile, thief: human, in: state)
    }

    private func handleTapTile(_ tile: HexCoordinate) {
        guard isMandatoryRobberActive, tile != state.board.robberTile else { return }
        let victims = Robber.eligibleVictims(for: tile, thief: human, in: state)
        if victims.isEmpty {
            performRobberMove(tile: tile, victim: nil)
        } else {
            robberTargetTile = tile
        }
    }

    private func performRobberMove(tile: HexCoordinate, victim: PlayerID?) {
        do {
            try viewModel.apply(.moveRobber(tile, stealFrom: victim))
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
        robberTargetTile = nil
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

    private var isPlacementModeActive: Bool {
        switch state.phase {
        case .setupForward, .setupBackward:
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

    // MARK: - Notification triggers

    private func handleLogChange(newCount: Int) {
        defer { lastSeenLogCount = newCount }
        guard newCount > lastSeenLogCount, newCount <= state.log.count else { return }
        for line in state.log[lastSeenLogCount..<newCount] {
            if let notification = classify(logLine: line) {
                enqueue(notification)
            }
        }
    }

    /// Matches the exact log phrasing `RulesEngine`/`SetupPhase` append (see
    /// their `state.log.append(...)` call sites) - a small, disclosed
    /// coupling to log wording in exchange for not touching `CatanEngine`.
    private func classify(logLine line: String) -> GameNotification? {
        if line.contains("built a road") || line.contains("placed a road") {
            return GameNotification(text: line, systemImage: "line.diagonal", tint: .brown)
        }
        if line.contains("built a settlement") || line.contains("placed a settlement") {
            return GameNotification(text: line, systemImage: "house.fill", tint: .green)
        }
        if line.contains("built a city") {
            return GameNotification(text: line, systemImage: "building.2.fill", tint: .indigo)
        }
        if line.contains("played a knight") || line.contains("played road building")
            || line.contains("played year of plenty") || line.contains("played monopoly") {
            return GameNotification(text: line, systemImage: "rectangle.stack.fill", tint: .purple)
        }
        return nil
    }

    private func handleLongestRoadChange(_ newValue: PlayerID?) {
        defer { lastLongestRoadPlayer = newValue }
        guard let newValue, newValue != lastLongestRoadPlayer else { return }
        enqueue(GameNotification(
            text: "\(CatanTheme.playerLabel(for: newValue)) now has the Longest Road",
            systemImage: "road.lanes", tint: .orange
        ))
    }

    private func handleLargestArmyChange(_ newValue: PlayerID?) {
        defer { lastLargestArmyPlayer = newValue }
        guard let newValue, newValue != lastLargestArmyPlayer else { return }
        enqueue(GameNotification(
            text: "\(CatanTheme.playerLabel(for: newValue)) now has the Largest Army",
            systemImage: "shield.fill", tint: .red
        ))
    }

    private func handleTradeOffersChange() {
        for offer in state.pendingTradeOffers where offer.from != human && !seenTradeOfferIDs.contains(offer.id) {
            seenTradeOfferIDs.insert(offer.id)
            enqueue(GameNotification(
                text: "\(CatanTheme.playerLabel(for: offer.from)) wants to trade",
                systemImage: "arrow.left.arrow.right", tint: .blue,
                onTap: { showTradeSheet = true }
            ))
        }
    }

    private func enqueue(_ notification: GameNotification) {
        withAnimation {
            notifications.append(notification)
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation {
                notifications.removeAll { $0.id == notification.id }
            }
        }
    }
}

#Preview {
    GameView(viewModel: GameViewModel())
}
