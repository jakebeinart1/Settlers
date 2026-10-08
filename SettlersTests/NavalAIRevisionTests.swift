import CatanAI
import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

/// Match-start provenance must identify the actual seated policy. Testing the
/// tags alone would miss a restore that silently seats today's replacement.
@MainActor @Suite(.serialized)
struct NavalAIRevisionTests {
    @Test(arguments: BotDifficulty.allCases)
    func missingSetupFieldRetainsBothOriginalNavalTiers(difficulty: BotDifficulty) throws {
        let setup = navalSetup(difficulty: difficulty)
        #expect(setup.navalAIRevision == .legacyV1)
        var wire = try object(JSONEncoder().encode(setup))
        wire.removeValue(forKey: "navalAIRevision")
        let restored = try JSONDecoder().decode(MatchSetup.self, from: JSONSerialization.data(withJSONObject: wire))
        #expect(restored.navalAIRevision == .legacyV1)
        #expect(restored.difficulty == difficulty)
        #expect(restored.isValidMatch)
    }

    @Test(arguments: ["implicitLegacy", "explicitOn", "explicitOff"])
    func publicNewGameNormalizesOnlyImplicitLegacyShipStealing(choice: String) throws {
        try withFixture { fixture in
            let model = fixture.makeModel()
            var setup = navalSetup(difficulty: .classic)
            setup.navalOptions = choice == "implicitLegacy"
                ? .legacyDefaults : NavalOptions(shipStealingEnabled: choice == "explicitOn")
            model.startNewGame(setup: setup)
            let match = try requireMatch(model, revision: .scoutingV2)
            #expect(match.setup.navalOptions.shipStealingEnabled == (choice == "explicitOn"))
            #expect(model.state.naval?.options == match.setup.navalOptions)
            #expect(try requireMatch(fixture.makeModel(), revision: .scoutingV2) == match)
        }
    }

    @Test func restartPreservesImplicitLegacyShipStealingAndOriginalBrain() throws {
        try withFixture { fixture in
            let model = fixture.makeModel()
            var setup = navalSetup(difficulty: .expert)
            setup.expertRevision = .navalV1
            setup.navalOptions = .legacyDefaults
            model.startNewGame(setup: setup, configuredAs: setup)
            try commitOpeningAction(in: model)
            let match = try requireMatch(model, revision: .legacyV1)
            #expect(match.setup.navalOptions.shipStealingEnabled)
            try requireRestoreAndRestart(match, model: model, fixture: fixture)
        }
    }

    @Test(arguments: BotDifficulty.allCases, [0, 2])
    func freshMatchSeatsV2AndRetainsItThroughColdRestoreAndRestart(difficulty: BotDifficulty, humanChair: Int) throws {
        try withFixture { fixture in
            let model = fixture.makeModel()
            model.startNewGame(setup: navalSetup(difficulty: difficulty, humanChair: humanChair))
            try commitOpeningAction(in: model)
            let match = try requireMatch(model, revision: .scoutingV2)
            #expect(match.setup.expertRevision == (difficulty == .expert ? .navalV2 : .legacy))
            #expect(model.humanPlayer == PlayerID(index: humanChair))
            try requireRestoreAndRestart(match, model: model, fixture: fixture)
        }
    }

    @Test(arguments: BotDifficulty.allCases, [false, true])
    func preUpdateCheckpointWithoutBrainTagRetainsV1AndExactSession(difficulty: BotDifficulty, removeExpertTag: Bool) throws {
        try withFixture { fixture in
            let model = fixture.makeModel()
            var setup = navalSetup(difficulty: difficulty, humanChair: 2)
            setup.expertRevision = difficulty == .expert && !removeExpertTag ? .navalV1 : .legacy
            model.startNewGame(setup: setup, configuredAs: setup)
            try commitOpeningAction(in: model)
            let match = try requireMatch(model, revision: .legacyV1)
            let bytes = try rewriteSetup(at: model.checkpointStore.fileURL) {
                $0.removeValue(forKey: "navalAIRevision")
                if removeExpertTag { $0.removeValue(forKey: "expertRevision") }
            }
            let restored = fixture.makeModel()
            #expect(try requireMatch(restored, revision: .legacyV1) == match)
            #expect(restored.session.checkpoint == model.session.checkpoint)
            #expect(try Data(contentsOf: model.checkpointStore.fileURL) == bytes)
            try requireRestoreAndRestart(match, model: restored, fixture: fixture)
        }
    }

