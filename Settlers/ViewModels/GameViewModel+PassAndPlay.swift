import CatanEngine

@MainActor
extension GameViewModel {
    /// The human the game is waiting on, if it is waiting on one.
    ///
    /// `.discarding` is handled separately because `GamePhase.awaitingSeatIndex`
    /// answers `nil` for it - correctly, since the phase is genuinely
    /// multi-seat and no single chair owns it. Reading only `awaitingSeatIndex`
    /// deadlocked a hot-seat game outright: after a 7, the player holding the
    /// phone discarded, the other human stayed in `pending`, and because
    /// `awaitingSeatIndex` was `nil` no handoff cover appeared and
    /// `humanPlayer` never moved - so the discard sheet (which is gated on
    /// `humanPlayer` being pending) went away, while `GameSession.nextActor()`
    /// sat on `.awaitingExternalSeat` for a seat with no way to act.
    public var seatOwedATurn: PlayerID? {
        // Private acknowledgements outrank ordinary turn routing. A winning
        // Victory Point or third Knight can end the game immediately; after a
        // cold hot-seat resume there is otherwise no phase-owned seat left to
        // tell the cover who may safely read the result.
        if let owner = pendingDevCardReveal?.owner, humanSeats.contains(owner) { return owner }
        if let owner = pendingDevCardResolution?.owner, humanSeats.contains(owner) { return owner }
        if let reader = pendingShipCapture?.reader, humanSeats.contains(reader) { return reader }
        if let responder = owedTradeResponseSeat { return responder }
        if case .discarding(let pending) = state.phase {
            // Sorted: `pending` is a `Set` and Swift seeds hash order per
            // process, so `.first` on it would pick a different seat between
            // launches. The holder of the phone goes first when they owe one,
            // so nobody is asked to pass a phone they still have to use.
            let owing = pending.sorted().filter { humanSeats.contains($0) }
            if let seatAtDevice, owing.contains(seatAtDevice) { return seatAtDevice }
            return owing.first
        }
        guard let owed = state.phase.awaitingSeatIndex.map({ PlayerID(index: $0) }),
              humanSeats.contains(owed) else { return nil }
        return owed
    }

    var isLocalMultiplayer: Bool { humanSeats.count > 1 }

    /// No seat is claimed on a cold resume or while the device is inactive.
    /// A bot may keep playing while the cover waits for a human decision.
    var needsLocalHandoff: Bool {
        guard isLocalMultiplayer else { return false }
        guard appIsActive, let seatAtDevice else { return true }
        return seatOwedATurn.map { $0 != seatAtDevice } ?? false
    }

    var localTurnOwner: PlayerID? {
        let index: Int?
        switch state.phase {
        case .discarding: index = state.robberMoverIndex
        case .choosingResource: index = state.naval?.productionRollerIndex
        default: index = state.phase.awaitingSeatIndex
        }
        return index.map { PlayerID(index: $0) }
    }

    @discardableResult
    func claimLocalDevice(for seat: PlayerID) -> Bool {
        guard appIsActive, needsLocalHandoff, seatOwedATurn == seat else { return false }
        releaseLocalDevice()
        seatAtDevice = seat
        reconcileBoardDecision()
        return true
    }

    func releaseLocalDevice() {
        guard isLocalMultiplayer else { return }
        seatAtDevice = nil
        resourceProductionFeedback = nil
        gameplayFeedback.clear()
        boardDecisionCoordinator.clear()
        resetDiscardPresentation()
        navalHarvestDraft.reset()
    }
}
