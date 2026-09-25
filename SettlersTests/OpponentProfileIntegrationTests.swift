import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@MainActor
@Suite(.serialized)
struct OpponentProfileIntegrationTests {
    @Test func newGameDraftRefreshesProfilesWithoutRewritingActiveMatch() throws {
        try withStores { stores in
            // Four seats deliberately: as of 2026-09-16 the New Game screen
            // offers only four, and `initialSetup` grows a smaller prefill to
            // fit rather than discarding it. A three-seat fixture here would be
            // resized on the way back in and this test would be measuring that
            // resize instead of the profile refresh it is about.
            var configured = setup(playerCount: 4, humans: [0],
                                   civilizations: [.norse, .rome, .japan, .greece])
            for index in [1, 2, 3] {
                let catalog = OpponentProfile.forCivilization(try #require(configured.seats[index].civilization))
                configured.seats[index].opponentProfile = OpponentProfile(id: catalog.id, name: catalog.name,
                    civilization: catalog.civilization, strategy: index == 1 ? .aggressive : .cautious)
            }
            let active = stores.makeModel()
            active.startNewGame(setup: configured)
            let checkpoint = stores.root.appendingPathComponent("match_checkpoint.json")
            let before = try Data(contentsOf: checkpoint)
            let draft = NewGameSetupView.initialSetup(from: stores.setupStore.load(),
                preferredName: "Human 1", preferredCivilization: .norse)
            #expect(!draft.wasUnreadable && draft.setup.seats.allSatisfy { $0.opponentProfile == nil })
            #expect(draft.setup.seats.map(\.civilization) == configured.seats.map(\.civilization))
            #expect(draft.setup.seats.map(\.name) == configured.seats.map(\.name))
            #expect(stores.setupStore.load().value == configured)
            #expect(try Data(contentsOf: checkpoint) == before, "Opening/cancelling New Game must not write")
            #expect(stores.makeModel().opponentProfiles == active.opponentProfiles)
            let fresh = stores.makeModel()
            fresh.startNewGame(setup: draft.setup)
            #expect(fresh.opponentProfiles.values.allSatisfy { $0.strategy == .balanced })
            #expect(fresh.opponentProfiles.mapValues(\.id) == active.opponentProfiles.mapValues(\.id))
            #expect(fresh.opponentProfiles.mapValues(\.name) == active.opponentProfiles.mapValues(\.name))
            #expect(GameViewModel.makePolicies(fresh.opponentProfiles, difficulty: .classic, ghosts: .shared).values.allSatisfy { $0.id == "heuristic-balanced" })
        }
    }

    @Test func everySupportedSeatCompositionGetsExactlyItsBotProfiles() throws {
        try withStores { stores in
            for playerCount in GameSetup.supportedPlayerCounts {
                let seatIndices = Array(0..<playerCount)
                for humanMask in 1..<(1 << playerCount) {
                    let humans = Set(seatIndices.filter { humanMask & (1 << $0) != 0 })
                    let model = stores.makeModel()
                    model.startNewGame(setup: setup(playerCount: playerCount, humans: humans))

                    #expect(model.opponentProfiles.count == playerCount - humans.count)
                    for index in seatIndices {
                        let seat = PlayerID(index: index)
                        let profile = model.opponentProfile(for: seat)
                        if humans.contains(index) {
                            #expect(profile == nil)
                        } else {
                            #expect(profile?.civilization == Civilization.forSeat(index))
                            #expect(profile?.strategy == .balanced)
                        }
                    }
                    #expect(GameViewModel.makePolicies(model.opponentProfiles, difficulty: .classic, ghosts: .shared).values.allSatisfy {
                        $0.id == "heuristic-balanced"
                    })
                }
            }
        }
    }

    @Test func strategyFollowsTheGeneralRatherThanBotSeatRank() throws {
        try withStores { stores in
            let first = stores.makeModel()
            first.startNewGame(setup: setup(
                playerCount: 4, humans: [0],
                civilizations: [.medieval, .rome, .egypt, .japan]
            ))
            let romeAtOne = try #require(first.opponentProfile(for: PlayerID(index: 1)))

            let second = stores.makeModel()
            second.startNewGame(setup: setup(
                playerCount: 4, humans: [1],
                civilizations: [.egypt, .medieval, .rome, .japan]
            ))
            let romeAtTwo = try #require(second.opponentProfile(for: PlayerID(index: 2)))

            #expect(romeAtOne == romeAtTwo)
            #expect(romeAtOne.strategy == .balanced)
        }
    }

    @Test func relaunchRecoversProfilesFromActiveMatchWhenSidecarIsMissing() throws {
        try withStores { stores in
            let original = stores.makeModel()
            original.startNewGame(setup: setup(
                playerCount: 3, humans: [0],
                civilizations: [.norse, .rome, .japan]
            ))
            let expected = original.opponentProfiles
            try stores.civilizationStore.clear()

            let relaunched = stores.makeModel()

            #expect(relaunched.opponentProfiles == expected)
            #expect((0..<3).map(Civilization.forSeat) == [.norse, .rome, .japan])
        }
    }

    @Test func activeMatchOutranksAStaleSameSizedCivilizationSidecar() throws {
        try withStores { stores in
            let original = stores.makeModel()
            original.startNewGame(setup: setup(
                playerCount: 3, humans: [0], civilizations: [.norse, .rome, .japan]
            ))
            try stores.civilizationStore.save([.greece, .egypt, .aztec])

            let relaunched = stores.makeModel()

            #expect((0..<3).map(Civilization.forSeat) == [.norse, .rome, .japan])
            #expect(relaunched.opponentProfile(for: PlayerID(index: 1))?.civilization == .rome)
        }
    }

    @Test func legacyActiveMatchKeepsItsOrdinalBotStrategies() throws {
        try withStores { stores in
            let legacy = setup(
                playerCount: 4, humans: [0],
                civilizations: [.norse, .rome, .japan, .egypt]
            )
            try stores.setupStore.save(legacy)
            try stores.setupStore.saveActiveMatch(legacy)
            try stores.civilizationStore.save([.norse, .rome, .japan, .egypt])
            try stores.gameStore.save(GameSetup.newGame(
                board: BoardGenerator.standard(), seed: 71, playerCount: 4
            ))

            let model = stores.makeModel()

            #expect(model.opponentProfile(for: PlayerID(index: 1))?.strategy == .balanced)
            #expect(model.opponentProfile(for: PlayerID(index: 2))?.strategy == .aggressive)
            #expect(model.opponentProfile(for: PlayerID(index: 3))?.strategy == .cautious)
        }
    }

    @Test func restartKeepsTheRealizedOpponentRosterAndTheNewGamePrefill() throws {
        try withStores { stores in
            let configured = setup(
                playerCount: 4, humans: [0],
                civilizations: [.norse, .rome, .japan, .egypt],
                randomizeSeatOrder: true
            )
            let model = stores.makeModel()
            model.startNewGame(setup: configured)
            let profiles = model.opponentProfiles
            let civilizations = (0..<4).map(Civilization.forSeat)

            model.restartCurrentMatch(fallbackRandomizedBoard: false, fallbackRandomizeSeat: false)

            #expect(model.opponentProfiles == profiles)
            #expect((0..<4).map(Civilization.forSeat) == civilizations)
            #expect(stores.setupStore.load().value == configured)
        }
    }

    @Test func activeMatchSnapshotsProfileAndLogIdentity() throws {
        try withStores { stores in
            let snapshot = OpponentProfile(
                id: "augustus-v1", name: "Augustus", civilization: .rome, strategy: .cautious
            )
            var configured = setup(
                playerCount: 3, humans: [0], civilizations: [.norse, .rome, .japan]
            )
            configured.seats[1].opponentProfile = snapshot
            let model = stores.makeModel()
            model.startNewGame(setup: configured)
            let move = try #require(
                RulesEngine.legalMoves(for: model.state, seat: model.humanPlayer).first
            )
            try model.apply(move)

            let relaunched = stores.makeModel()
            #expect(relaunched.opponentProfile(for: PlayerID(index: 1)) == snapshot)
            #expect(relaunched.playerLabel(for: PlayerID(index: 1)) == "Augustus")

            let detail = try #require(stores.logStore.summaries().first)
            let roster = try stores.logStore.detail(for: detail).roster
            #expect(roster.botProfiles[1] == "augustus-v1")
            #expect(roster.botProfileNames[1] == "Augustus")
            #expect(roster.botPersonalities[1] == "cautious")
            let savedSession = model.session.checkpoint
            #expect(relaunched.session.checkpoint == savedSession)
            relaunched.restartCurrentMatch(fallbackRandomizedBoard: false, fallbackRandomizeSeat: false)
            #expect(relaunched.opponentProfile(for: PlayerID(index: 1)) == snapshot)
            #expect(GameViewModel.makePolicies(relaunched.opponentProfiles, difficulty: .classic, ghosts: .shared)[PlayerID(index: 1)]?.id == "heuristic-cautious")
        }
    }

    @Test func unsupportedResearchSnapshotBlocksResumeAndPreservesBytes() throws {
        try withStores { stores in
            let model = stores.makeModel()
            model.startNewGame(setup: setup(playerCount: 3, humans: [0]))
            let path = stores.root.appendingPathComponent("match_checkpoint.json")
            var document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
            var match = try #require(document["activeMatch"] as? [String: Any])
            var savedSetup = try #require(match["setup"] as? [String: Any])
            var seats = try #require(savedSetup["seats"] as? [[String: Any]])
            var profile = try #require(seats[1]["opponentProfile"] as? [String: Any])
            profile["policy"] = "neuralR2"
            seats[1]["opponentProfile"] = profile
            savedSetup["seats"] = seats
            match["setup"] = savedSetup
            document["activeMatch"] = match
            let unsupported = try JSONSerialization.data(withJSONObject: document)
            try unsupported.write(to: path)
            let restored = stores.makeModel()
            #expect(!restored.savedGameAvailability.canResume)
            #expect(restored.persistenceBlocked)
            #expect(restored.savedGameAvailability.recoveryMessage != nil)
            #expect(try Data(contentsOf: path) == unsupported)
        }
    }

    @Test func profileSnapshotKeepsIdentityCoherentWhenLegacySeatFieldDisagrees() throws {
        try withStores { stores in
            let snapshot = OpponentProfile(
                id: "augustus-v1", name: "Augustus Prime", civilization: .rome, strategy: .cautious
            )
            var configured = setup(
                playerCount: 3, humans: [0], civilizations: [.norse, .egypt, .japan]
            )
            configured.seats[1].opponentProfile = snapshot
            try stores.setupStore.save(configured)
            try stores.setupStore.saveActiveMatch(configured)
            try stores.gameStore.save(GameSetup.newGame(
                board: BoardGenerator.standard(), seed: 72, playerCount: 3
            ))

            let model = stores.makeModel()

            #expect(Civilization.forSeat(1) == .rome)
            #expect(model.opponentProfile(for: PlayerID(index: 1)) == snapshot)
            #expect(model.playerLabel(for: PlayerID(index: 1)) == "Augustus Prime")
        }
    }

    @Test func oneIdentityValueBindsEveryVisibleSeatAttribute() throws {
        try withStores { stores in
            let model = stores.makeModel()
            model.startNewGame(setup: setup(
                playerCount: 4,
                humans: [0, 2],
                civilizations: [.medieval, .egypt, .japan, .norse]
            ))

            let identities = Dictionary(uniqueKeysWithValues: model.state.players.map {
                ($0.id, model.playerIdentity(for: $0.id))
            })
            let first = try #require(identities[PlayerID(index: 0)])
            let second = try #require(identities[PlayerID(index: 1)])
            let third = try #require(identities[PlayerID(index: 2)])
            let fourth = try #require(identities[PlayerID(index: 3)])

            #expect(first == PlayerIdentity(
                seat: PlayerID(index: 0), displayName: "Human 1",
                civilization: .medieval, controller: .human
            ))
            #expect(second == PlayerIdentity(
                seat: PlayerID(index: 1), displayName: "Ramesses",
                civilization: .egypt, controller: .computer
            ))
            #expect(third == PlayerIdentity(
                seat: PlayerID(index: 2), displayName: "Human 3",
                civilization: .japan, controller: .human
            ))
            #expect(fourth == PlayerIdentity(
                seat: PlayerID(index: 3), displayName: "Ragnar",
                civilization: .norse, controller: .computer
            ))
            #expect(identities.values.allSatisfy {
                model.playerLabel(for: $0.seat) == $0.displayName
                    && $0.civilization.paintedPieceImageName(isCity: false) != nil
            })
        }
    }

    private struct Stores {
        let root: URL
        let gameStore: GameStore
        let civilizationStore: CivilizationAssignmentStore
        let setupStore: MatchSetupStore
        let logStore: GameLogStore

        @MainActor func makeModel() -> GameViewModel {
            GameViewModel(
                gameStore: gameStore,
                civilizationStore: civilizationStore,
                matchSetupStore: setupStore,
                gameLogStore: logStore,
                gameStatsStore: GameStatsStore(fileURL: root.appendingPathComponent("stats.json"))
            )
        }
    }

    private func withStores(_ body: (Stores) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpponentProfiles.\(UUID().uuidString)")
        let suite = "OpponentProfiles.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let previousSeat = UserDefaults.standard.object(forKey: "humanSeat")
        let previousCivilizations = CivilizationAssignment.current
        let previousHumanNames = CivilizationAssignment.humanNames
        let previousHumanSeat = CivilizationAssignment.humanSeat
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
            if let previousSeat {
                UserDefaults.standard.set(previousSeat, forKey: "humanSeat")
            } else {
                UserDefaults.standard.removeObject(forKey: "humanSeat")
            }
            CivilizationAssignment.current = previousCivilizations
            CivilizationAssignment.humanNames = previousHumanNames
            CivilizationAssignment.humanSeat = previousHumanSeat
        }
        let setupStore = MatchSetupStore()
        setupStore.defaults = defaults
        try body(Stores(
            root: root,
            gameStore: GameStore(fileURL: root.appendingPathComponent("game.json")),
            civilizationStore: CivilizationAssignmentStore(
                fileURL: root.appendingPathComponent("civilizations.json")
            ),
            setupStore: setupStore,
            logStore: GameLogStore(directoryURL: root.appendingPathComponent("logs"), maxKeptLogs: 20)
        ))
    }

    private func setup(
        playerCount: Int,
        humans: Set<Int>,
        civilizations: [Civilization]? = nil,
        randomizeSeatOrder: Bool = false
    ) -> MatchSetup {
        let choices = civilizations ?? Array(Civilization.allCases.prefix(playerCount))
        return MatchSetup(
            seats: (0..<playerCount).map { index in
                MatchSetup.Seat(
                    index: index,
                    isHuman: humans.contains(index),
                    name: humans.contains(index) ? "Human \(index + 1)" : "",
                    civilization: choices[index]
                )
            },
            victoryPointTarget: 10,
            randomizedBoard: false,
            randomizeSeatOrder: randomizeSeatOrder
        )
    }
}
