# Empires — Gameplay Identity and Private-Decision UX

**Spec version:** 1.0
**Date:** 2026-09-04
**Status:** Item 1 implemented on `codex/player-identity-system`; items 2–5 build-ready
**Scope:** Player identity, robber victim selection, development-card reveal and hand, discard minimization

## 1. Product outcome

Empires should make a crowded board understandable without forcing the player
to memorize names, colors, and unrelated icons. Private decisions should feel
deliberate: the app shows what is being considered, what will happen, and the
one action that commits it. Mandatory decisions may be minimized for context,
but never dismissed or silently resolved.

The five reported problems are one product family:

1. A player must have one identity everywhere.
2. A robber victim must be recognizable before the theft commits.
3. A bought development card must be privately revealed.
4. A mandatory discard must permit board inspection.
5. Development cards must have a discoverable hand and complete play flows.

## 2. Experience principles

- **Identity is redundant on purpose.** Name, civilization, painted crest, and
  color travel together. Color alone is never the only ownership cue.
- **Selection is not commitment.** Board targets and cards first become a
  visible proposal; a separate, explicit action commits irreversible choices.
- **Mandatory is not modal forever.** A required task may collapse into the
  action dock so the board can be inspected, but normal game commands stay
  unavailable until the task is complete.
- **Private information gets a private moment.** A development-card reveal and
  a hot-seat handoff are not transient toasts.
- **One visual grammar.** Painted gold frames, scenic blue grounds, serif type,
  civilization crests, resource art, and the stable bottom action slot are the
  shared vocabulary. No new generic sheet or SF-Symbol faction language.
- **The engine owns legality.** Views render typed legal choices and disabled
  reasons; they do not reconstruct rules from phase switches.

## 3. Sequencing decision

Planning can happen in parallel; implementation should not. Items 2–5 all
touch the board target state or bottom command region, so parallel patches
would create several competing interaction coordinators.

1. Finish and verify player identity.
2. Build the robber destination and victim flow on that identity contract.
3. Build development-card reveal and hand together; they are one journey, not
   two disconnected features.
4. Build discard minimization on the resulting shared command-dock rules.
5. Run one cross-feature state-priority pass: handoff > mandatory discard >
   robber decision > development-card flow > trade offer > ordinary actions.

AI trade acceptance and road strategy are intentionally outside this UI stage.
They need separate measured AI work and must not be smuggled into presentation
changes.

---

## 4. Item 1 — One player identity everywhere

### End state

Every occupied chair resolves to one match-scoped `PlayerIdentity` containing
its seat, controller kind, snapshotted display name, civilization, color, and
painted piece mark. `PlayerRoster`, derived from the realized checkpoint setup,
owns the map. `seatAtDevice` remains separate because passing the phone changes
who can interact, not who is playing.

### Visual requirements

- HUD cards use the exact civilization color family used by that player's
  roads and pieces.
- Every player header uses a `CivilizationCrest` made from the same painted
  settlement art placed on the board.
- Human name, AI snapshot name, civilization, crest, card fill, border, roads,
  buildings, handoff cover, trade request, trade outcome, and end-game row all
  resolve from the same identity value.
- The current robber-victim choices carry that same crest, name,
  civilization, color and public hand count even before item 2 replaces the
  surrounding one-tap interaction with a confirmable flow.
- Neutral identities remain neutral. In particular, Columbia cannot acquire a
  red, purple, or blue cast from texture blending.
- Replacing dots and SF Symbols must not shrink the board, grow the top HUD, or
  make the New Game screen overflow at 375 × 667 points.
- Archived game rows use the archived name, never a strategy such as
  “balanced” as a player name.

### Functional acceptance criteria

- **ID-1:** Every occupied seat has exactly one identity and one controller.
- **ID-2:** A human identity has a non-empty match name and no opponent profile.
- **ID-3:** A computer identity has one snapshotted opponent profile whose
  civilization matches the chair.
- **ID-4:** A contradictory Human+AI chair or mismatched profile/civilization
  cannot start a new game and receives a named validation reason.
- **ID-5:** Random seat ordering moves the whole identity as one unit.
- **ID-6:** Fresh start, restart, cold resume, and hot-seat handoff preserve the
  complete roster exactly.
- **ID-7:** Changing app name/civilization preferences does not rename or
  recolor an active match.
- **ID-8:** Board drawing receives the live identity resolver; it does not read
  a process-global seat color.
- **ID-9:** Solo and hot-seat winners are classified from the complete set of
  human seats, not whichever seat currently holds the phone.
- **ID-10:** Current logs snapshot identity; legacy logs fall back to a human or
  computer label, never a personality label.
- **ID-11:** Every visible robber-victim choice exposes the roster identity and
  public resource-card count; no anonymous question-mark player icon remains.

---

## 5. Item 2 — Robber destination and victim selection

### Product goal

Moving the robber is an inspectable two-step decision. The player can consider
a legal destination, see whom that destination exposes, change their mind, and
then commit the destination/victim combination. Nothing moves merely because a
drag or exploratory tap ended.

