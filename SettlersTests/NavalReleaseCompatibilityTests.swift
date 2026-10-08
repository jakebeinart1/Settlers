import CatanAI
import CatanEngine
import Foundation
import Testing
@testable import Settlers

/// Exercise the seams where the published human-review release meets Naval:
/// public movie data, recorded-rule playback, migration and mandatory decisions.
@MainActor
@Suite(.serialized)
struct NavalReleaseCompatibilityTests {
    private let human = PlayerID(index: 0)

    @Test func publicMovieRetainsFleetAndColonyScoresWithoutConcealedWorldData() throws {
        var initial = try NavalQAFixture.make(.cityHarvest)
        initial.players[0].devCards = [.victoryPoint, .monopoly]
        initial.naval?.generationAttempts = 53
        initial.naval?.usedFallback = true
        var sequence = try ReplayExportSequence(detail: ReplayExportFixtures.detail(initial: initial))
        let frame = try #require(try sequence.next())
        let projected = try #require(frame.boardState.naval)
        let authoritative = try #require(initial.naval)
        let hidden = Set(initial.board.tiles.map(\.coordinate)).subtracting(authoritative.revealed)

        #expect(!hidden.isEmpty)
        #expect(frame.boardState.board == Naval.visibleBoard(in: initial))
        #expect(frame.boardState.board.tiles.filter { hidden.contains($0.coordinate) }.allSatisfy {
            $0.kind == .fog && $0.numberToken == nil
        })
        #expect(projected.ships == authoritative.ships)
        #expect(projected.revealed == authoritative.revealed)
        #expect(projected.colonyPoints == authoritative.colonyPoints)
        #expect(projected.colonyPoints[human] == 1)
        #expect(projected.islandByHex.isEmpty && projected.colonizedIslands.isEmpty)
        #expect(projected.pendingResourceChoices.isEmpty && projected.productionRollerIndex == nil)
        #expect(!projected.capturePending && projected.generationAttempts == 0 && !projected.usedFallback)
        #expect(projected.options.mapFamily == nil && projected.mapFamily == .archipelago)
        #expect(frame.boardState.players.allSatisfy { $0.resources.isEmpty && $0.devCards.isEmpty })
        #expect(frame.boardState.devCardDeck.isEmpty && frame.boardState.bank.isEmpty)
        #expect(frame.boardState.rng == RandomSource(seed: 0))
        #expect(frame.publicScores[0] == initial.publicVictoryPoints(for: human))
        #expect(frame.publicScores[0] < initial.victoryPoints(for: human))
        #expect(sequence.closingFrame(from: frame).publicScores == frame.publicScores)
    }

    @Test func concealedGeographyHandsAndSeedsCannotChangeAMovieFrame() throws {
        let initial = try NavalQAFixture.make(.voyage)
        let naval = try #require(initial.naval)
        let hidden = try #require(initial.board.tiles.firstIndex {
            !naval.revealed.contains($0.coordinate) && $0.kind == .resourceChoice
        })
        let coordinate = initial.board.tiles[hidden].coordinate
        let corners = initial.board.corners(of: coordinate)
        var first = try ReplayExportSequence(detail: ReplayExportFixtures.detail(initial: initial))
        let original = try #require(try first.next())
        // Synthetic private-data variations deliberately cover sea versus land,
        // ordinary versus any-resource production, tokens and concealed ports.
        // Complete projected-state equality detects leaks even if today's
        // renderer happens not to draw the offending field.
        for kind in [TileKind.sea, .resource(.ore), .resourceChoice] {
            var altered = initial
            var tiles = altered.board.tiles
            tiles[hidden] = Tile(coordinate: coordinate, kind: kind, numberToken: kind.produces ? 11 : nil)
            let ports = altered.board.ports + [Port(vertexA: corners[0], vertexB: corners[1], kind: .resource(.ore))]
            altered.board = Board(tiles: tiles, ports: ports, onBoardVertices: altered.board.onBoardVertices,
                                  onBoardEdges: altered.board.onBoardEdges, robberTile: altered.board.robberTile)
            altered.garrisons[coordinate] = Garrison(owner: PlayerID(index: 1), strength: 9)
            altered.naval?.islandByHex[coordinate] = 999
            altered.naval?.generationAttempts = 64
            altered.naval?.usedFallback = true
            altered.naval?.mapFamily = .peninsula
            altered.rng = RandomSource(seed: 999)
            altered.players[1].resources = [.ore: 29]
            altered.players[1].devCards = [.victoryPoint, .monopoly]
            altered.devCardDeck.reverse()
            var second = try ReplayExportSequence(detail: ReplayExportFixtures.detail(initial: altered))
            let redacted = try #require(try second.next())
            #expect(original.boardState == redacted.boardState)
            #expect(original.publicScores == redacted.publicScores)
            #expect(original.caption == redacted.caption)
        }
    }

    @Test(arguments: [NavalQAFixture.Position.harvest, .capture])
    func mandatoryNavalDecisionCannotAdvanceOrReconcileAStoredOffer(position: NavalQAFixture.Position) async throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.startNewGame(setup: fixture.setup)
        var initial = try NavalQAFixture.make(position)
        for (seat, resource) in [(PlayerID(index: 1), Resource.ore), (human, Resource.wool)] {
            let missing = max(0, 1 - initial.players[seat.index].resources[resource, default: 0])
            initial.bank[resource, default: 0] -= missing
            initial.players[seat.index].resources[resource, default: 0] += missing
        }
        let offer = TradeOffer(from: PlayerID(index: 1), give: [.ore: 1], want: [.wool: 1])
        #expect(Trading.bothSidesCanHonour(offer, responder: human, state: initial))
        initial.pendingTradeOffers = [offer]
        let policies = Dictionary(uniqueKeysWithValues: initial.players.dropFirst().map {
            ($0.id, NavalPolicy(tier: .expert) as any Policy)
        })
        try GameSession(state: initial, policies: policies, policySeed: 44).checkpoint.validate()
        model.replaceStateForTesting(initial, humanSeat: human, difficulty: .expert)
        defer { model.isBlockingSurfaceOpen = true }
        let before = model.checkpointDocument
        let cursor = model.session.checkpoint

        #expect(model.hasMandatoryHumanNavalDecision)
        #expect(model.openIncomingOffer == nil)
        try model.reconcileHumanTradeOffers()
        model.skipBotPauses()
        await model.runBotTurnIfNeeded()

        #expect(model.checkpointDocument == before)
        #expect(model.session.checkpoint == cursor)
        #expect(fixture.makeModel().session.checkpoint == cursor)
    }

    @Test func migrationPreservesRecordedNavalRulesAndDecisionOrigin() throws {
        let fixture = try CheckpointModelFixture()
        let initial = try NavalQAFixture.make(.voyage)
        var setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: .greece)
        setup.mode = .naval
        setup.victoryPointTarget = initial.victoryPointTarget
        setup.navalOptions = try #require(initial.naval?.options)
        setup.expertRevision = setup.difficulty == .expert ? .navalV1 : .legacy
        setup.navalAIRevision = .legacyV1
        let civilizations = Array(Civilization.allCases.prefix(initial.players.count))
        let profiles = GameViewModel.opponentProfiles(for: initial, humanSeats: [human], civilizations: civilizations)
        setup = GameViewModel.realisedMatch(chairs: setup.seats, civilizations: civilizations,
                                           opponentProfiles: profiles, from: setup)
        #expect(setup.realizedIdentityProblem == nil)
        let policies = GameViewModel.makePolicies(profiles, difficulty: setup.difficulty,
            ghosts: fixture.makeModel().ghostStore, expertRevision: setup.expertRevision, mode: .naval)
        var session = GameSession(state: initial, policies: policies, policySeed: 44)
        var match = MatchCheckpoint(id: UUID(), initialState: initial, setup: setup)
        let purchase = try #require(RulesEngine.legalMoves(for: initial, seat: human).first {
            if case .buildShip = $0 { return true }
            return false
        })
        try session.applyExternal(purchase, by: human)
        try match.apply(purchase, by: human, isHumanDecision: false)
        let url = try fixture.logStore.export(checkpoint: match)
        let detail = try fixture.logStore.detail(for: url)

        let migrated = try MatchCheckpointMigration.prepare(session: session.checkpoint, setup: setup,
            statistics: fixture.statsStore, activeLog: detail)
        let restored = try #require(migrated.activeMatch)

        #expect(restored.state == match.state)
        #expect(restored.moves.map(\.rulesVersion) == [RulesEngine.currentRulesVersion])
        #expect(restored.moves.map(\.isHumanDecision) == [false])
        #expect(restored.sessionCheckpoint == session.checkpoint)
    }

    @Test func interactiveReplayUsesTheSameKnownRulesAsMovieExport() throws {
        let fixture = try CheckpointModelFixture()
        let detail = try ReplayExportFixtures.mixedRulesRecording(directory: fixture.root.appendingPathComponent("mixed"))
        let timeline = GameReplayTimeline(detail: detail)
        var expected = detail.initialState
        for entry in detail.events {
            try RulesEngine.replay(entry.move, by: entry.player,
                                   rulesVersion: try #require(entry.rulesVersion), to: &expected)
        }
        #expect(timeline.truncation == nil)
        #expect(timeline.frames.count == detail.events.count + 1)
        #expect(timeline.frames.last?.state == expected)
    }

    @Test func movieWorldOverviewUsesTheFullViewportWithoutLiveNavigation() {
        let state = Naval.newGame(seed: 7501)
        let live = BoardView(state: state, decision: nil, onSelectTarget: { _ in })
        let movie = BoardView(state: state, decision: nil, onSelectTarget: { _ in },
                              allowsGameCommands: false, animatesStateChanges: false).staticWorldOverview()
        let container = CGSize(width: 402, height: 400)
        #expect(live.showsNavigationControls)
        #expect(live.worldViewport(in: container).height == 344)
        #expect(!movie.showsNavigationControls && !movie.animatesStateChanges)
        #expect(movie.worldViewport(in: container) == container)
        #expect(movie.camera == .fitted)
    }
}
