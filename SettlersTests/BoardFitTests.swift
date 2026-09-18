import Testing
import CoreGraphics
import CatanEngine
@testable import Settlers

/// Proves the board fits inside the space it is given - everything drawn, not
/// just the hexes.
///
/// ## Why this is a test and not an eyeball
/// The board's scale has been tuned by screenshot three times, and each time
/// something drawn *outside* the tiles was clipped: port badges sit offshore,
/// past the shoreline, and vertex placement rings stick out past the outermost
/// corners. `fittedGeometry` measured neither, so the fix each time was to pad
/// the board by a guessed amount - which is right on one screen by luck and
/// wrong on the next.
///
/// These assertions are the thing that guess was standing in for. They run
/// across a spread of frame sizes, so a change that fits an iPhone 17 Pro and
/// clips an iPad fails here rather than in a screenshot nobody took.

/// Every frame the board realistically gets handed, including deliberately
/// awkward ones.
private let candidateRects: [CGRect] = [
    CGRect(x: 0, y: 0, width: 402, height: 300),   // iPhone 17 Pro, roughly
    CGRect(x: 0, y: 0, width: 393, height: 280),   // a shorter phone
    CGRect(x: 0, y: 0, width: 440, height: 360),   // a larger phone
    CGRect(x: 0, y: 0, width: 834, height: 700),   // iPad
    CGRect(x: 0, y: 0, width: 320, height: 200),   // cramped: wider than tall
    CGRect(x: 0, y: 0, width: 250, height: 600),   // cramped: taller than wide
]

private let boards: [(String, Board)] = [
    ("standard", BoardGenerator.standard()),
    ("randomized-1", BoardGenerator.randomized(seed: 1)),
    ("randomized-2", BoardGenerator.randomized(seed: 2)),
    ("expanded", BoardGenerator.randomized(seed: 1, shape: .expanded)),
    ("vast", BoardGenerator.randomized(seed: 1, shape: .vast)),
]

/// Vast's two lower-right ports collide even though both fit the viewport.
/// Clearance is in board units so zooming cannot turn a pass into an overlap.
@MainActor
@Test func portBadgesHaveClearanceOnEveryBoard() {
    for shape in [BoardShape.classic, .expanded, .vast] {
        let board = BoardGenerator.randomized(seed: 1, shape: shape)
        let geometry = BoardView.fittedGeometry(
            for: board, in: CGRect(x: 0, y: 0, width: 402, height: 382.67), padding: BoardView.boardPadding)
        let center = BoardView.boardCenter(for: board, geometry: geometry)
        let points = TileDrawing.portIconPoints(board: board, geometry: geometry, boardCenter: center)
        let required = geometry.size * (2 * TileDrawing.portFrameRadiusFactor + TileDrawing.portBadgeGapFactor)
        for first in points.indices {
            for second in points.indices where second > first {
                let distance = hypot(points[first].x - points[second].x, points[first].y - points[second].y)
                #expect(distance >= required - 0.001,
                        "radius \(shape.radius), ports \(first)/\(second): \(distance)pt apart, need \(required)pt")
            }
        }
    }
}

@MainActor
@Test func everythingDrawnStaysInsideTheFrame() {
    for (boardName, board) in boards {
        for rect in candidateRects {
            let geometry = BoardView.fittedGeometry(for: board, in: rect, padding: BoardView.boardPadding)
            let center = BoardView.boardCenter(for: board, geometry: geometry)

            // Port badges - the outermost thing on the board, and what every
            // previous clipping report was actually about.
            let badge = geometry.size * TileDrawing.portFrameRadiusFactor
            for icon in TileDrawing.portIconPoints(board: board, geometry: geometry, boardCenter: center) {
                let box = CGRect(x: icon.x - badge, y: icon.y - badge, width: badge * 2, height: badge * 2)
                #expect(rect.contains(box),
                        "\(boardName) at \(Int(rect.width))x\(Int(rect.height)): a port badge is clipped (\(box) outside \(rect))")
            }

            // Vertex placement rings, which are a fixed point size and so do
            // not shrink with the board.
            let ring = TileDrawing.vertexRingRadius
            for vertex in board.onBoardVertices {
                let point = geometry.vertexPosition(vertex, board: board)
                let box = CGRect(x: point.x - ring, y: point.y - ring, width: ring * 2, height: ring * 2)
                #expect(rect.contains(box),
                        "\(boardName) at \(Int(rect.width))x\(Int(rect.height)): a placement ring is clipped")
            }
        }
    }
}

/// Resolving the crowded pair must not buy clearance by shrinking the board
/// or moving unrelated ports. It must also commute with camera scale/pan.
@MainActor
@Test func portClearancePreservesBoardExtentAndCameraScaling() {
    let unit = HexGeometry(origin: .zero, size: 1)
    let zoomed = HexGeometry(origin: CGPoint(x: 37, y: 51), size: 43)
    for (_, board) in boards {
        let center = BoardView.boardCenter(for: board, geometry: unit)
        let original = board.ports.map { port in
            TileDrawing.portIconPoint(a: unit.vertexPosition(port.vertexA, board: board),
                                      b: unit.vertexPosition(port.vertexB, board: board),
                                      boardCenter: center, size: 1)
        }
        let resolved = TileDrawing.portIconPoints(board: board, geometry: unit, boardCenter: center)
        let projected = TileDrawing.portIconPoints(
            board: board, geometry: zoomed, boardCenter: BoardView.boardCenter(for: board, geometry: zoomed))
        let bounds = CGRect(x: original.map(\.x).min()!, y: original.map(\.y).min()!,
                            width: original.map(\.x).max()! - original.map(\.x).min()!,
                            height: original.map(\.y).max()! - original.map(\.y).min()!)
        for index in resolved.indices {
            #expect(bounds.insetBy(dx: -0.001, dy: -0.001).contains(resolved[index]), "clearance expanded the board bounds")
            #expect(abs(projected[index].x - (resolved[index].x * zoomed.size + zoomed.origin.x)) < 0.001)
            #expect(abs(projected[index].y - (resolved[index].y * zoomed.size + zoomed.origin.y)) < 0.001)
        }
        let moved = original.indices.filter { hypot(original[$0].x - resolved[$0].x, original[$0].y - resolved[$0].y) > 0.001 }
        #expect(moved.count == (board.tiles.count == 61 ? 2 : 0), "unrelated ports moved")
    }
}

