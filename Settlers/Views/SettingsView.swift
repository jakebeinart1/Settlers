import SwiftUI
import CatanEngine

/// Read-only reference screen listing each seat's fixed civilization - its
/// real settlement artwork, general, and material color. Nothing here is
/// user-editable: with art/color/shape all fixed per `Civilization` (see
/// that type's docs for why), there's no longer a "Piece Colors"/"Piece
/// Shape" picker to offer - this screen exists purely so it's clear why the
/// board looks the way it does per seat. Matches `MainMenuView`'s flat,
/// dark, colonist.io-style look.
public struct SettingsView: View {
    public let onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            VStack(spacing: 28) {
                header

                ScrollView {
                    civilizationSection
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }

                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    // MARK: - Civilizations

    private var civilizationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Civilizations")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))

            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { seatIndex in
                    civilizationRow(seatIndex: seatIndex)
                }
            }
        }
    }

    private func civilizationRow(seatIndex: Int) -> some View {
        let civilization = Civilization.forSeat(seatIndex)
        return HStack(spacing: 12) {
            CivilizationBadge(civilization: civilization, isCity: false, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(civilization.displayName)
                    .font(.subheadline.bold())
                Text(seatIndex == 0 ? "You" : civilization.generalName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.14)))
    }
}

#Preview {
    SettingsView(onDismiss: {})
}
