import SwiftUI
import CatanEngine

/// Top HUD strip: one compact chip per player showing name/personality,
/// resource-card count, victory points, and longest-road/largest-army
/// badges. The human's chip additionally breaks its hand down by resource
/// (bots' hands stay a single face-down count, matching what a human player
/// would actually be able to see across the table).
public struct PlayerHUDView: View {
    public let state: GameState

    public init(state: GameState) {
        self.state = state
    }

    private let human = PlayerID(index: 0)

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(state.players, id: \.id) { player in
                chip(for: player)
            }
        }
    }

    @ViewBuilder
    private func chip(for player: Player) -> some View {
        let isHuman = player.id == human
        let isActive = isActivePlayer(player.id)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(CatanTheme.color(for: player.id))
                    .frame(width: 10, height: 10)
                Text(isHuman ? "You" : "\(personalityLabel(for: player.id))")
                    .font(.caption.bold())
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(state.victoryPoints(for: player.id)) VP")
                    .font(.caption2.bold())
            }

            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.caption2)
                Text("\(totalResources(player))")
                    .font(.caption2)

                if state.longestRoadPlayer == player.id {
                    badge("road.lanes", tint: .orange)
                }
                if state.largestArmyPlayer == player.id {
                    badge("shield.fill", tint: .red)
                }
            }

            if isHuman {
                HStack(spacing: 6) {
                    ForEach(Resource.allCases, id: \.self) { resource in
                        let count = player.resources[resource] ?? 0
                        if count > 0 {
                            VStack(spacing: 1) {
                                Circle()
                                    .fill(CatanTheme.color(for: resource))
                                    .frame(width: 8, height: 8)
                                Text("\(count)")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: isActive ? 0.20 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isActive ? CatanTheme.color(for: player.id) : .clear, lineWidth: 2)
        )
    }

    private func badge(_ systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
    }

    private func totalResources(_ player: Player) -> Int {
        player.resources.values.reduce(0, +)
    }

    private func isActivePlayer(_ id: PlayerID) -> Bool {
        switch state.phase {
        case .setupForward(let index), .setupBackward(let index),
             .rollDice(let index), .mainTurn(let index), .movingRobber(let index):
            return PlayerID(index: index) == id
        case .discarding(let pending):
            return pending.contains(id)
        case .gameOver:
            return false
        }
    }

    /// Mirrors `GameViewModel`'s bot-personality assignment (1 -> balanced,
    /// 2 -> aggressive, 3 -> cautious) so the HUD can label bot chips without
    /// depending on `GameViewModel`/`CatanAI` directly.
    private func personalityLabel(for id: PlayerID) -> String {
        switch id.index {
        case 1: return "Bot (Balanced)"
        case 2: return "Bot (Aggressive)"
        case 3: return "Bot (Cautious)"
        default: return "Bot"
        }
    }
}

#Preview {
    PlayerHUDView(state: GameSetup.newGame(board: BoardGenerator.standard()))
        .padding()
        .background(Color.black)
}
