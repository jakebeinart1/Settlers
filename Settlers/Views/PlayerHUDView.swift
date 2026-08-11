import SwiftUI
import CatanEngine

/// Top HUD strip: one compact chip per **bot** player (the human gets their
/// own, more spacious panel at the bottom of the screen - see
/// `HumanPlayerPanel`) showing name/personality, resource breakdown,
/// development-card count, and victory-point/longest-road/largest-army tags.
/// Every player's resource hand is shown in full (an intentional
/// simplification for a casual single-device game - everyone's sitting at
/// the same table anyway) while dev cards stay a count-only badge for every
/// player, since which specific cards a player holds is the one piece of
/// information that's legitimately hidden even in a casual game.
public struct BotHUDRow: View {
    public let state: GameState

    public init(state: GameState) {
        self.state = state
    }

    private let human = PlayerID(index: 0)

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(state.players.filter { $0.id != human }, id: \.id) { player in
                PlayerChip.body(for: player, state: state, isHuman: false)
            }
        }
    }
}

/// Spacious bottom panel showing the human's full standing - name, VP/road/
/// army tags, a prominent per-resource dot breakdown, and (since dev cards
/// no longer get their own menu/button) a row of playable dev-card tiles
/// right alongside the resources - tapping one calls `onTapDevCard` so
/// `GameView` can open `DevCardPopupView` for it.
public struct HumanPlayerPanel: View {
    public let state: GameState
    public let onTapDevCard: (DevCardType) -> Void

    public init(state: GameState, onTapDevCard: @escaping (DevCardType) -> Void) {
        self.state = state
        self.onTapDevCard = onTapDevCard
    }

    private let human = PlayerID(index: 0)

    /// Held dev card types (with count + "new"/unplayable-this-turn count),
    /// in a fixed display order - mirrors the old `DevCardPanelView.rows`.
    private var devCardRows: [(type: DevCardType, held: Int, new: Int)] {
        guard let player = state.players.first(where: { $0.id == human }) else { return [] }
        let boughtThisTurn = state.devCardsBoughtThisTurn[human] ?? []
        return [DevCardType.knight, .roadBuilding, .yearOfPlenty, .monopoly, .victoryPoint].compactMap { type in
            let held = player.devCards.filter { $0 == type }.count
            guard held > 0 else { return nil }
            let new = boughtThisTurn.filter { $0 == type }.count
            return (type, held, new)
        }
    }

    public var body: some View {
        if let player = state.players.first(where: { $0.id == human }) {
            let isActive = PlayerChip.isActivePlayer(human, in: state)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(CatanTheme.color(for: human))
                        .frame(width: 14, height: 14)
                    Text("You")
                        .font(.headline)
                    Spacer()
                    PlayerChip.tag(text: "\(state.victoryPoints(for: human)) VP", icon: "star.fill", tint: .yellow)
                    if state.longestRoadPlayer == human {
                        PlayerChip.tag(text: "Longest Road", icon: "road.lanes", tint: .orange)
                    }
                    if state.largestArmyPlayer == human {
                        PlayerChip.tag(text: "Largest Army", icon: "shield.fill", tint: .red)
                    }
                }

                HStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 10) {
                        ForEach(Resource.allCases, id: \.self) { resource in
                            let count = player.resources[resource] ?? 0
                            VStack(spacing: 2) {
                                Circle()
                                    .fill(CatanTheme.color(for: resource))
                                    .frame(width: 16, height: 16)
                                Text("\(count)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(CatanTheme.onWaterText)
                            }
                            .opacity(count > 0 ? 1 : 0.35)
                        }
                    }

                    if !devCardRows.isEmpty {
                        Divider()
                            .frame(height: 30)
                            .overlay(Color.white.opacity(0.25))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(devCardRows, id: \.type) { row in
                                    let isPlayable = row.type != .victoryPoint
                                        && DevCards.canPlay(row.type, by: human, in: state)
                                    DevCardHUDTile(type: row.type, held: row.held, new: row.new, isPlayable: isPlayable) {
                                        onTapDevCard(row.type)
                                    }
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? CatanTheme.hudChipBackgroundActive : CatanTheme.hudChipBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isActive ? CatanTheme.color(for: human) : .clear, lineWidth: 2)
            )
        }
    }
}

