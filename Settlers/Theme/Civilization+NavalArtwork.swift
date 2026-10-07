import Foundation

extension Civilization {
    /// Each current controller has a distinct painted hull and broad colored
    /// sail. Capture changes this presentation only after the engine commits;
    /// no builder provenance or new save field is inferred from a ship's ID.
    var shipAssetName: String {
        switch self {
        case .medieval: return "civ-britannia-ship"
        case .greece: return "civ-greece-ship"
        case .egypt: return "civ-egypt-ship"
        case .aztec: return "civ-aztec-ship"
        case .columbia: return "civ-columbia-ship"
        case .rome: return "civ-rome-ship"
        case .japan: return "civ-japan-ship"
        case .norse: return "civ-norse-ship"
        }
    }
}
