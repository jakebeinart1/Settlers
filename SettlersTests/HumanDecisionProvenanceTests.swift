import CatanAI
import CatanEngine
import Foundation
import Testing
@testable import Settlers

/// Exercise real app responses through the candidate session, checkpoint,
/// reload and JSONL seam. No bot experiment or training write is started.
@MainActor
@Suite(.serialized)
struct HumanDecisionProvenanceTests {
    enum Origin: String, CaseIterable, Sendable {
        case automatic, timeout, manualDecline, manualAccept
        var isHumanDecision: Bool { self == .manualDecline || self == .manualAccept }
    }

    @Test(arguments: Origin.allCases)
    func responseOriginSurvivesCheckpointArchiveAndReload(origin: Origin) throws {
        let fixture = try CheckpointModelFixture()
        let (model, offer) = try proposal(origin: origin, fixture: fixture)
        defer { model.isBlockingSurfaceOpen = true }
        try respond(origin: origin, offer: offer, model: model)
        let match = try #require(model.checkpointDocument?.activeMatch)
        #expect(match.moves.count == 2, "Do not drop automatic responses from history")
        #expect(match.moves.last?.isHumanDecision == origin.isHumanDecision)
        #expect(match.moves.last?.move == .respondToTrade(offerID: offer.id, accept: origin == .manualAccept))
        #expect(match.state.pendingTradeOffers.isEmpty)

        let reloaded = fixture.makeModel()
        reloaded.isBlockingSurfaceOpen = true
        #expect(reloaded.savedGameAvailability.canResume)
        #expect(reloaded.checkpointDocument?.activeMatch?.moves == match.moves)
        #expect(reloaded.state == match.state)
        let url = try fixture.logStore.export(checkpoint: match)
        let detail = try fixture.logStore.detail(for: url)
        #expect(detail.events.map(\.isHumanDecision) == match.moves.map(\.isHumanDecision))
        #expect(detail.events.map(\.move) == match.moves.map(\.move))
        var replay = detail.initialState
        for event in detail.events {
            let version = try #require(event.rulesVersion)
            try RulesEngine.replay(event.move, by: event.player, rulesVersion: version, to: &replay)
        }
        #expect(replay == match.state, "Non-training moves must still advance the complete replay")

        // Only supply an end marker to exercise catch-up's archive selection;
        // this small response fixture is not evidence of a completed game.
        try fixture.logStore.finalizeGame(gameID: match.id, winner: model.humanPlayer)
        let catchUp = GameViewModel.catchUpGames(logs: fixture.logStore, rated: [match.id], me: "provenance-test")
        let game = try #require(catchUp.first?.game)
        #expect(game.events.map(\.isHumanDecision) == match.moves.map(\.isHumanDecision))
        #expect(game.events.map(\.move) == match.moves.map(\.move))
    }

    @Test func legacyCheckpointAndArchiveWithoutOriginKeepPriorTrainingBehavior() throws {
        let fixture = try CheckpointModelFixture()
        let (model, offer) = try proposal(origin: .automatic, fixture: fixture)
        try respond(origin: .automatic, offer: offer, model: model)
        model.isBlockingSurfaceOpen = true
        let match = try #require(model.checkpointDocument?.activeMatch)
        #expect(match.moves.last?.isHumanDecision == false)
        let checkpointURL = model.checkpointStore.fileURL
        let checkpointObject = try JSONSerialization.jsonObject(with: Data(contentsOf: checkpointURL))
        var document = try #require(checkpointObject as? [String: Any])
        var active = try #require(document["activeMatch"] as? [String: Any])
        var moves = try #require(active["moves"] as? [[String: Any]])
        for index in moves.indices { moves[index].removeValue(forKey: "isHumanDecision") }
        active["moves"] = moves
        document["activeMatch"] = active
        try JSONSerialization.data(withJSONObject: document).write(to: checkpointURL, options: .atomic)
        let reloaded = fixture.makeModel()
        reloaded.isBlockingSurfaceOpen = true
        #expect(reloaded.savedGameAvailability.canResume)
        let oldMatch = try #require(reloaded.checkpointDocument?.activeMatch)
        let checkpointDefaultsToHuman = oldMatch.moves.allSatisfy { $0.isHumanDecision }
        #expect(checkpointDefaultsToHuman)
        #expect(oldMatch.state == match.state)

        let url = try fixture.logStore.export(checkpoint: match)
        let bytes = try Data(contentsOf: url)
        var legacy = Data()
        for line in bytes.split(separator: 0x0A) {
            let decoded = try JSONSerialization.jsonObject(with: Data(line))
            var entry = try #require(decoded as? [String: Any])
            entry.removeValue(forKey: "isHumanDecision")
            legacy.append(try JSONSerialization.data(withJSONObject: entry))
            legacy.append(0x0A)
        }
        try legacy.write(to: url)
        let oldArchive = try fixture.logStore.detail(for: url)
        #expect(oldArchive.events.count == match.moves.count)
        let archiveDefaultsToHuman = oldArchive.events.allSatisfy { $0.isHumanDecision }
        #expect(archiveDefaultsToHuman)
        #expect(oldArchive.events.map(\.move) == match.moves.map(\.move))
    }

