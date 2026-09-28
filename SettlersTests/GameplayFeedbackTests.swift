import Foundation
import Testing
import SwiftUI
import CatanEngine
@testable import Settlers

struct GameplayFeedbackTests {
    let viewer = PlayerID(index: 2)
    let rival = PlayerID(index: 0)
    let now = Date(timeIntervalSince1970: 50_000)

    @Test func roadGainTransferAndLossShowExactNetChangesForBothSeats() throws {
        var before = fixture()
        var after = before
        after.longestRoadPlayer = viewer
        let gain = try #require(notices([.builtRoad(viewer)], before, after).first)
        #expect(gain.title(name: name) == "Alex earned Longest Road")
        #expect(gain.pointChanges == [viewer: 2])
        before.longestRoadPlayer = rival
        let transfer = try #require(notices([.builtRoad(viewer)], before, after).first)
        #expect(transfer.title(name: name) == "Alex took Longest Road from Sam")
        #expect(transfer.pointChanges == [viewer: 2, rival: -2])
        #expect(transfer.scoreSummary(name: name) == "Sam −2 VP, Alex +2 VP")
        after.longestRoadPlayer = nil
        let loss = try #require(notices([.builtSettlement(viewer)], before, after).first)
        #expect(loss.title(name: name) == "Sam lost Longest Road")
        #expect(loss.pointChanges == [rival: -2])
    }

    @Test func cityUpgradeIsOnePointAndTiedRoadDoesNotAnnounceAnAward() throws {
        var before = fixture()
        let vertex = try #require(before.board.onBoardVertices.sorted().first)
        before.players[viewer.index].settlements = [vertex]
        before.longestRoadPlayer = rival
        var after = before
        after.players[viewer.index].settlements = []
        after.players[viewer.index].cities = [vertex]
        let notice = try #require(notices([.builtCity(viewer)], before, after).first)
        #expect(notice.kind == .points(viewer))
        #expect(notice.pointChanges == [viewer: 1])
        #expect(notice.title(name: name) == "Alex gained 1 VP")
    }

    @Test func purchasesNeverDiscloseTheFaceOrOpponentsHiddenVictoryPoints() {
        let before = fixture()
        for seat in [viewer, rival] {
            var after = before
            after.players[seat.index].devCards = [.victoryPoint]
            let result = notices([.boughtDevCard(seat)], before, after)
            if seat == viewer {
                #expect(result.map(\.kind) == [.points(viewer)])
                #expect(result.first?.pointChanges == [viewer: 1])
            } else {
                #expect(result.isEmpty)
            }
            after.players[seat.index].devCards = [.monopoly]
            #expect(notices([.boughtDevCard(seat)], before, after).isEmpty)
        }
    }

    @Test(arguments: [DevCardType.knight, .roadBuilding, .yearOfPlenty, .monopoly])
    func allPublicCardPlaysUseActualEngineEvents(_ card: DevCardType) throws {
        var before = fixture()
        before.players[viewer.index].devCards = [card]
        before.players[viewer.index].settlements = [before.board.onBoardVertices.sorted().first!]
        let move = try #require(RulesEngine.legalMoves(for: before, seat: viewer).first { move in
            switch (card, move) {
            case (.knight, .playKnight), (.roadBuilding, .playRoadBuilding),
                 (.yearOfPlenty, .playYearOfPlenty), (.monopoly, .playMonopoly): true
            default: false
            }
        })
        var after = before
        let events = try RulesEngine.apply(move, by: viewer, to: &after)
        let notice = try #require(notices(events, before, after).first)
        #expect(notice.kind == .card(viewer, card))
        #expect(notice.title(name: name) == "Alex played \(DevCardStyle.fullName(for: card))")
        #expect(notices(events, before, before).isEmpty, "a staged or rejected move changed nothing")
        #expect(notices([], before, after).isEmpty, "restoring a board is not a new public event")
    }

    @Test func knightAndArmyTransferAreReadableSeparateNoticesWithOneScoreDelta() throws {
        var before = fixture()
        before.largestArmyPlayer = rival
        var after = before
        after.largestArmyPlayer = viewer
        let items = notices([.playedKnight(viewer, from: nil, stealing: nil)], before, after)
        #expect(items.count == 2)
        #expect(items[0].pointChanges.isEmpty)
        #expect(items[1].pointChanges == [rival: -2, viewer: 2])
        #expect(items[1].title(name: name) == "Alex took Largest Army from Sam")
    }

    @Test func rapidActionsKeepCurrentNoticeAndExpireInFIFOOrder() throws {
        var queue = GameplayFeedbackQueue()
        let first = item(.monopoly)
        let second = item(.knight)
        queue.enqueue([first], now: now)
        queue.enqueue([second], now: now.addingTimeInterval(0.1))
        #expect(queue.visible?.id == first.id)
        #expect(queue.deadline == now.addingTimeInterval(4))
        queue.advance(now: now.addingTimeInterval(4))
        #expect(queue.visible?.id == second.id)
        queue.advance(now: now.addingTimeInterval(8))
        #expect(queue.visible == nil)
        #expect(queue.deadline == nil)
    }

    @Test func priorityHoldPreservesReadingTimeButNeverRevivesOldNews() {
        var queue = GameplayFeedbackQueue()
        queue.enqueue([item(.monopoly)], now: now)
        queue.suspend(true, now: now.addingTimeInterval(1))
        #expect(queue.visible == nil)
        #expect(queue.deadline == nil)
        queue.suspend(false, now: now.addingTimeInterval(10))
        #expect(queue.deadline == now.addingTimeInterval(13))
        #expect(queue.visible != nil)
        queue.suspend(true, now: now.addingTimeInterval(11))
        queue.suspend(false, now: now.addingTimeInterval(30))
        #expect(queue.current == nil)
        #expect(queue.pending.isEmpty)
    }

    @Test func boundedQueueAndDismissalDoNotReplayOldEvents() {
        var queue = GameplayFeedbackQueue()
        let first = item(.monopoly)
        queue.enqueue([first], now: now)
        for _ in 0..<20 { queue.enqueue([item(.knight)], now: now) }
        #expect(queue.current?.id == first.id)
        #expect(queue.pending.count == GameplayFeedbackQueue.maximumPending)
        queue.clear()
        queue.advance(now: now.addingTimeInterval(4))
        #expect(queue.current == nil)
        #expect(queue.pending.isEmpty)
        #expect(queue.deadline == nil)
    }

    private func fixture() -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 32)
        state.phase = .mainTurn(playerIndex: viewer.index)
        return state
    }

    private func notices(_ events: [GameEvent], _ before: GameState, _ after: GameState) -> [GameplayFeedback] {
        GameplayFeedback.committed(events: events, before: before, after: after, viewer: viewer, now: now)
    }

    private func item(_ card: DevCardType) -> GameplayFeedback {
        GameplayFeedback(kind: .card(viewer, card), pointChanges: [:], occurredAt: now)
    }

    private func name(_ seat: PlayerID) -> String { seat == viewer ? "Alex" : "Sam" }
}
