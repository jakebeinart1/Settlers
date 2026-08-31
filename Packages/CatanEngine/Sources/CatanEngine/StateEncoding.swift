import Foundation

/// Two renderings of a `GameObservation` - a fixed-width numeric vector for a
/// trainer, and a compact text block for a language model - over one shared,
/// versioned layout.
///
/// ## Why both live in one file
/// They are two views of the same position, and the only thing that keeps them
/// two views of the *same* position is a layout written down once. Split across
/// two files they drift: a field added to the prose and not to the vector (or
/// the reverse) is invisible at compile time and surfaces much later as a model
/// that plays worse than its prompt suggests it should. Every board index
/// either rendering quotes comes from the same `BoardIndex`, so `v17` in the
/// text and vertex slot 17 in the vector are the same corner by construction
/// rather than by agreement.
///
/// ## What is deliberately NOT encoded, and why
/// - `GameState.rng`. A model able to read the generator would learn the dice
///   rather than the game, and nobody at a real table can see it.
/// - `GameState.devCardDeck`'s *contents* - only its size. Deck order is hidden
///   from every seat, `.revealAll` included; it is not the observer's secret to
///   reveal.
/// - `GameState.schemaVersion`. It describes a save file, not a position.
/// - `GameState.robberMoverIndex`. Transient bookkeeping that carries the
///   7-roller across an intervening `.discarding` phase; the phase itself names
///   the mover the moment it matters (`.movingRobber(playerIndex:)`).
///
/// ## Two move numberings exist, and they are not the same number
/// `promptDescription` numbers the moves **0-based within this observation's
/// own `legalMoves`** - typically single digits, and meaningless in any other
/// position. `ActionSpace` numbers moves **globally and permanently**, 0..<8815
/// on the standard board, where a given index means the same move forever.
///
/// The prompt uses the local numbering on purpose: asking a language model to
/// pick out of nine options beats asking it to name an index in a space of
/// 8,815, almost all of which is illegal at any moment. A trainer wants the
/// opposite - a fixed-width head where slot k always means the same thing - and
/// should use `ActionSpace` with `ActionSpace.mask(for:)`.
///
/// **Never feed a number from one into the other.** They are unrelated
/// integers that happen to share a type, which is exactly the kind of mistake
/// that produces a legal-looking move nobody chose. To cross over, decode the
/// prompt's number through `observation.legalMoves[n]` and then encode that
/// move with `ActionSpace.index(of:pendingOffers:)`.
///
/// Everything else in `GameState` reaches both renderings.
public enum StateEncoding {

    // MARK: - Layout version

    /// The version of the layout this file defines.
    ///
    /// ## Why a version marker rather than "just keep it in sync"
    /// A trained artifact - a policy network's weights, a fitted linear model,
    /// a set of few-shot prompt examples - is fitted against *one* arrangement
    /// of feature slots. Change the arrangement and the artifact reads the
    /// wrong number out of every slot after the first insertion point.
    ///
    /// The dangerous version of that failure is the silent one. Pad a
    /// 1012-wide model up to 1050, or truncate 1050 down to 1012, and
    /// everything still runs: no shape error, no exception, no crash. The model
    /// simply plays badly. "The bots got worse" is among the most expensive
    /// things to diagnose in this repo, because it looks exactly like a tuning
    /// problem and sends you sweeping weights for a week.
    ///
    /// **So anything that persists a trained artifact must record this number
    /// beside it and refuse to load on a mismatch.** Refusing is cheap;
    /// discovering afterwards that a month of self-play was fitted against a
    /// shifted layout is not.
    ///
    /// Bump it for any change to slot meaning, slot order or `featureCount`,
    /// and for any change to the *field set* `promptDescription` emits - a
    /// few-shot prompt built against the old shape stops matching. Purely
    /// cosmetic changes to separators or spacing do not need a bump.
    public static let layoutVersion = 1

    // MARK: - Board shape this layout is defined against

    // The layout is fixed-width, so it has to be fixed-width *against
    // something*. These are the standard 19-hex board `BoardGenerator`
    // produces, in both its `standard()` and `randomized(seed:)` forms.
    // A board of another size is not "mostly compatible" - it would silently
    // shift every slot after the first board block - so both renderings check
    // and trap rather than encode something a consumer would misread.

    public static let seatCount = 4
    public static let tileCount = 19
    public static let vertexCount = 54
    public static let edgeCount = 72
    /// One slot per `GamePhase` case, in `phaseSlot(_:)` order.
    public static let phaseCount = 7
    /// Width of every per-resource slot group. Read off the enum rather than
    /// written as 5, so a sixth resource cannot leave a block width behind -
    /// which would shift every slot after it while still compiling.
    public static let resourceKindCount = Resource.allCases.count
    /// Width of every per-dev-card slot group, for the same reason.
    public static let devCardKindCount = DevCardType.allCases.count

    // MARK: - Normalisation maxima
    //
    // Every count in the vector is divided by one of these and clamped to
    // 0...1. Raw counts train badly next to each other: 19 bank cards, 15
    // roads and 10 victory points are the same magnitude of "a lot" but three
    // different numbers, and a learner spends capacity discovering the scale
    // instead of the game.
    //
    // Where a true ceiling exists it is used (there are exactly 19 cards of
    // each resource in the box). Where the true ceiling is absurd - a hand can
    // in principle hold all 95 resource cards - a *soft* cap is used and the
    // value clamps, because dividing a typical 7-card hand by 95 wastes the
    // useful part of the range on positions that never occur.

