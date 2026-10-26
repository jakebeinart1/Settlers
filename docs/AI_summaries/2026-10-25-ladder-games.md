# The ladder's 63 games: why humans beat Expert, and what changed

2026-10-25. The first day every ranked game could be read on a Mac
(`scripts/cloudkit-games.py`, Alex's server key). Jake asked: check the wins
(Kbeast and everyone), make the ghosts better, and make Expert much better
than the humans.

## Who wins

63 ranked games, all decisive. Per seat, replayed through the engine
(`ghost ladder`):

| Seat | Games | Win rate (95% Wilson) |
|---|---|---|
| Kbeast | 25 | **84.0%** [65.3, 93.6] |
| Bein (Jake) | 23 | 52.2% [33.0, 70.8] |
| Chandy | 10 | 40.0% [16.8, 68.7] |
| Kylesito | 3 (vs Classic) | 0/3 |
| Expert, per seat | 155 | 12.9% [8.5, 19.1] |
| Kbeast's ghost | 10 | 0/10 |
| Jake's ghost | 6 | 1/6 |

**No human has played today's Expert.** Replaying each game's Expert seats
through every revision (`ghost revision`) matches every game to `legacy`,
`cityProductionV1` or `pointCompletingCardsV1` at 99-100% agreement; none to
`timingOneAheadV1`, which reaches phones with the next TestFlight build.

## How Kbeast wins (per game, his seat vs the Experts at his tables)

| | Kbeast | Expert |
|---|---|---|
| Cards per turn from dice | 3.24 | 2.89 |
| Dev cards bought | 5.5 | 3.5 |
| Cards lost to sevens | 3.8 | **8.3** |
| Bank trades | 6.2 | 3.3 |
| Longest Road at the end | 60% | 20% |
| Opening: pips / resource types | 20.2 / 3.9 | 19.1 / 4.7 |

Two table-level leaks, both from the bots' side:

- **The robber misses the human.** When the human truly led, the robbing
  Expert's evaluator named someone else its strongest rival 33% of the time
  (194/288), while public points named the human 87% (251/288). Experts
  robbed each other three times for each time they robbed Kbeast.
- **Trades feed the human.** Of 140 offers Experts accepted from humans, 60
  were followed by a settlement or city that same turn (`ghost refusals`).

## Expert: what was tried

Bot-strength protocol (`ghost duel`): 4 players, randomized board, candidate in
every chair vs three of today's Expert (`timingOneAheadV1`), whole-seed 90%
bootstrap. Screen seeds 1100000-1100199 (800 games, nominate at >= 26.5%);
confirmation on held-out 1110000-1110311 (1,248 games), promote only if the
interval clears 25%. Protocol written before each run
(`~/Library/Caches/empires-analysis/PROTOCOL.md`).

| Arm | Screen | Confirmation |
|---|---|---|
| Robber and knights on the threat leader | 24.9 [23.1, 26.6] | - |
| Refuse every trade the leader proposes | 26.2 [24.6, 27.9] | - |
| Both | 26.2 [24.2, 28.2] | - |
| Opening ignoring resource variety | **15.5** [13.2, 17.9] | - |
| Refuse trades that let a level-or-ahead proposer build (half a card slack) | 25.2 [23.4, 27.3] | - |
| Same, plus refuse the leader | 25.8 [23.8, 27.8] | - |
| Jake's "refuse if it helps them more" (standing gains + a build) | 24.2 [22.1, 26.5] | - |
| **Opening on the most pips (within 1)** | **28.6** [26.1, 31.2] | 26.5 [24.5, 28.5], not promoted |
| **Refuse build-enabling trades (1 card slack)** | **27.6** [25.5, 29.8] | 25.6 [24.0, 27.3] |
| Pips opening + trade refusal | - | 27.0 [24.9, 29.0], not promoted |

The pips opening reproduces the human edge it was built from (3.42 vs 3.09
cards a turn), and against three Classic bots (seeds 1120000-1120199) pips won
88.6% and pips + refusal 89.4%, against 86.2% for today's Expert. Its held-out
interval still touches 25%, so it is not promoted.

**What shipped:** `ExpertRevision.timingTradeGuardV1`, today's timing Expert
plus the trade refusal, on Jake's instruction ("just reject those trades if
the bot would know that it would be more helpful for the opponent. But like no
data leaking"). It reads only the public ledger: the proposer's believed hand,
public points, and dev-card count. Against real ladder games it refuses 75 of
the 140 trades Experts took from humans, 37 of the 60 that fed a build. Among
bots it costs nothing (screen above). That is a measured no-loss and a measured
effect on human trades, **not** a confirmed strength gain.

**What did not happen: "Expert much better than the humans."** Every rule here
moves self-play by 0-3.6 points; Kbeast beats three Experts 84% of the time.
That gap is not a rule away. The next real measurement is free: the next
TestFlight build seats `timingTradeGuardV1` against people for the first time.

## Ghosts: the choice model was too weak to ship as it was

Ghosts on `main` play by their person's fitted choice model (`f8005f7`). On the
ladder's games, every chair vs three `pointCompletingCardsV1` Experts (the
Expert people faced), seeds 1200000-1200099:

