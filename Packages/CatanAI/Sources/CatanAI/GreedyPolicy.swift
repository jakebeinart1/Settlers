import CatanEngine

/// Plays the highest-production move available, and nothing cleverer.
///
/// ## Why this exists
/// `RandomPolicy` was supposed to be the yardstick a strength claim is measured
/// against, and it turned out to be a *saturated* one: the shipped heuristic
/// beat it 200 games out of 200. A measurement pinned at 100% cannot move, so
/// it can no longer tell you whether a change made the bot better or worse -
/// which is exactly the question the anchor was introduced to answer.
///
/// This is the middle rung. It is meant to lose to the real bot and beat random
/// play, so that both comparisons have room to move in both directions. If a
/// future agent cannot beat this, it has not learned to play Catan; if it beats
/// this but loses to `HeuristicPolicy`, that is a real and readable result.
///
/// ## What "greedy" means precisely
/// It values one thing - resource production - and is blind to everything else
/// that wins games:
///
/// - **It never trades.** No bank trades, no proposals, and it declines every
///   offer. Trading is the single largest source of strength in Catan, so
///   withholding it is what keeps this policy comfortably below the heuristic.
/// - **It has no plan.** Moves are taken in a fixed priority order, evaluated
///   only against the position in front of it, with no notion of what it is
///   building toward.
/// - **It ignores the opponents,** except when placing the robber, where
///   ignoring them is not expressible.
/// - **It has no tuning constants.** Deliberately: `BotWeights` exists so the
///   heuristic can be swept, and an anchor that can be swept is not an anchor.
///   A yardstick that moves measures nothing.
///
/// Everything it does know - that an 8 produces more often than a 4, that a
/// city beats a settlement - is a fact of the rules rather than a judgement, so
/// this policy stays fixed forever while the things measured against it change.
public struct GreedyPolicy: Policy {
    public let id = "greedy"

    public init() {}

    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        let moves = observation.legalMoves
        precondition(!moves.isEmpty, "asked to move with no legal move in phase \(observation.state.phase)")

        // Priority order, most valuable first. The first kind with a legal
        // instance wins, and the choice *within* that kind is made by
        // production alone.
        if let move = bestSettlementOrCity(moves, board: observation.state.board) { return move }
        if let move = moves.first(where: { $0.isRoll || $0.isBuyDevCard }) { return move }
        if let move = bestRobberMove(moves, observation: observation) { return move }
        if let move = bestDiscard(moves, observation: observation) { return move }
        if let move = bestRoad(moves) { return move }

        // Trading is refused rather than ignored: an unanswered offer would
        // leave the proposer waiting, and declining is the honest expression of
        // a policy that does not trade.
        if let decline = moves.first(where: { $0.isDeclineTrade }) { return decline }
        if moves.contains(.endTurn) { return .endTurn }

