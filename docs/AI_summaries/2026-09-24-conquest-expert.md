# The Conquest Expert (2026-09-24)

**Adopted.** `EvaluationWeights.conquest(mode)` now returns a set fitted on Conquest's
current rules (any 3 cards, deck 1-4, same-turn deploy). Pinned by
`theShippedConquestExpertIsTheAdoptedFit`.

## Why

Jake beat the Conquest Expert "pretty badly" by taking 6s and 8s, stockpiling army cards
and securing his spots. That Expert (sim seat `eval-v0`, now frozen) had never been fitted
on Conquest and could not see the plan: a card in hand was worth only its strength, and a
thin garrison beside an armed rival looked safe.

## What changed in the evaluation

| Term | What it prices |
|---|---|
| `captureThreat` | the production swing of the best hex the hand can take now |
| `garrisonExposure` | production on held hexes an adjacent rival could break with what they hold (count x deck mean) |
| `takeoverFoothold` | contested hexes the seat touches but does not hold - a reason to settle onto a crowded 6/8 |

Plus one bug: buying an army card was scored with the card removed from the hand, so a
buy never got credit for the capture it enabled. It is now the expectation over the
printed deck's strengths (never the hidden top card; bit-identical whatever it is).

## Fit

Sign-SPSA, 30 iterations x 8 boards x 4 chairs x 2 arms x 2 pools (vs 3x `eval-v0`,
vs 3x `balanced`), common random numbers, seeds 760000+, win rate only. Largest moves:
production +46%, variety +35%, approach +25%, knight +25%, port +35%, devCardHeld -39%,
takeoverFoothold +15%.

## Evidence (held-out, Classic, four players, every game decisive)

| | result |
|---|---|
| vs 3x `eval-v0` (the Expert Jake beat), seeds 98000+ | 28.7% ±4.4 (400) |
| same, seeds 100000+ | 28.2% ±3.1 (800) |
| **pooled** | **28.4% ±2.6 (1,200), z = +2.73** |
| vs 3x Classic `balanced` | 81.5% ±3.8 (400) |

An earlier fit (before the buying fix and `takeoverFoothold`) measured 28.2% ±4.4 on 400
games and was not adopted on that evidence alone.

## Strategy audit (100 all-Expert games, per seat per game)

| | before | adopted |
|---|---|---|
| army cards bought | 2.71 | 3.98 |
| 6/8 taken (games with any) | 0.09 (19%) | 0.34 (42%) |
| crowded hex taken | 0.14 | 0.45 |
| taken from the leader | 0.11 | 0.28 |
| reinforcements | 0.34 | 0.51 |
| settle-then-take | 0.04 | 0.08 |
| starved a rival of a resource (games) | - | 1.55 (94%) |
| starved the leader (games) | - | 0.61 (80%) |

Jake's proposed resource-denial term was not added: the audit shows the Expert already
starves rivals, the leader included, in most games.

## Not yet measured

- Vast: the Classic fit is used there untested.
- Human-level strength: self-play says it is stronger than the Expert Jake beat; his next
  games are the real test.
