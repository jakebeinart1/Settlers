# The Expanded "stall" is a supply cliff, not a passive bot

**Date:** 2026-09-16
**Measured on:** 40 seeded Expanded games, four Expert seats, current trading
(`exp.best.*.jsonl`, seeds 700-739).

The roadmap carried this as an open bug: "four Expert bots still fail to finish
1 of 40 seeded Expanded games, where the shipping heuristic finishes 40." The
working assumption was bot passivity - the failure mode the `bot-strength`
skill warns about, where an optimiser learns to protect a win rate by stalling.

**It is not that.** The one unfinished game is not a table of bots refusing to
commit. It is a table that has run out of things to buy.

## What seed 724 actually looks like at the cap

At move 3,000 the scores are **21 / 19 / 24 / 22**. Every seat is deep into the
endgame and one is a single point short of the 25-point target.

| seat | settlements | cities | roads | dev cards | bank trades | turns |
|---|---:|---:|---:|---:|---:|---:|
| 0 | 6 | **8** | 28 | 12 | 137 | 59 |
| 1 | 4 | 6 | 23 | 14 | 111 | 59 |
| 2 | 11 | **8** | 28 | 13 | 264 | 59 |
| 3 | 9 | **8** | 28 | 11 | 260 | 58 |

Three of the four seats sit **exactly on the 8-city limit**
(`Ruleset.forMode(.expanded)`, `pieceLimits: [.settlement: 10, .city: 8]`), and
the four seats together bought **50 development cards against a 50-card deck** -
the deck is empty, so the ten victory-point cards are all dealt and gone. Roads
are 28 of a 30 limit.

So the remaining routes to a 25th point are: a new settlement on a board where
30 buildings already stand, or taking a bonus off the seat holding it. The game
has no cheap way to end, and the move cap arrives first.

## This is common, not a freak seed

Across the 40 games:

- **19 of 40** empty the development deck completely.
- **24 of 40** have at least one seat on the 8-city cap.
- Games that empty the deck run **1,383 moves** against **1,011** for games that
  do not.

The winner of a decisive game averages 8.3 settlements, 6.6 cities and **12.8
development cards bought**. A quarter of the entire deck per winner: reaching 25
is not primarily a building race, it is a dev-card race, and the deck is a
shared, finite resource that four such racers exhaust.

Worth checking the arithmetic rather than trusting the feel of it. The piece
limits cap standing buildings at 10 settlements + 8 cities, and the bonuses are
worth 4 each - so the target is reachable on paper. What is scarce in practice
is *vertices*: with four seats each wanting eight or nine settlements on one
37-tile board, the last few points have to come from the deck, and the deck runs
out.

## The second finding: bank-trade churn when nothing is buildable

The bot keeps bank-trading after there is nothing left to buy. Normalised per
turn, so game length is not doing the work:

| games | bank trades per turn |
|---|---:|
| shortest 10 | 0.29 |
| longest 10 | 0.88 |
| deck still has cards (n=21) | 0.30 |
| deck emptied (n=19) | 0.69 |
| **seed 724 (the unfinished one)** | **3.29** |

An eleven-fold rise in the dead position. `bankTrade` is scored through the
generic one-ply path in `EvaluationPolicy.score`, so a trade is chosen whenever
the resulting hand scores better - hand synergy can pay for the cards a 4:1
costs even when no purchase exists to spend the result on. Nothing ties a bank
trade to a purchase it enables.

Two reasons this matters beyond the one seed:

1. **It distorts training.** An unfinished game is scored as a loss for every
   seat, so moves burned on churn become losses attributed to the weights.
2. **It is visible in the app.** A human playing Expanded would watch a bot
   convert resources at the bank, over and over, to no end.

## What has deliberately *not* been changed

Nothing in the policy. The Classic Expert-vs-Expert sweep is running against a
frozen `sim-train2`, and changing the bot mid-sweep would invalidate it - the
anchor rule from the `bot-strength` skill. This note is the measurement; the fix
is a separate decision:

- **Bot-side (mine to propose):** require a bank trade to enable a purchase this
  turn, or price it against `bestPurchaseGain` the way `TradeValuation` already
  prices a proposal. Cheap, testable, and it fixes the churn wherever it appears.
- **Rules-side (Jake's call, because it changes the game):** the 8-city cap and
  the 50-card deck are what make the last points unreachable. Raising either, or
  lowering the 25-point target, is a design change and not one to make quietly.

The honest summary of the original bug report: the bots are not stalling. The
mode's supply runs out before its victory condition does, roughly half the time,
and one seed in forty is unlucky enough that nobody has closed by then.
