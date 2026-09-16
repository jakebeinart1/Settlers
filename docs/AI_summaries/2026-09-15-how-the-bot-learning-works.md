# How the bot learning works, end to end

**Date:** 2026-09-15
**For:** Jake, who asked to be taught the whole process in detail.

This is the complete pipeline behind the Empires bots: what the bot actually
is, how it decides, how it gets trained, how strength is measured, and which
parts are real machine learning versus ordinary engineering. Every number here
was measured in this repository.

---

## 1. The honest headline: there is no neural network

When people say "AI bot" they usually picture a neural network trained on
millions of games. **That is not what ships here, and twice it was tried and
failed.**

- A learned value function reached **67.7% sign accuracy against a 74.0%
  baseline** — worse than guessing the majority answer.
- An imitation policy trained on bot games went **0 for 40**.

What ships is a **hand-designed evaluation function with machine-tuned
numbers**. The structure is written by a person; the numbers inside it are
fitted by an optimiser. That is a real and respectable form of machine
learning — it is how strong chess and Catan engines worked for decades — but it
is worth being precise, because "we trained a bot" invites a picture that is
not this.

The one published attempt to do it the neural way in Catan (PPO, custom
attention network, 450M decisions, a month on a 3090) plateaued and its author
said it "doesn't feel close to the standard of a good human player." That is
the bar full RL has to clear, and it is why this project spends its effort
elsewhere.

---

## 2. The stack, from rules to decision

```
GameState  ──►  EvaluationPolicy  ──►  PositionEvaluator  ──►  EvaluationWeights
(the rules)     (picks a move)         (scores a position)     (19 numbers)
```

**`CatanEngine`** owns the rules: what is legal, what a move does, the dice,
the deck. It knows nothing about bots.

**`EvaluationPolicy`** is the bot. Its whole algorithm is three lines of
English:

1. List every legal move.
2. Apply each one to a copy of the game and score the position it leads to.
3. Play the move with the best score.

That is a **one-ply search**: it looks one move ahead. No tree, no rollouts.

**`PositionEvaluator`** turns a position into a single number. It measures
features of the board — victory points, production per turn, resource variety,
room to expand, hand shape, knights, road length, ports — multiplies each by a
weight, and adds them up.

**`EvaluationWeights`** is those 19 numbers. This is the part that gets
trained.

### The one idea that makes it play like a competitor

The score is not "how good am I". It is:

```
my standing  −  rival × (best opponent's standing)
```

That subtraction is your rule — *relative position over absolute gain*. A trade
that helps you and the leader equally scores near zero; one that helps the
leader more scores negative. It is also why the bot will hand three cards to a
player who cannot win: helping someone who is not the strongest rival costs
almost nothing.

`rival` is currently 0.92. When the optimiser was free to drive it to zero —
"play your own game, ignore the table" — it did not. That is the closest thing
to independent evidence your principle is correct.

---

## 3. What "training" means here: SPSA

The structure is fixed; training only moves the 19 numbers.

### Why not ordinary gradient descent

Gradient descent needs a derivative. There is no derivative of "win rate" with
respect to `handCard` — the only way to find out is to *play games*, and the
answer comes back as noisy win/loss counts. This is **black-box optimisation of
a noisy function**, a different problem from training a network.

### Why not a grid search

19 weights. Even three values each is 3¹⁹ ≈ 1.2 billion combinations, and each
one costs hundreds of games. Impossible.

### SPSA: Simultaneous Perturbation Stochastic Approximation

The trick that makes it affordable:

1. Pick a random direction — flip a coin per weight, ±1.
2. Play a batch of games with all weights nudged **that** way (`θ + cΔ`).
3. Play the same batch with all weights nudged **the opposite** way (`θ − cΔ`).
4. Whichever did better, step the weights that way.

The magic is step 2 and 3: **two evaluations estimate a gradient in all 19
dimensions at once**, regardless of how many weights there are. A naive
approach would need 19 separate measurements.

### Common random numbers

Both probes play the **identical seed set** against the **identical
opponents**. Same boards, same dice, same deck order. So the difference between
them is the weights and nothing else — board luck cancels instead of being
noise the sample size has to absorb. Without this, a 300-game batch tells you
almost nothing.

### Sign-SPSA, and a bug worth learning from

Textbook SPSA divides by the perturbation size to get a gradient, then
multiplies by a learning rate. Get the constants wrong and you move nowhere.

**That happened here.** The first sweep stepped each weight **0.056% per
iteration** — about 1% over an entire three-hour run. It would have reported
"no improvement found", and that conclusion would have been an artefact of my
arithmetic, not a fact about the weights. The tell: the three most-moved
weights were *different every iteration* — a real search settles on a
direction; that was a random walk.

The fix is **sign-SPSA**: take the *direction* of the difference at full step,
and use its magnitude only to shrink a step the evidence does not support.
Step size then went 4.5% → 1.7% per iteration as the run settles.

### What is frozen and why

- `victoryPoint = 1.0` — the **ruler**. Every other weight means "worth this
  much of a victory point". Let it move and the whole scale slides.
- `winning = 1000` — a dominance constant, not a trade-off. Reaching the target
  is the end of the comparison, not "worth a lot of points".
- `tradeMargin = 0` — frozen by your rule: the bot may never buy strength by
  accepting worse trades.

Bounds keep each weight's sign, because a negative `approach` or a positive
`sevenLoss` has no meaning in the game, only in the arithmetic.

