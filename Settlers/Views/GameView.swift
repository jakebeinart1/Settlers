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

/// The real, composed game screen: `PlayerHUDView` up top, `BoardView`
/// filling the middle (with placement-mode highlighting driven by
/// `placementMode`/the road-building sub-flow), `GameLogView` +
/// `BuildMenuView` + trade/dev-card entry points along the bottom, and
/// `TradeSheetView`/`RobberTargetView`/`DiscardView` as sheets driven by
/// `viewModel.state.phase` (or by the dev-card panel, for the knight and
/// road-building sub-flows).
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

                turnControls

                HStack(spacing: 10) {
                    BuildMenuView(viewModel: viewModel, placementMode: $placementMode)
                    VStack(spacing: 6) {
                        Button("Trade") { showTradeSheet = true }
                        Button("Dev Cards") { showDevCardPanel = true }
                    }
                    .buttonStyle(.bordered)
                }
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
        }
        .sheet(isPresented: isDiscardPresented) {
            DiscardView(viewModel: viewModel)
        }
    }

    // MARK: - Turn controls

    @ViewBuilder
    private var turnControls: some View {
        switch state.phase {
        case .rollDice(let playerIndex) where playerIndex == human.index:
            Button("Roll Dice") { perform(.rollDice) }
                .buttonStyle(.borderedProminent)
        case .mainTurn(let playerIndex) where playerIndex == human.index:
            Button("End Turn") { perform(.endTurn) }
                .buttonStyle(.bordered)
        default:
            EmptyView()
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
}

#Preview {
    GameView(viewModel: GameViewModel())
}
