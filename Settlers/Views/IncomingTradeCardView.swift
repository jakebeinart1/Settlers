import SwiftUI
import CatanEngine

/// Small card that slides in above the action row when a bot proposes a
/// trade to the human - replaces the old "wants to trade" toast (which just
/// jumped to the trade sheet) with a self-contained Accept/Reject card and a
/// 5-second countdown ring. The countdown only runs while the card is
/// untouched; tapping anywhere on the card (to read it) pauses the timer so
/// reviewing an offer never causes it to auto-decline out from under you.
/// Timing out untouched counts as a Reject (`respondToTrade(accept: false)`).
public struct IncomingTradeCardView: View {
    public let offer: TradeOffer
    public let onAccept: () -> Void
    public let onReject: () -> Void

    public init(offer: TradeOffer, onAccept: @escaping () -> Void, onReject: @escaping () -> Void) {
        self.offer = offer
        self.onAccept = onAccept
        self.onReject = onReject
    }

    private let totalSeconds: Double = 5
    @State private var remaining: Double = 5
    @State private var isPaused = false
    /// A monotonically increasing tick source (0.1s) rather than a single
    /// `Task.sleep(for: totalSeconds)`, so pausing on tap genuinely halts
    /// the countdown instead of just hiding a timer that fires anyway.
    @State private var tickTask: Task<Void, Never>?

    public var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: remaining / totalSeconds)
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(CatanTheme.playerLabel(for: offer.from)) wants to trade")
                    .font(.caption.bold())
                Text("Give \(describe(offer.give)) → Get \(describe(offer.want))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Button {
                onReject()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .padding(6)
                    .background(Color.red.opacity(0.85), in: Circle())
                    .foregroundStyle(.white)
            }
            Button {
                onAccept()
            } label: {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .padding(6)
                    .background(Color.green.opacity(0.85), in: Circle())
                    .foregroundStyle(.white)
            }
        }
        .padding(10)
        .background(CatanTheme.hudChipBackgroundActive, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.2), lineWidth: 1))
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onTapGesture {
            isPaused = true
        }
        .onAppear(perform: startTicking)
        .onDisappear { tickTask?.cancel() }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task {
            while remaining > 0 {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
                guard !isPaused else { continue }
                remaining = max(0, remaining - 0.1)
            }
            onReject()
        }
    }

    private func describe(_ resources: [Resource: Int]) -> String {
        resources
            .filter { $0.value > 0 }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.value) \($0.key.rawValue)" }
            .joined(separator: ", ")
    }
}