    @Test(arguments: BotDifficulty.allCases, [NavalPolicy.Revision.legacyV1, .scoutingV2])
    func legacySidecarMigrationPreservesRecordedTierAndBrain(difficulty: BotDifficulty, revision: NavalPolicy.Revision) throws {
        try withFixture { fixture in
            let state = Naval.newGame(seed: 9291)
            var setup = navalSetup(difficulty: difficulty, humanChair: 2)
            setup.navalAIRevision = revision
            setup.expertRevision = difficulty == .expert ? (revision == .scoutingV2 ? .navalV2 : .navalV1) : .legacy
            for index in setup.seats.indices where !setup.seats[index].isHuman {
                let civilization = try #require(setup.seats[index].civilization)
                setup.seats[index].opponentProfile = .forCivilization(civilization)
            }
            try fixture.gameStore.save(state)
            try fixture.setupStore.saveActiveMatch(setup)
            let bytes = try Data(contentsOf: fixture.gameStore.fileURL)
            let model = fixture.makeModel()
            let migrated = try requireMatch(model, revision: revision)
            #expect(migrated.setup.difficulty == difficulty)
            #expect(migrated.setup.expertRevision == setup.expertRevision)
            #expect(migrated.state == state)
            #expect(model.humanPlayer == PlayerID(index: 2))
            #expect(try Data(contentsOf: fixture.gameStore.fileURL) == bytes)
            #expect(try requireMatch(fixture.makeModel(), revision: revision) == migrated)
        }
    }

