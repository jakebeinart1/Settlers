# Game screen UI redesign report

Base commit: `c801479`. Work done directly on `main` per project convention.

## Files changed

- `Settlers/Theme/CatanTheme.swift` — added `waterBackground`, `panelBackground`, `onWaterText`.
- `Settlers/Views/Board/BoardView.swift` — fills `waterBackground` behind the hex `Canvas`.
- `Settlers/Views/UniformActionButton.swift` (new) — the shared uniform-button view, factored out of `BuildMenuView`'s old private `buildButton` helper.
- `Settlers/Views/BuildMenuView.swift` — now built on `UniformActionButton`; behavior unchanged.
- `Settlers/Views/GameView.swift` — bottom of the screen redesigned into a `panelBackground` panel containing a dice chip, Row 1 (`BuildMenuView`), and Row 2 (Trade / Dev Cards / turn action), plus the notification-trigger logic (`onChange` handlers + `enqueue`/`classify`).
- `Settlers/Views/GameNotificationView.swift` (new) — `GameNotification` model + `GameNotificationOverlay` stacked-toast view.
- `Settlers/Views/PlayerHUDView.swift` — resource breakdown and dev-card count now shown for all 4 players; VP/Road/Army are now labeled pill tags instead of bare icons.
- `Settlers/Views/GameLogView.swift` — log text color fixed for contrast.
- `Settlers/Views/DevCardPanelView.swift` — fixed a dark-text-on-dark-background contrast bug found during the sweep.
- `Settlers.xcodeproj/project.pbxproj` — registered the two new Swift files with the `Settlers` target (this project has no synchronized-folder groups, so new files need an explicit reference; added via the `xcodeproj` gem).

## Per-item status

