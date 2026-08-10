import Foundation
import Observation
import CatanEngine

/// Persists the player-facing rendering preferences set from `SettingsView`:
/// each seat's `PieceColor` and the board-wide `PieceShapeStyle`. Backed by
/// `UserDefaults` rather than a JSON file (unlike `GameStore`) since this is
/// small keyed preference data, not a `GameState`-sized blob.
///
/// `@Observable` so `CatanTheme`/`BoardView` call sites reading
/// `SettingsStore.shared` re-render automatically the moment `SettingsView`
/// changes a value - no explicit "Save" step or app restart needed.
@MainActor
@Observable
public final class SettingsStore {
    public static let shared = SettingsStore()

    private enum Keys {
        static let playerColors = "settings.playerColors"
        static let pieceShapeStyle = "settings.pieceShapeStyle"
    }

    private let defaults: UserDefaults

    /// One `PieceColor` per seat, indexed by `PlayerID.index` (0...3).
    /// Setting this enforces nothing by itself - `SettingsView` is
    /// responsible for preventing duplicate colors across seats - but it
    /// always persists and notifies observers on write.
    public var playerColors: [PieceColor] {
        didSet { persistPlayerColors() }
    }

    public var pieceShapeStyle: PieceShapeStyle {
        didSet { defaults.set(pieceShapeStyle.rawValue, forKey: Keys.pieceShapeStyle) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let stored = defaults.stringArray(forKey: Keys.playerColors) ?? []
        self.playerColors = (0..<4).map { index in
            guard stored.indices.contains(index), let color = PieceColor(rawValue: stored[index]) else {
                return PieceColor.defaultColor(forSeatIndex: index)
            }
            return color
        }

        if let rawShape = defaults.string(forKey: Keys.pieceShapeStyle), let shape = PieceShapeStyle(rawValue: rawShape) {
            self.pieceShapeStyle = shape
        } else {
            self.pieceShapeStyle = .classic
        }
    }

    /// The color for a given seat, falling back to that seat's default if
    /// `playerColors` is somehow shorter than expected (defensive - it's
    /// always initialized to length 4).
    public func color(forSeatIndex index: Int) -> PieceColor {
        playerColors.indices.contains(index) ? playerColors[index] : PieceColor.defaultColor(forSeatIndex: index)
    }

    /// Sets seat `index`'s color. Does not itself check for collisions with
    /// other seats - `SettingsView` disables already-taken swatches so this
    /// is never called with a duplicate in practice.
    public func setColor(_ color: PieceColor, forSeatIndex index: Int) {
        guard playerColors.indices.contains(index) else { return }
        playerColors[index] = color
    }

    public func resetToDefaults() {
        playerColors = (0..<4).map(PieceColor.defaultColor(forSeatIndex:))
        pieceShapeStyle = .classic
    }

    private func persistPlayerColors() {
        defaults.set(playerColors.map(\.rawValue), forKey: Keys.playerColors)
    }
}
