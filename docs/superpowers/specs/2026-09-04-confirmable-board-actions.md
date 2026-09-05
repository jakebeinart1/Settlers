# Empires — Confirmable Board Actions

**Status:** implementation contract
**Scope:** settlement, city, road, Road Building, and robber decisions
**Build order:** shared coordinator → construction → robber → cross-feature audit

This specification extends
`2026-09-04-gameplay-interaction-ux.md`. The earlier document remains the
identity, development-card, discard, and robber-victim contract. This document
defines the shared interaction grammar that construction and robber placement
were still missing.

## 1. Product outcome

A board tap or drag means “consider this location,” never “spend resources and
commit it.” Every spatial action follows one visible sequence:

`start → inspect legal targets → stage a preview → revise if desired → confirm → durable commit`

The player sees the exact piece in their civilization color before committing.
The board remains full size, the proposed location is unmistakable, and the
bottom command dock always explains what is waiting. No unrelated game action
can occur while a proposal is active.

## 2. In scope

- Initial settlement and initial road placement in both setup passes.
- Paid road, settlement, and city construction during the main turn.
- Both roads selected by Road Building.
- Mandatory robber movement after rolling seven.
- Cancellable robber movement initiated by a Knight.
- Explicit robber-victim selection and final confirmation.
- Tap and drag as equivalent selection inputs; tap is always available as the
  accessible alternative to drag.
- Failure, Settings, hot-seat, relaunch, narrow-screen, Dynamic Type, Reduce
  Motion, VoiceOver, and deterministic QA behavior.
- A final state-priority audit across every blocking or mandatory surface.

## 3. Non-goals

- Changing placement legality, costs, robber rules, or development-card rules.
- Persisting an unconfirmed proposal in `GameState` or the match checkpoint.
- Undoing a move after its durable commit.
- AI policy, trade acceptance, road strategy, network multiplayer, or board
  camera work.
- Free-form piece physics. Dragging selects the nearest legal target; the
  canonical piece still snaps to board geometry.

## 4. Interaction grammar

### 4.1 Start

Mandatory decisions start automatically when canonical phase state requires
the human to place a setup piece or move the robber. Optional decisions start
only after the player chooses a build row or a playable Knight/Road Building
card.

Starting a decision replaces the ordinary bottom actions. It never hides the
board behind a modal.

### 4.2 Explore

- Every legal target remains visibly available until confirmation.
- Illegal construction targets receive no command control.
- During robber targeting, illegal tiles are visibly subdued so the “not the
  current territory” rule is understandable.
- Tapping a legal target or dragging the active piece onto it produces the
  same proposal.
- Dragging outside every legal target changes nothing.

### 4.3 Preview and revise

- A proposed road is translucent in the assigned road color with a strong gold
  provisional border.
- A proposed settlement/city uses the exact assigned civilization artwork,
  translucency, and a strong gold provisional border.
- A proposed city remains visually readable as an upgrade of the settlement
  underneath it.
- A proposed robber is a ghost on the destination. The committed origin becomes
  an explicit origin marker, and the active robber is also shown in a labeled
  board-side cradle.
- Tapping or dragging to another legal target moves the proposal without any
  engine event, resource change, card consumption, save write, or log entry.
- `Clear` removes only the proposal and keeps the decision active.

### 4.4 Confirm or cancel

- `Confirm` is visible throughout and disabled until the proposal is complete.
- Setup and seven-driven decisions are mandatory: they may be revised or
  cleared, but cannot be abandoned.
- Paid construction may be cancelled before confirmation; no resource is spent.
- A Knight may be cancelled before confirmation; the card is not consumed.
- Road Building may be cancelled before confirmation; neither road nor card is
  consumed.
- Confirmation requests one complete `GameMove`. The candidate state and
  checkpoint are committed before the UI publishes the result.
- On engine or persistence failure, the proposal and controls remain on screen
  with a readable retry path.

## 5. Construction behavior

### Setup settlement and road

- The dock names the setup pass, the piece, and whether it is the first or
  second placement round.
- Selecting a settlement does not advance to road placement until Confirm.
- After the settlement commits, the dock changes to the required adjacent road;
  only the engine-provided edges are selectable.
- Selecting that road does not advance the snake order until Confirm.
- There is no Build button during setup.

### Paid construction

- Choosing Road, Settlement, or City closes Build and opens the board decision
  dock.
- The dock repeats the piece name and cost so leaving Build loses no context.
- Resources and piece supply do not change during preview.
- Cancel returns to ordinary actions. Reopening Build reflects unchanged state.
- Confirm spends the exact engine-defined cost once and leaves the normal turn
  active unless that build wins the match.

