import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@MainActor
@Suite(.serialized)
struct GameViewModelCheckpointTests {
    @Test func successfulExportOnlyClearsAnExportWarning() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.gameLogWarning = "The recording is preserved in a recovery backup."

        model.exportCommittedRecordings()

        #expect(model.gameLogWarning == "The recording is preserved in a recovery backup.")
    }

    @Test func newGameSetupAvailabilityIsReadOnceByTheModelOwner() throws {
        let fixture = try CheckpointModelFixture()
        try fixture.setupStore.save(fixture.setup)
        let model = fixture.makeModel()
        var later = fixture.setup
        later.victoryPointTarget = 12
        try fixture.setupStore.save(later)

        #expect(model.newGameSetupLoadResult == .loaded(fixture.setup))
    }

    @Test func successfulExportDoesNotEraseUnrecoverableHistoricalStatisticsWarning() throws {
        let fixture = try CheckpointModelFixture()
        let url = fixture.root.appendingPathComponent("match_checkpoint.json")
        try Data("unreadable checkpoint".utf8).write(to: url)
        let model = fixture.makeModel()
        #expect(!model.savedGameAvailability.canResume)
        model.startNewGame(setup: fixture.setup)
        #expect(model.savedGameAvailability.canResume)
        #expect(model.gameLogWarning?.contains("could not be restored automatically") == true)
        model.isBlockingSurfaceOpen = true
        let move = try #require(RulesEngine.legalMoves(for: model.state, seat: model.humanPlayer).first)
        try model.apply(move)
        #expect(try fixture.logStore.summaries().count == 1)
        #expect(model.gameLogWarning?.contains("could not be restored automatically") == true)
    }

    /// Clearing the finished match must not clear what it contributed to the
    /// lifetime totals. There is no longer a stats reset anywhere in the app,
    /// so this is the only thing standing between a played game and its
    /// disappearance from the menu's stats row.
    @Test func completedMatchStatisticsSurviveReloadAndClear() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.startNewGame(setup: fixture.setup)
        model.qaPlayToEnd()
        #expect(model.statistics.gamesPlayed == 1)
        let resumed = fixture.makeModel()
        #expect(resumed.statistics == model.statistics)
        #expect(resumed.clearCompletedMatch())
        let cleared = fixture.makeModel()
        #expect(cleared.statistics.gamesPlayed == 1)
        #expect(!cleared.savedGameAvailability.canResume)
    }

    @Test func candidateDocumentFailureStopsBotsAsPersistenceFailure() async throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        var setup = fixture.setup
        setup.seats[0].isHuman = false
        setup.seats[0].name = ""
        setup.seats[2].isHuman = true
        setup.seats[2].name = "Alex"
        model.startNewGame(setup: setup)
        let before = model.state
        model.accumulatedActiveDuration = .infinity
        await model.runBotTurnIfNeeded()
        #expect(model.state == before)
        #expect(model.persistenceBlocked)
        #expect(model.persistenceErrorMessage != nil)
        #expect(model.retryPersistence())
        #expect(model.state == before)
        #expect(!model.persistenceBlocked)
    }

    @Test func replacingReadableButRejectedRosterPreservesStatisticsAndArchivesOriginalBytes() throws {
        let fixture = try CheckpointModelFixture()
        fixture.statsStore.recordGameEnd(won: true, finalVP: 8, duration: 60)
        let initial = fixture.makeModel()
        initial.startNewGame(setup: fixture.setup)
        initial.appWillResignActive()
        let url = initial.checkpointStore.fileURL
        var wire = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var match = try #require(wire["activeMatch"] as? [String: Any])
        var setup = try #require(match["setup"] as? [String: Any])
        var seats = try #require(setup["seats"] as? [[String: Any]])
        seats[1]["civilization"] = Civilization.allCases[2].rawValue
        setup["seats"] = seats
        match["setup"] = setup
        wire["activeMatch"] = match
        let rejectedBytes = try JSONSerialization.data(withJSONObject: wire)
        try rejectedBytes.write(to: url, options: .atomic)
        let blocked = fixture.makeModel()
        #expect(!blocked.savedGameAvailability.canResume)
        #expect(blocked.statistics.gamesPlayed == 1)
        blocked.startNewGame(setup: fixture.setup)
        #expect(blocked.savedGameAvailability.canResume)
        #expect(blocked.statistics.gamesPlayed == 1)
        #expect(blocked.checkpointDocument?.pendingExports.isEmpty == true)
        #expect(fixture.makeModel().statistics.gamesPlayed == 1)
        let recovery = url.deletingLastPathComponent().appendingPathComponent("Recovery")
        let copies = try FileManager.default.subpathsOfDirectory(atPath: recovery.path)
            .filter { $0.hasSuffix("checkpoint.json") }
        #expect(try copies.contains {
            try Data(contentsOf: recovery.appendingPathComponent($0)) == rejectedBytes
        })
    }

    @Test func failedTradeConfirmationAndDeclineKeepTheOfferAvailableForRetry() throws {
        let fixture = try CheckpointModelFixture()
        var refuseWrite = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if refuseWrite, stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        var position = GameSetup.newGame(board: BoardGenerator.standard(), seed: 33, playerCount: 3)
        position.phase = .mainTurn(playerIndex: 0)
        position.players[0].resources = [.grain: 6]
        position.players[1].resources = [.brick: 2]
        position.bank[.grain] = 13
        position.bank[.brick] = 17
        model.replaceStateForTesting(position, humanSeat: PlayerID(index: 0))
        model.isBlockingSurfaceOpen = true
        let offer = TradeOffer(from: model.humanPlayer, give: [.grain: 4], want: [.brick: 1])
        try model.apply(.proposeTrade(offer))
        let pending = try #require(model.pendingTradeConfirmation)
        let before = model.state
        refuseWrite = true
        #expect(model.confirmPendingTrade() == .persistenceFailed)
        #expect(model.state == before)
        #expect(model.pendingTradeConfirmation?.offerID == pending.offerID)
        model.declinePendingTrade()
        #expect(model.state == before)
        #expect(model.pendingTradeConfirmation?.offerID == pending.offerID)
        #expect(fixture.makeModel().pendingTradeConfirmation?.offerID == pending.offerID)
        refuseWrite = false
        #expect(model.confirmPendingTrade() == .succeeded)
        #expect(model.pendingTradeConfirmation == nil)
        #expect(model.state.players[0].resources[.brick] == 1)
        #expect(fixture.makeModel().state == model.state)
    }

    @Test(arguments: [false, true])
    func aPauseOpenedDuringBotPacingPreventsItsMove(background: Bool) async throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        var setup = fixture.setup
        setup.seats[0].isHuman = false
        setup.seats[0].name = ""
        setup.seats[2].isHuman = true
        setup.seats[2].name = "Alex"
        model.startNewGame(setup: setup)
        let before = model.state
        let cursor = model.session.checkpoint
        let loop = Task { await model.runBotTurnIfNeeded() }
        try await Task.sleep(for: .milliseconds(50))
        if background { model.appWillResignActive() } else { model.isBlockingSurfaceOpen = true }
        await loop.value
        #expect(model.state == before)
        #expect(model.session.checkpoint == cursor)
        #expect(fixture.makeModel().state == before)
    }

    @Test func failedBotWriteLeavesThePolicyCursorAndBoardUnchanged() async throws {
        let fixture = try CheckpointModelFixture()
        var refuseWrite = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if refuseWrite, stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        var setup = fixture.setup
        setup.seats[0].isHuman = false
        setup.seats[0].name = ""
        setup.seats[2].isHuman = true
        setup.seats[2].name = "Alex"
        model.startNewGame(setup: setup)
        let before = model.state
        let cursor = model.session.checkpoint
        refuseWrite = true
        await model.runBotTurnIfNeeded()
        #expect(model.state == before)
        #expect(model.session.checkpoint == cursor)
        #expect(model.persistenceErrorMessage != nil)
        #expect(fixture.makeModel().session.checkpoint == cursor)
    }

    @Test func clearedCheckpointDoesNotResurrectPreservedLegacySave() throws {
        let fixture = try CheckpointModelFixture()
        let legacy = GameSetup.newGame(board: BoardGenerator.standard(), seed: 55, playerCount: 3)
        try fixture.gameStore.save(legacy)
        let model = fixture.makeModel()
        model.qaForceHumanWin()
        #expect(model.clearCompletedMatch())
        let resumed = fixture.makeModel()
        #expect(!resumed.savedGameAvailability.canResume)
        #expect(!resumed.requiresSaveReplacementConfirmation)
        #expect(fixture.gameStore.hasSave(), "migration preserves the source save")
    }

    @Test func bankedDurationSurvivesColdResumeWithoutCountingTimeClosed() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.startNewGame(setup: fixture.setup)
        model.appWillResignActive()
        let banked = model.accumulatedActiveDuration
        let resumed = fixture.makeModel()
        #expect(resumed.accumulatedActiveDuration == banked)
        #expect(resumed.session.checkpoint == model.session.checkpoint)
    }

    @Test func exportFailureDoesNotLoseAReplacedRecording() throws {
        let fixture = try CheckpointModelFixture()
        let blocked = fixture.root.appendingPathComponent("logs")
        try Data("not a directory".utf8).write(to: blocked)
        let model = fixture.makeModel()
        model.startNewGame(setup: fixture.setup)
        model.isBlockingSurfaceOpen = true
        let move = try #require(RulesEngine.legalMoves(for: model.state, seat: model.humanPlayer).first)
        try model.apply(move)
        model.startNewGame(setup: fixture.setup)
        #expect(model.savedGameAvailability.canResume)
        #expect(model.gameLogWarning != nil)
        try FileManager.default.removeItem(at: blocked)
        _ = fixture.makeModel()
        let recordings = try fixture.logStore.summaries()
        #expect(recordings.contains(where: { $0.moveCount == 1 }))
    }

    @Test func failedHumanWriteDoesNotPublishBoardEventsOrPolicyProgress() throws {
        let fixture = try CheckpointModelFixture()
        var refuseWrite = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if refuseWrite, stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        model.startNewGame(setup: fixture.setup)
        model.isBlockingSurfaceOpen = true
        let before = model.state
        let session = model.session.checkpoint
        let move = try #require(RulesEngine.legalMoves(for: before, seat: model.humanPlayer).first)
        refuseWrite = true

        #expect(throws: MatchPersistenceFailure.self) { try model.apply(move) }

        #expect(model.state == before)
        #expect(model.session.checkpoint == session)
        #expect(model.eventBatch.events.isEmpty)
        #expect(fixture.makeModel().state == before)
        refuseWrite = false
        try model.apply(move)
        #expect(model.state.players[0].settlements.count == 1)
    }

    @Test func failedDiscardWriteRetainsTheDraftAcrossReloadAndRetriesExactlyOnce() throws {
        let fixture = try CheckpointModelFixture()
        var refuseWrite = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if refuseWrite, stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        let human = PlayerID(index: 0)
        var position = GameSetup.newGame(
            board: BoardGenerator.standard(), seed: 4_204, playerCount: 3,
            victoryPointTarget: fixture.setup.victoryPointTarget
        )
        position.players[human.index].resources = [.brick: 8]
        position.bank[.brick] = 11
        position.lastDiceRoll = 7
        position.robberMoverIndex = human.index
        position.phase = .discarding(pending: [human])
        model.replaceStateForTesting(position, humanSeat: human)
        for _ in 0..<4 { model.selectForDiscard(.brick) }
        let before = model.state
        let revision = model.checkpointDocument?.revision

        refuseWrite = true
        #expect(!model.submitDiscard())
        #expect(model.state == before)
        #expect(model.checkpointDocument?.revision == revision)
        #expect(model.discardDraft.counts == [.brick: 4])
        #expect(model.discardDraft.errorMessage != nil)

        refuseWrite = false
        #expect(model.retryPersistence())
        #expect(model.state == before)
        #expect(model.discardDraft.counts == [.brick: 4])
        #expect(model.submitDiscard())
        #expect(model.state.players[human.index].resources[.brick] == 4)
        #expect(model.discardDraft.counts.isEmpty)
        guard case .movingRobber(let playerIndex) = model.state.phase else {
            Issue.record("the committed retry did not advance to robber placement")
            return
        }
        #expect(playerIndex == human.index)
    }

    @Test func hotSeatReloadKeepsTheClaimedDiscardersDraft() throws {
        let fixture = try CheckpointModelFixture()
        var refuseWrite = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if refuseWrite, stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        let first = PlayerID(index: 0)
        let discarder = PlayerID(index: 1)
        var position = GameSetup.newGame(
            board: BoardGenerator.standard(), seed: 4_205, playerCount: 3,
            victoryPointTarget: fixture.setup.victoryPointTarget
        )
        position.players[discarder.index].resources = [.brick: 8]
        position.bank[.brick] = 11
        position.lastDiceRoll = 7
        position.robberMoverIndex = first.index
        position.phase = .discarding(pending: [discarder])
        model.replaceStateForTesting(position, humanSeats: [first, discarder])
        model.claimDeviceForSeatOwedATurn()
        for _ in 0..<4 { model.selectForDiscard(.brick) }

        refuseWrite = true
        #expect(!model.submitDiscard())
        #expect(model.humanPlayer == discarder)
        #expect(model.discardDraft.counts == [.brick: 4])

        refuseWrite = false
        #expect(model.retryPersistence())
        #expect(model.humanPlayer == discarder)
        #expect(model.discardDraft.counts == [.brick: 4])
    }

    @Test func lostWriteAcknowledgementPublishesExactlyTheCommittedMove() throws {
        let fixture = try CheckpointModelFixture()
        var interrupt = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if interrupt, stage == .afterReplace { throw CocoaError(.fileWriteUnknown) }
        })
        model.startNewGame(setup: fixture.setup)
        model.isBlockingSurfaceOpen = true
        interrupt = true
        let move = try #require(RulesEngine.legalMoves(for: model.state, seat: model.humanPlayer).first)
        try model.apply(move)
        #expect(model.state.players[0].settlements.count == 1)
        #expect(fixture.makeModel().state == model.state)
        #expect(model.persistenceErrorMessage == nil)
    }

    @Test func failedReplacementKeepsTheOldTableAndLabels() throws {
        let fixture = try CheckpointModelFixture()
        var refuseWrite = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if refuseWrite, stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        model.startNewGame(setup: fixture.setup)
        let before = model.state
        let generation = model.gameGeneration
        var next = fixture.setup
        next.seats[0].name = "Replacement"
        refuseWrite = true
        model.startNewGame(setup: next)
        #expect(model.state == before)
        #expect(model.gameGeneration == generation)
        #expect(model.playerLabel(for: model.humanPlayer) == "Alex")
        #expect(fixture.makeModel().state == before)
    }

    @Test func statsOnlyMigrationSurvivesColdLaunch() throws {
        let fixture = try CheckpointModelFixture()
        fixture.statsStore.recordGameEnd(won: true, finalVP: 8, duration: 60)
        let model = fixture.makeModel()
        #expect(model.statistics.gamesPlayed == 1)
        #expect(!model.savedGameAvailability.canResume)
        // The legacy file is migrated, never consumed: it stays on disk with
        // its original contents so a failed migration can be retried.
        #expect(fixture.makeModel().statistics.gamesPlayed == 1)
        #expect(fixture.statsStore.load().gamesPlayed == 1)
    }

    @Test func coldResumeUsesCommittedMatchInsteadOfStaleLegacyFiles() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.startNewGame(setup: fixture.setup)
        model.isBlockingSurfaceOpen = true
        let move = try #require(RulesEngine.legalMoves(for: model.state, seat: model.humanPlayer).first)
        try model.apply(move)
        let committed = model.state

        try fixture.gameStore.save(GameSetup.newGame(board: BoardGenerator.standard(), seed: 999))
        fixture.setupStore.restore(Data("stale roster".utf8), forActiveMatch: true)
        let resumed = fixture.makeModel()

        #expect(resumed.savedGameAvailability.canResume)
        #expect(resumed.state == committed)
        #expect(resumed.playerLabel(for: resumed.humanPlayer) == "Alex")
    }

    @Test func restartingALegacyFourPlayerEpicMatchUsesAReachableTarget() throws {
        let fixture = try CheckpointModelFixture()
        let state = GameSetup.newGame(
            board: BoardGenerator.standard(), seed: 8112,
            playerCount: 4, victoryPointTarget: 12
        )
        let civilizations = Array(Civilization.allCases.prefix(4))
        let human = PlayerID(index: 0)
        let profiles = GameViewModel.opponentProfiles(
            for: state, humanSeats: [human], civilizations: civilizations
        )
        let setup = MatchSetup(
            seats: (0..<4).map { index in
                MatchSetup.Seat(
                    index: index,
                    isHuman: index == 0,
                    name: index == 0 ? "Alex" : "",
                    civilization: civilizations[index],
                    opponentProfile: profiles[PlayerID(index: index)]
                )
            },
            victoryPointTarget: 12,
            randomizedBoard: false,
            randomizeSeatOrder: false
        )
        let session = GameViewModel.makeSession(state: state, opponentProfiles: profiles, difficulty: .classic)
        var match = MatchCheckpoint(id: UUID(), initialState: state, setup: setup)
        try match.attachSession(session.checkpoint)
        let store = MatchCheckpointStore(
            fileURL: fixture.root.appendingPathComponent("match_checkpoint.json")
        )
        try store.commit(MatchCheckpointDocument(activeMatch: match), replacingRevision: nil)

        let resumed = fixture.makeModel()
        #expect(resumed.state.victoryPointTarget == 12,
                "the legacy match must remain resumable at its original target")

        resumed.restartCurrentMatch(fallbackRandomizedBoard: true, fallbackRandomizeSeat: true)

        #expect(resumed.state.victoryPointTarget == Ruleset.forMode(.classic).defaultVictoryPointTarget)
        #expect(resumed.checkpointDocument?.activeMatch?.setup.victoryPointTarget
                == Ruleset.forMode(.classic).defaultVictoryPointTarget)
        #expect(resumed.savedGameAvailability.canResume)
    }
}

