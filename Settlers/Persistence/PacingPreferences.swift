import Foundation
import Observation

/// How fast an AI turn plays out, as a **named** set rather than a number.
///
/// ## Why an enum and not a `Double`
/// This used to be a free value in a bundled `pacing.yml`, guarded by a strict
/// parser that range-checked every number because `secondsPerBotAction: 0`
/// makes the bot loop spin as fast as the CPU allows - the exact symptom the
/// file was created to cure. A named set removes the class of bug instead of
/// validating it: there is no way to spell an invalid speed, so there is
/// nothing to check and nothing to report. That is acceptance criterion B1.3
/// in `docs/superpowers/specs/2026-08-30-settings-surfaces-acceptance-criteria.md`.
public enum AITurnSpeed: String, CaseIterable, Sendable {
    case slow
    case standard
    case fast

    /// What the In-Game Settings screen calls each speed.
    public var displayName: String {
        switch self {
        case .slow: return "Slow"
        case .standard: return "Standard"
        case .fast: return "Fast"
        }
    }

    /// Minimum wall-clock time one bot action takes, in seconds.
    ///
    /// Carried over from `pacing.yml`, which is where this rationale lived:
    /// a floor, not a fixed cost - the bots decide far faster than this, and
    /// every pause the player sees is added deliberately on top of a game loop
    /// that has no notion of time at all. A seat can take up to
    /// `GameSession.maxActionsPerTurn` (25) actions, so a second here is a
    /// 25-second worst-case turn, which is why `slow` stops at 2.0 rather than
    /// going further.
    ///
    /// `standard` is 1.1 because that is what shipped in `pacing.yml`: default
    /// behaviour must be unchanged by this screen existing. `fast` is 0.6, the
    /// value hardcoded before the config file existed - deliberately **not**
    /// zero or near-zero, per B1.4: being able to see what the AI did is the
    /// entire reason the delay exists, so no selectable speed may make a turn
    /// effectively instant.
    public var secondsPerBotAction: Double {
        switch self {
        case .slow: return 2.0
        case .standard: return 1.1
        case .fast: return 0.6
        }
    }
}

/// How long the player has to answer an incoming trade offer.
///
/// Carried over from `pacing.yml`: the bots are held for the whole of it -
/// nobody moves while you are deciding (see `GameViewModel.openIncomingOffer`)
/// - so this is reading time, not a race. 15s is long enough to read who is
/// asking and what for; the hardcoded 6s that preceded it was not, and it
/// expired while the player was still reading, which is what got reported.
///
/// `noLimit` is a case rather than a magic zero *at this layer* - it still
/// resolves to zero seconds because that is what `IncomingTradeCardView`'s
/// countdown already means by "never", but the setting itself cannot be
/// confused with "answer instantly".
public enum IncomingOfferTimer: String, CaseIterable, Sendable {
    case fifteenSeconds
    case thirtySeconds
    case sixtySeconds
    case noLimit

    public var displayName: String {
        switch self {
        case .fifteenSeconds: return "15s"
        case .thirtySeconds: return "30s"
        case .sixtySeconds: return "60s"
        case .noLimit: return "No Limit"
        }
    }

    /// Seconds before the offer card answers for the player. **Zero means
    /// never** - the contract `IncomingTradeCardView` already reads.
    public var seconds: Double {
        switch self {
        case .fifteenSeconds: return 15
        case .thirtySeconds: return 30
        case .sixtySeconds: return 60
        case .noLimit: return 0
        }
    }
}

/// The player's pacing preferences, stored in `UserDefaults` and edited from
/// `InGameSettingsView`.
///
/// ## What this replaced, and why
/// Pacing used to be a bundled `pacing.yml` parsed by `PacingSettingsStore`.
/// A bundled file is read-only on iOS, so it was developer-configurable and
/// not player-configurable: editing it and rebuilding was the loop. Surface B
/// of the settings spec puts AI speed and the trade timer in front of the
/// player, which a bundled file cannot do. The strict parser, its five error
/// cases and the startup force-read all went with it - none of them have
/// anything to answer once the values are named cases with no text form to
/// get wrong.
///
/// ## Why these are presentation and stay in the app target
/// `GameSession` has no notion of elapsed time - the whole loop runs as fast
/// as the CPU allows, which is what lets the headless harness play thousands
/// of games. Pacing is wrapped *around* that loop by `GameViewModel`. Nothing
/// here can reach a decision, only the delay before one is shown, so no value
/// here can change who wins and none of it is saved with the game (spec §6).
/// Putting it in `CatanAI` would move a surface the seeded fingerprint tests
/// guard and would break the rule that both packages import only Foundation.
///
/// ## Read it fresh, every time
/// Call sites read `PacingPreferences.shared` at the moment they need a value
/// rather than capturing one - that is what makes a change take effect on the
/// turn in progress with no restart (B1.2). `GameViewModel.runBotTurnIfNeeded`
/// re-reads inside its loop for exactly this reason.
///
/// `nonisolated(unsafe)` rather than `@MainActor` follows the precedent set by
/// `CivilizationAssignment`: this whole app is single-threaded UI code, every
/// read and write already happens on the main thread, and actor-isolating the
/// singleton would force `@MainActor` down through every nonisolated view
/// property that reads it.
@Observable
public final class PacingPreferences {
    public nonisolated(unsafe) static let shared = PacingPreferences()

    /// `UserDefaults` keys. Namespaced, and pinned here rather than spelled at
    /// each call site, because a renamed case would otherwise silently read as
    /// "nothing stored" and reset the player's choice to the default.
    static let aiTurnSpeedKey = "pacing.aiTurnSpeed"
    static let incomingOfferTimerKey = "pacing.incomingOfferTimer"

    /// How long the dice-roll highlight stays on the tiles that produced.
    ///
    /// A constant, not a preference: it is not on Surface B, because it is a
    /// 1.5-second flash nobody has asked to tune and one more control on that
    /// screen costs more than it is worth. It keeps the value `pacing.yml`
    /// shipped so the highlight is unchanged.
    public static let rollHighlightSeconds: Double = 1.5

    public private(set) var aiTurnSpeed: AITurnSpeed
    public private(set) var incomingOfferTimer: IncomingOfferTimer

    private let defaults: UserDefaults

    /// `defaults` is injectable purely so tests can build a second instance
    /// over the *real* standard container and prove a written preference is
    /// read back by a fresh reader, which a singleton alone cannot show.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.aiTurnSpeed = Self.stored(forKey: Self.aiTurnSpeedKey, in: defaults) ?? .standard
        self.incomingOfferTimer = Self.stored(forKey: Self.incomingOfferTimerKey, in: defaults) ?? .fifteenSeconds
    }

    public func select(_ speed: AITurnSpeed) {
        aiTurnSpeed = speed
        defaults.set(speed.rawValue, forKey: Self.aiTurnSpeedKey)
    }

    public func select(_ timer: IncomingOfferTimer) {
        incomingOfferTimer = timer
        defaults.set(timer.rawValue, forKey: Self.incomingOfferTimerKey)
    }

    /// Reads a stored raw value, answering `nil` for both "never set" and "set
    /// to something this build no longer has a case for".
    ///
    /// Falling back to the default is right *here* and would have been wrong in
    /// the `pacing.yml` parser it replaces: that file was written by a
    /// developer who could be told their edit was rejected, so silence was the
    /// bug. This is a preference store whose only writer is `select` above, so
    /// an unrecognised value means a case was renamed between builds. There is
    /// nobody to report that to and no better answer than the default.
    private static func stored<T: RawRepresentable>(forKey key: String, in defaults: UserDefaults) -> T?
    where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:))
    }
}
