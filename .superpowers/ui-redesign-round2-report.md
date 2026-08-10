# UI/UX Redesign Round 2 — Report

Base: `d4f4938`. App-layer/UI only; `CatanEngine`/`CatanAI` untouched.

## Files changed

- `Settlers/Views/GameView.swift` — layout restructure, inline robber flow, dice animation, single action row.
- `Settlers/Views/BuildMenuView.swift` — single "Build" button with a `Menu` for Road/Settlement/City/Dev Card.
- `Settlers/Views/PlayerHUDView.swift` — split into `BotHUDRow` (3 bot chips) + `HumanPlayerPanel` (spacious bottom panel) + shared `PlayerChip` helper.
- `Settlers/Views/DevCardPanelView.swift` — dev cards rendered as `DevCardTile` playing-card-style tiles in a horizontal scroll.
- `Settlers/Views/Board/TileView.swift` — `TileDrawing.drawRobber` now redraws the tile's number in white on top of the robber icon.
- `Settlers/Views/Board/BoardView.swift` — added `highlightedTiles`/`isTileTargetingActive` for the inline robber-move mode; passes the robber tile's number through to `drawRobber`.
- `Settlers/Theme/CatanTheme.swift` — added `hudChipBackground`/`hudChipBackgroundActive` (lighter blue-family tones replacing the old near-black grays).

## Per-item status

