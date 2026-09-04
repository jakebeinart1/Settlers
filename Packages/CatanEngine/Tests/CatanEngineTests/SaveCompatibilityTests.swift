import Testing
import Foundation
@testable import CatanEngine

/// Guards the decoding path that stops a schema change from silently deleting
/// every player's in-progress game.
///
/// `GameState` used the synthesized `init(from:)`, which calls `decode` (not
/// `decodeIfPresent`) for non-optional properties. A save written before a
/// property existed therefore failed to decode outright; `GameStore.load()`
/// swallowed that with `try?`, returned nil, and the app started a fresh game
/// with no message. That is not hypothetical - it already happened in the
/// field when `tradesAcceptedThisTurn` was added.

/// Encodes a real game state and removes `keys` from the JSON, simulating a
/// save written by an older build that predates those fields.
private func encodeOmitting(_ keys: [String], from state: GameState) throws -> Data {
    let data = try JSONEncoder().encode(state)
    var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    for key in keys { object.removeValue(forKey: key) }
    return try JSONSerialization.data(withJSONObject: object)
}

@Test func aSaveMissingFieldsAddedAfterItWasWrittenStillLoads() throws {
    var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 5), seed: 5)
    try RulesEngine.apply(.placeInitialSettlement(
        RulesEngine.legalMoves(for: state).compactMap {
            if case .placeInitialSettlement(let v) = $0 { return v } else { return nil }
        }.first!), by: state.players[0].id, to: &state)

    // Every field added since the first shipped save, plus the one this change
    // introduces (`declinedTradeOffersThisTurn`). An older save has none of them.
    let laterAdditions = ["schemaVersion", "rng", "tradesAcceptedThisTurn",
                          "devCardsBoughtThisTurn", "devCardPlayedThisTurn", "log",
                          "declinedTradeOffersThisTurn"]
    for key in laterAdditions {
        let trimmed = try encodeOmitting([key], from: state)
        #expect(throws: Never.self, "a save without '\(key)' must still load") {
            _ = try JSONDecoder().decode(GameState.self, from: trimmed)
        }
    }

    // And all of them missing at once - i.e. the oldest save shape.
    let oldest = try encodeOmitting(laterAdditions, from: state)
    let decoded = try JSONDecoder().decode(GameState.self, from: oldest)
    #expect(decoded.schemaVersion == 0, "a save with no version marker should read as v0")
    #expect(decoded.players.count == state.players.count)
    #expect(decoded.board.tiles.count == state.board.tiles.count)
}

@Test func aSaveMissingTheBoardIsRejectedRatherThanSilentlyDiscarded() throws {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    // `board`, `players` and `phase` describe no recoverable game if absent,
    // so decoding must throw and let the caller report a corrupt save - as
    // opposed to the permissive fields above, which default.
    for key in ["board", "players", "phase"] {
        let trimmed = try encodeOmitting([key], from: state)
        #expect(throws: (any Error).self, "a save without '\(key)' is unrecoverable and must throw") {
            _ = try JSONDecoder().decode(GameState.self, from: trimmed)
        }
    }
}

@Test func aFreshGameCarriesTheCurrentSchemaVersion() {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    #expect(state.schemaVersion == GameState.currentSchemaVersion)
}
