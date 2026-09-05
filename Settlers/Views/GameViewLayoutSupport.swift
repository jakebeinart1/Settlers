import SwiftUI

/// The gameplay surface that owns input after all simultaneous claims have
/// been resolved. Declaration order is not priority; the resolver below is
/// deliberately explicit so adding a case cannot silently reorder the UI.
enum GameInteractionSurface: CaseIterable, Hashable, Sendable {
    case handoff
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
    var needsHandoff = false
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
        if input.needsHandoff {
            winner = .handoff
        } else if input.hasRecoveryFailure {
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

private struct SlotHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Reserves the tallest height its content has measured. Dynamic banners used
/// to resize the flexible board every time they appeared or disappeared.
/// Empty content must be a zero-height view; an unconstrained `Color.clear`
/// competes with the board for the same flexible space before measurement.
struct StableHeightSlot<Content: View>: View {
    @Binding var height: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(key: SlotHeightKey.self, value: geometry.size.height)
                }
            )
            .onPreferenceChange(SlotHeightKey.self) { measured in
                if measured > height { height = measured }
            }
            .frame(height: height > 0 ? height : nil, alignment: .top)
    }
}
