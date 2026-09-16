# Classic retrain on the new trading: measured, not adopted

**Date:** 2026-09-16
**Question:** the weights were fitted when Expert made only single-resource
offers, so they describe a policy that no longer exists. Does refitting them for
the composed-offer trading make the bot stronger?

**Answer: not demonstrably, and it loses ground in the one arm that matters
most. The shipped weights stay.**

## The training number, and why it should not be believed on its own

Forty sign-SPSA iterations, Classic, 12 seeds per (mix, chair), seed block
610000, against a frozen `sim-train2`:

```
baseline  47.9%
best      51.0%   (iteration 40 of 40)
```

Two things make that +3.1 weak evidence before anything else is run:

1. **It peaked on the final iteration.** The run was still wandering when it
   stopped, so the best point is the most favourable draw rather than a settled
   optimum.
2. **At 12 seeds per chair each measurement carries roughly ±4 points.** A
   3.1-point gain measured on the very seeds it was fitted to sits inside its
   own noise.

This project has already paid for believing a training-arm number once: 67.2%
against the opponent it trained on, 47.3% against a stranger.

## Held-out validation, all four table mixes

624 rotated games per arm per mix, held-out seeds from 950000, complete chair
rotation, unfinished scored as a loss. The acceptance rule was written into
`validate2.py` before any result was read.

| shipping bots | today | tuned | paired diff [95% CI] | p |
|---:|---:|---:|---:|---:|
| 3 | 77.7% | 74.0% | **−3.7** [−7.9, +0.5] | 0.100 |
| 2 | 47.0% | 53.0% | **+6.1** [+1.2, +11.0] | 0.017 |
| 1 | 33.7% | 35.9% | +2.2 [−2.3, +6.8] | 0.365 |
| 0 | 25.0% | 27.7% | +2.7 [−1.5, +7.0] | 0.239 |

**The rig is proven correct by its own control.** Four identical Experts return
**exactly 25.0%** in the bottom row, which is the null a complete rotation must
produce by symmetry. The numbers above it therefore mean something.

## Why this is a rejection even though the script says "no table mix is worse"

`validate2.py`'s verdict implements the weaker of the two rules in play - reject
only on a *significant* regression. Jake's rule is stronger, and was stated
before the run: **no regression against balanced, and improvement against
Expert.** Measured against that:

- **Expert against three shipping bots is down 3.7 points.** It is not
  statistically significant (p = 0.100), but it is a regression in exactly the
  arm named, and "not significant" is not the same as "not there" - the interval
  runs to −7.9.
- **Expert against Expert is up 2.7 points and indistinguishable from zero**
  (p = 0.239). The arm required to improve did not.

The single significant cell, +6.1 at two shipping bots, has to be read against
the fact that **four mixes were tested**. With four independent tests the chance
of at least one landing under p = 0.05 by luck alone is about 18%. One
significant result out of four is close to what noise produces.

Adopting on the script's verdict would be shipping on a technicality, in the
direction the stronger rule forbids.

## What the sweep moved, for the record

Largest relative moves from the shipped set: `concessionPerCard` −60%,
`buildableSites` +33%, `roadLength` +25%, `knight` −23%, `handCardOverflow`
+22%, `handCard` +20%, `approach` −17%. Nothing structural: `rival` stayed near
1.0 rather than collapsing toward zero, which is the same independent support
for the relative-position objective the first sweep produced.

The weights are kept at
`$SCRATCH/eval2/best2.classic.json` in case a later, better-powered run wants a
starting point. They are not in the app.

## What would actually settle the −3.7

624 games per arm cannot resolve a 3.7-point difference; roughly 2,000 per arm
would. That measurement is worth running only if the decision could change, and
it cannot here: the tuned set would still have to *improve* Expert-vs-Expert to
meet the rule, and it does not.

The more useful conclusion is the one the trading work already established -
**the +14.7 points came from giving the bot better moves to choose from, not
from tuning how it scores them.** Every large gain in this project has come from
adding a missing term, never from refitting existing ones.

## Trap defused along the way

`best2.classic.json` on disk at the start of this run was **from the earlier
18-weight sweep**, the one whose `--weights` guard caught it passing 18 numbers
where 19 exist. Validating against it would have silently measured a broken
run's output. It is renamed `STALE-18-weight-run.best2.classic.json`, and the
absence of the file is now the signal that a sweep found nothing.
