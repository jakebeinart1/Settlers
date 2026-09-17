# Re-sweeping the Classic weights against an opponent that refuses trades

**Date:** 2026-09-17
**Question:** every weight Expert has ever been given was fitted at a table
that accepts its trades, and at a table that refuses, Expert measured the same
strength as the heuristic it replaced (38.7% against 39.3%). Does refitting
with a refusing opponent *in the pool* recover the advantage?

**Answer: yes, +4.3 points at the refusing table, replicated on two
independent held-out blocks, with no significant cost anywhere else. Adopted.**

It took two sweeps, and the first one's failure is the more useful half of this
write-up.

## Rig

One Release binary plays both arms, because `sim --weights` exists. It is a
frozen build of `5806373`, sha256 `90f00fcd59e32a24…`, never rebuilt for the
duration. `--weights` carrying `EvaluationWeights.default` produces
fingerprints byte-identical to seat `eval` on seeds 70010-70011, so "the
shipped policy" and "the candidate with default weights" are the same program.

Two checks were run before any sweep, and both are the reason the numbers
below mean anything:

- **Rig control.** Four identical `eval` seats over a complete four-chair
  rotation returned **exactly 25.0%** of 160 games, 160/160 decisive. A
  complete rotation must produce that by symmetry; anything else is a rotation
  applied wrong.
- **Reproduction.** `eval` against three `refuses-balanced`, same 40 seeds:
  **36.9% ±7.5**, consistent with the 38.7% ±5.3 recorded on 2026-09-16.

Training seeds 700000-709000. Validation blocks 800000- and 810000-, both held
out from every earlier run here. Sign-SPSA, common random numbers within an
iteration (the + and - perturbations play the same boards, so the difference
that forms the gradient is paired), block resampled every iteration.
`victoryPoint` and `winning` are frozen: one defines the unit scale and the
other is a dominance constant, so sweeping them only rescales the objective.
**An unfinished game counts as a loss for the candidate in training** -
decisive-only scoring is right for reporting a strength number and wrong inside
an optimiser, which would otherwise learn to stall. No game in any run reached
the cap; every cell below is 100% decisive.

## Sweep 1: rejected, and it is the finding

Sixty iterations, objective = win rate at a refusing table **plus** win rate at
a trading table. Held out on block 800000-, 1,248 rotated games per arm:

| cell | shipped | tuned | diff | p |
|---|---:|---:|---:|---:|
| vs 3× `refuses-balanced` | 39.8% ±2.7 | **44.8% ±2.8** | **+5.0** | 0.003 |
| vs 3× `balanced` | 80.2% ±2.2 | 77.2% ±2.3 | **−3.0** | 0.039 |
| head to head vs the shipped weights | 25.0% by symmetry | **19.6% ±2.2** | −5.4 | z = −4.38 |

The first row is what the sweep was asked for. The third row is why it was
rejected: **the tuned set loses to the set it would replace**, 19.6% against a
null that is *known* rather than estimated, because a complete rotation of two
equal weight sets returns exactly 25.0%.

Nothing was wrong with the optimiser. It maximised the objective it was given,
and that objective let a −3.0 in one cell buy a +5.0 in the other. The
acceptance rule forbids that trade; the sum did not. This is the same failure
the refusing opponent was built to expose - fitting the table rather than the
game - pointed the other way, and it is easy to imagine adopting it on the
strength of row one alone.

## Sweep 2: the head-to-head arm goes inside the objective

Forty iterations, objective = refusing table **+** trading table **+** head to
head against the shipped weights. One change; the acceptance rules were not
touched. Validated on the fresh block 810000- and then replicated on 800000-,
1,248 rotated games per arm per block, every cell 100% decisive:

| cell | 810000- | 800000- | pooled (2,496/arm) |
|---|---:|---:|---:|
| vs 3× `refuses-balanced` | **+4.8** (p = 0.003) | **+3.8** (p = 0.019) | **+4.3** |
| vs 3× `balanced` | −1.1 (p = 0.448) | −1.8 (p = 0.227) | −1.5 |
| head to head vs shipped (null 25.0%) | **28.3%** (z = +2.68) | 26.1% (z = +0.92) | **27.2%** (z ≈ +2.5) |

Absolute rates, pooled: at the refusing table **40.8% → 44.2%**; at the
trading table 80.3% → 78.8%.

All three acceptance rules pass, and rule 1 passes *independently in both
blocks*, which is the part worth trusting. The replication was run precisely
because two candidates had been tried by then, so "one block's luck" was a live
explanation for the first result and a second block was the cheap way to kill
it.

## What moved

`handSynergy` −17.6%, `rival` −12.7%, `handCardOverflow` −11.3%, `production`
−9.0%, `buildableSites` +11.8%, `expansion` +4.2%. The direction is consistent
and it is the hypothesis this run was built on: **value moves off the hand,
which is only worth what somebody will give you for it, and onto the board,
which pays whether or not anybody trades.** The 2026-09-16 diagnosis named
`handCard` tripling in the original sweep as "the table, not the game"; this is
that correction arriving.

`sevenLoss`, `tradeMargin` and `concessionPerCard` could move for the first
time and landed at −0.0081, 0.0073 and 0.0061 - respectively 25×, 14× and 6×
smaller than values previously measured to lose badly. Read those as the search
confirming zero, not as three new terms switching on.

## Three cautions that belong next to the result

1. **The trading cell's point estimate is negative in both blocks** (−1.1,
   −1.8). Neither is significant and the pooled −1.5 sits inside its interval,
   but the sign repeats, so this is a small real cost paid for a larger real
   gain rather than a free lunch.
2. **Two SPSA runs on this objective disagreed on the direction of most
   weights.** Sweep 1 moved `handSynergy` +11.3% and `roadLength` +29.8%;
   sweep 2 moved them −17.6% and −3.8%. The surface is flat relative to the
   noise, so no individual weight's move here is a fact about Catan. Only the
   validated end-to-end difference is.
3. **This narrows the gap; it does not close it.** At a refusing table Expert
   now wins 44.2% against a 25.0% null - a real edge where there was none - but
   against a trading table it wins 78.8%. A difficulty tier whose strength
   still depends this much on whether opponents say yes is a tier with a
   missing idea in it, not just mis-set numbers. The next move is a *term*, not
   another sweep: this evaluation has no notion of a plan that needs no
   counterparty.

## Reproducing

```bash
# Anchor, built once and kept:
swift build --package-path Packages/CatanAI -c release
# Candidate = EvaluationWeights.default's vector, which IS the swept set.
sim --games 8 --seed 810000 --players 4 --victory-points 10 --board randomized \
    --mode classic --seats eval-tuned,refuses-balanced,refuses-balanced,refuses-balanced \
    --weights <19 values> --jsonl
```

Rotate the candidate through all four chairs, sum, and compare against the same
seeds played by seat `eval`. The sweep rig itself was scratch tooling and is
not in the tree; it is ~200 lines of Python over `sim`, and the method above is
the part worth keeping.
