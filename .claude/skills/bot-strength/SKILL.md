---
name: bot-strength
description: Evaluate Empires bot-strength changes honestly on supported three- and four-player tables using a frozen anchor, paired held-out seeds, every-chair rotation, table-size-aware power, and confidence intervals. Use before claiming a bot, heuristic, weight set, or difficulty tier is stronger; use gameplay verification instead for functional checks.
---

# Bot strength

**A win rate against your own current bot is not strength.** It is a measure of
how well the new policy exploits one specific opponent, and that number can
climb steadily while true strength does not move at all - you have found the
current bot's blind spot, not a better way to play Catan. Alex has already paid
for this exact mistake once, in GlobalConquest: a policy's win rate against the
scripted heuristic rose from 0.83 to 0.95 across a training run while its
anchored Elo against a fixed pool stayed flat. Nights were spent on that number.

**And the second failure is arithmetic, not philosophy.** With `playerCount`
occupied seats, the average-policy null win rate is **`1 / playerCount`**:
**33.3% at three players and 25% at four**. "It won 60% of 50 games" still has
a 95% confidence interval of roughly plus or minus 14 points. Almost every
result anyone reports informally is inside its own noise.

Treat table size as part of the experiment, not a pooling dimension. A claim
about both product-supported table sizes needs a result for each; three- and
four-player trajectories are not paired observations even when they share a
seed number.

This skill is the method. It needs no code beyond what **sim-harness** already
provides.

## What has actually run

| Path | Status |
|---|---|
| **The complete two-arm method** | **NOT YET RUN.** Four-player candidate arms have used held-out seeds, complete chair rotation, the committed Greedy anchor, and clustered intervals. They did not include the separately built all-anchor control arm required below, so they are useful regression evidence rather than a complete calibrated-difficulty result. See `docs/AI_summaries/2026-09-02-personality-separation-results.md`. |
| **The four-player harness underneath** | **RUN AND PROVEN 2026-08-29** - see **sim-harness**. Reproducible across processes, cross-checked against the five pinned fingerprints, ~0.5 games/sec per process and ~1.76 games/sec across 10 shards. These timings are not three-player measurements. |
| **Seat advantage, four identical `balanced` bots** | **MEASURED 2026-08-29, 200 games** (seeds 5000-5199): 21.0 / 20.0 / 27.5 / 31.5 percent by seat, an 11.5-point spread, `chi2 = 7.16, df = 3, p = 0.067`. **Suggestive, not established** - and that is the point. See "Rotate the seats" below. |
| **Three-player strength or seat advantage** | **UNMEASURED.** The three-player values below are arithmetic for planning a future run, not empirical evidence about the bots or seats. |
| **A frozen anchor opponent** | **EXISTS IN SOURCE.** `GreedyPolicy` is the committed, intentionally untuned middle anchor and `RandomPolicy` is the floor. A comparison still has to build and hash the exact anchor binary once; a source type called "anchor" does not freeze the executable used by a run. |
| **The variance reduction paired/CRN evaluation actually buys here** | **UNMEASURED.** Pairing on board seed reduces the required sample by roughly `(1 - rho)`, where `rho` is the per-seed correlation between arms - and `rho` has never been computed for this game. Every sample size below is therefore the **unpaired ceiling**. Measure `rho` from your first run; do not assume a discount you have not earned. |
| **Comparing two weight sets in one run** | **NOT POSSIBLE TODAY.** The harness exposes policy names but not arbitrary weights, so two weight arms remain two separate binaries. The analyzer now accepts independent candidate/baseline build IDs and refuses mismatched seed/chair/configuration keys. |

## Hard preconditions: if one is missing, STOP - the run will produce a number that means nothing

- **A frozen anchor.** A specific commit of the bot code, built once, kept, and
  never rebuilt for the duration of a comparison. If the anchor changes between
  arms you have measured two things at once.
