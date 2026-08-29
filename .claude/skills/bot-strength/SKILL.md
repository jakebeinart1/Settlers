---
name: bot-strength
description: How to make an honest strength claim about a change to the Empires bots - paired evaluation over the same board seeds with seat rotation, a frozen anchor opponent, a sample sized to the effect, and a confidence interval instead of a bare win rate. Use before saying a heuristic or weight change made the bots better, before merging anything under `Packages/CatanAI/Sources`, and whenever the claim is "the bots are smarter now", "I ran 50 games and it won 60%", "this weight is clearly better", "the bots are too easy", "make them harder", or "trust me, it feels stronger". The null win rate at this table is **25%, not 50%** - four seats - and separating 25% from 30% at 95% confidence and 80% power needs about **1,248 games per arm**, which at the harness's measured ~0.5 games/sec is ~40 minutes per arm. A win rate against your own current heuristic is not strength; it can rise while true strength is flat, so never quote one without naming the frozen anchor it was measured against.
---

# Bot strength

**A win rate against your own current bot is not strength.** It is a measure of
how well the new policy exploits one specific opponent, and that number can
climb steadily while true strength does not move at all - you have found the
current bot's blind spot, not a better way to play Catan. Alex has already paid
for this exact mistake once, in GlobalConquest: a policy's win rate against the
scripted heuristic rose from 0.83 to 0.95 across a training run while its
anchored Elo against a fixed pool stayed flat. Nights were spent on that number.

**And the second failure is arithmetic, not philosophy.** Four seats means the
null win rate is **25%**, so "it won 60% of 50 games" is a statement with a 95%
confidence interval of roughly plus or minus 14 points. Almost every result
anyone reports informally is inside its own noise.

This skill is the method. It needs no code beyond what **sim-harness** already
provides.

## What has actually run

| Path | Status |
|---|---|
| **This method, end to end** | **NEVER RUN IN THIS REPO.** Not once. There is no paired evaluation, no seat rotation, no frozen anchor, no confidence interval, and no recorded result anywhere in the tree. Every number below is either a measured property of the harness or arithmetic. Do not cite this file as evidence that the bots are any particular strength. |
| **The harness underneath** | **RUN AND PROVEN 2026-08-29** - see **sim-harness**. Reproducible across processes, cross-checked against the five pinned fingerprints, ~0.5 games/sec per process and ~1.76 games/sec across 10 shards. |
| **Seat advantage, four identical `balanced` bots** | **MEASURED 2026-08-29, 200 games** (seeds 5000-5199): 21.0 / 20.0 / 27.5 / 31.5 percent by seat, an 11.5-point spread, `chi2 = 7.16, df = 3, p = 0.067`. **Suggestive, not established** - and that is the point. See "Rotate the seats" below. |
| **A frozen anchor opponent** | **DOES NOT EXIST.** There is no pinned anchor bot, no committed weight file, and no versioned baseline in this repo. `BotWeights.default` is the only policy and it moves whenever anyone edits it. **Creating the anchor is step 1 and it is real work, not a formality.** |
| **The variance reduction paired/CRN evaluation actually buys here** | **UNMEASURED.** Pairing on board seed reduces the required sample by roughly `(1 - rho)`, where `rho` is the per-seed correlation between arms - and `rho` has never been computed for this game. Every sample size below is therefore the **unpaired ceiling**. Measure `rho` from your first run; do not assume a discount you have not earned. |
| **Comparing two weight sets in one run** | **NOT POSSIBLE TODAY.** The harness exposes `--personalities` but not weights, so two arms are two separate binaries. See the trap below. |

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

Play the **identical** seed set with the anchor build and the candidate build.
Because the engine is reproducible across processes (that is the property
**sim-harness** proves), the same seed produces the same board, the same dev
card deck, and the same dice sequence for both arms. The board luck therefore
cancels between arms instead of being noise you have to pay sample size to
average away.

