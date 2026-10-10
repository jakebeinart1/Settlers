import Foundation
import Testing
@testable import CatanEngine

struct NavalRoadContinuationTests {
    private let owner = PlayerID(index: 0)

    @Test(arguments: [BuildingKind.settlement, .city], [true, false])
    func twoRoadApproachCanChooseEitherSideOfARivalTown(kind: BuildingKind, coastal: Bool) throws {
        let fixture = try NavalRoadFixture.make(version: 6, kind: kind, coastalJunction: coastal)
        let state = fixture.state
        #expect(state.players[0].roads.count == 2)
        #expect(fixture.branches.count == 2)
        for edge in fixture.branches {
            #expect(Building.canBuildRoad(edge, for: owner, in: state))
            #expect(RulesEngine.legalMoves(for: state).contains(.buildRoad(edge)))
        }
    }

    @Test(arguments: [BuildingKind.settlement, .city], [true, false])
    func eitherPaidExitCostsOneRoadAndKeepsLongestRoadSplit(kind: BuildingKind, coastal: Bool) throws {
        let fixture = try NavalRoadFixture.make(version: 6, kind: kind, coastalJunction: coastal)
        for edge in fixture.branches {
            var state = fixture.state
            let bank = state.bank
            let events = try RulesEngine.apply(.buildRoad(edge), by: owner, to: &state)
            #expect(events == [.builtRoad(owner)])
            #expect(state.players[0].roads.count == 3)
            #expect(state.players[0].resources[.brick] == 0 && state.players[0].resources[.lumber] == 0)
            #expect(state.bank[.brick] == bank[.brick, default: 0] + 1)
            #expect(state.bank[.lumber] == bank[.lumber, default: 0] + 1)
            #expect(LongestRoad.length(for: state.players[0], in: state) == 2)
            #expect(state.longestRoadPlayer == nil)
        }
    }