    /// Cards of each resource in the box, and therefore the ceiling on both
    /// bank stock and any one player's holding of a single resource.
    public static let resourceCardsPerKind = 19
    /// Soft cap for total hand size. Above this the exact count stops mattering
    /// strategically - the 7-card discard rule already dominates - so clamping
    /// loses nothing a policy would have used.
    public static let handSizeSoftCap = 20
    /// Development cards in a full deck (14 knight + 5 VP + 2 + 2 + 2).
    public static let devCardDeckSize = 25
    /// Knights in the deck: the ceiling on both knights played and any single
    /// dev-card type held.
    public static let knightCardCount = 14
    /// Victory points needed to win, and therefore the VP normaliser. Mirrors
    /// the threshold in `WinCondition.checkForWinner`.
    public static let victoryPointTarget = 10
    /// Soft cap on dev cards bought in one turn. Buying more than this in a
    /// single turn needs 5+ of three resources and effectively never happens.
    public static let devCardsBoughtSoftCap = 5
    /// Soft cap on trades accepted from one proposer in a turn. `TradeHeuristics`
    /// already treats a proposer past two or three as suspicious, so the exact
    /// count above this carries no further signal.
    public static let tradesAcceptedSoftCap = 4
    /// Soft cap on simultaneously pending trade offers.
    public static let pendingTradeOfferSoftCap = 8
    /// Dice roll bounds, for mapping a roll onto 0...1.
    public static let minDiceRoll = 2
    public static let maxDiceRoll = 12
    /// Pips on the most productive number tokens (6 and 8), and therefore the
    /// normaliser for `DiceOdds.pips(for:)`.
    public static let maxPips = 5

    // MARK: - Layout block widths

    /// Slots for the last dice roll: its normalised value, and a flag saying
    /// whether there has been one at all. The flag is not redundant - without
    /// it "not rolled yet" and "rolled a 2" both encode as 0, and a learner
    /// cannot tell the start of a turn from a bad one.
    public static let diceFeatureCount = 2

    /// Global single-scalar slots: dev cards left in the deck, and pending
    /// trade offers.
    public static let globalScalarCount = 2

    /// Slots describing the position as a whole, before any per-seat block:
    /// phase one-hot, last roll, bank stock, the two scalars above, and a
    /// robber one-hot over the canonical tile order.
    public static let globalFeatureCount =
        phaseCount + diceFeatureCount + resourceKindCount + globalScalarCount + tileCount

    /// Holdings slots per seat: hand by resource (HIDDEN), hand size, unplayed
    /// dev cards by type (HIDDEN), unplayed dev card count, dev cards bought
    /// this turn, whether a dev card has been played this turn.
    public static let holdingsFeatureCount = resourceKindCount + 1 + devCardKindCount + 1 + 1 + 1

    /// Standing slots per seat: trades accepted this turn, public VP,
    /// settlements, cities, roads built, knights played, longest continuous
    /// road, holds longest road, holds largest army, is the seat to move, owes
    /// a discard.
    public static let standingFeatureCount = 11

    /// Port slots per seat: a generic 3:1 flag plus one 2:1 flag per resource.
    public static let portFeatureCount = 1 + resourceKindCount

    /// Slots per seat.
    public static let perPlayerFeatureCount =
        holdingsFeatureCount + standingFeatureCount + portFeatureCount

    /// Slots per board tile: resource one-hot, desert flag, pip probability.
    public static let perTileFeatureCount = resourceKindCount + 1 + 1

    /// Slots per board vertex: settlement + city flags for each seat, in
    /// egocentric seat order.
    public static let perVertexFeatureCount = 2 * seatCount

    /// Slots per board edge: road ownership for each seat, in egocentric seat
    /// order.
    public static let perEdgeFeatureCount = seatCount

    /// The length of every vector `features(_:)` returns, for every position,
    /// in every phase, forever - until `layoutVersion` changes.
    ///
    /// 1012 = 35 global + 4 x 31 per-seat + 19 x 7 per-tile
    ///      + 54 x 8 per-vertex + 72 x 4 per-edge.
    public static let featureCount =
        globalFeatureCount
        + seatCount * perPlayerFeatureCount
        + tileCount * perTileFeatureCount
        + vertexCount * perVertexFeatureCount
        + edgeCount * perEdgeFeatureCount

    // MARK: - Hidden information

    /// How much of a non-observing seat's private holdings the encoding shows.
    ///
    /// ## Why this exists as a switch rather than a rewrite
    /// Agents currently see everything, opponents' hands included. That is a
    /// recorded decision to defer (see `GameObservation`), not an oversight:
    /// hiding hands changes how strong the bots are and is worth doing on
    /// purpose. This enum is what makes taking that decision later a local
    /// change - both renderings read every hidden-information field through
    /// `holdings(of:seenBy:policy:)` and nowhere else, so flipping the default
    /// is the whole edit.
    ///
    /// Crucially `featureCount` is identical under both policies: concealed
    /// per-kind slots go to zero rather than disappearing. A model trained
    /// under `.revealAll` can therefore be evaluated under `.publicCountsOnly`
    /// without a width mismatch. It will play worse - it is being asked a
    /// question it was never trained on - but it will not silently misread the
    /// vector, which is the failure this file exists to prevent.
    public enum HiddenInformationPolicy: Sendable, Equatable {
        /// Everything is visible, including opponents' exact hands. Today's
        /// behaviour, unchanged.
        case revealAll
        /// Opponents' exact hands and dev cards are replaced by the counts a
        /// real player can see across the table.
        case publicCountsOnly
    }

    /// One seat's card holdings, split by what is public at a real table and
    /// what is not.
    ///
    /// The split is the point. `handSize` and `devCardCount` are public in real
    /// Catan - anyone can count the cards in an opponent's hand - while
    /// `resources` and `devCards` are not. Keeping them in one type with that
    /// distinction spelled out means a future consumer cannot accidentally
    /// treat the hidden half as public.
    public struct Holdings: Sendable {
        /// HIDDEN INFORMATION. Exact resource counts by kind. Empty when
        /// `isRevealed` is false.
        public let resources: [Resource: Int]
        /// HIDDEN INFORMATION. Unplayed development cards by type. Empty when
        /// `isRevealed` is false.
        public let devCards: [DevCardType: Int]
        /// PUBLIC. Total resource cards held - visible to everyone at the table
        /// whether or not the kinds are.
        public let handSize: Int
        /// PUBLIC. Number of unplayed development cards held. Visible because
        /// every purchase happens in the open.
        public let devCardCount: Int
        /// Whether `resources` and `devCards` carry true values. False means
        /// only the two public counts are meaningful.
        public let isRevealed: Bool
    }

