import SwiftUI
import CatanEngine

/// Top HUD strip: one compact chip per player showing name/personality,
/// resource breakdown, development-card count, and victory-point/longest-
/// road/largest-army tags. All four players' resource hands are shown in
/// full (an intentional simplification for a casual single-device game -
/// everyone's sitting at the same table anyway) while dev cards stay a
/// count-only badge for every player, since which specific cards a player
/// holds is the one piece of information that's legitimately hidden even in
/// a casual game.
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
            }

            // Short labels ("Road"/"Army" rather than "Longest Road"/"Largest
            // Army") so a tag stays legible inside a chip that's only
            // ~90pt wide at 4-across - the icon plus a one-word label is
            // still identifiable at a glance without wrapping.
            HStack(spacing: 4) {
                tag(text: "\(state.victoryPoints(for: player.id)) VP", icon: "star.fill", tint: .yellow)
                if state.longestRoadPlayer == player.id {
                    tag(text: "Road", icon: "road.lanes", tint: .orange)
                }
                if state.largestArmyPlayer == player.id {
                    tag(text: "Army", icon: "shield.fill", tint: .red)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.caption2)
                Text("\(totalResources(player))")
                    .font(.caption2)
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.caption2)
                Text("\(player.devCards.count)")
                    .font(.caption2)
            }
            .foregroundStyle(CatanTheme.onWaterText)

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
                                .foregroundStyle(CatanTheme.onWaterText)
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

    /// Small labeled pill - icon + short text - used for the VP/longest-road/
    /// largest-army indicators so they read as a single family of tags
    /// rather than a bare icon the viewer has to already know how to decode.
    private func tag(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 9, weight: .bold))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(tint.opacity(0.85), in: Capsule())
        .fixedSize()
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