    @Test(arguments: [1, 2, 3, 4, 5], [BuildingKind.settlement, .city])
    func legacyVersionsKeepTheRivalTownBlockAcrossSaveAndReplay(version: Int, kind: BuildingKind) throws {
        let fixture = try NavalRoadFixture.make(version: version, kind: kind)
        let encoded = try JSONEncoder().encode(fixture.state)
        var restored = try JSONDecoder().decode(GameState.self, from: encoded)
        #expect(restored == fixture.state && restored.naval?.rulesVersion == version)
        for edge in fixture.branches {
            #expect(!Building.canBuildRoad(edge, for: owner, in: restored))
            #expect(!RulesEngine.legalMoves(for: restored).contains(.buildRoad(edge)))
            #expect(throws: MoveError.illegalPlacement) {
                try RulesEngine.replay(.buildRoad(edge), by: owner, rulesVersion: RulesEngine.currentRulesVersion, to: &restored)
            }
            #expect(restored == fixture.state)
        }
    }

    @Test(arguments: [GameMode.classic, .expanded, .vast], GameVariant.allCases)
    func ordinaryModesKeepTheRivalTownBlock(mode: GameMode, variant: GameVariant) throws {
        let fixture = try NavalRoadFixture.make(version: 6, mode: mode, variant: variant)
        #expect(fixture.state.naval == nil)
        for edge in fixture.branches { #expect(!Building.canBuildRoad(edge, for: owner, in: fixture.state)) }
    }

    @Test(arguments: [1, 2, 3, 4, 5, 6])
    func arrivingAtARivalTownRemainsLegalInEveryVersion(version: Int) throws {
        let fixture = try NavalRoadFixture.make(version: version)
        var state = fixture.state
        let arriving = try #require(state.players[0].roads.first { $0.a == fixture.junction || $0.b == fixture.junction })
        state.players[0].roads.remove(arriving)
        #expect(Building.canBuildRoad(arriving, for: owner, in: state))
        try RulesEngine.apply(.buildRoad(arriving), by: owner, to: &state)
        #expect(state.players[0].roads.count == 2)
        for edge in fixture.branches {
            #expect(Building.canBuildRoad(edge, for: owner, in: state) == (version >= 6))
        }
    }

    @Test func rivalRoadBlocksOnlyItsOwnEdgeAndTheTownCannotSupplyAConnection() throws {
        let fixture = try NavalRoadFixture.make(version: 6)
        var state = fixture.state
        let claimed = try #require(fixture.branches.first)
        let other = try #require(fixture.branches.last)
        state.players[1].roads.insert(claimed)
        #expect(!Building.canBuildRoad(claimed, for: owner, in: state))
        #expect(Building.canBuildRoad(other, for: owner, in: state))
        let unchanged = state
        #expect(throws: MoveError.illegalPlacement) { try RulesEngine.apply(.buildRoad(claimed), by: owner, to: &state) }
        #expect(state == unchanged)
        state.players[0].roads = []
        #expect(!Building.canBuildRoad(other, for: owner, in: state))
        #expect(!Building.canBuildSettlement(fixture.junction, for: owner, in: state))
        #expect(state.board.adjacentVertices(of: fixture.junction).allSatisfy {
            !Building.canBuildSettlement($0, for: owner, in: state)
        })
        state.players[0].settlements = []
        let sea = try #require(fixture.junction.touchingTiles.first { coordinate in
            state.board.tiles.contains { $0.coordinate == coordinate && $0.kind == .sea }
        })
        NavalTestSupport.addShip(at: sea, player: 0, in: &state)
        #expect(!Building.canBuildRoad(other, for: owner, in: state), "A ship cannot seed a road before founding a town")
    }

    @Test func fogCostAndPieceSupplyRemainRequired() throws {
        let fixture = try NavalRoadFixture.make(version: 6)
        let edge = try #require(fixture.branches.first)
        var hidden = fixture.state
        hidden.naval?.options.fogEnabled = true
        hidden.naval?.revealed.subtract(Set(edge.a.touchingTiles).intersection(edge.b.touchingTiles))
        #expect(!Building.canBuildRoad(edge, for: owner, in: hidden))
        var unfunded = fixture.state
        unfunded.players[0].resources = [:]
        let baseline = unfunded
        #expect(!RulesEngine.legalMoves(for: unfunded).contains(.buildRoad(edge)))
        #expect(throws: MoveError.insufficientResources) { try RulesEngine.apply(.buildRoad(edge), by: owner, to: &unfunded) }
        #expect(unfunded == baseline)
        var exhausted = fixture.state
        for candidate in exhausted.board.onBoardEdges.sorted() where !fixture.branches.contains(candidate) {
            guard exhausted.players[0].roads.count < exhausted.rules.maxRoadsPerPlayer else { break }
            exhausted.players[0].roads.insert(candidate)
        }
        #expect(exhausted.players[0].roads.count == 20)
        #expect(!Building.canBuildRoad(edge, for: owner, in: exhausted))
        let sea = try #require(fixture.state.board.tiles.first { $0.kind == .sea }?.coordinate)
        let outside = try #require(HexGeometry.edges(of: sea).first { !fixture.state.board.onBoardEdges.contains($0) })
        #expect(!Building.canBuildRoad(outside, for: owner, in: fixture.state))
    }

    @Test func roadBuildingCanExtendPastTownAndItsSecondEdgeRemainsAtomic() throws {
        let fixture = try NavalRoadFixture.make(version: 6)
        let first = try #require(fixture.branches.first)
        let middle = first.a == fixture.junction ? first.b : first.a
        let second = try #require(fixture.state.board.edgesTouching(middle).first { $0 != first })
        var state = fixture.state
        state.players[0].devCards = [.roadBuilding]
        state.players[0].resources = [:]
        #expect(DevCards.legalRoadBuildingPairs(by: owner, in: state).contains { $0.first == first && $0.second == second })
        let bank = state.bank
        let events = try RulesEngine.apply(.playRoadBuilding(first, second), by: owner, to: &state)
        #expect(events == [.playedRoadBuilding(owner)])
        #expect(state.players[0].roads.count == 4 && state.players[0].devCards.isEmpty)
        #expect(state.bank == bank)
        #expect(LongestRoad.length(for: state.players[0], in: state) == 2)
        var occupied = fixture.state
        occupied.players[0].devCards = [.roadBuilding]
        occupied.players[1].roads.insert(second)
        let unchanged = occupied
        #expect(throws: MoveError.illegalPlacement) {
            try RulesEngine.apply(.playRoadBuilding(first, second), by: owner, to: &occupied)
        }
        #expect(occupied == unchanged)
    }

    @Test func roadBuildingWithOnePieceLeftRollsBackWithoutConsumingTheCard() throws {
        let fixture = try NavalRoadFixture.make(version: 6)
        let first = try #require(fixture.branches.first)
        let middle = first.a == fixture.junction ? first.b : first.a
        let second = try #require(fixture.state.board.edgesTouching(middle).first { $0 != first })
        var state = fixture.state
        state.players[0].devCards = [.roadBuilding]
        for edge in state.board.onBoardEdges.sorted() where edge != first && edge != second {
            guard state.players[0].roads.count < state.rules.maxRoadsPerPlayer - 1 else { break }
            state.players[0].roads.insert(edge)
        }
        #expect(state.players[0].roads.count == 19 && Building.canBuildRoad(first, for: owner, in: state))
        #expect(!DevCards.legalRoadBuildingPairs(by: owner, in: state).contains { $0.first == first && $0.second == second })
        let unchanged = state
        #expect(throws: MoveError.illegalPlacement) {
            try RulesEngine.apply(.playRoadBuilding(first, second), by: owner, to: &state)
        }
        #expect(state == unchanged)
    }

    @Test func newContractKeepsItsRoadMoveAcrossColdSaveAndReplay() throws {
        let fixture = try NavalRoadFixture.make(version: 6)
        let edge = try #require(fixture.branches.first)
        var original = fixture.state
        let events = try RulesEngine.apply(.buildRoad(edge), by: owner, to: &original)
        var replay = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(fixture.state))
        let replayed = try RulesEngine.replay(.buildRoad(edge), by: owner, rulesVersion: 3, to: &replay)
        #expect(replayed == events && replay == original)
        let saved = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(original))
        #expect(saved == original && saved.naval?.rulesVersion == 6)
        #expect(Naval.validationProblem(in: saved) == nil)
        #expect(LongestRoad.length(for: saved.players[0], in: saved) == 2)
    }

    @Test func currentMatchesAndDecodedMissingVersionsUseTheirOwnContracts() throws {
        let current = Naval.newGame(seed: 73)
        #expect(current.naval?.rulesVersion == 6)
        let fixture = try NavalRoadFixture.make(version: 1)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.state)) as? [String: Any])
        var naval = try #require(object["naval"] as? [String: Any])
        naval.removeValue(forKey: "rulesVersion")
        object["naval"] = naval
        let restored = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.naval?.rulesVersion == 1)
        #expect(fixture.branches.allSatisfy { !Building.canBuildRoad($0, for: owner, in: restored) })
    }
}

