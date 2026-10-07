import Testing
import CatanEngine
@testable import Settlers

@MainActor
struct MonopolyCollectionPreviewTests {
    @Test(arguments: GameMode.allCases)
    func canonicalSuppliesCountOnlyCardsOutsideTheBankAndOwnHand(mode: GameMode) {
        let totals: [GameMode: Int] = [.classic: 19, .expanded: 38, .vast: 60, .naval: 38]
        let total = Ruleset.forMode(mode).bankPerResource
        #expect(total == totals[mode])
        let preview = MonopolyCollectionPreview(totalPerResource: total, bank: [.ore: total - 7], ownHand: [.ore: 2])
        #expect(preview.collectibleCount(for: .ore) == 5)
    }

    @Test(arguments: Resource.allCases)
    func emptyFullAndOwnerOnlyStockKeepExactZeroDistinctFromUnknown(resource: Resource) {
        let emptyBank = MonopolyCollectionPreview(totalPerResource: 38, bank: [resource: 0], ownHand: [resource: 2])
        #expect(emptyBank.collectibleCount(for: resource) == 36)
        let fullBank = MonopolyCollectionPreview(totalPerResource: 38, bank: [resource: 38], ownHand: [:])
        #expect(fullBank.collectibleCount(for: resource) == 0)
        let ownerOnly = MonopolyCollectionPreview(totalPerResource: 38, bank: [resource: 35], ownHand: [resource: 3])
        #expect(ownerOnly.collectibleCount(for: resource) == 0)
        #expect(ownerOnly.collectibleCount(for: Resource.allCases.first { $0 != resource }!) == nil)
    }

    @Test func absentLegacyBankIsUnknownButSparseOwnHandMeansZero() {
        let missingBank = MonopolyCollectionPreview(totalPerResource: 19, bank: [:], ownHand: [:])
        #expect(missingBank.collectibleCount(for: .wool) == nil)
        let sparseHand = MonopolyCollectionPreview(totalPerResource: 19, bank: [.wool: 15], ownHand: [:])
        #expect(sparseHand.collectibleCount(for: .wool) == 4)
    }

    @Test func impossibleInventoryReturnsUnknownWithoutClampingOrOverflow() {
        let invalid: [(total: Int, bank: Int, owned: Int)] = [
            (-1, 0, 0), (0, 0, 0), (19, -1, 0), (19, 20, 0),
            (19, 0, -1), (19, 0, 20), (19, 10, 10), (19, Int.max, 0),
        ]
        for input in invalid {
            let preview = MonopolyCollectionPreview(totalPerResource: input.total,
                                                    bank: [.ore: input.bank], ownHand: [.ore: input.owned])
            #expect(preview.collectibleCount(for: .ore) == nil)
        }
        let bounded = MonopolyCollectionPreview(totalPerResource: Int.max, bank: [.ore: Int.max], ownHand: [.ore: 0])
        #expect(bounded.collectibleCount(for: .ore) == 0)
    }

    @Test(arguments: GameMode.allCases, [3, 4])
    func previewEqualsActualCollectionAtSupportedTablesAndANonzeroSeat(mode: GameMode, playerCount: Int) throws {
        let initial = game(mode: mode, playerCount: playerCount)
        let owner = PlayerID(index: playerCount - 1)
        for resource in Resource.allCases {
            var state = initial
            fund(2, of: resource, to: owner, in: &state)
            fund(3, of: resource, to: PlayerID(index: 0), in: &state)
            fund(1, of: resource, to: PlayerID(index: 1), in: &state)
            state.phase = .rollDice(playerIndex: owner.index)
            let cardIndex = try #require(state.devCardDeck.firstIndex(of: .monopoly))
            state.devCardDeck.remove(at: cardIndex)
            state.players[owner.index].devCards = [.monopoly]
            let expected = try #require(preview(state, for: owner).collectibleCount(for: resource))
            let bank = state.bank
            #expect(expected == 4)
            #expect(try DevCards.playMonopoly(resource, by: owner, state: &state) == expected)
            #expect(state.bank == bank)
            #expect(state.players[owner.index].resources[resource] == 6)
            #expect(preview(state, for: owner).collectibleCount(for: resource) == 0)
        }
    }

    @Test(arguments: [1, 2, 3])
    func maskedNavalStateAndPrivateRedistributionKeepThePublicPreview(rulesVersion: Int) {
        var state = game(mode: .naval, playerCount: 4)
        state.naval?.rulesVersion = rulesVersion
        let owner = PlayerID(index: 2)
        fund(2, of: .ore, to: owner, in: &state)
        fund(2, of: .ore, to: PlayerID(index: 0), in: &state)
        fund(1, of: .grain, to: PlayerID(index: 0), in: &state)
        fund(1, of: .ore, to: PlayerID(index: 1), in: &state)
        fund(2, of: .grain, to: PlayerID(index: 1), in: &state)
        let masked = GameObservation(seat: owner, state: state, legalMoves: []).state
        #expect(masked.players[0].resources.isEmpty && masked.players[1].resources.isEmpty)
        for resource in Resource.allCases {
            #expect(preview(state, for: owner).collectibleCount(for: resource)
                    == preview(masked, for: owner).collectibleCount(for: resource))
        }
        state.players[0].resources = [.ore: 1, .grain: 2]
        state.players[1].resources = [.ore: 2, .grain: 1]
        #expect(GameObservation(seat: owner, state: state, legalMoves: []).state == masked)
        #expect(preview(state, for: owner).collectibleCount(for: .ore) == 3)
        #expect(preview(state, for: owner).collectibleCount(for: .grain) == 3)
    }

    @Test func conquestPurchaseReturnsPaymentToBankAndUpdatesCollectibleStock() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 26, variant: .conquest)
        let owner = PlayerID(index: 2)
        let rival = PlayerID(index: 0)
        fund(2, of: .ore, to: owner, in: &state)
        fund(4, of: .ore, to: rival, in: &state)
        state.phase = .mainTurn(playerIndex: rival.index)
        #expect(preview(state, for: owner).collectibleCount(for: .ore) == 4)
        try RulesEngine.apply(.buyArmyCard(paying: [.ore: 3]), by: rival, to: &state)
        #expect(preview(state, for: owner).collectibleCount(for: .ore) == 1)
        #expect(state.bank[.ore] == 16)
    }

    private func preview(_ state: GameState, for owner: PlayerID) -> MonopolyCollectionPreview {
        MonopolyCollectionPreview(totalPerResource: state.rules.bankPerResource,
                                  bank: state.bank, ownHand: state.players[owner.index].resources)
    }

    private func game(mode: GameMode, playerCount: Int) -> GameState {
        if mode == .naval { return Naval.newGame(seed: 26, playerCount: playerCount) }
        return GameSetup.newGame(board: BoardGenerator.standard(Ruleset.forMode(mode).board),
                                 seed: 26, playerCount: playerCount, mode: mode)
    }

    /// The fixture transfers real finite supply, so preview/payout agreement
    /// cannot pass because the test invented cards outside the bank.
    private func fund(_ amount: Int, of resource: Resource, to owner: PlayerID, in state: inout GameState) {
        precondition(state.bank[resource, default: 0] >= amount)
        state.bank[resource, default: 0] -= amount
        state.players[owner.index].resources[resource, default: 0] += amount
    }
}
