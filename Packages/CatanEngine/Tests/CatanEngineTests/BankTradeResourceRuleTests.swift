import Testing
@testable import CatanEngine

/// Exercises the shared validator and both mutation entry points. A bank trade
/// can balance at the port's rate yet remain illegal because its sides overlap.
@Suite struct BankTradeResourceRuleTests {
    private let player = PlayerID(index: 0)

    private func table(rate: Int = 4) throws -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 927)
        state.phase = .mainTurn(playerIndex: player.index)
        state.players[0].resources = [.brick: 8, .lumber: 8]
        state.bank[.brick] = 11
        state.bank[.lumber] = 11
        if rate < 4 {
            let kind: PortKind = rate == 2 ? .resource(.brick) : .generic
            let port = try #require(state.board.ports.first { $0.kind == kind })
            state.players[0].settlements = [port.vertexA]
        }
        return state
    }

    @Test(arguments: [2, 3, 4], [1, 2])
    func sameResourceBankTradeIsRejectedWithoutMutation(rate: Int, quantity: Int) throws {
        let state = try table(rate: rate)
        #expect(Trading.bestRate(for: .brick, player: player, state: state) == rate)
        expectRejected(give: [.brick: rate * quantity], get: [.brick: quantity], state: state)
    }

    @Test(arguments: [2, 3, 4])
    func mixedBankTradesWithOverlapAreRejectedWithoutMutation(rate: Int) throws {
        let state = try table(rate: rate)
        let lumberRate = rate == 3 ? 3 : 4
        // Each exchange buys two cards at valid rates; only the overlap is illegal.
        expectRejected(give: [.brick: rate * 2], get: [.brick: 1, .ore: 1], state: state)
        expectRejected(give: [.brick: rate, .lumber: lumberRate], get: [.brick: 2], state: state)
        expectRejected(give: [.brick: rate, .lumber: lumberRate], get: [.brick: 1, .ore: 1], state: state)
    }

    @Test(arguments: [2, 3, 4])
    func disjointCompoundBankTradeStillAppliesAtEachResourcesRate(rate: Int) throws {
        var state = try table(rate: rate)
        let lumberRate = rate == 3 ? 3 : 4
        let give: [Resource: Int] = [.brick: rate, .lumber: lumberRate]
        let get: [Resource: Int] = [.ore: 1, .grain: 1]
        #expect(Trading.bankTradeProblem(give: give, get: get, by: player, state: state) == nil)

        let events = try RulesEngine.apply(.bankTrade(give: give, get: get), by: player, to: &state)

        #expect(events == [.tradedWithBank(player, gave: give, got: get)])
        #expect(state.players[0].resources == [.brick: 8 - rate, .lumber: 8 - lumberRate, .ore: 1, .grain: 1])
        #expect(state.bank == [.brick: 11 + rate, .lumber: 11 + lumberRate, .ore: 18, .grain: 18, .wool: 19])
    }

    @Test func emptyAndNonpositiveBankTradesAreRejectedWithoutMutation() throws {
        let state = try table()
        expectRejected(give: [:], get: [.ore: 1], state: state)
        expectRejected(give: [.brick: 4], get: [:], state: state)
        expectRejected(give: [:], get: [:], state: state)
        // Zero entries must be rejected even alongside an otherwise valid trade.
        expectRejected(give: [.brick: 4, .lumber: 0], get: [.ore: 1], state: state)
        expectRejected(give: [.brick: 4], get: [.ore: 1, .grain: 0], state: state)
        expectRejected(give: [.brick: -4, .lumber: 8], get: [.ore: 1], state: state)
        expectRejected(give: [.brick: 4], get: [.ore: 2, .grain: -1], state: state)
    }

    private func expectRejected(give: [Resource: Int], get: [Resource: Int], state: GameState) {
        var state = state
        let before = state
        let move = GameMove.bankTrade(give: give, get: get)
        #expect(Trading.bankTradeProblem(give: give, get: get, by: player, state: state) == .illegalPlacement)
        #expect(!RulesEngine.legalMoves(for: state).contains(move))
        #expect(throws: MoveError.illegalPlacement) {
            try Trading.bankTrade(give: give, get: get, by: player, state: &state)
        }
        #expect(state == before)
        #expect(throws: MoveError.illegalPlacement) {
            try RulesEngine.apply(move, by: player, to: &state)
        }
        #expect(state == before)
    }
}
