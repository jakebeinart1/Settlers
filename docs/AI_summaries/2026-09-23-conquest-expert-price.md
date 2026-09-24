# Conquest, judged by a trained Expert: what should an army card cost? (2026-09-23)

**Answer: any 3 resource cards.** Classic board only so far.

## Why Expert, and how it was trained

The heuristic bots (`2026-09-23-conquest-first-measurement.md`) found armies unprofitable,
but they are weak judges. Expert (`EvaluationPolicy`) scores every move by the position it
leads to, so it can find whatever the rules actually reward. It was blind to Conquest until
`1c34746`: its production model now sees garrisons, and two weights price army strength
held and garrisoned.

Trained with sign-SPSA, the method of `2026-09-17-no-trade-weight-sweep.md`: 40 iterations,
12 boards x 4 chairs x 2 arms each, common random numbers, a fresh price drawn per iteration
(each / any 3 / any 1), seeds 700000-739011. **The objective is win rate and nothing else** -
not army use - so the bot uses armies only if they help it win. Unfinished games score as
losses. Largest moves: production +63%, knight +92%, armyStrength +39%. Trained vector
(`sim --weights`, 21 values):

```
1.000000,0.751520,0.140225,0.336059,0.198076,0.042506,0.172088,0.049513,0.067951,-0.062140,-0.005942,0.258676,0.500518,0.082826,0.098822,0.879994,0.007991,0.006164,1000.000000,0.020876,0.015157
```

## Results

Frozen binary `b231827`, held-out seeds 90000-90099 (rotations, 400 games per cell) and
90000-90199 (tables). Classic, four players, every game decisive. Null is 25%.

| | 1 of each | **any 3** | any 1 |
|---|---|---|---|
| trained vs untrained Expert | 25.8% ± 4.3 | 26.8% ± 4.3 | **45.0% ± 4.9** |
| **no-army Expert vs 3 trained** | **19.8% ± 3.9** | **24.8% ± 4.2** | **6.5% ± 2.4** |
| army cards bought / game (all trained) | 0.1 | 11.3 | 25.0 |
| PvP captures / game | 0.81 | 4.46 | 15.03 |
| moves / game | 664 | 731 | 699 |

Win rate by how many army cards a seat bought (all-trained table, every seat of every game):

| | 0 | 1-3 | 4-7 | 8+ |
|---|---|---|---|---|
| 1 of each | 25.2% (794) | - | - | - |
| **any 3** | **22.5% (182)** | **23.6% (394)** | **24.2% (153)** | **40.8% (71)** |
| any 1 | - | 11.9% (84) | 22.2% (492) | 36.2% (224) |

## Reading it

- **1 of each: armies are dead.** A win-maximising bot buys 0.1 cards a game. The only army
  play left is the free starting card - forbidding even that costs 5 points (19.8%).
- **any 1: armies are the only game.** A seat that refuses them wins 6.5%. Fifteen takeovers
  a game. One meta.
- **any 3: several lanes.** Refusing armies entirely is still viable (24.8%, inside the null),
  yet the trained table buys 11 cards and makes 4.5 takeovers a game. Seats win at similar
  rates whether they bought 0, 1-3 or 4-7 cards. This is the shape Jake asked for: armies
  are a real route, not a requirement and not a trap.
- **The 8+ bucket (40.8%, n=71, about +/-11) is partly reverse causality**: a seat that is
  already winning has the spare cards to buy that many. It is not evidence that spamming wins.
- **Training helped only where armies matter.** At any 1 the trained weights beat the
  untrained fork 45% to a 25% null; at the other two prices it made no significant difference.

## Not yet measured

- Vast. Expert runs ~5 s per Classic game; Vast is slower.
- Prices between (any 2, any 4) and whether any 3 should require mixed types.
- Swing detail beyond PvP captures (e.g. how often the leader loses a hex).
