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
    private static let glideFrames = 24
    private static let glideFrameDuration = Duration.milliseconds(16)

    func spotlighting(_ spotlight: BoardSpotlight?) -> Self {
        var lit = self
        lit.spotlight = spotlight
        return lit
    }

    /// Drawn below the buildings, so a lit network rims the road under the
    /// settlements rather than smearing over them.
    func spotlightRoads(_ spotlight: BoardSpotlight, geometry: HexGeometry) -> some View {
        roadNetworkPath(for: spotlight.edges, geometry: geometry)
            .stroke(CatanTheme.cityPennantGold, style: roadStroke(width: geometry.size * 0.26))
            .shadow(color: CatanTheme.cityPennantGold, radius: 8)
            .allowsHitTesting(false)
    }

    func spotlightLayer(_ spotlight: BoardSpotlight, geometry: HexGeometry) -> some View {
        let gold = CatanTheme.cityPennantGold
        return ZStack {
            ForEach(spotlight.vertices.sorted(), id: \.self) { vertex in
                Circle()
                    .stroke(gold, lineWidth: geometry.size * 0.09)
                    .shadow(color: gold, radius: 10)
                    .frame(width: geometry.size * 1.15, height: geometry.size * 1.15)
                    .position(geometry.vertexPosition(vertex, board: board))
            }
            if let focus = spotlight.focus, let label = spotlight.label {
                let piece = geometry.vertexPosition(focus, board: board)
                Text(label)
                    .font(.system(size: max(22, geometry.size * 0.7), weight: .black, design: .serif))
                    .foregroundStyle(gold)
                    .padding(.horizontal, 10)
                    .background(Capsule().fill(.black.opacity(0.75)))
                    .overlay(Capsule().stroke(gold, lineWidth: 2))
                    .position(x: piece.x, y: piece.y - geometry.size * 1.1)
                    .id(focus)
                    .transition(.opacity.combined(with: .offset(y: 12)))
            }
        }
        .allowsHitTesting(false)
    }

    /// Steps the camera rather than animating it. The tile `Canvas` projects
    /// a new camera at once while SwiftUI pieces interpolate, so an animated
    /// camera tears the pieces off their hexes mid-move - the same reason
    /// naval focus disables camera animation in `body`.
    func glideCamera(to focus: VertexID?, fit: BoardFit, container: CGSize) async {
        guard !reduceMotion else { return }
        let target = spotlightCamera(on: focus, fit: fit, container: container)
        let start = camera
        for frame in 1...Self.glideFrames {
            let progress = Double(frame) / Double(Self.glideFrames)
            let eased = CGFloat(progress * progress * (3 - 2 * progress))
            camera = BoardCamera(
                zoom: start.zoom + (target.zoom - start.zoom) * eased,
                pan: CGSize(width: start.pan.width + (target.pan.width - start.pan.width) * eased,
                            height: start.pan.height + (target.pan.height - start.pan.height) * eased))
            do { try await Task.sleep(for: Self.glideFrameDuration) } catch { return }
        }
    }

    private func spotlightCamera(on focus: VertexID?, fit: BoardFit, container: CGSize) -> BoardCamera {
        guard let focus else { return .fitted }
        let zoom = Self.spotlightZoom
        let center = CGPoint(x: container.width / 2, y: container.height / 2)
        let point = fit.geometry.vertexPosition(focus, board: board)
        return BoardCamera(zoom: zoom, pan: CGSize(width: (center.x - point.x) * zoom,
                                                   height: (center.y - point.y) * zoom))
            .clamped(fittedBounds: fit.bounds, container: container, maximumZoom: cameraMaximumZoom)
    }
}
