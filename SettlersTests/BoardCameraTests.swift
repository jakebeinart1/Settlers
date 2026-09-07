import Testing
import CoreGraphics
import CatanEngine
@testable import Settlers

/// The board camera's clamping and composition rules.
///
/// ## Why this is a test and not an eyeball
/// The reported bug was the board moving on its own - re-zooming and shifting
/// during placement and robber moves - so the fix is worth nothing if the
/// deliberate camera can leave the board somewhere the fitted board never
/// was. Two properties carry that, and neither is visible in a screenshot:
///
/// 1. Zoomed all the way out, there is exactly ONE legal camera, and it is
///    the fitted board. Not "a camera that looks fitted" - the same numbers.
/// 2. However you compose pinches and drags, the board still covers the
///    container. Nothing can drag it off screen and strand it there.
///
/// Both are properties of `BoardCamera`'s arithmetic, which is why that type
/// has no SwiftUI in it.

private let board = BoardGenerator.standard()

/// The frames the board realistically gets, matching `BoardFitTests`.
private let containers: [CGSize] = [
    CGSize(width: 402, height: 300),   // iPhone 17 Pro, roughly
    CGSize(width: 393, height: 280),   // a shorter phone
    CGSize(width: 834, height: 700),   // iPad
    CGSize(width: 320, height: 200),   // cramped: wider than tall
]

@MainActor
private func fitted(_ container: CGSize) -> (geometry: HexGeometry, bounds: CGRect) {
    let geometry = BoardView.fittedGeometry(
        for: board, in: CGRect(origin: .zero, size: container), padding: BoardView.boardPadding)
    return (geometry, BoardView.contentBounds(for: board, geometry: geometry))
}

@MainActor
@Test func zoomedOutThereIsExactlyOneLegalCamera() {
    // The floor and the resting state are the same view, so "recenter" and
    // "zoom all the way out" cannot disagree about where the board lives.
    for container in containers {
        let (_, bounds) = fitted(container)
        // Try to shove it around at (and below) the floor from every side.
        for pan in [CGSize(width: 400, height: 0), CGSize(width: -400, height: 0),
                    CGSize(width: 0, height: 400), CGSize(width: 0, height: -400)] {
            for zoom in [1.0 as CGFloat, 0.4, 0.01] {
                let clamped = BoardCamera(zoom: zoom, pan: pan)
                    .clamped(fittedBounds: bounds, container: container)
                #expect(clamped == .fitted,
                        "at \(Int(container.width))x\(Int(container.height)) zoom \(zoom) pan \(pan): settled at \(clamped), not the fitted camera")
            }
        }
    }
}

@MainActor
@Test func theFittedCameraDrawsExactlyTheFittedGeometry() {
    // `applied(to:)` at rest must be the identity, or the lock is a lock on
    // something subtly other than the fit every other test asserts about.
    for container in containers {
        let (geometry, _) = fitted(container)
        let center = CGPoint(x: container.width / 2, y: container.height / 2)
        let camera = BoardCamera.fitted.applied(to: geometry, containerCenter: center)
        #expect(camera.size == geometry.size)
        #expect(camera.origin == geometry.origin)
    }
}

@MainActor
@Test func theBoardCannotBeDraggedOffScreen() {
    for container in containers {
        let (_, bounds) = fitted(container)
        for zoom in [1.2 as CGFloat, 2, BoardCamera.maxZoom] {
            for pan in [CGSize(width: 5_000, height: 5_000), CGSize(width: -5_000, height: -5_000),
                        CGSize(width: 5_000, height: -5_000), CGSize(width: -900, height: 300)] {
                let camera = BoardCamera(zoom: zoom, pan: pan)
                    .clamped(fittedBounds: bounds, container: container)
                let center = CGPoint(x: container.width / 2, y: container.height / 2)
                let shown = camera.projectedBounds(ofFitted: bounds, containerCenter: center)
                let frame = CGRect(origin: .zero, size: container)

                // Zoomed in, the board is larger than the container on the
                // binding axis, so it must cover it edge to edge. There is
                // never a strip of empty water at the edge of the screen.
                if shown.width >= frame.width {
                    #expect(shown.minX <= frame.minX + 0.01 && shown.maxX >= frame.maxX - 0.01,
                            "zoom \(zoom) pan \(pan): board \(shown) leaves a horizontal gap in \(frame)")
                }
                if shown.height >= frame.height {
                    #expect(shown.minY <= frame.minY + 0.01 && shown.maxY >= frame.maxY - 0.01,
                            "zoom \(zoom) pan \(pan): board \(shown) leaves a vertical gap in \(frame)")
                }
            }
        }
    }
}

@MainActor
@Test func zoomIsHeldBetweenItsFloorAndCeiling() {
    let container = CGSize(width: 402, height: 300)
    let (_, bounds) = fitted(container)
    for requested in [0.1 as CGFloat, 0.99, 1, 2, 9, 1_000] {
        let zoom = BoardCamera(zoom: requested, pan: .zero)
            .clamped(fittedBounds: bounds, container: container).zoom
        #expect(zoom >= BoardCamera.minZoom && zoom <= BoardCamera.maxZoom,
                "requested \(requested), settled at \(zoom)")
    }
}

