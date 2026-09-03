import Foundation

/// Cached at the load boundary, not inferred from file existence on every render.
/// A blocked save has a display-only placeholder state; only an explicit new
/// game may replace it, after the original artifacts have been preserved.
public enum SavedGameAvailability: Equatable {
    case absent
    case playable
    case blocked(String)

    public var canResume: Bool { self == .playable }

    public var recoveryMessage: String? {
        guard case .blocked(let message) = self else { return nil }
        return message
    }
}

enum SavedGameRecoveryError: LocalizedError {
    case blocked(String)

    var errorDescription: String? {
        switch self {
        case .blocked(let message): return message
        }
    }
}
