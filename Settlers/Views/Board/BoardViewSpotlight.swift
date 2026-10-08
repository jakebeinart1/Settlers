import SwiftUI
import CatanEngine

/// What the victory cutscene lights on an otherwise read-only board.
struct BoardSpotlight: Equatable {
    var vertices: Set<VertexID> = []
    var edges: Set<EdgeID> = []
    /// The piece the camera glides to; `nil` is the fitted board.
    var focus: VertexID?
    /// Floats above `focus`, e.g. "+2".
    var label: String?
}

extension BoardView {
    /// Close enough that one piece and its neighbours fill the board, far
    /// enough that the tour still reads as one island rather than one hex.
    static let spotlightZoom: CGFloat = 1.9

    func spotlighting(_ spotlight: BoardSpotlight?) -> Self {
        var lit = self
        lit.spotlight = spotlight
        return lit
    }

    /// Drawn below the buildings, so a lit network rims the road under the
    /// settlements rather than smearing over them. Glows here are a wide
    /// translucent stroke under a narrow one, never `.shadow`: a blur is
    /// expensive to composite, and the tour lights up to fifteen at once.
    func spotlightRoads(_ spotlight: BoardSpotlight, geometry: HexGeometry) -> some View {
        let network = roadNetworkPath(for: spotlight.edges, geometry: geometry)
        return ZStack {
            network.stroke(CatanTheme.cityPennantGold.opacity(0.35), style: roadStroke(width: geometry.size * 0.42))
            network.stroke(CatanTheme.cityPennantGold, style: roadStroke(width: geometry.size * 0.24))
        }
        .allowsHitTesting(false)
    }

    func spotlightLayer(_ spotlight: BoardSpotlight, geometry: HexGeometry) -> some View {
        let gold = CatanTheme.cityPennantGold
        return ZStack {
            ForEach(spotlight.vertices.sorted(), id: \.self) { vertex in
                ZStack {
                    Circle().stroke(gold.opacity(0.35), lineWidth: geometry.size * 0.22)
                    Circle().stroke(gold, lineWidth: geometry.size * 0.08)
                }
                .frame(width: geometry.size * 1.15, height: geometry.size * 1.15)
                .position(geometry.vertexPosition(vertex, board: board))
            }
            if let focus = spotlight.focus, let label = spotlight.label {
                let piece = geometry.vertexPosition(focus, board: board)
                Text(label)
                    .font(.system(size: 17, weight: .black, design: .serif))
                    .foregroundStyle(gold)
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(.black.opacity(0.75)))
                    .overlay(Capsule().stroke(gold, lineWidth: 1))
                    .position(x: piece.x, y: piece.y - geometry.size * 1.1)
                    .id(focus)
                    .transition(.opacity.combined(with: .offset(y: 12)))
            }
        }
        .allowsHitTesting(false)
    }

    /// Where the tour's lens sits: the zoom and pan to apply to the whole
    /// drawn board as ONE transform (`body` applies it before the clip).
    ///
    /// Not the camera. Stepping `camera` re-renders every board layer each
    /// frame, and the recorded glide ran at ~20-25fps on the simulator; it
    /// cannot be animated either, because the tile `Canvas` takes a camera
    /// change at once while SwiftUI pieces interpolate, tearing pieces off
    /// their hexes (the reason naval focus disables camera animation). A
    /// transform over the composited board animates on the GPU with every
    /// layer moving together.
    func spotlightLens(fit: BoardFit, container: CGSize) -> BoardCamera {
        guard let focus = spotlight?.focus, !reduceMotion else { return .fitted }
        let zoom = Self.spotlightZoom
        let center = CGPoint(x: container.width / 2, y: container.height / 2)
        let point = fit.geometry.vertexPosition(focus, board: board)
        return BoardCamera(zoom: zoom, pan: CGSize(width: (center.x - point.x) * zoom,
                                                   height: (center.y - point.y) * zoom))
            .clamped(fittedBounds: fit.bounds, container: container, maximumZoom: cameraMaximumZoom)
    }
}
