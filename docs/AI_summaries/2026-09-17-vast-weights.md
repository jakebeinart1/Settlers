# Vast's weights: the placeholder was the problem, not the tuning

**Date:** 2026-09-17
**Question:** Vast ships `EvaluationWeights.handSet` — hand-written numbers,
never fitted, never validated on a 61-tile board played to 26. What should it
play instead?

**Answer: the fitted Classic set, unchanged. It beats the placeholder 81.7% in
the same game. No Vast-specific sweep was needed, and one would have been three
hours spent on the wrong question.**

## Why a sweep was not the first move

`#4` on the backlog reads "tune the weights for Vast", and the obvious shape is
an SPSA run on the Vast board — five hours of compute, at least. Before paying
that, there is a much cheaper question with the same decision attached: **is the
incumbent even a reasonable starting point?** Vast inherited `handSet` on an
argument, not a measurement — that a longer game rewards different things than
Classic. Testing the argument costs one comparison.

The argument was wrong, and by a margin no sweep would have closed.

## Measured

Anchor: the frozen Release `sim` from `5806373`, the same binary used for the
Classic sweep. Seat `eval` carries no weights override, so in Vast it plays
exactly what the app ships. Held-out seeds 820000-, complete four-chair
rotation, 480 rotated games per arm, **every cell 100% decisive**:

| cell | shipped `handSet` | fitted set | diff |
|---|---:|---:|---:|
| head to head vs `handSet` (null 25.0%) | 25.0% by symmetry | **81.7% ±3.5** | **+56.7** (z = +28.7) |
| vs 3× `balanced` | 67.7% ±4.2 | **85.2% ±3.2** | **+17.5** (p < 0.001) |
| vs 3× `refuses-balanced` | 62.5% ±4.3 | 57.3% ±4.4 | −5.2 (p = 0.055) |

One Expert on the fitted weights beats three on the hand-set ones **four games
in five, on their own board**.

## The one cell that disagreed, run to full power

−5.2 at p = 0.055 is the width of the interval talking, and adopting over a
cell that regresses needs the number rather than a shrug. Re-run on a fresh
block, 830000-, at 1,248 games per arm:

| | `handSet` | fitted set | diff | p |
|---|---:|---:|---:|---:|
| vs 3× `refuses-balanced` | 60.7% ±2.7 | 59.3% ±2.7 | **−1.4** | **0.402** |

It is not a regression. The 480-game estimate was noise of exactly the size its
interval advertised, which is the argument for reading intervals rather than
point estimates, made at this project's own expense one more time.

## The stall check, which is the one that could have blocked this

`forMode`'s own doc records why Vast was given `handSet` in the first place:
the fitted Classic weights **stalled in Expanded**, four Expert seats failing to
finish 2 of 40 seeded games where the hand-set weights finished all 40. Every
cell above has one candidate seat against three opponents, so **none of them
could see that failure.** Four seats on the candidate, Vast, seeds 840000-:

| lineup | decisive |
|---|---|
| 4× fitted set | **40/40** |
| 4× `handSet` | **40/40** |

The Expanded stall does not reproduce on this board. That is consistent with
what replacing Expanded with Vast was for: Expanded's endgame ran out of
supply, and Vast was built so it does not.

## A rule I wrote that turned out to be wrong, kept rather than quietly swapped

Before running anything I declared that Vast would adopt under the same three
rules as Classic, the first being **"a significant gain against a refusing
table"**. The fitted set does not meet that rule — it is 1.4 points behind
there, p = 0.40.

The rule was mis-specified, and it is worth saying why rather than editing it
out. It was written to fix *Classic's* defect: Expert had no advantage at all
against a refusing table (38.7% against the heuristic's 39.3%). **Vast does not
have that defect** — the shipped placeholder already wins 60.7% there against a
25.0% null. Requiring a gain in a cell that was never broken, while ignoring a
56.7-point head-to-head deficit in the cell that is, optimises the wrong thing.

`TODO.md`'s own phrasing of the rule — "no table mix regresses, Expert-vs-Expert
improves" — is met decisively: nothing regresses significantly, and
Expert-vs-Expert improves by 56.7 points.

## What was not done

- **No Vast-specific sweep.** The fitted set was tuned on Classic. It is now
  measured as much better than the alternative on Vast, which is a different
  claim from optimal on Vast. A sweep starting from this set is still available
  and is now a question of refinement rather than repair.
- **The trade-behaviour metrics were not re-measured on Vast.** Win rate,
  decisive rate and the head-to-head are what this decision rested on; bank
  trades per turn, cities per game and the rest were not compared.
