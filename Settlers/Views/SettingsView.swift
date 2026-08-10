import SwiftUI
import CatanEngine

/// Lets the player customize each seat's piece color and the board-wide
/// piece shape style, both persisted via `SettingsStore.shared` and applied
/// live (no explicit "Save" step - every control writes straight through to
/// the store, which is `@Observable`, so `BoardView`/`PlayerHUDView`/etc.
/// pick the change up immediately once this screen is dismissed). Matches
/// `MainMenuView`'s flat, dark, colonist.io-style look.
public struct SettingsView: View {
    public let onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    private var store: SettingsStore { SettingsStore.shared }

    public var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            VStack(spacing: 28) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        colorSection
                        shapeSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }

                resetButton
                    .padding(.bottom, 16)
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

    // MARK: - Colors

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Piece Colors")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))

            VStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { seatIndex in
                    playerColorRow(seatIndex: seatIndex)
                }
            }
        }
    }

    private func playerColorRow(seatIndex: Int) -> some View {
        let player = PlayerID(index: seatIndex)
        let selected = store.color(forSeatIndex: seatIndex)
        let takenElsewhere = Set(store.playerColors.indices.filter { $0 != seatIndex }.map { store.playerColors[$0] })

        return VStack(alignment: .leading, spacing: 8) {
            Text(CatanTheme.playerLabel(for: player))
                .font(.subheadline.bold())
                .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 10) {
                ForEach(PieceColor.allCases, id: \.self) { candidate in
                    let isTaken = takenElsewhere.contains(candidate) && candidate != selected
                    Button {
                        store.setColor(candidate, forSeatIndex: seatIndex)
                    } label: {
                        Circle()
                            .fill(candidate.color)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .strokeBorder(candidate == selected ? Color.white : Color.white.opacity(0.15), lineWidth: candidate == selected ? 3 : 1)
                            )
                            .opacity(isTaken ? 0.25 : 1)
                    }
                    .disabled(isTaken)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.14)))
    }

    // MARK: - Shape style

    private var shapeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Piece Shape")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: 16) {
                ForEach(PieceShapeStyle.allCases, id: \.self) { style in
                    shapeStyleThumbnail(style)
                }
            }
        }
    }

    private func shapeStyleThumbnail(_ style: PieceShapeStyle) -> some View {
        let isSelected = store.pieceShapeStyle == style
        return Button {
            store.pieceShapeStyle = style
        } label: {
            VStack(spacing: 10) {
                style.settlementShape()
                    .fill(CatanTheme.color(for: PlayerID(index: 0)))
                    .overlay(style.settlementShape().stroke(.black.opacity(0.6), lineWidth: 1))
                    .frame(width: 36, height: 36)

                Text(style.displayName)
                    .font(.subheadline.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? CatanTheme.color(for: Resource.brick) : .clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var resetButton: some View {
        Button {
            store.resetToDefaults()
        } label: {
            Text("Reset to Defaults")
                .font(.subheadline.bold())
        }
        .buttonStyle(.bordered)
        .tint(.white)
    }
}

#Preview {
    SettingsView(onDismiss: {})
}
