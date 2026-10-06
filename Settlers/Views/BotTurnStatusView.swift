import SwiftUI
import CatanEngine

/// Replaces disabled commands while a CPU owns the next action. The row has
/// the same height as every other command dock, so no wait resizes the map.
///
/// Its button is the Block Trade Offers preference, not a one-turn "Skip
/// pauses" - that became a setting (Jake, 2026-10-06), because a player who
/// wants no pauses wants none every turn. Both live in In-Game Settings too.
struct BotTurnStatusView: View {
    let identity: PlayerIdentity
    let progress: BotTurnProgress?
    let onRetry: () -> Void
    private var preferences: PacingPreferences { .shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            HStack(spacing: 10) {
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
                if isFailed { retryButton }
            }
            .padding(.horizontal, 8)
            // A container identifier without containment propagates to its
            // children, replacing the Skip/Retry button's own identity.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.Game.botProgress)
        }
    }

    private var retryButton: some View {
        Button(action: onRetry) {
            VStack(spacing: 3) {
                Image(systemName: "arrow.clockwise")
                Text("Retry").font(.caption.bold())
            }
            .foregroundStyle(SettingsChrome.ornamentGold)
            .frame(minWidth: 92, minHeight: 52)
            .background(PaintedChromeBackground(fill: .color(CatanTheme.panelBackground), cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.Game.retryBotProgress)
        .accessibilityHint("Retries CPU progress after reloading a failed save when necessary.")
    }

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
