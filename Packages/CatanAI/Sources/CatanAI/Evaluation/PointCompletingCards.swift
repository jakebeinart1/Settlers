import CatanEngine

/// The retained B-002 correction: a free-resource/free-road card can open an
/// immediately affordable point purchase that a one-ply position score misses.
/// Keep the exact tested Q(after)-Q(before), not a new coefficient or search.
enum PointCompletingCards {
    /// Added after a legal card play and its masked event fold. Credit only
    /// newly opened readiness; an already affordable purchase earns nothing
    /// again. Actual terminal moves retain their ordinary score. Both ledgers
    /// belong to the observer and carry that observer's exact hand.
    static func adjustment(
        for move: GameMove, from state: GameState, to next: GameState,
        ledger: PublicLedger, nextLedger: PublicLedger,
        evaluator: PositionEvaluator
    ) -> Double {
        guard applies(to: move, in: state, seat: evaluator.seat) else { return 0 }
        precondition(ledger.observer == evaluator.seat && nextLedger.observer == evaluator.seat,
                     "card readiness requires the observer's ledgers")
        guard next.victoryPoints(for: evaluator.seat) < next.victoryPointTarget else { return 0 }
        return readyPointValue(in: next, ledger: nextLedger, evaluator: evaluator)
            - readyPointValue(in: state, ledger: ledger, evaluator: evaluator)
    }

    private static func applies(to move: GameMove, in state: GameState, seat: PlayerID) -> Bool {
        guard state.phase.isMainTurn(of: seat.index) else { return false }
        switch move {
        case .playYearOfPlenty, .playRoadBuilding: return true
        default: return false
        }
    }

    /// The best printed point gain affordable with the observer's present
    /// hand and geometry. Engine checks enforce distance and piece supply;
    /// no partial recipe, conversion, future robbery or hidden holding counts.
    private static func readyPointValue(
        in state: GameState, ledger: PublicLedger, evaluator: PositionEvaluator
    ) -> Double {
        guard let owner = state.players.first(where: { $0.id == evaluator.seat }) else {
            preconditionFailure("card readiness requires an existing observer")
        }
        let board = BoardIndex(state: state)
        var points = 0
        if RulesEngine.canAfford(Building.cityCost, player: owner),
           owner.settlements.sorted().contains(where: { Building.canBuildCity($0, for: owner.id, in: state) }) {
            points = max(points, state.rules.victoryPoints(for: .city) - state.rules.victoryPoints(for: .settlement))
        }
        if RulesEngine.canAfford(Building.settlementCost, player: owner),
           board.buildableSites(for: owner.id, in: state)
            .contains(where: { Building.canBuildSettlement($0, for: owner.id, in: state) }) {
            points = max(points, state.rules.victoryPoints(for: .settlement))
        }
        return readinessValue(points: points, state: state, ledger: ledger, evaluator: evaluator, board: board)
    }

    /// Ordinary readiness is an option, not an already completed purchase.
    /// A certain winning purchase closes the existing terminal-standing gap
    /// rather than receiving a second win. No future move or RNG is applied.
    private static func readinessValue(
        points: Int, state: GameState, ledger: PublicLedger,
        evaluator: PositionEvaluator, board: BoardIndex
    ) -> Double {
        guard points > 0 else { return 0 }
        let owned = state.victoryPoints(for: evaluator.seat)
        guard owned < state.victoryPointTarget else { return 0 }
        if owned + points >= state.victoryPointTarget {
            return max(0, evaluator.weights.winning
                - evaluator.standing(of: evaluator.seat, in: state, ledger: ledger, board: board))
        }
        return max(0, Double(points) * evaluator.weights.victoryPoint)
    }
}