    /// The holdings of `player` as `observer` is entitled to see them.
    ///
    /// The single choke point for hidden information in this file. Both
    /// renderings go through it, so changing what an opponent may see is a
    /// change here and nowhere else.
    public static func holdings(of player: Player,
                                seenBy observer: PlayerID,
                                policy: HiddenInformationPolicy = .revealAll) -> Holdings {
        var devByType: [DevCardType: Int] = [:]
        for card in player.devCards { devByType[card, default: 0] += 1 }
        // Summed over `Resource.allCases`, not over `player.resources` - the
        // dictionary's iteration order is seeded per process, and while an Int
        // sum is order-independent, driving every enumeration off `allCases`
        // is the habit that keeps the non-obvious cases (a Double sum, a
        // `.first`) from creeping in beside it.
        let handSize = Resource.allCases.reduce(0) { $0 + (player.resources[$1] ?? 0) }

        let concealed = policy == .publicCountsOnly && player.id != observer
        return Holdings(
            resources: concealed ? [:] : player.resources,
            devCards: concealed ? [:] : devByType,
            handSize: handSize,
            devCardCount: player.devCards.count,
            isRevealed: !concealed
        )
    }

    // MARK: - Canonical board ordering

    /// The sorted index space both renderings address the board through.
    ///
    /// ## Why this type exists at all
    /// `Board.onBoardVertices` and `Board.onBoardEdges` are `Set`s, and Swift
    /// seeds hash iteration order once per process. Walking them directly would
    /// give feature slot 400 a different meaning on every launch, which makes a
    /// saved model worthless in a way that produces no error - the vector is
    /// still the right width and still full of plausible numbers. This repo has
    /// been bitten by `Set` ordering four separate times already (see the
    /// determinism section of `CLAUDE.md`); this is the same defect aimed at a
    /// trained artifact instead of at a bot's tie-break.
    ///
    /// Tiles are sorted by coordinate rather than taken in `board.tiles` order
    /// for the same reason one step removed: the array order is deterministic
    /// today because `BoardGenerator` builds it from a fixed spiral, but a
    /// hand-assembled board would index differently, and "hex 7" should mean a
    /// physical location, not a construction order.
    public struct BoardIndex: Sendable {
        /// Tiles in ascending coordinate order.
        public let tiles: [Tile]
        /// Vertices in ascending `VertexID` order.
        public let vertices: [VertexID]
        /// Edges in ascending `EdgeID` order.
        public let edges: [EdgeID]

        private let tileSlots: [HexCoordinate: Int]
        private let vertexSlots: [VertexID: Int]
        private let edgeSlots: [EdgeID: Int]

        public init(_ board: Board) {
            tiles = board.tiles.sorted { $0.coordinate < $1.coordinate }
            vertices = board.onBoardVertices.sorted()
            edges = board.onBoardEdges.sorted()

            precondition(tiles.count == StateEncoding.tileCount,
                         "layout v\(StateEncoding.layoutVersion) is defined against \(StateEncoding.tileCount) tiles, got \(tiles.count)")
            precondition(vertices.count == StateEncoding.vertexCount,
                         "layout v\(StateEncoding.layoutVersion) is defined against \(StateEncoding.vertexCount) vertices, got \(vertices.count)")
            precondition(edges.count == StateEncoding.edgeCount,
                         "layout v\(StateEncoding.layoutVersion) is defined against \(StateEncoding.edgeCount) edges, got \(edges.count)")

            tileSlots = Dictionary(uniqueKeysWithValues: tiles.enumerated().map { ($0.element.coordinate, $0.offset) })
            vertexSlots = Dictionary(uniqueKeysWithValues: vertices.enumerated().map { ($0.element, $0.offset) })
            edgeSlots = Dictionary(uniqueKeysWithValues: edges.enumerated().map { ($0.element, $0.offset) })
        }

        /// The `h#` index of a tile. Traps rather than returning a sentinel: a
        /// coordinate that is not on this board is a bug in the caller, and a
        /// silently wrong slot is exactly the failure this type prevents.
        public func slot(of coordinate: HexCoordinate) -> Int {
            guard let slot = tileSlots[coordinate] else {
                preconditionFailure("hex \(coordinate) is not on this board")
            }
            return slot
        }

        /// The `v#` index of a vertex.
        public func slot(of vertex: VertexID) -> Int {
            guard let slot = vertexSlots[vertex] else {
                preconditionFailure("vertex \(vertex) is not on this board")
            }
            return slot
        }

        /// The `e#` index of an edge.
        public func slot(of edge: EdgeID) -> Int {
            guard let slot = edgeSlots[edge] else {
                preconditionFailure("edge \(edge) is not on this board")
            }
            return slot
        }
    }

    // MARK: - Shared layout helpers

    /// The seats in egocentric order: the observer first, then the rest in
    /// increasing seat order, wrapping around.
    ///
    /// ## Why egocentric rather than absolute
    /// If slot 35 meant "seat 0's brick" then a learner sitting in seat 2 has
    /// to find its own hand at a different offset than a learner in seat 0, and
    /// ends up learning "having brick is good" four separate times, once per
    /// seat, from a quarter of the data each. With this ordering slot 35 is
    /// always *my* brick and the seat I happen to occupy stops being a feature
    /// of the game. The same argument applies to the per-vertex and per-edge
    /// ownership blocks, which is why they use this order too.
    public static func seatOrder(from seat: PlayerID) -> [PlayerID] {
        (0..<seatCount).map { PlayerID(index: (seat.index + $0) % seatCount) }
    }

    /// The seats that actually exist in `state`, rotated so `seat` is first.
    ///
    /// A three-player game has no seat 3, and the fixed-width rotation above
    /// would name one - which `player(_:in:)` traps on. This returns only real
    /// seats; the fixed-width blocks are padded to `seatCount` with zeros by
    /// their callers.
    ///
    /// Padding rather than shrinking is deliberate. `featureCount` must mean
    /// the same thing in every position forever or a trained model reads the
    /// wrong number out of every slot after the first, silently - which is the
    /// whole argument for `layoutVersion`. An absent seat reading as all-zero
    /// is also exactly how a concealed seat already reads under
    /// `.publicCountsOnly`, so no new meaning is introduced.
    public static func seatOrder(from seat: PlayerID, in state: GameState) -> [PlayerID] {
        let present = state.players.count
        guard present > 0 else { return [] }
        return (0..<present).map { PlayerID(index: (seat.index + $0) % present) }
    }

