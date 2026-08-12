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

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(CatanTheme.color(for: human))
                        .frame(width: 17, height: 17)
                    Text("You")
                        .font(.system(size: 21, weight: .bold, design: .serif))
                    Image(systemName: Civilization.forSeat(human.index).emblemSymbol)
                        .font(.subheadline)
                        .foregroundStyle(CatanTheme.onWaterText.opacity(0.8))
                    Text(Civilization.forSeat(human.index).displayName)
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(CatanTheme.onWaterText.opacity(0.8))
                    Spacer()
                    // Roads built, knights played, and VP are all public
                    // information in real Catan (roads sit visibly on the
                    // board; a knight has to be played face-up to move the
                    // robber) - sized up from the bot chips' compact stats,
                    // since this is your own panel and has the room for it.
                    HStack(spacing: 4) {
                        Image(systemName: "road.lanes")
                        Text("\(player.roads.count)")
                    }
                    .font(.subheadline.bold())
                    HStack(spacing: 4) {
                        Image(systemName: "shield.fill")
                        Text("\(player.playedKnights)")
                    }
                    .font(.subheadline.bold())
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                        Text("\(state.victoryPoints(for: human)) VP")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.85), in: Capsule())
                    if state.longestRoadPlayer == human {
                        PlayerChip.tag(text: "Longest Road", icon: "road.lanes", tint: .orange)
                    }
                    if state.largestArmyPlayer == human {
                        PlayerChip.tag(text: "Largest Army", icon: "shield.fill", tint: .red)
                    }
                }

                // `.top` rather than `.center`: dev card tiles (56pt tall)
                // and the resource dots (~43pt tall) have different
                // intrinsic heights, so centering them against each other
                // shifted the resource row up/down depending on whether any
                // dev cards were held - pinning both to the top keeps the
                // resource row's position stable regardless.
                HStack(alignment: .top, spacing: 16) {
                    HStack(spacing: 14) {
                        ForEach(Resource.allCases, id: \.self) { resource in
                            let count = player.resources[resource] ?? 0
                            VStack(spacing: 3) {
                                Circle()
                                    .fill(CatanTheme.color(for: resource))
                                    .frame(width: 20, height: 20)
                                Text("\(count)")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(CatanTheme.onWaterText)
                            }
                            .opacity(count > 0 ? 1 : 0.35)
                        }
                    }

                    if !devCardRows.isEmpty {
                        Divider()
                            .frame(height: 38)
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
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? CatanTheme.hudChipBackgroundActive : CatanTheme.hudChipBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isActive ? CatanTheme.color(for: human) : .clear, lineWidth: 2)
            )
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: PlayerFrameKey.self, value: [human: geo.frame(in: .named("game"))])
                }
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
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.title3)
                Text(name)
                    .font(.system(size: 9.5, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("x\(held)")
                    .font(.system(size: 11.5, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(width: 58, height: 56)
            .background(RoundedRectangle(cornerRadius: 9).fill(color.gradient))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.4), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if new > 0 {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 9, height: 9)
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

    private var name: String {
        switch type {
        case .knight: return "Knight"
        case .roadBuilding: return "Road"
        case .yearOfPlenty: return "Plenty"
        case .monopoly: return "Monopoly"
        case .victoryPoint: return "VP"
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

        let civilization = Civilization.forSeat(player.id.index)

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle()
                    .fill(CatanTheme.color(for: player.id))
                    .frame(width: 11, height: 11)
                Image(systemName: civilization.emblemSymbol)
                    .font(.system(size: 10))
                Text(isHuman ? "You" : civilization.generalName)
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            Text(civilization.displayName)
                .font(.system(size: 10, design: .serif))
                .foregroundStyle(CatanTheme.onWaterText.opacity(0.8))

            // Short labels ("Road"/"Army" rather than "Longest Road"/"Largest
            // Army") so a tag stays legible inside a chip that's only
            // ~110pt wide at 3-across - the icon plus a one-word label is
            // still identifiable at a glance without wrapping.
            HStack(spacing: 4) {
                // Bots' VP badge only counts what's actually public
                // (buildings + longest road/largest army) - a held but
                // unplayed Victory Point dev card is hidden information in
                // real Catan too, same as which specific cards make up
                // their hand, so it shouldn't silently show up in their
                // total before they'd ever reveal it.
                tag(text: "\(publicVictoryPoints(for: player, state: state)) VP", icon: "star.fill", tint: .yellow)
                if state.longestRoadPlayer == player.id {
                    tag(text: "Road", icon: "road.lanes", tint: .orange)
                }
                if state.largestArmyPlayer == player.id {
                    tag(text: "Army", icon: "shield.fill", tint: .red)
                }
            }

            // Opponents' specific resources are hidden information in real
            // Catan - only the *count* of cards they're holding is public
            // knowledge, so bot chips show a hand-size badge rather than
            // the per-resource-type breakdown `HumanPlayerPanel` shows for
            // your own hand. Roads built and knights played are both fully
            // public in real Catan too (roads are visible on the board
            // itself, and knights have to be played face-up to move the
            // robber) - shown here as plain icon+count pairs, no word
            // labels. Two rows of two rather than one row of four: four
            // across ran wider than this ~110pt-wide chip and got clipped.
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    statBadge(icon: "hand.raised.fill", value: handSize)
                    statBadge(icon: "sparkles.rectangle.stack.fill", value: player.devCards.count)
                }
                HStack(spacing: 10) {
                    statBadge(icon: "road.lanes", value: player.roads.count)
                    statBadge(icon: "shield.fill", value: player.playedKnights)
                }
            }
            .foregroundStyle(CatanTheme.onWaterText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? CatanTheme.hudChipBackgroundActive : CatanTheme.hudChipBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isActive ? CatanTheme.color(for: player.id) : .clear, lineWidth: 2)
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: PlayerFrameKey.self, value: [player.id: geo.frame(in: .named("game"))])
            }
        )
    }

    /// Bare icon + number, no word label - for the compact public-stat row
    /// (hand size / dev cards / roads / knights played) where four of these
    /// need to fit across one narrow chip.
    static func statBadge(icon: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text("\(value)")
                .font(.caption.bold())
        }
    }

    /// Small labeled pill - icon + short text - used for the VP/longest-road/
    /// largest-army indicators so they read as a single family of tags
    /// rather than a bare icon the viewer has to already know how to decode.
    static func tag(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(tint.opacity(0.85), in: Capsule())
        .fixedSize()
    }

    /// VP that's actually public knowledge for `player`: buildings plus the
    /// longest-road/largest-army bonuses (all visible on the board/HUD
    /// already), deliberately excluding held-but-unplayed Victory Point dev
    /// cards - `GameState.victoryPoints(for:)` includes those, which is
    /// correct for `player`'s *own* total (shown in `HumanPlayerPanel`, who
    /// obviously knows their own hand) but would leak hidden information if
    /// shown for an opponent, same as which specific cards they're holding.
    static func publicVictoryPoints(for player: Player, state: GameState) -> Int {
        var total = player.settlements.count + player.cities.count * 2
        if state.longestRoadPlayer == player.id { total += 2 }
        if state.largestArmyPlayer == player.id { total += 2 }
        return total
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

}

#Preview {
    VStack {
        BotHUDRow(state: GameSetup.newGame(board: BoardGenerator.standard()))
        HumanPlayerPanel(state: GameSetup.newGame(board: BoardGenerator.standard()), onTapDevCard: { _ in })
    }
    .padding()
    .background(Color.black)
}
