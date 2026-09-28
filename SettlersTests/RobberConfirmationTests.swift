import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

/// Exercises the production coordinator and engine with explicit board modes
/// instead of depending on launch fixtures. Every chair, victim count, and
/// Knight timing window must keep preview separate from the final engine move.
struct RobberConfirmationTests {
    @Test(arguments: RobberConfirmationScenario.all)
    func previewVictimAndCommit(_ scenario: RobberConfirmationScenario) throws {
        var fixture = scenario.fixture()
        var coordinator = fixture.coordinator()
        let before = fixture.state
        #expect(coordinator.confirmableMove == nil)
        #expect(coordinator.presentation?.canCancel == scenario.source.isKnight)
        #expect(coordinator.select(.tile(fixture.destination)) == true)
        #expect(coordinator.presentation?.legalVictims == fixture.victims)
        #expect(coordinator.presentation?.canConfirm == fixture.victims.isEmpty)
        let victim = fixture.victims.last
        if let victim { #expect(coordinator.select(.victim(victim)) == true) }
        #expect(coordinator.presentation?.selectedVictim == victim)
        #expect(fixture.state == before, "preview must not move, steal, consume a Knight, or draw RNG")

        let move = try #require(coordinator.confirmableMove)
        #expect(move == scenario.source.move(to: fixture.destination, victim: victim))
        try RulesEngine.apply(move, by: fixture.actor, to: &fixture.state)
        #expect(fixture.state.board.robberTile == fixture.destination)
        #expect(fixture.state.players[fixture.actor.index].resources[.ore, default: 0] == (victim == nil ? 0 : 1))
        for rival in fixture.victims {
            #expect(fixture.state.players[rival.index].resources[.ore] == (rival == victim ? 0 : 1))
        }
        #expect(fixture.state.players[fixture.actor.index].devCards.isEmpty)
        #expect(fixture.state.players[fixture.actor.index].playedKnights == (scenario.source.isKnight ? 1 : 0))
        #expect(fixture.state.phase == scenario.source.resultingPhase(actor: fixture.actor))
        coordinator.reconcile(with: fixture.context(moveCount: 8))
        #expect(coordinator.presentation == nil)
        #expect(coordinator.confirmableMove == nil, "a second confirm cannot repeat the theft")
    }

    @Test(arguments: RobberConfirmationScenario.withVictims)
    func changingTerritoryClearsVictimAndRejectsOldCallbacks(_ scenario: RobberConfirmationScenario) throws {
        let fixture = scenario.fixture()
        var coordinator = fixture.coordinator()
        let victim = try #require(fixture.victims.last)
        #expect(coordinator.select(.victim(victim)) == false, "victim callbacks before a tile are invalid")
        #expect(coordinator.select(.tile(fixture.state.board.robberTile)) == false)
        #expect(coordinator.select(.tile(HexCoordinate(q: 99, r: 99))) == false)
        #expect(coordinator.select(.tile(fixture.destination)) == true)
        #expect(coordinator.select(.victim(fixture.actor)) == false)
        #expect(coordinator.select(.victim(PlayerID(index: scenario.seats))) == false)
        #expect(coordinator.select(.victim(victim)) == true)
        let empty = try #require(coordinator.presentation?.legalTiles.first {
            Robber.eligibleVictims(for: $0, thief: fixture.actor, in: fixture.state).isEmpty
        })