    /// The one-hot slot for a phase. Fixed order; changing it is a
    /// `layoutVersion` bump.
    public static func phaseSlot(_ phase: GamePhase) -> Int {
        switch phase {
        case .setupForward: return 0
        case .setupBackward: return 1
        case .rollDice: return 2
        case .mainTurn: return 3
        case .discarding: return 4
        case .movingRobber: return 5
        case .gameOver: return 6
        }
    }

    /// The seat whose turn it is, or `nil` where no single seat owns the phase.
    ///
    /// `.discarding` is deliberately `nil`. Any pending seat may act, and which
    /// one goes first is `GameSession`'s scheduling choice rather than a
    /// property of the position - encoding it here would teach a learner an
    /// artifact of the driver. The per-seat "owes a discard" flag carries what
    /// an agent actually needs. `.gameOver` is `nil` because nobody acts.
    public static func turnSeat(in state: GameState) -> PlayerID? {
        switch state.phase {
        case .setupForward(let index), .setupBackward(let index), .rollDice(let index),
             .mainTurn(let index), .movingRobber(let index):
            return state.players[index].id
        case .discarding, .gameOver:
            return nil
        }
    }

    /// Whether `seat` still owes a discard in the current phase.
    public static func owesDiscard(_ seat: PlayerID, in state: GameState) -> Bool {
        guard case .discarding(let pending) = state.phase else { return false }
        return pending.contains(seat)
    }

    /// The player record for `seat`. Traps if absent: an observation naming a
    /// seat the state does not contain is a corrupt observation, and returning
    /// a zeroed placeholder would encode a plausible-looking lie.
    static func player(_ seat: PlayerID, in state: GameState) -> Player {
        guard let found = state.players.first(where: { $0.id == seat }) else {
            preconditionFailure("observation names seat \(seat.index), which the state does not contain")
        }
        return found
    }

    /// A tile's production likelihood in pips, or 0 for the desert.
    ///
    /// Delegates to `DiceOdds`, which is the engine's single statement of the
    /// dice distribution - two consumers had previously each grown their own
    /// copy of that table, and a third copy here would be the same mistake with
    /// a worse blast radius, since a wrong pip count would be baked into every
    /// trained artifact rather than into one bot's tie-break.
    ///
    /// Encoding pips rather than the raw token matters: on a raw number line 8
    /// and 9 look adjacent and 2 and 12 look far apart, when in production
    /// terms 8 is the best tile on the board and 2 and 12 are equally the
    /// worst. A learner should not have to rediscover the triangle.
    static func pips(of numberToken: Int?) -> Int {
        guard let token = numberToken else { return 0 }
        return DiceOdds.pips(for: token)
    }
}

// MARK: - Numeric feature vector

public extension StateEncoding {

    /// The position as a fixed-width vector of `featureCount` floats, every one
    /// of them finite and in `0...1`.
    ///
    /// ## What the layout looks like
    /// Five blocks, in this order. All board blocks walk `BoardIndex`'s sorted
    /// order, and all per-seat blocks walk `seatOrder(from:)`, so slot meanings
    /// never depend on hash order or on which seat is observing.
    ///
    /// | Offset | Width | Block |
    /// |---|---|---|
    /// | 0 | 35 | global: phase one-hot, last roll, bank, deck, offers, robber |
    /// | 35 | 4 x 31 | per seat, observer first |
    /// | 159 | 19 x 7 | per tile, ascending coordinate |
    /// | 292 | 54 x 8 | per vertex, ascending `VertexID` |
    /// | 724 | 72 x 4 | per edge, ascending `EdgeID` |
    ///
    /// ## Why every value is normalised
    /// A trainer fed 19 bank cards beside 10 victory points beside a 0/1 flag
    /// spends its first epochs learning the three scales instead of the game,
    /// and gradient magnitudes end up dominated by whichever feature happens to
    /// count highest. Each count is divided by a documented maximum from the
    /// constants above and clamped into `0...1`.
    ///
    /// - Parameters:
    ///   - observation: what the seat is shown. `legalMoves` is not encoded
    ///     here - see the note on `promptDescription`.
    ///   - policy: whether opponents' exact hands are visible. Does not change
    ///     the vector's width.
    static func features(_ observation: GameObservation,
                         policy: HiddenInformationPolicy = .revealAll) -> [Float] {
        let index = BoardIndex(observation.state.board)
        var values: [Float] = []
        values.reserveCapacity(featureCount)

        appendGlobal(observation, index: index, into: &values)
        let order = seatOrder(from: observation.seat, in: observation.state)
        for seat in order {
            appendSeat(seat, observation, policy: policy, into: &values)
        }
        // Empty chairs. A three-player game leaves the fourth seat's block
        // zeroed rather than shortening the vector - see `seatOrder(from:in:)`.
        values.append(contentsOf:
            repeatElement(0, count: (seatCount - order.count) * perPlayerFeatureCount))
        appendTiles(index, into: &values)
        appendBoardOwnership(observation, index: index, into: &values)

        // `precondition`, not `assert`: a misaligned vector is precisely the
        // defect that produces no error and shows up weeks later as weak play,
        // and `assert` is compiled out of the configuration that ships.
        precondition(values.count == featureCount,
                     "layout v\(layoutVersion) promises \(featureCount) features, produced \(values.count)")
        return values
    }

    // MARK: Blocks

    /// Global block, 35 slots: phase one-hot (7), last roll normalised + a flag
    /// saying whether there was one (2), bank stock per resource (5), dev cards
    /// left in the deck (1), pending trade offers (1), robber tile one-hot (19).
    private static func appendGlobal(_ observation: GameObservation, index: BoardIndex, into values: inout [Float]) {
        let state = observation.state
        values.append(contentsOf: oneHot(phaseSlot(state.phase), width: phaseCount))
        // The flag matters: without it "no roll yet" and "rolled a 2" both
        // encode as 0.0 and a learner cannot tell the start of a turn from a
        // bad one.
        values.append(state.lastDiceRoll.map { normalised($0 - minDiceRoll, max: maxDiceRoll - minDiceRoll) } ?? 0)
        values.append(state.lastDiceRoll == nil ? 0 : 1)
        for resource in Resource.allCases {
            values.append(normalised(state.bank[resource] ?? 0, max: resourceCardsPerKind))
        }
        values.append(normalised(state.devCardDeck.count, max: devCardDeckSize))
        values.append(normalised(state.pendingTradeOffers.count, max: pendingTradeOfferSoftCap))
        values.append(contentsOf: oneHot(index.slot(of: state.board.robberTile), width: tileCount))
    }

