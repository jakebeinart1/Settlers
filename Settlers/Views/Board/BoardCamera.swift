import CoreGraphics

/// The board's viewport: how far it is zoomed in past its fitted scale, and
/// how far it has been dragged from center.
///
/// ## Why this is a value type with no SwiftUI in it
/// Everything drawn on the board derives from a single `HexGeometry`
/// (`origin` + `size`), and every one of `HexGeometry`'s accessors is linear
/// in those two numbers. So a camera does not need its own transform applied
/// to each layer - it only needs to produce a *different* `HexGeometry`, and
/// tiles, ports, roads, buildings, placement rings and hit testing all follow
/// it exactly, with no chance of the drawn board and the tappable board
/// disagreeing. A `.scaleEffect` on the container would have done neither:
/// it rasterizes the `Canvas` at its unzoomed size (blurring as you zoom in)
/// and duplicates the transform on the hit-testing path.
///
/// Keeping it free of SwiftUI is also what lets `BoardCameraTests` assert the
/// clamping rules directly. The clamp is the whole safety property here - it
/// is what stops the board being flung off screen and what makes "zoomed all
/// the way out" and "the locked fit" the same view rather than two views that
/// merely look alike.
struct BoardCamera: Equatable {
    /// Zoomed out is exactly the fitted board and nothing wider. Floor and
    /// resting state are deliberately the same number: with any slack below
    /// the fit, "fully zoomed out" and "recentered" become two different
    /// resting places, and the board settles into whichever one the last
    /// gesture happened to leave - which reads as the drift this camera was
    /// built to remove.
    static let minZoom: CGFloat = 1

    /// Roughly one hex filling a phone's board area. Past this the tile art
    /// is being magnified well beyond its drawn detail and the board loses
    /// enough context to navigate by.
    static let maxZoom: CGFloat = 3

    /// Multiple of the fitted scale. `1` is fit-to-container.
    var zoom: CGFloat = 1

    /// Translation from the fitted position, in points, defined about the
    /// container's center (see `zoomed(by:about:containerCenter:)` for why
    /// every gesture is normalized to that one focal point).
    var pan: CGSize = .zero

    /// The resting camera: the fitted, locked board.
    static let fitted = BoardCamera()

    /// True when the camera is at rest, and so when a "recenter" control has
    /// nothing to do and should not be offered.
    var isFitted: Bool { self == .fitted }

    // MARK: - Applying

    /// The geometry to actually draw with: `base` (the locked fit) as seen
    /// through this camera.
    func applied(to base: HexGeometry, containerCenter center: CGPoint) -> HexGeometry {
        HexGeometry(
            origin: CGPoint(
                x: center.x + (base.origin.x - center.x) * zoom + pan.width,
                y: center.y + (base.origin.y - center.y) * zoom + pan.height),
            size: base.size * zoom)
    }

    /// Where a point in the fitted board lands on screen under this camera.
    /// The same similarity transform `applied(to:)` performs, which is why
    /// the two cannot drift apart.
    private func project(_ point: CGPoint, about center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + (point.x - center.x) * zoom + pan.width,
                y: center.y + (point.y - center.y) * zoom + pan.height)
    }

    /// The board's drawn extent on screen under this camera, given that
    /// extent at the fitted scale.
    func projectedBounds(ofFitted bounds: CGRect, containerCenter center: CGPoint) -> CGRect {
        let origin = project(bounds.origin, about: center)
        return CGRect(origin: origin, size: CGSize(width: bounds.width * zoom, height: bounds.height * zoom))
    }

    // MARK: - Gestures

    /// This camera after pinching by `factor` about `location`.
    ///
    /// Pinching about the fingers rather than the container's center is what
    /// makes zoom feel like it is grabbing the board instead of a slider. But
    /// storing a per-gesture focal point would make `pan` mean something
    /// different after every pinch, so the result is renormalized back to a
    /// center-focused camera. Composing the two transforms:
    ///
    ///     T'(p) = L + (T(p) - L) * k,  where T(p) = C + (p - C) * z + pan
    ///           = C + (p - C) * (z * k) + [pan * k + (L - C) * (1 - k)]
    ///
    /// which is a center-focused camera with `zoom = z * k` and the bracketed
    /// term as its `pan`. Exact, not an approximation - so a pinch, a drag
    /// and another pinch compose without accumulating error.
    func zoomed(by factor: CGFloat, about location: CGPoint, containerCenter center: CGPoint) -> BoardCamera {
        BoardCamera(
            zoom: zoom * factor,
            pan: CGSize(
                width: pan.width * factor + (location.x - center.x) * (1 - factor),
                height: pan.height * factor + (location.y - center.y) * (1 - factor)))
    }

    /// This camera after dragging by `translation`.
    func panned(by translation: CGSize) -> BoardCamera {
        BoardCamera(zoom: zoom, pan: CGSize(width: pan.width + translation.width,
                                            height: pan.height + translation.height))
    }

    // MARK: - Clamping

    /// This camera with its zoom held between `minZoom` and `maxZoom`, and
    /// its pan held so the board cannot be dragged away from the container.
    ///
    /// `fittedBounds` is everything drawn, at the fitted scale, in container
    /// coordinates - the same extent `BoardView.contentBounds` measures, so
    /// the port badges and placement rings that the fit reserves space for
    /// are inside the clamp too.
    ///
    /// The pan limit is the usual one for a zooming viewport: the board may
    /// slide by however much of it does not fit on screen, and no further. On
    /// an axis where the whole board still fits, the slack is zero and the
    /// board is pinned to its fitted position on that axis. At `zoom == 1`
    /// the slack is zero on both axes, so **the clamp alone re-establishes
    /// the locked fit** - zoomed out, there is exactly one legal camera.
    func clamped(fittedBounds: CGRect, container: CGSize) -> BoardCamera {
        let center = CGPoint(x: container.width / 2, y: container.height / 2)
        let held = BoardCamera(zoom: min(max(zoom, Self.minZoom), Self.maxZoom), pan: pan)

        // Where the board would sit with no pan at all: the position the pan
        // is measured as a departure from.
        let unpanned = BoardCamera(zoom: held.zoom, pan: .zero)
            .projectedBounds(ofFitted: fittedBounds, containerCenter: center)

        func clamp(_ value: CGFloat, boardMid: CGFloat, boardExtent: CGFloat,
                   containerMid: CGFloat, containerExtent: CGFloat) -> CGFloat {
            let slack = max(0, (boardExtent - containerExtent) / 2)
            let centered = containerMid - boardMid
            return min(max(value, centered - slack), centered + slack)
        }

        return BoardCamera(
            zoom: held.zoom,
            pan: CGSize(
                width: clamp(held.pan.width, boardMid: unpanned.midX, boardExtent: unpanned.width,
                             containerMid: center.x, containerExtent: container.width),
                height: clamp(held.pan.height, boardMid: unpanned.midY, boardExtent: unpanned.height,
                              containerMid: center.y, containerExtent: container.height)))
    }
}
