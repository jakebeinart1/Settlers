# Win-condition planner — design

**Date:** 2026-09-14
**Status:** implemented; measured at 1.6% against a 25% null and **not shipped** — see the [delivery note](../../AI_summaries/2026-09-14-win-condition-planner.md)
**Branch:** `feat/win-condition-planner`

## The problem

Every bot in the app is `HeuristicPolicy` → `Bot.decide`: a one-ply, hand-weighted
scorer with no plan, no lookahead, and no opponent model. The repository's own
audit names the gap — "no persisted strategic objective, route reservation across
turns, adversarial lookahead, probabilistic rollout, learned value, or explicit
multi-turn plan" (`2026-09-05-current-ai-baseline.md`, §7).

Two measured consequences:

- **Classic (10 VP)** — competent but shallow. Road networks fragment (a 90-game
  audit found 53 fragmented networks, 8–9 dead tips per bot).
- **Expanded (25 VP)** — it cannot *close*. 2 of 20 measured games never finished
  inside the cap; the earlier 12-VP calibration showed the same signature, every
  seat parked at 11 points with the deck exhausted. A greedy per-turn scorer has
  no representation of "a path to 25", so the late game churns.

Prior attempts at the learned shortcut both failed and were removed: bounded
rollout search lost by 27.5 points, and an imitation policy that improved
top-1 accuracy from 31.5% to 42.4% went **0/40** in real games. The linear value
function failed its gate twice (67.7% sign accuracy against a 74.0% baseline).

The conclusion those results support is not "learning does not work here" but
"there is no usable value function yet". This design computes one instead of
learning it.

## The objective

The planner does **not** minimise its own turns to victory. It maximises a
differential:

```
advantage(seat) = min over opponents(clock(opponent)) − clock(seat)
```

where `clock(x)` is the expected number of that seat's turns to reach the game's
victory-point target along its cheapest route.

Everything else in this design falls out of that one choice:

- A trade that cuts my clock by 1 and the leader's by 2 scores **−1** and is
  refused, even though it helps me.
- The same trade offered to the trailing player scores better than to the leader.
- A contested settlement is worth *my gain plus their denied gain*, so a road
  that costs me 1 turn and costs an opponent 3 beats a city that saves me 2 and
  costs them nothing.

The current bot computes the absolute quantity, which is exactly why it builds
the city and loses the spot.

## Information contract

The planner reads **public information only**. This is a deliberate strength
constraint and it also makes any measured result an honest one: today's bot reads
exact opponent hands in Monopoly targeting, trade evaluation and threat scoring.

`GameObservation.state` is the full `GameState`, so the constraint is enforced by
construction rather than by discipline — the planner consumes a `PublicLedger`
and a small set of state fields that are genuinely public (board, buildings,
roads, played knights, bank, public VP, pending offers), and never touches
`players[i].resources`, `players[i].devCards`, or `devCardDeck` for any seat but
its own.

### Deterministic card counting

`PublicLedger` tracks, per seat, an exact known resource multiset plus a count of
cards whose identity is genuinely unknown. It is folded from the `GameEvent`
stream, which is already structured and already has the right public/private
split (`PrivateGameEvent` keeps dev-card faces out of it).

Knowable exactly: roll payouts, build and purchase costs, bank/port trades,
Year of Plenty, Monopoly, and the terms of every accepted player trade.
Genuinely unknown: robber and knight steals, dev-card faces, and any card spent
out of an unknown pool.

Two engine changes support this:

1. `GameEvent.masked(for:)` — `movedRobber(..., stealing:)` and
   `playedKnight(..., stealing:)` currently expose a resource the doc comment
   itself describes as one "only the engine knows". Masked to `nil` for every
   observer except the thief and the victim.
2. `LedgerAwarePolicy` — a second protocol beside `Policy`. `GameSession` keeps
   one ledger per seat, folds every applied move's masked events into it, and
   hands the acting seat's ledger to any policy that adopts the protocol. Ledgers
   are persisted in the session checkpoint, so a resumed game does not silently
   reset every belief; an older checkpoint decodes with none and rebuilds from
   the position alone.

The ledger is small (five counts plus two integers per seat), so persisting it
costs nothing like the `log: [String]` field that was removed from `GameState`
for copy cost.

