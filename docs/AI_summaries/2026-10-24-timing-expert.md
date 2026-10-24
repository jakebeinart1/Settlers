# Timing Expert: one ahead, a knight before the roll, lean hands

2026-10-23/24. New Expert revision `timingOneAheadV1` (`TimingPolicy.oneAheadV1`),
now the brain for new four-seat, 10-point, randomized-board Classic Expert games.
Fixed-board games keep `cityProductionV1`; every other table keeps `legacy`;
saved games keep the revision they started with.

## Why

Jake asked why the Expert loses to humans on the ladder (41 rated games on his
phone: Expert 13% per seat; Kbeast 8/10 vs three Experts; Jake 11/20), and then
whether the Expert plays its cards **at the right times**. His rule: stay
exactly one knight (and one road) ahead, because a bigger lead is wasted and a
one-step lead wins games.

## What was tried and failed first

All 4 players, randomized board, candidate in every chair vs three
`pointCompletingCardsV1` Experts, 800 games per arm, controls exactly 25.0%.

| Arm | Win rate |
|---|---|
| Blending Kbeast's / Jake's ghost into Expert (lambda 0.01-0.2) | 24.1% down to 13.9% |
| Knight weight x2 / dev-card weight x1.5 | 23.5% / 23.9% |
| Road weight x2 / x0.5 | 25.8% / 23.5% |
| Situational weights (race, phase, standing, economy, all) | 23.1-25.5% |
| Timing: hold knights / lean hands alone | 23.4% / 23.9% |
| Timing: knight before the roll alone | 25.8% |
| Jake's one-ahead rule alone | 26.1% |
| **One ahead + knight before roll + lean hands** | **28.5%** |

Valuing knights more does not help; *when* they are played does.

## What the timing data showed

800 Expert self-play games vs Jake's 13 finished games (replayed from `GameLogs`):

- The Expert **never** played a knight before rolling: `EvaluationPolicy.decide`
  returns `.rollDice` whenever it is legal. Jake did 0.46 times a game.
- The robber sat on a seat's own tile in ~43% of its rolls.
- Expert winners lost **8.4 cards a game** to sevens; Jake lost 4.7.
- Expert knights came early (first quartile round 6-7); Jake's mid-game (9.5-14).

Kbeast's own move timing could not be studied: only his SeatStats sync to
Jake's phone (LiveSync drops moves). His phone would have to be read directly.

## The rules (`TimingPolicy`)

- **margin** (Jake's): a knight that takes Largest Army, or turns a tie back
  into a one-knight lead, is played at once; past a one-knight lead knights are
  held. Holding Longest Road two or more segments ahead, road length is worth
  nothing; within one segment either way, double.
- **preroll**: a knight before the roll when the robber blocks one of this
  seat's tiles, or when it wins.
- **lean**: a turn that would end on more than five cards spends instead, when
  anything can be bought.

## Evidence (bot-strength method, protocols declared before each run)

| Check | Games | Result |
|---|---|---|
| Screen, seeds 975000-975199 | 800 | 28.5%, 90% [26.2, 30.9] |
| **Confirmation, held-out seeds 985000-985311** | **1,248** | **28.5%, 90% bootstrap [26.9, 30.2]**, all decisive |
| vs three Classic `balanced` bots, seeds 986000-986199 (paired with the old Expert) | 800 + 800 | 89.0% vs 85.1%, paired +3.9 pts, 90% [+1.6, +6.2] |
| vs older Experts (legacy v1, city-production, round-3), seeds 987000-987199 | 800 + 800 | 30.9% vs 28.7%, paired +2.1 pts, 90% [-1.0, +5.1] - inconclusive, not worse |

Per chair in confirmation: 99, 89, 89, 79 wins of 312. The shipping build's
fingerprints match the confirmation run (seed 985000: `6d2b27c3f2673b1f`,
`ce7a17e5bc52b12d`).

Scope: claims cover four-seat randomized boards only, which is exactly where the
revision is selected. Three-seat and fixed-board tables were not tested and do
not get it.

## Gotchas found on the way

- `sim --build-id` rejects `+`; the first `preroll+hold` arms exited without
  playing. Use `_` in build ids.
- A `pgrep -f "winpaths play"` wait loop matches its own command line and
  waits forever. Use `pgrep -x <name>` or a marker file.