/// HUD-scale dev card tile - a shrunk version of the old `DevCardPanelView`
/// card, small enough to sit inline next to the resource dots. Tappable
/// only while `isPlayable` (mirrors `DevCards.canPlay`, with Victory Point
/// cards always excluded since they're never played).
private struct DevCardHUDTile: View {
    let type: DevCardType
    let held: Int
    let new: Int
    let isPlayable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.callout)
                Text("x\(held)")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(width: 34, height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(color.gradient))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.4), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if new > 0 {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 8, height: 8)
                        .offset(x: 2, y: -2)
                }
            }
        }
        .disabled(!isPlayable)
        .opacity(isPlayable ? 1 : 0.5)
    }

    private var icon: String {
        switch type {
        case .knight: return "shield.fill"
        case .roadBuilding: return "road.lanes"
        case .yearOfPlenty: return "sparkles"
        case .monopoly: return "crown.fill"
        case .victoryPoint: return "star.fill"
        }
    }

    private var color: Color {
        switch type {
        case .knight: return .red
        case .roadBuilding: return .brown
        case .yearOfPlenty: return .green
        case .monopoly: return .purple
        case .victoryPoint: return Color(red: 0.85, green: 0.65, blue: 0.1)
        }
    }
}

/// Shared chip rendering + active-player logic used by `BotHUDRow` (and, for
/// its tag pills, `HumanPlayerPanel`).
@MainActor
enum PlayerChip {
    @ViewBuilder
    static func body(for player: Player, state: GameState, isHuman: Bool) -> some View {
        let isActive = isActivePlayer(player.id, in: state)
        let handSize = player.resources.values.reduce(0, +)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(CatanTheme.color(for: player.id))
                    .frame(width: 10, height: 10)
                Text(isHuman ? "You" : personalityLabel(for: player.id))
                    .font(.caption.bold())
                    .lineLimit(1)
            }

            // Short labels ("Road"/"Army" rather than "Longest Road"/"Largest
            // Army") so a tag stays legible inside a chip that's only
            // ~110pt wide at 3-across - the icon plus a one-word label is
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

            HStack(spacing: 10) {
                // Opponents' specific resources are hidden information in
                // real Catan - only the *count* of cards they're holding is
                // public knowledge, so bot chips show a hand-size badge
                // rather than the per-resource-type breakdown `HumanPlayerPanel`
                // shows for your own hand.
                HStack(spacing: 4) {
                    Image(systemName: "hand.raised.fill")
                        .font(.caption2)
                    Text("\(handSize) cards")
                        .font(.caption2.bold())
                }
                HStack(spacing: 4) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.caption2)
                    Text("\(player.devCards.count) dev")
                        .font(.caption2.bold())
                }
            }
            .foregroundStyle(CatanTheme.onWaterText)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? CatanTheme.hudChipBackgroundActive : CatanTheme.hudChipBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isActive ? CatanTheme.color(for: player.id) : .clear, lineWidth: 2)
        )
    }

    /// Small labeled pill - icon + short text - used for the VP/longest-road/
    /// largest-army indicators so they read as a single family of tags
    /// rather than a bare icon the viewer has to already know how to decode.
    static func tag(text: String, icon: String, tint: Color) -> some View {
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

    static func isActivePlayer(_ id: PlayerID, in state: GameState) -> Bool {
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
    static func personalityLabel(for id: PlayerID) -> String {
        switch id.index {
        case 1: return "Bot (Balanced)"
        case 2: return "Bot (Aggressive)"
        case 3: return "Bot (Cautious)"
        default: return "Bot"
        }
    }
}

#Preview {
    VStack {
        BotHUDRow(state: GameSetup.newGame(board: BoardGenerator.standard()))
        HumanPlayerPanel(state: GameSetup.newGame(board: BoardGenerator.standard()), onTapDevCard: { _ in })
    }
    .padding()
    .background(Color.black)
}