- **Held-out seeds.** The seed range you evaluate on must not be the range you
  tuned on. Tuning on seeds 1-500 and reporting on seeds 1-500 measures how
  well you fit 500 boards.
- **A settled tree.** `git status` clean, or at least clean under
  `Packages/CatanAI/Sources` and `Packages/CatanEngine/Sources`. Record the SHA
  of each arm in the result.
- **A stated effect size, chosen before the run.** "How much better does it
  need to be to matter?" decides the sample size. Deciding it afterwards, by
  looking at the result, is how a 3-point wobble becomes a shipped claim.
- **A declared table size.** Record `playerCount` as three or four. Pair and
  analyze within that stratum; run both strata before making a product-wide
  claim.

## The method

### 1. Freeze an anchor, and never touch it again

Build the baseline once into a binary you keep:

```bash
REPO="$(git rev-parse --show-toplevel)"
git -C "$REPO" rev-parse --short HEAD                       # record this in the result
swift build --package-path "$REPO/Packages/CatanAI" -c release
cp "$(swift build --package-path "$REPO/Packages/CatanAI" -c release --show-bin-path)/sim" \
   /tmp/anchor-sim
```

The anchor exists so that today's number and next month's number are on the
same scale. The moment you rebuild it, they are not, and every earlier result
becomes uncomparable - which is the same trap as a pool-relative Elo quoted
without its pool.

### 2. Same board seeds for both arms (common random numbers)

Within one table-size and rules configuration, play the **identical** seed set
with the anchor build and the candidate build. Because the engine is
reproducible across processes (that is the property **sim-harness** proves),
the same seed produces the same board, the same dev card deck, and the same
dice sequence for both arms. The board luck therefore cancels between arms
instead of being noise you have to pay sample size to average away.

This is the whole reason cross-process determinism matters. Without it, "the
same seeds" is a sentence with no content.

### 3. Rotate the seats

**A seat is not a neutral container.** Turn order decides who places first in
setup, who places last-and-first at the turn, and who rolls first. The only
seat-advantage evidence recorded here is the following **four-player** probe,
measured 2026-08-29 with four identical `balanced` bots over 200 games, so that
every difference is turn order and nothing else:

```
sim --games 20 --seed <s> --personalities balanced,balanced,balanced,balanced --jsonl
  sharded 10 ways over seeds 5000-5199
```

| seat | wins / 200 | win rate | 95% CI |
|---|---|---|---|
| 0 | 42 | 21.0% | +/- 5.6 pp |
| 1 | 40 | 20.0% | +/- 5.5 pp |
| 2 | 55 | 27.5% | +/- 6.2 pp |
| 3 | 63 | 31.5% | +/- 6.4 pp |

**Read this result the careful way, because it is also a worked example of
everything below.** The point estimates span **11.5 points** from seat 1 to
seat 3, which is more than twice the 5-point effect a heuristic change would be
thrilled to produce. But the sample does not establish it: a chi-square
goodness-of-fit against a uniform 25% gives `chi2 = 7.16, df = 3, p = 0.067` -
suggestive, not significant. Distinguishing a true 31.5% from 25% would need
**750 games per arm**, and this probe ran 200.

So the honest reading is: *the seats may well not be equivalent, by a margin
big enough to swamp what you are trying to measure, and 200 games is not enough
to say so.* That is precisely why the design rotates seats rather than
arguing about whether the effect is real. Rotation makes the question moot for
free; measuring it properly would cost an hour.

For `playerCount = k`, play every board seed **k times** and put the candidate
in each occupied chair exactly once. This is the existing four-player worked
example:

| Rotation | seat 0 | seat 1 | seat 2 | seat 3 |
|---|---|---|---|---|
| A | candidate | anchor | anchor | anchor |
| B | anchor | candidate | anchor | anchor |
| C | anchor | anchor | candidate | anchor |
| D | anchor | anchor | anchor | candidate |

