import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@Suite(.serialized) struct CompleteMatchTests {
    // Complete games retain large trajectories; serialize parameter cases as
    // well as the suite, and avoid racing the app's shared civilization labels.
    @MainActor
    @Test(.serialized, arguments: AppMatchCase.supportedMatrix)
    func sampledAutomatedMatchesCompletePersistAndReplay(match: AppMatchCase) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompleteMatchTests.\(UUID().uuidString)")
        // Cleanup failure must not replace a gameplay assertion's diagnosis.
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "CompleteMatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let setupStore = MatchSetupStore()
        setupStore.defaults = defaults
        let gameStore = GameStore(fileURL: root.appendingPathComponent("save.json"))
        let logStore = GameLogStore(directoryURL: root.appendingPathComponent("logs"), maxKeptLogs: 2)
        let statsStore = GameStatsStore(fileURL: root.appendingPathComponent("stats.json"))
        let model = GameViewModel(
            gameStore: gameStore,
            civilizationStore: CivilizationAssignmentStore(fileURL: root.appendingPathComponent("civs.json")),
            matchSetupStore: setupStore,
            gameLogStore: logStore,
            gameStatsStore: statsStore
        )
        model.startNewGame(setup: match.setup)
        let initialState = model.state

        #expect(initialState.players.count == match.playerCount)
        #expect(initialState.victoryPointTarget == match.victoryPointTarget)
        #expect(initialState.mode == match.mode)
        #expect((initialState.board == BoardGenerator.standard(Ruleset.forMode(match.mode).board)) == !match.randomizedBoard)
        let activeSetup = try #require(model.checkpointDocument?.activeMatch?.setup)
        #expect(activeSetup.seats.count == match.playerCount)
        #expect(activeSetup.humanSeats.count == match.humanCount)
        #expect(activeSetup.victoryPointTarget == match.victoryPointTarget)
        #expect(Set(activeSetup.humanSeats.map(\.name)) == Set(match.setup.humanSeats.map(\.name)))
        #expect(Set(activeSetup.seats.compactMap(\.civilization)).count == match.playerCount)
        #expect(activeSetup.humanSeats.allSatisfy { $0.opponentProfile == nil })
        #expect(activeSetup.aiSeats.allSatisfy { $0.opponentProfile != nil })
        #expect(model.opponentProfiles.count == match.playerCount - match.humanCount)
        if !match.randomizeSeatOrder {
            #expect(model.humanSeats == Set(match.humanSeatIndices.map { PlayerID(index: $0) }))
            #expect(activeSetup.seats.map(\.civilization) == match.setup.seats.map(\.civilization))
            #expect(activeSetup.humanSeats.map(\.name) == match.setup.humanSeats.map(\.name))
        }
        let realisedHumanSeats = model.humanSeats
        let realisedNames = CivilizationAssignment.humanNames
        let realisedProfiles = model.opponentProfiles

        // Policies drive every chair here, including human-labelled chairs.
        // This covers app bookkeeping, not human taps, handoffs or discards.
        model.qaPlayToEnd()

        guard case .gameOver(let winner) = model.state.phase else {
            Issue.record("complete-match path stopped before game over")
            return
        }
        let summaries = try logStore.summaries()
        #expect(summaries.count == 1)
        let summary = try #require(summaries.first)
        let detail = try logStore.detail(for: summary)
        #expect(summary.isComplete)
        #expect(summary.winner == winner)
        #expect(summary.moveCount > 100)
        #expect(try logStore.activeGameID() == nil)
        let stats = model.statistics
        if match.humanCount == 1 {
            #expect(stats.gamesPlayed == 1)
            #expect(stats.gamesWon == (winner == model.humanPlayer ? 1 : 0))
            #expect(stats.totalFinalVP == min(
                model.state.victoryPoints(for: model.humanPlayer), model.state.victoryPointTarget))
            #expect(stats.totalDurationSeconds.isFinite)
            #expect(stats.totalDurationSeconds > 0)
        } else {
            #expect(stats == GameStats(), "hot-seat games must not pollute one person's lifetime stats")
        }

        var replay = initialState
        for event in detail.events {
            try RulesEngine.apply(event.move, by: event.player, to: &replay)
        }
        #expect(replay == model.state)

        let restored = GameViewModel(
            gameStore: gameStore,
            civilizationStore: CivilizationAssignmentStore(fileURL: root.appendingPathComponent("civs.json")),
            matchSetupStore: setupStore,
            gameLogStore: logStore,
            gameStatsStore: statsStore
        )
        #expect(restored.state == model.state)
        #expect(restored.humanSeats == realisedHumanSeats)
        #expect(CivilizationAssignment.humanNames == realisedNames)
        #expect(restored.opponentProfiles == realisedProfiles)
        #expect(restored.checkpointDocument?.activeMatch?.setup == activeSetup)
    }
}