    /// One seat's 31 slots: 14 holdings, 11 standing, 6 port access.
    private static func appendSeat(_ seat: PlayerID,
                                   _ observation: GameObservation,
                                   policy: HiddenInformationPolicy,
                                   into values: inout [Float]) {
        let state = observation.state
        let seated = player(seat, in: state)
        appendHoldings(of: seated, observer: observation.seat, policy: policy, state: state, into: &values)
        appendStanding(of: seated, state: state, into: &values)
        appendPorts(of: seated, state: state, into: &values)
    }

    /// Holdings, 14 slots: hand by resource (5, HIDDEN), hand size (1, public),
    /// unplayed dev cards by type (5, HIDDEN), unplayed dev card count (1,
    /// public), dev cards bought this turn (1, public - every purchase happens
    /// in the open), whether a dev card has been played this turn (1, public).
    ///
    /// The two HIDDEN groups are the only hidden-information features in the
    /// layout, and they are sourced entirely from `holdings(of:seenBy:policy:)`.
    /// Under `.publicCountsOnly` they are zero for every seat but the observer,
    /// and the two public counts beside them still carry what a real player can
    /// see. Nothing downstream changes.
    private static func appendHoldings(of seated: Player,
                                       observer: PlayerID,
                                       policy: HiddenInformationPolicy,
                                       state: GameState,
                                       into values: inout [Float]) {
        let held = holdings(of: seated, seenBy: observer, policy: policy)
        for resource in Resource.allCases {
            values.append(normalised(held.resources[resource] ?? 0, max: resourceCardsPerKind))
        }
        values.append(normalised(held.handSize, max: handSizeSoftCap))
        for type in DevCardType.allCases {
            values.append(normalised(held.devCards[type] ?? 0, max: knightCardCount))
        }
        values.append(normalised(held.devCardCount, max: devCardDeckSize))
        values.append(normalised((state.devCardsBoughtThisTurn[seated.id] ?? []).count, max: devCardsBoughtSoftCap))
        values.append(state.devCardPlayedThisTurn == seated.id ? 1 : 0)
    }

    /// Standing, 11 slots: trades accepted this turn, public VP, settlements,
    /// cities, roads built, knights played, longest continuous road, holds
    /// longest road, holds largest army, is the seat to move, owes a discard.
    ///
    /// `publicVictoryPoints` rather than `victoryPoints` on purpose - the
    /// difference between them is exactly the hidden VP cards, and putting the
    /// hidden total here would leak them for every seat under every policy.
    /// The observer's own VP cards are already in the holdings block.
    private static func appendStanding(of seated: Player, state: GameState, into values: inout [Float]) {
        values.append(normalised(state.tradesAcceptedThisTurn[seated.id] ?? 0, max: tradesAcceptedSoftCap))
        values.append(normalised(state.publicVictoryPoints(for: seated.id), max: victoryPointTarget))
        values.append(normalised(seated.settlements.count, max: Building.maxSettlementsPerPlayer))
        values.append(normalised(seated.cities.count, max: Building.maxCitiesPerPlayer))
        values.append(normalised(seated.roads.count, max: Building.maxRoadsPerPlayer))
        values.append(normalised(seated.playedKnights, max: knightCardCount))
        // Segments built and longest continuous run are different numbers - a
        // forked network can hold many more of the former - and only the second
        // one answers "how close is this seat to the bonus".
        values.append(normalised(LongestRoad.length(for: seated, in: state), max: Building.maxRoadsPerPlayer))
        values.append(state.longestRoadPlayer == seated.id ? 1 : 0)
        values.append(state.largestArmyPlayer == seated.id ? 1 : 0)
        values.append(turnSeat(in: state) == seated.id ? 1 : 0)
        values.append(owesDiscard(seated.id, in: state) ? 1 : 0)
    }

    /// Port access, 6 slots: a generic 3:1 flag then one 2:1 flag per resource.
    ///
    /// Derived rather than left for a learner to infer from vertex ownership
    /// plus a port table the vector does not contain. Ports are static for a
    /// game but decide whether a spare-ore position is worth anything.
    private static func appendPorts(of seated: Player, state: GameState, into values: inout [Float]) {
        let owned = seated.settlements.union(seated.cities)
        var generic: Float = 0
        var byResource: [Resource: Float] = [:]
        // `board.ports` is an array, so this walk is already stable; both
        // assignments are idempotent, so the result would not depend on order
        // even if it were not.
        for port in state.board.ports where owned.contains(port.vertexA) || owned.contains(port.vertexB) {
            switch port.kind {
            case .generic: generic = 1
            case .resource(let resource): byResource[resource] = 1
            }
        }
        values.append(generic)
        for resource in Resource.allCases { values.append(byResource[resource] ?? 0) }
    }

    /// Tile block, 7 slots per tile in ascending coordinate order: resource
    /// one-hot (5), desert flag (1), pip probability (1).
    private static func appendTiles(_ index: BoardIndex, into values: inout [Float]) {
        for tile in index.tiles {
            for resource in Resource.allCases {
                values.append(tile.kind == .resource(resource) ? 1 : 0)
            }
            values.append(tile.kind == .desert ? 1 : 0)
            values.append(normalised(pips(of: tile.numberToken), max: maxPips))
        }
    }

