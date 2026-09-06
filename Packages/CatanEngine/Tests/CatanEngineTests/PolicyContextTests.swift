import Foundation
import Testing
@testable import CatanEngine

/// Exact policy context must survive saves without inventing pre-feature
/// history or letting a failed move consume a turn or proposal.
struct PolicyContextTests {
    @Test(arguments: [3, 4])
    func freshGamesStartWithKnownEmptyContext(playerCount: Int) {
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1, playerCount: playerCount)
        #expect(state.schemaVersion == 4)
        #expect(state.completedTurnCount == 0)
        #expect(state.tradesProposedThisTurn == 0)
    }

    @Test(arguments: [Int?.some(0), .some(19), .none])
    func explicitInitializerContextRoundTrips(completedTurns: Int?) throws {
        let initial = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
        let state = GameState(
            board: initial.board, players: initial.players, phase: initial.phase,
            bank: initial.bank, devCardDeck: initial.devCardDeck, rng: initial.rng,
            completedTurnCount: completedTurns, tradesProposedThisTurn: 2
        )
        let restored = try roundTrip(state)
        #expect(restored == state)
        #expect(restored.completedTurnCount == completedTurns)
        #expect(restored.tradesProposedThisTurn == 2)
    }

    @Test func legacyMissingContextRemainsUnknownAfterResumingAndSaving() throws {
        var object = try jsonObject(mainTurnState())
        object["schemaVersion"] = 3
        object.removeValue(forKey: "completedTurnCount")
        object.removeValue(forKey: "tradesProposedThisTurn")
        var restored = try decode(object)
        #expect(restored.schemaVersion == 3)
        #expect(restored.completedTurnCount == nil)
        #expect(restored.tradesProposedThisTurn == 0)

        let actor = restored.players[0].id
        try RulesEngine.apply(.proposeTrade(offer(from: actor)), by: actor, to: &restored)
        #expect(restored.tradesProposedThisTurn == 1)
        try RulesEngine.apply(.endTurn, by: actor, to: &restored)
        #expect(restored.completedTurnCount == nil)
        #expect(restored.tradesProposedThisTurn == 0)
        #expect(try roundTrip(restored) == restored)
    }

    @Test func nullContextDecodesWithTheSameLegacyDefaults() throws {
        var object = try jsonObject(mainTurnState())
        object["completedTurnCount"] = NSNull()
        object["tradesProposedThisTurn"] = NSNull()
        let restored = try decode(object)
        #expect(restored.completedTurnCount == nil)
        #expect(restored.tradesProposedThisTurn == 0)
    }

    @Test func setupAndRollingDoNotCompleteTurns() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
        while case .setupForward = state.phase {
            try placeFirstSetupMove(in: &state)
        }
        while case .setupBackward = state.phase {
            try placeFirstSetupMove(in: &state)
        }
        #expect(state.phase == .rollDice(playerIndex: 0))
        try RulesEngine.apply(.rollDice, by: state.players[0].id, to: &state)
        #expect(state.completedTurnCount == 0)
        #expect(state.tradesProposedThisTurn == 0)
    }

    @Test(arguments: [false, true])
    func proposalsCountIndependentlyOfTheirResponses(accept: Bool) throws {
        var state = mainTurnState()
        let actor = state.players[0].id
        let proposed = offer(from: actor)
        try RulesEngine.apply(.proposeTrade(proposed), by: actor, to: &state)
        #expect(state.tradesProposedThisTurn == 1)
        try RulesEngine.apply(.respondToTrade(offerID: proposed.id, accept: accept),
                              by: state.players[1].id, to: &state)
        #expect(state.tradesProposedThisTurn == 1)
        try RulesEngine.apply(.proposeTrade(offer(from: actor)), by: actor, to: &state)
        #expect(state.tradesProposedThisTurn == 2)
        #expect(state.completedTurnCount == 7)
        #expect(try roundTrip(state) == state)
    }

    @Test func successfulEndTurnAdvancesKnownHistoryAndResetsProposals() throws {
        var state = mainTurnState()
        let actor = state.players[0].id
        try RulesEngine.apply(.proposeTrade(offer(from: actor)), by: actor, to: &state)
        try RulesEngine.apply(.endTurn, by: actor, to: &state)
        #expect(state.completedTurnCount == 8)
        #expect(state.tradesProposedThisTurn == 0)
        #expect(state.phase == .rollDice(playerIndex: 1))
        #expect(state.pendingTradeOffers.isEmpty)
        #expect(try roundTrip(state) == state)
    }

    @Test func rejectedProposalsAndEndTurnsLeaveTheWholeStateUnchanged() throws {
        let actor = PlayerID(index: 0)
        let other = PlayerID(index: 1)
        let wrongAuthor = offer(from: other)
        let unaffordable = TradeOffer(from: actor, give: [.brick: 5], want: [.grain: 1])
        let invalid = TradeOffer(from: actor, give: [.brick: -1], want: [.grain: 1])
        let cases: [(GamePhase, PlayerID, GameMove)] = [
            (.mainTurn(playerIndex: 0), other, .endTurn),
            (.rollDice(playerIndex: 0), actor, .endTurn),
            (.mainTurn(playerIndex: 0), other, .proposeTrade(wrongAuthor)),
            (.mainTurn(playerIndex: 0), actor, .proposeTrade(wrongAuthor)),
            (.mainTurn(playerIndex: 0), actor, .proposeTrade(unaffordable)),
            (.mainTurn(playerIndex: 0), actor, .proposeTrade(invalid)),
            (.rollDice(playerIndex: 0), actor, .proposeTrade(offer(from: actor))),
        ]
        for (phase, seat, move) in cases {
            var state = mainTurnState()
            state.phase = phase
            state.tradesProposedThisTurn = 2
            let before = state
            #expect(throws: MoveError.self) { try RulesEngine.apply(move, by: seat, to: &state) }
            #expect(state == before)
        }
    }

    @Test func contextDoesNotChangeLegalMovesOrOtherActions() throws {
        var state = mainTurnState()
        let legal = RulesEngine.legalMoves(for: state)
        state.completedTurnCount = nil
        state.tradesProposedThisTurn = 12
        #expect(RulesEngine.legalMoves(for: state) == legal)
        try RulesEngine.apply(.bankTrade(give: [.brick: 4], get: [.ore: 1]),
                              by: state.players[0].id, to: &state)
        #expect(state.completedTurnCount == nil)
        #expect(state.tradesProposedThisTurn == 12)
    }

    private func mainTurnState() -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
        state.phase = .mainTurn(playerIndex: 0)
        state.completedTurnCount = 7
        state.players[0].resources = [.brick: 4]
        state.players[1].resources = [.grain: 2]
        state.bank[.brick] = 15
        state.bank[.grain] = 17
        return state
    }

    private func offer(from actor: PlayerID) -> TradeOffer {
        TradeOffer.enumerated(from: actor, give: [.brick: 1], want: [.grain: 1])
    }

    private func placeFirstSetupMove(in state: inout GameState) throws {
        let index = try #require(state.phase.awaitingSeatIndex)
        let move = try #require(RulesEngine.legalMoves(for: state).first)
        try RulesEngine.apply(move, by: state.players[index].id, to: &state)
    }

    private func roundTrip(_ state: GameState) throws -> GameState {
        try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state))
    }

    private func jsonObject(_ state: GameState) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> GameState {
        try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
