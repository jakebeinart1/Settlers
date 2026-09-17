import Testing
import Foundation
@testable import Settlers

/// Covers the pacing preferences that replaced the bundled `pacing.yml`.
///
/// The nine tests these replace were almost entirely about a strict YAML
/// parser refusing to guess - an unknown key, a non-numeric value, a value
/// outside its range. None of those failures can be spelled any more: both
/// settings are named enums, so an invalid setting is unrepresentable rather
/// than validated, and there is no text to parse. What is left worth testing
/// is different, and is what this file covers:
///
/// 1. The **defaults have not moved**. A settings screen must not change the
///    game for a player who never opens it, and `standard` = 1.1s / 15s are
///    exactly what `pacing.yml` shipped.
/// 2. The **range each enum spans is still sane** - specifically that no speed
///    is effectively instant (spec B1.4), which is the one property the
///    deleted range check was actually protecting.
/// 3. A stored preference **survives being read back by a fresh reader**,
///    through the real `UserDefaults` container the app runs on.
///
/// ## The same caveat as `PersistenceTests`
/// These read and write the *simulator's real* `UserDefaults.standard`, not an
/// injected suite, because a round-trip through a temporary container proves
/// nothing about the container the app uses - a mistyped key name would pass.
/// `gate.sh` runs this on every push, so without care a routine gate run would
/// silently reset whatever pacing the developer had chosen on that simulator.
/// So every test that writes snapshots the keys it touches and puts them back,
/// whatever the outcome - the `StoreFile.preserving` pattern, applied to
/// `UserDefaults` instead of files.
private enum StoredPreference {
    static let keys = [PacingPreferences.aiTurnSpeedKey, PacingPreferences.incomingOfferTimerKey]

    /// Runs `body` with `keys` saved aside and put back afterwards, including
    /// restoring their absence if they were never set.
    static func preserving<T>(_ keys: [String], _ body: () throws -> T) rethrows -> T {
        let defaults = UserDefaults.standard
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        return try body()
    }

    /// A reader over the real container, started from nothing stored.
    static func freshInstall() -> PacingPreferences {
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        return PacingPreferences(defaults: .standard)
    }
}

// MARK: - Defaults must reproduce what shipped

@Test func standardSpeedIsTheValuePacingYmlShipped() {
    #expect(AITurnSpeed.standard.secondsPerBotAction == 1.1,
            "the default speed must be unchanged by this screen existing")
}

@Test func rollHighlightKeepsTheValuePacingYmlShipped() {
    #expect(PacingPreferences.rollHighlightSeconds == 1.5)
}

@Test func aFreshInstallGetsTheShippedDefaults() {
    StoredPreference.preserving(StoredPreference.keys) {
        let preferences = StoredPreference.freshInstall()
        #expect(preferences.aiTurnSpeed == .standard)
        #expect(preferences.incomingOfferTimer == .fifteenSeconds,
                "15s is what pacing.yml shipped; a player who never opens settings sees no change")
        #expect(preferences.aiTurnSpeed.secondsPerBotAction == 1.1)
        #expect(preferences.incomingOfferTimer.seconds == 15)
    }
}

// MARK: - The properties the deleted range checks were protecting

/// The one real job of the old parser's `0.05...10` range check on
/// `secondsPerBotAction`: zero made the bot loop spin as fast as the CPU
/// allowed, which is the exact symptom the config file was created to cure.
/// Being able to see what the AI did is the reason the delay exists (B1.4).
@Test func noSelectableSpeedIsEffectivelyInstant() {
    for speed in AITurnSpeed.allCases {
        // 0.5 until `ultraFast` (0.3) was added on Jake's ask, 2026-09-17.
        // The bar this guards is "a player can see what the AI did", not any
        // particular number; 0.3s still shows a placement and its animation,
        // and nothing may go below it without that argument being made again.
        #expect(speed.secondsPerBotAction >= 0.3,
                "\(speed) at \(speed.secondsPerBotAction)s would make a bot turn unwatchable")
    }
}

/// The other end of that range. A seat can take up to 25 actions in a turn, so
/// anything above ~2s is a turn measured in minutes.
@Test func noSelectableSpeedMakesATurnLastMinutes() {
    for speed in AITurnSpeed.allCases {
        #expect(speed.secondsPerBotAction <= 2.0,
                "\(speed) at \(speed.secondsPerBotAction)s is a 25-action turn of \(speed.secondsPerBotAction * 25)s")
    }
}

/// A three-option control whose options do the same thing is a control that
/// does nothing, and would look identical in a screenshot.
@Test func everySpeedIsDistinctFromEveryOther() {
    let seconds = AITurnSpeed.allCases.map(\.secondsPerBotAction)
    #expect(Set(seconds).count == AITurnSpeed.allCases.count)
}

