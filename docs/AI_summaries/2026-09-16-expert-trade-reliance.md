# Expert's advantage is contingent on opponents accepting its trades

**2026-09-16.** Measured after Jake beat three Expert bots on his phone
(Classic, 10 points, game `9713086E`) and asked why they played so passively.

## The headline

Expert's entire measured strength advantage over the shipping Classic
heuristic disappears at a table that will not accept its trades.

| opponents (3x, full chair rotation, seeds 60000-60081) | Expert | Classic `balanced` | Expert's edge |
|---|---|---|---|
| `balanced` - accepts trades | **83.5%** (+/-4.0) | 25.0% (by symmetry) | **+58.5 pts** |
| `refuses-balanced` - accepts nothing | **38.7%** (+/-5.3) | **39.3%** (+/-5.3) | **-0.6 pts** |

328 decisive games per cell, 25.0% null, complete four-chair rotation.
Both numbers in the second row are inside each other's interval: at a
non-trading table Expert and the bot it was built to replace are the same
strength.

Jake accepted 1 of 75 offers in the game that prompted this. He is the
second row.

## The control that makes the row readable

Refusing is not a free strength change for the refuser. An ordinary
`balanced` bot against three `refuses-balanced` wins **39.3% (+/-5.3)**
against a 25.0% null, so refusing costs the refuser about 14 points.

That runs *against* the headline and makes it stronger: Expert faces
measurably weaker opponents in the second row and still gains nothing on
Classic.

## Where the reliance came from

Nothing in the opponent pool could refuse trades until this run, so every
strength number Expert has ever been given - the 68.4% in
`BotDifficulty`, the SPSA sweep's fitted weights - was earned at a table
that trades. `EvaluationWeights.tradeMargin`'s own doc says it: "a stream
of small gains is where this policy's strength comes from."

`handCard` tripling in the sweep is the same fact as a number. Holding
cards is correct when someone will trade with you later. The weight did
not learn something about Catan; it learned something about the table it
was swept on.

## The bank-trade fix, measured

`.bankTrade` had no handling in `Sources/CatanAI/Evaluation` at all - it
fell through `EvaluationPolicy.score` to the generic one-ply path, while
proposals got `TradeValuation.bestPurchaseGain`. Routing it through the
same correction (`328c235`):

| cell | bank trades/game | cities/game | moves/game | win rate (paired) |
|---|---|---|---|---|
| vs `balanced` | 2.71 -> **3.52** | 2.16 -> 2.39 | 479 -> 464 | -2.1 pts, p=0.36 |
| vs `cautious` | 2.78 -> **3.92** | 2.07 -> 2.38 | 502 -> 495 | -0.3 pts, p=1.00 |
| vs `refuses-balanced` | 3.11 -> **4.30** | 1.62 -> 2.11 | 600 -> 579 | **+4.6 pts, p=0.115** |
| vs `eval-round3` | 2.23 -> **2.63** | 1.55 -> 1.59 | 679 -> 597 | -3.7 pts, p=0.23 |

It does mechanically what it was built to do - more bank trades, more
cities, shorter games, in every cell - and **moves no win rate anywhere**.
Only the no-trade cell trends up, and 328 games can only resolve a
~10-point effect, so that +4.6 is a candidate for a full-power run and
not a result.

**Strength is not claimed for this change.** It is kept because it is
mechanically correct, costs nothing, and every cell stayed 328/328
decisive.

## Also measured, and awkward

Expert as shipped (`.worthIt`) against three frozen `eval-round3` wins
**29.3% (+/-4.9)** against a 25.0% null. The trade model currently in the
app is not clearly stronger than the one it replaced.

## Method

Anchor `1810c78` + the `refuses-balanced` opponent, built once and kept;
candidate adds only the bank-trade change. Fingerprints on seed 7001
confirm the change reaches Expert (`c6191e48613826a0` ->
`870c64628144e05b`) and nothing else (`balanced,aggressive,cautious,balanced`
byte-identical). Seeds 60000-60081, held out from 90000-, 92000- and
95000-. 2,624 games in the screen plus 328 in the control; all decisive.

## What to do next

1. **Re-sweep with `refuses-balanced` in the pool.** The self-sufficiency
   gap is a weights problem before it is a heuristic problem, and the
   current weights were fitted where it could not be seen.
2. **Make the no-trade cell a permanent arm.** A tier whose advantage
   evaporates against a self-sufficient human is not a difficulty tier.
3. Full-power (1,248/arm) on the no-trade cell for the bank fix's +4.6.
