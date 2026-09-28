import Testing
import CatanEngine

struct TradeDraftConstraintTests {
    private let player = PlayerID(index: 2)

    @Test(arguments: [Trading.DraftMode.players, .bank])
    func sameResourceIsExcludedInEitherDraftMode(_ mode: Trading.DraftMode) {
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 927)
        #expect(Trading.draftProblem(give: [.brick: 4], get: [.brick: 1], mode: mode,
                                    by: player, state: state) == .overlappingResources)
    }

    @Test(arguments: [2, 3, 4])
    func bankDraftNamesTheRequiredBundleAtThePlayersActualPortRate(_ rate: Int) throws {
        let state = try table(rate: rate)
        #expect(Trading.draftProblem(give: [.brick: rate + 1], get: [:], mode: .bank,
                                    by: player, state: state) == .invalidBankBundle(resource: .brick, rate: rate))
        #expect(Trading.draftProblem(give: [.brick: rate * 2], get: [:], mode: .bank,
                                    by: player, state: state) == nil)
        #expect(Trading.draftProblem(give: [.brick: rate + 1], get: [.ore: 1], mode: .players,
                                    by: player, state: state) == nil, "Domestic drafts have no port-rate constraint")
    }

    @Test func bankDraftChecksEachResourcesOwnRateInACompoundTrade() throws {
        let state = try table(rate: 2)
        #expect(Trading.draftProblem(give: [.brick: 4, .lumber: 8], get: [.ore: 4], mode: .bank,
                                    by: player, state: state) == nil)
        #expect(Trading.draftProblem(give: [.brick: 4, .lumber: 3], get: [.ore: 4], mode: .bank,
                                    by: player, state: state) == .invalidBankBundle(resource: .lumber, rate: 4))
        #expect(Trading.bankTradeProblem(give: [.brick: 4, .lumber: 3], get: [.ore: 4],
                                        by: player, state: state) == .illegalPlacement)
    }

    @Test func overlapPrecedesStableResourceOrderForBundleErrorsWithoutMutatingState() throws {
        let state = try table()
        let before = state
        let drafts: [[Resource: Int]] = [[.wool: 1, .brick: 1], [.brick: 1, .wool: 1]]
        for give in drafts {
            #expect(Trading.draftProblem(give: give, get: [.ore: 1], mode: .bank,
                                        by: player, state: state) == .invalidBankBundle(resource: .brick, rate: 4))
            #expect(Trading.draftProblem(give: give, get: [.wool: 1], mode: .bank,
                                        by: player, state: state) == .overlappingResources)
        }
        #expect(state == before)
    }

    @Test func clearDraftConstraintsAreNotPermissionToCommit() throws {
        let state = try table()
        let drafts: [(give: [Resource: Int], get: [Resource: Int], problem: MoveError)] = [
            ([:], [:], .illegalPlacement),
            ([.brick: 4], [:], .illegalPlacement),
            ([:], [.ore: 1], .illegalPlacement),
            ([.brick: 4], [.ore: 2], .illegalPlacement),
            ([.brick: 12], [.ore: 3], .insufficientResources),
            ([.brick: 4, .wool: 0], [.ore: 1], .illegalPlacement),
            ([.brick: -4], [.ore: 1], .illegalPlacement)
        ]
        for draft in drafts {
            #expect(Trading.draftProblem(give: draft.give, get: draft.get, mode: .bank,
                                        by: player, state: state) == nil)
            #expect(Trading.bankTradeProblem(give: draft.give, get: draft.get,
                                            by: player, state: state) == draft.problem)
        }
        var depleted = state
        depleted.bank[.ore] = 0
        #expect(Trading.draftProblem(give: [.brick: 4], get: [.ore: 1], mode: .bank,
                                    by: player, state: depleted) == nil)
        #expect(Trading.bankTradeProblem(give: [.brick: 4], get: [.ore: 1],
                                        by: player, state: depleted) == .bankCannotSupply(.ore))
    }

    @Test(arguments: [1, 2])
    func historicalOverlappingDomesticTradesStillApplyAndReplay(_ rulesVersion: Int) throws {
        var initial = try table()
        let responder = PlayerID(index: 0)
        initial.players[responder.index].resources = [.brick: 2]
        initial.bank[.brick] = 9
        let offer = TradeOffer(from: player, give: [.brick: 2], want: [.brick: 1])
        #expect(Trading.draftProblem(give: offer.give, get: offer.want, mode: .players,
                                    by: player, state: initial) == .overlappingResources)
        var applied = initial
        let proposed = try RulesEngine.apply(.proposeTrade(offer), by: player, to: &applied)
        let accepted = try RulesEngine.apply(.respondToTrade(offerID: offer.id, accept: true), by: responder, to: &applied)
        #expect(proposed == [.proposedTrade(player, give: [.brick: 2], want: [.brick: 1])])
        #expect(accepted == [.acceptedTrade(responder, from: player, gave: [.brick: 1], got: [.brick: 2])])
        #expect(applied.players[player.index].resources == [.brick: 7])
        #expect(applied.players[responder.index].resources == [.brick: 3])
        #expect(applied.bank == initial.bank)
        #expect(applied.pendingTradeOffers.isEmpty)

        var replayed = initial
        let replayProposal = try RulesEngine.replay(.proposeTrade(offer), by: player,
                                                    rulesVersion: rulesVersion, to: &replayed)
        let replayAcceptance = try RulesEngine.replay(.respondToTrade(offerID: offer.id, accept: true), by: responder,
                                                      rulesVersion: rulesVersion, to: &replayed)
        #expect(replayProposal == proposed)
        #expect(replayAcceptance == accepted)
        #expect(replayed == applied)
    }

    private func table(rate: Int = 4) throws -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 927)
        state.phase = .mainTurn(playerIndex: player.index)
        state.players[player.index].resources = [.brick: 8]
        state.bank[.brick] = 11
        if rate < 4 {
            let kind: PortKind = rate == 2 ? .resource(.brick) : .generic
            let port = try #require(state.board.ports.first { $0.kind == kind })
            state.players[player.index].cities = [port.vertexA]
        }
        return state
    }
}
