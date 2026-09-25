import SwiftUI

/// The gameplay surface that owns input after all simultaneous claims have
/// been resolved. Declaration order is not priority; the resolver below is
/// deliberately explicit so adding a case cannot silently reorder the UI.
enum GameInteractionSurface: CaseIterable, Hashable, Sendable {
    case recoveryFailure
    case mandatoryDiscard
    case mandatoryBoardDecision
    case privateReceipt
    case optionalBoardDecision
    case incomingTrade
    case ordinaryActions
}

/// Current claims on the game's one interactive surface.
///
/// Settings is intentionally orthogonal. It covers the resolved surface while
/// open, but does not replace or erase a draft that must resume underneath.
struct GameInteractionPriorityInput: Equatable, Sendable {
    var hasRecoveryFailure = false
    var hasMandatoryDiscard = false
    var hasMandatoryBoardDecision = false
    var hasPrivateReceipt = false
    var hasOptionalBoardDecision = false
    var hasIncomingTrade = false
    var isSettingsPresented = false
}

struct GameInteractionPriorityResolution: Equatable, Sendable {
    /// The winning gameplay surface, preserved even while Settings covers it.
    let winner: GameInteractionSurface
    let isSettingsCoverPresented: Bool

    /// Input ownership and policy pacing use the same answer. Only an
    /// unobstructed ordinary surface permits bot progress; Settings freezes
    /// whichever surface it temporarily covers.
    var blocksBotProgress: Bool {
        isSettingsCoverPresented || winner != .ordinaryActions
    }
}

/// One deterministic answer for visual order, hit testing, accessibility, and
/// bot pausing. Keeping the precedence here prevents each consumer from
/// inventing a subtly different chain of SwiftUI conditionals.
enum GameInteractionPriority {
    static func resolve(
        _ input: GameInteractionPriorityInput
    ) -> GameInteractionPriorityResolution {
        let winner: GameInteractionSurface
        if input.hasRecoveryFailure {
            winner = .recoveryFailure
        } else if input.hasMandatoryDiscard {
            winner = .mandatoryDiscard
        } else if input.hasMandatoryBoardDecision {
            winner = .mandatoryBoardDecision
        } else if input.hasPrivateReceipt {
            winner = .privateReceipt
        } else if input.hasOptionalBoardDecision {
            winner = .optionalBoardDecision
        } else if input.hasIncomingTrade {
            winner = .incomingTrade
        } else {
            winner = .ordinaryActions
        }
        return GameInteractionPriorityResolution(
            winner: winner,
            isSettingsCoverPresented: input.isSettingsPresented
        )
    }
}
