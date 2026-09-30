# The ghost that froze at 7 VP, and what shipped with it (2026-09-28)

Landed on `main` at `a168a4b`..`6adc97f`, gate passed (all 10 stages).

## The report

Jake: "My ghost I just played was at 7 and would not play a card, it had 34
cards at one point." TestFlight game `8B5DB719`, played 2026-09-28 11:21.

## How it was found

The game was copied off Jake's iPhone and replayed, not guessed at:

```bash
xcrun devicectl device copy from --device <UDID> --domain-type appDataContainer \
  --domain-identifier com.alexchandler.empires --source "Documents/GameLogs" --destination <dir>
# and "Library/Application Support" for the ghost (Ghosts/<id>/v<n>.json), ratings, stats
```

A TestFlight build is readable this way; the logs are `GameLogStore` JSONL and
replay through `RulesEngine.apply`. The ghost was seat 1: from turn 65 it only
rolled and ended, holding 19-32 cards (brick, grain, lumber, wool, no ore).

Re-running `GhostPolicy.decide` at each frozen position with the phone's own
ghost file reproduced `endTurn` every time. Expert at the same positions
proposed a trade, and with proposals exhausted traded 3:1 for ore and bought
development cards.

## Cause

Not retraining drift: the phone's ghost had retrained once (25 games, beta
6.50 -> 7.56). The cause was two things together:

1. **Expert prices a big hand as nearly free.** In Classic weights a card past
   the discard threshold is `handCardOverflow + discardExposure` = +0.0573 -
   0.0524 = **+0.005**. At 25 cards the ore trade scored -0.0249 against
   `endTurn` -0.0389: a 0.014 margin.
2. **The ghost's habits flipped that margin.** Jake's fitted habits include
   -1.3 on bank trades and -0.7 on ending a turn; at lambda 0.01 that
   difference was the whole decision, eight turns running.

Self-play, 40 games each, turn ends holding more than 7 cards: Classic 0.8%,
Expert 7.2%, the phone ghost 15.1% (1% over 15, max 31).

## What shipped

**`HandDiscipline`** (Expert and `GhostPolicy`): a bot that would end its own
turn over the discard threshold takes its best spending move instead (build,
dev card, bank trade). Every spend lowers the hand, so it terminates. Jake's
rule, from the same day: "stay under seven... if you have 10 to 15 you should
play out of that... you are literally wasting cards." After: Expert 7.2% ->
0.4%, ghost 15.1% -> 0.5%, max ghost hand 31 -> 9.

Strength, 4 seats, full chair rotation, held-out seeds 930000+, 100% decisive:

| arm | games | win rate | 95% CI |
|---|---:|---:|---|
| new Expert vs 3 old Experts (null 25%) | 672 | 26.3% | 23.0-29.6 |
| new Expert vs 3 Classic | 624 | 82.4% | 79.4-85.4 |
| old Expert vs 3 Classic | 624 | 83.0% | 80.1-85.9 |
| Jake's phone ghost, new, vs 3 Classic | 624 | **68.8%** | 65.2-72.4 |
| same ghost, old, vs 3 Classic | 624 | 60.4% | 56.6-64.2 |

No cost to Expert. The ghost gained 8.4 points (about 3 standard errors):
hoarding was losing it games. It now wins well above Jake's calibration target
(lambda 0.010 was set to match his 54%), so **lambda wants recalibrating**.

**Beta prior in `PersonFitter`.** On-phone retraining pulled every weight and
habit toward the previous ghost but not beta. Eight simulated retrains of the
bundled ghost: beta 6.5 -> 23-32, production 1.61 -> 1.12. After: beta 6.5 ->
7.4, production 1.61 -> 1.67. `handCard` still drifts toward whoever the ghost
learns from (0.08 -> 0.14 with Expert as the stand-in); `HandDiscipline` is
what guarantees the outcome regardless.

**Renames** (`docs/live-sync.md`). Jake renamed himself "Bein"; his row and
"Jake's Ghost" stayed. A new name claimed by the same Apple ID now renames every
`Player` record it holds; every phone rewrites its games and rebuilds Elo; games
verify against the slug they were posted under; the ghost keeps its id through
`GhostStore` aliases. Jake's phone migrates on its first sync of a build with
this change.

**Spider graphs for Expert and Classic.** Tapping either AI row opens its page;
the graph is from its own games once it has three, from its own self-play until
then. Classic's self-play reference was measured new; Expert's re-measured.

## Tested and not shipped: no limit on bot trade offers

Jake asked for it on the condition that bots stay reasonable. Measured, four
Expert seats, 60 games per arm, same seeds:

| | cap of 3 refusals | no cap |
|---|---:|---:|
| proposals per game | 193 | 540 |
| most proposals in one turn | 6 | 19 |
| moves per game | 634 | 1,306 |
| turns cut off by the 25-action backstop | 0 | 16 |

