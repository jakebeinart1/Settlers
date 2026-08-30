import Testing
import Foundation
@testable import Settlers

/// Covers the pacing config, and specifically its refusal to guess.
///
/// The parser is deliberately strict, and that strictness is the feature: a
/// lenient `key: value` reader that skips a line it does not understand
/// reports success having applied nothing, so a number you edited silently
/// does not take effect and the app behaves as though you never touched it.
/// These tests exist to prove it fails loudly instead.

@Test func aWellFormedFileParses() throws {
    let settings = try PacingSettingsStore.parse("""
        # a comment
        secondsPerBotAction: 1.25

        rollHighlightSeconds: 2   # trailing comment
        incomingOfferTimeoutSeconds: 0
        """)
    #expect(settings.secondsPerBotAction == 1.25)
    #expect(settings.rollHighlightSeconds == 2)
    #expect(settings.incomingOfferTimeoutSeconds == 0)
}

@Test func absentKeysKeepTheirDefaults() throws {
    // Partial files are legal - the point is that an omitted key falls back,
    // while a MISPELLED one does not (see below). Those must not look the same.
    let settings = try PacingSettingsStore.parse("secondsPerBotAction: 3")
    #expect(settings.secondsPerBotAction == 3)
    #expect(settings.rollHighlightSeconds == PacingSettings.default.rollHighlightSeconds)
}

@Test func anUnknownKeyIsRejectedRatherThanIgnored() {
    // The failure this whole design is about: a typo'd key silently doing
    // nothing, leaving you convinced the setting does not work.
    #expect(throws: PacingSettingsStore.LoadError.self) {
        try PacingSettingsStore.parse("secondsPerBotActions: 2")
    }
}

@Test func aNonNumericValueIsRejected() {
    #expect(throws: PacingSettingsStore.LoadError.self) {
        try PacingSettingsStore.parse("secondsPerBotAction: slowly")
    }
}

@Test func aLineThatIsNotAKeyValuePairIsRejected() {
    // Guards against this quietly growing into a half-YAML parser: nesting,
    // lists and anchors all fail here rather than being partly honoured.
    #expect(throws: PacingSettingsStore.LoadError.self) {
        try PacingSettingsStore.parse("pacing:\n  - 1\n  - 2")
    }
}

@Test func commentsAndBlankLinesAreFine() throws {
    let settings = try PacingSettingsStore.parse("\n# only comments\n\n   # indented\n\n")
    #expect(settings == PacingSettings.default)
}

@Test func anOutOfRangeValueIsRejected() {
    // The subtler half of the same failure an unknown key causes. A number
    // that parses but does nothing useful still leaves you convinced the
    // setting is broken - and `secondsPerBotAction: 0` does not merely do
    // nothing, it restores the exact symptom this file exists to cure by
    // letting the bot loop spin as fast as the CPU allows.
    for line in ["secondsPerBotAction: 0",
                 "secondsPerBotAction: -1",
                 "secondsPerBotAction: 999",
                 "rollHighlightSeconds: -1",
                 "incomingOfferTimeoutSeconds: -5"] {
        #expect(throws: PacingSettingsStore.LoadError.self, "\(line) should be rejected") {
            try PacingSettingsStore.parse(line)
        }
    }
}

@Test func zeroIsAcceptedOnlyWhereItMeansSomething() throws {
    // Zero is the documented "never" for the offer timeout, so it must parse
    // there even though it is rejected everywhere else.
    let settings = try PacingSettingsStore.parse("incomingOfferTimeoutSeconds: 0")
    #expect(settings.incomingOfferTimeoutSeconds == 0)
}

@Test func theShippedFileParsesAndIsSane() throws {
    // The bundled file is what actually runs. `PacingSettingsStore.current`
    // traps on a bad one, so this is the test that stops a bad edit reaching a
    // launch.
    // `Bundle.main` rather than the test bundle: these are host-app unit
    // tests, so main IS the app being tested, and the app bundle is where
    // `pacing.yml` actually ships. Reading it from anywhere else would test a
    // copy that never runs.
    let settings = try PacingSettingsStore.load(from: .main)
    #expect(settings.secondsPerBotAction > 0, "a zero floor makes bot turns unwatchable again")
    #expect(settings.secondsPerBotAction < 5, "a bot turn is up to 25 actions; this would be minutes")
    #expect(settings.incomingOfferTimeoutSeconds >= 0)
}
