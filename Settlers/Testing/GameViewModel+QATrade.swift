#if DEBUG
import CatanEngine

extension GameViewModel {
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
        fixture.players[human.index].resources[.grain] = 1
        fixture.players[bot.index].resources[.brick] = 1
        fixture.bank[.grain] = 18
        fixture.bank[.brick] = 18
        fixture.phase = .mainTurn(playerIndex: human.index)

        let offer = TradeOffer(from: bot, give: [.brick: 1], want: [.grain: 1])
        do {
            try Trading.proposeTrade(offer, state: &fixture)
        } catch {
            preconditionFailure("failed to construct incoming-trade QA fixture: \(error)")
        }
        replaceStateForTesting(fixture, humanSeat: human)
        return offer
    }
}
#endif