@MainActor
final class CheckpointModelFixture {
    let root: URL
    let defaults: UserDefaults
    let defaultsName: String
    let gameStore: GameStore
    let setupStore: MatchSetupStore
    let civilizationStore: CivilizationAssignmentStore
    let logStore: GameLogStore
    let statsStore: GameStatsStore

    var setup: MatchSetup {
        MatchSetup(seats: (0..<3).map {
            MatchSetup.Seat(index: $0, isHuman: $0 == 0, name: $0 == 0 ? "Alex" : "",
                            civilization: Civilization.allCases[$0])
        }, victoryPointTarget: 10, randomizedBoard: false, randomizeSeatOrder: false)
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CheckpointModel.\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaultsName = "CheckpointModel.\(UUID())"
        defaults = try #require(UserDefaults(suiteName: defaultsName))
        let store = MatchSetupStore()
        store.defaults = defaults
        setupStore = store
        gameStore = GameStore(fileURL: root.appendingPathComponent("save.json"))
        civilizationStore = CivilizationAssignmentStore(fileURL: root.appendingPathComponent("civilizations.json"))
        logStore = GameLogStore(directoryURL: root.appendingPathComponent("logs"), maxKeptLogs: 10)
        statsStore = GameStatsStore(fileURL: root.appendingPathComponent("stats.json"))
    }

    func makeModel(atCommitStage: @escaping (MatchCheckpointStore.CommitStage) throws -> Void = { _ in }) -> GameViewModel {
        let store = MatchCheckpointStore(fileURL: root.appendingPathComponent("match_checkpoint.json"),
                                         atCommitStage: atCommitStage)
        return GameViewModel(checkpointStore: store, gameStore: gameStore, civilizationStore: civilizationStore,
                      matchSetupStore: setupStore, gameLogStore: logStore, gameStatsStore: statsStore)
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: defaultsName)
        try? FileManager.default.removeItem(at: root)
    }
}

/// Legacy view-model tests also need isolated checkpoint authority. Retain the
/// fixture through the injected store hook so its lifetime matches the model.
@MainActor
func isolatedGameViewModel() -> GameViewModel {
    do {
        let fixture = try CheckpointModelFixture()
        return fixture.makeModel(atCommitStage: { [fixture] _ in _ = fixture })
    } catch { preconditionFailure("Could not create isolated test model: \(error)") }
}
