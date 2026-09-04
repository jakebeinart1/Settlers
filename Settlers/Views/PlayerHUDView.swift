import SwiftUI
import CatanEngine

/// Top HUD strip: one compact chip per **bot** player (the human gets their
/// own, more spacious panel at the bottom of the screen - see
/// `HumanPlayerPanel`) showing name/personality, hand size, development-card
/// count, and victory-point/longest-road/largest-army tags.
///
/// **An opponent's chip shows only what is public in real Catan**: how many
/// cards they hold, not which; public victory points, so an unplayed VP card
/// stays hidden; roads, which are visible on the board; and played knights,
/// which are played face-up. `PlayerChip`'s own comments spell each out. Only
/// `HumanPlayerPanel` shows a per-resource breakdown, and only for its owner.
///
/// This doc previously said the opposite - "every player's resource hand is
/// shown in full", described as a deliberate simplification. That has not been
/// true for some time; the code below it was already correct. It mattered
/// enough to fix because it is exactly the claim someone would rely on when
/// deciding how much work hiding a second human's hand would be.
public struct BotHUDRow: View {
    public let state: GameState
    public let human: PlayerID
    public let playerIdentity: (PlayerID) -> PlayerIdentity

    public init(state: GameState, human: PlayerID,
                playerIdentity: @escaping (PlayerID) -> PlayerIdentity = CatanTheme.playerIdentity) {
        self.state = state
        self.human = human
        self.playerIdentity = playerIdentity
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.seatsShownAsOpponents(in: state, deviceSeat: human), id: \.id) { player in
                PlayerChip.body(for: player, state: state, playerIdentity: playerIdentity)
            }
        }
    }

    /// Seats rendered as opponent chips - hand SIZE, public victory points,
    /// roads and played knights, never the per-resource breakdown.
    ///
    /// Extracted from `body` so it can be tested. It is the app's entire
    /// hidden-information boundary, and the test that covered it was vacuous:
    /// it filtered the device seat out of a list and then asserted the list did
    /// not contain it. An audit demonstrated that three mutations destroying
    /// hand-hiding left the whole suite green.
    public static func seatsShownAsOpponents(in state: GameState, deviceSeat: PlayerID) -> [Player] {
        state.players.filter { $0.id != deviceSeat }
    }

    /// Seats whose full per-resource hand is drawn. **Exactly one**, always:
    /// whoever is holding the phone. Anything else is a hidden-information
    /// leak, and it is silent - nothing throws, nothing logs, one person just
    /// sees another person's cards.
    public static func seatsShowingFullHand(in state: GameState, deviceSeat: PlayerID) -> Set<PlayerID> {
        let opponents = Set(seatsShownAsOpponents(in: state, deviceSeat: deviceSeat).map(\.id))
        return Set(state.players.map(\.id)).subtracting(opponents)
    }
}

/// Spacious bottom panel showing the human's full standing - name, VP/road/
/// army tags, a prominent per-resource dot breakdown, and (since dev cards
/// no longer get their own menu/button) a row of playable dev-card tiles
/// right alongside the resources - tapping one calls `onTapDevCard` so
/// `GameView` can open `DevCardPopupView` for it.
public struct HumanPlayerPanel: View {
    public let state: GameState
    public let human: PlayerID
    public let playerIdentity: (PlayerID) -> PlayerIdentity
    public let onTapDevCard: (DevCardType) -> Void