| Ghost | Win rate | Person's real rate | Knights / game |
|---|---|---|---|
| Kbeast | 2.2% [1.0, 3.8] | 84% | 0.21 (Kbeast 2.6) |
| Bein | 1.8% [0.8, 2.8] | 52% | 0.00 |
| Chandy | 15.5% [12.5, 18.8] | 40% | 0.23 |
| Kylesito | 1.8% [0.8, 3.0] | 0/3 | 0.24 |

Cause: the fitted weight on Expert's score at the kind step is ~0.001, so
"build a city or end the turn" is decided by habit features alone.

**Fix: `GhostPolicy.choiceRegret = 0.15`.** The person's model picks only among
moves Expert scores within 0.15 of its best. Held-out fidelity (4-fold by game)
and strength:

| | Fidelity Kbeast / Bein | Win rate Kbeast / Bein |
|---|---|---|
| Expert alone | 58.8% / 62.4% | 25% by symmetry |
| Regret 0.05 | 63.3% / 67.4% | 27.2% / 28.0% |
| **Regret 0.15 (shipped)** | **70.4% / 74.4%** | **28.5% / 24.5%** |
| Regret 0.3 | 73.9% / 78.3% | 23.0% / 27.2% |
| Regret 0.6 | 74.6% / 79.8% | 13.2% / - |
| Unrestricted (was on main) | 76.5% / 82.4% | 2.2% / 1.8% |

At 0.15 the other two: Chandy's ghost wins 24.2% [20.5, 28.0] and matches him
64.5% (Expert 54.1%); Kylesito's wins 13.5% [10.8, 16.2] and matches him 59.8%
(Expert 36.6%) - weaker than Expert, as he is (0 of 3 against Classic).

Every ladder player who has faced Expert beats it more often than Expert
does, so the limit is set where ghosts still play at Expert strength.
A ghost cannot yet reach Kbeast's 84%; nothing that exists can.

## Tools added (`Packages/CatanAI/Sources/ghost/`)

- `ghost ladder GAME.json...`: one line per seat: who, won, how points were made.
- `ghost revision GAME.json...`: which Expert played a game's bot seats.
- `ghost leader GAME.json...`: at each Expert robber move, believed vs true leader.
- `ghost refusals GAME.json...`: each human trade an Expert accepted, and
  whether the trade guard would refuse it.
- `ghost duel --candidate C --anchor A --seed S --seeds N [--lone]`: the
  bot-strength protocol for policies `sim` cannot name (choice ghosts,
  `trade-guard`), with per-seat behaviour in every line. The screened rules
  that did not ship, and `leader-<rules>` to rerun them, are on branch
  `exp/ladder-arms`.
- `ghost fidelity --cv 4 --regret R|none`.
