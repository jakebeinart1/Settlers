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

/// The real, composed game screen: `PlayerHUDView` up top (unchanged
/// layout), `BoardView` filling the middle over a water-blue background,
/// `GameLogView`, two uniform bottom rows (build actions, then trade/turn
/// actions) over a lighter-blue panel, and `TradeSheetView`/
/// `RobberTargetView`/`DiscardView` as sheets driven by
/// `viewModel.state.phase` (or by the dev-card panel, for the knight and
/// road-building sub-flows). A transient notification overlay surfaces bot
/// trade offers and build/dev-card/longest-road/largest-army events on top
/// of everything else.
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
                PlayerHUDView(state: state)

                BoardView(
                    state: state,
                    onTapVertex: handleTapVertex,
                    onTapEdge: handleTapEdge,
                    onTapTile: { _ in },
                    highlightedVertices: highlightedVertices,
                    highlightedEdges: highlightedEdges,
                    isPlacementModeActive: isPlacementModeActive
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
        .sheet(isPresented: isMandatoryRobberPresented) {
            RobberTargetView(viewModel: viewModel, mode: .mandatory)
                .interactiveDismissDisabled(true)
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
    }

    // MARK: - Bottom panel: two uniform rows over a lighter water panel

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            if let roll = state.lastDiceRoll {
                diceChip(roll)
            }
            BuildMenuView(viewModel: viewModel, placementMode: $placementMode)
            tradeRow
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
    }

    /// Row 2: Trade / Dev Cards / turn action (Roll Dice or End Turn),
    /// always showing all three slots so the row never jumps around as
    /// phase changes - buttons that don't apply right now disable+dim
    /// instead of disappearing.
    private var tradeRow: some View {
        HStack(spacing: 10) {
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

    /// `.sheet(isPresented:)` needs a `Binding`, but presentation here is
    /// entirely a function of `state.phase`; the `set` is a no-op since
    /// applying the robber/discard move itself advances `state.phase` and
    /// naturally dismisses the sheet on the next render.
    private var isMandatoryRobberPresented: Binding<Bool> {
        Binding(
            get: {
                if case .movingRobber(let playerIndex) = state.phase { return playerIndex == human.index }
                return false
            },
            set: { _ in }
        )
    }

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