    public init(state: GameState, human: PlayerID,
                playerIdentity: @escaping (PlayerID) -> PlayerIdentity = CatanTheme.playerIdentity,
                onTapDevCard: @escaping (DevCardType) -> Void) {
        self.state = state
        self.human = human
        self.playerIdentity = playerIdentity
        self.onTapDevCard = onTapDevCard
    }

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
            let identity = playerIdentity(human)

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
                    CivilizationCrest(civilization: identity.civilization, size: 30)
                    // `.lineLimit(1)` + `.fixedSize()` - without these,
                    // this and the civilization name (e.g. "Japan") were
                    // the ones that gave way when the row got crowded,
                    // wrapping mid-word onto a second line instead of
                    // staying put. The match identity rather than a literal
                    // "You" supports hot-seat names and durable snapshots.
                    Text(identity.displayName)
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .lineLimit(1)
                        .fixedSize()
                    Text(identity.civilization.displayName)
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
                    if devCardRows.isEmpty {
                        // No dev cards to share the row with, so the 5
                        // resource dots are the row's only content - tight
                        // fixed spacing left them bunched at the leading
                        // edge with the rest of the panel's width sitting
                        // empty. Stretching each dot into its own equal-width
                        // flexible column (matching the bot chips' stat-badge
                        // fix) technically filled the width, but blew the
                        // group apart into 5 disconnected icons scattered
                        // edge to edge - it read worse, not better. Centering
                        // the whole cluster instead put it back together, but
                        // sat oddly disconnected from the left-aligned name/
                        // VP rows above it - wider spacing keeps it as one
                        // still-grouped hand of cards, left-aligned like
                        // everything else in the panel.
                        HStack(spacing: 22) {
                            ForEach(Resource.allCases, id: \.self) { resource in
                                resourceDot(resource, count: player.resources[resource] ?? 0)
                            }
                        }
                        .padding(.leading, 6)
                    } else {
                        // `.fixedSize()` here (same reason as the roads/
                        // knights/VP row above): without it, once the dev-card
                        // `ScrollView` next to it wanted more room than was
                        // available, this HStack was the one that gave way -
                        // it has nothing else protecting its size - and got
                        // squeezed until resources on the right (grain, wool)
                        // ran past the panel's edge and off-screen entirely,
                        // not just visually compressed. The `ScrollView` is
                        // the one actually meant to give way here (it already
                        // scrolls for overflow); resources should always show
                        // in full. Once there's a dev-card row to share space
                        // with, the resource dots go back to their natural
                        // tight spacing rather than spreading out - stretching
                        // them here would just shove the dev cards further
                        // right for no benefit.
                        HStack(spacing: 13) {
                            ForEach(Resource.allCases, id: \.self) { resource in
                                resourceDot(resource, count: player.resources[resource] ?? 0)
                            }
                        }
                        .padding(.leading, 6)
                        .fixedSize()
                    }

                    if !devCardRows.isEmpty {
                        Divider()
                            .frame(height: 34)
                            .overlay(Color.white.opacity(0.25))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(devCardRows, id: \.type) { row in
                                    // `DevCards.canPlay` only checks
                                    // ownership, not phase - a dev card is
                                    // only actually playable during your own
                                    // turn, and (per the official rules)
                                    // Knight is the one card that's playable
                                    // before rolling too - the other three
                                    // only during `.mainTurn`, after the
                                    // roll. Without a phase check here the
                                    // tile looked tappable at other times as
                                    // well, and for Knight specifically that
                                    // let you walk through the whole "move
                                    // the robber" flow before the engine's
                                    // own phase guard ever got a chance to
                                    // reject it - the other three dev cards
                                    // apply immediately on tap and so at
                                    // least surfaced an error, which is why
                                    // this read as "only Knight can be
                                    // played at the wrong time" rather than
                                    // "none of them actually can".
                                    // A knight may also be played before the
                                    // roll, which is the one thing that stops
                                    // this being a plain `isMainTurn(of:)`.
                                    let isMyTurnToPlay: Bool = {
                                        if state.phase.isMainTurn(of: human.index) { return true }
                                        if case .rollDice(let idx) = state.phase {
                                            return row.type == .knight && idx == human.index
                                        }
                                        return false
                                    }()
                                    let isPlayable = row.type != .victoryPoint
                                        && isMyTurnToPlay
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
            .background(TintedTextureBackground(tint: identity.civilization.cardBackgroundColor(active: isActive)))
            .overlay(alignment: .bottomTrailing) {
                // A specialized watermark just for the human's own panel -
                // a small painted silhouette (mountains + pagodas, matching
                // the board background's own style) tucked bottom-trailing
                // in the panel's own empty margin (below the left-aligned
                // content), the way the reference's player card carries its
                // own bit of scenery instead of a flat color. Bot chips
                // don't get this - they're small, share a row, and change
                // occupant (civ) every game, where a baked scenic image
                // would either look cramped or need per-civ variants; this
                // one card is always "you" and has the room for it.
                Image("human-card-motif")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .opacity(0.45)
                    .allowsHitTesting(false)
            }
            .clipShape(FrameCornerRect(cornerRadius: 12, notchScale: 1.0))
            .playerCardBorder(
                // Same treatment as the bot chips (`PlayerChip.body`):
                // always outlined in your own piece color, just a heavier
                // line while it's your turn rather than the only time a
                // border shows at all.
                color: identity.civilization.accentColor,
                cornerRadius: 12,
                lineWidth: isActive ? 3.25 : 2.5
            )
        }
    }

    /// One resource's colored square + held count, dimmed when `count` is 0
    /// - factored out so both the spread-out (no dev cards) and tight (dev
    /// cards present) layouts above render identical squares. A rounded
    /// square rather than a circle - matches the resource swatches in
    /// `MainMenuView`'s title block, per Jake's ask to keep the same shape
    /// language on the board's own resource counts instead of a dot.
    private func resourceDot(_ resource: Resource, count: Int) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3)
                .fill(CatanTheme.color(for: resource))
                .frame(width: 18, height: 18)
            Text("\(count)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CatanTheme.onWaterText)
        }
        .opacity(count > 0 ? 1 : 0.35)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(resource.rawValue.capitalized) cards")
        .accessibilityValue("\(count)")
        .accessibilityIdentifier(AccessibilityID.Game.humanResource(resource))
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

    // Shared with `DevCardPopupView` via `DevCardStyle` - these were three
    // byte-identical switches in both files, so a card could have been one
    // colour in this strip and another in the popup the strip opens.
    private var icon: String { DevCardStyle.icon(for: type) }
    private var name: String { DevCardStyle.shortName(for: type) }
    private var color: Color { DevCardStyle.color(for: type) }
}