This is the whole reason cross-process determinism matters. Without it, "the
same seeds" is a sentence with no content.

### 3. Rotate the seats

**A seat is not a neutral container.** Turn order decides who places first in
setup, who places last-and-first at the turn, and who rolls first. Measured
here on 2026-08-29 with **four identical `balanced` bots over 200 games**, so
that every difference is turn order and nothing else:

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

Play every board seed **four times**, rotating which seat holds the candidate:

| Rotation | seat 0 | seat 1 | seat 2 | seat 3 |
|---|---|---|---|---|
| A | candidate | anchor | anchor | anchor |
| B | anchor | candidate | anchor | anchor |
| C | anchor | anchor | candidate | anchor |
| D | anchor | anchor | anchor | candidate |

Sum over the four rotations and the seat effect cancels exactly. Skip the
rotation and a candidate that happens to sit in a favourable seat looks
stronger by however large that effect is - which, on the numbers above, is
larger than most heuristic changes are ever going to be.

**Budget accordingly: one board seed is four games.** 1,248 games per arm is
312 board seeds.

### 4. Size the sample to the effect, before running

For two independent proportions at `alpha = 0.05` two-sided and `power = 0.80`:

```
n per arm = (z_{alpha/2} + z_beta)^2 * [p1(1-p1) + p2(1-p2)] / (p1 - p2)^2
          = (1.960 + 0.842)^2 * [p1(1-p1) + p2(1-p2)] / (p1 - p2)^2
```

Worked for the case in the description - baseline 25% (four seats), candidate
30%, i.e. **a 5-point win-rate difference**:

```
(2.802)^2 = 7.849
p1(1-p1) = 0.25 * 0.75 = 0.1875
p2(1-p2) = 0.30 * 0.70 = 0.2100
n = 7.849 * (0.1875 + 0.2100) / (0.05)^2 = 7.849 * 0.3975 / 0.0025 = 1,248
```

**1,248 games per arm, 2,496 games total, 312 board seeds x 4 rotations.**

| Effect to distinguish | games per arm | total | wall clock at 1.76 games/sec (10 shards) |
|---|---|---|---|
| 25% vs 35% (10 points) | 326 | 652 | ~6 min |
| 25% vs 30% (5 points) | 1,248 | 2,496 | ~24 min |
| 25% vs 28% (3 points) | 3,394 | 6,788 | ~64 min |
| 50% vs 55% (head-to-head framing) | 1,562 | 3,124 | ~30 min |

**The rotation buys back half of that, and it is worth understanding why.**
Full seat rotation makes 25% the *exact* null rather than a second quantity you
have to estimate: if the candidate were byte-identical to the anchor, its win
rate summed over the four rotations would be 25% by the symmetry of the design,
whatever the seat effect turns out to be. That makes this a **one-sample**
proportion test against a known `p0`, with

```
n = [ z_{alpha/2} * sqrt(p0(1-p0)) + z_beta * sqrt(p1(1-p1)) ]^2 / (p1 - p0)^2
  = [ 1.960*sqrt(0.1875) + 0.842*sqrt(0.2100) ]^2 / (0.05)^2
  = (0.8487 + 0.3857)^2 / 0.0025 = 610
```

| Effect | one-sample games | board seeds | at 1.76 games/sec |
|---|---|---|---|
| 25% -> 35% | 157 | 40 | ~1.5 min |
| 25% -> 30% | 610 | 153 | ~6 min |
| 25% -> 28% | 1,672 | 418 | ~16 min |

Use the two-sample numbers when you are **not** confident the null is exactly
25% - an incomplete rotation, an odd number of seats in the pool, a candidate
that changes the *anchor's* behaviour (a trade heuristic does; a placement
heuristic mostly does not). The extra cost of being conservative is about
twenty minutes.

Single-process, all of these are ~4x longer (measured 0.45-0.51 games/sec).
Either way, **the cost of adequate power here is minutes, not days** - which
removes the only honest excuse for running 50 games and reporting a win rate.