Sum over all `k` rotations and the seat effect cancels exactly. Skip a chair
and a candidate that happens to sit in a favourable seat looks stronger by
however large that effect is - which, in the historical four-player probe
above, is larger than most heuristic changes are ever going to be.

| occupied seats (`k`) | null win rate | rotations / games per seed per arm | anchor opponents |
|---|---:|---:|---:|
| 3 | 33.3% | 3 | 2 |
| 4 | 25.0% | 4 | 3 |

Budget in whole rotations: `boardSeeds = ceil(requiredGames / k)`. The
four-player 1,248-game worked example is 312 board seeds; the three-player
1,440-game counterpart below is 480.

An **arm** comprises every chair rotation for one policy build. Arm 1 rotates
the candidate through all `k` chairs against `k - 1` anchors; arm 2 rotates an
*unmodified anchor* through the same chairs against `k - 1` anchors. Arm 2
should come out at `1 / k`, and running it is not optional: if it does not, the
rig is wrong (a rotation skipped, a crash scored as a loss, the wrong binary
in a shard) and arm 1's number is meaningless.

### 4. Size the sample to the effect, before running

For two independent proportions at `alpha = 0.05` two-sided and `power = 0.80`,
set `p1 = 1 / playerCount` and `p2 = p1 + minimumMeaningfulDifference`:

```
n per arm = (z_{alpha/2} + z_beta)^2 * [p1(1-p1) + p2(1-p2)] / (p1 - p2)^2
          = (1.960 + 0.842)^2 * [p1(1-p1) + p2(1-p2)] / (p1 - p2)^2
```

The displayed z-scores are rounded; the planning counts use their unrounded
quantiles and then round up to a whole game and a whole chair rotation.

The existing four-player worked example uses a 25% baseline and 30% candidate,
i.e. **a 5-point win-rate difference**:

```
(z_{alpha/2} + z_beta)^2 = 7.849 (using unrounded z-scores)
p1(1-p1) = 0.25 * 0.75 = 0.1875
p2(1-p2) = 0.30 * 0.70 = 0.2100
n = 7.849 * (0.1875 + 0.2100) / (0.05)^2 = 7.849 * 0.3975 / 0.0025 = 1,248
```

**1,248 games per arm, 2,496 games total, 312 board seeds x 4 rotations.**

The independently checked three-player counterpart uses `p1 = 1/3` and
`p2 = 0.383333...`: **1,440 games per arm, 2,880 total, 480 board seeds x 3
rotations**. This is planning arithmetic, not a measured three-player result.

Historical four-player planning table (the timing was measured on four-player
games):

| Effect to distinguish | games per arm | total | wall clock at 1.76 games/sec (10 shards) |
|---|---|---|---|
| 25% vs 35% (10 points) | 326 | 652 | ~6 min |
| 25% vs 30% (5 points) | 1,248 | 2,496 | ~24 min |
| 25% vs 28% (3 points) | 3,394 | 6,788 | ~64 min |
| 50% vs 55% (head-to-head framing) | 1,562 | 3,124 | ~30 min |

Round each four-player arm to a whole rotation: the 10-, 5-, and 3-point rows
need 82, 312, and 849 seeds respectively, yielding 328, 1,248, and 3,396 games
per arm. Do not reuse the four-player throughput measurement as a three-player
timing estimate.

Three-player planning table:

| Effect to distinguish | minimum games per arm | board seeds | actual games after full rotations |
|---|---:|---:|---:|
| 33.3% vs 43.3% (10 points) | 368 | 123 | 369 |
| 33.3% vs 38.3% (5 points) | 1,440 | 480 | 1,440 |
| 33.3% vs 36.3% (3 points) | 3,956 | 1,319 | 3,957 |

