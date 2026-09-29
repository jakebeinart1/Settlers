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
