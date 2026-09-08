import SwiftUI
import CatanEngine

/// `BoardView`'s deliberate camera: the fit it rests at, and the pinch, pan
/// and recenter that move away from it.
///
/// Split out of `BoardView.swift` rather than kept beside the layers it draws
/// over: that file was the largest view in the app before the camera was
/// added to it, and this is a genuine seam - everything below is about WHERE
/// the board is drawn, and nothing below knows what is drawn on it.
///
/// The arithmetic itself is in `BoardCamera`, which has no SwiftUI in it and
/// is unit-tested directly. This file is only the wiring.
extension BoardView {
    /// A solved fit: the geometry the board rests at, and the extent it draws
    /// into at that geometry.
    ///
    /// Internal rather than private only because `BoardView.body`, in the
    /// other file, is what consumes it.
    struct BoardFit {
        let geometry: HexGeometry
        /// Everything drawn, in container points, at `geometry` - the extent
        /// the camera clamps against.
        let bounds: CGRect
    }

    // MARK: - Camera

    /// Pinch to zoom, about the fingers rather than the board's center.
    func pinch(fit: BoardFit, container: CGSize, center: CGPoint) -> some Gesture {
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
    func drag(fit: BoardFit, container: CGSize) -> some Gesture {
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

    // MARK: - The fit

    /// The fit to draw with this frame.
    ///
    /// ## This is a pure function on purpose, and that is the whole fix
    /// It used to be `@State`, remembered across frames and re-solved only
    /// when the container grew - "lock the fit to the tallest container this
    /// board has been given". That rule was introduced to stop the board
    /// re-zooming every time a sibling panel appeared, and it did stop that,
    /// but it replaced a frame-dependent board size with a **history**-
    /// dependent one, which is worse and much harder to see:
    ///
    /// - `GameView`'s below-board chrome used to be a flexible row, so the
    ///   board's container measured 362.67, 382.67 or 503.67 points on the
    ///   same device in the same game depending on which panels were up.
    /// - Locking to the tallest meant a game that rolled a seven (the 503.67
    ///   discard layout) kept a board 39% too big for every later screen,
    ///   drawn ~70pt below its container and clipped at the bottom - which is
    ///   what cut the outer port badges off - while a game that never rolled
    ///   one kept a correct board. Two identical games, two board sizes.
    /// - And the growth was visible: the board jumped the instant the first
    ///   seven landed.
    ///
    /// **No rule that observes the container can fix that.** Tallest-seen is
    /// history-dependent, shortest-seen shrinks the board mid-game the first
    /// time a tall panel appears, and first-seen locks to the untrustworthy
    /// first frame. The container has to stop varying instead, which is what
    /// `GameView.belowBoardReserve` now guarantees: the board's container is
    /// a fixed height in every phase.
    ///
    /// With the container constant, a pure function of `(board, container)`
    /// is constant too - and, unlike a lock, it cannot quietly absorb a
    /// future regression. If something ever makes the container vary again
    /// the board will visibly move, which is a bug you can see, rather than
    /// silently becoming history-dependent, which is a bug you cannot.
    ///
    /// **Do not reintroduce a stored fit here.** If the board moves, the
    /// container moved; fix the layout that moved it.
    /// `BoardViewportInvarianceTests` fails when it does.
    func applicableFit(for board: Board, in container: CGSize) -> BoardFit {
        Self.solvedFit(for: board, in: container)
    }

    static func solvedFit(for board: Board, in container: CGSize) -> BoardFit {
        let geometry = fittedGeometry(for: board,
                                      in: CGRect(origin: .zero, size: container),
                                      padding: boardPadding)
        return BoardFit(geometry: geometry,
                         bounds: contentBounds(for: board, geometry: geometry))
    }
}
