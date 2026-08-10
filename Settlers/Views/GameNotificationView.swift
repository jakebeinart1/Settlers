import SwiftUI

/// A transient, auto-dismissing event notification (bot trade offer, road/
/// settlement/city built, dev card played, longest-road/largest-army
/// earned). Purely a UI-layer concept - see `GameView`'s log-diffing logic
/// for how these get created.
public struct GameNotification: Identifiable, Equatable {
    public let id = UUID()
    public let text: String
    public let systemImage: String
    public let tint: Color
    /// Optional tap affordance - currently used only by trade-offer
    /// notifications, to jump straight to the trade sheet.
    public var onTap: (() -> Void)?

    public static func == (lhs: GameNotification, rhs: GameNotification) -> Bool {
        lhs.id == rhs.id
    }
}

/// Stacked toast surface, layered above the board/buttons in a `ZStack`
/// (same pattern as the existing "Bot thinking…" overlay): doesn't block
/// taps on anything underneath it, and each toast disappears on its own
/// after `GameView` removes it from the queue.
public struct GameNotificationOverlay: View {
    public let notifications: [GameNotification]

    public init(notifications: [GameNotification]) {
        self.notifications = notifications
    }

    public var body: some View {
        VStack(spacing: 6) {
            ForEach(notifications) { notification in
                Button {
                    notification.onTap?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: notification.systemImage)
                        Text(notification.text)
                            .font(.caption.bold())
                            .lineLimit(2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(notification.tint.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(notification.onTap == nil)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 12)
        .allowsHitTesting(!notifications.isEmpty)
    }
}