        #expect(coordinator.select(.tile(empty)) == true)
        #expect(coordinator.presentation?.selectedVictim == nil)
        #expect(coordinator.select(.victim(victim)) == false, "an old victim callback cannot retarget the theft")
        #expect(coordinator.confirmableMove == scenario.source.move(to: empty, victim: nil))
        #expect(coordinator.select(.tile(fixture.destination)) == true)
        #expect(coordinator.confirmableMove == nil, "returning to a tile needs a new victim choice")
        coordinator.clearSelection()
        #expect(coordinator.presentation?.selectedTile == nil)
        #expect(coordinator.presentation?.legalVictims.isEmpty == true)
        #expect(coordinator.confirmableMove == nil)
    }

    @Test(arguments: RobberConfirmationScenario.withVictims)
    func staleVictimIsDroppedWhenTheirHandEmpties(_ scenario: RobberConfirmationScenario) throws {
        var fixture = scenario.fixture()
        var coordinator = fixture.coordinator()
        let victim = try #require(fixture.victims.last)
        #expect(coordinator.select(.tile(fixture.destination)) == true)
        #expect(coordinator.select(.victim(victim)) == true)
        fixture.state.players[victim.index].resources = [:]
        fixture.state.bank[.ore, default: 0] += 1

        // Even if position metadata is unchanged, refreshed engine candidates
        // must remove an invalid victim while retaining the legal destination.
        coordinator.reconcile(with: fixture.context())

        #expect(coordinator.presentation?.selectedTile == fixture.destination)
        #expect(coordinator.presentation?.selectedVictim == nil)
        #expect(coordinator.presentation?.legalVictims == Array(fixture.victims.dropLast()))
        #expect(coordinator.select(.victim(victim)) == false)
        if fixture.victims.count == 1 {
            #expect(coordinator.confirmableMove == scenario.source.move(to: fixture.destination, victim: nil))
        } else {
            #expect(coordinator.confirmableMove == nil)
        }
    }

    @Test(arguments: RobberConfirmationSource.allCases)
    func newlyEligibleVictimRequiresAChoice(_ source: RobberConfirmationSource) {
        var fixture = RobberConfirmationScenario(source: source, victims: 0).fixture()
        var coordinator = fixture.coordinator()
        #expect(coordinator.select(.tile(fixture.destination)) == true)
        #expect(coordinator.presentation?.canConfirm == true)
        let rival = PlayerID(index: 0)
        let vertex = fixture.state.board.corners(of: fixture.destination)[0]
        fixture.state.players[rival.index].cities.insert(vertex)
        fixture.state.players[rival.index].resources = [.ore: 1]
        fixture.state.bank[.ore, default: 0] -= 1

        coordinator.reconcile(with: fixture.context())

        #expect(coordinator.presentation?.legalVictims == [rival])
        #expect(coordinator.confirmableMove == nil)
        #expect(coordinator.select(.victim(rival)) == true)
        #expect(coordinator.confirmableMove == source.move(to: fixture.destination, victim: rival))
    }

    @Test(arguments: RobberConfirmationSource.allCases)
    func staleDestinationCannotBeConfirmed(_ source: RobberConfirmationSource) {
        var fixture = RobberConfirmationScenario(source: source, victims: 1).fixture()
        var coordinator = fixture.coordinator()
        #expect(coordinator.select(.tile(fixture.destination)) == true)
        #expect(coordinator.select(.victim(fixture.victims[0])) == true)
        fixture.state.board.robberTile = fixture.destination

        coordinator.reconcile(with: fixture.context())

        #expect(coordinator.presentation?.selectedTile == nil)
        #expect(coordinator.presentation?.selectedVictim == nil)
        #expect(coordinator.confirmableMove == nil)
        #expect(coordinator.select(.tile(fixture.destination)) == false)
    }

    @Test(arguments: RobberConfirmationSource.allCases, RobberContextChange.allCases)
    func positionAndActorChangesInvalidateTheProposal(
        _ source: RobberConfirmationSource, _ change: RobberContextChange
    ) {
        let fixture = RobberConfirmationScenario(source: source, victims: 1).fixture()
        var coordinator = fixture.coordinator()
        #expect(coordinator.select(.tile(fixture.destination)) == true)
        #expect(coordinator.select(.victim(fixture.victims[0])) == true)

        coordinator.reconcile(with: fixture.context(change: change))

        #expect(coordinator.confirmableMove == nil)
        #expect(coordinator.presentation?.selectedTile == nil)
        #expect(coordinator.presentation?.selectedVictim == nil)
        if source == .seven && change != .actor {
            #expect(coordinator.presentation?.intent == .robberAfterSeven)
        } else {
            #expect(coordinator.presentation == nil)
        }
    }

    @Test(arguments: RobberConfirmationSource.allCases)
    func failureRetainsExactMoveWhileCancelFollowsItsSource(_ source: RobberConfirmationSource) throws {
        let fixture = RobberConfirmationScenario(source: source, victims: 2).fixture()
        var coordinator = fixture.coordinator()
        #expect(coordinator.select(.tile(fixture.destination)) == true)
        #expect(coordinator.select(.victim(fixture.victims[0])) == true)
        let move = try #require(coordinator.confirmableMove)
        coordinator.reportFailure("Injected checkpoint failure")
        coordinator.reconcile(with: fixture.context())
        #expect(coordinator.confirmableMove == move)
        #expect(coordinator.presentation?.errorMessage == "Injected checkpoint failure")
        #expect(coordinator.cancel() == source.isKnight)
        if source.isKnight {
            #expect(coordinator.presentation == nil)
        } else {
            #expect(coordinator.confirmableMove == move)
        }
    }

    @Test(arguments: RobberConfirmationSource.allCases)
    func changedPhaseDropsTheProposalEvenWithoutANewPosition(_ source: RobberConfirmationSource) {
        var fixture = RobberConfirmationScenario(source: source, victims: 1).fixture()
        var coordinator = fixture.coordinator()
        #expect(coordinator.select(.tile(fixture.destination)) == true)
        #expect(coordinator.select(.victim(fixture.victims[0])) == true)
        fixture.state.phase = .rollDice(playerIndex: 0)

        coordinator.reconcile(with: fixture.context())

        #expect(coordinator.presentation == nil)
        #expect(coordinator.confirmableMove == nil)
    }

    @Test(arguments: [RobberConfirmationSource.knightBeforeRoll, .knightAfterRoll])
    func unavailableKnightDropsTheProposal(_ source: RobberConfirmationSource) {
        var fixture = RobberConfirmationScenario(source: source, victims: 1).fixture()
        var coordinator = fixture.coordinator()
        #expect(coordinator.select(.tile(fixture.destination)) == true)
        #expect(coordinator.select(.victim(fixture.victims[0])) == true)
        fixture.state.players[fixture.actor.index].devCards = []

        coordinator.reconcile(with: fixture.context())

        #expect(coordinator.presentation == nil)
        #expect(coordinator.confirmableMove == nil)
    }
}