@MainActor
@Test func portBadgesDoNotCollideWithPlacementRings() {
    // The overlap that started this: during setup every vertex is ringed at
    // once, and a badge sitting on one is unreadable. `portOffset` is sized
    // against exactly this, so it needs a test rather than a comment.
    for (boardName, board) in boards {
        let rect = CGRect(x: 0, y: 0, width: 402, height: 300)
        let geometry = BoardView.fittedGeometry(for: board, in: rect, padding: BoardView.boardPadding)
        let center = BoardView.boardCenter(for: board, geometry: geometry)
        let badge = geometry.size * TileDrawing.portFrameRadiusFactor
        let ring = VertexTapTarget.highlightDiameter(spacing: geometry.size) / 2

        for icon in TileDrawing.portIconPoints(board: board, geometry: geometry, boardCenter: center) {
            for vertex in board.onBoardVertices {
                let point = geometry.vertexPosition(vertex, board: board)
                let separation = hypot(icon.x - point.x, icon.y - point.y)
                let overlap = Int((badge + ring) - separation)
                let detail = "\(boardName): a port badge overlaps a placement ring by \(overlap)pt"
                #expect(separation >= badge + ring, "\(detail)")
            }
        }
    }
}

/// The frame's aspect ratio is what decides how much of it the board can use,
/// and that is not obvious from either the fit or the frame alone.
///
/// Everything the board draws measures about 1.035 wide for every 1 tall. A
/// frame that is relatively wider than that binds the fit on height and leaves
/// the difference as water down both sides - and no amount of zooming can
/// spend it, because zooming to fill the width pushes the top and bottom port
/// badges out of the frame, which is what `everythingDrawnStaysInsideTheFrame`
/// above refuses.
///
/// So the frame's shape is the lever. The in-game board frame used to measure
/// 402x362 (1.111) and left 27.8pt of side water beyond the fit's own margin;
/// giving it the home-indicator band that the layout had never claimed made it
/// 402x382.67 (1.051), and that falls to 7.7. This pins the relationship: if a
/// future change takes height back out of the board's frame, the board does
/// not merely get smaller, it stops filling its width, and this says so.
@MainActor
@Test func theShippedInGameFrameIsFilledOnBothAxes() {
    // Measured on an iPhone 17 Pro at Dynamic Type `.large`, with
    // `GameView.homeIndicatorClearance` left below the action row.
    let rect = CGRect(x: 0, y: 0, width: 402, height: 382.67)
    let board = BoardGenerator.standard()
    let geometry = BoardView.fittedGeometry(for: board, in: rect, padding: BoardView.boardPadding)
    let bounds = BoardView.contentBounds(for: board, geometry: geometry)

    // Slack beyond the cosmetic margin the fit reserves on every side. The
    // binding axis has none by definition; the loose one had 27.8pt of it at
    // the old 402x362 frame and has 7.7 here.
    let spareHeight = rect.height - bounds.height - BoardView.boardPadding * 2
    let spareWidth = rect.width - bounds.width - BoardView.boardPadding * 2
    #expect(spareHeight < 0.001,
            "height should still be the binding axis; it is leaving \(Int(spareHeight))pt")
    #expect(spareWidth < 10,
            "the board is leaving \(Int(spareWidth))pt of water down its sides - the frame is relatively wider than the board again")
}

@MainActor
@Test func theBoardUsesTheSpaceItIsGiven() {
    // The other direction, and the reason this file exists at all: guarding
    // only against clipping invites fixing a clip by shrinking the board, and
    // the board was reported as too small twice. Something drawn must come
    // reasonably close to the frame on the binding axis.
    let rect = CGRect(x: 0, y: 0, width: 402, height: 300)
    let board = BoardGenerator.standard()
    let geometry = BoardView.fittedGeometry(for: board, in: rect, padding: BoardView.boardPadding)
    let center = BoardView.boardCenter(for: board, geometry: geometry)
    let badge = geometry.size * TileDrawing.portFrameRadiusFactor

    var minEdgeGap = CGFloat.greatestFiniteMagnitude
    for icon in TileDrawing.portIconPoints(board: board, geometry: geometry, boardCenter: center) {
        minEdgeGap = min(minEdgeGap,
                         icon.y - badge - rect.minY, rect.maxY - (icon.y + badge),
                         icon.x - badge - rect.minX, rect.maxX - (icon.x + badge))
    }
    #expect(minEdgeGap < 24, "the board is leaving \(Int(minEdgeGap))pt unused on its tightest side")
    #expect(minEdgeGap >= 0, "the board is clipped")
}
