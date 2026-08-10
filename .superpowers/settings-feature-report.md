# Settings Screen: Per-Player Piece Colors + Shape Style

## Summary

Added a new `SettingsView` reachable from `MainMenuView` via a gear-icon
button (top-right, sheet presentation). It lets the player customize each of
the 4 seats' piece color (from a curated 8-color palette, with duplicate
colors across seats disallowed) and pick between two piece shape styles
(`.classic`, an enhanced version of the existing house silhouette, and
`.modern`, a new pin/marker style). Both choices persist across launches via
`UserDefaults` and apply live to the running game without a restart.

## Palette

Defined `PieceColor: String, Codable, CaseIterable` in
`Settlers/Theme/PieceColor.swift` with 8 cases: **blue, red, orange, cream,
green, purple, teal, yellow**. The first four (blue/red/orange/cream) are
exactly the app's original hardcoded seat colors, now exposed as
`PieceColor.defaultColor(forSeatIndex:)` so the shipped defaults are
unchanged for anyone who never opens Settings. The four additions
(green/purple/teal/yellow) were chosen to stay clearly distinguishable from
each other, from the original four, and from `CatanTheme`'s resource tile
colors (brick/lumber/ore/grain/wool) and the board's blue
`waterBackground`/`panelBackground` - avoided a second blue/navy or a second
orange/gold that could be confused with tiles or other seats.

