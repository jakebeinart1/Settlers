import Testing
import CatanEngine
@testable import CatanAI

/// Jake's trade rule (2026-10-25): refuse a trade the bot can tell helps the
/// proposer more, from public information only. These pin when it refuses;
/// the evidence is in `TradeGuardPolicy`'s doc comment and
/// docs/AI_summaries/2026-10-25-ladder-games.md.
@Suite struct TradeGuardTests {
    private let me = PlayerID(index: 0)
    private let rival = PlayerID(index: 1)

    @Test func theRevisionSeatsTheFrozenTradeGuard() {
        #expect(ExpertRevision.timingTradeGuardV1.policy.id == "evaluation-timing-trade-guard-v1")
        #expect(ExpertRevision.timingTradeGuardV1.policy is TradeGuardPolicy)
    }

    @Test func aTradeThatFinishesALevelRivalsCityIsRefused() throws {
        let (state, accept) = try offer(rivalHolds: [.ore: 2, .grain: 2], mySettlements: 1)
        #expect(TradeGuardPolicy.v1.refuses(accept, seat: me, state: state, ledger: ledger(rivalHolds: [.ore: 2, .grain: 2])))
    }

    @Test func aTradeThatBuildsNothingGoesAhead() throws {
        let (state, accept) = try offer(rivalHolds: [.brick: 1], mySettlements: 1)
        #expect(!TradeGuardPolicy.v1.refuses(accept, seat: me, state: state, ledger: ledger(rivalHolds: [.brick: 1])))
    }

    @Test func aRivalWellBehindMayStillTrade() throws {
        let (state, accept) = try offer(rivalHolds: [.ore: 2, .grain: 2], mySettlements: 3)
        #expect(!TradeGuardPolicy.v1.refuses(accept, seat: me, state: state, ledger: ledger(rivalHolds: [.ore: 2, .grain: 2])))
    }

    /// The rival's believed hand is all the guard reads: hidden cards it never sees.
    @Test func theRivalsRealHandIsNeverRead() throws {
        var (state, accept) = try offer(rivalHolds: [.brick: 1], mySettlements: 1)
        state.players[1].resources = [.ore: 2, .grain: 2, .wool: 1]
        #expect(!TradeGuardPolicy.v1.refuses(accept, seat: me, state: state, ledger: ledger(rivalHolds: [.brick: 1])))
    }

    /// The rival offers one wool for one ore, holding `rivalHolds` and one
    /// settlement; this seat holds `mySettlements` settlements and an ore.
    private func offer(rivalHolds: [Resource: Int], mySettlements: Int) throws
        -> (GameState, GameMove) {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 33)
        let corners = state.board.onBoardVertices.sorted()
        state.players[0].settlements = Set(corners.prefix(mySettlements * 3).enumerated().filter { $0.offset % 3 == 0 }.map(\.element))
        state.players[1].settlements = [try #require(corners.last)]
        state.players[0].resources = [.ore: 1]
        state.players[1].resources = rivalHolds.merging([.wool: 1]) { $0 + $1 }
        let trade = TradeOffer(from: rival, give: [.wool: 1], want: [.ore: 1])
        state.pendingTradeOffers = [trade]
        state.phase = .mainTurn(playerIndex: 1)
        return (state, .respondToTrade(offerID: trade.id, accept: true))
    }

    private func ledger(rivalHolds: [Resource: Int]) -> PublicLedger {
        let known = rivalHolds.merging([.wool: 1]) { $0 + $1 }
        return PublicLedger(observer: me, seats: [
            me: .init(known: [.ore: 1], maxTotal: 1),
            rival: .init(known: known, maxTotal: known.values.reduce(0, +)),
        ])
    }
}