    @Test func unknownFutureBrainBlocksRestoreWithoutChangingCheckpointBytes() throws {
        try withFixture { fixture in
            let model = fixture.makeModel()
            model.startNewGame(setup: navalSetup(difficulty: .classic))
            try commitOpeningAction(in: model)
            let url = model.checkpointStore.fileURL
            let bytes = try rewriteSetup(at: url) { $0["navalAIRevision"] = "future-naval-brain" }
            #expect(throws: DecodingError.self) { try MatchCheckpointStore(fileURL: url).load() }
            let restored = fixture.makeModel()
            #expect(restored.persistenceBlocked)
            #expect(!restored.savedGameAvailability.canResume)
            #expect(restored.savedGameAvailability.recoveryMessage != nil)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test(arguments: ["expertBrainMismatch", "expertTagMismatch", "landMode"])
    func contradictorySavedBrainTagsAreRejected(configuration: String) throws {
        try withFixture { fixture in
            let model = fixture.makeModel()
            var setup = navalSetup(difficulty: .expert)
            if configuration == "landMode" {
                setup.mode = .classic
                setup.victoryPointTarget = 10
            }
            model.startNewGame(setup: setup)
            let url = model.checkpointStore.fileURL
            let bytes = try rewriteSetup(at: url) { saved in
                switch configuration {
                case "expertBrainMismatch": saved["navalAIRevision"] = "legacyV1"
                case "expertTagMismatch": saved["expertRevision"] = "navalV1"
                case "landMode": saved["navalAIRevision"] = "scoutingV2"
                default: preconditionFailure("Unknown saved-brain test")
                }
            }
            #expect(throws: MatchCheckpointStore.StoreError.invalidSetup) { try MatchCheckpointStore(fileURL: url).load() }
            let restored = fixture.makeModel()
            #expect(restored.persistenceBlocked)
            #expect(!restored.savedGameAvailability.canResume)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test(arguments: BotDifficulty.allCases, [NavalPolicy.Revision.legacyV1, .scoutingV2])
    func exportedArchiveKeepsBothTiersBrainAndReplaysRecordedMoves(difficulty: BotDifficulty, revision: NavalPolicy.Revision) throws {
        try withFixture { fixture in
            let model = fixture.makeModel()
            var setup = navalSetup(difficulty: difficulty)
            setup.navalAIRevision = revision
            setup.expertRevision = difficulty == .expert ? (revision == .scoutingV2 ? .navalV2 : .navalV1) : .legacy
            model.startNewGame(setup: setup, configuredAs: setup)
            try commitOpeningAction(in: model)
            let match = try requireMatch(model, revision: revision)
            let url = try fixture.logStore.export(checkpoint: match)
            let detail = try fixture.logStore.detail(for: url)
            #expect(detail.roster.navalAIRevision == revision)
            #expect(detail.roster.expertRevision == (difficulty == .expert ? setup.expertRevision : nil))
            var replay = detail.initialState
            for entry in detail.events {
                try RulesEngine.replay(entry.move, by: entry.player,
                    rulesVersion: try #require(entry.rulesVersion), to: &replay)
            }
            #expect(replay == match.state)
        }
    }

    @Test func oldArchivesDoNotInventNavalProvenanceAndLandArchivesOmitIt() throws {
        let roster = GameLogStore.SeatRoster.legacy(humanSeat: PlayerID(index: 0))
        let data = try JSONEncoder().encode(roster)
        #expect(try object(data)["navalAIRevision"] == nil)
        #expect(try JSONDecoder().decode(GameLogStore.SeatRoster.self, from: data).navalAIRevision == nil)
        try withFixture { fixture in
            let model = fixture.makeModel()
            model.startNewGame(setup: fixture.setup)
            try commitOpeningAction(in: model)
            let match = try #require(model.checkpointDocument?.activeMatch)
            let url = try fixture.logStore.export(checkpoint: match)
            #expect(try fixture.logStore.detail(for: url).roster.navalAIRevision == nil)
        }
    }

    @Test(arguments: BotDifficulty.allCases)
    func editablePrefillCanSwitchModesWithoutChangingActiveBrain(difficulty: BotDifficulty) throws {
        try withFixture { fixture in
            let model = fixture.makeModel()
            model.startNewGame(setup: navalSetup(difficulty: difficulty))
            let before = model.session.checkpoint
            let active = try requireMatch(model, revision: .scoutingV2)
            var draft = active.setup.normalizedForNewGame()
            #expect(draft.navalAIRevision == .legacyV1 && draft.expertRevision == .legacy)
            draft.mode = .classic
            draft.normalizeNewGameOptions()
            #expect(draft.isStartable)
            draft.difficulty = difficulty == .expert ? .classic : .expert
            #expect(draft.isStartable)
            draft.mode = .naval
            draft.normalizeNewGameOptions()
            #expect(draft.isStartable)
            #expect(draft.newMatchNavalAIRevision == .scoutingV2)
            #expect(model.session.checkpoint == before)
            #expect(try requireMatch(model, revision: .scoutingV2) == active)
        }
    }

    @Test(arguments: BotDifficulty.allCases, [4, 5])
    func replacedDebugBaselinesPersistTheFixtureBrain(difficulty: BotDifficulty, rulesVersion: Int) throws {
        try withFixture { fixture in
            let model = fixture.makeModel()
            var state = try NavalQAFixture.make(.voyage)
            state.naval?.rulesVersion = rulesVersion
            model.replaceStateForTesting(state, humanSeat: PlayerID(index: 2), difficulty: difficulty)
            let revision: NavalPolicy.Revision = rulesVersion == 5 ? .scoutingV2 : .legacyV1
            let match = try requireMatch(model, revision: revision)
            let restored = fixture.makeModel()
            #expect(try requireMatch(restored, revision: revision) == match)
            #expect(restored.session.checkpoint == model.session.checkpoint)
        }
    }

    private func navalSetup(difficulty: BotDifficulty, humanChair: Int = 0) -> MatchSetup {
        MatchSetup(seats: (0..<4).map { index in
            MatchSetup.Seat(index: index, isHuman: index == humanChair,
                name: index == humanChair ? "Alex" : "", civilization: Civilization.allCases[index])
        }, mode: .naval, victoryPointTarget: 14, randomizedBoard: true,
            randomizeSeatOrder: false, difficulty: difficulty)
    }

    /// Commit an actual opening action through the production checkpoint path.
    /// The nonzero human fixture also exercises a persisted policy decision.
    private func commitOpeningAction(in model: GameViewModel) throws {
        var candidate = model.session
        let step: GameSession.Step
        if case .awaitingExternalSeat(let seat) = candidate.nextActor() {
            let move = try #require(RulesEngine.legalMoves(for: candidate.state, seat: seat).first)
            step = try candidate.applyExternal(move, by: seat)
        } else {
            let decision = candidate.decideNext()
            let (seat, move) = try #require(decision)
            step = try candidate.commit(seat: seat, move: move)
        }
        try model.qaCommitStep(step, candidate: candidate)
    }

    private func requireRestoreAndRestart(_ match: MatchCheckpoint, model: GameViewModel, fixture: CheckpointModelFixture) throws {
        let revision = match.setup.navalAIRevision
        let bytes = try Data(contentsOf: model.checkpointStore.fileURL)
        let restored = fixture.makeModel()
        #expect(try requireMatch(restored, revision: revision) == match)
        #expect(restored.session.checkpoint == model.session.checkpoint)
        #expect(try Data(contentsOf: model.checkpointStore.fileURL) == bytes)
        var first = model.session
        var second = restored.session
        let originalNext = first.decideNext()
        let restoredNext = second.decideNext()
        #expect(originalNext?.0 == restoredNext?.0 && originalNext?.1 == restoredNext?.1)
        #expect(first.checkpoint == second.checkpoint)
        restored.restartCurrentMatch(fallbackRandomizedBoard: false, fallbackRandomizeSeat: true)
        let restarted = try requireMatch(restored, revision: revision)
        #expect(restarted.id != match.id)
        #expect(restarted.setup.seats == match.setup.seats)
        #expect(restarted.setup.expertRevision == match.setup.expertRevision)
        #expect(restarted.setup.navalOptions == match.setup.navalOptions)
        #expect(try requireMatch(fixture.makeModel(), revision: revision) == restarted)
    }

    private func requireMatch(_ model: GameViewModel, revision: NavalPolicy.Revision) throws -> MatchCheckpoint {
        try #require(model.persistenceErrorMessage == nil, "\(model.persistenceErrorMessage ?? "")")
        try #require(model.savedGameAvailability.canResume)
        let match = try #require(model.checkpointDocument?.activeMatch)
        #expect(match.setup.navalAIRevision == revision)
        #expect(match.sessionCheckpoint == model.session.checkpoint)
        #expect(try MatchCheckpointStore(fileURL: model.checkpointStore.fileURL).load()?.activeMatch == match)
        #expect(Set(model.session.policies.keys) == Set(match.setup.aiSeats.map { PlayerID(index: $0.index) }))
        let version = revision == .scoutingV2 ? "v2" : "v1"
        let tier = match.setup.difficulty == .expert ? "expert" : "traditional"
        for policy in model.session.policies.values {
            let naval = try #require(policy as? NavalPolicy)
            #expect(naval.revision == revision)
            #expect(naval.id == "naval-\(tier)-\(version)")
        }
        return match
    }

    private func rewriteSetup(at url: URL, change: (inout [String: Any]) -> Void) throws -> Data {
        var wire = try object(Data(contentsOf: url))
        var match = try #require(wire["activeMatch"] as? [String: Any])
        var setup = try #require(match["setup"] as? [String: Any])
        change(&setup)
        match["setup"] = setup
        wire["activeMatch"] = match
        let bytes = try JSONSerialization.data(withJSONObject: wire, options: .sortedKeys)
        try bytes.write(to: url, options: .atomic)
        return bytes
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func withFixture(_ body: (CheckpointModelFixture) throws -> Void) throws {
        let civilizations = CivilizationAssignment.current
        let humanSeat = CivilizationAssignment.humanSeat
        let names = CivilizationAssignment.humanNames
        defer {
            CivilizationAssignment.current = civilizations
            CivilizationAssignment.humanSeat = humanSeat
            CivilizationAssignment.humanNames = names
        }
        try body(CheckpointModelFixture())
    }
}