Duplicate-color prevention: `SettingsView.playerColorRow` computes
`takenElsewhere` (the set of colors used by the *other* three seats) and
disables+dims (25% opacity) any swatch in that set for the current row. This
is enforced in the UI (can't tap a taken swatch) rather than left to the
user's discretion, matching the task's explicit requirement.

## Shape styles

Defined `PieceShapeStyle: String, Codable, CaseIterable` in
`Settlers/Theme/PieceShapeStyle.swift` with two cases:

- **`.classic`** - the original `SettlementShape`/`CityShape` in
  `Settlers/Views/Board/TileView.swift`, genuinely enhanced while in there:
  the settlement got a steeper roofline (0.5 -> 0.55 of height) and a small
  chimney block on the right roof slope; the city got a second, taller
  chimney over its main house in addition to its existing annex, so it reads
  as more "built up" than a settlement at a glance, not just bigger.
- **`.modern`** - new `ModernSettlementShape` (a rounded pin/map-marker
  teardrop) and `ModernCityShape` (a faceted hexagonal "gem/crown" shape,
  wider and more angular than the settlement pin) - a clearly distinct
  silhouette family from the house shapes, my creative call per the task's
  "your creative call" allowance.

`PieceShapeStyle.settlementShape()` / `.cityShape()` return `AnyShape` and
are the single place that maps style -> concrete `Shape`.

## SettingsStore

`Settlers/Persistence/SettingsStore.swift`, modeled on `GameStore.swift`'s
singleton/file-layout convention but backed by `UserDefaults` directly
(small keyed preferences, not a JSON blob):

```swift
@MainActor
@Observable
public final class SettingsStore {
    public static let shared = SettingsStore()
    public var playerColors: [PieceColor]      // index 0-3, PlayerID.index
    public var pieceShapeStyle: PieceShapeStyle
    public func color(forSeatIndex:) -> PieceColor
    public func setColor(_:forSeatIndex:)
    public func resetToDefaults()
}
```

`@MainActor` + `@Observable` (matching `GameViewModel`'s existing pattern) -
required for Swift 6 strict concurrency since `.shared` is a static
singleton, and gives free SwiftUI re-render on every write via `didSet`
persisting to `UserDefaults` and Observation's automatic tracking. No manual
`objectWillChange` plumbing needed; `BoardView`/`CatanTheme` reading
`SettingsStore.shared.pieceShapeStyle` or `.color(forSeatIndex:)` inside a
view's `body` picks up changes automatically once `SettingsView` writes them
- confirmed live in the simulator (see Verification below).

## Call sites updated

- **`CatanTheme.color(for: PlayerID)`** (`Settlers/Theme/CatanTheme.swift`)
  - the single centralized function - now delegates to
  `SettingsStore.shared.color(forSeatIndex:).color` instead of the hardcoded
  switch (which became `PieceColor.defaultColor(forSeatIndex:)`). Marked
  `@MainActor` to match `SettingsStore`. Every existing caller of this
  function automatically picks up custom colors with no per-call-site
  changes: `BoardView.swift` (settlement/city fill, road fill),
  `PlayerHUDView.swift` (seat swatch, active-player ring), `EndGameView.swift`
  (winner headline color, VP table swatches), `TradeSheetView.swift` doesn't
  call `color(for: PlayerID)` (only `color(for: Resource)`, untouched).
- **`BoardView.swift`** (`buildingViews`) - the only place `SettlementShape()`/
  `CityShape()` were directly instantiated. Now reads
  `SettingsStore.shared.pieceShapeStyle` once per render and calls
  `.settlementShape()` / `.cityShape()` on it.

No other call site in `Settlers/Views/` instantiates the shapes or bypasses
`CatanTheme.color(for:)` for player colors (verified via grep across
`Settlers/Views/`).

## SettingsView

`Settlers/Views/SettingsView.swift` - flat dark colonist.io-style screen
matching `MainMenuView`/`EndGameView`'s established look
(`Color(white: 0.08)` background, heavy rounded title font, `Color(white:
0.14)` cards). Contents:

- Header with "Settings" title and an X dismiss button.
- 4 rows (`CatanTheme.playerLabel(for:)` for labels - "You"/"Player 1-3"),
  each a horizontal scroll of 8 color swatches; selected swatch gets a white
  ring, taken-by-another-seat swatches are dimmed and disabled.
- A 2-up shape style picker: each option renders a live thumbnail (an actual
  `settlementShape()` filled with the human's current color) plus a label;
  selected option gets an orange border.
- "Reset to Defaults" button at the bottom (not required by the task but
  cheap to add, restores all 4 default colors and `.classic`).

All writes go straight to `SettingsStore.shared` - no local `@State` mirror,
no explicit save step.

## Wired into the app

`MainMenuView.swift` - added a small gear-icon (`gearshape.fill`) button,
top-right, presenting `SettingsView` as a `.sheet`. Didn't add a second entry
point from `GameView` (mid-game HUD is already dense with build/trade
buttons and the task's example only called for "a small gear-icon button"
from the main menu) - reachable at any time via returning to the menu, which
was judged sufficient per "reachable at any time it makes sense."

## Verification

Built `xcodebuild build -scheme Settlers -destination 'platform=iOS
Simulator,name=iPhone 17'` - **BUILD SUCCEEDED**, twice (once immediately
after implementation, once as a final check before writing this report).
`iPhone 16` isn't installed in this environment, so `iPhone 17` was used
throughout, per prior tasks' convention.

Visual verification in Simulator (screenshots taken via `xcrun simctl io
screenshot`, driven by AppleScript `click at` against the Simulator window,
recalibrated per-tap against the window's live accessibility frame since the
window can resize between launches):

1. **Settings screen itself** - opened via the gear icon from the main menu.
   Shows all 4 player rows with the 8-swatch palette (blue selected/ringed
   for "You" by default, red/orange/cream pre-selected+ringed for
   Player 1/2/3 and visibly dimmed in every other row), and the Classic
   (enhanced house-with-chimney) / Modern (pin) shape picker with Classic
   selected and outlined by default.
2. **Live color change** - tapped the purple swatch for "You": it became
   selected (white ring) immediately, its shape-picker thumbnail preview
   turned purple, and purple became dimmed in the other three rows'
   palettes in the same frame (no dismiss/reopen needed) - confirms
   `@Observable` propagation.
3. **Live shape change** - tapped "Modern": its thumbnail became the
   selected/outlined one, both thumbnails re-rendered in the current human
   color.
4. **Board/HUD reflecting both changes after leaving Settings** - dismissed
   via the X button, started "New Game": the "You" HUD card's seat swatch
   circle rendered purple immediately (before any placement). After placing
   the human's initial settlement, the board rendered a **purple, pin-shaped
   ("Modern") settlement** with a matching purple road at the placed vertex
   - confirmed both the custom color and the alternate shape style are
   live on the actual game board, not just in Settings' own preview
   thumbnails.

Screenshots are in the session scratchpad (not committed - ephemeral
verification artifacts): `s1.png`/`g1-g3.png` (Settings screen + live
edits), `board2.png` (purple HUD swatch right after New Game),
`settlement_check.png` (cropped close-up of the purple Modern-pin settlement
+ road on the board).

## Unrelated issue discovered (not fixed, out of scope)

While driving a bot-heavy game in the simulator to test rendering, hit a
pre-existing crash unrelated to this change: `Bot.decideDiscard` in
`Packages/CatanAI/Sources/CatanAI/Bot.swift:115` hits an
`assertionFailure` when a bot needs to discard on a rolled 7, which crashed
the app (and once, the whole simulator device state). This is a
pre-existing bug in `CatanAI`'s bot discard heuristic, outside this task's
app-layer-only, colors/shapes-only scope (the task explicitly says "Don't
touch `CatanEngine`/`CatanAI`"), and not something this change introduced or
touches. Flagging it here rather than fixing it silently or leaving it
unmentioned.

## Judgment calls / deviations

- **8-color palette size**: task suggested "~6-8"; went with 8 to give a
  genuinely wide choice while keeping all of them clearly distinguishable
  against the board's existing colors.
- **Classic shape enhancement**: interpreted "maybe genuinely enhance its
  visual detail" as license to add a chimney + steeper roof to the
  settlement and a second chimney to the city, rather than leaving Classic
  byte-for-byte identical to the shipped shape.
- **Modern shape choice**: went with a pin/marker for the settlement and a
  faceted gem/crown for the city (one of the task's suggested options)
  rather than a "detailed little house with chimney/door" alternative, to
  keep Modern visually orthogonal to Classic (a second house style would
  read as a minor tweak, which the task explicitly said to avoid).
- **No second Settings entry point from `GameView`**: judged the main-menu
  gear icon sufficient; didn't want to add UI surface to the already-dense
  in-game HUD for a preference screen that doesn't need mid-game access.
- **Xcode project file**: this repo's `Settlers.xcodeproj` is a manually
  edited `project.pbxproj` (no `PBXFileSystemSynchronizedRootGroup`), so the
  4 new Swift files (`PieceColor.swift`, `PieceShapeStyle.swift`,
  `SettingsStore.swift`, `SettingsView.swift`) had to be registered by hand
  in `PBXBuildFile`/`PBXFileReference`/`PBXGroup`/`PBXSourcesBuildPhase` -
  otherwise `xcodebuild` doesn't see them at all. Not a deviation from the
  task, just noting the extra step future file additions to this project
  will also need.