### 5. Report the interval, never the point

The 95% interval on a measured win rate `p` from `n` games is
`p +/- 1.96 * sqrt(p(1-p)/n)`. Around the 25% null:

| games | 95% CI half-width |
|---|---|
| 100 | +/- 8.5 points |
| 250 | +/- 5.4 points |
| 400 | +/- 4.2 points |
| 1,000 | +/- 2.7 points |
| 2,000 | +/- 1.9 points |
| 5,000 | +/- 1.2 points |

Read the first row again: **at 100 games you cannot see a 5-point effect at
all.** A "tie" at 100 games over a 5-point question is underpowered, not
evidence of no difference, and must be labelled that way.

Every reported result carries, in one line: the anchor's SHA, the candidate's
SHA, the seed range, the number of games, the rotation scheme, the win rate
**with its interval**, and the decisive rate (see below). A result missing any
of those cannot be compared with the next one.

## Trap: the number that rises while strength does not

Measuring the candidate only against the current bot answers "does this beat
that one opponent", which is not the question anyone means. Three defences,
in order of cost:

1. **The anchor must be frozen and old.** Not "the bot as of this morning".
2. **Keep a second, dumber opponent in the pool** - four `balanced` seats is
   the cheapest one available today - so a candidate that has learned to
   exploit one specific policy shows up as improving against one arm and not
   the other.
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
candidate produces the same `fingerprint` as the anchor on the same seed, the
edit changed nothing about how the game was played, and any win-rate
difference you go on to measure is noise by construction. Check one seed before
spending 24 minutes.

## Trap: decide the scoring convention before you look at the results

The harness caps a game at 3,000 moves and emits `"winner":null` if it trips.
That has **never happened** in the 350 games measured so far (212-824 moves,
mean 462, zero unfinished) - but a change that makes bots passive is the change
that would cause it, and it is the kind of change that can look strong under a
careless convention.

**Score decisive games only, and report the decisive rate alongside.** Scoring
an unfinished game by some margin - VP at the cap, territory, resources -
rewards a policy that never loses because it never commits. GlobalConquest hit
precisely this: an agent that turtled scored well on margin-at-cutoff and was
not stronger. If the decisive rate drops between arms, that is the headline
result, not a footnote.

## Trap: 25%, not 50%

Four seats. A bot that is exactly average wins one game in four. Two habits
follow, and both get skipped:

- A "60% win rate" against three copies of the anchor is a **huge** effect, not
  a modest one - which should raise suspicion of a bug (an illegal-move
  crash scoring as a loss, a rotation not actually applied) before it raises
  confidence.
- The head-to-head framing that centres on 50% does not apply. If you want a
  50%-centred number, define it explicitly - e.g. paired per-seed
  candidate-beats-anchor - and say which one you used.

## Honest limits (do not overpromise)

- **Nothing in this file has been run.** The method is sound and the arithmetic
  is checked; no strength claim about the Empires bots exists yet, and this
  skill is not one.
- **The measurement is self-play only.** All four seats are bots. It says
  nothing about how the bots feel to a human, whether they are fun, or whether
  they are appropriately difficult - which is what Alex will actually be asked
  about.
- **Win rate is not the only thing that matters** and is a poor proxy for some
  of what does: game length, whether bots trade at all, whether they stall.
  The harness records moves and final VP; anything richer needs a new field.
- **The sample sizes are the unpaired ceiling.** Pairing on board seed should
  reduce them, by an amount nobody here has measured. Claiming the discount
  before measuring `rho` is exactly the kind of unearned confidence this file
  exists to prevent.
- **A power calculation is not a guarantee.** 80% power means one run in five
  misses a real effect of the size you sized for.
- **Personality mix is a confound in its own right.** The default lineup is
  `balanced, aggressive, cautious, balanced` - three different policies at one
  table. Use four identical opponents for a strength comparison, and keep the
  mixed lineup for questions about the shipped game.

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
