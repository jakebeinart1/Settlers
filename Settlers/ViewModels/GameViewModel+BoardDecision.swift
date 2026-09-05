import CatanEngine

@MainActor
extension GameViewModel {
    /// The complete semantic state SwiftUI needs. The final `GameMove` remains
    /// hidden so no tap, drag, or view can bypass explicit confirmation.
    public var boardDecisionPresentation: BoardDecisionPresentation? {
        boardDecisionCoordinator.presentation
    }

    @discardableResult
    public func beginBoardDecision(_ intent: BoardDecisionIntent) -> Bool {
        reconcileBoardDecision()
        return boardDecisionCoordinator.begin(intent, with: boardDecisionContext)
    }

    @discardableResult
    public func selectBoardTarget(_ target: BoardTarget) -> Bool {
        boardDecisionCoordinator.select(target)
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
