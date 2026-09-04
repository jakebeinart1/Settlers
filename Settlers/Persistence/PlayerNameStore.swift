import Foundation

/// The name preference used to prefill the next New Game screen. A running
/// match snapshots each human's name in its realized `MatchSetup`, so changing
/// this preference never renames a game already in progress. A single
/// `UserDefaults` string rather than folding into
/// `CivilizationSettings`: it's an unrelated, independently-editable field,
/// and keeping it separate means no `Codable` migration story for the
/// existing `CivilizationSettings` blob.
public struct PlayerNameStore: Sendable {
    public static let shared = PlayerNameStore()

    private let key = "playerDisplayName"

    init() {}

    /// The saved name, or `""` if none has been set yet (or it was cleared)
    /// - callers fall back to "You" for an empty name, this store doesn't
    /// bake that fallback in itself.
    public func load() -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }

    /// Trims whitespace before saving - an all-whitespace "name" should read
    /// as "no custom name set" (falls back to "You"), not as a blank label.
    /// Longest name this stores.
    ///
    /// Matches the cap the New Game screen enforces at input. Without it here,
    /// an absurd name typed into App Settings prefilled a seat unchecked and,
    /// because the HUD panel uses `.fixedSize()`, pushed the whole game screen
    /// sideways - a preference reaching a layout that never agreed to it.
    public static let maximumLength = 12

    public func save(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(String(trimmed.prefix(Self.maximumLength)), forKey: key)
    }
}
