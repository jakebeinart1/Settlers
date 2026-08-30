import SwiftUI
import CatanEngine

/// The three small chips that float over the board: the dice roll
/// (top-left), and the bank/deck counts with the pause button beneath
/// them (top-right).
///
/// Split out of `GameView` because that file had grown past the 1,250-line
/// limit `.swiftlint.yml` enforces, and these three are the most cohesive
/// group in it - they share a purpose, a corner, and a coordinate space.
/// `TopChipHeightKey` measures the band they occupy so the board can clear
/// them without a hardcoded inset.
extension GameView {

    /// Stacked directly beneath `deckCountChip` in the board's top-trailing
    /// corner (see that overlay). Opens `InGameSettingsView` - pacing, the
    /// trade timer, and the Resume/Restart/Main Menu actions this button used
    /// to open on their own. The pause is no longer implicit: `GameView`
    /// mirrors this into `GameViewModel.isSettingsSurfaceOpen`, which the bot
    /// loop stops on, so the game cannot advance behind the screen.
    var pauseButton: some View {
        Button {
            isShowingInGameSettings = true
        } label: {
            Image("menu-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
        }
    }

    /// Bigger and plainer than before (no more flying resource badges to
    /// share attention with) - the current roll is the one thing this
    /// needs to say clearly, so it gets a large number front and center.
    /// `rollHistory` (up to the 3 rolls before this one) sits underneath in
    /// a small, faded line - enough to catch someone back up at a glance
    /// without competing with the current roll for attention.
    func diceChip(_ roll: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                // A real die-face tile, not the old SF Symbol - that read as
                // a thin outline rather than an actual square against the
                // reference's bold ivory tile (see chat).
                DieFaceView(value: roll, size: 34)
                Text("\(roll)")
                    .font(.system(size: 32, weight: .heavy, design: .serif))
            }
            .foregroundStyle(.white)
            // Bumped from 10 - "7" (and other single digits) sat close
            // enough to the chip's own right edge/border to read as clipped,
            // especially once the digit's serif tail is included.
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(PaintedChromeBackground(textureImageName: "dice-fill", cornerRadius: 12, notchScale: 1.0))
            .scaleEffect(diceScale)
            .rotationEffect(.degrees(diceRotation))

            if !rollHistory.isEmpty {
                Text(rollHistory.map(String.init).joined(separator: "   "))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.leading, 14)
            }
        }
    }

    /// Top-right counterpart to `diceChip`: the bank's remaining count for
    /// each individual resource, plus the development-card deck's remaining
    /// count - both finite, shared piles in real Catan (19 of each resource,
    /// 25 development cards), so seeing them tick down explains things like
    /// "why can't I buy a dev card anymore" at a glance instead of a
    /// silently-disabled button. Broken out per-resource rather than one
    /// summed total, since "the bank is out of ore" and "the bank is out of
    /// brick" are different, useful pieces of information a single number
    /// would hide.
    var deckCountChip: some View {
        HStack(spacing: 8) {
            ForEach(Resource.allCases, id: \.self) { resource in
                VStack(spacing: 1) {
                    // Rounded square, not a circle - matches the resource
                    // swatches in `MainMenuView`'s title block and
                    // `HumanPlayerPanel.resourceDot`, per Jake's ask to keep
                    // one consistent shape for "a resource" across the app.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(CatanTheme.color(for: resource))
                        .frame(width: 10, height: 10)
                    Text("\(state.bank[resource] ?? 0)")
                        .font(.system(size: 11, weight: .bold, design: .serif))
                }
            }

            Divider()
                .frame(height: 22)
                .overlay(Color.white.opacity(0.3))

            VStack(spacing: 1) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 10))
                Text("\(state.devCardDeck.count)")
                    .font(.system(size: 11, weight: .bold, design: .serif))
            }
        }
        .foregroundStyle(.white)
        // Widened from 10 - Jake wanted more breathing room on either side
        // of the resource-count digits than the tight original fit gave.
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(PaintedChromeBackground(textureImageName: "bank-fill", cornerRadius: 10, notchScale: 1.0))
    }

    /// A physical six-sided die face - a rounded ivory square with black pip
    /// dots in the standard layout - used by `diceChip` in place of the old
    /// `Image(systemName: "die.face.N.fill")`, which read as a thin outline
    /// rather than an actual square at the size it was shown.
    struct DieFaceView: View {
        let value: Int
        let size: CGFloat

        /// Fractional (x, y) pip centers within the tile, standard 6-face
        /// die layout, shared across every count via one 3x3 grid.
        private static let pipLayouts: [Int: [(CGFloat, CGFloat)]] = [
            1: [(0.5, 0.5)],
            2: [(0.25, 0.25), (0.75, 0.75)],
            3: [(0.25, 0.25), (0.5, 0.5), (0.75, 0.75)],
            4: [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)],
            5: [(0.25, 0.25), (0.75, 0.25), (0.5, 0.5), (0.25, 0.75), (0.75, 0.75)],
            6: [(0.25, 0.22), (0.75, 0.22), (0.25, 0.5), (0.75, 0.5), (0.25, 0.78), (0.75, 0.78)],
        ]

        var body: some View {
            let pips = Self.pipLayouts[min(max(value, 1), 6)] ?? []
            let pipSize = size * 0.16

            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(CatanTheme.onWaterText.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .strokeBorder(.black.opacity(0.55), lineWidth: max(1, size * 0.045))
                )
                .overlay(
                    ForEach(Array(pips.enumerated()), id: \.offset) { _, pip in
                        Circle()
                            .fill(.black.opacity(0.82))
                            .frame(width: pipSize, height: pipSize)
                            .position(x: pip.0 * size, y: pip.1 * size)
                    }
                )
                .frame(width: size, height: size)
        }
    }
}
