import CoreGraphics
import CatanEngine

/// Cosmetic samples are a stable public-coordinate field, independent of
/// hidden terrain and the saved gameplay RNG. Zoom changes scale, never pattern.
nonisolated enum NavalVisualNoise {
    static func sample(_ cell: HexCoordinate, index: Int, channel: Int = 0) -> CGFloat {
        var bits = UInt64(truncatingIfNeeded: cell.q) &* 0x9E3779B97F4A7C15
            ^ UInt64(truncatingIfNeeded: cell.r) &* 0xBF58476D1CE4E5B9
        bits &+= UInt64(index + 1) &* 0x94D049BB133111EB
        bits &+= UInt64(channel + 1) &* 0xD6E8FEB86659FD93
        bits = (bits ^ (bits >> 30)) &* 0xBF58476D1CE4E5B9
        bits = (bits ^ (bits >> 27)) &* 0x94D049BB133111EB
        bits ^= bits >> 31
        return CGFloat(bits & 0xFFFF) / 65_535
    }
}