    @Test(arguments: [Origin.automatic, .timeout])
    func failedNonHumanResponseDoesNotPublishAMoveOrOrigin(origin: Origin) throws {
        let fixture = try CheckpointModelFixture()
        var refuseWrite = false
        let (model, offer) = try proposal(origin: origin, fixture: fixture, atCommitStage: { stage in
            if refuseWrite, stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        if origin == .timeout { try model.reconcileHumanTradeOffers() }
        let before = model.checkpointDocument
        let cursor = model.session.checkpoint
        let bytes = try Data(contentsOf: model.checkpointStore.fileURL)
        refuseWrite = true
        #expect(throws: MatchPersistenceFailure.self) { try respond(origin: origin, offer: offer, model: model) }
        #expect(model.persistenceBlocked)
        #expect(model.checkpointDocument == before)
        #expect(model.session.checkpoint == cursor)
        #expect(try Data(contentsOf: model.checkpointStore.fileURL) == bytes)
        model.isBlockingSurfaceOpen = true
    }

    @Test func defaultedConstructorsAndAppendRemainHumanDecisions() throws {
        let fixture = try CheckpointModelFixture()
        let initial = GameSetup.newGame(board: BoardGenerator.standard(), seed: 34)
        let actor = initial.players[0].id
        let move = try #require(RulesEngine.legalMoves(for: initial, seat: actor).first)
        #expect(MatchCheckpoint.RecordedMove(actor: actor, move: move, timestamp: Date()).isHumanDecision)
        #expect(GameLogEvent(timestamp: Date(), player: actor, move: move).isHumanDecision)
        #expect(LoggedMove(player: actor, move: move).isHumanDecision)
        let id = try fixture.logStore.startNewGame(initialState: initial, roster: .legacy(humanSeat: actor))
        try fixture.logStore.appendMove(gameID: id, player: actor, move: move)
        let summary = try fixture.logStore.summary(for: id)
        let present = try #require(summary)
        #expect(try fixture.logStore.detail(for: present).events.first?.isHumanDecision == true)
        var next = initial
        try RulesEngine.apply(move, by: actor, to: &next)
        let following = try #require(RulesEngine.legalMoves(for: next, seat: actor).first)
        try fixture.logStore.appendMove(gameID: id, player: actor, move: following, isHumanDecision: false)
        #expect(try fixture.logStore.detail(for: present).events.map(\.isHumanDecision) == [true, false])
    }

    private func proposal(origin: Origin, fixture: CheckpointModelFixture,
                          atCommitStage: @escaping (MatchCheckpointStore.CommitStage) throws -> Void = { _ in }) throws
        -> (GameViewModel, TradeOffer) {
        let model = fixture.makeModel(atCommitStage: atCommitStage)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 33, playerCount: 3)
        state.phase = .mainTurn(playerIndex: 1)
        state.players[0].resources = [.lumber: 4, .brick: 2]
        state.players[1].resources = [.ore: 2, .wool: 2]
        state.players[2].resources = [.grain: 2, .wool: 2]
        for resource in Resource.allCases {
            state.bank[resource] = 19 - state.players.reduce(0) { $0 + $1.resources[resource, default: 0] }
        }
        if origin == .automatic {
            let port = try #require(state.board.ports.first { $0.kind == .resource(.lumber) })
            state.players[0].settlements.insert(port.vertexA)
        }
        model.replaceStateForTesting(state, humanSeat: PlayerID(index: 0))
        let offer = TradeOffer.enumerated(from: PlayerID(index: 1), give: [.ore: origin == .automatic ? 2 : 1],
                                          want: [.lumber: origin == .automatic ? 4 : 1])
        var candidate = model.session
        let step = try candidate.commit(seat: offer.from, move: .proposeTrade(offer))
        try model.commitStep(step, candidate: candidate)
        return (model, offer)
    }

    private func respond(origin: Origin, offer: TradeOffer, model: GameViewModel) throws {
        try model.reconcileHumanTradeOffers()
        guard origin != .automatic else { return }
        model.isBlockingSurfaceOpen = true // Fence the response's scheduled runner.
        try model.respondToIncomingTrade(offer, accept: origin == .manualAccept, explicit: origin.isHumanDecision)
    }
}
