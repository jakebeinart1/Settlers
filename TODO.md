# Settlers — To Do

## 0. UI polish (quick, self-contained fixes)

Small, independent cleanups to the current gameplay surfaces — no design work
or spec needed, just fix the screen. **All done as of 2026-09-07**; kept
here for the rationale each fix carries.

Three more landed the same day, from Jake playing on the phone, and are
recorded here rather than given a section of their own (a fourth, remembering
the chosen civilization, followed on 2026-09-08 - see section 3):

- [x] ~~The name typed on New Game is remembered for the next New Game.~~
      The setup itself was already saved, but `NewGameSetupView` overwrites
      the saved setup's human name with the `PlayerNameStore` preference every
      time it opens, and only App Settings ever wrote that preference - so a
      typed name survived exactly until the next visit. Starting a game now
      writes the preference too (`ContentView.rememberPreferredName`).
      Guarded end-to-end by `PlayerNameMemoryFlowTests`.
- [x] ~~The keyboard overlays New Game instead of compressing it.~~ The screen
      is built inside a `GeometryReader` that derives `isShortScreen` and every
      spacing from the height it is given, so the keyboard's safe-area inset
      visibly scrunched the whole configuration and sprang it back on dismiss.
      `.ignoresSafeArea(.keyboard)` makes it an overlay. Guarded by
      `NewGameKeyboardInvarianceTests` - which only bites with the simulator's
      hardware keyboard disconnected, and says so.
- [x] ~~The pause screen offers one way out, not two.~~ Close and "Resume Game"
      were the same button under two names, over a "Game Control" section that
      repeated all three exits. It is now one bottom row - Close, Restart, Quit
      - with the two destructive ones still behind their confirmations, and the
      boxed "These settings do not change match rules" plaque is folded into
      the screen's subtitle (a plaque is the chrome this app uses for something
      you act on, so a bordered sentence read as a button that would not press).

The next open work is section 1.

- [x] ~~**Board camera: lock the viewport, then make it deliberate.**~~
      **Done 2026-09-07; the lock was WRONG and was replaced the same day.**
      The first fix held the fit at the tallest container the board had been
      given, which stopped the board re-zooming per frame but made its size
      depend on the session's *history* instead: a game that rolled a seven
      kept a board 39% too big and clipped at the bottom, a game that did not
      kept a correct one. The real fix is that everything below the board now
      lives in a fixed-height frame (`GameView.belowBoardReserve`), so the
      board's container cannot vary at all and `BoardView`'s fit is a pure
      function with no stored state - the confirm/cancel panel, the incoming
      trade card, a discard and the inline banners no longer reach the board.
      Guarded by `BoardViewportInvarianceTests`. On top of it, pinch-to-zoom, drag-to-pan and
      a recenter control (`BoardCamera`, bottom-left of the board so it does
      not land on the drag cradle). The camera is a value type with no
      SwiftUI in it, so its clamping is unit-tested (`BoardCameraTests`) -
      zoomed out there is exactly one legal camera and it is the fitted
      board, and nothing can strand the board off screen. Real touches are
      covered by `BoardCameraFlowTests`. Board padding also went 4 -> 6; it
      cannot go higher without port badges landing on placement rings (see
      `BoardView.boardPadding`, which carries the measurements).
      **Two follow-ups the same day, both from Jake playing on device.**
      (1) The board stopped moving, but the panels *inside* the reserve did
      not: the 20pt info banner was still omitted during a board decision, so
      the nameplate and command row jumped 20pt up on every settlement
      placement, knight and seven. The banner is now reserved
      unconditionally and only its content is conditional
      (`BelowBoardInvarianceTests`). (2) Zoomed in, settlements and roads
      drew past the board's top edge over the bot HUD and the sky, because
      only the `Canvas` layer (tiles/ports/robber) self-clips - `.position`
      pieces do not. `BoardView` now clips to its own bounds; the clip cannot
      live on `GameView.boardArea`, which is taller by `topChipInset`.
      Both are on `main` (`071bfe6`, `cc83b0c`), full gate green, and
      installed to Jake's iPhone as build 4.
- [x] ~~Delete `StableHeightSlot` (`Settlers/Views/GameViewLayoutSupport.swift`).~~
      **Done 2026-09-07.** Dead since the viewport fix - the two heights it
      measured are fixed constants now, and nothing referenced it but two
      comments in `GameView` explaining why a grow-only slot was the *wrong*
      shape here. Those comments keep the lesson and no longer name a type
      that does not exist.
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

**Done** - 2026-09-07 for the archive and the replay, 2026-09-08 for the menu
trim. The archive moved out of App Settings and onto the
main menu as **Game History** (directly above the statistics row, hidden until
something has been recorded), and a row now opens the board rather than a
transcript. `GameLogListView` and `GameLogDetailView` - a flat system-chrome
list and a `String(describing:)` dump of every archived `GameMove` - are
deleted, and so is `SettingsView` itself. The menu is now New Game, Resume,
Game History, and the stats row.