/// Zero is meaningful in exactly one place and only one: "wait for the human
/// indefinitely", which is what `IncomingTradeCardView` reads it as. A timed
/// option that resolved to zero would silently become "no limit".
@Test func onlyNoLimitResolvesToZeroSeconds() {
    for timer in IncomingOfferTimer.allCases where timer != .noLimit {
        #expect(timer.seconds > 0, "\(timer) must be a real countdown, not an accidental 'never'")
    }
    #expect(IncomingOfferTimer.noLimit.seconds == 0)
}

/// The labels are the whole of what the player sees, so a label that disagrees
/// with its value is a lie the UI tells with no way to notice.
@Test func everyTimerLabelMatchesItsValue() {
    #expect(IncomingOfferTimer.fifteenSeconds.displayName == "15s")
    #expect(IncomingOfferTimer.fifteenSeconds.seconds == 15)
    #expect(IncomingOfferTimer.thirtySeconds.displayName == "30s")
    #expect(IncomingOfferTimer.thirtySeconds.seconds == 30)
    #expect(IncomingOfferTimer.sixtySeconds.displayName == "60s")
    #expect(IncomingOfferTimer.sixtySeconds.seconds == 60)
    #expect(IncomingOfferTimer.noLimit.displayName == "No Limit")
}

@Test func everyOptionHasADistinctNonEmptyLabel() {
    let speedLabels = AITurnSpeed.allCases.map(\.displayName)
    let timerLabels = IncomingOfferTimer.allCases.map(\.displayName)
    // Evaluated outside `#expect`: `contains(where:)` is `rethrows`, and the
    // macro's expansion of a rethrowing call needs a `try` the test has no
    // error to catch.
    let shortestLabelLength = (speedLabels + timerLabels).map(\.count).min() ?? 0
    #expect(shortestLabelLength > 0, "every option needs a label to tap")
    #expect(Set(speedLabels).count == speedLabels.count)
    #expect(Set(timerLabels).count == timerLabels.count)
}

// MARK: - Persistence, through the container the app actually runs on

/// `.serialized` because every test in here writes the same two
/// `UserDefaults.standard` keys.
@Suite(.serialized)
struct PacingPreferenceStorageTests {

    @Test func aChosenSpeedIsReadBackByAFreshReader() {
        StoredPreference.preserving(StoredPreference.keys) {
            let writer = StoredPreference.freshInstall()
            writer.select(AITurnSpeed.slow)

            #expect(writer.aiTurnSpeed == .slow, "the in-memory value updates immediately")
            #expect(PacingPreferences(defaults: .standard).aiTurnSpeed == .slow,
                    "and a reader constructed afterwards sees it, so the key name is right")
        }
    }

    @Test func aChosenOfferTimerIsReadBackByAFreshReader() {
        StoredPreference.preserving(StoredPreference.keys) {
            let writer = StoredPreference.freshInstall()
            writer.select(IncomingOfferTimer.noLimit)

            #expect(writer.incomingOfferTimer == .noLimit)
            #expect(PacingPreferences(defaults: .standard).incomingOfferTimer == .noLimit)
            #expect(PacingPreferences(defaults: .standard).incomingOfferTimer.seconds == 0)
        }
    }

    /// B2.2 at the storage layer: wanting fast bots is not consent to be
    /// auto-declined, so the two settings cannot share a key or move together.
    @Test func theTwoPreferencesAreStoredIndependently() {
        StoredPreference.preserving(StoredPreference.keys) {
            let preferences = StoredPreference.freshInstall()
            preferences.select(AITurnSpeed.fast)

            let reader = PacingPreferences(defaults: .standard)
            #expect(reader.aiTurnSpeed == .fast)
            #expect(reader.incomingOfferTimer == .fifteenSeconds,
                    "changing the speed must not touch the trade timer")
        }
    }

    /// A raw value this build has no case for - a renamed case between
    /// installs - reads as the default rather than trapping. There is nobody
    /// to report it to: unlike the developer-authored `pacing.yml` this
    /// replaced, the only writer of these keys is `select`.
    @Test func anUnrecognisedStoredValueFallsBackToTheDefault() {
        StoredPreference.preserving(StoredPreference.keys) {
            _ = StoredPreference.freshInstall()
            UserDefaults.standard.set("glacial", forKey: PacingPreferences.aiTurnSpeedKey)
            UserDefaults.standard.set("someday", forKey: PacingPreferences.incomingOfferTimerKey)

            let preferences = PacingPreferences(defaults: .standard)
            #expect(preferences.aiTurnSpeed == .standard)
            #expect(preferences.incomingOfferTimer == .fifteenSeconds)
        }
    }
}