### Proposed board state

```text
BOARD
  robber in a side cradle while choosing
  legal destination rings on tiles
  selected tile: strong gold ring + ghost robber

BOTTOM COMMAND DOCK
  Move the Robber
  Choose a highlighted territory
  [Cancel]                       [Confirm Move]

AFTER A TILE IS SELECTED
  Steal from
  [crest  Name / Civilization / 7 cards]
  [crest  Name / Civilization / 3 cards]
  [Choose another territory]    [Confirm Steal]
```

### Interaction decisions

- Both tap and drag may select a tile, but neither commits it.
- While choosing, the current robber is shown in a clearly labeled board-side
  cradle; the map also retains an origin marker so the old position is clear.
- A legal selected tile gets a ghost robber and unique gold outline. Other
  legal tiles remain available; illegal tiles are dim and non-interactive.
- `Confirm Move` is disabled until a legal destination exists.
- If the destination has no eligible victim, confirmation commits the move.
- If it has one or more victims, stable identity cards replace the dock's
  destination controls. Even one victim remains a deliberate selection.
- Victim cards show crest, name, civilization, and public resource-card count.
  They reveal no resource types.
- Victims are ordered by the same stable seat order as the top HUD.
- “Choose another territory” returns to destination selection without changing
  game state or consuming a Knight.
- Cancel is available only for a played Knight before commit. A robber move
  caused by rolling seven is mandatory and cannot be abandoned.
- Local selection clears only after the engine move and durable checkpoint both
  succeed. An error leaves the proposal recoverable.

### Visual requirements

- Reuse `CivilizationCrest`; do not create portraits or another logo system.
- One-, two-, and three-victim layouts fit without overlap or horizontal
  scrolling on 375 × 667 points.
- Every tile, victim, cancel, change, and confirmation target is at least
  44 × 44 points.
- Selected state uses shape, text, and border in addition to color.
- Reduce Motion removes pulsing/scaling and keeps a simple crossfade.

### Acceptance criteria

- **ROB-1:** Only engine-provided legal destinations can be selected.
- **ROB-2:** Selecting or dragging previews but never mutates `GameState`.
- **ROB-3:** Confirming applies exactly one `.moveRobber` or `.playKnight`.
- **ROB-4:** Every eligible victim appears exactly once; no ineligible player
  appears.
- **ROB-5:** Victim name, civilization, crest, tint, and border match the HUD
  and board identity exactly.
- **ROB-6:** Public card counts are accurate and resource composition is hidden.
- **ROB-7:** Changing destination does not consume a card, steal, save a move,
  or append a log event.
- **ROB-8:** Zero-, one-, two-, and three-victim cases complete correctly.
- **ROB-9:** Mandatory seven and Knight use one shared chooser but preserve
  their distinct cancel and card-consumption rules.
- **ROB-10:** Apply/persistence failure retains the selected tile and victim and
  shows a readable retry path.
- **ROB-11:** VoiceOver labels identify the territory, victim, civilization,
  public card count, and selected state without relying on color.
- **ROB-12:** Cold relaunch before confirmation restores only canonical engine
  state; no partial move or consumed Knight exists.

### Verification matrix

- Deterministic QA fixture with a central destination, three victims, long
  names, varied civilization colors, one city, and two settlements.
- Unit tests for victim construction and ordering at 0/1/2/3 victims.
- Interaction tests: select, change tile, select victim, confirm, cancel Knight,
  and retry after injected persistence failure.
- Screenshots at 402-point and 375-point widths plus an accessibility text size.
- Manual tapped flows after rolling seven and playing a Knight, on three- and
  four-player tables and with a nonzero human seat.

---

## 6. Items 3 and 5 — Development-card reveal and usable hand

These ship together. A reveal without a hand is a dead end; a hand without a
reveal does not answer what was bought.

### Complete journey

`Build → durable purchase → private reveal → owned hand → detail → legal choice → durable result`

### Purchase reveal

- Present only after the purchase and checkpoint commit succeed.
- Show full card name, existing type artwork/color, concise effect, and status.
- Active card: “New · Play starting next turn.”
- Victory Point: “Hidden victory point · Counts automatically.”
- Actions: `View My Cards` and `Continue`; a winning VP purchase instead offers
  `Claim Victory` before the end-game presentation.
- The reveal persists until explicitly dismissed. It is never a toast.
- A failed purchase leaves Build open and shows no reveal.

### Discoverable hand

- A permanent Development Cards shelf sits in the human panel, even when empty.
- Empty copy: “None yet · Buy one from Build.”
- Grouped tiles show full-enough card name, count, and Ready/New/Passive status.
- Tiles are always tappable for explanation. Legality disables only `Play` and
  supplies a plain-language reason.
- A mixed stack distinguishes older playable copies from a copy bought this turn.
- Victory Point cards remain private and have no Play action.

### Rules and flow requirements