**The ledger is deliberately not a field on `GameObservation`.** That looked
simpler and is not: the observation is `Codable` and `Equatable`, it is stored
inside a checkpoint's queued trade response, and `Checkpoint.validate()` asserts
the stored observation matches the session's state — a belief folded from a
different history would fail that check and reject a good save. It is also
serialised into every exported training example, where it is not wanted.

Two bounds, not one. `known` is a floor of resources a seat certainly holds and
`maxTotal` a ceiling on hand size. Hand size is public at a real table, so the
ceiling is taken from the position and is exact. The floor degrades where
information genuinely does: an unattributable card leaving a hand lowers *every*
resource in the floor, because the card taken could have been any of them.

## Cost model — expected turns

### Production rate

For a seat, the expected cards of resource `r` per turn is

```
rate(r) = Σ over tiles t producing r  pips(t) / 36 × buildingYield(t)
```

with `buildingYield` 1 per adjacent settlement and 2 per adjacent city, and
tiles under the robber contributing zero. `DiceOdds.pips` is the engine's
existing single source for the pip table.

### Time to afford

Expected turns to afford a cost vector `c`, holding hand `h`:

```
turnsToAfford(c, h) = max over r of  max(0, c[r] − h[r]) / rate(r)
```

The `max` over resources, not the sum, is the point: you cannot build a city out
of five wheat. A resource with `rate(r) == 0` and an unmet deficit is infinite
unless a conversion supplies it, which is what makes ports load-bearing.

### Bank and port conversions as edges

A seat's best rate for resource `r` is 4:1, 3:1 with a generic port, or 2:1 with
the matching resource port. Conversions enter the graph as edges so the planner
naturally concludes that a 2:1 ore port shortens the city route — rather than
scoring ports with a hand-tuned constant as the current `PlacementHeuristics`
does.

### Seven risk

Holding more than `Ruleset.discardThreshold` cards carries a real expected cost:

```
sevenCost(h) = P(7) × floor(|h| / 2) × (1 / totalRate)
```

converted into turns. This is not a decoration — it is what makes the planner
buy a development card at 8 cards to duck below the threshold, and it is why that
behaviour needs no special case.

## Route search

### Node

A node is deliberately *not* the full game state:

```
(victoryPoints, productionRate per resource, piecesLeft, knightsPlayed,
 roadLength, portsOwned, bonusesHeld)
```

Expected turns is a function of rates and deficits, not of an exact hand, so this
collapses an enormous state space into something dedupable.

### Edges

Purchases — road, settlement, city, development card — plus bank/port
conversions. Edge cost is `turnsToAfford` at the node's rates, and a settlement
or city edge *raises the rate at the destination node*, which is how the planner
discovers that an early city compounds.

Development cards are priced at their expectation over the mode's remaining
`devCardDeck` composition: knights advance the Largest Army route, victory-point
cards advance VP directly.

### Algorithm

**Bounded beam search** with explicit diversity preservation: each depth keeps
the best surviving node for every distinct last purchase before filling the rest
by rank, so the route that only pays off late — the Largest Army run, the long
road — cannot be pruned at depth 2 by whichever purchase happens to look cheapest
now. Beam width and depth are configuration, not literals.

Deduplication happens *before* diversity selection. Two routes buying the same
things in a different order reach the same node at different costs, and the
cheapest path to a node must be the one that survives.

The runtime does not call the full planner for every comparison. `estimate`
searches a bounded horizon and prices the remaining tail with the heuristic;
every candidate is measured the same way, so comparisons stay meaningful while a
decision stays affordable.

An **exact uniform-cost (Dijkstra) planner** ships alongside it as a test oracle,
not as a runtime path: on small and truncated cases, the beam result must equal
the exact result. That is the correctness gate — "the numbers look plausible" is
not one, and it earned its place on the first run by catching a beam that was
nine expected turns worse than optimal while returning a perfectly walkable
route.

### Contested targets and deadline races

A route step that competes for a board position or a bonus is priced as a swing:

```
value = myGain + theirDeniedGain × P(they get there first)
```

`P(they get there first)` is computed from public information: their distance to
the vertex in roads, their road pieces remaining, their counted hand, and seat
order. Longest Road and Largest Army use the same machinery — they are contested
resources with a clock — so there is one mechanism, not two.

A bonus race that cannot be won before an opponent claims it is priced at its
real value, which is near zero, rather than at its victory-point face value.

## Two layers: route and action

**Route** — the committed sequence of victory-point sources. Re-priced once per
turn, and switched only when an alternative beats it by a margin. This is the
plan object the audit says is missing, and the margin is what stops the churn
that produced today's fragmented roads.

