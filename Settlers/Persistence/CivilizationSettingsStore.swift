import Foundation
import CatanEngine

/// Durable defaults for the next New Game screen.
///
/// Neither value is a running-game assignment. Starting a match copies the
/// chosen civilizations into `CivilizationAssignmentStore`; later preference
/// edits therefore cannot rewrite a game already in progress.
public struct CivilizationSettings: Codable, Equatable, Sendable {
    public var yourCivilization: Civilization
    /// Which civilizations a seat left on Random may be dealt. Still read on
    /// every new game (`GameViewModel`), but no longer editable: the screen
    /// that edited it was deleted on 2026-09-08 and the pool now stays at its
    /// default of every civilization. The field remains because the assignment
    /// code is written against a pool, and because narrowing it is a plausible
    /// New Game Setup control later - not because anything writes it today.
    public var eligibleRandomCivilizations: Set<Civilization>

    /// Four seats may all be left on Random, including human seats.
    public static let minimumEligibleCivilizations = GameSetup.supportedPlayerCounts.upperBound
    public static let `default` = CivilizationSettings(
        yourCivilization: .medieval,
        eligibleRandomCivilizations: Set(Civilization.allCases)
    )

    public init(yourCivilization: Civilization,
                eligibleRandomCivilizations: Set<Civilization>) {
        self.yourCivilization = yourCivilization
        self.eligibleRandomCivilizations = eligibleRandomCivilizations
    }

    /// Expands an old three-entry pool deterministically while retaining every
    /// civilization the player selected under the previous format.
    public func normalized() -> CivilizationSettings {
        guard eligibleRandomCivilizations.count < Self.minimumEligibleCivilizations else { return self }
        var result = self
        for civilization in Civilization.allCases where
            result.eligibleRandomCivilizations.count < Self.minimumEligibleCivilizations {
            result.eligibleRandomCivilizations.insert(civilization)
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case yourCivilization
        case eligibleRandomCivilizations
        case includedBotCivilizations
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        yourCivilization = try values.decode(Civilization.self, forKey: .yourCivilization)
        eligibleRandomCivilizations = try values.decodeIfPresent(
            Set<Civilization>.self, forKey: .eligibleRandomCivilizations)
            ?? values.decode(Set<Civilization>.self, forKey: .includedBotCivilizations)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(yourCivilization, forKey: .yourCivilization)
        try values.encode(eligibleRandomCivilizations, forKey: .eligibleRandomCivilizations)
    }
}

/// Persists next-match civilization defaults in an injectable defaults domain.
public final class CivilizationSettingsStore: @unchecked Sendable {
    public static let shared = CivilizationSettingsStore()

    private let defaults: UserDefaults
    private let key = "civilizationSettings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> CivilizationSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(CivilizationSettings.self, from: data)
        else { return .default }
        return settings.normalized()
    }

    public func save(_ settings: CivilizationSettings) {
        let normalized = settings.normalized()
        precondition(normalized == settings,
                     "refusing to save a Random pool smaller than "
                     + "\(CivilizationSettings.minimumEligibleCivilizations) civilizations")
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: key)
        } catch {
            preconditionFailure("Could not encode civilization settings: \(error)")
        }
    }
}
