import Foundation

/// The player's durable civilization preferences - which civilization they
/// play as, and which others are eligible to be drawn for the 3 bot seats.
/// Edited from `SettingsView`; read by `GameViewModel.startNewGame` each
/// time a fresh game is set up (an in-progress game's actual seat
/// assignment is separate - see `CivilizationAssignmentStore`).
public struct CivilizationSettings: Codable, Equatable, Sendable {
    public var yourCivilization: Civilization
    public var includedBotCivilizations: Set<Civilization>

    /// Matches the app's original fixed lineup (Britannia as "you") plus
    /// every other civilization included by default, for maximum bot
    /// variety out of the box.
    public static let `default` = CivilizationSettings(
        yourCivilization: .medieval,
        includedBotCivilizations: Set(Civilization.allCases.filter { $0 != .medieval })
    )

    /// The minimum number of bot civilizations that must stay included -
    /// there are exactly 3 bot seats, so fewer than 3 candidates would
    /// leave a seat with nothing distinct to draw.
    public static let minimumIncludedBots = 3
}

/// Persists `CivilizationSettings` to `UserDefaults` - unlike `GameStore`
/// (a single in-progress game, replaced wholesale on every save), this is a
/// small standing preference the player edits occasionally from Settings,
/// so `UserDefaults` fits better than a JSON file on disk.
public struct CivilizationSettingsStore: Sendable {
    public static let shared = CivilizationSettingsStore()

    private let key = "civilizationSettings"

    init() {}

    /// Reads the saved settings, or `.default` if none are saved yet or the
    /// saved value fails to decode (e.g. an older format).
    public func load() -> CivilizationSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(CivilizationSettings.self, from: data)
        else { return .default }
        return settings
    }

    public func save(_ settings: CivilizationSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
