# Mid-game decisions: rollouts find no mistake, weight screens find no confirmed gain

2026-10-29. Follows `2026-10-28-opening-rollouts.md`, which named mid-game
(rolls 11-20, "19% mistakes") as the next target. Expert under test:
`openingOreGrainV1`, 4 players, Classic rules, randomized board.

## 1. Rollouts: Expert's mid-game choice is not worse than its alternatives

`ghost improve --rolls 11-30 --all-seats --sample 6 --alternatives 2 --rollouts 16`
over 49 games (three quarters four-Expert self-play, the rest one Expert
against the Kbeast, Bein and Chandy ghosts): 166 decisions, each playing
Expert's move and its next two candidates 16 times on shared dice.

| | win share vs Expert's move, 90% |
|---|---|
| Expert's 2nd choice | -1.3 ± 1.6 points |
| Expert's 3rd choice | -2.8 ± 1.7 points |

No move kind (roads, bank trades, dev cards, ending the turn, knights)
had an alternative significantly better. The 2026-10-28 "19% mistakes" came
from taking the best of several noisy alternatives against a fixed threshold;
with paired differences averaged instead, it disappears.

## 2. A new fit, and why it was not enough on its own

`ghost terms` replays each studied position (`ImproveLine` is deterministic)
and records every `EvaluationWeights` term of the position after each branch.
`fit.py` regresses branch win share on those terms with a fixed effect per
decision: what the rollouts say each term is worth. On 154 decisions the
evaluation explained R² 0.006 of the win differences, so no term was
significantly off. The nearest hints were dev cards held (implied 1.24 vs
0.256), variety (1.32 vs 0.128) and road length (-0.27 vs 0.089).

## 3. Weight screens (every chair vs three `openingOreGrainV1`, 640 games each)

| arm | seeds | win % | 90% |
|---|---|---|---|
| devCardHeld 0.5 | 2400000-159 | 21.6 | [19.4, 23.7] |
| variety 0.4 | 2400000-159 | 22.5 | [20.5, 24.5] |
| roadLength 0.03 | 2400000-159 | 26.1 | [23.6, 28.6] |
| all three | 2400000-159 | 21.6 | [19.1, 24.2] |
| roadLength 0 | 2410000-159 | 27.8 | [25.3, 30.3] |
| roadLength 0.03 | 2410000-159 | 26.7 | [24.5, 29.1] |
| roadLength 0.05 | 2410000-159 | 23.4 | [21.4, 25.6] |
| devCardHeld 0.15 | 2410000-159 | 24.7 | [22.8, 26.6] |
| variety 0.06 | 2410000-159 | 25.5 | [23.3, 27.7] |

The rollout fit's two strongest hints both cost real strength over whole
games: **the shipped devCardHeld and variety weights are right.**

## 4. Confirmation of the nominee, roadLength 0: no gain

| opponents | seeds | games | roadLength 0 | today's Expert |
|---|---|---|---|---|
| three `openingOreGrainV1` | 2420000-1199 | 4,800 | **25.0% [24.1, 25.9]** | 25% by symmetry |
| three Classic | 2440000-311 | 1,248 | 87.9% [86.3, 89.5] | 89.0% [87.5, 90.5] |
| three pcc Experts | 2450000-311 | 1,248 | 35.6% [33.2, 37.9] | 30.9% [28.6, 33.4] |

Not promoted: the screen's 27.8% was the best of nine arms. It does change
the plan - Longest Road 6% of games against 31%, more cities (1.68 vs 1.48),
dev cards (4.86 vs 3.94) and Largest Army (30% vs 20%) - and that plan beats
older Experts, but not today's.

## What this settles

- Expert's mid-game decisions, judged against its own candidates, are sound;
  its one-ply evaluation sits at or near a local optimum of the weights tested.
- Rollouts at 16 per branch are too noisy to fit weights directly (R² 0.006).
  A fit worth trusting needs thousands of decisions; screen in whole games.
- Do not retry devCardHeld or variety upward, or roadLength 0 alone.

## Tools added

- `ghost improve --rolls lo-hi --all-seats`: study a phase, every Expert seat.
- `ghost terms`: evaluation terms per studied branch, for fitting.
- `ghost duel` seat `weights:name=value,...`: today's Expert with changed weights.
  `TimingPolicy`, `TradeGuardPolicy` and `OpeningPolicy` take optional
  weights / inner policies for this; every shipped revision is unchanged.

Scripts and results: `~/Library/Caches/empires-analysis/midgame/`.
