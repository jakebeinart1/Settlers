import Testing
@testable import CatanEngine

/// Shared positions keep controller comparisons about the same move, rather
/// than comparing two policies that chose different actions or spent RNG.
struct EngineFairnessCase: Sendable {
    let mode: GameMode
    let variant: GameVariant
    let seat: Int

    static let all: [Self] = [GameMode.classic, .vast].flatMap { mode in
        GameVariant.allCases.flatMap { variant in
            (0..<4).map { Self(mode: mode, variant: variant, seat: $0) }
        }
    }

    var actor: PlayerID { PlayerID(index: seat) }
    var victim: PlayerID { PlayerID(index: (seat + 1) % 4) }
    var bystander: PlayerID { PlayerID(index: (seat + 2) % 4) }

    func state(seed: UInt64 = 77, beforeRoll: Bool = false) -> GameState {
        let rules = Ruleset.forMode(mode)
        var state = GameSetup.newGame(board: BoardGenerator.standard(rules.board), seed: seed,
                                      mode: mode, variant: variant)
        state.phase = beforeRoll ? .rollDice(playerIndex: seat) : .mainTurn(playerIndex: seat)
        state.players[seat].resources = [.brick: 2, .lumber: 2, .wool: 1, .grain: 2, .ore: 2]
        state.players[victim.index].resources = [.ore: 4, .grain: 3, .wool: 2]
        state.players[bystander.index].resources = [.brick: 2, .ore: 1]
        for player in state.players {
            for (resource, amount) in player.resources { state.bank[resource, default: 0] -= amount }
        }
        let corners = HexGeometry.corners(of: target(in: state))
        state.players[victim.index].settlements.insert(corners[0])
        state.players[bystander.index].settlements.insert(corners[3])
        return state
    }

    func target(in state: GameState) -> HexCoordinate {
        state.board.tiles.map(\.coordinate).sorted().first { $0 != state.board.robberTile }!
    }
}

private struct FairnessMovePolicy: Policy {
    let id = "fairness-scripted"
    let move: GameMove
    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove { move }
}

@Suite struct EngineFairnessTests {
    @Test(arguments: EngineFairnessCase.all)
    func humanAndPolicyApplyTheSameLegalCardMoves(fixture: EngineFairnessCase) throws {
        for beforeRoll in [false, true] {
            var state = fixture.state(beforeRoll: beforeRoll)
            state.players[fixture.seat].devCards = [.knight, .monopoly, .yearOfPlenty, .roadBuilding]
            let vertex = try #require(state.board.onBoardVertices.sorted().first {
                !HexGeometry.corners(of: fixture.target(in: state)).contains($0)
            })
            state.players[fixture.seat].settlements.insert(vertex)
            let legal = RulesEngine.legalMoves(for: state, seat: fixture.actor)
            let moves = legal.filter { move in
                switch move {
                case .playKnight, .playMonopoly, .playYearOfPlenty, .playRoadBuilding: true
                default: false
                }
            }
            #expect(!moves.isEmpty)
            // One complete choice per type reaches every card's application
            // without making a large-board road-pair enumeration a benchmark.
            let chosen: [GameMove] = [
                .playKnight(moveRobberTo: fixture.target(in: state), stealFrom: fixture.victim),
                .playMonopoly(.ore), .playYearOfPlenty(.grain, .grain),
                try #require(moves.first { if case .playRoadBuilding = $0 { return true }; return false }),
            ]
            for move in chosen {
                #expect(legal.contains(move))
                try assertControllerParity(state: state, actor: fixture.actor, move: move)
            }
        }
    }

    @Test(arguments: EngineFairnessCase.all)
    func requiredRobberyAndDiscardHaveControllerParity(fixture: EngineFairnessCase) throws {
        var state = fixture.state()
        state.phase = .movingRobber(playerIndex: fixture.seat)
        try assertControllerParity(state: state, actor: fixture.actor,
                                   move: .moveRobber(fixture.target(in: state), stealFrom: fixture.victim))
        state.phase = .discarding(pending: [fixture.actor, fixture.victim])
        state.robberMoverIndex = fixture.seat
        let discard = GameMove.discard([.brick: 2, .lumber: 2])
        #expect(RulesEngine.legalMoves(for: state, seat: fixture.actor).contains(discard))
        try assertControllerParity(state: state, actor: fixture.actor, move: discard)
    }

    @Test(arguments: EngineFairnessCase.all)
    func wrongSeatCannotPlayAndNeitherCommitPathMutates(fixture: EngineFairnessCase) throws {
        var state = fixture.state()
        state.players[fixture.victim.index].devCards = [.monopoly]
        var human = GameSession(state: state, policies: [:], policySeed: 1)
        var bot = GameSession(state: state, policies: [:], policySeed: 1)
        #expect(throws: MoveError.notYourTurn) {
            try human.applyExternal(.playMonopoly(.ore), by: fixture.victim)
        }
        #expect(throws: MoveError.notYourTurn) {
            try bot.commit(seat: fixture.victim, move: .playMonopoly(.ore))
        }
        #expect(human.state == state)
        #expect(bot.state == state)
    }

    private func assertControllerParity(state: GameState, actor: PlayerID, move: GameMove) throws {
        var human = GameSession(state: state, policies: [:], policySeed: 19)
        var bot = GameSession(state: state, policies: [actor: FairnessMovePolicy(move: move)], policySeed: 19)
        let external = try human.applyExternal(move, by: actor)
        let next = try bot.step()
        let automated = try #require(next)
        #expect(external.actor == automated.actor)
        #expect(external.move == automated.move)
        #expect(external.events == automated.events)
        #expect(external.privateEvents == automated.privateEvents)
        #expect(human.state == bot.state)
        for player in state.players { #expect(human.ledger(for: player.id) == bot.ledger(for: player.id)) }
    }
}
