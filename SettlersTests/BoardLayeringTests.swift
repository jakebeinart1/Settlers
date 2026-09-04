import Testing
import SwiftUI
import UIKit
@testable import Settlers
@testable import CatanEngine

/// Guards one rule about how `BoardView` stacks its layers: **a placement
/// highlight may never repaint a piece.**
///
/// ## The defect this exists for
/// The vertex/edge tap targets used to be the last children of `BoardView`'s
/// `ZStack`, i.e. drawn on top of every settlement, city and road. During
/// setup that is not a corner case, it is the normal flow: the moment the human
/// places their first settlement the engine asks for a road, and the three
/// legal road edges radiating from that settlement each laid a
/// `Color.yellow.opacity(0.55)` capsule straight across the piece. Three of them
/// overlapping is ~0.91 effective alpha, so the settlement read as a solid
/// yellow blob until the road went down and the highlights cleared - which
/// looked exactly like the piece being drawn in the wrong player colour and then
/// changing colour a moment later. That is how it was reported.
///
/// ## How the test works
/// `BoardView` is rendered twice over the same `GameState` at the same size -
/// once with no placement mode, once with the placement mode armed and the
/// edges around the piece highlighted - and the two rasters are compared inside
/// the piece's own footprint. Rendering rather than inspecting the view tree is
/// deliberate: z-order is not readable from SwiftUI's declarative structure, and
/// the only thing that actually went wrong was which pixels won.
///
/// The comparison is restricted to a small square at the vertex's centre. The
/// piece art is `scaledToFit` inside a square frame, so its outer margins are
/// transparent and the highlight is *supposed* to show through there (a hint
/// peeking out from behind state is the intended look); the centre is solid
/// artwork, so any difference there means something was painted over the piece.
@MainActor
struct BoardLayeringTests {
    /// Side of the square patch compared at the piece's centre, in points.
    /// Small enough to stay well inside the settlement silhouette at the
    /// rendered board size, large enough that a stray overlay cannot slip
    /// between the sampled pixels.
    private static let patchSide = 9
    private static let canvasSide: CGFloat = 700

    @Test func placementHighlightsDoNotRepaintPieces() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        let vertex = try #require(Self.mostCentralVertex(of: state.board))
        state.players[0].settlements.insert(vertex)

        let plain = try Self.render(state: state, highlightedEdges: [], isPlacementModeActive: false)
        let armed = try Self.render(
            state: state,
            highlightedEdges: Set(state.board.edgesTouching(vertex)),
            isPlacementModeActive: true
        )

        let geometry = BoardView.fittedGeometry(
            for: state.board,
            in: CGRect(x: 0, y: 0, width: Self.canvasSide, height: Self.canvasSide),
            padding: 16
        )
        let centre = geometry.vertexPosition(vertex, board: state.board)

        let plainPatch = Self.patch(of: plain, centredOn: centre)
        let armedPatch = Self.patch(of: armed, centredOn: centre)
        let changed = zip(plainPatch, armedPatch).filter { $0 != $1 }.count
        // The means are reported rather than the raw bytes: the whole point of
        // the defect is which colour won, and 324 bytes of hex says that far
        // less clearly than "purple became tan".
        #expect(
            changed == 0,
            """
            A placement highlight repainted the settlement: \(changed) of \(plainPatch.count) \
            colour bytes changed when the placement mode was armed. \
            Piece centre was RGB \(Self.meanRGB(plainPatch)) unarmed, RGB \(Self.meanRGB(armedPatch)) armed.
            """
        )
    }

    @Test func piecesUseTheProvidedMatchIdentityInsteadOfGlobalSeatStyling() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        let vertex = try #require(Self.mostCentralVertex(of: state.board))
        state.players[0].settlements.insert(vertex)

        let britannia = try Self.render(
            state: state, highlightedEdges: [], isPlacementModeActive: false,
            civilization: .medieval
        )
        let rome = try Self.render(
            state: state, highlightedEdges: [], isPlacementModeActive: false,
            civilization: .rome
        )
        let geometry = BoardView.fittedGeometry(
            for: state.board,
            in: CGRect(x: 0, y: 0, width: Self.canvasSide, height: Self.canvasSide),
            padding: 16
        )
        let centre = geometry.vertexPosition(vertex, board: state.board)
        let changed = zip(
            Self.patch(of: britannia, centredOn: centre),
            Self.patch(of: rome, centredOn: centre)
        ).filter { $0 != $1 }.count

        #expect(changed > 0, "Board pieces ignored the match-authoritative identity resolver")
    }

    // MARK: - Helpers

    /// The on-board vertex nearest the board's geometric centre - a stable,
    /// board-layout-independent way to pick a vertex that is interior (so it
    /// has all three incident edges) and far from the rendered frame's edges.
    private static func mostCentralVertex(of board: Board) -> VertexID? {
        let geometry = HexGeometry(origin: .zero, size: 1)
        let centre = BoardView.boardCenter(for: board, geometry: geometry)
        return board.onBoardVertices.sorted().min { lhs, rhs in
            let a = geometry.vertexPosition(lhs, board: board)
            let b = geometry.vertexPosition(rhs, board: board)
            return hypot(a.x - centre.x, a.y - centre.y) < hypot(b.x - centre.x, b.y - centre.y)
        }
    }

    private static func render(
        state: GameState,
        highlightedEdges: Set<EdgeID>,
        isPlacementModeActive: Bool,
        civilization: Civilization = .medieval
    ) throws -> CGImage {
        let view = BoardView(
            state: state,
            playerIdentity: { seat in
                PlayerIdentity(
                    seat: seat, displayName: "Player \(seat.index + 1)",
                    civilization: seat.index == 0 ? civilization : .greece,
                    controller: seat.index == 0 ? .human : .computer
                )
            },
            onTapVertex: { _ in },
            onTapEdge: { _ in },
            onTapTile: { _ in },
            highlightedEdges: highlightedEdges,
            isPlacementModeActive: isPlacementModeActive
        )
        .frame(width: canvasSide, height: canvasSide)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return try #require(renderer.cgImage)
    }

    /// Average red/green/blue of a premultiplied-RGBA byte run, for a failure
    /// message a human can read at a glance.
    private static func meanRGB(_ rgba: [UInt8]) -> (Int, Int, Int) {
        let pixels = rgba.count / 4
        var totals = (0, 0, 0)
        for index in stride(from: 0, to: rgba.count, by: 4) {
            totals.0 += Int(rgba[index])
            totals.1 += Int(rgba[index + 1])
            totals.2 += Int(rgba[index + 2])
        }
        return (totals.0 / pixels, totals.1 / pixels, totals.2 / pixels)
    }

    /// The raw RGBA bytes of a `patchSide` x `patchSide` square centred on
    /// `point`, normalized into a fresh bitmap context so two rasters are
    /// always compared in the same pixel format and row alignment.
    private static func patch(of image: CGImage, centredOn point: CGPoint) -> [UInt8] {
        let side = patchSide
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            // Draw the whole image translated so the wanted patch lands on the
            // context's origin - simpler and less error-prone than cropping,
            // which has to reason about the CGImage's own row padding.
            context.draw(
                image,
                in: CGRect(
                    x: -(point.x - CGFloat(side) / 2),
                    y: -(CGFloat(image.height) - point.y - CGFloat(side) / 2),
                    width: CGFloat(image.width),
                    height: CGFloat(image.height)
                )
            )
        }
        return bytes
    }
}