@MainActor
@Test func pinchingHoldsThePointUnderTheFingers() {
    // The property that makes zoom feel like it grabs the board: whatever is
    // under the pinch stays under it. This is also what proves the
    // renormalization to a center-focused camera in `zoomed(by:about:)` is
    // exact rather than approximately right - an error here would show up as
    // the board creeping away under repeated pinches.
    let container = CGSize(width: 402, height: 300)
    let center = CGPoint(x: container.width / 2, y: container.height / 2)
    let (geometry, _) = fitted(container)
    let focus = CGPoint(x: 120, y: 90)

    // A point on the fitted board, tracked through the zoom.
    let probe = geometry.center(of: board.tiles[3].coordinate)
    let before = BoardCamera.fitted.applied(to: geometry, containerCenter: center)
    let after = BoardCamera.fitted
        .zoomed(by: 2.5, about: focus, containerCenter: center)
        .applied(to: geometry, containerCenter: center)

    // Where the probe was drawn before and after, relative to the focus.
    let wasAt = before.center(of: board.tiles[3].coordinate)
    let nowAt = after.center(of: board.tiles[3].coordinate)
    #expect(abs((nowAt.x - focus.x) - (wasAt.x - focus.x) * 2.5) < 0.001)
    #expect(abs((nowAt.y - focus.y) - (wasAt.y - focus.y) * 2.5) < 0.001)
    #expect(probe == wasAt)
}

@MainActor
@Test func gesturesComposeWithoutDrift() {
    // Pinch in, pan, pinch back out: the clamp must return the board to the
    // fitted camera exactly, not to a camera near it. If this drifts, the
    // board ends every session slightly off-center - the original complaint,
    // reintroduced through the fix.
    let container = CGSize(width: 402, height: 300)
    let center = CGPoint(x: container.width / 2, y: container.height / 2)
    let (_, bounds) = fitted(container)

    var camera = BoardCamera.fitted
    camera = camera.zoomed(by: 2.4, about: CGPoint(x: 90, y: 60), containerCenter: center)
        .clamped(fittedBounds: bounds, container: container)
    camera = camera.panned(by: CGSize(width: -40, height: 25))
        .clamped(fittedBounds: bounds, container: container)
    camera = camera.zoomed(by: 0.05, about: CGPoint(x: 300, y: 220), containerCenter: center)
        .clamped(fittedBounds: bounds, container: container)

    #expect(camera == .fitted, "zooming back out settled at \(camera)")
}

@MainActor
@Test func contentBoundsCoverEverythingTheFitReserved() {
    // The clamp is only as good as the extent it clamps against. If
    // `contentBounds` measured less than `fittedGeometry` reserved, the
    // camera would happily park a port badge outside the container.
    for container in containers {
        let (geometry, bounds) = fitted(container)
        let center = BoardView.boardCenter(for: board, geometry: geometry)
        let badge = geometry.size * TileDrawing.portFrameRadiusFactor

        for port in board.ports {
            let icon = TileDrawing.portIconPoint(
                a: geometry.vertexPosition(port.vertexA, board: board),
                b: geometry.vertexPosition(port.vertexB, board: board),
                boardCenter: center, size: geometry.size)
            let box = CGRect(x: icon.x - badge, y: icon.y - badge, width: badge * 2, height: badge * 2)
            #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(box),
                    "a port badge \(box) is outside the measured content bounds \(bounds)")
        }

        let ring = TileDrawing.vertexRingRadius
        for vertex in board.onBoardVertices {
            let point = geometry.vertexPosition(vertex, board: board)
            let box = CGRect(x: point.x - ring, y: point.y - ring, width: ring * 2, height: ring * 2)
            #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(box),
                    "a placement ring \(box) is outside the measured content bounds \(bounds)")
        }
    }
}

@MainActor
@Test func refactoringTheFitLeftItWhereItWas() {
    // `fittedGeometry` was restructured to share its measurement with the
    // camera. It is a pure function, so the guard is cheap and exact: the
    // same inputs must still produce the same board. `BoardFitTests` proves
    // the fit is *correct*; this proves the extraction did not move it.
    for container in containers {
        let (geometry, bounds) = fitted(container)
        // The fit centers the measured content in the container.
        #expect(abs(bounds.midX - container.width / 2) < 0.001,
                "the board is not horizontally centered at \(Int(container.width))x\(Int(container.height))")
        #expect(abs(bounds.midY - container.height / 2) < 0.001,
                "the board is not vertically centered at \(Int(container.width))x\(Int(container.height))")
        // ...and fills it on the binding axis, less the cosmetic padding.
        let slackX = container.width - bounds.width
        let slackY = container.height - bounds.height
        #expect(min(slackX, slackY) <= BoardView.boardPadding * 2 + 0.001,
                "the board is leaving \(Int(min(slackX, slackY)))pt on its tightest axis")
        #expect(geometry.size > 0)
    }
}
