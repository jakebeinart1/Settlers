import CatanEngine

@MainActor
extension GameViewModel {
    /// The complete semantic state SwiftUI needs. The final `GameMove` remains
    /// hidden so no tap, drag, or view can bypass explicit confirmation.
    public var boardDecisionPresentation: BoardDecisionPresentation? {
        guard var result = boardDecisionCoordinator.presentation else { return nil }
        result.sailing = NavalSailingPresentation(state: state, decision: result)
        result.blockadedTiles = NavalBlockadePresentation.tiles(in: state, decision: result)
        return result
    }

    @discardableResult
    public func beginBoardDecision(_ intent: BoardDecisionIntent) -> Bool {
        reconcileBoardDecision()
        return boardDecisionCoordinator.begin(intent, with: boardDecisionContext)
    }

    @discardableResult
    public func selectBoardTarget(_ target: BoardTarget) -> Bool {
        if case .ship(let id) = target, boardDecisionPresentation == nil {
            guard state.naval?.ships.contains(where: {
                $0.id == id && $0.owner == humanPlayer && $0.stepsRemaining > 0
            }) == true, beginBoardDecision(.sailShip) else { return false }
        }
        return boardDecisionCoordinator.select(target)
    }

    public func clearBoardDecisionSelection() {
        boardDecisionCoordinator.clearSelection()
    }

    @discardableResult
    public func undoBoardDecisionSelection() -> Bool {
        boardDecisionCoordinator.undoSelection()
    }

    @discardableResult
    public func cancelBoardDecision() -> Bool {
        boardDecisionCoordinator.cancel()
    }

    /// Commits one complete engine move through the existing candidate-session
    /// checkpoint transaction. A rejection or failed write leaves the proposal
    /// intact and visible; `commitStep` reconciles it only after durable success.
    @discardableResult
    public func confirmBoardDecision() -> Bool {
        guard let move = boardDecisionCoordinator.confirmableMove else {
            boardDecisionCoordinator.reportFailure("Choose a legal location before confirming.")
            return false
        }
        do {
            try apply(move)
            continueVoyage(after: move)
            return true
        } catch {
            boardDecisionCoordinator.reportFailure(error.localizedDescription)
            return false
        }
    }

    /// Keep the selected vessel ready for any unspent travel without retaining
    /// a stale destination. Each destination still needs explicit confirmation.
    private func continueVoyage(after move: GameMove) {
        let shipID: Int?
        switch move {
        case .sailShip(let id, _): shipID = id
        case .buildShip: shipID = state.naval?.ships.last?.id
        default: shipID = nil
        }
        guard let shipID, state.naval?.ships.contains(where: {
            $0.id == shipID && $0.owner == humanPlayer && $0.stepsRemaining > 0
        }) == true, beginBoardDecision(.sailShip) else { return }
        _ = boardDecisionCoordinator.select(.ship(shipID))
    }

    @discardableResult
    public func skipShipCapture() -> Bool {
        do {
            try apply(.skipShipCapture)
            return true
        } catch {
            boardDecisionCoordinator.reportFailure(error.localizedDescription)
            return false
        }
    }

    /// Clears ephemeral intent at a privacy or navigation boundary without
    /// asking the view to know every board-decision subtype.
    func clearBoardDecisionForBoundary() {
        boardDecisionCoordinator.clear()
    }

    func reconcileBoardDecision() {
        guard humanSeats.count == 1 || seatAtDevice != nil else {
            boardDecisionCoordinator.clear()
            return
        }
        boardDecisionCoordinator.reconcile(with: boardDecisionContext)
    }

    private var boardDecisionContext: BoardDecisionContext {
        BoardDecisionContext(
            matchID: checkpointDocument?.activeMatch?.id,
            committedMoveCount: checkpointDocument?.activeMatch?.moves.count ?? 0,
            actor: humanPlayer,
            state: state
        )
    }
}