    /// Vertex block then edge block, both in egocentric seat order: 8 slots per
    /// vertex (settlement, city) x 4 seats, then 4 slots per edge (road).
    ///
    /// A three-player game pads the missing seat's slots to zero **inside each
    /// vertex and each edge**, not at the end of the block. That placement is
    /// the whole point: slot *k* of a vertex has to mean "the k-th seat in
    /// egocentric order owns this vertex" in every position forever, so the
    /// absent chair's two slots must sit where that chair's slots always sit.
    /// Padding at the end of the block would keep the width right and shift the
    /// meaning of every slot after the first vertex - silently, which is the
    /// exact defect `layoutVersion` exists to make impossible.
    private static func appendBoardOwnership(_ observation: GameObservation,
                                             index: BoardIndex,
                                             into values: inout [Float]) {
        let seated = seatOrder(from: observation.seat, in: observation.state)
            .map { player($0, in: observation.state) }
        let emptyChairs = seatCount - seated.count
        for vertex in index.vertices {
            for owner in seated {
                values.append(owner.settlements.contains(vertex) ? 1 : 0)
                values.append(owner.cities.contains(vertex) ? 1 : 0)
            }
            values.append(contentsOf: repeatElement(0, count: emptyChairs * 2))
        }
        for edge in index.edges {
            for owner in seated {
                values.append(owner.roads.contains(edge) ? 1 : 0)
            }
            values.append(contentsOf: repeatElement(0, count: emptyChairs))
        }
    }

    // MARK: Scalar helpers

    /// A count as a `0...1` feature.
    ///
    /// Clamped, not merely divided. Several maxima above are deliberately soft
    /// (a hand can exceed `handSizeSoftCap`), and a feature that escapes
    /// `0...1` breaks the range contract this file advertises and that
    /// `StateEncodingTests` checks. Saturating is the honest behaviour: the
    /// caps sit where extra magnitude stops carrying strategy.
    private static func normalised(_ value: Int, max limit: Int) -> Float {
        precondition(limit > 0, "normalisation maximum must be positive, got \(limit)")
        return Swift.min(1, Swift.max(0, Float(value) / Float(limit)))
    }

    /// A one-hot row of `width` slots with `index` set.
    private static func oneHot(_ index: Int, width: Int) -> [Float] {
        precondition((0..<width).contains(index), "one-hot index \(index) outside 0..<\(width)")
        var slots = [Float](repeating: 0, count: width)
        slots[index] = 1
        return slots
    }
}

// MARK: - Compact text rendering

public extension StateEncoding {

    /// How many numbered moves go on one line. Purely for human legibility;
    /// changing it does not change the field set, so it is not a version bump.
    static let movesPerLine = 6

    /// Hex characters in the fallback handle for a trade offer that is not in
    /// the pending list. See `offerHandle(_:among:)`.
    static let offerHandleLength = 6

    /// The position as a compact text block for a language model's context.
    ///
    /// ## Why not just serialise the state
    /// A `JSONEncoder` dump of a mid-game `GameState` measures about 24 KB,
    /// because every vertex and edge is a nested array of axial hex coordinates
    /// and there are hundreds of them. At roughly 4 characters per token that
    /// is ~6,000 tokens of context *per turn*, most of it spent re-describing a
    /// board that has not changed, before the model has read a single legal
    /// move. This rendering costs about an eighth of that (measured in
    /// `StateEncodingTests`), and the saving comes almost entirely from
    /// addressing the board by its canonical index - `v17`, `e40`, `h3` -
    /// rather than by geometry.
    ///
    /// ## Its relationship to `features(_:)`
    /// Both render the same observation and neither shows anything the other
    /// hides. There is exactly one deliberate asymmetry: the text lists the
    /// legal moves and the vector does not. That is not a leak of state - the
    /// move list is a pure function of the position both already encode - it is
    /// a difference in how the two consumers receive their action space. A
    /// policy network is handed an action mask alongside its features; a
    /// language model has no such channel and has to be told in prose. The
    /// `OFFERS` section sits with the moves for the same reason: it exists to
    /// make `accept`/`reject` interpretable, and the vector carries the pending
    /// offer *count* as state.
    ///
    /// - Parameters:
    ///   - observation: what the seat is shown.
    ///   - policy: whether opponents' exact hands are visible. Under
    ///     `.publicCountsOnly` an opponent's hand renders as `hand=7[?]`.
    static func promptDescription(_ observation: GameObservation,
                                  policy: HiddenInformationPolicy = .revealAll) -> String {
        let state = observation.state
        let index = BoardIndex(state.board)
        var lines = [
            "OBS v\(layoutVersion) seat=P\(observation.seat.index) phase=\(phaseLabel(state.phase)) "
                + "lastRoll=\(state.lastDiceRoll.map(String.init) ?? "-")",
            "KEY h#/v#/e# are hex/vertex/edge indices in this layout's canonical board order. "
                + "vp is public victory points, so hidden VP cards are excluded. Omitted seat fields are zero.",
            hexLine(index, robber: state.board.robberTile),
            portLine(state.board, index: index),
            bankLine(state),
        ]
        lines.append(contentsOf: seatOrder(from: observation.seat, in: observation.state).map {
            seatLine($0, observation, index: index, policy: policy)
        })
        lines.append(contentsOf: offerLines(state))
        lines.append(contentsOf: moveLines(observation, index: index))
        return lines.joined(separator: "\n")
    }

    // MARK: Sections

    /// `HEX h0=gr5 h1=wo2 h9=desert* ...`, ascending coordinate, `*` on the
    /// robber's tile.
    private static func hexLine(_ index: BoardIndex, robber: HexCoordinate) -> String {
        let entries = index.tiles.enumerated().map { slot, tile -> String in
            let robberMark = tile.coordinate == robber ? "*" : ""
            switch tile.kind {
            case .desert: return "h\(slot)=desert\(robberMark)"
            case .resource(let resource): return "h\(slot)=\(short(resource))\(tile.numberToken ?? 0)\(robberMark)"
            }
        }
        return "HEX(*=robber) " + entries.joined(separator: " ")
    }

    /// `PORT 3:1@v0,v1 grain@v12,v13 ...` in `board.ports` order, which is an
    /// array and therefore already stable.
    private static func portLine(_ board: Board, index: BoardIndex) -> String {
        let entries = board.ports.map { port -> String in
            let kind: String
            switch port.kind {
            case .generic: kind = "3:1"
            case .resource(let resource): kind = "\(resource.rawValue)2:1"
            }
            return "\(kind)@v\(index.slot(of: port.vertexA)),v\(index.slot(of: port.vertexB))"
        }
        return "PORT " + entries.joined(separator: " ")
    }

