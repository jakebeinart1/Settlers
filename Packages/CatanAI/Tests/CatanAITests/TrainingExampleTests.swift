import CatanEngine
import Testing
@testable import CatanAI

@Test func trainingExampleCarriesTheVersionedMaskedContract() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 501)
    state.phase = .mainTurn(playerIndex: 0)
    let seat = state.players[0].id
    let legal = RulesEngine.legalMoves(for: state, seat: seat)
    let observation = GameObservation(seat: seat, state: state, legalMoves: legal)
    let chosen = try #require(legal.first)

    let example = TrainingExample(
        buildID: "test-build",
        seed: 501,
        decisionIndex: 7,
        policyID: "test-policy",
        hiddenInformationPolicy: .revealAll,
        boardMode: .standard,
        observation: observation,
        chosenMove: chosen,
        winner: seat
    )

    #expect(example.schemaVersion == TrainingExample.schemaVersion)
    #expect(example.stateLayoutVersion == StateEncoding.layoutVersion)
    #expect(example.actionLayoutVersion == ActionSpace.layoutVersion)
    #expect(example.features.count == StateEncoding.featureCount)
    #expect(example.actionCount == ActionSpace(board: state.board).size)
    #expect(example.legalActionIndices == example.legalActionIndices.sorted())
    #expect(Set(example.legalActionIndices).count == example.legalActionIndices.count)
    #expect(example.legalActionIndices.contains(example.chosenActionIndex))
    #expect(example.hiddenInformationPolicy == .revealAll)
    #expect(example.playerCount == 4)
    #expect(example.victoryPointTarget == 10)
    #expect(example.boardMode == .standard)
    #expect(example.winnerSeat == seat.index)
    #expect(example.outcome == 1)
}

@Test func trainingOutcomeIsRelativeToTheObservingSeat() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 502)
    state.phase = .mainTurn(playerIndex: 0)
    let seat = state.players[0].id
    let observation = GameObservation(seat: seat, state: state, legalMoves: [.endTurn])

    let example = TrainingExample(
        buildID: "test-build",
        seed: 502,
        decisionIndex: 0,
        policyID: "test-policy",
        hiddenInformationPolicy: .revealAll,
        boardMode: .standard,
        observation: observation,
        chosenMove: .endTurn,
        winner: state.players[1].id
    )

    #expect(example.outcome == -1)
}

@Test(arguments: [3, 4])
func configuredExamplesUseOneActionHeadWidth(playerCount: Int) {
    let state = GameSetup.newGame(
        board: BoardGenerator.standard(),
        seed: UInt64(500 + playerCount),
        playerCount: playerCount
    )
    let seat = state.players[0].id
    let observation = GameObservation(
        seat: seat,
        state: state,
        legalMoves: RulesEngine.legalMoves(for: state, seat: seat)
    )
    let move = observation.legalMoves[0]
    let example = TrainingExample(
        buildID: "test-build",
        seed: UInt64(500 + playerCount),
        decisionIndex: 0,
        policyID: "test-policy",
        hiddenInformationPolicy: .publicCountsOnly,
        boardMode: .standard,
        observation: observation,
        chosenMove: move,
        winner: seat
    )

    #expect(example.actionCount == ActionSpace(board: state.board).size)
    #expect(example.actionCount == 9_295)
    #expect(example.playerCount == playerCount)
    #expect(example.victoryPointTarget == 10)
    #expect(example.boardMode == .standard)
}
