# Win-condition planner — delivery and measurement

**Date:** 2026-09-14
**Branch:** `feat/win-condition-planner`
**Design:** [spec](../superpowers/specs/2026-09-14-win-condition-planner-design.md)

## Verdict first

The planner is **built, tested, deterministic, information-clean, and
substantially weaker than the bot that ships.** Measured over 1,248 decisive
games with full chair rotation against three frozen `balanced` heuristics, it
won **1.6%** of games against a 25.0% null — 95% CI [0.9, 2.3].

It is not wired into the app roster and must not be until it beats the anchor.

This is the third candidate in this repository to look right and lose badly
(after bounded rollout search at −27.5 points and the imitation policy at 0/40),
and it is the reason the measurement protocol exists.

## What was measured

| | |
|---|---|
| Source commit | `dade2da` |
| Frozen simulator SHA-256 | `e45771380aaa479d…` (one binary, both arms) |
| Table | 4 players, 10 VP, randomized boards, Classic |
| Seeds | 90000–90311, held out (never used in development) |
| Rotation | complete — candidate in each of the 4 chairs once per seed |
| Games | 1,248 per arm, 2,496 total |
| Decisive | 1,248 / 1,248 in both arms (100%) |

**Candidate arm** — planner in one chair, `balanced` in the other three:

| Chair | Wins | Rate |
|---|---:|---:|
| 0 | 3/312 | 1.0% |
| 1 | 5/312 | 1.6% |
| 2 | 5/312 | 1.6% |
| 3 | 7/312 | 2.2% |
| **Total** | **20/1,248** | **1.6%** (95% CI 0.9–2.3) |

**Control arm** — `balanced` in all four chairs, same seeds and rotations:
**312/1,248 = 25.0%** (95% CI 22.6–27.4), chairs at 26.9 / 25.0 / 23.7 / 24.4.

The control landing exactly on the null is what makes the candidate number
trustworthy: the rig, the rotation and the scoring are correct, so 1.6% is the
policy and not the harness.

## Why it loses — diagnosed, not guessed

Behaviour counters, 25 games, per-game averages:

| | planner | balanced (mean of 3) |
|---|---:|---:|
| Roads built | 3.9 | 10.4 |
| Settlements built | 1.0 | 2.3 |
| Cities built | 2.1 | 0.7 |
| Development cards bought | 0.6 | 6.9 |
| Knights played | 0.3 | 3.3 |
| Trades proposed | 2.9 | 20.6 |
| **Trade responses accepted** | **10.3** | **4.5** |
| Final victory points | 5.3 | 7.7 |

Three distinct defects, each traceable to a specific modelling choice:

**1. It tunnels on cities and stops expanding.** The tail estimate prices the
remaining victory points by simulating the *same* purchase repeated. Cities have
the best turns-per-point ratio once ore and grain flow, so the estimate is
always a stack of cities — and a route that is all cities needs no roads and no
new settlements. Real routes are mixed. The estimate needs to price a *mix*, or
the search's own first purchases will always be chosen to serve a fiction.

**2. It never buys development cards.** A card is priced at its expectation over
the deck, about 0.2 victory points, which loses to a settlement on every
comparison. But the knight path to Largest Army — worth 2 points in Classic and
4 in Expanded — is not credited in the tail estimate at all, so the whole Largest
Army route is invisible to the very estimate that decides what the route is.
0.3 knights per game against 3.3 is that omission, directly.

**3. It is the table's donor.** It accepts 10.3 trades per game against the
heuristic's 4.5, while proposing almost none. The acceptance test is
`Δadvantage > 0` evaluated over a bounded horizon with contest pricing off, and
at that fidelity almost any incoming offer reads as positive. The differential
objective was supposed to make it *selective*; instead the approximation used at
the point of decision is too coarse to see what it is giving away.

All three share a root: the quantity used to *decide* is not the quantity the
design specifies. The full planner is only consulted for a route that nothing
reads; every actual decision runs on a bounded estimate whose tail is a
single-purchase extrapolation.

## What is nonetheless established and worth keeping

- **The exact planner as a test oracle works, and immediately earned its place.**
  On its first run it caught the beam returning a walkable, plausible route that
  was nine expected turns worse than optimal, because deduplication was
  interleaved with beam diversity selection and the cheap path to a node was
  discarded as a duplicate of the expensive one.
- **Public-information play is enforced, not intended.** `PublicLedger` counts
  cards from per-seat masked events; `GameEvent.masked(for:)` closes the
  stolen-resource leak the engine's own doc comment described.
  `thePlannerIgnoresWhatItIsNotEntitledToSee` scrambles every opponent hand and
  the deck order and requires an identical move.
- **A fifth instance of the dictionary-ordering determinism defect was found and
  fixed at the source.** `ProductionRate` now stores slots positionally;
  as a `[Resource: Double]` its `total` summed `values` in per-process order and
  diverged seeded games.
- **Both modes terminate.** Classic and Expanded games both reach a winner,
  including the 25-point mode where the shipping heuristic failed to finish 2 of
  20 measured games. That is not a strength claim — a bot that loses quickly also
  terminates — but the Expanded closing machinery exists and runs.
- **The simulator can now measure this class of change.** `sim` gained a
  `planner` seat and `--mode classic|expanded`, which is what made a 1,248-game
  rotated measurement a twenty-minute job.

## What a next iteration would have to change

In the order the evidence supports:

1. **Price a mixed route in the tail estimate**, not a repetition of one
   purchase. This is defect 1 and probably feeds 2.
2. **Credit the bonus routes in the estimate** — Largest Army and Longest Road
   are worth 2 and 4 points and are currently invisible to it.
3. **Raise the fidelity of trade acceptance specifically**, or accept fewer
   trades by construction until the estimate is good enough to be selective.
4. Re-measure against the same frozen anchor on a *fresh* held-out seed range.
   Seeds 90000–90311 are now spent.

## Honest limits

- Four players, 10 VP, randomized boards, Classic only. Expanded strength is
  unmeasured; only termination was checked.
- Self-play only. It says nothing about how any bot feels to a human, which is
  still the open backlog item.
- The measurement is powered for a 5-point difference. It did not need to be:
  the effect is 23 points in the wrong direction.
