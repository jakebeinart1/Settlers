import SwiftUI

/// Compact ownership card for the current robber-victim chooser.
///
/// The larger two-step robber redesign is specified separately. This card
/// closes the identity bug in the shipping chooser now: a victim is never an
/// anonymous question-mark icon detached from the name, civilization and
/// board color the player just matched above.
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
            "\(identity.displayName), \(identity.civilization.displayName), "
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