1. **Two uniform button rows** — done. Row 1 is `BuildMenuView` (Road/Settlement/City/Dev Card) unchanged functionally. Row 2 is Trade/Dev Cards/turn-action, always showing all three slots — the turn-action slot shows "Roll Dice" or "End Turn" when applicable, and a disabled "Turn"/hourglass placeholder otherwise, so the row never jumps around. Trade and Dev Cards disable+dim outside `.mainTurn` for the human (matches when those moves are actually legal per `RulesEngine.legalMoves`).
2. **All players' resource visibility** — done. `PlayerHUDView` now renders the per-resource breakdown for every player's chip, not just the human's.
3. **Buy/see dev cards** — done. Buying was already wired via `BuildMenuView`'s Dev Card button (unchanged). Row 2's "Dev Cards" button opens `DevCardPanelView` (unchanged mechanism), now reachable from the redesigned row and gated the same way as Trade.
4. **VP/longest-road/largest-army tags** — done. All three are now icon+text pill tags in `PlayerHUDView` (`tag(text:icon:tint:)`). Deviation: used short labels — "Road"/"Army" rather than "Longest Road"/"Largest Army" — because the full phrases wrapped letter-by-letter inside a ~90pt-wide chip at 4-across; verified visually (see screenshots) that this reads cleanly at a glance while staying inside chip bounds.
5. **Notifications** — done, UI-layer-only. `GameView` diffs `state.log` (substring-matches on the exact phrasing `RulesEngine`/`SetupPhase` already append — "built a road", "built a settlement", "built a city", "played a knight/road building/year of plenty/monopoly"), plus watches `state.longestRoadPlayer`/`state.largestArmyPlayer` for ownership changes (no log line exists for these two events, so they're detected structurally instead) and `state.pendingTradeOffers` for new offers where `offer.from != human`. Each produces a `GameNotification` appended to a `@State` queue, auto-removed after 4s via a detached `Task.sleep`. Rendered by `GameNotificationOverlay`, a `ZStack`-layered `VStack` of toasts (same layering pattern as the existing "Bot thinking…" overlay) that doesn't block board/button taps. Trade-offer toasts are tappable (opens the trade sheet); others are inert. Chose substring-matching over adding a structured `GameEvent` list to `CatanEngine`, per the task's stated default — kept this purely a UI-layer change.
6. **Top HUD / turn flow unchanged** — done. `PlayerHUDView`'s chip background/layout and `GameView`'s overall phase-driven flow (sheets, setup/robber/discard handling) are untouched; only chip *content* changed.
7. **Color/contrast pass** — done. Found and fixed two real problems: `GameLogView`'s `.secondary` text on its near-black background was very low contrast (confirmed visually — text was nearly unreadable); changed to a fixed light gray (`Color(white: 0.75)`). `DevCardPanelView`'s dev-card rows set their own dark background (`Color(white: 0.16)`) while inheriting the Form's default (dark-mode-adaptive) label color and `.secondary` — on this app the Form context resolved to near-black text over that dark row background; fixed by forcing white/light foreground on that row's content. Spot-checked `TradeSheetView`, `DiscardView`, `RobberTargetView` — all use plain system `Form` styling with default-adaptive colors and no custom dark row backgrounds, so no further contrast issues found there.
8. **Dice display** — done. A "🎲 Rolled N" capsule chip appears at the top of the bottom panel whenever `state.lastDiceRoll` is non-nil, using `die.face.N.fill` (clamped 1-6) plus the roll total as text — chosen over reconstructing two individual dice faces per the task's "keep it simple" guidance, since a 2-12 total can't map cleanly to a single accurate two-die split without extra state.
9. **Water/panel backgrounds** — done. `CatanTheme.waterBackground` (deep blue) fills behind `BoardView`'s `Canvas`; `CatanTheme.panelBackground` (lighter blue) fills behind the two bottom rows. Top HUD area's background is untouched.
10. **Uniform button sizing** — done. Both rows are built from the same `UniformActionButton` (icon over title, `.frame(maxWidth: .infinity)`, same padding/corner radius/disable-dim treatment), factored out of `BuildMenuView`'s prior private helper so Row 1 and Row 2 are pixel-identical in styling.

## Notification approach — why substring matching

Chose UI-only substring matching over adding a structured `[GameEvent]` list to `CatanEngine`/`RulesEngine`, per the task's stated default preference. The log strings' phrasing is stable and centrally defined (`RulesEngine.swift`/`SetupPhase.swift`'s `state.log.append(...)` call sites), so matching against them is a small, disclosed coupling rather than fragile guesswork. The two events with no existing log line at all (longest road / largest army changing hands) are instead detected by watching `state.longestRoadPlayer`/`state.largestArmyPlayer` directly via `onChange`, which is exact (no string matching needed) since those are already discrete, comparable fields.

## Build confirmation

`xcodebuild -project Settlers.xcodeproj -scheme Settlers -destination 'platform=iOS Simulator,name=iPhone 17' build` → **BUILD SUCCEEDED**, confirmed both mid-implementation and again as the final state after fully reverting the temporary screenshot harness (see below). `git diff --stat` against `c801479` shows exactly the 8 modified + 2 new UI files listed above, plus the `.pbxproj` registration — no leftover harness code.

## Simulator verification

Used `iPhone 17` (iPhone 16 unavailable in this environment, per prior-task convention). `simctl` has no tap/UI-scripting subcommand and this project has no XCUITest target, so — matching the "NSLog+temporary harness" technique used in earlier tasks — I added a temporary `#if DEBUG` code path (`GameViewModel.debugSetState`, a `ContentView` launch-env-var branch building a hand-crafted mid-game `GameState`, and a `GameView` launch-env-var branch to auto-present a sheet) to drive the app straight into representative states for screenshotting, without simulating a full legal move sequence or fighting simulator-window coordinate math. **This harness was fully reverted before the final commit** — confirmed via `git status`/`git diff --stat` showing no trace of it.

Screenshots taken (all via `xcrun simctl io <udid> screenshot`):

1. **Main menu** — unchanged, confirms no regression to the pre-existing screen.
2. **Redesigned game screen** (mid-game state: all 4 players with resources/dev cards, VP 1-5, longest road on Player 1, largest army on Player 2, dice rolled 8): shows the water-blue board background, the lighter-blue bottom panel with the dice chip ("🎲 Rolled 8"), Row 1 (Road/Settlement/City/Dev Card, correctly dimmed — no legal moves in this synthetic state) and Row 2 (Trade/Dev Cards/End Turn, enabled and uniformly sized with Row 1), all 4 HUD chips showing full resource breakdowns and dev-card counts, and the "5 VP"/"Road" and "3 VP"/"Army" tags rendering as clean short pills (after the wrap fix — see below).
3. **Notification overlay caught live**: two stacked toasts — "You built a settlement" (green, house icon) and "Player 1 wants to trade" (blue, trade icon) — animated in from the top, non-blocking, over the still-interactive board/buttons underneath.
4. **After auto-dismiss**: confirms both toasts cleared themselves after ~4s with no user interaction, log updated to include "You built a settlement" with now-legible gray-on-black text.
5. **Dev Cards sheet**: "Knight x1" / "Year of Plenty x1" rows now rendering in readable white-on-dark-gray (previously would have been near-black-on-dark-gray).
6. **Trade sheet**: standard system `Form` styling, confirmed good contrast (light background, dark text) — no changes needed here.

### Bug caught and fixed during verification
First pass at the VP/Road/Army tags (screenshot 2, initial version) showed "Longest Road" and "Largest Army" wrapping character-by-character down each pill inside the ~90pt-wide HUD chips — unreadable. Fixed by shortening the tag labels to "Road"/"Army" and adding `.fixedSize()`/`.lineLimit(1)` to prevent any future wrap; re-verified with a fresh screenshot showing clean, single-line pills.

## Deviations / judgment calls

- Tag labels shortened to "Road"/"Army" rather than the task's example "Longest Road"/"Largest Army" (see above) — a direct response to what the chip width could actually render legibly.
- Row 2 button choice/order: Trade, Dev Cards, turn-action (3 buttons) alongside Row 1's 4 build buttons, per the task's suggested split.
- Dice display shows the roll total only (not two reconstructed die faces), per the task's explicit "a clear total is what matters most" guidance.
- `UniformActionButton` was extracted as a small new shared view file rather than inlined a second time, so Row 1/Row 2 styling can't drift apart later.

## Commit

```
git add -A
git commit -m "Redesign game screen: uniform build/trade button rows, all-players resource HUD, VP/road/army tags, event notifications, water theme, dice display"
git push
```
