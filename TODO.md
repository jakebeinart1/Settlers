# Settlers — To Do

## 0. Gameplay interaction UX

Product requirements, interaction decisions, acceptance criteria, and the
implementation sequence live in
`docs/superpowers/specs/2026-09-04-gameplay-interaction-ux.md`.

- [x] One match-authoritative player identity across live gameplay surfaces.
- [x] Confirmable robber destination and identity-rich victim selection,
      including an off-board drag cradle, ghost destination, explicit victim,
      change-territory action, and one final durable confirmation.
- [x] Private development-card purchase reveal plus discoverable usable hand.
- [x] Minimize mandatory discard into an inspect-only board mode.
- [x] Cross-feature state-priority and accessibility pass, backed by the shared
      interaction resolver plus native setup, discard, development-card,
      trade, handoff, Settings, construction, and robber journeys.

## 1. Bot strength
Make the bot opponents play meaningfully better.

- [x] Added `ThreatAssessment` (`Packages/CatanAI/Sources/CatanAI/ThreatAssessment.swift`)
      — a per-opponent threat score (VP + production + hidden dev cards +
      proximity to Largest Army/Longest Road) — and wired it, proportionally
      via `relativeWeight`, into robber targeting, settlement/road
      placement (denies threatening opponents' frontier spots, blocks their
      road network), trade acceptance (raises the bar for high-threat
      proposers), and Monopoly targeting. See
      `docs/superpowers/specs/2026-08-16-bot-threat-assessment-design.md`.
- [x] Established a reproducible, seat-rotated baseline against the frozen
      Greedy anchor; added per-seat behavior metrics; and fixed bot-to-bot
      proposals so another policy answers before the proposer continues. See
      `docs/AI_summaries/2026-09-02-ai-baseline-and-personality-audit.md`.
- [x] Demonstrated two distinct style axes on held-out, chair-rotated games:
      Aggressive uses playable knights more often; Cautious proposes a player
      trade before paying the bank more often. See
      `docs/AI_summaries/2026-09-02-personality-separation-results.md`.
- [x] Defined and validated city capture rate as the consolidation metric;
      Cautious chose a legal city +6.5 points more often than Balanced on
      held-out, chair-rotated games (95% CI +3.1 to +10.3). The narrower
      city-versus-settlement and city-versus-outward-build metrics were
      explicitly rejected as too sparse. See
      `docs/AI_summaries/2026-09-02-consolidation-metric-results.md`.
- [x] Replaced bot-seat-order personality assignment with stable, realized
      opponent profiles that compose civilization, general, strategy, and
      dialogue; active matches snapshot profiles across relaunch/restart and
      logs record both profile identity and measured strategy. See
      `docs/AI_summaries/2026-09-02-opponent-profile-decision-log.md`.
- [ ] Calibrate genuine difficulty tiers against frozen anchors before adding
      a difficulty control to New Game. Personality and difficulty are
      separate axes and must remain separate in both evaluation and UI.
- [ ] Compare heuristic/search, RL/self-play, LLM, and hybrid prototypes through
      the shared `GameObservation`/`ActionSpace` seam. Do not select an
      algorithm from intuition or from another game's results. The evidence
      map, decision gates, and ordered research program are in
      `docs/AI_summaries/2026-09-05-ai-strategy-research-program.md`.

## 2. Main menu / game log rework

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
- [ ] Opponent event messages: besides trade offers, bots should be able to
      send you a message when your move screws them over mid-game (cut off
      on the road, longest road taken from them, a settlement/city built
      that hurts their spot, etc.). Triggers: an opponent gets cut off from
      a road spot, Longest Road changes hands, a settlement is built, a
      city is built. Surfaced in a message window opened via the same
      button as the pause menu (bottom-right), so you can see opponent
      reactions to events as the game goes.

## 3. New game modes (larger maps)

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
      Google-Maps-style "recenter" button that resets the camera back to
      the current default fit-to-container view.
- [ ] Generate new full-screen map background art for the larger board via
      the existing AI art pipeline (`design-references/tiles/_scripts/`);
      hex tile textures are stamped per-hex and don't need regenerating.
- [ ] Add a map/mode selector to New Game setup (`MatchSetup`,
      `NewGameSetupView`), wired to the new board generator and VP target.

## 4. Board / dev-card / robber UI polish

- [ ] Lock the board viewport during settlement placement, general gameplay,
      and robber movement — it currently re-zooms/shifts. `BoardView` has no
      persisted camera; `fittedGeometry(for:in:padding:)`
      (`Settlers/Views/Board/BoardView.swift:523`) recomputes scale-to-fit on
      every render from whatever is currently drawn (targeting overlays,
      port badges, etc.), so the effective zoom moves under the player's
      finger mid-interaction instead of holding one fixed fit. Standardize
      on a single locked fit per screen/mode rather than a fit computed per
      redraw. Related to, but distinct from, the "3. New game modes" item
      that wants real pinch/pan camera controls — this item is about the
      *unintentional* movement, independent of whether pan/zoom ships.
- [ ] Clean up the development-card deck / draw UI — currently redundant.
      Audit `DevCardPopupView.swift` and `Theme/DevCardStyle.swift` for
      duplicated card-face/deck presentation and simplify to one clear
      pull/reveal flow.
- [ ] Fix truncation in the robber steal (victim-selection) screen — the
      bottom portion of the sheet is cut off. Likely
      `RobberVictimButton.swift` and its containing sheet/journey from the
      robber interaction resolver; make it fit without clipping on the
      standard device sizes covered by `run-settlers`/`play-settlers`.