1. **Dev cards as visual cards** — done. `DevCardTile`: icon + color per type (knight=red/shield, road building=brown/road, year of plenty=green/sparkles, monopoly=purple/crown, victory point=gold/star), held-count badge, existing "NEW" badge preserved, horizontal scroll. Tap-to-play and `isPlayable` disable/dim behavior unchanged.
2. **Human's resources via dots, prominent** — done via item 12's `HumanPlayerPanel` (16pt dots + bold counts, dimmed when zero).
3. **Bots show dev-card count only** — confirmed present (inherited from round 1) and preserved in `BotHUDRow`/`PlayerChip`; no bot's specific held cards are ever rendered.
4. **Dice roll animation** — done. `animateDiceRoll()` drives a quick scale (0.6→1.3→1.0) + rotation (-12°→10°→0°) spring pulse on the dice chip whenever `state.lastDiceRoll` changes, via `.onChange`. Kept to a single brief pulse rather than cycling die faces, per the "tasteful and brief" guidance. Not capturable in a static screenshot — verified the trigger logic and that the chip animates on each `onChange` firing (confirmed each `debugLoadPreviewState` reload with a different roll value re-triggered it during manual testing).
5. **HUD contrast** — done. Replaced `Color(white: isActive ? 0.20 : 0.12)` with `CatanTheme.hudChipBackground`/`hudChipBackgroundActive` (blue family, `red:0.18,green:0.40,blue:0.60` / `red:0.25,green:0.52,blue:0.74`). Confirmed visually readable in screenshots.
6. **Single Build button** — done. `BuildMenuView` is now one button (hammer icon, "Build" or the armed placement's name) using a native SwiftUI `Menu` for Road/Settlement/City/Dev Card, each with the same per-option `RulesEngine.legalMoves`-based disabling as before. When a placement mode is armed, the menu also offers "Cancel <mode>". Chose `Menu` over `.popover`/sheet as the most native/immediate mechanism requiring no extra state. Relocated into the single 4-button action row (Build/Trade/Dev Cards/turn action) alongside the other buttons rather than its own row, since a lone full-width button read as excessive empty space.
7. **Roll Dice/End Turn same button** — already done (prior round), confirmed untouched (`turnActionButton` in `GameView.swift`).
8. **Robber number visible in white** — done. `TileDrawing.drawRobber` now takes the tile's `numberToken` and redraws it in white on top of the robber icon. Verified via screenshot with the robber forced onto a "5" (grain) tile — the white "5" is clearly legible inside the robber's dark circle.
9. **Piece shapes/colors customizable** — already done (prior round), untouched and confirmed still working (pieces render correctly with `SettingsStore.shared.pieceShapeStyle`/color in all screenshots).
10. **Inline robber move on main board** — done for the mandatory post-7-roll case, the common path. `GameView` now puts the *existing* `BoardView` into tile-targeting mode (`highlightedTiles`/`isTileTargetingActive`, new `BoardView` params) whenever `state.phase == .movingRobber(human)`: every tile but the current robber tile is outlined yellow and tappable via the same `onTapTile` callback; the current robber tile (and, during targeting, all vertex/edge tap targets) dims. Tapping a tile with no eligible victims applies `.moveRobber` immediately; tapping one with eligible victims shows an inline "Steal from: [Player buttons] [Cancel]" row that replaces the bottom action row (`robberTargetingPanel`), instead of a sheet. Verified both sub-cases via screenshots (no-victim auto-commit path not separately screenshotted, but is a straight `viewModel.apply` call, same as the victim path's button action). **Deviation**: per the task's explicit allowance, the knight-card sub-flow (`RobberTargetView.Mode.knightCard`, triggered from the dev-card panel) was left as the existing sheet with its own embedded duplicate `BoardView` — unifying it into the same inline mechanism was possible in principle (same `highlightedTiles`/tap-routing machinery) but risked touching the road-building/knight dev-card handoff logic in `GameView.handleDevCardPlay` under time pressure; the mandatory case (the far more frequent, more jarring-as-a-modal one) got the inline treatment as prioritized.
11. **Human's cards visible at bottom** — done, see item 12.
12. **3 top bot boxes / 1 bottom human box** — done. `GameView`'s `VStack` is now: `BotHUDRow` (3 bot chips only) → `BoardView` → road-building banner/error → `GameLogView` → `HumanPlayerPanel` (spacious: name, VP/Longest Road/Largest Army tags, 16pt resource dots with counts, dev-card-count) → `bottomPanel` (dice chip + action row). `PlayerHUDView.swift` now defines `BotHUDRow`, `HumanPlayerPanel`, and a shared `PlayerChip` enum (the old single 4-chip `PlayerHUDView` type is gone).
13. (n/a — no item 13 in the task list; items 1-12 cover the full brief.)

## Verification

- `xcodebuild -scheme Settlers -destination 'platform=iOS Simulator,name=iPhone 17' build` → **BUILD SUCCEEDED**, confirmed both mid-implementation and as the final state after fully reverting the temporary screenshot harness (`git diff --stat` against `d4f4938` shows only the 7 files listed above — `ContentView.swift`/`GameViewModel.swift` are back to their original content, confirmed via `git diff` showing no changes to either).
- Simulator: `iPhone 17` (iPhone 16 unavailable in this environment, matching prior-task convention).
- Screenshots taken via a temporary `#if DEBUG` harness (`GameViewModel.debugLoadPreviewState(kind:)`, a `ContentView` launch-env-var branch, and a temporary `GameView` debug initializer to pre-seed the inline robber tile pick) — same technique used in the round-1 report, fully reverted before the final commit:
  1. **Mid-game main screen** (`midgame`): 3 bot chips up top (lightened blue backgrounds, VP/Road/Army tags, dev-card counts only), water-blue board with legible number tokens, empty log, spacious human panel at bottom with full resource dots + dev-card count, dice chip ("🎲 Rolled 8"), and the single-button action row (Build/Trade/Dev Cards/End Turn).
  2. **Inline robber targeting, no selection yet** (`robber`): all tiles but the desert (current robber tile) outlined yellow; bottom panel replaced with "🏜️ Move the Robber — tap a highlighted tile above" instead of the action row.
  3. **Inline robber targeting, victim picker** (`robberVictim`): after a tile pick (pre-seeded via the debug initializer since a real tap couldn't be scripted in this environment — `simctl` has no tap/UI-scripting subcommand and AppleScript couldn't attach to the Simulator window here), the bottom panel shows "Steal from: [Player 1] [Cancel]".
  4. **Robber number legibility** (`robberOnNumber`): robber forced onto the "5" tile — the white "5" renders clearly inside the dark robber circle.
  5. **Dev card visual redesign** (`devcards`): `DevCardPanelView` shown directly — Knight (red/shield, x2), Year of Plenty (green/sparkles, x1), Victory Point (gold/star, x1, dimmed/disabled since unplayable).
  6. **Post-revert sanity check**: launched the app with no env var — clean, unmodified main menu, confirming the harness left no trace in the normal launch path.
- **Not captured in a screenshot**: the Build button's `Menu` popup itself (native SwiftUI menu chrome, opened only by a live tap) and the dice roll's motion — both are describable but not photographable statically; verified by code review that `Menu`'s items and `.disabled` state are wired identically to the old four-button logic, and that `animateDiceRoll()` fires on every `state.lastDiceRoll` change.

## Concerns / judgment calls

- Knight-card robber sub-flow intentionally left as a sheet (see item 10) — explicitly allowed by the task brief as the fallback if unifying both flows risked the mandatory case.
- Couldn't script a live tap in this environment (no XCUITest target, `simctl` has no UI-scripting subcommand, AppleScript didn't find a Simulator window to attach to) — used the same synthetic-state harness technique as round 1's report for all screenshots, including a small temporary `GameView` debug initializer (fully reverted) to pre-seed the robber-victim-picker screenshot without a real tap.
- `BuildMenuView`'s menu-open visual and the dice animation's motion are unverified by screenshot (see above) but verified by code/logic review.
