import SwiftUI
import CatanEngine

/// `BoardView`'s deliberate camera: the locked fit it rests at, and the pinch,
/// pan and recenter that move away from it.
///
/// Split out of `BoardView.swift` rather than kept beside the layers it draws
/// over: that file was the largest view in the app before the camera was
/// added to it, and this is a genuine seam - everything below is about WHERE
/// the board is drawn, and nothing below knows what is drawn on it.
///
/// The arithmetic itself is in `BoardCamera`, which has no SwiftUI in it and
/// is unit-tested directly. This file is only the wiring.
extension BoardView {
    /// A solved fit, plus enough of the layout that produced it to tell
    /// whether it still applies.
    /// Internal rather than private only because `BoardView.body`, in the
    /// other file, is what consumes it.
    struct LockedFit {
        let tiles: [HexCoordinate]
        let width: CGFloat
        /// The tallest container this board has been given at this width.
        /// See `lockedFit(for:in:)` for why the tallest and not the latest.
        let height: CGFloat
        let geometry: HexGeometry
        /// Everything drawn, in container points, at `geometry` - the extent
        /// the camera clamps against.
        let bounds: CGRect

        func describesSameBoard(as board: Board, width: CGFloat) -> Bool {
            self.width == width && tiles == board.tiles.map(\.coordinate)
        }
    }

    // MARK: - Camera

    /// Pinch to zoom, about the fingers rather than the board's center.
    func pinch(fit: LockedFit, container: CGSize, center: CGPoint) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let anchor = gestureAnchor ?? camera
                gestureAnchor = anchor
                camera = anchor
                    .zoomed(by: value.magnification, about: value.startLocation, containerCenter: center)
                    .clamped(fittedBounds: fit.bounds, container: container)
            }
            .onEnded { _ in gestureAnchor = nil }
    }

    /// Drag to pan, but only once there is something to pan to. At the fitted
    /// scale the clamp pins the pan to zero, so attaching this there would
    /// swallow drags to do nothing - and the board's own decision layers have
    /// drag interactions of their own that should keep every pixel they have.
    func drag(fit: LockedFit, container: CGSize) -> some Gesture {
        DragGesture(minimumDistance: Self.panSlop)
            .onChanged { value in
                guard camera.zoom > BoardCamera.minZoom else { return }
                let anchor = gestureAnchor ?? camera
                gestureAnchor = anchor
                camera = anchor
                    .panned(by: value.translation)
                    .clamped(fittedBounds: fit.bounds, container: container)
            }
            .onEnded { _ in gestureAnchor = nil }
    }

    /// Far enough that a drag is unambiguously a drag: a tap on a placement
    /// ring must still reach the target layer underneath.
    private static let panSlop: CGFloat = 12

    var recenterButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
                camera = .fitted
            }
        } label: {
            Image(systemName: "dot.scope")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(.black.opacity(0.45)))
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
        }
        .accessibilityLabel("Recenter board")
        .accessibilityIdentifier(AccessibilityID.Board.recenter)
    }

    // MARK: - The locked fit

    /// The fit to draw with this frame. Falls back to solving one when the
    /// lock does not yet apply, so the very first frame - drawn before
    /// `onAppear` has committed anything - is already correct.
    func applicableFit(for board: Board, in container: CGSize) -> LockedFit {
        if let lockedFit, lockedFit.describesSameBoard(as: board, width: container.width) {
            return lockedFit
        }
        return Self.solvedFit(for: board, in: container)
    }

    static func solvedFit(for board: Board, in container: CGSize) -> LockedFit {
        let geometry = fittedGeometry(for: board,
                                      in: CGRect(origin: .zero, size: container),
                                      padding: boardPadding)
        return LockedFit(
            tiles: board.tiles.map(\.coordinate),
            width: container.width,
            height: container.height,
            geometry: geometry,
            bounds: contentBounds(for: board, geometry: geometry))
    }

    /// Decides whether the board's fit may move.
    ///
    /// ## The bug this exists to kill
    /// `fittedGeometry` is a pure function of `(board, container, padding)`,
    /// and it was being called inline on every render - so the board silently
    /// re-zoomed and re-centered every time its *container* changed height.
    /// It changes constantly: `GameView.boardArea` is `maxHeight: .infinity`
    /// in a column, so the confirm/cancel decision panel, the incoming trade
    /// card and the inline banners all take height from the board as they
    /// come and go. Placing a settlement moved the board. So did a 7.
    ///
    /// ## Why the tallest container and not the latest
    /// Everything that steals height *takes* it - nothing makes the board's
    /// container taller than its unobstructed layout. So the tallest
    /// container seen at a given width **is** the unobstructed layout, which
    /// makes "lock to the tallest" a rule that converges on the right answer
    /// from any starting frame, with no timer and no settling heuristic, and
    /// never oscillates: the height it locks to is monotonic.
    ///
    /// That matters because the first frame is not trustworthy.
    /// `GameView.topChipInset` starts at a placeholder and is corrected once
    /// the chips report their real height, so a rule of "lock the first fit
    /// you see" would lock to a layout that existed for one frame.
    ///
    /// The consequence, and it is the intended one: while a panel is up, the
    /// board is drawn at its unobstructed size inside a shorter container and
    /// is cropped by `boardArea`'s clip. It stays exactly where it was rather
    /// than shrinking to fit - which is the whole point. Pinch or pan to
    /// reach anything the panel covers.
    ///
    /// Width is in the key because it is the one dimension nothing steals: it
    /// changes only on rotation or a genuinely different screen, where a fit
    /// solved for the old width would be wrong rather than merely stale.
    func updateLock(for board: Board, in container: CGSize) {
        guard container.width > 0, container.height > 0 else { return }

        if let lockedFit, lockedFit.describesSameBoard(as: board, width: container.width) {
            guard container.height > lockedFit.height else { return }
            let grown = Self.solvedFit(for: board, in: container)
            self.lockedFit = grown
            camera = camera.clamped(fittedBounds: grown.bounds, container: container)
            return
        }

        lockedFit = Self.solvedFit(for: board, in: container)
        camera = .fitted
    }
}