struct AppMatchCase: Sendable, CustomTestStringConvertible {
    // Sampled coverage, not every combination: both table sizes and every
    // target offered at that size meet both board/order modes, including
    // noncontiguous human seats. Existing four-player 12-point checkpoints
    // remain valid, but the New Game screen does not create another one.

    static let supportedMatrix: [AppMatchCase] = {
        let classic = (0...1).flatMap { variant in
            GameSetup.supportedPlayerCounts.flatMap { playerCount in
                MatchSetup.newGameVictoryPointTargets(for: playerCount, mode: .classic).enumerated().map { targetIndex, target in
                    AppMatchCase(
                        playerCount: playerCount,
                        humanSeatIndices: humanSeats(
                            playerCount: playerCount, targetIndex: targetIndex, variant: variant),
                        victoryPointTarget: target,
                        randomizedBoard: (targetIndex + variant).isMultiple(of: 2),
                        randomizeSeatOrder: variant == 1
                    )
                }
            }
        }
        // One Expanded case, not a second full matrix. A 25-point game is the
        // longest thing the app can be asked to play - several hundred more
        // moves than any Classic case - and the length is the point: it is the
        // only case here that reaches the sizes where committing a move used
        // to cost O(history) (see
        // `docs/plans/2026-09-11-expanded-bots-and-speed.md`). One case covers
        // the whole session/persistence/statistics/log/resume path at that
        // length; a matrix of them would only buy runtime.
        return classic + [AppMatchCase(
            playerCount: 4, humanSeatIndices: [0], victoryPointTarget: 25,
            randomizedBoard: false, randomizeSeatOrder: false, mode: .expanded
        )]
    }()

    let playerCount: Int
    let humanSeatIndices: [Int]
    let victoryPointTarget: Int
    let randomizedBoard: Bool
    let randomizeSeatOrder: Bool
    var mode: GameMode = .classic

    var humanCount: Int { humanSeatIndices.count }

    var testDescription: String {
        "\(mode)/\(playerCount)p/humans\(humanSeatIndices)/\(victoryPointTarget)vp/"
            + "\(randomizedBoard ? "random" : "standard")Board/"
            + "\(randomizeSeatOrder ? "random" : "fixed")Seats"
    }

    var setup: MatchSetup {
        MatchSetup(
            seats: (0..<playerCount).map { index in
                MatchSetup.Seat(
                    index: index,
                    isHuman: humanSeatIndices.contains(index),
                    name: humanSeatIndices.contains(index) ? "Player \(index + 1)" : "",
                    civilization: Civilization.allCases[index]
                )
            },
            mode: mode,
            victoryPointTarget: victoryPointTarget,
            randomizedBoard: randomizedBoard,
            randomizeSeatOrder: randomizeSeatOrder
        )
    }

    private static func humanSeats(playerCount: Int, targetIndex: Int, variant: Int) -> [Int] {
        let masks = playerCount == 3
            ? [[[0], [0, 2], [0, 1, 2]], [[2], [0, 1, 2], [1]]]
            : [[[0], [0, 2], [0, 2, 3]], [[3], [0, 1, 2, 3], [1, 3]]]
        return masks[variant][targetIndex]
    }
}
