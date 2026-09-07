# Settlers — To Do

## 0. UI polish (quick, self-contained fixes)

Small, independent cleanups to the current gameplay surfaces — no design work
or spec needed, just fix the screen. Take these before the larger feature
work below; they're cheap and visibly improve every game played in the
meantime.

- [x] ~~**Board camera: lock the viewport, then make it deliberate.**~~
      **Done 2026-09-07.** The fit is now solved once per board/width and
      held (`BoardView.updateLock(for:in:)`), so the confirm/cancel panel,
      the incoming trade card and the inline banners no longer re-zoom the
      board as they come and go. On top of it, pinch-to-zoom, drag-to-pan and
      a recenter control (`BoardCamera`, bottom-left of the board so it does
      not land on the drag cradle). The camera is a value type with no
      SwiftUI in it, so its clamping is unit-tested (`BoardCameraTests`) -
      zoomed out there is exactly one legal camera and it is the fitted
      board, and nothing can strand the board off screen. Real touches are
      covered by `BoardCameraFlowTests`. Board padding also went 4 -> 6; it
      cannot go higher without port badges landing on placement rings (see
      `BoardView.boardPadding`, which carries the measurements).
- [x] ~~Clean up the development-card deck / draw UI — currently redundant.~~
      **Done 2026-09-07.** The "Ready to play / This card can be used now"
      plaque now appears only when the card CANNOT be played - for a playable
      card the hand tile already badges it READY and the action button reads
      "Play Knight" with what it will ask for, so the plaque was a fourth
      copy. The sheet also hugs its content (`ViewThatFits`) instead of
      always filling the screen and leaving ~300pt of empty panel between the
      description and the buttons, and the hand tiles' "1 READY · 1 NEW"
      badge no longer hangs off both sides of its tile.
- [x] ~~Fix truncation in the robber steal (victim-selection) screen.~~
      **Done 2026-09-07.** The names were the truncation ("Alexan...",
      "Rames...", "Moctez..."): the compact card led with the crest and left
      about 34pt for the text column. The crest and card count now share a
      top row and the name gets the card's full width. The card also grew
      48 -> 54pt and its content is inset off the painted frame it was being
      drawn underneath, and "Choose another territory" is drawn as "Change
      territory" (the full name stays as its accessibility label).

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
- [x] ~~Board camera: pinch/gesture zoom and pan, plus a "recenter"
      button.~~ **Moved to "0. UI polish"** (2026-09-07) and merged with the
      viewport-lock bug fix, which is the same feature seen from the other
      end. Tracked there, not here — it ships on the current 19-tile board
      regardless of whether larger maps do. This section still *depends* on
      it: a board bigger than the screen is unusable without pan/zoom.
- [ ] Generate new full-screen map background art for the larger board via
      the existing AI art pipeline (`design-references/tiles/_scripts/`);
      hex tile textures are stamped per-hex and don't need regenerating.
- [ ] Add a map/mode selector to New Game setup (`MatchSetup`,
      `NewGameSetupView`), wired to the new board generator and VP target.
