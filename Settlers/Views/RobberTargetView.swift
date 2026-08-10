import SwiftUI
import CatanEngine

/// Modal for choosing where to move the robber (and, if it lands on a tile
/// bordered by an opponent, who to steal from). Used both as the mandatory
/// modal after a 7-roll (`mode: .mandatory`, phase `.movingRobber`) and as
/// the knight dev-card sub-flow (`mode: .knightCard`, from
/// `DevCardPanelView`) - the only difference is which `GameMove` case
/// committing the pick produces.
public struct RobberTargetView: View {
    public enum Mode: Equatable {
        case mandatory
        case knightCard
    }

    public let viewModel: GameViewModel
    public let mode: Mode
    public var onComplete: () -> Void = {}

    public init(viewModel: GameViewModel, mode: Mode, onComplete: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.mode = mode
        self.onComplete = onComplete
    }

    @State private var selectedTile: HexCoordinate?
    @State private var errorMessage: String?

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Move the Robber")
                    .font(.headline)

                BoardView(
                    state: viewModel.state,
                    onTapVertex: { _ in },
                    onTapEdge: { _ in },
                    onTapTile: { tile in
                        guard tile != viewModel.state.board.robberTile else { return }
                        selectedTile = tile
                    }
                )
                .frame(height: 320)

                if let selectedTile {
                    let victims = Robber.eligibleVictims(for: selectedTile, thief: viewModel.humanPlayer, in: viewModel.state)
                    if victims.isEmpty {
                        Button("Move Robber Here") { commit(tile: selectedTile, victim: nil) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Text("Steal from:")
                            .font(.subheadline)
                        HStack {
                            ForEach(victims, id: \.self) { victim in
                                Button(CatanTheme.playerLabel(for: victim)) {
                                    commit(tile: selectedTile, victim: victim)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                } else {
                    Text("Tap a tile to move the robber there.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
    }

    private func commit(tile: HexCoordinate, victim: PlayerID?) {
        let move: GameMove
        switch mode {
        case .mandatory:
            move = .moveRobber(tile, stealFrom: victim)
        case .knightCard:
            move = .playKnight(moveRobberTo: tile, stealFrom: victim)
        }
        do {
            try viewModel.apply(move)
            errorMessage = nil
            selectedTile = nil
            onComplete()
        } catch {
            errorMessage = "\(error)"
        }
    }
}
