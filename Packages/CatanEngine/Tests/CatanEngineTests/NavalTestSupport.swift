import Foundation
import Testing
@testable import CatanEngine

enum NavalTestSupport {
    static func ready(seed: UInt64 = 73, playerCount: Int = 4, fog: Bool = true, rulesVersion: Int? = nil) throws -> GameState {
        var state = Naval.newGame(seed: seed, playerCount: playerCount, options: NavalOptions(fogEnabled: fog))
        if let rulesVersion { state.naval?.rulesVersion = rulesVersion }
        while state.phase.isSetup {
            let index = try #require(state.phase.awaitingSeatIndex)
            let move = try #require(RulesEngine.legalMoves(for: state).first)
            try RulesEngine.apply(move, by: state.players[index].id, to: &state)
        }
        state.phase = .mainTurn(playerIndex: 0)
        return state
    }

    static func fund(_ costs: [Resource: Int], player: Int = 0, in state: inout GameState) {
        for resource in Resource.allCases {
            let amount = costs[resource, default: 0]
            state.players[player].resources[resource, default: 0] += amount
            state.bank[resource, default: 0] -= amount
        }
    }

    @discardableResult
    static func roll(_ total: Int, player: Int, state: inout GameState) throws -> [GameEvent] {
        try prepareRoll(total, player: player, state: &state)
        return try RulesEngine.apply(.rollDice, by: state.players[player].id, to: &state)
    }

    /// Exposes the pre-roll baseline so exact replay checks use the same seeded
    /// dice preparation as ordinary Naval rule tests, without duplicating it.
    static func prepareRoll(_ total: Int, player: Int, state: inout GameState) throws {
        let seed = try #require((0..<1_000).first { seed in
            var rng = RandomSource(seed: UInt64(seed))
            return Int.random(in: 1...6, using: &rng) + Int.random(in: 1...6, using: &rng) == total
        })
        state.rng = RandomSource(seed: UInt64(seed))
        state.phase = .rollDice(playerIndex: player)
    }

    static func addShip(at coordinate: HexCoordinate, player: Int, steps: Int? = nil, in state: inout GameState) {
        let id = state.naval!.nextShipID
        let remaining = steps ?? Naval.movementPerTurn(in: state)
        state.naval?.ships.append(Ship(id: id, owner: state.players[player].id, coordinate: coordinate, stepsRemaining: remaining))
        state.naval?.nextShipID += 1
        state.naval?.hullsBuilt[state.players[player].id, default: 0] += 1
        _ = Naval.reveal(around: [coordinate], by: state.players[player].id, in: &state)
    }
}
