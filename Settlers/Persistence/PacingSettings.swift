import Foundation

/// How long the app waits between bot actions, and how long messages stay up.
///
/// ## Why this is configuration and not code
/// The bots decide instantly. Every pause the player sees is deliberate, and
/// the right length is a matter of taste that wants trying rather than
/// deriving - the reported symptom was "the computer's making turns so quickly
/// that I don't even see what they're doing". Numbers a person will want to
/// sweep belong in configuration; numbers that are part of Catan stay in code
/// (see the house rule on `BotWeights`).
///
/// ## This is presentation, and must stay in the app
/// `GameSession` has no notion of elapsed time at all - the whole game loop
/// runs as fast as the CPU allows, which is what lets a headless harness play
/// thousands of games. Pacing is wrapped *around* that loop by
/// `GameViewModel`. Putting these values in `CatanAI` would move a surface the
/// seeded fingerprint tests guard, and would break the rule that both packages
/// import only Foundation. Nothing here can affect determinism: no value below
/// reaches a decision, only the delay before one is shown.
struct PacingSettings: Equatable, Sendable {

    /// Minimum wall-clock time one bot action takes, in seconds.
    ///
    /// A floor, not a fixed cost - a bot's own thinking is far below it.
    /// Raising this makes a bot's turn readable and makes the whole game
    /// longer in direct proportion: a seat may take up to
    /// `GameSession.maxActionsPerTurn` (25) actions, so 1.0 here is a 25-second
    /// worst-case turn.
    var secondsPerBotAction: Double = 0.6

    /// How long the dice-roll highlight stays on the producing tiles.
    var rollHighlightSeconds: Double = 1.5

    /// How long an incoming trade offer stays on screen before it is
    /// auto-declined. **Zero means wait for the human indefinitely**, which is
    /// the default: an offer that answers itself is not a decision.
    var incomingOfferTimeoutSeconds: Double = 0

    /// The defaults reproduce the behaviour that was hardcoded before this
    /// type existed, apart from `incomingOfferTimeoutSeconds`, which was
    /// effectively 6 and is now 0 - that was the reported bug, not a setting
    /// anyone chose.
    static let `default` = PacingSettings()
}
