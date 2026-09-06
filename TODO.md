# Settlers — To Do

## 0. UI polish (quick, self-contained fixes)

Small, independent cleanups to the current gameplay surfaces — no design work
or spec needed, just fix the screen. Take these before the larger feature
work below; they're cheap and visibly improve every game played in the
meantime.

- [ ] **Priority.** Lock the board viewport so it never moves on its own
      based on in-game actions — settlement/road/city placement, general
      gameplay, and robber movement all currently shift or re-zoom the
      board. Root cause: `BoardView` has no persisted camera —
      `fittedGeometry(for:in:padding:)`
      (`Settlers/Views/Board/BoardView.swift:523`) recomputes scale-to-fit on
      every render from whatever happens to be drawn (targeting overlays,
      port badges, etc.), so the fit — and with it the apparent zoom/pan —
      changes as those overlays come and go. Fix: compute one fit per
      screen/mode and hold it fixed instead of recomputing per redraw. This
      is a bug fix, independent of the *deliberate* pinch/pan camera planned
      for "4. New game modes" — do this first regardless of whether that
      feature ships, since it's broken in the current single-board game too.
- [ ] Clean up the development-card deck / draw UI — currently redundant.
      Audit `DevCardPopupView.swift` and `Theme/DevCardStyle.swift` for
      duplicated card-face/deck presentation and simplify to one clear
      pull/reveal flow.
- [ ] Fix truncation in the robber steal (victim-selection) screen — the
      bottom portion of the sheet is cut off. Likely
      `RobberVictimButton.swift` and its containing sheet/journey from the
      robber interaction resolver; make it fit without clipping on the
      standard device sizes covered by `run-settlers`/`play-settlers`.

## 1. Bot strength

Make the bot opponents play meaningfully better. **Not done.** Playtesting
(2026-09-06) says bots still lose consistently to a human player and show
visibly repeating patterns during play. Past infra/metrics work here
(baseline vs. the frozen Greedy anchor, personality separation, threat
assessment) never measured bots against human-level play, only bot-vs-bot —
so a bot can win every logged metric and still be the easy, repetitive
opponent being reported now.

- [ ] Bots cannot beat a human player and repeat visibly predictable patterns
      in real play (reported 2026-09-06). Needs a human-anchored strength
      check (not just bot-vs-bot), and root-causing of the specific repeated
      patterns before more personality/metric work is layered on top of a
      bot that isn't winning games.
- [ ] Calibrate genuine difficulty tiers against frozen anchors before adding
      a difficulty control to New Game. Personality and difficulty are
      separate axes and must remain separate in both evaluation and UI.
- [ ] Compare heuristic/search, RL/self-play, LLM, and hybrid prototypes through
      the shared `GameObservation`/`ActionSpace` seam. Do not select an
      algorithm from intuition or from another game's results. The evidence
      map, decision gates, and ordered research program are in
      `docs/AI_summaries/2026-09-05-ai-strategy-research-program.md`.

## 2. Opponent event messages

Extends the existing bot dialogue/personality infrastructure
(`Packages/CatanAI/Sources/CatanAI/TradeMessages.swift`,
`Settlers/Models/OpponentProfile.swift`) beyond trade offers. Split out of
the old "Main menu / game log rework" section — it's a bot-behavior/dialogue
feature, not a menu or log-UI change, even though it happens to share a
button with the pause menu.

- [ ] Besides trade offers, bots should be able to send you a message when
      your move screws them over mid-game (cut off on the road, longest
      road taken from them, a settlement/city built that hurts their spot,
      etc.). Triggers: an opponent gets cut off from a road spot, Longest
      Road changes hands, a settlement is built, a city is built. Surfaced
      in a message window opened via the same button as the pause menu
      (bottom-right), so you can see opponent reactions to events as the
      game goes.

## 3. Main menu / game log rework

- [ ] Trim the main menu — drop the Settings entry there; most of what it
      exposes is already reachable later (in-game settings, etc.), so a
      separate top-level Settings screen is redundant.
- [ ] Pull the plain-text game log out of the current in-game Settings screen
      and give it its own visual replay view instead of (or alongside) the
      text log.
- [ ] New feature: a visual game log / replay — shows the board and lets you
      scrub a slider from game start to finish to see how the board state
      (and score) evolved, rather than reading a log of text events.
- [ ] Surface this same replay view from the end-of-game win/lose screen
      (e.g. a "View Game Log" button) so you can review how the game played
      out right after it ends.

## 4. New game modes (larger maps)

New fixed modes (board size + VP target + map art bundled together, not
independent mix-and-match settings), starting with a "Plan to 20" mode on a
much bigger board. Scoping notes from an architecture survey (2026-09-04):
engine (`Board`, `HexCoordinate`, `GameState` schema) is already
size-agnostic — only `BoardGeneration.swift`'s literal 19-tile/port tables
are fixed — but board pan/zoom/recenter does not exist anywhere today
(`BoardView` always auto-fits the whole board to its container via one
`HexGeometry` fit calc; no `ScrollView`/`MagnificationGesture`/persisted
viewport). See the full survey findings before starting design.

- [ ] Design and write a spec for the first new mode (board layout
      generator, VP target, stall-audit for reaching 20 VP given
      buildings/dev-card caps, player-count support) via
      superpowers:brainstorming → docs/superpowers/specs/.
- [ ] Board camera: pinch/gesture zoom and pan on `BoardView`, plus a
      Google-Maps-style "recenter" button that resets back to the default
      fit-to-container view. Build this on top of the locked, non-drifting
      viewport from "0. UI polish" — do that fix first, since a deliberate
      camera isn't worth building on a fit calc that's still recomputing
      itself per render.
- [ ] Generate new full-screen map background art for the larger board via
      the existing AI art pipeline (`design-references/tiles/_scripts/`);
      hex tile textures are stamped per-hex and don't need regenerating.
- [ ] Add a map/mode selector to New Game setup (`MatchSetup`,
      `NewGameSetupView`), wired to the new board generator and VP target.