    /// `BANK br=19 lu=17 or=15 gr=12 wo=18 devDeck=21`.
    private static func bankLine(_ state: GameState) -> String {
        let stock = Resource.allCases.map { "\(short($0))=\(state.bank[$0] ?? 0)" }.joined(separator: " ")
        return "BANK \(stock) devDeck=\(state.devCardDeck.count)"
    }

    /// One seat's row. Zero-valued optional fields are omitted rather than
    /// printed as `=0`: they are the common case, and the `KEY` line says that
    /// an absent field is zero, so their absence costs no ambiguity and saves
    /// roughly a fifth of the block.
    private static func seatLine(_ seat: PlayerID,
                                 _ observation: GameObservation,
                                 index: BoardIndex,
                                 policy: HiddenInformationPolicy) -> String {
        let state = observation.state
        let seated = player(seat, in: state)
        let held = holdings(of: seated, seenBy: observation.seat, policy: policy)
        var parts = ["P\(seat.index)"]
        if seat == observation.seat { parts.append("you") }
        if turnSeat(in: state) == seat { parts.append("turn") }
        parts.append("vp=\(state.publicVictoryPoints(for: seat))")
        parts.append("hand=\(held.handSize)[\(held.isRevealed ? bundle(held.resources) : "?")]")
        parts.append("dev=\(held.devCardCount)[\(held.isRevealed ? devBundle(held.devCards) : "?")]")
        parts.append("sett=\(vertexList(seated.settlements, index: index))")
        parts.append("city=\(vertexList(seated.cities, index: index))")
        parts.append("road=\(edgeList(seated.roads, index: index))")
        parts.append(contentsOf: seatFlags(seated, state: state, index: index))
        return parts.joined(separator: " ")
    }

    /// The tail of a seat row: the fields that are usually zero or absent.
    private static func seatFlags(_ seated: Player, state: GameState, index: BoardIndex) -> [String] {
        var parts: [String] = []
        let longest = LongestRoad.length(for: seated, in: state)
        if longest > 0 { parts.append("lroad=\(longest)") }
        if seated.playedKnights > 0 { parts.append("knights=\(seated.playedKnights)") }
        let bought = (state.devCardsBoughtThisTurn[seated.id] ?? []).count
        if bought > 0 { parts.append("boughtThisTurn=\(bought)") }
        if state.devCardPlayedThisTurn == seated.id { parts.append("playedDevThisTurn") }
        if let trades = state.tradesAcceptedThisTurn[seated.id], trades > 0 { parts.append("tradesThisTurn=\(trades)") }
        let ports = portLabels(for: seated, in: state)
        if !ports.isEmpty { parts.append("ports=\(ports.joined(separator: ","))") }
        if state.longestRoadPlayer == seated.id { parts.append("HOLDS-LONGEST-ROAD") }
        if state.largestArmyPlayer == seated.id { parts.append("HOLDS-LARGEST-ARMY") }
        if owesDiscard(seated.id, in: state) { parts.append("MUST-DISCARD") }
        return parts
    }

    /// `OFFERS 2: #0 from=P1 give=br2 want=or1 | #1 ...`, or nothing when none
    /// are pending.
    ///
    /// Numbered by position in `state.pendingTradeOffers` - an array, so the
    /// order is already stable - and `accept`/`reject` quote the same numbers.
    ///
    /// ## Why numbers rather than a slice of the offer's UUID
    /// The first spelling of this printed six hex characters of the id, which
    /// is ambiguous in practice and not merely in theory. `TradeOffer.enumerated`
    /// derives its id by walking an FNV-1a hash over a descriptor string and
    /// keeping one byte per input character, so two offers from the same
    /// proposer share almost the whole leading window: a real 23-offer position
    /// rendered eight of them as the identical handle `0c62bf`. Positional
    /// numbering cannot collide, is shorter, and matches how
    /// `ActionSpace.index(of:pendingOffers:)` addresses the same offers.
    private static func offerLines(_ state: GameState) -> [String] {
        guard !state.pendingTradeOffers.isEmpty else { return [] }
        let entries = state.pendingTradeOffers.enumerated().map { slot, offer in
            "#\(slot) from=P\(offer.from.index) give=\(bundle(offer.give)) want=\(bundle(offer.want))"
        }
        return ["OFFERS \(entries.count): " + entries.joined(separator: " | ")]
    }

    /// The numbered legal moves.
    ///
    /// Numbered by position in `observation.legalMoves`, from 0, so a reply of
    /// `12` is `legalMoves[12]` with no lookup table in between and no second
    /// ordering to keep in sync.
    private static func moveLines(_ observation: GameObservation, index: BoardIndex) -> [String] {
        // Numbered within THIS observation, not by `ActionSpace` - see the
        // "Two move numberings" section on `StateEncoding`. A model picking
        // from nine options is a far easier ask than one naming an index in a
        // space of 8,815 that is almost entirely illegal right now.
        var lines = ["MOVES \(observation.legalMoves.count) - reply with one number, 0-based, "
            + "indexing this list only"]
        let offers = observation.state.pendingTradeOffers
        let labels = observation.legalMoves.enumerated().map {
            "\($0.offset) \(label(for: $0.element, index: index, pendingOffers: offers))"
        }
        for start in stride(from: 0, to: labels.count, by: movesPerLine) {
            lines.append("  " + labels[start..<Swift.min(start + movesPerLine, labels.count)].joined(separator: " | "))
        }
        return lines
    }

    // MARK: Labels

