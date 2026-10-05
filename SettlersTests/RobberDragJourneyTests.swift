import CoreGraphics
import Testing
@testable import CatanEngine
@testable import Settlers

@MainActor
@Suite(.serialized)
struct RobberDragJourneyTests {
    private let actor = PlayerID(index: 2)
    private let victim = PlayerID(index: 0)
    private let container = CGSize(width: 402, height: 300)

    @Test(arguments: [BoardDecisionIntent.robberAfterSeven, .knight])
    func dragRetargetAndVictimOnlyCommitAtConfirmation(_ intent: BoardDecisionIntent) throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.replaceStateForTesting(position(intent), humanSeat: actor)
        if intent == .knight { #expect(model.beginBoardDecision(.knight)) }
        let before = model.state
        let revision = try #require(model.checkpointDocument?.revision)
        let moveCount = try #require(model.checkpointDocument?.activeMatch?.moves.count)
        let withVictim = HexCoordinate(q: 1, r: 0)

        try dragFromOrigin(to: withVictim, in: model)
        #expect(model.boardDecisionPresentation?.canConfirm == false)
        #expect(model.selectBoardTarget(.victim(victim)))
        let another = try #require(model.boardDecisionPresentation?.legalTiles.first { $0 != withVictim })
        try dragFromOrigin(to: another, in: model)
        #expect(model.boardDecisionPresentation?.selectedVictim == nil)
        try dragFromOrigin(to: withVictim, in: model)
        #expect(model.selectBoardTarget(.victim(victim)))
        #expect(model.state == before)
        #expect(model.checkpointDocument?.revision == revision)
        #expect(model.checkpointDocument?.activeMatch?.moves.count == moveCount)
        #expect(fixture.makeModel().state == before, "preview has not reached the durable checkpoint")

        #expect(model.confirmBoardDecision())
        let committed = model.state
        #expect(committed.board.robberTile == withVictim)
        #expect(committed.players[victim.index].resources[.ore] == 0)
        #expect(committed.players[actor.index].resources[.ore] == 1)
        #expect(committed.players[actor.index].playedKnights == (intent == .knight ? 1 : 0))
        #expect(committed.players[actor.index].devCards.count == (intent == .knight ? 1 : 2))
        #expect(model.checkpointDocument?.revision == revision + 1)
        #expect(model.checkpointDocument?.activeMatch?.moves.count == moveCount + 1)
        #expect(fixture.makeModel().state == committed)
        #expect(!model.confirmBoardDecision())
        #expect(model.state == committed)
        #expect(model.checkpointDocument?.revision == revision + 1)
        #expect(model.checkpointDocument?.activeMatch?.moves.count == moveCount + 1)
    }

    @Test(arguments: [BoardDecisionIntent.robberAfterSeven, .knight])
    func invalidDropThenClearAndCancelPreserveCanonicalState(_ intent: BoardDecisionIntent) throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.replaceStateForTesting(position(intent), humanSeat: actor)
        if intent == .knight { #expect(model.beginBoardDecision(.knight)) }
        let before = model.state
        let revision = model.checkpointDocument?.revision
        try dragFromOrigin(to: HexCoordinate(q: 1, r: 0), in: model)
        #expect(model.selectBoardTarget(.victim(victim)))
        let selected = model.boardDecisionPresentation
        let geometry = displayedGeometry(for: model.state)
        let router = try makeRouter(in: model, geometry: geometry)
        #expect(router.dropTarget(at: geometry.center(of: before.board.robberTile),
            state: model.state, decision: model.boardDecisionPresentation,
            geometry: geometry, containerSize: container, allowsGameCommands: true) == nil)
        #expect(model.boardDecisionPresentation == selected)
        model.clearBoardDecisionSelection()
        #expect(model.boardDecisionPresentation?.selectedTile == nil)
        #expect(model.boardDecisionPresentation?.selectedVictim == nil)
        #expect(model.cancelBoardDecision() == (intent == .knight))
        #expect((model.boardDecisionPresentation == nil) == (intent == .knight))
        #expect(model.state == before)
        #expect(model.checkpointDocument?.revision == revision)
        #expect(fixture.makeModel().state == before)
    }

    private func dragFromOrigin(to tile: HexCoordinate, in model: GameViewModel) throws {
        let geometry = displayedGeometry(for: model.state)
        let router = try makeRouter(in: model, geometry: geometry)
        #expect(router.origin == .robber)
        #expect(router.pannedCamera(by: CGSize(width: 50, height: 20)) == nil)
        let target = try #require(router.dropTarget(at: geometry.center(of: tile),
            state: model.state, decision: model.boardDecisionPresentation,
            geometry: geometry, containerSize: container, allowsGameCommands: true))
        #expect(model.selectBoardTarget(target))
        #expect(model.boardDecisionPresentation?.selectedTile == tile)
    }

    private func makeRouter(in model: GameViewModel, geometry: Settlers.HexGeometry) throws -> BoardGestureRouter {
        let decision = try #require(model.boardDecisionPresentation)
        return BoardGestureRouter(startLocation: geometry.center(of: model.state.board.robberTile),
            state: model.state, decision: decision, geometry: geometry,
            camera: BoardCamera(zoom: 1.4, pan: CGSize(width: 12, height: -8)),
            containerSize: container, allowsGameCommands: true)
    }

    private func displayedGeometry(for state: GameState) -> Settlers.HexGeometry {
        let fit = BoardView.solvedFit(for: state.board, in: container)
        return BoardCamera(zoom: 1.4, pan: CGSize(width: 12, height: -8))
            .applied(to: fit.geometry, containerCenter: CGPoint(x: 201, y: 150))
    }

    private func position(_ intent: BoardDecisionIntent) -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7_402, playerCount: 3)
        state.board.robberTile = HexCoordinate(q: 0, r: 0)
        state.phase = intent == .knight ? .rollDice(playerIndex: actor.index) : .movingRobber(playerIndex: actor.index)
        state.players[actor.index].devCards = [.knight, .knight]
        let tile = HexCoordinate(q: 1, r: 0)
        let vertex = state.board.onBoardVertices.sorted().first { state.board.neighborTiles(of: $0).contains(tile) }!
        state.players[victim.index].settlements.insert(vertex)
        state.players[victim.index].resources = [.ore: 1]
        state.bank[.ore, default: 0] -= 1
        return state
    }
}
