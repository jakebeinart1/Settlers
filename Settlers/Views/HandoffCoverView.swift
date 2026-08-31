import SwiftUI
import CatanEngine

/// The opaque screen shown when the phone has to change hands.
///
/// ## Why this is not a `PopupCard`
/// `PopupCard` dims the board behind a 45%-opacity scrim and dismisses on a tap
/// outside the card. Both are wrong here. 45% leaves `HumanPlayerPanel`'s
/// resource chips perfectly legible, so the hand this exists to hide would be
/// readable through it; and tap-to-dismiss would let the phone be uncovered by
/// somebody who is not the player it is waiting for. Same paint box, opposite
/// mechanics: fully opaque, and dismissible only by its one button.
///
/// ## What it cannot do
/// The cover is software; the peek is human. Anyone who taps Ready without
/// actually passing the phone sees the next player's hand, and no app can
/// prevent that. It is also not re-armed when the app returns from the
/// background - the person who backgrounded it is the person already holding
/// it, and the real "somebody else picked up the phone" boundary is the device
/// lock screen, which is not this app's to enforce.
struct HandoffCoverView: View {
    /// The player the game is waiting on.
    let seat: PlayerID
    /// How many cards they are holding, so they know what they are picking up
    /// without anyone having to reveal which cards those are.
    let handSize: Int
    let onReady: () -> Void

    var body: some View {
        ZStack {
            // Opaque, and covering everything including the safe area. A
            // translucent ground would defeat the entire point, so this is the
            // board art at full opacity with a dark wash over it rather than a
            // scrim over the live board.
            // Clamped to the screen with a `GeometryReader`, exactly as
            // `MainMenuView`, `EndGameView` and `GameView` all do. Without the
            // clamp, `scaledToFill` reports the aspect-filled image's own
            // height - 810pt against a 667pt screen on a 16:9 phone - the
            // stack centres inside that, and "I'm Ready" lays out below the
            // bottom edge. Since this view also swallows every touch and a
            // force quit resumes straight back into it, that made hot-seat
            // play unreachable AND unrecoverable on an iPhone SE.
            GeometryReader { geo in
                Image("board-background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .overlay(Color.black.opacity(0.72))
            }
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                Text("Pass the phone")
                    .font(.subheadline.weight(.semibold))
                    .kerning(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    CivilizationBadgeMark(seat: seat)
                    Text(CatanTheme.playerLabel(for: seat))
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .foregroundStyle(CatanTheme.color(for: seat))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("it's your turn")
                        .font(.title3)
                        .foregroundStyle(CatanTheme.onWaterText)
                }

                // Public information - anyone at a real table can count the
                // cards in your hand - so showing it here reveals nothing and
                // saves the incoming player a beat of orientation.
                Text("\(handSize) card\(handSize == 1 ? "" : "s") in hand")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                GoldRowButton(title: "I'm Ready", systemImage: "hand.tap.fill", action: onReady)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        // Swallows every touch that is not the button, so nothing underneath
        // can be driven blind by whoever is holding the phone.
        .contentShape(Rectangle())
        .transition(.opacity)
    }
}

/// The seat's civilization mark, sized for the cover.
private struct CivilizationBadgeMark: View {
    let seat: PlayerID

    var body: some View {
        Image(Civilization.forSeat(seat.index).paintedPieceImageName(isCity: false) ?? "civ-britannia-settlement")
            .resizable()
            .scaledToFit()
            .frame(width: 92, height: 92)
            .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
    }
}