**Action** — recomputed at *every* decision point. Among the currently legal
moves, take the one that most improves `advantage` given the committed route.

This split is what makes opportunism and commitment coexist. At 8 cards with a
development card affordable but not a city, the card advances the route *and*
deletes the seven cost, so it scores best. If the roll then completes the city,
the city is simply the best route-advancing action now available. The route never
changed; only what was affordable did.

## Trades

Both directions are priced by how they move both clocks.

**Inbound** — accept iff `Δadvantage > 0`: my clock improvement minus the
proposer's, where the proposer's improvement is measured **against their route,
not against their card count**. One lumber is usually near-nothing; one lumber
that completes a fifth road and takes Longest Road is two victory points and a
large clock drop. Card counting plus the opponent's route model is what separates
the two, and a bot that counted cards alone would walk into the second.

**Outbound** — propose the offer maximising `Δadvantage`, which naturally prefers
trading with a trailing seat over the leader.

Consequence, recorded deliberately: this accepts lopsided-in-our-favour offers
far more readily than the current scorer (which measures marginal value against
its own nearest build target and cannot tell that an offer is lopsided at all),
and refuses even-looking trades with the leader. Trade *volume* on marginal
offers drops. Volume is player-facing, so it is a tuning knob, not a discovery.

## Personality

The planner is pure and identical for every seat. Personality keeps its current
home — robber targeting, trade willingness, dialogue voice — and does not tilt
the route calculation.

Recorded risk: three bots that plan identically will play more alike than they do
now. A near-equal-route tie-break seam exists for diversity if that proves to be
the wrong trade.

## Modes

Classic and Expanded from the start. Every mode-specific quantity already comes
from `Ruleset` — `longestRoadBonus` (2 / 4), `largestArmyBonus`,
`longestRoadMinimum`, `largestArmyMinimum`, `devCardDeck`, `discardThreshold`,
`pieceLimits`, and the victory-point target — so the planner reads the rules
rather than hardcoding them. Expanded is the mode with the measured defect, so
excluding it would exclude the reason for the work.

Note that `StateEncoding` and `ActionSpace` remain Classic-only and are untouched
here; this design needs neither.

## Shipping and measurement

The planner ships as a **new `Policy`**, not an edit to `Bot`. The current
heuristic stays exactly as it is and becomes the frozen evaluation anchor.

It does not enter the app roster until it beats that anchor under the
`bot-strength` protocol: frozen anchor, paired held-out seeds, every-chair
rotation, table-size-aware power, confidence intervals. Improved plausibility is
not evidence — the repository has already paid for that lesson twice.

## Components

| Unit | Responsibility |
|---|---|
| `GameEvent.masked(for:)` | Removes the stolen-resource leak per observer |
| `PublicLedger` | Per-seat counted belief, folded from masked events |
| `ProductionRate` | Expected cards per turn per resource, robber-aware |
| `TradeRate` | Best bank/port conversion rate per resource |
| `PurchaseCost` | Costs and yields of each purchase under a `Ruleset` |
| `ClockModel` | `turnsToAfford`, seven risk, rate composition |
| `RouteNode` / `RouteEdge` | The search graph |
| `BeamRoutePlanner` | Bounded beam search with archetype seeding |
| `ExactRoutePlanner` | Uniform-cost oracle, tests only |
| `ContestModel` | Swing value and deadline races |
| `AdvantageModel` | `advantage(seat)` over all clocks |
| `RouteCommitment` | Route stability and switch margin |
| `ActionSelector` | Best route-advancing legal move |
| `PlannerTradeEvaluator` | Inbound and outbound trades by `Δadvantage` |
| `PlannerPolicy` | The `Policy` conformance |

## Testing

- `ExactRoutePlanner` equals `BeamRoutePlanner` on truncated cases.
- `PublicLedger` never contains information absent from masked events; a
  dedicated test asserts the planner reads no opponent private field.
- Cost-model unit tests: rates, deficits, port conversions, seven risk.
- Scenario tests for each worked example in this design — the 8-card dev card,
  the contested road versus city, the lopsided trade, the leader-refusal.
- Determinism: seeded games reproduce across separate processes.
- Both modes exercised; Expanded games must terminate.

## Out of scope

Difficulty tiers, learned components, adversarial lookahead over opponent
replanning, `StateEncoding`/`ActionSpace` Expanded support, and any change to the
shipping roster.