Classic was unchanged (78.8 proposals a game either way; it runs out of new
offers before three refusals), but a Classic 12-VP matrix game failed to finish
inside 3,000 moves. Jake's decision, 2026-09-28: **leave the cap at 3.**

## Tests the gate runs

- `CatanAITests/HandDisciplineTests` - Jake's hand, Expert and ghost; the
  control arm with the rule off reproduces the freeze.
- `CatanAITests/GhostPersonModelTests.anIncrementalFitKeepsBetaNearThePreviousGhost`
  - fails on the old fitter (10 -> 2.2), passes on the new.
- `SettlersTests/LiveSyncTests` - rename on both phones, Jake's untracked-state
  catch-up, a pre-rename game uploading, renaming back, and two players playing
  each other's ghosts to one shared ladder.
- `SettlersTests/LeaderboardTests`, `SettlersTests/GhostTrainerTests`,
  `SettlersUITests/GhostOpponentFlowTests.testTheAITiersHaveSpiderGraphs`.

## Not proven

The online flows are tested against an in-memory CloudKit with two simulated
phones. No real two-device test has run: the CloudKit build signs under Alex's
team, and Jake's Mac holds only Jake's identity. That needs a TestFlight build
containing `6adc97f` on two phones.

## Strict merged-app audit (2026-09-29)

Audit base: `11cae60f873ff2d4e3bdb7604ce3a995269c2328`. Shipped Build 14
source was `697d67cdb24c79c3a9671de02d887162d28b17f4`; the isolated audit
integrates Jake's main through `bbc39a1d39f19b30c15114d4af7b303f793f0989`.
Worktree: `/Users/alex/.codex/worktrees/trade-robber-feedback/Settlers`, branch
`codex/merged-app-audit-20260929`. The primary AI-research checkout is untouched.

Confirmed bugs fixed, not new strategy initiatives:

- Restore an owner's server ghost before uploading local state; reject stale
  uploads and track successful uploads per stable ghost ID, not per device.
- Surface partial CloudKit claim/query/asset failures rather than advancing a
  cursor over omitted records. Preserve server change tags for concurrency.
- Follow the server's accepted name on an unchanged second phone. Persist a
  deliberate Join/name-change request before any network operation; retry it
  after account lookup or rename failure. Save the previous verified owner slug
  before changing claims, so an interrupted rename can finish after relaunch.
- Recover stable ghost aliases on restored owners and observing phones, even
  when the downloaded ghost already has the correct display name.
- Invalidate derived ratings durably before changing stats. A failed rating
  write or interrupted pass then rebuilds on retry, despite an advanced cursor.

### Standards review

Independent review found stale-rating recovery and swallowed claim failures;
both were reproduced and corrected. Follow-up SDK and recovery reviews found
the cold-owner alias, stale second-phone name, observer alias and interrupted
rename paths; regression tests reproduced those failures before their fixes.
Final bounded source review reported **zero remaining actionable findings**.
This verdict is source review, not a claim of physical-device CloudKit testing.

### Spec review

Independent review confirmed the restore-before-upload and rename/cursor
recovery requirements. It also found that the real recording-warning alert
consumed the queued city/VP notice while blocking the board. The view now holds
feedback for that alert; the native Confirm → hold five seconds → dismiss flow
passes with its unread notice still visible. Final bounded review reported
**zero remaining source blockers**. Standards and Spec remain separate verdicts.

### Observed verification and limits

- `final-sync-green.xcresult`: 29 app-test functions passed across adapter,
  sync and observer suites. Later `recovery-green.xcresult`: all three functions
  (four parameterized executions) passed, covering the two final interruption
  paths plus the stale-phone control. Red runs are retained beside the green.
- At 375pt, native taps verified bank quantities/receipts, production gains,
  score/card notices, discard minimization at maximum Dynamic Type, nonzero-seat
  Vast robber confirmation and New Game. Four final affected flows passed after
  correcting two test assumptions: the normal SE board is 230pt, not 250pt;
  a redundant alert-disappearance wait consumed the notice's reading window.
- Inspection exposed oversized compact card icons and scenery painted above
  card labels. Fixed the compact icon font and moved scenery into the background,
  preserving the card/board frames. A real Year of Plenty flow at maximum text
  size passed; the final screenshot was opened and checked.
- Jake's final dice-odds help chart was exercised through native scrolling.
  The assertion now checks the actual scroll viewport, not mere existence or
  the whole app frame. The complete chart screenshot was opened and checked.
- These checks used dedicated QA simulators only. No user save, research tree,
  production CloudKit record or signing default was reset. No new Settlers crash
  report appeared during these focused runs. Real two-device production sync
  remains unobserved; fake-server and real-SDK boundary tests are not that proof.

Final whole-gate, CI, merge, signing, runtime and Apple delivery receipts are
stored at `/Users/alex/Library/Application Support/EmpiresResearch/deliveries/merged-audit-20260929/STATUS.md`.
The focused checks above do not substitute for those final release checks.
