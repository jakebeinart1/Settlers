import Foundation

/// Loads `PacingSettings` from a bundled `pacing.yml`.
///
/// ## Why YAML, and why a parser this strict
/// YAML was asked for, and for a flat file of three numbers with comments it
/// is a reasonable ask - comments are the one thing JSON cannot give, and the
/// point of this file is for a person to read it and try a different number.
///
/// What is NOT reasonable is a lenient hand-rolled parser. A YAML subset that
/// shrugs at a line it does not understand and carries on is exactly the
/// failure this repo has a rule about: it reports success having applied
/// nothing, so a value you edited silently does not take effect and the app
/// behaves as though you never changed it. So every line must be a comment, be
/// blank, or be a `key: value` pair whose key is known and whose value parses
/// as a number - anything else throws, and the throw is surfaced rather than
/// swallowed.
///
/// This deliberately supports **only** flat `key: value` scalars. It is not a
/// YAML implementation and must not grow into one; if this file ever needs
/// nesting, lists, anchors or multi-line strings, that is the signal to take a
/// real parser as a dependency in the app target (never in the packages, which
/// stay dependency-free so CI can test them on Linux).
///
/// ## Where the file lives
/// Bundled with the app, so it is read-only at runtime on iOS: editing it and
/// rebuilding is the loop. That is the honest limit of a bundled config - a
/// setting a *player* could change would have to be a Settings screen writing
/// to `Documents/`, which is a different feature.
enum PacingSettingsStore {

    enum LoadError: Error, CustomStringConvertible {
        case unreadable(String)
        case malformedLine(number: Int, text: String)
        case unknownKey(String, line: Int)
        case unparsableValue(key: String, value: String, line: Int)
        case valueOutOfRange(key: String, value: Double, allowed: ClosedRange<Double>, line: Int)

        var description: String {
            switch self {
            case .unreadable(let name):
                return "pacing config '\(name)' is missing from the app bundle"
            case .malformedLine(let number, let text):
                return "pacing.yml line \(number) is not 'key: value': \(text)"
            case .unknownKey(let key, let line):
                return "pacing.yml line \(line): unknown key '\(key)'"
            case .unparsableValue(let key, let value, let line):
                return "pacing.yml line \(line): '\(key)' needs a number, got '\(value)'"
            case .valueOutOfRange(let key, let value, let allowed, let line):
                return "pacing.yml line \(line): '\(key)' is \(value), outside \(allowed.lowerBound)...\(allowed.upperBound)"
            }
        }
    }

    /// The settings the app runs on.
    ///
    /// Resolved once. A `fatalError` on a bad config is deliberate and only
    /// reachable by a developer editing the bundled file: the alternative is
    /// running with silently-ignored settings, which is the exact confusion
    /// this parser's strictness exists to prevent. It cannot be triggered by a
    /// player, since the file ships inside the app.
    ///
    /// **`SettlersApp` touches this during startup on purpose.** It is a lazy
    /// global, so without that its first read is whenever the bot loop or the
    /// roll highlight happens to run - meaning a malformed file would trap
    /// mid-game, after someone had started one, rather than immediately. The
    /// whole argument for trapping rests on failing at the earliest possible
    /// moment, so the read has to be forced.
    static let current: PacingSettings = {
        do {
            return try load(from: Bundle.main)
        } catch {
            fatalError("\(error)")
        }
    }()

    static func load(from bundle: Bundle, named name: String = "pacing") throws -> PacingSettings {
        guard let url = bundle.url(forResource: name, withExtension: "yml"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw LoadError.unreadable(name)
        }
        return try parse(text)
    }

    private static func checked(_ value: Double, key: String,
                                in allowed: ClosedRange<Double>, line: Int) throws -> Double {
        guard allowed.contains(value) else {
            throw LoadError.valueOutOfRange(key: key, value: value, allowed: allowed, line: line)
        }
        return value
    }

    /// Parses the flat `key: value` subset described above.
    ///
    /// Separate from `load` so it can be tested without a bundle - the failure
    /// modes are the whole point of this type, and they are unreachable through
    /// a file that ships correct.
    static func parse(_ text: String) throws -> PacingSettings {
        var settings = PacingSettings.default

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            // Strip trailing comments, then trim. A `#` inside a value would be
            // wrong here, but every value in this file is a number.
            let withoutComment = rawLine.split(separator: "#", maxSplits: 1,
                                               omittingEmptySubsequences: false)[0]
            let line = withoutComment.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw LoadError.malformedLine(number: lineNumber, text: line)
            }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let rawValue = parts[1].trimmingCharacters(in: .whitespaces)
            guard let value = Double(rawValue) else {
                throw LoadError.unparsableValue(key: key, value: rawValue, line: lineNumber)
            }

            // Range-checked, not just parsed. A number that reads fine and
            // then does nothing is the very failure this parser's strictness
            // exists to prevent: `secondsPerBotAction: 0` makes the bot loop
            // spin as fast as the CPU allows, which is the symptom the file was
            // created to cure, and a negative `rollHighlightSeconds` makes the
            // highlight vanish instantly because `Task.sleep` with a past
            // deadline returns immediately. Both would have been accepted.
            switch key {
            case "secondsPerBotAction":
                settings.secondsPerBotAction = try checked(value, key: key, in: 0.05...10, line: lineNumber)
            case "rollHighlightSeconds":
                settings.rollHighlightSeconds = try checked(value, key: key, in: 0...10, line: lineNumber)
            case "incomingOfferTimeoutSeconds":
                // Zero is meaningful here and only here: it means "never".
                settings.incomingOfferTimeoutSeconds = try checked(value, key: key, in: 0...120, line: lineNumber)
            default: throw LoadError.unknownKey(key, line: lineNumber)
            }
        }
        return settings
    }
}
