import SwiftUI
import CatanEngine

/// Replaces disabled commands while a CPU owns the next action. The row has
/// the same height as every other command dock, so no wait resizes the map.
/// Pacing lives on the leading side; incoming trade answers live on the
/// trailing side. Repeated physical Skip touches therefore cannot turn into
/// acceptance or refusal when an offer replaces this row.
struct BotTurnStatusView: View {
    let identity: PlayerIdentity
    let progress: BotTurnProgress?
    let onSkip: () -> Void
    let onRetry: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            HStack(spacing: 10) {
                if Self.showsPacingControl(progress: progress, skipPausesIsOn: PacingPreferences.shared.skipPauses) {
                    pacingControl
                }
                CivilizationCrest(civilization: identity.civilization, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(identity.displayName) · CPU")
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text(description(at: context.date))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            // A container identifier without containment propagates to its
            // children, replacing the Skip/Retry button's own identity.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.Game.botProgress)
        }
    }

    /// The complete painted rectangle is one predictable target, including
    /// padding. Its position never shares an incoming answer's hit region.
    private var pacingControl: some View {
        Button(action: isFailed ? onRetry : onSkip) {
            VStack(spacing: 3) {
                Image(systemName: isFailed ? "arrow.clockwise" : "forward.end.fill")
                Text(isFailed ? "Retry" : "Skip pauses").font(.caption.bold())
            }
            .foregroundStyle(SettingsChrome.ornamentGold)
            .frame(width: Self.pacingButtonWidth, height: Self.pacingButtonHeight)
            .background(PaintedChromeBackground(fill: .color(CatanTheme.panelBackground), cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(isFailed ? AccessibilityID.Game.retryBotProgress : AccessibilityID.Game.skipBotPauses)
        .accessibilityHint(isFailed
            ? "Retries CPU progress after reloading a failed save when necessary."
            : "Skips viewing delays only. Human decisions still require your response.")
    }

    /// With Skip Pauses already on in Settings the Skip button does nothing
    /// (Jake, 2026-10-08), so it is left out. Retry always shows: it is the
    /// only way out of a failed CPU step.
    static func showsPacingControl(progress: BotTurnProgress?, skipPausesIsOn: Bool) -> Bool {
        if case .failed = progress { return true }
        return !skipPausesIsOn
    }

    private static let pacingButtonWidth: CGFloat = 92
    private static let pacingButtonHeight: CGFloat = 52

    private var isFailed: Bool {
        if case .failed = progress { return true }
        return false
    }

    private func description(at date: Date) -> String {
        switch progress {
        case .waiting(_, let deadline):
            let seconds = Int(ceil(max(0, deadline.timeIntervalSince(date))))
            return "Viewing pause · \(seconds)s"
        case .thinking: return "Choosing a move…"
        case .failed(_, let message): return "Paused · \(message)"
        case nil: return "Preparing the next move…"
        }
    }
}
