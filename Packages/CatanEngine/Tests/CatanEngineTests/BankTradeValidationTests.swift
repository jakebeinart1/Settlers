import Testing
@testable import CatanEngine

/// Covers the bank-trade validation the trade popup now shares with the
/// engine. The reported bug was that the popup's own copy of the rate
/// arithmetic never checked the bank's stock: the button went gold, the hint
/// said "Ready to trade", and the tap returned "You don't have enough
/// resources for that" while the player sat holding the cards they were
/// spending. The earlier investigation missed it because it only ever tried a
/// full-bank 4:1 trade.

private func stateWithHumanHolding(_ hand: [Resource: Int], bank: [Resource: Int]) -> GameState {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    state.phase = .mainTurn(playerIndex: 0)
    state.players[0].resources = hand
    state.bank = bank
    return state
}

@Test func bankTradeIsRejectedWhenTheBankCannotSupplyTheWantedResource() {
    // Four brick in hand, no port, and an ore-less bank: the rate maths
    // balances at 4:1, so only the bank check can catch this.
    let state = stateWithHumanHolding([.brick: 4], bank: [.ore: 0, .brick: 19])
    let problem = Trading.bankTradeProblem(give: [.brick: 4], get: [.ore: 1],
                                           by: state.players[0].id, state: state)
    #expect(problem == .bankCannotSupply(.ore),
            "a depleted bank must be reported as such, not as the player's own shortage")
}

@Test func theRejectionMessageNamesTheBankRatherThanThePlayersHand() {
    let problem = MoveError.bankCannotSupply(.ore)
    let message = problem.errorDescription ?? ""
    #expect(message.lowercased().contains("bank"))
    #expect(!message.lowercased().contains("you don't have"),
            "the message must not blame the player's hand for the bank being empty")
}

@Test func aLegalBankTradeReportsNoProblemAndApplies() throws {
    var state = stateWithHumanHolding([.brick: 4], bank: [.ore: 5, .brick: 15])
    let player = state.players[0].id
    #expect(Trading.bankTradeProblem(give: [.brick: 4], get: [.ore: 1], by: player, state: state) == nil)

    try Trading.bankTrade(give: [.brick: 4], get: [.ore: 1], by: player, state: &state)
    #expect(state.players[0].resources[.brick] == 0)
    #expect(state.players[0].resources[.ore] == 1)
    #expect(state.bank[.brick] == 19)
    #expect(state.bank[.ore] == 4)
}

@Test func tradingAResourceForItselfIsRejected() {
    // 8 brick for 2 brick balances at 4:1, so the rate check alone accepts a
    // trade that only ever loses the player six cards.
    let state = stateWithHumanHolding([.brick: 8], bank: [.brick: 11])
    let problem = Trading.bankTradeProblem(give: [.brick: 8], get: [.brick: 2],
                                           by: state.players[0].id, state: state)
    #expect(problem != nil, "a resource may not be traded for itself")
}

@Test func validationAgreesWithWhatApplyingActuallyDoes() throws {
    // The popup enables its button from `bankTradeProblem`, so any state where
    // the two disagree is a button that lies. Sweep a range of piles.
    let hands: [[Resource: Int]] = [[.brick: 4], [.brick: 8], [.brick: 3], [.wool: 4, .brick: 4]]
    let banks: [[Resource: Int]] = [[:], [.ore: 0], [.ore: 1], [.ore: 19]]

    for hand in hands {
        for bank in banks {
            var state = stateWithHumanHolding(hand, bank: bank)
            let player = state.players[0].id
            let predicted = Trading.bankTradeProblem(give: [.brick: 4], get: [.ore: 1],
                                                     by: player, state: state)
            var applyThrew: MoveError?
            do { try Trading.bankTrade(give: [.brick: 4], get: [.ore: 1], by: player, state: &state) }
            catch let error as MoveError { applyThrew = error }

            let detail = "validation said \(String(describing: predicted)) but applying gave "
                + "\(String(describing: applyThrew)) for hand \(hand) bank \(bank)"
            #expect(predicted == applyThrew, "\(detail)")
        }
    }
}
