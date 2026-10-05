# On-board robber drag — integration contract

Base: `38f7885` (shipped Build 16). Worktree: `human-review-robber`.

## Source-backed cause

- `BoardDecisionInteractionLayer.swift`, `BoardDecisionCradleLayer.cradleDragGesture`,
  attaches the only piece drag to the bottom-right cradle. Its release resolves a
  legal target and calls `onSelectTarget`; it does not apply a move.
- `BoardView.swift`, `robberMarkerSemantics` / `boardMarker`, places the origin
  at `geometry.center(of: board.robberTile)` but explicitly disables hit testing.
  `drawCanonicalRobber` draws a hollow origin marker during robber decisions.
  Neither the Canvas nor that marker has a robber drag handler.
- `BoardView.body` simultaneously installs `BoardViewCamera.drag`. At zoom > 1
  that handler pans without checking the gesture's starting point. Adding an
  independent origin drag alone would therefore also pan the board.
- No `BoardGestureRouter` exists at this base. `GameView.boardArea` supplies the
  local-human coordinator presentation and the existing command-blocking flag.
  `GameViewModel+BoardDecision.selectBoardTarget` stages only; its separate
  `confirmBoardDecision` applies the move. `BoardDecisionCoordinator.selectRobber`
  already permits retargeting and clears the old victim on a new destination.

This is a source reproduction; no runtime reproduction was attempted without
main's serialized slot. No rules, saves, AI, or confirmation changes are needed.

## Design fixed before implementation

Capture the drag origin once in a pure `BoardGestureRouter`: existing cradle,
current canonical robber, or camera. Cradle detection comes first because it is
drawn above the board. A robber origin is active only with enabled commands, a
robber presentation, and the presentation actor owning the matching phase
(movingRobber for seven; rollDice/mainTurn for an armed Knight).

Use the camera-applied `HexGeometry`, including pan and zoom, for the origin
disc and legal-tile drop centers. The disc gets a minimum 44-point hit diameter
and scales with its drawn rim. Keep the existing 12-point board drag threshold
so ordinary tile taps keep their current recognizer tolerance. Keep the cradle's
existing three-point drag and selection handler. The board router suppresses
camera pan for cradle and robber starts, including invalid releases.

Only an on-board robber release inside the viewport and within the existing
tile-drop radius (max(30 points, 0.92 * hex size)) may emit a legal tile target.
Off-board, current-tile, cancelled, blocked, stale-state, and changed-decision
releases emit nothing. Captured ownership never turns into a pan mid-gesture.
Pinching cancels a captured drag while retaining the normal pinch handler.
Gesture cancellation clears transient drag feedback. Preview and canonical
origin remain separate; the old tile remains blocked until Confirm succeeds.

## Acceptance

1. Drag the canonical origin or the cradle for rolled seven and armed Knight.
   Both stage legal destinations through the existing target callback.
2. Repeat from the canonical origin after previewing; destination revises and
   any selected victim clears. Origin stays at its canonical coordinate.
3. No drag changes GameState, checkpoint revision, resources, RNG, log, card
   count, or played-Knight count. Confirm commits one exact engine move; a
   repeated Confirm cannot consume a second card or create a second move.
4. Knight Cancel consumes nothing; seven cannot be cancelled, but Clear resets
   its preview. Invalid release preserves the preceding proposal.
5. At fitted, zoomed, and panned cameras, origin hit testing and drop resolution
   use the same real coordinates as rendering. A piece drag leaves the camera
   unchanged; an inactive origin retains ordinary camera pan.
6. Normal taps, dock drags, pinch/recenter, legal outlines, ghost origin,
   viewport clipping, and the fixed board fit retain their contracts.

## Integration / serialized verification

Main cherry-picks the local commit and runs `xcodegen generate` to include the
new router and dedicated test files. No edits to GameView, GameViewModel,
GameViewModel+BoardDecision, ContentView, project.yml, or signing are required.
The existing BoardView initializer and callback remain unchanged.

Run the new router, model, and native UI suites after integration, plus existing
BoardCameraTests / BoardCameraFlowTests, BoardDecisionCoordinatorTests /
BoardDecisionViewModelTests, MainMenuFlowTests' cradle drags, and both board
viewport invariance suites. Use the dedicated Empires QA device, serialized
with main, and derived data outside the worktree. New native UI tests must use
element-frame coordinates, not Mac window coordinates. Review ordinary and
Reduce Motion screenshots at 402- and 375-point widths. Main must actually tap
the integrated app before anyone reports gameplay verified.

Heavy build, test, gate, push, PR, and simulator work is reserved for main.
This worktree may lint changed Swift files and commit locally.

Dedicated suites: `RobberDragRouterTests`, `RobberDragJourneyTests`, and
`OnBoardRobberDragFlowTests`. The router suite includes the independently
calculated origin `(224, 95)` and legal destination `(362.5640646055102, 95)`
under a 2x camera with pan `(65, -35)`; fitted coordinates must miss. It also
covers clamped cameras, hit/drop boundaries, disabled commands, wrong actor and
phase, stale decision/state, cancellation, and cradle-over-origin precedence.
The model suite uses local human seat index 2 in a three-seat game and checks
the durable checkpoint, complete GameState equality during staging, exact move
count/revision increment, one consumed Knight out of two, and no second commit.

For behavioral red proof on Build 16, add only the standalone
`SettlersUITests/OnBoardRobberDragFlowTests.swift` test file to the old tree and
regenerate there; its `testRolledSevenOriginDragRetargetsAndStillRequiresVictimAndConfirm`
uses identifiers that already exist and should fail waiting for a preview after
the origin drag. This has not been run here. The new router/model suites require
the new router type and are not a standalone baseline-red proof.

Current validation: changed-file SwiftLint passed with zero violations. Build,
app tests, UI tests, screenshots, and gameplay remain unverified pending main's
serialized execution. The old `BoardViewCamera.drag` helper is retained untouched;
BoardView now installs `routedDrag` instead. No integration callback adapter is
needed. Recognizable canonical robber artwork remains at its old tile until
dragging or staging a destination; a drag/preview then displays the existing
ghost origin and destination treatment, and cancellation restores the artwork.
