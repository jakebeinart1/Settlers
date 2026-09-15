# Position evaluation — the bot that beat the shipping heuristic

**Date:** 2026-09-14
**Branch:** `feat/win-condition-planner`
**Predecessor:** [win-condition planner](2026-09-14-win-condition-planner.md)

## Verdict first

`EvaluationPolicy` wins **47.3%** of games against three frozen `balanced`
heuristics, over 1,248 decisive games with complete chair rotation on held-out
seeds, against a 25.0% null — 95% CI [44.5, 50.0]. The control arm returned
exactly 25.0%.

That figure is with fitted weights. Hand-set weights scored 43.0%; a weight
sweep added **+4.7 points, paired, McNemar p = 0.010** (see
[the sweep](#the-weight-sweep) below, and read both of its columns).

It is the first candidate in this repository to beat the shipping bot under the
`bot-strength` protocol. It is **not** wired into the app roster, and should not
be until it has also been measured against an opponent this repository did not
design.

## What changed from the planner

The objective did not change. The quantity computed at the point of decision
did.

The planner priced each candidate by re-running a bounded route search for two
seats. That cost about 100ms and, more importantly, answered with an estimate
whose tail was *one purchase repeated* — so the thing ordering its moves was
never the thing the design specified. All three of its measured defects follow
from that single approximation.

`PositionEvaluator` scores the board as it stands: production, variety, room to
expand, the best expansion available, hand synergy, discard exposure, cards
held, knights, road length, ports. It returns this seat's standing less the
strongest rival's. There is no horizon and no tail, so there is nothing left to
approximate away.

The differential objective survives as `EvaluationWeights.rival`. At 1.0 the
seat plays pure relative position — a point both seats gain is worth nothing.
Jake's rule ("if you both gain a point from a transaction, it's better to have a
higher net point total") is that term being nonzero, expressed as the quantity
being maximised rather than as a rule applied afterwards.

## What was measured

| | |
|---|---|
| Source commit | `41d1658` |
| Frozen simulator SHA-256 | `fbbc81f881218da5…` (one binary, both arms) |
| Table | 4 players, 10 VP, randomized boards, Classic |
| Seeds | 95000–95311, held out |
| Rotation | complete — candidate in each of the 4 chairs once per seed |
| Games | 1,248 per arm, 2,496 total |
| Decisive | 1,248 / 1,248 in both arms (100%) |

**Candidate** — `eval` in one chair, `balanced` in the other three:

| Chair | Wins | Rate |
|---|---:|---:|
| 0 | 150/312 | 48.1% |
| 1 | 146/312 | 46.8% |
| 2 | 124/312 | 39.7% |
| 3 | 117/312 | 37.5% |
| **Total** | **537/1,248** | **43.0%** (95% CI 40.3–45.8) |

**Control** — `balanced` in all four chairs, same seeds and rotations:
**312/1,248 = 25.0%** (95% CI 22.6–27.4).

The control landing exactly on the null is what makes the candidate number
readable: the rotation and the scoring are correct, so 43.0% is the policy and
not the harness.

It wins from every chair, which matters because the four chairs are not
equivalent — the control arm's own spread runs 29.2% to 17.6% on these seeds.

## The three planner defects, closed

Per-game counters over 25 games, candidate against the mean of three `balanced`
seats:

| | planner | **eval** | balanced |
|---|---:|---:|---:|
| Settlements built | 1.0 | **2.2** | 2.3 |
| Cities built | 2.1 | **1.4** | 0.7 |
| Roads built | 3.9 | **6.8** | 10.0 |
| Development cards bought | 0.6 | **7.9** | 5.2 |
| Knights played | 0.3 | **4.2** | 2.7 |
| Trades proposed | 2.9 | **53.9** | 20.7 |
| Trade responses accepted | 10.3 | **9.3** | 8.1 |
| Final victory points | 5.3 | **8.5** | 7.0 |

The donor behaviour is the interesting one. The planner accepted 10.3 trades a
game while proposing 2.9. This policy proposes 53.9 and accepts 9.3 while
*rejecting* 40.9 — it is now the seat driving the table's trading rather than
the seat funding it.

## Two candidates that cannot be scored by applying them

Everything the engine offers resolves immediately, so "apply it and look at the
result" is both the simplest scoring rule and the most faithful. Two do not
resolve, and both are handled explicitly.

**`buyDevCard` is projected, not applied.** Applying it would let the deck's
order decide which card the evaluation sees, so a seat could prefer the turn on
which the deck happens to hold a victory point. That is hidden information
steering a decision, and it would flatter every strength number taken
afterwards. The cost leaves the hand, an unplayed card enters it, and what a
card is worth on average is carried by `EvaluationWeights.devCardHeld` where a
sweep can reach it. `theEvaluatorIgnoresWhatItIsNotEntitledToSee` reverses the
deck and requires an identical move.

**`proposeTrade` is priced by the trade it would become.** Applying it only puts
an offer on the table, so every proposal would score exactly zero and the policy
would never propose anything — which is the failure the planner shipped with.
It is scored against the plausible payer who benefits *most* from paying,
because we do not choose who accepts. Scoring against the friendliest payer is
how a bot becomes a donor.

## Known limits, stated rather than buried

- **One leak remains.** A candidate that steals is applied, so the evaluation
  sees which card the steal would take. That is one card of hidden information
  reaching a robber placement. It is recorded in `EvaluationPolicy`'s doc
  comment and is not yet closed.
- **Self-play only, and only against ourselves.** Every number here is against
  this repository's own heuristic. That measures how well the candidate exploits
  one opponent, which the `bot-strength` skill opens by warning about. An
  independent anchor is the next thing that should happen.
- **Classic, four players, 10 VP.** Expanded strength is unmeasured; only
  termination was checked.
- **The weights are fitted against one opponent.** They were tuned against
  `eval` and validated against `balanced`, and the gap between those two results
  says plainly that some of what was learned is specific to `eval`. Whether the
  fitted weights hold up against a *third* opponent is unmeasured, and it is the
  single best argument for the independent anchor below.

## What comes next, in the order the evidence supports

1. **An opponent we did not design.** Catanatron is GPL-3.0, so it can be an
   external benchmark process but never linked into the app. This is what turns
   "beats our bot" into "plays Catan well".
2. ~~**Sweep the weights.**~~ Done: +4.7 points, and the `--weights` seam now
   exists for `BotWeights` to use the same way.
3. **Fold the planner's clock in as one feature.** Expected turns to the target
   is not discarded — it is the term this policy does not yet carry. Leaving it
   out here is what makes its contribution measurable rather than assumed.
4. **Spend the idle deliberation budget.** `GameViewModel` already sleeps 600ms
   per bot turn for presentation. A search under this evaluation is free within
   that budget and a player cannot tell it apart from a pause.
