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

            // Eased back open a little from the aggressive first trim, now
            // that the board's actual size is settled - that pass went
            // straight for the smallest sizes that still fit everything,
            // which read as cramped rather than just compact. This is a
            // middle ground: still noticeably smaller than the original,
            // but with room to breathe. `ScrollView`/`.fixedSize()`
            // everywhere below still guarantee nothing clips regardless of
            // how much content shows up (dev cards, both bonus tags, etc.)
            // - that's handled by structure, not by staying tiny.
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(CatanTheme.color(for: human))
                        .frame(width: 15, height: 15)
                    // `.lineLimit(1)` + `.fixedSize()` - without these,
                    // "You" and the civilization name (e.g. "Japan") were
                    // the ones that gave way when the row got crowded,
                    // wrapping mid-word onto a second line instead of
                    // staying put.
                    Text("You")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .lineLimit(1)
                        .fixedSize()
                    Image(systemName: Civilization.forSeat(human.index).emblemSymbol)
                        .font(.subheadline)
                        .foregroundStyle(CatanTheme.onWaterText.opacity(0.8))
                    Text(Civilization.forSeat(human.index).displayName)
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(CatanTheme.onWaterText.opacity(0.8))
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 0)
                }

                // Roads built (well, longest stretch - see below), knights
                // played, and VP are all public information in real Catan
                // (roads sit visibly on the board; a knight has to be
                // played face-up to move the robber). Its own horizontally
                // scrolling row, separate from the identity row above -
                // these badges plus the longest-road/largest-army tags
                // (each `.fixedSize()`, so none of them ever wrap) could
                // add up to more than the screen's width, and packed into
                // the identity row above (which also has "You"/the
                // civilization name protected the same way) that meant
                // something had to run off the right edge with no way to
                // reach it - exactly what happened once both bonus tags
                // were showing at once. A dedicated scrollable row can
                // never clip anything, it just becomes swipeable on the
                // rare hand that needs it.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        // Total resource-card count, at a glance, without
                        // having to add up the 5 individual dots below -
                        // same card-stack glyph the bot chips use for the
                        // same number.
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.stack.fill")
                            Text("\(player.resources.values.reduce(0, +))")
                        }
                        .font(.subheadline.bold())
                        .fixedSize()
                        // Longest continuous stretch (what the 2VP bonus is
                        // actually based on), not total segments built - a
                        // forked network can have far more segments than
                        // its longest single run.
                        HStack(spacing: 4) {
                            Image(systemName: "road.lanes")
                            Text("\(LongestRoad.length(for: player, in: state))")
                        }
                        .font(.subheadline.bold())
                        .fixedSize()
                        HStack(spacing: 4) {
                            Image(systemName: "shield.fill")
                            Text("\(player.playedKnights)")
                        }
                        .font(.subheadline.bold())
                        .fixedSize()
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                            Text("\(state.victoryPoints(for: human)) VP")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.85), in: Capsule())
                        .fixedSize()
                        if state.longestRoadPlayer == human {
                            PlayerChip.miniBadge(icon: "road.lanes", tint: .orange)
                        }
                        if state.largestArmyPlayer == human {
                            PlayerChip.miniBadge(icon: "shield.fill", tint: .red)
                        }
                    }
                }

                // `.top` rather than `.center`: dev card tiles (56pt tall)
                // and the resource dots (~43pt tall) have different
                // intrinsic heights, so centering them against each other
                // shifted the resource row up/down depending on whether any
                // dev cards were held - pinning both to the top keeps the
                // resource row's position stable regardless.
                HStack(alignment: .top, spacing: 10) {
                    // `.fixedSize()` here too (same reason as the roads/
                    // knights/VP row above): without it, once the dev-card
                    // `ScrollView` next to it wanted more room than was
                    // available, this HStack was the one that gave way -
                    // it has nothing else protecting its size - and got
                    // squeezed until resources on the right (grain, wool)
                    // ran past the panel's edge and off-screen entirely,
                    // not just visually compressed. The `ScrollView` is the
                    // one actually meant to give way here (it already
                    // scrolls for overflow); resources should always show
                    // in full.
                    HStack(spacing: 13) {
                        ForEach(Resource.allCases, id: \.self) { resource in
                            let count = player.resources[resource] ?? 0
                            VStack(spacing: 3) {
                                Circle()
                                    .fill(CatanTheme.color(for: resource))
                                    .frame(width: 18, height: 18)
                                Text("\(count)")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(CatanTheme.onWaterText)
                            }
                            .opacity(count > 0 ? 1 : 0.35)
                        }
                    }
                    .fixedSize()

                    if !devCardRows.isEmpty {
                        Divider()
                            .frame(height: 34)
                            .overlay(Color.white.opacity(0.25))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(devCardRows, id: \.type) { row in
                                    // `DevCards.canPlay` only checks
                                    // ownership, not phase - a dev card
                                    // (knight included) is only actually
                                    // playable during your own `.mainTurn`,
                                    // i.e. after rolling. Without this
                                    // check the tile looked tappable before
                                    // rolling too, and for Knight
                                    // specifically that let you walk
                                    // through the whole "move the robber"
                                    // flow before the engine's own phase
                                    // guard ever got a chance to reject it -
                                    // the other three dev cards apply
                                    // immediately on tap and so at least
                                    // surfaced an error, which is why this
                                    // read as "only Knight can be played
                                    // before rolling" rather than "none of
                                    // them actually can".
                                    let isMainTurn: Bool = {
                                        if case .mainTurn(let idx) = state.phase { return idx == human.index }
                                        return false
                                    }()
                                    let isPlayable = row.type != .victoryPoint
                                        && isMainTurn
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
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? CatanTheme.hudChipBackgroundActive : CatanTheme.hudChipBackground)
            )
            .overlay(
                // Same treatment as the bot chips (`PlayerChip.body`):
                // always outlined in your own piece color, just a heavier
                // line while it's your turn rather than the only time a
                // border shows at all.
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(CatanTheme.color(for: human), lineWidth: isActive ? 2.5 : 1.25)
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
            // Kept in step with the resource-dot row next to it (~38pt: an
            // 18pt circle + a bold 14pt count) - a taller tile row than its
            // neighbor visibly grows the whole panel the instant a dev
            // card first appears.
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.footnote)
                Text(name)
                    .font(.system(size: 8, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("x\(held)")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(width: 44, height: 38)
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
                // Fixed size, no `minimumScaleFactor` - that let each name
                // shrink independently to fit the same chip width, so
                // "Ragnar" (6 characters) stayed near full size while
                // "Charlemagne" (11) shrank dramatically to fit, and the
                // three bot names never actually matched each other. A
                // consistent size for everyone, truncating with an ellipsis
                // in the rare case a name still doesn't fit, reads far more
                // uniform than every name being a different size.
                Text(isHuman ? "You" : civilization.generalName)
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .lineLimit(1)
            }
            Text(civilization.displayName)
                .font(.system(size: 10, design: .serif))
                .foregroundStyle(CatanTheme.onWaterText.opacity(0.8))

            // Longest Road/Largest Army used to spell themselves out
            // ("Road"/"Army") as their own `tag()` pills, each stacked on
            // its own row below the VP pill - between the two, that could
            // grow a chip three rows tall. Now that they're bare
            // `miniBadge` dots (a fixed 16pt each, no text to negotiate
            // width for), all three fit on one row without risking the
            // "wider than this chip's fair share" problem the stacking used
            // to guard against, so the chip stays a consistent height
            // whether a bot holds zero, one, or both bonuses.
            HStack(spacing: 4) {
                // Bots' VP badge only counts what's actually public
                // (buildings + longest road/largest army) - a held but
                // unplayed Victory Point dev card is hidden information in
                // real Catan too, same as which specific cards make up
                // their hand, so it shouldn't silently show up in their
                // total before they'd ever reveal it.
                tag(text: "\(publicVictoryPoints(for: player, state: state)) VP", icon: "star.fill", tint: .yellow)
                if state.longestRoadPlayer == player.id {
                    miniBadge(icon: "road.lanes", tint: .orange)
                }
                if state.largestArmyPlayer == player.id {
                    miniBadge(icon: "shield.fill", tint: .red)
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
                    // A card-stack glyph rather than a raised-hand one - a
                    // stack of cards reads immediately as "how many
                    // resource cards this player is holding", where the
                    // hand icon needed a beat to parse.
                    statBadge(icon: "rectangle.stack.fill", value: handSize)
                    statBadge(icon: "sparkles.rectangle.stack.fill", value: player.devCards.count)
                }
                HStack(spacing: 10) {
                    // Longest continuous stretch, not total segments built -
                    // see HumanPlayerPanel's matching stat for why.
                    statBadge(icon: "road.lanes", value: LongestRoad.length(for: player, in: state))
                    statBadge(icon: "shield.fill", value: player.playedKnights)
                }
            }
            .foregroundStyle(CatanTheme.onWaterText)
        }
        // Trimmed twice now (108/12 -> 98/10 -> this) - the board needs
        // more room than this chip does, and it had slack to give up both
        // times.
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? CatanTheme.hudChipBackgroundActive : CatanTheme.hudChipBackground)
        )
        .overlay(
            // Always outlined in the seat's own color now, not just while
            // active - that color is already how every piece of theirs on
            // the board reads as belonging to them, so the chip should say
            // the same thing at a glance even on someone else's turn. Active
            // still gets called out, just by a heavier line rather than by
            // being the only one with a border at all.
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(CatanTheme.color(for: player.id), lineWidth: isActive ? 2.5 : 1.25)
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

    /// A little colored dot carrying just the bonus's icon, no spelled-out
    /// label - used for Longest Road/Largest Army instead of `tag()`'s full
    /// text pill. There are only two possible dots (road/army) and their
    /// tint alone already distinguishes them from the VP pill and each
    /// other, so the label was pure width with no added clarity; dropping it
    /// keeps these from competing for space with everything else in the row
    /// they sit in.
    static func miniBadge(icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(tint.opacity(0.85), in: Circle())
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