- [x] ~~Trim the main menu - drop the Settings entry there.~~ **Done
      2026-09-08.** `SettingsView` and the gear pill are deleted. Of its five
      sections, three had already been made redundant: Your Name and Your
      Civilization are set directly on New Game Setup (and were in fact the
      *cause* of both settings not sticking - opening that screen overwrote the
      saved setup with the preference), and Game Logs became Game History.
      Jake called the remaining two - the Random Civilization Pool and Reset
      Stats - irrelevant, so they went with the screen rather than keeping it
      alive as a home for two controls nobody uses.
      Removed with it: `GameViewModel.resetStatistics()`,
      `MatchCheckpointDocument.resetStatistics()`,
      `CivilizationSettings.setRandomEligibility` and `-qaShowSettings`, all of
      which had no caller left. The random pool *field* stays and still feeds
      every Random seat; it simply sits at its default of all eight
      civilizations now.
      **The one thing this could have broken, and does not:** with App Settings
      gone nothing wrote `CivilizationSettings.yourCivilization`, so every new
      game would have opened on the built-in Medieval default however many
      games were played. Starting a game now writes the chosen civilization as
      well as the name (`ContentView.rememberPreferredIdentity`), guarded by
      `PlayerNameMemoryFlowTests` - verified to fail without the write.
- [x] ~~Pull the plain-text game log out of the current in-game Settings screen
      and give it its own visual replay view.~~ **Done 2026-09-07.** It was on
      the *main-menu* Settings screen, not the in-game one. Its "Game Logs"
      section is gone; the archive is `GameHistoryView`, on the same painted
      seaside ground as the menu it opens from.
- [x] ~~New feature: a visual game log / replay - shows the board and lets you
      scrub a slider from game start to finish.~~ **Done 2026-09-07.**
      `GameReplayView`: the real `BoardView` at the top, then a per-seat score
      strip, the narrated move, a scrubber, and transport controls (start,
      previous, play/pause, next, end). `GameReplayTimeline` reconstructs every
      position by replaying the recording's moves through `RulesEngine` and
      materialises them all up front, because a scrubber is a random-access
      control and the engine only walks forwards. A recording this build cannot
      replay (an older rules version, say) keeps the frames it reconstructed and
      says where it stopped, rather than ending silently on a half-played board.
      Everything below the board sits in a fixed-height frame for the same
      reason `GameView` does it - scrubbing must not resize the board.
      Guarded by `GameReplayTimelineTests` (8 cases) and `GameHistoryFlowTests`
      (3 native UI cases in 3 launches - deliberately few, because the extra
      app launches starved the full-match test in `gate.sh`'s parallel run).
      The win screen's own replay button is asserted inside that full-match
      test rather than in a second one, for the same reason.
- [x] ~~Show the total points and how they are made up on the replay - dev
      cards, Longest Road, Largest Army - so you can see where a player's
      other points came from.~~ **Done 2026-09-08.** Each seat in the score
      strip is now a button onto a `VictoryPointBreakdown` card: settlements,
      cities, victory cards, longest road and largest army, each with what
      there *is* (2 cities, 5 long, 3 knights) next to what it is *worth*.
      All five rows are always drawn, so the card keeps one shape while the
      replay runs under it, and the two bonus badges also sit beside the score
      itself - four of a leader's points can be in Longest Road and Largest
      Army with nothing on the board to show for them, which is the whole
      question the card answers.
      The card **floats over the board** rather than sitting below it: the rule
      this screen is built around is that everything under the board is a
      fixed-height frame, and a panel that comes and goes inside that frame is
      exactly what used to re-zoom the board mid-game. An overlay costs the
      layout nothing.
      `total` is `GameState.victoryPoints(for:)` verbatim, never a sum of the
      rows - the engine warns that a second victory-point formula in a view is
      one that drifts. `VictoryPointBreakdownTests` (6 cases) asserts the rows
      add up to the engine's total at every position of a replayed game, so a
      new source of points fails a test rather than shipping a card that says
      ten over rows adding to eight. Held victory-point cards are shown here
      although the live HUD hides them: a recording is a finished game, and
      hiding them would leave exactly the unexplained gap the card exists to
      close.
- [x] ~~Surface this same replay view from the end-of-game win/lose screen.~~
      **Done 2026-09-07.** "View Replay" under "New Game" on `EndGameView`,
      resolved up front from the archive so the button is absent rather than
      broken when no recording exists (a queued export, or the QA win fixture).

## 4. New game modes (larger maps)

New fixed modes (board size + VP target + map art bundled together, not
independent mix-and-match settings), starting with a "Plan to 20" mode on a
much bigger board. Scoping notes from an architecture survey (2026-09-04):
engine (`Board`, `HexCoordinate`, `GameState` schema) is already
size-agnostic — only `BoardGeneration.swift`'s literal 19-tile/port tables
are fixed. The survey's other finding, that board pan/zoom/recenter did not
exist anywhere, is **no longer true**: `BoardCamera` shipped 2026-09-07 (see
section 0) and the board now pinches, pans, recenters and clips to its own
bounds. What it does not do is *persist* a viewport across launches, which a
larger board may want. See the full survey findings before starting design.

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