---

## 4. Measuring strength: the part that is easy to fake

Training is the easy half. **Knowing whether the result is real is the hard
half**, and it is where most bot projects fool themselves.

### The null is 1 / playerCount

Four seats means an average bot wins **25%**, not 50%. A "60% win rate" is a
huge effect, not a modest one — and should raise suspicion of a bug before it
raises confidence.

### Sample size

A 5-point difference needs **1,248 games per arm**. At 100 games the
uncertainty is ±8.5 points, so a 5-point effect is invisible. Almost every
informally reported bot result is inside its own noise.

### Rotate every chair

Turn order matters: measured here, four *identical* bots won 21.0 / 20.0 / 27.5
/ 31.5 percent by seat — an 11.5-point spread, bigger than most changes being
measured. So each board seed is played four times with the candidate in each
chair. The seat effect then cancels exactly.

### Held-out seeds

Seeds used for training are never used for reporting. Otherwise the number says
"how well did I fit those particular boards".

### A frozen anchor

The opponent is a specific binary, built once and kept. Rebuild it and today's
number is not comparable with last week's.

### A control arm

Run the *unmodified* bot through the identical rig. It must come back at
exactly 25.0%. When it does, the rig is proven correct and the candidate's
number means something. This has caught real rig bugs.

### Paired tests

Both arms play the same boards, so the comparison is paired: count the games
where exactly one arm won and run **McNemar's test**. Far more sensitive than
comparing two independent percentages.

### Score decisive games only — and count stalls as losses when training

A game that never finishes is scored as a loss for everyone during training.
Otherwise an optimiser discovers it can protect its win rate by **stalling**,
which is exactly the failure that had to be fixed twice in Expanded mode.

---

## 5. The trap this project keeps proving

**Training against yourself teaches you to exploit yourself.**

The first sweep trained Expert against Expert. Result:

| measured against | before | after |
|---|---:|---:|
| the opponent it trained on | 25.0% | **67.2%** |
| the shipping bot it never saw | 42.5% | **47.3%** |

A policy that truly got much stronger moves both. **42 points against itself,
5 against a stranger** means most of what it learned was one opponent's blind
spots. The honest number is the smaller one.

Had only the training arm been run, the report would have been "67% win rate" —
and it would have been wrong. This is why held-out validation against an
opponent the sweep never played is not optional. The next step on the roadmap
is an opponent *this repository did not design* (Catanatron, run as an external
benchmark), because even `balanced` is our own.

---

## 6. The tools, and when to use which

| tool | question it answers | cost |
|---|---|---|
| `trade-bench` | what does it *do* — offers, acceptance, bundles, builds | ~60s |
| `sim` | does it *win* more | 20+ min |
| `compare_models.py` | new vs old, paired, per table mix | ~30 min |
| `sweep2.py` | find better weights | 1–3 h |
| `validate2.py` | do the new weights hold up on unseen games | ~30 min |

```bash
# behaviour, fast
swift run --package-path Packages/CatanAI -c release trade-bench --games 16

# strength, slow but real
swift run --package-path Packages/CatanAI -c release sim \
  --games 312 --seed 95000 --seats eval,balanced,balanced,balanced --jsonl
```

`trade-bench` exists because waiting 20 minutes to see a behaviour change made
every trading experiment slow enough to *guess* instead of *measure*. It plays
**real games through the real engine** with real opponents — the only thing it
skips is playing enough of them to compute a win rate, which is why it never
prints one.

---

## 7. What the training actually found

The sweep's biggest correction was one thing, not twelve:

| weight | hand-set | fitted | change |
|---|---:|---:|---:|
| `handCard` | 0.020 | 0.065 | **+223%** |
| `discardExposure` | −0.120 | −0.057 | **+53%** |
| everything structural | — | — | <5% |

Both say the same thing: **a card in hand is worth far more than the risk of
holding it through a seven.** The hand-set values had the bot bank-trading
cards away to duck the discard limit; it was paying certain cards to avoid a
probable loss, and emptying the hand its trading runs on.

That also answers the question from play — yes, Expert loses ~9 cards a game to
sevens against the shipping bot's 1.9, and *plugging that leak measurably loses
games*: pricing expected discard losses dropped it from 57.5% to 39.0%.

---

## 8. What is deliberately not machine-learned

- **The features.** Which things matter — production, expansion room, hand
  shape — is a design decision. An optimiser tunes numbers; it cannot invent a
  term that is missing. Every large gain this project has had came from adding
  a *missing* term (sites more than one road away, the counterparty's gain in a
  trade), not from tuning existing ones.
- **The search.** One ply, plus a two-hand shortcut for trades. Deeper search
  is an open lever: the app already pauses 600ms per bot move for presentation,
  which is free thinking time nothing spends.
- **The opponent model.** Expert models an opponent with its *own* evaluation.
  That is why the first trade cascade failed: it filtered offers by what it
  believed opponents would accept, and the shipping bots value cards
  completely differently.

---

## 9. Where real ML would go next

Two candidates, in order of how much they are likely to buy:

1. **Deeper search.** Not learning at all, but the cheapest real strength left.
2. **Player-imitation ghost bots** (your idea, in `TODO.md`). This is the one
   that genuinely needs a learned policy, because the thing being modelled is a
   *person*, and no hand-written evaluation can be that person. The plumbing
   exists — recorded games, masked policy/value examples, replay — and the
   modelling is the open research question, with two prior failures here as the
   honest prior.
