# Expert's own mistakes, found by rollouts: the opening

2026-10-28. Jake asked how Kbeast keeps winning (77% with the restart
penalty), then reframed it: "its not about making the experts beat him. It is
about making the experts best." So the method changed from copying a person to
finding where Expert's own choices lose, by playing positions out.

## Kbeast, against today's Expert

77 ranked games on CloudKit (Kbeast 33, Bein 29, Chandy 10, Kylesito 3, Noah 2).
Kbeast is 24/33 overall but **2/6 against today's timing Expert**; Bein 3/6.
Per game, his seat vs the Experts at his tables:

| | Kbeast | Expert |
|---|---|---|
| Cards per turn from dice | 3.27 | 2.94 |
| Dev cards bought / knights | 5.5 / 2.7 | 3.2 / 1.6 |
| Largest Army / Longest Road at the end | 45% / 48% | 11% / 16% |
| Cards lost to sevens | 4.3 | 7.8 |
| Cities | 1.7 | 1.2 |

20 of his 24 wins hold the Army or the Road. He reaches 8 public points later
than Expert (roll 69 vs 63) and then surges on hidden points and a title swing.

**`ghost shoes`**: at each of his decisions where Expert would have played
differently (527, in 12 games against today's Expert), both moves were played
out 16 times with every seat Expert afterwards. His move won **+0.8 ± 1.0
points** more: no single move is the edge. His edge is a plan across a game,
not a better move at any one moment, and a plan cannot be copied move by move.

## Expert's mistakes in its own games

**`ghost improve`**: today's Expert in one chair, against itself, older Experts
(legacy/cityProduction/pointCompletingCards; timing/timing/pcc) or the
Kbeast/Bein/Chandy choice ghosts. At a sample of its decisions, its move and
its next two candidates are each played out 24 times on shared dice (opponents
keep their own policies). 43 games, 408 decisions:

| | decisions | best alternative gains | lead of 4+ wins in 24 |
|---|---|---|---|
| All | 408 | +2.4 ± 1.0 points | 10.3% |
| vs itself / old A / old B / ghosts | 132 / 105 / 80 / 91 | | 6.8 / 10.5 / 13.8 / 12.1% |
| Opening settlement | 22 | | 18.2% |
| Rolls 11-20 / after 30 | 26 / 268 | | 19.2 / 7.8% |

Taking the better of two noisy alternatives biases the gain up; no table
breaks Expert. The opening stood out, so it got its own run.

## What wins an opening

`ghost improve --openings`: every seat's opening settlements, Expert's top seven
spots each, 16 shared-dice rollouts per spot. 13 games, 104 placements. Fitting
the win rate within each placement (board luck cancels):

| Per unit | Win rate (± 95%) |
|---|---|
| Pip | +1.49 ± 0.50 points |
| Ore or grain pip, on top | **+1.38 ± 0.36** |
| Brick+lumber / wool pip, on top | -0.02 / +0.13 |
| Resource type, any | +0.4 ± 3.1 |
| New resource type, 2nd settlement | **+4.3 ± 3.2** |
| Port | +3.4 ± 3.4 |

Expert's spot won 25.2%, most-pips 24.3%, most-types 24.3%. Expert picked the
best of its seven only 30/104 times, but that is rollout noise: with 16 rollouts
the luckiest of seven reads ~15 points high, the whole gap. Expert's placement
score values every pip alike and pays 0.5 per type for variety, which earns
nothing here.

## The fitted opening, measured

`OpeningPolicy`: pips + 0.85 per ore or grain pip + 3.3 per new type on the
second settlement; every other move is the trade-guard Expert's. Frozen binary,
four seats, every chair against three `TradeGuardPolicy.v1`, 90% bootstrap over
whole seed families, promotion predeclared as the interval wholly above 25%:

| Run | Seeds | Games | Win rate | 90% |
|---|---|---|---|---|
| Screen | 1360000-1360311 | 1,248 | 26.6% | [24.4, 28.9] |
| **Confirm** (sized for +1.6 points) | 1370000-1371199 | 4,800 | **27.5%** | **[26.3, 28.6]** |

All games decisive. In the screen it opened on 20.4 pips and 4.0 types (Expert
19.2 and 4.8) and built 1.84 cities a game (Expert 1.36). That is close to
Kbeast's own opening on the ladder (20.2 pips, 3.9 types, 2026-10-25). The
pips-only opening screened in October confirmed at 26.5% [24.5, 28.5] and was
not promoted; ore and grain, plus new types on the second settlement, are the
difference.

Secondary opponents, same frozen binary, seeds 1380000-1380311, every chair
(today's Expert in the same chairs as the baseline):

| Three opponents | New opening | Today's Expert | Paired difference (90%) |
|---|---|---|---|
| Classic (balanced) | 89.8% | 87.7% | +2.2 [+0.2, +4.2] |
| pointCompletingCards Experts | 36.5% | 30.4% | +6.0 [+3.0, +9.1] |

1,248 games per cell, all decisive. Better against both, so the gain is not an
exploit of the trade-guard Expert alone.

## What shipped

`ExpertRevision.openingOreGrainV1` (`OpeningPolicy.v1`), selected for new
four-seat randomized Classic Expert games. Saved games keep their revision.
The library policy replays the frozen test binary's games move for move
(12/12 checked).

## Tools

In `ghost`: `shoes` (a person's moves vs Expert's, played out), `improve`
(Expert's choices vs its next-best, `--openings` for placements), and `duel`
seats `opening[:og,new]` for sweeping the two weights. Analysis scripts and data
live in `~/Library/Caches/empires-analysis/shoes/` (not committed).

## Next

Rolls 11-20 are the next-highest mistake rate (19%). The same rollout method
applies; human games (`ghost shoes`) are only a source of moves Expert never
lists.
