import SwiftUI
import CatanEngine

/// Stable numeric identities stay internal; players refer to a ship by owner.
nonisolated enum NavalShipName {
    static func name(_: Int) -> String { "Ship" }
}

/// Visible and spoken quantities share the same singular wording.
nonisolated enum NavalQuantityText {
    static func hexes(_ count: Int) -> String { "\(count) \(count == 1 ? "hex" : "hexes")" }
    static func stepsRemaining(_ count: Int) -> String {
        count == 0 ? "No sailing left this turn" : "\(hexes(count)) of sailing left"
    }
}

/// Sea and resource-choice materials reuse the board's painted blues and gold.
/// Vessels use the shared civilization artwork in NavalShipBadge.
enum NavalArtwork {
    static let sea = Color(red: 0.075, green: 0.28, blue: 0.40)
    static let shallows = Color(red: 0.20, green: 0.49, blue: 0.53)
    static let mist = Color(red: 0.73, green: 0.78, blue: 0.78)
    static let mistShadow = Color(red: 0.38, green: 0.49, blue: 0.54)
    static let mistLight = Color(red: 0.88, green: 0.90, blue: 0.85)
    static let sail = Color(red: 0.96, green: 0.90, blue: 0.73)
    static let hull = Color(red: 0.37, green: 0.22, blue: 0.12)

    static func drawSea(_ tile: Tile, geometry: HexGeometry, visibleBoard: Board,
                        in context: GraphicsContext) {
        NavalSeaDrawing.draw(tile, geometry: geometry, visibleBoard: visibleBoard, in: context)
    }

    /// The harvest field uses its own painted terrain, with the same grout,
    /// outline and production token as every other numbered land tile.
    static func drawResourceChoice(_ tile: Tile, geometry: HexGeometry, in context: GraphicsContext) {
        TileDrawing.drawTile(tile, geometry: geometry, in: context)
    }
}

/// The unknown world is opaque; only committed discoveries retire their mist.
/// Deterministic billows use coordinate-derived offsets and have no idle timer.
/// Animation interpolates a copied value without reaching actor-owned state.
/// Explicit non-isolation keeps its scalar witness safe wherever SwiftUI
/// performs that interpolation; body rendering still follows View's contract.
nonisolated struct NavalMistLayer: View, Animatable {
    let hidden: [HexCoordinate]
    let retiring: Set<HexCoordinate>
    let geometry: HexGeometry
    var progress: CGFloat
    var drifts = true

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            NavalMistDrawing.draw(hidden, geometry: geometry, viewport: size,
                                  opacity: 1, withdrawal: 0, in: context)
            NavalMistDrawing.draw(retiring.sorted(), geometry: geometry, viewport: size,
                                  opacity: 1 - progress, withdrawal: drifts ? progress : 0, in: context)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

}