- Typed engine status owns playability and its block reason.
- Knight, Road Building, Year of Plenty, and Monopoly support legal pre-roll and
  action-phase timing; the UI cannot duplicate an older Knight-only rule.
- Only one active development card may be played per turn.
- Cards bought this turn cannot be played this turn; older copies of the same
  type remain playable.
- Road Building previews two sequential legal roads and commits atomically.
- Year of Plenty selects exactly two bank-available cards and commits atomically.
- Monopoly selects one resource and reports even a zero-card result.
- Knight enters the shared robber chooser.
- Every unfinished card flow is cancellable without mutating engine state.

### Acceptance criteria

- **DEV-1:** Every successful purchase reveals the exact bought card once.
- **DEV-2:** Failed or uncommitted purchases never reveal or add a card.
- **DEV-3:** Relaunch preserves the hand and bought-this-turn restriction.
- **DEV-4:** The hand is discoverable empty, occupied, and mixed-status.
- **DEV-5:** Disabled reasons come from typed engine status.
- **DEV-6:** Each active card has a complete legal, cancellable, atomic flow.
- **DEV-7:** Victory Points count automatically and stay hidden until game end.
- **DEV-8:** Private card identity is excluded from opponent-facing history.
- **DEV-9:** Every card flow survives 375-point width and accessibility text.
- **DEV-10:** Full gate plus tapped purchase-and-play verification covers every
  card type.

---

## 7. Item 4 — Minimize mandatory discard to inspect the board

### Product goal

The discard remains mandatory but does not blind the player to the board state
needed to make a good choice.

### Interaction model

- Entering a human discard obligation opens the editor expanded with a blank
  draft.
- A 44-point minimize control collapses it into the stable bottom action slot.
- The dock reads `Discard required` plus remaining progress and reopens the
  editor; it never submits.
- Draft selections survive minimize/expand and an in-game Settings round trip.
- Expanded submission is enabled only at the exact required count.
- A failed application or save retains the full draft and displays an error.
- A new player/obligation clears the old draft. Cold resume starts expanded
  with no ephemeral selection.

### Inspect-only contract

- Board and public HUD remain readable.
- Non-mutating board camera gestures remain available.
- Roll, Build, Trade, End Turn, robber targeting, development-card play, and
  all vertex/edge/tile command targets are absent or inaccessible.
- The normal action row is replaced, not merely greyed out behind the dock.
- Handoff remains above the discard UI and hides private hand/draft information.

### Acceptance criteria

- **DISC-1:** The requirement and exact count come from canonical engine state.
- **DISC-2:** Selection cannot exceed the requirement or the cards owned.
- **DISC-3:** Reaching the count never auto-submits.
- **DISC-4:** Minimize/expand changes no game, checkpoint, log, or bot state.
- **DISC-5:** The board is inspectable while every game-producing command is
  both non-hittable and absent from accessibility navigation.
- **DISC-6:** Hot-seat handoff clears the outgoing draft before exposing the
  next person's hand.
- **DISC-7:** Settings pauses incoming-offer timers while discard is active.
- **DISC-8:** Expanded and collapsed layouts fit small phones and Dynamic Type
  without changing board size at ordinary text sizes.
- **DISC-9:** Submission failure retains the draft and is retryable.
- **DISC-10:** Restart and Quit may abandon the draft only because they abandon
  the match itself and remain confirmation-gated.

---

## 8. Cross-feature decision log

| ID | Decision | Reason |
|---|---|---|
| UX-1 | Painted settlement art is the faction crest everywhere. | Two emblem systems made board-to-HUD matching harder. |
| UX-2 | Runtime identity is a roster derived from the realized checkpoint. | Names, profiles, colors, and marks must survive restart/resume as one value. |
| UX-3 | Board selection always precedes irreversible commit. | Drag release and exploratory taps are ambiguous intent. |
| UX-4 | Mandatory flows minimize into the bottom dock, never dismiss. | Context remains visible without falsely suggesting the obligation vanished. |
| UX-5 | Dev reveal and hand are one implementation stage. | Each surface is incomplete without the other. |
| UX-6 | Robber and dev-card targeting share one selection coordinator. | Knight is the same spatial decision with a different source and cancel rule. |
| UX-7 | Presentation state stays out of `GameState`. | Saves contain committed rules state, not half-considered UI choices. |
| UX-8 | No AI tuning occurs in this work. | Trade/road intelligence needs measured model work, not UI intuition. |

## 9. Definition of done for each implementation item

An item is complete only when all of the following are true:

- Acceptance criteria have executable coverage where automation is meaningful.
- New Swift files are included through `project.yml`/XcodeGen.
- `scripts/gate.sh --debug-app` passes, including Release compilation.
- The app is freshly installed on the dedicated QA simulator.
- 402-point and 375-point screenshots are inspected for clipping, overlap,
  color drift, text scaling, and board-size regression.
- The full critical flow is tapped through using the native UI harness.
- Failure, cancellation, resume, hot-seat, and accessibility paths are checked.
- A high-strictness review is fixed before the PR is opened.
