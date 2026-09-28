#if DEBUG
import CatanEngine

extension GameViewModel {
    /// Conserved 2:1 position from the reported six-grain / three-ore trade.
    func qaPrepareBankTradePosition() {
        var fixture = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4_308)
        let port = fixture.board.ports.first { $0.kind == .resource(.grain) }!
        fixture.players[humanPlayer.index].settlements.insert(port.vertexA)
        fixture.players[humanPlayer.index].resources = [.grain: 7]
        fixture.bank[.grain, default: 0] -= 7
        // A real, generously priced player proposal can use the same fixture.
        // Responses still run the production bot evaluation, never a fake yes.
        for seat in fixture.players.indices where seat != humanPlayer.index {
            fixture.players[seat].resources = [.ore: 1]
            fixture.bank[.ore, default: 0] -= 1
        }
        fixture.phase = .mainTurn(playerIndex: humanPlayer.index)
        replaceStateForTesting(fixture, humanSeat: humanPlayer)
    }

    /// Installs a real pending bot offer with a conserved, deterministic hand.
    ///
    /// Unlike the old view-only fixture, accepting or rejecting this offer
    /// is present in engine state, so the response travels through
    /// `RulesEngine` and proves the interaction changes that state rather than
    /// merely dismissing a card.
    func qaSeedIncomingTrade() -> TradeOffer {
        let human = humanPlayer
        guard let bot = state.players.first(where: { !humanSeats.contains($0.id) })?.id else {
            preconditionFailure("incoming-trade QA requires at least one bot")
        }
        var fixture = state
        for index in fixture.players.indices {
            fixture.players[index].resources = [:]
        }
        fixture.bank = Dictionary(uniqueKeysWithValues: Resource.allCases.map { ($0, 19) })
        // The widest bundle the engine permits is four give types against one
        // want type: `maxComposedTradeGive` is 5 cards and `maxComposedTradeWant`
        // 3, and with only five resources a disjoint offer cannot spread further
        // than 4 + 1. Row width is driven by the number of *types*, not cards,
        // because `resourceDots` renders one swatch and a count per type.
        let bundling = QALaunchFlag.bundleOffer.isSet
        let give: [Resource: Int] = bundling
            ? [.brick: 2, .lumber: 1, .wool: 1, .ore: 1]
            : [.brick: 1]
        let want: [Resource: Int] = bundling ? [.grain: 3] : [.grain: 1]

        for (resource, count) in want {
            fixture.players[human.index].resources[resource] = count
            fixture.bank[resource, default: 19] -= count
        }
        for (resource, count) in give {
            fixture.players[bot.index].resources[resource] = count
            fixture.bank[resource, default: 19] -= count
        }
        fixture.phase = .mainTurn(playerIndex: human.index)

        let offer = TradeOffer(from: bot, give: give, want: want)
        do {
            try Trading.proposeTrade(offer, state: &fixture)
            if QALaunchFlag.queuedBotOffers.isSet {
                fixture.phase = .mainTurn(playerIndex: bot.index)
                fixture.players[human.index].resources[.grain, default: 0] += 1
                fixture.bank[.grain, default: 0] -= 1
                fixture.players[bot.index].resources[.brick, default: 0] += 2
                fixture.bank[.brick, default: 0] -= 2
                try Trading.proposeTrade(TradeOffer(from: bot, give: [.brick: 2], want: [.grain: 1]), state: &fixture)
            }
        } catch {
            preconditionFailure("failed to construct incoming-trade QA fixture: \(error)")
        }
        replaceStateForTesting(fixture, humanSeat: human)
        return offer
    }
}
#endif
