import Testing
@testable import CatanEngine

@Suite struct RulesVersionReplayTests {
    private let thief = PlayerID(index: 0)
    private let victim = PlayerID(index: 1)

    @Test func versionOnePreservesPartialYearOfPlentyHistory() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 911)
        state.phase = .mainTurn(playerIndex: thief.index)
        state.players[thief.index].devCards = [.yearOfPlenty]
        state.bank[.ore] = 0
        state.bank[.grain] = 1

        let events = try RulesEngine.replay(
            .playYearOfPlenty(.ore, .grain),
            by: thief,
            rulesVersion: RulesEngine.oldestSupportedRulesVersion,
            to: &state
        )

        #expect(events == [.playedYearOfPlenty(thief, taken: [.ore: 1, .grain: 1])])
        #expect(state.players[thief.index].resources[.ore] == nil)
        #expect(state.players[thief.index].resources[.grain] == 1)
        #expect(state.players[thief.index].devCards.isEmpty)
    }

    @Test func versionOnePreservesNilVictimRobberHistory() throws {
        var fixture = stateWithEligibleVictim(seed: 912)
        fixture.state.phase = .movingRobber(playerIndex: thief.index)
        fixture.state.robberMoverIndex = thief.index

        let events = try RulesEngine.replay(
            .moveRobber(fixture.target, stealFrom: nil),
            by: thief,
            rulesVersion: RulesEngine.oldestSupportedRulesVersion,
            to: &fixture.state
        )

        #expect(events == [.movedRobber(thief, from: nil, stealing: nil)])
        #expect(fixture.state.players[victim.index].resources[.lumber] == 1)
        #expect(fixture.state.phase == .mainTurn(playerIndex: thief.index))
        #expect(fixture.state.robberMoverIndex == nil)
    }

    @Test(arguments: [false, true])
    func versionOnePreservesNilVictimKnightHistory(beforeRoll: Bool) throws {
        var fixture = stateWithEligibleVictim(seed: beforeRoll ? 913 : 914)
        fixture.state.phase = beforeRoll
            ? .rollDice(playerIndex: thief.index)
            : .mainTurn(playerIndex: thief.index)
        fixture.state.players[thief.index].devCards = [.knight]

        let events = try RulesEngine.replay(
            .playKnight(moveRobberTo: fixture.target, stealFrom: nil),
            by: thief,
            rulesVersion: RulesEngine.oldestSupportedRulesVersion,
            to: &fixture.state
        )

        #expect(events == [.playedKnight(thief, from: nil, stealing: nil)])
        #expect(fixture.state.players[thief.index].playedKnights == 1)
        #expect(fixture.state.players[victim.index].resources[.lumber] == 1)
        #expect(fixture.state.players[thief.index].devCards.isEmpty)
    }

    @Test func versionOneStillReplaysAnExplicitRobberVictimExactly() throws {
        var fixture = stateWithEligibleVictim(seed: 915)

        let stolen = try Robber.applyRulesVersionOne(
            move: fixture.target,
            stealFrom: victim,
            by: thief,
            to: &fixture.state
        )

        #expect(stolen == .lumber)
        #expect(fixture.state.players[thief.index].resources[.lumber] == 1)
        #expect(fixture.state.players[victim.index].resources[.lumber] == 0)
    }

    @Test(arguments: [RulesEngine.oldestSupportedRulesVersion, RulesEngine.currentRulesVersion])
    func ordinaryMovesReplayUnderEverySupportedVersion(rulesVersion: Int) throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 916)
        state.phase = .mainTurn(playerIndex: thief.index)

        let events = try RulesEngine.replay(
            .endTurn,
            by: thief,
            rulesVersion: rulesVersion,
            to: &state
        )

        #expect(events == [.endedTurn(thief)])
        #expect(state.phase == .rollDice(playerIndex: victim.index))
    }

    @Test func unsupportedRulesVersionCannotMutateAReplay() {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 917)
        let before = state

        #expect(throws: MoveError.other("unsupported recorded rules version")) {
            try RulesEngine.replay(
                .rollDice,
                by: thief,
                rulesVersion: RulesEngine.currentRulesVersion + 1,
                to: &state
            )
        }
        #expect(state == before)
    }

    private func stateWithEligibleVictim(
        seed: UInt64
    ) -> (state: GameState, target: HexCoordinate) {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: seed)
        let target = state.board.tiles.map(\.coordinate).first {
            $0 != state.board.robberTile
        }!
        let victimVertex = HexGeometry.corners(of: target).first!
        state.players[victim.index].settlements.insert(victimVertex)
        state.players[victim.index].resources = [.lumber: 1]
        return (state, target)
    }
}