    /// A move in one short phrase, addressing the board by canonical index.
    ///
    /// `pendingOffers` lets `accept`/`reject` name their offer by its position
    /// in that list, the way the `OFFERS` block does. Omitting it still
    /// produces an unambiguous label - see `offerHandle(_:among:)` - it is just
    /// longer and does not line up with anything the reader has been shown.
    static func label(for move: GameMove, index: BoardIndex, pendingOffers: [TradeOffer] = []) -> String {
        switch move {
        case .placeInitialSettlement(let vertex): return "setupSett v\(index.slot(of: vertex))"
        case .placeInitialRoad(let edge): return "setupRoad e\(index.slot(of: edge))"
        case .rollDice: return "roll"
        case .buildRoad(let edge): return "road e\(index.slot(of: edge))"
        case .buildSettlement(let vertex): return "sett v\(index.slot(of: vertex))"
        case .buildCity(let vertex): return "city v\(index.slot(of: vertex))"
        case .buyDevCard: return "buyDev"
        case .playKnight(let tile, let victim):
            return "knight h\(index.slot(of: tile))\(stealSuffix(victim))"
        case .playRoadBuilding(let first, let second):
            return "roadBuilding e\(index.slot(of: first)),e\(index.slot(of: second))"
        case .playYearOfPlenty(let first, let second):
            return "yearOfPlenty \(short(first)),\(short(second))"
        case .playMonopoly(let resource): return "monopoly \(short(resource))"
        case .moveRobber(let tile, let victim):
            return "robber h\(index.slot(of: tile))\(stealSuffix(victim))"
        case .discard(let table): return "discard \(bundle(table))"
        case .bankTrade(let give, let get): return "bank \(bundle(give))>\(bundle(get))"
        case .proposeTrade(let offer): return "offer \(bundle(offer.give))>\(bundle(offer.want))"
        case .respondToTrade(let offerID, let accept):
            return "\(accept ? "accept" : "reject") \(offerHandle(offerID, among: pendingOffers))"
        case .endTurn: return "endTurn"
        }
    }

    private static func stealSuffix(_ victim: PlayerID?) -> String {
        victim.map { " steal=P\($0.index)" } ?? ""
    }

    /// `setup1:P0`, `main:P2`, `discard:P1,P3`, `over:P0` - phase plus whoever
    /// it names. The pending set is sorted; it is a `Set`, so an unsorted walk
    /// would print a different string on every launch and break the stability
    /// this rendering promises.
    static func phaseLabel(_ phase: GamePhase) -> String {
        switch phase {
        case .setupForward(let index): return "setup1:P\(index)"
        case .setupBackward(let index): return "setup2:P\(index)"
        case .rollDice(let index): return "roll:P\(index)"
        case .mainTurn(let index): return "main:P\(index)"
        case .discarding(let pending): return "discard:" + pending.sorted().map { "P\($0.index)" }.joined(separator: ",")
        case .movingRobber(let index): return "robber:P\(index)"
        case .gameOver(let winner): return "over:P\(winner.index)"
        }
    }

    /// Two-letter resource tags, short enough to keep a hand on one line and
    /// distinct enough to read: `br lu or gr wo`.
    static func short(_ resource: Resource) -> String {
        switch resource {
        case .brick: return "br"
        case .lumber: return "lu"
        case .ore: return "or"
        case .grain: return "gr"
        case .wool: return "wo"
        }
    }

    /// Dev card names in full: a hand holds at most a handful, so the clarity
    /// is nearly free, and `knight` is unambiguous where `k` would not be.
    static func short(_ card: DevCardType) -> String {
        switch card {
        case .knight: return "knight"
        case .roadBuilding: return "roadBuilding"
        case .yearOfPlenty: return "yearOfPlenty"
        case .monopoly: return "monopoly"
        case .victoryPoint: return "victoryPoint"
        }
    }

    /// `br2,or1`, or `-` when empty. Driven off `Resource.allCases` rather than
    /// the dictionary's own keys, whose order Swift seeds per process.
    static func bundle(_ table: [Resource: Int]) -> String {
        let parts = Resource.allCases.compactMap { resource -> String? in
            let amount = table[resource] ?? 0
            return amount > 0 ? "\(short(resource))\(amount)" : nil
        }
        return parts.isEmpty ? "-" : parts.joined(separator: ",")
    }

    /// `knight2,monopoly1`, or `-` when empty. Same `allCases` reasoning.
    static func devBundle(_ table: [DevCardType: Int]) -> String {
        let parts = DevCardType.allCases.compactMap { card -> String? in
            let amount = table[card] ?? 0
            return amount > 0 ? "\(short(card))\(amount)" : nil
        }
        return parts.isEmpty ? "-" : parts.joined(separator: ",")
    }

    /// `v3,v9`, or `-`. Sorted, because the source is a `Set`.
    private static func vertexList(_ vertices: Set<VertexID>, index: BoardIndex) -> String {
        let parts = vertices.sorted().map { "v\(index.slot(of: $0))" }
        return parts.isEmpty ? "-" : parts.joined(separator: ",")
    }

    /// `e2,e7`, or `-`. Sorted, because the source is a `Set`.
    private static func edgeList(_ edges: Set<EdgeID>, index: BoardIndex) -> String {
        let parts = edges.sorted().map { "e\(index.slot(of: $0))" }
        return parts.isEmpty ? "-" : parts.joined(separator: ",")
    }

    /// The ports a seat can use, as `3:1` and `ore2:1` style tags.
    private static func portLabels(for seated: Player, in state: GameState) -> [String] {
        let owned = seated.settlements.union(seated.cities)
        var generic = false
        var resources: Set<Resource> = []
        for port in state.board.ports where owned.contains(port.vertexA) || owned.contains(port.vertexB) {
            switch port.kind {
            case .generic: generic = true
            case .resource(let resource): resources.insert(resource)
            }
        }
        var labels = generic ? ["3:1"] : []
        labels.append(contentsOf: Resource.allCases.filter { resources.contains($0) }.map { "\($0.rawValue)2:1" })
        return labels
    }

    /// How the text names a pending trade offer: `#2` when the offer is in
    /// `pendingOffers`, otherwise a digest of its whole id.
    ///
    /// The fallback hashes all of the id rather than quoting a prefix of it,
    /// because `TradeOffer.enumerated`'s ids are strongly correlated in their
    /// leading bytes (see `offerLines`) and a prefix is therefore not a handle
    /// at all. It returns a label rather than trapping: this is a rendering
    /// path, and a caller labelling one move without the state to go with it
    /// should get something readable, not a crash.
    static func offerHandle(_ id: UUID, among pendingOffers: [TradeOffer]) -> String {
        if let slot = pendingOffers.firstIndex(where: { $0.id == id }) { return "#\(slot)" }
        var digest: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in id.uuidString.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        return "offer:" + String(digest, radix: 16).suffix(offerHandleLength)
    }
}
