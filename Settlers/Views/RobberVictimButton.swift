import SwiftUI

/// Full-height ownership card for robber-victim contexts outside the board
/// decision dock. It consumes the same match-authoritative `PlayerIdentity` as
/// the HUD, board pieces, and compact dock chooser.
struct RobberVictimButton: View {
    let identity: PlayerIdentity
    let resourceCardCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                crestWithCardCount
                Text(identity.displayName)
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(identity.civilization.displayName)
                    .font(.system(size: 8, weight: .semibold, design: .serif))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TintedTextureBackground(
                tint: identity.civilization.cardBackgroundColor(active: true)
            ))
            .clipShape(FrameCornerRect(cornerRadius: 8, notchScale: 0.7))
            .playerCardBorder(
                color: identity.civilization.accentColor,
                cornerRadius: 8,
                lineWidth: 2
            )
            .foregroundStyle(.white)
        }
        .accessibilityIdentifier(AccessibilityID.Robber.victim(identity.seat))
        .accessibilityLabel(
            "\(identity.accessibilityLabel), "
                + "\(resourceCardCount) resource cards"
        )
        .accessibilityHint("Steal one random resource card")
    }

    private var crestWithCardCount: some View {
        ZStack(alignment: .bottomTrailing) {
            CivilizationCrest(civilization: identity.civilization, size: 27)
            Text("\(resourceCardCount)")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(minWidth: 13, minHeight: 13)
                .background(Color.black.opacity(0.9), in: Circle())
                .overlay(Circle().strokeBorder(identity.civilization.accentColor, lineWidth: 1))
                .offset(x: 3, y: 2)
        }
    }
}