### Road Building

- The first edge is staged without mutation.
- After the first edge, legal second edges are derived from legal ordered pairs,
  including edges connected through the first preview.
- The player may undo the second edge, clear both, or cancel the card.
- After two edges are staged, both remain visible and require `Confirm 2 Roads`.
- Confirmation applies one atomic `.playRoadBuilding`; there is no one-road
  intermediate checkpoint.

## 6. Robber behavior

- The chooser is shared by rolled seven and Knight, but its cancellation rule
  comes from the source.
- The active robber appears in a labeled board-side cradle and can be dragged;
  every legal tile can also be tapped.
- The old tile shows an origin marker. A selected tile shows a ghost robber and
  a gold outline; the canonical robber has not moved yet.
- A no-victim destination still waits for `Confirm Move`.
- A victim-bearing destination shows every eligible player exactly once in
  stable HUD order. Even one victim must be explicitly selected.
- Victim cards reuse the authoritative name, civilization crest, tint, border,
  and public resource-card count; resource composition stays private.
- Selecting a victim stages it. It never steals immediately.
- `Choose another territory` clears victim and destination together.
- `Confirm Steal` applies one `.moveRobber` or `.playKnight` containing the
  selected destination and victim.

## 7. Visual system

- Preserve the existing painted seafaring board, gold notched chrome, serif
  typography, civilization art, and muted blue command ground.
- Spend visual emphasis on the provisional piece: one gold outline/glow, not a
  field of competing animation.
- The command dock stays at the existing bottom-row height at ordinary text
  sizes so the board does not jump or shrink as selection changes.
- The dock has four zones: 44-point piece cradle, concise instruction, optional
  Clear/Cancel, and a 44-point Confirm action.
- Controls use words as well as symbols. Check and X symbols never appear as an
  unexplained pair.
- At 375 × 667, controls do not overlap, clip, or require horizontal scrolling.
  Victim cards may horizontally scroll only when the table produces more cards
  than fit, with Confirm pinned and always reachable.
- The dense graphical identity/resource HUD caps its painted typography at the
  Large category and exposes every value to VoiceOver. The command dock uses
  scaled semantic type, grows at accessibility categories, and takes over the
  otherwise-reserved banner space so the board remains at least 250 points.
- Reduce Motion replaces drag-follow/spring emphasis with a simple opacity
  change. Selection never relies on motion or color alone.

## 8. Architecture decisions

| ID | Decision | Reason |
|---|---|---|
| BA-1 | One app-layer board-decision coordinator owns every uncommitted spatial proposal. | Five independent `@State` values already drift across cleanup, Settings, and handoff. |
| BA-2 | `CatanEngine` remains the sole legality and application authority. | A preview is presentation state, not a second rules engine. |
| BA-3 | The coordinator exposes one presentation snapshot and one requested move; SwiftUI is an adapter. | Callers should not reconstruct legal targets or commit semantics. |
| BA-4 | Mandatory setup/seven decisions are derived from canonical phase plus legal moves. | Relaunch reconstructs the obligation without persisting ephemeral selection. |
| BA-5 | Optional build/card decisions are explicitly armed and cancellable. | Their source and cancellation semantics do not exist in `GamePhase`. |
| BA-6 | Confirmation clears a proposal only after engine application and checkpoint commit succeed. | Failure must never look like success or force the player to rebuild a choice. |
| BA-7 | Drag and tap feed the same selection entry point. | Two input methods must not create two behaviors. |
| BA-8 | The whole staged decision is cleared at hot-seat handoff, restart, quit, or a contradictory state transition. | Half-finished private intent cannot cross seats or games. |
| BA-9 | Cold relaunch restores mandatory obligations blank and drops optional proposals. | Checkpoints contain rules truth, not thoughts the player had not confirmed. |
| BA-10 | Interaction precedence is resolved once and tested as a table. | Layer order, hit testing, bot pausing, and accessibility must not each invent a different winner. |
| BA-11 | The graphical HUD caps at Large; the decision dock scales and grows after reclaiming the idle banner slot. | A real Accessibility Large run expanded the old HUD off both sides and clipped Confirm. Separating fixed spatial data from the reading/command surface keeps the board at 250 points while the active instructions still honor Dynamic Type. |

## 9. Acceptance criteria — construction

- **BUILD-1:** Every setup settlement/road, paid road/settlement/city, and Road
  Building edge comes from the acting seat's engine-provided legal moves.
- **BUILD-2:** Selecting or dragging a target changes no canonical state,
  resource, piece count, checkpoint revision, event, or log.