        // Nothing above matched, so this is a phase with a single forced move
        // (or one this policy has no opinion about). `legalMoves` is ordered
        // deterministically by the engine, so taking the first is reproducible.
        return moves[0]
    }

    // MARK: - Choices

    /// Cities before settlements before initial placements, each on the
    /// highest-producing vertex offered.
    ///
    /// One function rather than three because the choice is identical in all
    /// three cases - rank the vertices by pips, take the best - and splitting it
    /// would be three copies of the same two lines.
    private func bestSettlementOrCity(_ moves: [GameMove], board: Board) -> GameMove? {
        let ranked: [KeyPath<GameMove, Bool>] = [\.isBuildCity, \.isBuildSettlement, \.isInitialSettlement]
        for pick in ranked {
            let candidates = moves.filter { $0[keyPath: pick] }
            guard !candidates.isEmpty else { continue }
            return candidates.max { left, right in
                let (a, b) = (production(of: left.vertex, board: board), production(of: right.vertex, board: board))
                // Tie-break on the vertex itself. `max(by:)` keeps the last of
                // equal elements, so without this the winner would depend on
                // the order `legalMoves` happened to produce.
                return a == b ? left.vertex! < right.vertex! : a < b
            }
        }
        return nil
    }

    /// Total pips on the tiles touching a vertex - how often it pays out.
    private func production(of vertex: VertexID?, board: Board) -> Int {
        guard let vertex else { return 0 }
        return board.neighborTiles(of: vertex).reduce(0) { total, coordinate in
            guard let tile = board.tiles.first(where: { $0.coordinate == coordinate }),
                  let token = tile.numberToken, case .resource = tile.kind else { return total }
            return total + DiceOdds.pips(for: token)
        }
    }

    /// Blocks the best tile this policy is not itself standing on, and steals
    /// from whoever holds the most.
    ///
    /// The one place opponents are considered, because a robber move that
    /// ignored them would have to invent a rule for where to put it anyway.
    private func bestRobberMove(_ moves: [GameMove], observation: GameObservation) -> GameMove? {
        let board = observation.state.board
        let player = observation.state.players.first { $0.id == observation.seat }
        let ownVertices = (player?.settlements ?? []).union(player?.cities ?? [])
        let candidates = moves.filter { $0.robberTarget != nil }
        guard !candidates.isEmpty else { return nil }

        return candidates.max { left, right in
            (robberValue(left, board: board, own: ownVertices, state: observation.state),
             left.robberOrdering)
            < (robberValue(right, board: board, own: ownVertices, state: observation.state),
               right.robberOrdering)
        }
    }

    /// A robber placement is worth the tile's pips, unless this policy would be
    /// blocking itself, in which case it is worth nothing.
    private func robberValue(
        _ move: GameMove, board: Board, own: Set<VertexID>, state: GameState
    ) -> Int {
        guard let target = move.robberTarget,
              let tile = board.tiles.first(where: { $0.coordinate == target }),
              let token = tile.numberToken else { return 0 }
        let touchesOwn = own.contains { board.neighborTiles(of: $0).contains(target) }
        guard !touchesOwn else { return 0 }
        // Prefer stealing from the player holding the most cards; a placement
        // with no victim is still worth its pips as a block.
        let victimCards = move.robberVictim.map { victim in
            state.players.first { $0.id == victim }?.resources.values.reduce(0, +) ?? 0
        } ?? 0
        return DiceOdds.pips(for: token) * 100 + victimCards
    }

    /// Sheds whichever cards it holds most of, keeping its hand balanced by
    /// accident rather than by design.
    private func bestDiscard(_ moves: [GameMove], observation: GameObservation) -> GameMove? {
        let held = observation.state.players.first { $0.id == observation.seat }?.resources ?? [:]
        let candidates = moves.filter { $0.discardAmounts != nil }
        guard !candidates.isEmpty else { return nil }
        return candidates.max { left, right in
            (surplusShed(left, held: held), left.discardOrdering)
                < (surplusShed(right, held: held), right.discardOrdering)
        }
    }

    /// How much of the discard comes out of the resources it holds most of.
    private func surplusShed(_ move: GameMove, held: [Resource: Int]) -> Int {
        guard let amounts = move.discardAmounts else { return 0 }
        return amounts.reduce(0) { total, entry in total + (held[entry.key] ?? 0) * entry.value }
    }

    /// Any road, taken last.
    ///
    /// Roads come after everything else on purpose: this way a road is only
    /// built with resources that nothing more valuable could use. Which road is
    /// not reasoned about at all - the engine's ordering decides - because
    /// road placement is exactly the kind of positional judgement this policy
    /// exists to be worse at.
    private func bestRoad(_ moves: [GameMove]) -> GameMove? {
        moves.first { $0.isBuildRoad || $0.isInitialRoad }
    }
}

// MARK: - Move shape helpers

/// Small accessors so the policy above reads as decisions rather than as a
/// wall of `if case` pattern matches.
private extension GameMove {
    var isBuildCity: Bool { if case .buildCity = self { return true }; return false }
    var isBuildSettlement: Bool { if case .buildSettlement = self { return true }; return false }
    var isInitialSettlement: Bool { if case .placeInitialSettlement = self { return true }; return false }
    var isBuildRoad: Bool { if case .buildRoad = self { return true }; return false }
    var isInitialRoad: Bool { if case .placeInitialRoad = self { return true }; return false }
    var isRoll: Bool { self == .rollDice }
    var isBuyDevCard: Bool { self == .buyDevCard }

    var isDeclineTrade: Bool {
        if case .respondToTrade(_, let accept) = self { return !accept }
        return false
    }

    /// The vertex a placement move targets, if it targets one.
    var vertex: VertexID? {
        switch self {
        case .placeInitialSettlement(let vertex), .buildSettlement(let vertex), .buildCity(let vertex):
            return vertex
        default: return nil
        }
    }

    /// Where a move sends the robber - covering both the robber phase and the
    /// knight card, which are the same decision wearing two case names.
    var robberTarget: HexCoordinate? {
        switch self {
        case .moveRobber(let target, _), .playKnight(let target, _): return target
        default: return nil
        }
    }

    var robberVictim: PlayerID? {
        switch self {
        case .moveRobber(_, let victim), .playKnight(_, let victim): return victim
        default: return nil
        }
    }

    /// A stable tie-break for robber moves, so equal-value placements do not
    /// resolve by whatever order they arrived in.
    var robberOrdering: String {
        guard let target = robberTarget else { return "" }
        return "\(target.q),\(target.r),\(robberVictim?.index ?? -1)"
    }

    var discardAmounts: [Resource: Int]? {
        if case .discard(let amounts) = self { return amounts }
        return nil
    }

    /// Sorted, so it does not depend on dictionary iteration order.
    var discardOrdering: String {
        guard let amounts = discardAmounts else { return "" }
        return amounts.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue):\($0.value)" }.joined(separator: ",")
    }
}