**Full rotation can make the null known instead of estimated.** If the
candidate is byte-identical to the anchor, its summed win rate over all `k`
rotations is exactly `1 / k` by symmetry, whatever the seat effect. That makes
this a **one-sample** proportion test against a known `p0`. The existing
four-player 25% to 30% worked example is:

```
n = [ z_{alpha/2} * sqrt(p0(1-p0)) + z_beta * sqrt(p1(1-p1)) ]^2 / (p1 - p0)^2
  = [ 1.960*sqrt(0.1875) + 0.842*sqrt(0.2100) ]^2 / (0.05)^2
  = (0.8487 + 0.3857)^2 / 0.0025 = 610
```

| Effect | minimum one-sample games | board seeds | actual rotated games | at 1.76 games/sec |
|---|---:|---:|---:|---:|
| 25% -> 35% | 157 | 40 | 160 | ~1.5 min |
| 25% -> 30% | 610 | 153 | 612 | ~6 min |
| 25% -> 28% | 1,672 | 418 | 1,672 | ~16 min |

Three-player one-sample planning arithmetic:

| Effect | minimum one-sample games | board seeds | actual rotated games |
|---|---:|---:|---:|
| 33.3% -> 43.3% | 180 | 60 | 180 |
| 33.3% -> 38.3% | 711 | 237 | 711 |
| 33.3% -> 36.3% | 1,962 | 654 | 1,962 |

Use the two-sample numbers when you are **not** confident the null is exactly
`1 / playerCount` - an incomplete rotation, a mismatched rules configuration,
or a candidate that changes the *anchor's* behaviour (a trade heuristic does;
a placement heuristic mostly does not). On the measured four-player harness,
the extra cost of the conservative 5-point comparison is about twenty minutes.

For the historical four-player harness, a single process was ~4x slower
(measured 0.45-0.56 games/sec). Measure three-player throughput before quoting
its wall time. The four-player evidence already removes any excuse for running
50 games and reporting a precise win rate.

### 5. Report the interval, never the point

The 95% interval on a measured win rate `p` from `n` games is
`p +/- 1.96 * sqrt(p(1-p)/n)`. The rough half-width depends on table size:

| games | three-player null (33.3%) | four-player null (25%) |
|---|---:|---:|
| 100 | +/- 9.2 points | +/- 8.5 points |
| 250 | +/- 5.8 points | +/- 5.4 points |
| 400 | +/- 4.6 points | +/- 4.2 points |
| 1,000 | +/- 2.9 points | +/- 2.7 points |
| 2,000 | +/- 2.1 points | +/- 1.9 points |
| 5,000 | +/- 1.3 points | +/- 1.2 points |

Read the first row again: **at 100 games you cannot see a 5-point effect at
all.** A "tie" at 100 games over a 5-point question is underpowered, not
evidence of no difference, and must be labelled that way.

Every reported result carries, in one line: the anchor's SHA, the candidate's
SHA, `playerCount`, rules configuration, seed range, number of games, complete
rotation scheme, win rate **with its interval**, and decisive rate (see below).
A result missing any of those cannot be compared with the next one.

## Trap: the number that rises while strength does not

Measuring the candidate only against the current bot answers "does this beat
that one opponent", which is not the question anyone means. Three defences,
in order of cost:

1. **The anchor must be frozen and old.** Not "the bot as of this morning".
2. **Keep a second, dumber opponent in the pool** - a table of `playerCount`
   identical `balanced` policies is the cheapest one available today - so a
   candidate that has learned to exploit one specific policy shows up as
   improving against one arm and not the other.
3. **Report both numbers separately.** Never average them into a single
   "strength". They answer different questions and the gap between them is
   itself the diagnostic.

## Trap: two arms are two binaries, so record what you built

There is no `--weights` flag. A weight or heuristic change means editing
`Packages/CatanAI/Sources`, rebuilding, and getting a *different binary* - so
the two arms of a comparison are two builds from two working trees, not two
invocations. Practical shape: build the anchor, `cp` it aside (step 1), then
change the source and build the candidate. Keep both binaries until the run is
written up.