- **BUILD-3:** The exact assigned-color piece preview appears at the selected
  target and is visibly provisional without relying on color alone.
- **BUILD-4:** Selecting a second legal target moves the proposal and preserves
  all canonical state.
- **BUILD-5:** Confirm applies exactly one matching move and durable checkpoint.
- **BUILD-6:** Clear never exits a mandatory decision; Cancel exits an optional
  decision without mutation.
- **BUILD-7:** Setup settlement and its required adjacent road each require a
  separate explicit confirmation.
- **BUILD-8:** Paid build resources are deducted exactly once, on confirmation.
- **BUILD-9:** City preview and confirmation target only the acting player's
  legal settlement; confirm replaces it with a city once.
- **BUILD-10:** Road Building requires two legal ordered edges and one final
  confirmation; cancellation consumes neither card nor road.
- **BUILD-11:** A failed application/save retains the complete proposal and a
  retryable explanation.
- **BUILD-12:** Hot-seat handoff exposes no outgoing proposal; the incoming
  mandatory obligation is reconstructed for the claimed seat.
- **BUILD-13:** Cold relaunch before confirmation contains no spent resource,
  placed piece, or consumed card.
- **BUILD-14:** Every target, Clear, Cancel, and Confirm control is at least 44
  points and has a complete VoiceOver label, value, and hint.
- **BUILD-15:** Setup, paid construction, and Road Building fit at 375 and 402
  points wide without shrinking the ordinary board.

## 10. Acceptance criteria — robber

- **ROB-1:** Only engine-provided legal destinations can be selected.
- **ROB-2:** Tap or drag previews but never mutates `GameState`.
- **ROB-3:** Confirm applies exactly one `.moveRobber` or `.playKnight`.
- **ROB-4:** Zero-, one-, two-, and three-victim destinations resolve correctly.
- **ROB-5:** Every eligible victim appears exactly once; no ineligible victim
  appears.
- **ROB-6:** Victim identity and public card count match HUD and board exactly.
- **ROB-7:** A destination with no victim still requires confirmation.
- **ROB-8:** A destination with victims requires an explicit victim selection
  and final confirmation; tapping a victim alone does not steal.
- **ROB-9:** Changing destination does not move the robber, steal, consume a
  Knight, save, or log.
- **ROB-10:** Seven cannot be cancelled; Knight can be cancelled before commit.
- **ROB-11:** Failure retains destination and victim and supplies a retry path.
- **ROB-12:** Cold relaunch restores only canonical robber state and a blank
  mandatory chooser when applicable.
- **ROB-13:** VoiceOver identifies source, territory, selected state, victim,
  civilization, and public card count without relying on color.

## 11. Acceptance criteria — shared interaction priority

The single visible/interactive winner is:

`handoff > recovery failure > mandatory discard > mandatory robber/setup > private receipt > optional board decision > incoming trade > ordinary actions`

- **INT-1:** The same winner governs visual Z-order, hit testing,
  accessibility visibility, and bot pausing.
- **INT-2:** Settings may temporarily cover an active draft and returns to the
  exact proposal; timers and bots do not progress behind it.
- **INT-3:** A higher-priority handoff clears outgoing ephemeral intent before
  revealing the incoming player's identity or hand.
- **INT-4:** An incoming trade cannot replace a mandatory or already-active
  spatial decision.
- **INT-5:** Development-card reveal/resolution remains private and blocks every
  board command until acknowledged.
- **INT-6:** No hidden control beneath an overlay is hittable or reachable by
  VoiceOver/XCUITest.
- **INT-7:** Every transition in the priority table has an automated regression
  or a documented manual check.

## 12. Verification matrix

- Pure coordinator tests for every begin/select/revise/clear/cancel/confirm
  sequence and contradictory state transition.
- `GameViewModel` tests proving state/checkpoint atomicity and retained draft on
  injected persistence failure.
- Tap-driven UI journeys for setup settlement + road, paid road, settlement,
  city, Road Building, rolled seven, and Knight.
- At least one real drag journey for construction and one for robber; tap
  alternatives remain independently tested.
- 0/1/2/3-victim fixtures and a nonzero human seat.
- Hot-seat handoff, Settings round trip, background/foreground, cold relaunch,
  and recovery retry.
- Screenshots at 402 × 874 and 375 × 667, ordinary and accessibility text, with
  explicit review for clipping, overlap, board-size drift, identity mismatch,
  and provisional-versus-committed readability.
- Full `scripts/gate.sh --debug-app`, fresh simulator install, process-survival
  check, crash-report diff, and high-strictness review before PR.
