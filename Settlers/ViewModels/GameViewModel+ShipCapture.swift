import Foundation
import CatanEngine

extension GameViewModel {
    /// Acknowledges the presentation only. Publication follows durable write;
    /// a failed acknowledgement leaves the transfer receipt available on retry.
    @discardableResult
    public func dismissShipCapture() -> Bool {
        guard checkpointDocument != nil else { return false }
        do {
            try acknowledgeShipCapture()
            Task { await runBotTurnIfNeeded() }
            return true
        } catch {
            _ = reportPersistenceFailure(error)
            return false
        }
    }

    func acknowledgeShipCapture() throws {
        guard let document = checkpointDocument else { throw MatchCheckpointStore.StoreError.staleRevision }
        try commitDocument(document.dismissingShipCapture())
        pendingShipCapture = nil
    }
}
