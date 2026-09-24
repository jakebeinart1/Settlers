import Testing
import Foundation
import CatanEngine
@testable import Settlers

@MainActor @Suite struct ConquestSetupTests {
    @Test func aSetupSavedBeforeConquestResumesAsStandard() throws {
        let legacy = """
        {"seats":[{"index":0,"isHuman":true,"name":"Jake"},
                  {"index":1,"isHuman":false,"name":""},
                  {"index":2,"isHuman":false,"name":""},
                  {"index":3,"isHuman":false,"name":""}],
         "victoryPointTarget":10,"randomizedBoard":false,"randomizeSeatOrder":false}
        """
        let setup = try JSONDecoder().decode(MatchSetup.self, from: Data(legacy.utf8))
        #expect(setup.variant == .standard)
    }

    @Test func theChosenVariantSurvivesASaveAndReload() throws {
        var setup = MatchSetup.default(preferredName: "Jake", preferredCivilization: .medieval)
        setup.variant = .conquest
        let reloaded = try JSONDecoder().decode(MatchSetup.self, from: try JSONEncoder().encode(setup))
        #expect(reloaded.variant == .conquest)
    }

    @Test func startingAConquestSetupStartsAConquestGame() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConquestSetupTests.\(UUID().uuidString)")
        let defaults = UserDefaults(suiteName: "ConquestSetupTests.\(UUID().uuidString)")!
        let setupStore = MatchSetupStore()
        setupStore.defaults = defaults
        let model = GameViewModel(
            gameStore: GameStore(fileURL: root.appendingPathComponent("save.json")),
            civilizationStore: CivilizationAssignmentStore(fileURL: root.appendingPathComponent("civs.json")),
            matchSetupStore: setupStore,
            gameLogStore: GameLogStore(directoryURL: root.appendingPathComponent("logs"), maxKeptLogs: 2),
            gameStatsStore: GameStatsStore(fileURL: root.appendingPathComponent("stats.json"))
        )
        var setup = MatchSetup.default(preferredName: "Jake", preferredCivilization: .medieval)
        setup.variant = .conquest
        model.startNewGame(setup: setup)
        #expect(model.state.variant == .conquest)
        #expect(!model.state.garrisons.isEmpty, "tribes hold every producing hex")
        try? FileManager.default.removeItem(at: root)
    }
}