enum RobberContextChange: CaseIterable {
    case match, moveCount, actor
}

enum RobberConfirmationSource: CaseIterable {
    case seven, knightBeforeRoll, knightAfterRoll
    var isKnight: Bool { self != .seven }

    func phase(actor: PlayerID) -> GamePhase {
        switch self {
        case .seven: .movingRobber(playerIndex: actor.index)
        case .knightBeforeRoll: .rollDice(playerIndex: actor.index)
        case .knightAfterRoll: .mainTurn(playerIndex: actor.index)
        }
    }

    func resultingPhase(actor: PlayerID) -> GamePhase {
        self == .seven ? .mainTurn(playerIndex: actor.index) : phase(actor: actor)
    }

    func move(to tile: HexCoordinate, victim: PlayerID?) -> GameMove {
        isKnight ? .playKnight(moveRobberTo: tile, stealFrom: victim) : .moveRobber(tile, stealFrom: victim)
    }
}

struct RobberConfirmationScenario: CustomTestStringConvertible {
    var mode: GameMode = .vast
    var seats: Int = 3
    var actorIndex: Int = 2
    let source: RobberConfirmationSource
    let victims: Int

    var testDescription: String { "\(mode), \(seats) seats, actor \(actorIndex), \(source), \(victims) victims" }

    static var all: [Self] {
        GameMode.newGameChoices.flatMap { mode in
            [3, 4].flatMap { seats in
                (0..<seats).flatMap { actor in
                    RobberConfirmationSource.allCases.flatMap { source in
                        (0..<seats).map { victims in
                            Self(mode: mode, seats: seats, actorIndex: actor, source: source, victims: victims)
                        }
                    }
                }
            }
        }
    }

    static var withVictims: [Self] { all.filter { $0.victims > 0 } }

    func fixture() -> RobberConfirmationFixture {
        var state = GameSetup.newGame(
            board: BoardGenerator.standard(mode == .vast ? .vast : .classic),
            seed: 9_270, playerCount: seats, mode: mode
        )
        let actor = PlayerID(index: actorIndex)
        // The outer ring exercises Vast destinations absent from Classic.
        let destination = state.board.tiles.last { $0.coordinate != state.board.robberTile }!.coordinate
        let rivals = Array(state.players.map(\.id).filter { $0 != actor }.prefix(victims))
        let corners = state.board.corners(of: destination)
        for (offset, rival) in rivals.enumerated() {
            state.players[rival.index].settlements.insert(corners[offset * 2])
            state.players[rival.index].resources = [.ore: 1]
            state.bank[.ore, default: 0] -= 1
        }
        state.phase = source.phase(actor: actor)
        state.players[actor.index].devCards = source.isKnight ? [.knight] : []
        return RobberConfirmationFixture(state: state, actor: actor, destination: destination,
                                         victims: rivals, source: source)
    }
}

struct RobberConfirmationFixture {
    var state: GameState
    let actor: PlayerID
    let destination: HexCoordinate
    let victims: [PlayerID]
    let source: RobberConfirmationSource

    func coordinator() -> BoardDecisionCoordinator {
        var result = BoardDecisionCoordinator()
        if source.isKnight {
            #expect(result.begin(.knight, with: context()) == true)
        } else {
            result.reconcile(with: context())
        }
        return result
    }

    func context(moveCount: Int = 7, change: RobberContextChange? = nil) -> BoardDecisionContext {
        BoardDecisionContext(
            matchID: UUID(uuidString: change == .match
                ? "22222222-2222-2222-2222-222222222222" : "11111111-1111-1111-1111-111111111111"),
            committedMoveCount: change == .moveCount ? moveCount + 1 : moveCount,
            actor: change == .actor ? PlayerID(index: 0) : actor,
            state: state
        )
    }
}
