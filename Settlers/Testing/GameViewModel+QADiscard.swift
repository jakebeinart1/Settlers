#if DEBUG
import CatanEngine

extension GameViewModel {
    /// A conserved eight-card hand owing an exact four-card discard. The real
    /// editor and engine commit remain untouched; only the otherwise rare
    /// position is made deterministic for visual and tap-driven QA.
    func qaPrepareMandatoryDiscard() {
        let human = humanPlayer
        var fixture = GameSetup.newGame(
            board: BoardGenerator.standard(),
            seed: 4_204,
            playerCount: state.players.count,
            victoryPointTarget: state.victoryPointTarget
        )
        completeInitialPlacements(in: &fixture)
        for index in fixture.players.indices {
            fixture.players[index].resources = [:]
        }
        fixture.bank = Dictionary(uniqueKeysWithValues: Resource.allCases.map { ($0, 19) })
        let holding: [Resource: Int] = [.brick: 4, .lumber: 2, .grain: 1, .wool: 1]
        fixture.players[human.index].resources = holding
        for (resource, count) in holding {
            fixture.bank[resource, default: 0] -= count
        }
        fixture.lastDiceRoll = 7
        fixture.robberMoverIndex = human.index
        fixture.phase = .discarding(pending: [human])
        replaceStateForTesting(fixture, humanSeat: human)
    }

    /// Builds the deterministic position through legal setup moves so the
    /// inspection screenshot exercises real roads and settlements instead of
    /// an empty board that cannot reveal piece-legibility regressions.
    private func completeInitialPlacements(in state: inout GameState) {
        while true {
            let seat: PlayerID
            switch state.phase {
            case .setupForward(let index), .setupBackward(let index):
                seat = PlayerID(index: index)
            default:
                return
            }
            guard let move = RulesEngine.legalMoves(for: state, seat: seat).first else {
                preconditionFailure("QA discard fixture reached setup with no legal move")
            }
            do {
                try RulesEngine.apply(move, by: seat, to: &state)
            } catch {
                preconditionFailure("QA discard fixture could not complete setup: \(error)")
            }
        }
    }
}
#endif
