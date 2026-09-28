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
- A FIFO notice with up to four seconds of reading time occupies the existing 20pt information slot. Small
  signed overlays occupy the existing VP badges. No modal, sounds, flying cards,
  board resize, gameplay wait, or repeating animation. Reduce Motion has no new
  motion to disable.
- Preserve the currently readable notice across rapid moves. Retain at most five
  waiting notices, discard news older than 24 seconds, and show a move's net VP
  changes once with its final notice. This is not an exhaustive game log.
- Errors, mandatory board/discard decisions, settings, and private card surfaces
  hide notices and pause reading time. Returning after 24 seconds discards stale
  news. Resumed and newly promoted notices schedule expiry no later than 24 seconds
  after their event, even if reading time remains. The winner screen remains
  authoritative on game completion.
- Clear transient news on background, match replacement, recovery, leaving the
  board, and legacy local-seat changes. Cold resume never recreates old notices.
  Clearing content preserves the view-owned hold: backgrounding with a card hand
  open does not change that surface's hold predicate or dismiss it.

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
- `targeted-2.xcresult`: six native tap flows covering all four card types, the
  city upgrade, and Longest Road transfer passed; the HUD layout test also passed
  at both 375 and 402pt. Inspected every card notice and both width renders.

## Review corrections and final source freeze

- Implementation: `9a5c019461b211d857c97454c5feb7c626518d05`.
  Additional layout/card tests: `21fab3fc914ea48d6999885f7f683bf5acd5c65c`.
- Final production fix: `82cf08ab838b05dddc52d97434fa49af4c41e48f`.
  The release owner independently added version 14 in `ca4d54b`; this implementation
  pass did not change signing, version settings, engine, AI, or save schemas.
- Review P2 was real: `clear()` reset suspension without the unchanged view hold
  triggering another `onChange`. `review-clear-red.xcresult` exited 65: the unit
  regression and real background → Monopoly → five-second private-result hold
  both failed. Clearing content now preserves suspension.
- Review P3 was real: resume and pending promotion scheduled expiry at event age
  26 and 27 seconds. `review-deadline-red.xcresult` exited 65 on those two exact
  boundary assertions, while the fixed background/Monopoly UI flow passed. One
  shared deadline calculation now caps both paths at event age 24 seconds.
- Final `review-green.xcresult` / `review-green.log`: **xcodebuild exit 0** on
  frozen source `82cf08a`. **22 test functions / 25 parameterized executions;
  zero failures and zero skips**, also recorded in `review-green-summary.json`.
  This comprises 11 `GameplayFeedbackTests` functions (14 executions), three
  `GameplayFeedbackCommitTests`, one `GameplayFeedbackLayoutTests`, and seven
  `GameplayFeedbackFlowTests`. Strict lint and `git diff --check` also passed.
- All app tests ran only on dedicated Empires SE QA
  `2D63B5E8-83B3-4565-812B-DCB831B0189F`, serially with two build jobs, using the
  evidence root's unique external `DerivedData/`. No manual-play simulator or
  user save was reset. No new Settlers crash reports appeared.
- Final screenshots and names are indexed by `screenshots-final/manifest.json`.
  Inspected the final held-result recovery (`DA02EA8B-7CF2-48CE-822C-FA0F66ED27A3.png`)
  and Longest Road transfer (`B2A20EBF-A920-468D-9FFA-7F2A2AB3CB57.png`). The public
  notice is readable; both transfer score deltas remain visible; native assertions
  confirm unchanged board and command-row frames.

## Release-owner integration

- The real 402pt run exposed a clipped local +2 badge that the HUD-size-only
  assertion did not detect. `67c1339` disables clipping on the stats scroller;
  the parent painted card still clips the row. No dimensions or score rules
  changed. Source follow-up review found no blocker.
- `visible-badge.xcresult`: all nine checks passed (seven card/score flows,
  cross-width HUD sizing, and command-row invariance). The corrected 402pt
  screenshot `screenshots-visible-badge/CEED9A08-5F5F-4CE2-AE03-8EB24443DB45.png`
  was opened and inspected; the whole local +2 badge is now visible.
- Earlier full app run: 471 tests, 468 passed, three simulator/query/time-out
  failures under severe host contention. `serial-recheck.xcresult` passed all
  three plus seven feedback flows on unchanged code. The failed run is retained,
  not represented as an initially green gate. Final complete app recheck and
  delivery receipts live in the evidence root's `STATUS.md`.
- Final `final-app-suite.xcresult`: **471 passed, zero failures/skips**, on the
  corrected `67c1339` application source. Final Release compilation passed;
  a fresh Release installation survived the 86-second check, its menu screenshot
  was inspected, and no new Settlers crash report appeared.

## Original implementation-pass limits

The 402pt check renders both HUDs and the reserved information slot; it is not a
full 402pt simulator tap run. Native interactions above ran at 375pt. This pass
did not run the full gate, compile Release, test a physical phone, push, archive,
merge, or upload. Those checks and Build 14 delivery belong to the release owner.
That focused implementation pass froze at `82cf08a`; the release-owner correction
and checks above supersede that source as the final delivery candidate.
