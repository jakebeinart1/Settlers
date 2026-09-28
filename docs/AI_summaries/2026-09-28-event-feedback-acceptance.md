# Small gameplay-feedback follow-up

Scope: public development-card plays, bonus ownership changes, and net visible
victory-point changes. This follows the resource/trade feedback in Build 13;
this branch does not alter that build or its signing, rules, AI, or save schema.

## Acceptance and decisions

- Emit only after `GameViewModel.commitStep` successfully saves the candidate.
  Staging, cancellation, failed saves, loading a save, and acknowledging a
  private result must not invent or repeat events.
- Name the actual player and each publicly played Knight, Road Building,
  Year of Plenty, or Monopoly. Purchases never announce a private card face.
- Name Longest Road gains, losses, and transfers; apply the same small treatment
  to Largest Army. Keep the persistent ownership icons unchanged.
- Derive signed VP deltas from committed before/after scores, not assumed action
  values. A city upgrade is +1; bonus transfers show the old holder's loss too.
  Use public VP for opponents, full VP only for the person holding the device.
- A four-second FIFO notice occupies the existing 20pt information slot. Small
  signed overlays occupy the existing VP badges. No modal, sounds, flying cards,
  board resize, gameplay wait, or repeating animation. Reduce Motion has no new
  motion to disable.
- Preserve the currently readable notice across rapid moves. Retain at most five
  waiting notices, discard news older than 24 seconds, and show a move's net VP
  changes once with its final notice. This is not an exhaustive game log.
- Errors, mandatory board/discard decisions, settings, and private card surfaces
  hide notices and pause reading time. Returning after 24 seconds discards stale
  news. The winner screen remains authoritative on game completion.
- Clear transient news on background, match replacement, recovery, leaving the
  board, and legacy local-seat changes. Cold resume never recreates old notices.

## Verification scope

`GameplayFeedbackTests` covers all four actual engine card plays, bonus ownership,
net city points, hidden information, FIFO pressure, held time, expiry, and clear.
`GameplayFeedbackCommitTests` exercises successful/failed durable writes, staged
and cancelled placement, recovery, background, restart, cold resume and private
acknowledgement. `GameplayFeedbackFlowTests` taps real Confirm, card play and city
upgrade controls, checks board/command-row invariance and captures screenshots.

QA fixture: `-qaAutoStart -qaLongestRoadPosition` seeds a complete Classic board
with tied five-road paths. The rival holds the tie. The human's sixth road is
only staged; the normal Confirm button must commit it before any feedback exists.

## Evidence (2026-09-28)

- `targeted-1.xcresult`: 11 app test functions (14 parameterized executions) and
  3 native tap flows passed on Empires SE QA (375pt). Debug compilation and
  SwiftLint strict passed. No new Settlers crash reports appeared.
- Inspected all three screenshots: the transfer shows +2 on the human and −2 on
  the former holder; city upgrade says +1; Monopoly names player and card. Both
  score overlays are fully visible and the board/command row frames did not move.
- Evidence root:
  `/Users/alex/Library/Application Support/EmpiresResearch/deliveries/event-feedback-20260928/`.
  Screenshots are under `screenshots-1/` with descriptive names in `manifest.json`.
- Additional cross-width layout checks follow. Full gate, 402pt simulator replay,
  review, merge and Build 14 delivery belong to the release owner, not this
  implementation pass.