**The fingerprints are your check that the change reached play.** If the
candidate produces the same `fingerprint` as the anchor on the same seed,
`playerCount`, and rules configuration, the edit changed nothing about how the
game was played, and any win-rate difference you go on to measure is noise by
construction. Check one seed before spending the historical four-player run's
24 minutes.

## Trap: decide the scoring convention before you look at the results

The harness caps a game at 3,000 moves and emits `"winner":null` if it trips.
That did **not happen in the 350 four-player games measured for this historical
record** (212-824 moves, mean 462, zero unfinished). This is not evidence about
three-player completion. A change that makes bots passive is the change that
would cause it, and it is the kind of change that can look strong under a
careless convention.

**Score decisive games only, and report the decisive rate alongside.** Scoring
an unfinished game by some margin - VP at the cap, territory, resources -
rewards a policy that never loses because it never commits. GlobalConquest hit
precisely this: an agent that turtled scored well on margin-at-cutoff and was
not stronger. If the decisive rate drops between arms, that is the headline
result, not a footnote.

## Trap: 1 / playerCount, not 50%

An average bot wins one game per occupied seat: one in three at a three-player
table, one in four at a four-player table. Two habits follow, and both get
skipped:

- A "60% win rate" against `playerCount - 1` copies of the anchor is a **huge**
  effect, not a modest one - which should raise suspicion of a bug (an
  illegal-move crash scoring as a loss, a rotation not actually applied)
  before it raises confidence.
- The head-to-head framing that centres on 50% does not apply. If you want a
  50%-centred number, define it explicitly - e.g. paired per-seed
  candidate-beats-anchor - and say which one you used.

## Honest limits (do not overpromise)

- **No complete two-arm calibration is recorded in this file.** Historical
  four-player candidate-arm probes are real regression evidence, but they omit
  the separately built all-anchor control arm. No measured three-player
  strength evidence appears here yet.
- **The measurement is self-play only.** Every occupied seat is a bot. It says
  nothing about how the bots feel to a human, whether they are fun, or whether
  they are appropriately difficult - which is what Alex will actually be asked
  about.
- **Win rate is not the only thing that matters** and is a poor proxy for some
  of what does: game length, whether bots trade at all, whether they stall.
  The harness records moves and final VP; anything richer needs a new field.
- **The sample sizes are the unpaired ceiling.** Pairing on board seed should
  reduce them within each table-size stratum, by an amount nobody here has
  measured. Claiming the discount before measuring `rho` is exactly the kind
  of unearned confidence this file exists to prevent.
- **A power calculation is not a guarantee.** 80% power means one run in five
  misses a real effect of the size you sized for.
- **Personality mix is a confound in its own right.** The historical
  four-player default lineup is `balanced, aggressive, cautious, balanced` -
  three different policies at one table. At either table size, use identical
  opponents for a strength comparison and keep the shipped mix for product
  behaviour questions.

## Related

- **`.claude/skills/sim-harness/SKILL.md`** - the instrument. Every command in
  this file assumes that harness, its seed semantics, and its JSONL record.
- **`.claude/skills/verify-settlers/SKILL.md`** - a strength claim and a
  working app are two different claims. A bot change still has to survive the
  ladder before it goes to Jake.
- **`Packages/CatanAI/Sources/CatanAI/BotWeights.swift`** - the numeric policy,
  documented as existing "to be swept or trained". That sweep is the first real
  customer for this method.
- **`~/Documents/Personal Projects/GlobalConquest/.claude/skills/evaluate/SKILL.md`**
  - the mature version of this discipline on another of Alex's projects: CRN
  decisive-only head-to-head, pool-relative anchored Elo, power tables, and the
  two mirages (vs-heuristic exploitation, margin-at-cutoff turtling) that cost
  real time there. Read it before extending this one.
