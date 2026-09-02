import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@Suite struct CivilizationPreferenceTests {
    @Test func legacyThreeCivilizationPoolIsExpandedForFourRandomSeats() throws {
        let suiteName = "CivilizationPreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = LegacyCivilizationSettings(
            yourCivilization: .medieval,
            includedBotCivilizations: [.greece, .rome, .japan]
        )
        defaults.set(try JSONEncoder().encode(legacy), forKey: "civilizationSettings")

        let loaded = CivilizationSettingsStore(defaults: defaults).load()

        #expect(loaded.eligibleRandomCivilizations.count >= 4)
        #expect(loaded.eligibleRandomCivilizations.isSuperset(of: legacy.includedBotCivilizations))
    }

    @Test func preferredCivilizationAndRandomPoolAreIndependent() {
        var settings = CivilizationSettings.default
        let pool = settings.eligibleRandomCivilizations

        settings.yourCivilization = .norse

        #expect(settings.eligibleRandomCivilizations == pool)
    }

    @Test func removingTheFourthEligibleCivilizationIsRefusedWithAReason() {
        var settings = CivilizationSettings(
            yourCivilization: .medieval,
            eligibleRandomCivilizations: [.greece, .rome, .japan, .norse, .aztec]
        )

        #expect(settings.setRandomEligibility(.greece, isEligible: false) == nil)
        #expect(settings.setRandomEligibility(.rome, isEligible: false)
                == "Keep at least 4 civilizations available for Random seats.")
        #expect(settings.eligibleRandomCivilizations == [.rome, .japan, .norse, .aztec])
    }

    @MainActor
    @Test func allRandomSeatsDrawOnlyFromTheSelectedPool() {
        let pool: Set<Civilization> = [.greece, .rome, .japan, .norse]
        let resolved = GameViewModel.resolveRandomCivilizations(
            configured: Array(repeating: nil, count: 4),
            eligiblePool: pool
        )

        #expect(Set(resolved) == pool)
        #expect(resolved.count == 4)
    }
}

private struct LegacyCivilizationSettings: Codable {
    let yourCivilization: Civilization
    let includedBotCivilizations: Set<Civilization>
}
