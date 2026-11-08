import Foundation
import Testing
import CatanEngine
@testable import Settlers

@Suite("Online spatial actions")
struct OnlineBoardDecisionTests {
    private let actor = PlayerID(index: 0)

    @Test func openingShowsExactlyTheAuthorizedCorners() throws {
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 841)
        let legal = RulesEngine.legalMoves(for: state, seat: actor)
        let selected = try #require(legal.first)
        guard case .placeInitialSettlement(let corner) = selected else {
            Issue.record("Expected an opening settlement")
            return
        }
        var draft = BoardDecisionCoordinator()
        draft.reconcile(with: context(state, moves: [selected]))
        #expect(draft.presentation?.legalVertices == [corner])
        let alternate = try #require(state.board.onBoardVertices.first { $0 != corner })
        let selectedAlternate = draft.select(.vertex(alternate))
        let selectedCorner = draft.select(.vertex(corner))
        #expect(!selectedAlternate)
        #expect(selectedCorner)
        #expect(draft.confirmableMove == selected)
    }

    @Test func emptyAuthorityMaskNeverCreatesAMandatoryDraft() {
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 842)
        var draft = BoardDecisionCoordinator()
        draft.reconcile(with: context(state, moves: []))
        #expect(draft.presentation == nil)
        #expect(draft.confirmableMove == nil)
    }

    @Test func authorityCanOfferARobberVictimWithoutExposingItsHand() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 843)
        state.phase = .movingRobber(playerIndex: actor.index)
        let victim = PlayerID(index: 1)
        let tile = try #require(state.board.tiles.first { $0.coordinate != state.board.robberTile }?.coordinate)
        let move = GameMove.moveRobber(tile, stealFrom: victim)
        var draft = BoardDecisionCoordinator()
        draft.reconcile(with: context(state, moves: [move]))
        #expect(state.players[victim.index].resources.isEmpty)
        let selectedTile = draft.select(.tile(tile))
        #expect(selectedTile)
        #expect(draft.presentation?.legalVictims == [victim])
        let selectedVictim = draft.select(.victim(victim))
        #expect(selectedVictim)
        #expect(draft.confirmableMove == move)
    }

    private func context(_ state: GameState, moves: [GameMove]) -> BoardDecisionContext {
        BoardDecisionContext(matchID: UUID(), committedMoveCount: 1, actor: actor,
                             state: state, authorizedMoves: moves)
    }
}