private struct NavalRoadFixture {
    let state: GameState
    let junction: VertexID
    let branches: [EdgeID]

    /// A two-road approach on a generated overseas island. The coastal founder
    /// and rival town obey the distance rule. The town may be inland like the
    /// screenshot or coastal; either junction has two free land edges beyond it.
    static func make(version: Int, kind: BuildingKind = .settlement,
                     mode: GameMode = .naval, variant: GameVariant = .standard, coastalJunction: Bool = true) throws -> Self {
        var state = mode == .naval
            ? Naval.newGame(seed: 73, options: NavalOptions(fogEnabled: false))
            : GameSetup.newGame(board: BoardGenerator.standard(Ruleset.forMode(mode).board), seed: 73, mode: mode, variant: variant)
        state.naval?.rulesVersion = version
        state.phase = .mainTurn(playerIndex: 0)
        let route = try #require(approach(in: state, coastalJunction: coastalJunction))
        state.players[0].settlements = [route.start]
        state.players[0].roads = [route.first, route.second]
        switch kind {
        case .settlement: state.players[1].settlements = [route.junction]
        case .city: state.players[1].cities = [route.junction]
        }
        NavalTestSupport.fund(Building.roadCost, in: &state)
        let branches = state.board.edgesTouching(route.junction).filter { $0 != route.second }
        return Self(state: state, junction: route.junction, branches: branches)
    }

    private static func approach(in state: GameState, coastalJunction: Bool)
        -> (start: VertexID, first: EdgeID, second: EdgeID, junction: VertexID)? {
        for junction in state.board.onBoardVertices.sorted() {
            guard state.board.edgesTouching(junction).count == 3 else { continue }
            if state.mode == .naval && (Naval.isCoastal(junction, in: state) != coastalJunction
                || !junction.touchingTiles.contains(where: { (state.naval?.islandByHex[$0, default: 0] ?? 0) > 0 })) { continue }
            if state.mode == .naval && !coastalJunction && !junction.touchingTiles.allSatisfy({ Naval.isKnownLand($0, in: state) }) { continue }
            for second in state.board.edgesTouching(junction) {
                let middle = second.a == junction ? second.b : second.a
                for first in state.board.edgesTouching(middle) where first != second {
                    let start = first.a == middle ? first.b : first.a
                    let validStart = state.mode != .naval || Naval.isCoastal(start, in: state)
                    if validStart, !state.board.adjacentVertices(of: junction).contains(start) {
                        return (start, first, second, junction)
                    }
                }
            }
        }
        return nil
    }
}
