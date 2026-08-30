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
]

@MainActor
@Test func everythingDrawnStaysInsideTheFrame() {
    for (boardName, board) in boards {
        for rect in candidateRects {
            let geometry = BoardView.fittedGeometry(for: board, in: rect, padding: 4)
            let center = BoardView.boardCenter(for: board, geometry: geometry)

            // Port badges - the outermost thing on the board, and what every
            // previous clipping report was actually about.
            let badge = geometry.size * TileDrawing.portFrameRadiusFactor
            for port in board.ports {
                let icon = TileDrawing.portIconPoint(
                    a: geometry.vertexPosition(port.vertexA, board: board),
                    b: geometry.vertexPosition(port.vertexB, board: board),
                    boardCenter: center, size: geometry.size)
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

@MainActor
@Test func portBadgesDoNotCollideWithPlacementRings() {
    // The overlap that started this: during setup every vertex is ringed at
    // once, and a badge sitting on one is unreadable. `portOffset` is sized
    // against exactly this, so it needs a test rather than a comment.
    for (boardName, board) in boards {
        let rect = CGRect(x: 0, y: 0, width: 402, height: 300)
        let geometry = BoardView.fittedGeometry(for: board, in: rect, padding: 4)
        let center = BoardView.boardCenter(for: board, geometry: geometry)
        let badge = geometry.size * TileDrawing.portFrameRadiusFactor
        let ring = TileDrawing.vertexRingRadius

        for port in board.ports {
            let icon = TileDrawing.portIconPoint(
                a: geometry.vertexPosition(port.vertexA, board: board),
                b: geometry.vertexPosition(port.vertexB, board: board),
                boardCenter: center, size: geometry.size)
            for vertex in board.onBoardVertices {
                let point = geometry.vertexPosition(vertex, board: board)
                let separation = hypot(icon.x - point.x, icon.y - point.y)
                let overlap = Int((badge + ring) - separation)
                let detail = "\(boardName): a \(port.kind) badge overlaps a placement ring by \(overlap)pt"
                #expect(separation >= badge + ring, "\(detail)")
            }
        }
    }
}

@MainActor
@Test func theBoardUsesTheSpaceItIsGiven() {
    // The other direction, and the reason this file exists at all: guarding
    // only against clipping invites fixing a clip by shrinking the board, and
    // the board was reported as too small twice. Something drawn must come
    // reasonably close to the frame on the binding axis.
    let rect = CGRect(x: 0, y: 0, width: 402, height: 300)
    let board = BoardGenerator.standard()
    let geometry = BoardView.fittedGeometry(for: board, in: rect, padding: 4)
    let center = BoardView.boardCenter(for: board, geometry: geometry)
    let badge = geometry.size * TileDrawing.portFrameRadiusFactor

    var minEdgeGap = CGFloat.greatestFiniteMagnitude
    for port in board.ports {
        let icon = TileDrawing.portIconPoint(
            a: geometry.vertexPosition(port.vertexA, board: board),
            b: geometry.vertexPosition(port.vertexB, board: board),
            boardCenter: center, size: geometry.size)
        minEdgeGap = min(minEdgeGap,
                         icon.y - badge - rect.minY, rect.maxY - (icon.y + badge),
                         icon.x - badge - rect.minX, rect.maxX - (icon.x + badge))
    }
    #expect(minEdgeGap < 24, "the board is leaving \(Int(minEdgeGap))pt unused on its tightest side")
    #expect(minEdgeGap >= 0, "the board is clipped")
}