/// Shared chip rendering + active-player logic used by `BotHUDRow` (and, for
/// its tag pills, `HumanPlayerPanel`).
@MainActor
enum PlayerChip {
    @ViewBuilder
    static func body(for player: Player, state: GameState,
                     playerIdentity: (PlayerID) -> PlayerIdentity) -> some View {
        let isActive = isActivePlayer(player.id, in: state)
        let handSize = player.resources.values.reduce(0, +)
        let identity = playerIdentity(player.id)
        let civilization = identity.civilization

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                CivilizationCrest(civilization: civilization, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    // The resolved match identity, never a hardcoded general
                    // name. The civilization sits in this same crest row so
                    // replacing the old 10pt SF Symbol with real piece art
                    // does not make the HUD taller or shrink the board.
                    Text(identity.displayName)
                        .font(.system(size: 10, weight: .bold, design: .serif))
                        .lineLimit(1)
                    Text(civilization.displayName)
                        .font(.system(size: 10, design: .serif))
                        .foregroundStyle(CatanTheme.onWaterText.opacity(0.8))
                        .lineLimit(1)
                }
            }

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
                tag(text: "\(state.publicVictoryPoints(for: player.id)) VP", icon: "star.fill", tint: .yellow)
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
            // across ran wider than this chip. Each row's pair used to just
            // sit at fixed spacing on the left, which (since neither the
            // chip's own width nor this VStack's is driven by these two
            // short badges) left a slab of dead space down the right side
            // of every chip. A plain trailing `Spacer` fixed that but
            // overcorrected - it snapped the second badge all the way to
            // the chip's far edge, leaving a single lopsided gap in the
            // middle instead of even spacing. Giving each badge an equal-
            // width `.frame(maxWidth: .infinity, alignment: .leading)`
            // column instead reads as one consistent two-column grid: the
            // second badge starts right at the row's midpoint every time,
            // in both rows, rather than wherever its own icon+number
            // happens to end.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    // A card-stack glyph rather than a raised-hand one - a
                    // stack of cards reads immediately as "how many
                    // resource cards this player is holding", where the
                    // hand icon needed a beat to parse.
                    statBadge(icon: "rectangle.stack.fill", value: handSize)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    statBadge(icon: "sparkles.rectangle.stack.fill", value: player.devCards.count)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 0) {
                    // Longest continuous stretch, not total segments built -
                    // see HumanPlayerPanel's matching stat for why.
                    statBadge(icon: "road.lanes", value: LongestRoad.length(for: player, in: state))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    statBadge(icon: "shield.fill", value: player.playedKnights)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(CatanTheme.onWaterText)
        }
        // Trimmed twice now (108/12 -> 98/10 -> this) - the board needs
        // more room than this chip does, and it had slack to give up both
        // times.
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(TintedTextureBackground(tint: civilization.cardBackgroundColor(active: isActive)))
        .clipShape(FrameCornerRect(cornerRadius: 12, notchScale: 1.0))
        .playerCardBorder(
            // Always outlined in the seat's own color now, not just while
            // active - that color is already how every piece of theirs on
            // the board reads as belonging to them, so the chip should say
            // the same thing at a glance even on someone else's turn. Active
            // still gets called out, just by a heavier line rather than by
            // being the only one with a border at all.
            color: civilization.accentColor,
            cornerRadius: 12,
            lineWidth: isActive ? 3.25 : 2.5
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

    static func isActivePlayer(_ id: PlayerID, in state: GameState) -> Bool {
        // See `GamePhase.awaitingSeatIndex` - this was a byte-for-byte copy of
        // the switch it replaces.
        if let seat = state.phase.awaitingSeatIndex { return PlayerID(index: seat) == id }
        // The only phase where more than one seat is active at once.
        if case .discarding(let pending) = state.phase { return pending.contains(id) }
        return false
    }

}

#Preview {
    VStack {
        BotHUDRow(state: GameSetup.newGame(board: BoardGenerator.standard()), human: PlayerID(index: 0))
        HumanPlayerPanel(state: GameSetup.newGame(board: BoardGenerator.standard()), human: PlayerID(index: 0), onTapDevCard: { _ in })
    }
    .padding()
    .background(Color.black)
}
