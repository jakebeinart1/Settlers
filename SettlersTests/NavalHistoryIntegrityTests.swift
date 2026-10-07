import Foundation
import Testing
import CatanEngine
@testable import Settlers

/// A coherent snapshot still needs the moves that actually produced it. These
/// mutations remain valid engine positions but must never replace recorded play.
@MainActor
@Suite struct NavalHistoryIntegrityTests {
    private enum Mutation: CaseIterable {
        case position, controller, movement, discovery, stock, colony
    }

    @Test(arguments: Mutation.allCases)
    private func unrecordedNavalChangesFailBothColdAndIncrementalValidation(_ mutation: Mutation) throws {
        let initial = try NavalQAFixture.make(.harvest)
        let baseline = MatchCheckpoint(id: UUID(), initialState: initial, setup: setup(for: initial))
        var session = GameSession(state: initial, policies: [:], policySeed: 1)
        let step = try session.applyExternal(.chooseResource(.ore), by: PlayerID(index: 0))
        let honest = try MatchCheckpointDocument(activeMatch: baseline)
            .recording(step, session: session.checkpoint, elapsedSeconds: 1)
        let active = try #require(honest.activeMatch)
        try active.validateHistory()
        var state = active.state
        try mutate(mutation, state: &state)
        #expect(Naval.validationProblem(in: state) == nil, "The counterexample must be an otherwise valid state")
        let corrupted = try replacingState(in: active, with: state)
        #expect(throws: MatchCheckpointStore.StoreError.inconsistentHistory) { try corrupted.validateHistory() }
        #expect(throws: MatchCheckpointStore.StoreError.inconsistentHistory) {
            try corrupted.validateHistory(succeeding: baseline)
        }
    }

    private func setup(for state: GameState) -> MatchSetup {
        let seats = state.players.map {
            MatchSetup.Seat(index: $0.id.index, isHuman: true, name: "Player \($0.id.index + 1)",
                           civilization: Civilization.allCases[$0.id.index])
        }
        var setup = MatchSetup(seats: seats, mode: .naval, victoryPointTarget: 14,
                               randomizedBoard: true, randomizeSeatOrder: false)
        setup.navalOptions = state.naval!.options
        return setup
    }

    private func mutate(_ mutation: Mutation, state: inout GameState) throws {
        let owner = PlayerID(index: 0)
        switch mutation {
        case .position:
            let destination = try #require(state.board.tiles.first { tile in
                tile.kind == .sea && tile.coordinate != state.naval!.ships[0].coordinate
                    && state.board.tiles.filter { $0.coordinate.distance(to: tile.coordinate) <= 2 }
                        .allSatisfy { state.naval!.revealed.contains($0.coordinate) }
            })
            state.naval!.ships[0].coordinate = destination.coordinate
        case .controller: state.naval!.ships[0].owner = PlayerID(index: 1)
        case .movement: state.naval!.ships[0].stepsRemaining = 3
        case .discovery:
            let hidden = try #require(state.board.tiles.first { !state.naval!.revealed.contains($0.coordinate) })
            state.naval!.revealed.insert(hidden.coordinate)
        case .stock:
            state.naval!.hullsBuilt[owner] = 0
            state.naval!.hullsBuilt[PlayerID(index: 1)] = 1
        case .colony:
            let island = try #require((1...4).first { !state.naval!.colonizedIslands[owner, default: []].contains($0) })
            state.naval!.colonizedIslands[owner, default: []].insert(island)
            state.naval!.colonyPoints[owner] = 2
        }
    }

    private func replacingState(in match: MatchCheckpoint, with state: GameState) throws -> MatchCheckpoint {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(match)) as? [String: Any])
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
        object["state"] = encoded
        var session = try #require(object["sessionCheckpoint"] as? [String: Any])
        session["state"] = encoded
        object["sessionCheckpoint"] = session
        return try JSONDecoder().decode(MatchCheckpoint.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
