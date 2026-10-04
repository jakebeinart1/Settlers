import Foundation
import Testing
import CatanAI
@testable import CatanEngine
@testable import Settlers

/// Revision selection belongs to a new-match transaction; disk restoration and
/// restart must keep the brain that actually played the saved match.
@MainActor @Suite(.serialized)
struct ExpertRevisionTests {
    @Test func initializerAndJSONWithoutRevisionKeepLegacyExpert() throws {
        let setup = expertSetup()
        #expect(setup.expertRevision == .legacy)
        var wire = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(setup)) as? [String: Any])
        wire.removeValue(forKey: "expertRevision")
        let restored = try JSONDecoder().decode(MatchSetup.self, from: JSONSerialization.data(withJSONObject: wire))
        #expect(restored.difficulty == .expert)
        #expect(restored.expertRevision == .legacy)
        #expect(ExpertRevision.legacy.policyID == "evaluation-v1")
        #expect(ExpertRevision.cityProductionV1.policyID == "evaluation-city-production-v1")
    }

    @Test func unknownRevisionBlocksColdResumeWithoutRewritingBytes() throws {
        try withFixture { fixture in
            let model = makeModel(fixture)
            model.startNewGame(setup: expertSetup())
            _ = try requireMatch(model, revision: .cityProductionV1)
            let url = model.checkpointStore.fileURL
            let bytes = try rewriteRevision(at: url, as: "future-expert-revision")
            #expect(throws: DecodingError.self) { try MatchCheckpointStore(fileURL: url).load() }

            let restored = makeModel(fixture)

            #expect(!restored.savedGameAvailability.canResume)
            #expect(restored.savedGameAvailability.recoveryMessage != nil)
            #expect(restored.persistenceBlocked)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    // A nonzero human chair is the deterministic equivalent of Random seating,
    // without a probabilistic retry loop in the regression suite.
    @Test(arguments: [0, 3])
    func supportedNewMatchPersistsCityPolicyThroughColdResumeAndRestart(humanChair: Int) throws {
        try withFixture { fixture in
            let model = makeModel(fixture)
            model.startNewGame(setup: expertSetup(humanChair: humanChair))
            let started = try requireMatch(model, revision: .cityProductionV1)
            #expect(model.humanPlayer == PlayerID(index: humanChair))

            let restored = makeModel(fixture)
            #expect(try requireMatch(restored, revision: .cityProductionV1) == started)
            #expect(restored.session.checkpoint == model.session.checkpoint)
            #expect(restored.humanPlayer == PlayerID(index: humanChair))
            restored.restartCurrentMatch(fallbackRandomizedBoard: true, fallbackRandomizeSeat: true)
            let restarted = try requireMatch(restored, revision: .cityProductionV1)
            #expect(restarted.id != started.id)
            #expect(restarted.setup.seats == started.setup.seats)
            #expect(try requireMatch(makeModel(fixture), revision: .cityProductionV1) == restarted)
        }
    }

    @Test func oldExpertCheckpointWithoutRevisionColdResumesAndRestartsOnLegacy() throws {
        try withFixture { fixture in
            let model = makeModel(fixture)
            let setup = expertSetup()
            // Author a pre-update match through the revision-preserving path;
            // public New Game deliberately promotes this supported table.
            model.startNewGame(setup: setup, configuredAs: setup)
            let old = try requireMatch(model, revision: .legacy)
            let bytes = try rewriteRevision(at: model.checkpointStore.fileURL, as: nil)

            let restored = makeModel(fixture)
            #expect(try requireMatch(restored, revision: .legacy) == old)
            #expect(restored.session.checkpoint == model.session.checkpoint)
            #expect(try Data(contentsOf: restored.checkpointStore.fileURL) == bytes)
            restored.restartCurrentMatch(fallbackRandomizedBoard: true, fallbackRandomizeSeat: true)
            let restarted = try requireMatch(restored, revision: .legacy)
            #expect(restarted.id != old.id)
            #expect(try requireMatch(makeModel(fixture), revision: .legacy) == restarted)
        }
    }

    @Test(arguments: ["conquest", "expanded", "vast", "threeSeats", "eightPoints", "twoHumans", "ghost"])
    func unsupportedNewTablesSelectLegacyAndColdResume(configuration: String) throws {
        try withFixture { fixture in
            let model = makeModel(fixture)
            var setup = expertSetup()
            setup.expertRevision = .cityProductionV1
            switch configuration {
            case "conquest": setup.variant = .conquest
            case "expanded":
                setup.mode = .expanded
                setup.victoryPointTarget = Ruleset.forMode(.expanded).defaultVictoryPointTarget
            case "vast":
                setup.mode = .vast
                setup.victoryPointTarget = Ruleset.forMode(.vast).defaultVictoryPointTarget
            case "threeSeats": setup.seats.removeLast()
            case "eightPoints": setup.victoryPointTarget = 8
            case "twoHumans":
                setup.seats[1].isHuman = true
                setup.seats[1].name = "Sam"
            case "ghost":
                try model.ghostStore.save(GhostProfile(id: "fixture", name: "Fixture Ghost",
                    person: .anchored(at: .forMode(.classic)), lambda: 0.5, gamesLearned: 24))
                setup.seats[2].ghostID = "fixture"
            default: preconditionFailure("Unknown test configuration: \(configuration)")
            }
            model.startNewGame(setup: setup)
            let started = try requireMatch(model, revision: .legacy)
            #expect(started.setup.mode == setup.mode)
            #expect(started.setup.variant == setup.variant)
            #expect(started.setup.victoryPointTarget == setup.victoryPointTarget)
            #expect(try requireMatch(makeModel(fixture), revision: .legacy) == started)
        }
    }

    @Test func classicDifficultyKeepsItsHeuristicsEvenWhenCityRevisionIsRequested() throws {
        try withFixture { fixture in
            let model = makeModel(fixture)
            var setup = expertSetup()
            setup.difficulty = .classic
            setup.expertRevision = .cityProductionV1
            model.startNewGame(setup: setup)
            let started = try requireMatch(model, revision: .legacy)
            #expect(started.setup.difficulty == .classic)
            #expect(try requireMatch(makeModel(fixture), revision: .legacy) == started)
            for profile in model.opponentProfiles.values {
                #expect(BotDifficulty.classic.policy(for: profile, expertRevision: .cityProductionV1).id
                    == "heuristic-\(profile.strategy.rawValue)")
            }
        }
    }

    @Test func restartFallbackDoesNotPinTheEditableNewGameBrain() throws {
        try withFixture { fixture in
            let model = makeModel(fixture)
            model.startNewGame(setup: expertSetup())
            fixture.setupStore.clear()
            model.restartCurrentMatch(fallbackRandomizedBoard: false, fallbackRandomizeSeat: false)
            _ = try requireMatch(model, revision: .cityProductionV1)
            let prefill = try #require(fixture.setupStore.load().value)
            var draft = NewGameSetupView.initialSetup(from: .loaded(prefill),
                preferredName: "Alex", preferredCivilization: Civilization.allCases[0]).setup
            #expect(draft.expertRevision == .legacy)
            draft.difficulty = .classic
            #expect(draft.isStartable)
            draft.difficulty = .expert
            draft.variant = .conquest
            #expect(draft.isStartable)
            draft.variant = .standard
            draft.mode = .vast
            draft.normalizeNewGameOptions()
            #expect(draft.isStartable)
            #expect(model.checkpointDocument?.activeMatch?.setup.expertRevision == .cityProductionV1)
        }
    }

    /// This is a full app-owned match (not only package self-play). The QA
    /// driver substitutes a human choice, but commits every move through the
    /// production session/checkpoint/export/result path without pacing sleeps.
    @Test func promotedExpertCompletesARecordedAppMatch() async throws {
        let (model, fixture, started) = try withFixture { fixture in
            let model = makeModel(fixture)
            // Completion bookkeeping is the seam here, not Ghost fitting.
            // Keep extraction bounded and await its queue before teardown.
            model.makeGhostTrainer = { store in
                var trainer = GhostTrainer(store: store)
                trainer.extract = { _, _ in [] }
                return trainer
            }
            model.startNewGame(setup: expertSetup())
            let started = try requireMatch(model, revision: .cityProductionV1)
            model.qaPlayToEnd()
            return (model, fixture, started)
        }
        // Await before any throwing post-game assertion: failed validation
        // must not tear down files while completion work still uses them.
        await model.lastFinishedMatchWork?.value
        guard case .gameOver(let winner) = model.state.phase else {
            Issue.record("Promoted Expert did not finish the app match")
            return
        }
        #expect(model.state.victoryPoints(for: winner) >= model.state.victoryPointTarget)
        #expect(model.persistenceErrorMessage == nil)
        let match = try #require(model.checkpointDocument?.activeMatch)
        #expect(match.id == started.id)
        #expect(match.setup.expertRevision == .cityProductionV1)
        try match.validateHistory()
        let url = try model.gameLogStore.export(checkpoint: match)
        let detail = try model.gameLogStore.detail(for: url)
        #expect(detail.isComplete)
        #expect(detail.roster.expertRevision == .cityProductionV1)
        #expect(detail.summary.winner == winner)
        #expect(!detail.events.isEmpty)
        #expect(try fixture.logStore.summaries().count == 1)
    }

    private func expertSetup(humanChair: Int = 0) -> MatchSetup {
        MatchSetup(seats: (0..<4).map { index in
            MatchSetup.Seat(index: index, isHuman: index == humanChair,
                name: index == humanChair ? "Alex" : "", civilization: Civilization.allCases[index])
        }, victoryPointTarget: 10, randomizedBoard: false, randomizeSeatOrder: false, difficulty: .expert)
    }

    /// Reuse checkpoint isolation while also injecting the newer stores that
    /// the shared fixture leaves at their application defaults.
    private func makeModel(_ fixture: CheckpointModelFixture) -> GameViewModel {
        GameViewModel(
            checkpointStore: MatchCheckpointStore(fileURL: fixture.root.appendingPathComponent("match_checkpoint.json")),
            gameStore: fixture.gameStore, civilizationStore: fixture.civilizationStore,
            matchSetupStore: fixture.setupStore, gameLogStore: fixture.logStore, gameStatsStore: fixture.statsStore,
            ghostStore: GhostStore(localDirectory: fixture.root.appendingPathComponent("ghosts"), bundledGhosts: []),
            ratingStore: RatingStore(directory: fixture.root.appendingPathComponent("ratings")),
            seatStatsStore: SeatStatsStore(directory: fixture.root.appendingPathComponent("seat-stats")),
            playerDirectory: PlayerDirectory(directory: fixture.root.appendingPathComponent("players"))
        )
    }

    private func withFixture<Result>(_ body: (CheckpointModelFixture) throws -> Result) throws -> Result {
        let civilizations = CivilizationAssignment.current
        let humanSeat = CivilizationAssignment.humanSeat
        let humanNames = CivilizationAssignment.humanNames
        defer {
            CivilizationAssignment.current = civilizations
            CivilizationAssignment.humanSeat = humanSeat
            CivilizationAssignment.humanNames = humanNames
        }
        return try body(CheckpointModelFixture())
    }

    /// Assert actual seated policies and a fresh read of checkpoint authority,
    /// so a correct revision tag alone cannot make a broken transaction pass.
    private func requireMatch(_ model: GameViewModel, revision: ExpertRevision) throws -> MatchCheckpoint {
        try #require(model.persistenceErrorMessage == nil, "\(model.persistenceErrorMessage ?? "")")
        try #require(model.savedGameAvailability.canResume)
        let match = try #require(model.checkpointDocument?.activeMatch)
        let stored = try #require(try MatchCheckpointStore(fileURL: model.checkpointStore.fileURL).load()?.activeMatch)
        #expect(stored == match)
        #expect(match.setup.expertRevision == revision)
        #expect(match.sessionCheckpoint == model.session.checkpoint)
        #expect(Set(model.session.policies.keys) == Set(match.setup.aiSeats.map { PlayerID(index: $0.index) }))
        for seat in match.setup.aiSeats {
            let policy = try #require(model.session.policies[PlayerID(index: seat.index)])
            let profile = try #require(seat.opponentProfile)
            if let ghost = seat.ghostID {
                #expect(policy is GhostPolicy)
                #expect(policy.id == "ghost-\(ghost)")
            } else if match.setup.difficulty == .classic {
                #expect(policy.id == "heuristic-\(profile.strategy.rawValue)")
            } else {
                #expect(policy.id == (revision == .legacy ? "evaluation-v1" : "evaluation-city-production-v1"))
            }
        }
        return match
    }

    /// Change only the on-disk setup field to model older or future producers.
    private func rewriteRevision(at url: URL, as revision: String?) throws -> Data {
        var wire = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var match = try #require(wire["activeMatch"] as? [String: Any])
        var setup = try #require(match["setup"] as? [String: Any])
        if let revision { setup["expertRevision"] = revision } else { setup.removeValue(forKey: "expertRevision") }
        match["setup"] = setup
        wire["activeMatch"] = match
        let bytes = try JSONSerialization.data(withJSONObject: wire, options: .sortedKeys)
        try bytes.write(to: url, options: .atomic)
        return bytes
    }
}
