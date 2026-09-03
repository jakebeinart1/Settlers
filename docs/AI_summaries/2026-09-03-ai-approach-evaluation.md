# AI approach evaluation and prototype order

Date: 2026-09-03
Status: short-horizon P1 and first P2 learned policy rejected

## Decision

Keep the measured heuristic as the shipping policy and prototype **bounded
rollout search** first. Then test a small masked policy/value model offline.
Do not start with direct LLM move inference or claim that a two-player
AlphaZero/ReBeL recipe transfers unchanged.

This order is not a conclusion that search will ultimately be strongest. It is
the cheapest experiment that can falsify the most important assumptions using
the engine and evaluation system we already trust:

1. Can looking ahead beat the heuristic under a phone-sized latency budget?
2. Is the current state/action abstraction sufficient outside SwiftUI?
3. Can we create useful policy/value training targets without weakening legal
   action masking or deterministic replay?

## Constraints from this game

- Three or four players, stochastic dice/cards, negotiation, and potentially
  hidden hands. This is neither deterministic chess nor a two-player zero-sum
  poker game.
- The current four-seat action layout has 9,295 stable indices but only a small legal
  subset at each decision. Every learned/search policy must consume the exact
  mask; an unmasked output is invalid by construction.
- A full match takes hundreds of actions. Phone inference must fit inside the
  existing pacing delay rather than adding seconds to every bot decision.
- `GameState` currently reaches policies in full. Alex explicitly parked the
  hidden-information decision, so perfect-information search may be used as a
  diagnostic upper-bound prototype, but cannot be called fair or shippable.
- Strength claims remain paired, chair-rotated comparisons against a frozen
  anchor. Personality metrics remain separate from strength.

## Evidence boundaries

- Gendre and Kaneko describe Catan as multiplayer, imperfect-information,
  stochastic, spatially heterogeneous, and negotiation-heavy; their result is
  evidence that learned Catan play is possible and that structure matters, not
  that their architecture automatically fits this rules implementation:
  https://arxiv.org/abs/2008.07079
- OpenSpiel documents AlphaZero as self-play MCTS for **perfect-information**
  games, with policy and value network outputs, and its supplied model path as
  parameterized for **two-player** games. Empires violates both assumptions:
  https://github.com/google-deepmind/open_spiel/blob/master/docs/alpha_zero.md
- ReBeL extends search plus learning to imperfect information, but its
  convergence claim is for **two-player zero-sum** games. That is not a direct
  theoretical fit for three/four-player Catan with trades:
  https://arxiv.org/abs/2007.13544
- OpenSpiel lists IS-MCTS, MCTS, CFR, PPO, AlphaZero and other families. The
  existence of implementations is useful engineering reference, not evidence
  that one wins on this environment:
  https://github.com/google-deepmind/open_spiel/blob/master/docs/algorithms.md

## Prototype sequence and kill criteria

### P1 — bounded rollout search

Use the real `GameSession`, legal moves, seeded randomness, and heuristic
rollout policies. Search only when multiple meaningful main-turn actions are
legal; delegate forced/setup/response moves to the heuristic. First run with
full state as an explicitly labeled upper-bound experiment.

Keep only if all are true:

- every selected move belongs to the supplied action mask;
- repeated calls with the same observation and RNG are identical across
  processes;
- p95 decision latency is measured at budgets suitable for a local device;
- every supported 3/4-player, 8/10/12-point configuration completes;
- a paired frozen-anchor evaluation shows either useful strength signal or a
  clear diagnostic about what the evaluator/search horizon lacks.

### P2 — masked policy/value baseline

Export `(layoutVersion, features, legalMask, chosenAction, outcome)` from
seeded self-play. Train a deliberately small baseline before a specialized
board network. This proves the data contract, masking, checkpoint provenance,
and on-device conversion path. Compare policy imitation accuracy, calibration,
inference latency, and actual game strength; offline loss alone cannot select a
model.

### P3 — self-play improvement

Only after P2 is reproducible, compare masked actor-critic/PPO and policy-value
search training. Preserve four-player rewards and seat rotation; do not import
a two-player 50% null hypothesis. A learned checkpoint must beat both the
frozen Greedy anchor and the shipping heuristic under the established sample
size rules before receiving a difficulty label.

### P4 — imperfect-information treatment

Once hidden hands become a product requirement, replace the full-state
prototype with an observation/information-state contract and sampled beliefs
or determinizations. Re-run all strength and personality evidence. Results from
the full-state upper bound do not survive this change automatically.

### P5 — language-model role

Keep language generation outside legal move execution initially: negotiation
voice, explanations, summaries, and possibly a low-frequency strategic intent
that a deterministic masked policy may accept or reject. Direct per-action LLM
inference remains a later experiment because it adds network availability,
latency, cost, nondeterminism, and schema-validation failure modes without
removing the need for the legal policy underneath it.

## Explicitly not decided

- Final algorithm or model family.
- Cloud versus local training hardware.
- Hidden-hand fairness.
- Difficulty tiers.
- Whether an LLM supplies strategic intent after the deterministic/search and
  learned-policy baselines exist.

Every prototype must remain a replaceable `Policy` and must not enter the app
roster until measured.

## P1 result — short-horizon configuration rejected

The prototype used the real `GameSession`, common seeded futures, the shipping
heuristic as its fallback and rollout policy, and the existing threat score as
its leaf evaluator. It searched only main-turn choices and never entered the
app roster.

Two budgets exposed a development-time tradeoff. These timings are from a
Debug Mac build, **not** an optimized iPhone benchmark; they cannot establish
deployment latency:

- One rollout, eight-action horizon, six candidates: 59.1 ms median, 1,038.2 ms
  p95, and 4,025.4 ms maximum across 432 evaluated decisions in three complete
  games. This warrants a Release/device measurement before any deployment
  decision; it does not by itself reject the larger budget.
- One rollout, two-action horizon, three candidates: 2.0–3.1 ms median and
  349.8–481.2 ms p95 across 5,470 evaluated decisions in 40 complete games.
  This was below the normal pacing interval at p95 and completed one game in every supported
  3/4-player × 8/10/12-point cell, but was materially weaker.

On seeds 42000–42009, with both policies rotated through every chair against
three frozen Greedy anchors, the reduced rollout won 24/40 games (60.0%) while
the existing Balanced heuristic won 35/40 (87.5%). The paired difference was
−27.5 percentage points with a seed-cluster bootstrap 95% interval of −42.5 to
−12.5. All 80 games were decisive. This sample is enough to reject a large
negative result; it is not being used to advertise a positive strength claim.

The short horizon re-scores near-term consequences using the same heuristic
that selected the fallback. My inference is that this perturbs good heuristic
choices without enough horizon or value-model accuracy to compensate. The
measured small-budget configuration fails P1's keep criteria and its
implementation was removed rather than retained as dormant production code.
This does **not** disprove rollout search or larger budgets: those need a
separate paired evaluation and Release/device timing. P2 is the next experiment
because it tests the data contract and can provide a learned value estimate,
not because search has been conclusively ruled out.

## P2 entry gate

Proceed to P2: export versioned, masked training examples from deterministic
self-play, validate replay/provenance, and train a deliberately small imitation
baseline. That experiment can test the state/action contract and provide the
value estimate missing from P1 without changing the shipping bot.

### P2 contract audit before export

The existing abstractions are close, but exporting them unchanged would create
a dataset that cannot represent three decisions correctly:

1. The numeric vector records only the **count** of pending offers. A response
   action is indexed by offer position, but the model cannot see that offer's
   proposer, give bundle, or want bundle. It therefore cannot learn why slot
   `respondToTrade(3, accept)` is good or bad.
2. The vector records ports already owned by each seat, but not the static port
   kind attached to each shoreline vertex. A settlement policy can see a legal
   vertex and its adjacent production, but cannot learn the future 2:1 or 3:1
   access granted by building there.
3. Seat blocks are egocentric while robber-victim action indices use absolute
   player IDs. The dataset must either make the observer's absolute chair
   explicit or canonicalize victim actions into the same egocentric frame.

These are silent information defects, not model-quality concerns. Training
before resolving them would produce a model that fits contradictory examples.
The next engine change must bump `StateEncoding.layoutVersion`, add regression
tests proving all three distinctions survive encoding, and keep a single fixed
four-chair action width for both three- and four-player games (nonexistent-chair
victims remain masked). Only then should the simulator export records with:

- dataset schema version and build/checkpoint provenance;
- state-layout and action-layout versions;
- observer seat, player count, seed, trajectory step, and final outcome;
- the fixed-width numeric features;
- sparse legal action indices representing the full mask;
- the chosen global action index.

The exporter must fail if a legal or chosen move has no index. A structural
validator must reject malformed sparse masks and chosen actions outside them
before training sees a byte; independent mask reconstruction would require
exporting replayable game state and is not claimed by this compact format.

### P2 contract resolution

`StateEncoding` layout v3 resolves those three blockers before any exporter is
allowed to exist. It has 5,182 fixed features: exact rows for all 256 indexed
pending-offer positions, six static port-kind slots on every canonical vertex,
and an absolute observer-chair one-hot plus table-size scalar. Three regression
tests were observed failing against v2 before the implementation and now pass;
the cross-process encoding fingerprint was deliberately repinned after the
version bump. Three-player states retain the same width and use the same
four-chair action space, so nonexistent victims are represented only as masked
actions rather than by a second model shape.

## P2 partial result — deterministic export and lower-bound baseline

The simulator now optionally writes one `TrainingExample` JSONL record per
policy evaluation while keeping its ordinary game stream unchanged. The Swift
constructor enforces the live state/action contract. A separate Python
validator enforces the serialized schema, provenance, feature bounds,
contiguous evaluations, winner-derived outcomes, and chosen-action membership
in the serialized legal mask. It cannot independently reconstruct the complete
legal mask from the deliberately compact feature vector. One 512-decision game exported
in two separate processes was byte-identical in full (5,685,786 bytes), not
merely equal after parsing.

The held-out baseline used 20 complete Release self-play games, seeds
53000–53019, with the measured Balanced/Aggressive/Cautious/Balanced roster:

- 11,687 validated examples total;
- 9,036 examples from 16 whole-game training seeds;
- 2,651 examples from four disjoint whole-game test seeds;
- 1,525 held-out decisions with more than one legal action.

The phase-conditioned masked action prior reached **31.5% top-1 imitation
accuracy**, versus **14.1% expected accuracy** for uniform choice over each
position's legal moves, and selected zero illegal actions by construction. This
proves that the action indices, masks, labels, and whole-seed split carry a
learnable signal. It is not a game-strength result.

The linear value baseline reduced held-out mean absolute error from **0.773**
for the training-set constant mean to **0.626**, but its **69.8% sign accuracy
was worse than the 74.0% majority-sign comparator**. It is therefore not fit to
guide search. The result is useful precisely because it blocks a weak value
estimate from being promoted on the basis of loss alone.

The checkpoint format records schema/layout versions, explicit hidden-information
policy, build and dataset provenance, teacher-policy counts, exact training
seeds, hyperparameters, phase/action counts, and value weights. Its loader
rejects incompatible layouts, provenance, information policy, or weight width.
Two fits over the same corpus produced byte-identical metrics and checkpoints;
the corrected checkpoint SHA-256 is
`dd9bd0ab1f3f2344ea8fc91badab57d26ab55f100727841d32b30c6e8bc57578`.
Raw datasets and checkpoints remain generated artifacts outside git.

This is only the lower-bound portion of P2. It does not yet establish on-device
checkpoint conversion, inference latency, calibration, or paired game strength,
and it does not pass the value-model quality gate.
## P2 state-conditioned screening result — rejected

A deterministic 64-feature signed-hash projection was trained over the same
whole-game split as a deliberately small state-conditioned policy/value
experiment. It improved held-out policy imitation from **31.5% to 42.4%**
top-1 accuracy, with zero illegal selections and calibration error **0.061**.
Its value estimate still failed the comparator: **0.637 MAE** beat the constant
mean's 0.773, while **67.7% sign accuracy** remained below the 74.0% majority
sign baseline.

Offline imitation did not translate into play. Against three frozen greedy
anchors over ten seeds and all four seat rotations, the projected policy went
**0/40**. It proposed a player trade in 50.6% of proposal opportunities, played
a knight in only 0.2% of 1,831 playable-knight opportunities, and built just
0.175 settlements and 0.075 cities per game. The adapter initially exposed a
separate identity bug by reconstructing indexed trade proposals with a
different UUID; returning the original legal move fixed that experiment-only
crash, after which all 40 games completed decisively.

The candidate is rejected and its runtime/training implementation is not kept
in the product branch. The useful result is the evaluation boundary: improved
teacher imitation is insufficient evidence of Catan strength, and the present
teacher corpus strongly overrepresents locally plausible actions that do not
produce a winning long-horizon policy. A future learned candidate needs either
search/value targets or self-play improvement, and must pass actual
seat-rotated gameplay screening before any on-device integration work.

## Difficulty calibration protocol — locked before the run

The first difficulty experiment is an **anchor-validation screen**, not a UI
label and not a five-point strength claim. It asks whether the shipping
Balanced heuristic is materially stronger than the frozen Greedy anchor in
every rules configuration the New Game screen supports. Greedy remains an
evaluation anchor; this protocol does not approve presenting it as an Easy
personality because Greedy intentionally never trades and therefore erases a
player-visible personality axis.

The Release simulator is built once from the settled source tree, copied aside,
and identified by both source commit and binary SHA-256. Candidate and control
use that same binary:

- candidate arm: one `heuristic-balanced` chair against Greedy in every other
  occupied chair;
- control arm: the evaluated chair and every opponent use Greedy;
- complete rotation through all three or four occupied chairs;
- one configuration per analyzer invocation; no pooling across table sizes,
  victory targets, or board modes;
- decisive games only, with the decisive rate reported separately;
- seed-cluster bootstrap intervals, with every chair rotation from one board
  seed kept in the same cluster.

The held-out corpus is 40 unique board seeds per cell, 480 seeds total:

| Players | VP | Board | Seeds | Games per arm |
| ---: | ---: | --- | --- | ---: |
| 3 | 8 | standard | 80000–80039 | 120 |
| 3 | 8 | randomized | 80040–80079 | 120 |
| 3 | 10 | standard | 80080–80119 | 120 |
| 3 | 10 | randomized | 80120–80159 | 120 |
| 3 | 12 | standard | 80160–80199 | 120 |
| 3 | 12 | randomized | 80200–80239 | 120 |
| 4 | 8 | standard | 80240–80279 | 160 |
| 4 | 8 | randomized | 80280–80319 | 160 |
| 4 | 10 | standard | 80320–80359 | 160 |
| 4 | 10 | randomized | 80360–80399 | 160 |
| 4 | 12 | standard | 80400–80439 | 160 |
| 4 | 12 | randomized | 80440–80479 | 160 |

That is 1,680 games per arm and 3,360 total. These counts are deliberately
larger than a smoke test but are not powered to resolve a five-percentage-point
difference. The predeclared keep criteria are instead a large-separation gate:

1. every game is decisive and remains below the 3,000-move cap;
2. each all-Greedy control cell equals its exact full-rotation null—33.3% for
   three players and 25% for four—or the rig is invalid;
3. in every cell, the paired 95% interval for Balanced minus control excludes
   zero on the positive side; and
4. in every cell, the point advantage is at least 20 percentage points.

The seeds are never used to tune a candidate. Passing establishes that the two
policies form distinct strength anchors across supported rules. It does not
establish that either is fun for a human or authorize a difficulty selector.
The next tier candidate must preserve personality, use a new held-out seed
range, and pass the same per-cell structure before product integration.

## Difficulty calibration result — failed as designed

The locked run was completed without changing the protocol: **3,360 games**
(1,680 candidate and 1,680 control records) from one frozen Release executable.
Balanced was clearly stronger than Greedy in every cell, but the calibration
**failed** the predeclared gate. Three- and four-player 12-point games exposed
non-termination at the 3,000-move cap, and the three-player, standard-board,
10-point cell cleared zero but missed the required 20-point separation.

| Players | VP | Board | Balanced wins | Control wins | Difference (95% CI) | Decisive candidate / control | Gate |
| ---: | ---: | --- | ---: | ---: | ---: | ---: | --- |
| 3 | 8 | standard | 73/120 (60.8%) | 40/120 (33.3%) | +27.5 (+19.2, +35.8) | 120/120 · 120/120 | pass |
| 3 | 8 | randomized | 92/120 (76.7%) | 40/120 (33.3%) | +43.3 (+34.2, +51.7) | 120/120 · 120/120 | pass |
| 3 | 10 | standard | 58/120 (48.3%) | 40/120 (33.3%) | +15.0 (+5.8, +24.2) | 120/120 · 120/120 | **fail: margin** |
| 3 | 10 | randomized | 106/120 (88.3%) | 40/120 (33.3%) | +55.0 (+49.2, +60.0) | 120/120 · 120/120 | pass |
| 3 | 12 | standard | 87/120 (72.5%) | 40/120 (33.3%) | +39.2 (+30.8, +46.7) | 120/120 · 120/120 | pass |
| 3 | 12 | randomized | 102/120 (85.0%) | 39/117 (33.3%) | +51.7 (+45.0, +58.3) | 120/120 · 117/120 | **fail: completion** |
| 4 | 8 | standard | 131/160 (81.9%) | 40/160 (25.0%) | +56.9 (+50.0, +63.7) | 160/160 · 160/160 | pass |
| 4 | 8 | randomized | 117/160 (73.1%) | 40/160 (25.0%) | +48.1 (+40.6, +55.6) | 160/160 · 160/160 | pass |
| 4 | 10 | standard | 137/160 (85.6%) | 40/160 (25.0%) | +60.6 (+53.8, +66.2) | 160/160 · 160/160 | pass |
| 4 | 10 | randomized | 134/160 (83.8%) | 40/160 (25.0%) | +58.8 (+52.5, +64.4) | 160/160 · 160/160 | pass |
| 4 | 12 | standard | 139/159 (87.4%) | 40/160 (25.0%) | +62.4 (+57.4, +67.4) | 159/160 · 160/160 | **fail: completion** |
| 4 | 12 | randomized | 140/157 (89.2%) | 34/136 (25.0%) | +64.2 (+58.5, +69.3) | 157/160 · 136/160 | **fail: completion** |

All-Greedy controls retained the exact full-rotation null among decisive games,
so the rotation and scoring rig behaved correctly. The 31 timeout records came
from repeated chair rotations over a smaller set of board seeds. All-Greedy
timed out on seed 80233 in the three-player randomized 12-point cell and seeds
80443, 80448, 80449, 80452, 80457, and 80467 in the four-player randomized
12-point cell. Four candidate games also timed out: seed 80405 on the standard
four-player board, and seeds 80457, 80464, and 80479 on randomized four-player
boards. Every timeout reached exactly 3,000 moves with at least one seat on 11
points, which is a real inability to close rather than a crashed simulation.

This rejects Greedy as a product **Easy** tier. It deliberately omits player
trades, erases a visible personality axis, and can fail to finish the match.
Balanced remains the shipping behavior, but this experiment alone does not
justify calling it Standard or assigning any human-facing difficulty label.
The next candidate must retain personality behavior and be measured first on
new development seeds and then once on untouched held-out seeds.

### Frozen-run provenance

- source commit: `186ed8364e4ebbcbddc05392dd962ef0af79bb21`
- simulator build ID: `sha256-10eef33e6442`
- simulator SHA-256: `10eef33e6442b4ff09abcf502dd7582aed7a3630485971884001e892806d59bd`
- raw records: 84 JSONL shards, 3,360 rows; sorted per-file checksum-manifest
  SHA-256 `7774445f0373347ed76c2f2fd8ee8ebe518c085674702112ca1d118eb59d70ec`
- 12 analysis reports; sorted per-file checksum-manifest SHA-256
  `57e89c890ac6152c48788201a58e028579a477c0b23746c338857491cd17516d`
- retained local artifact root: `/private/tmp/empires-calibration.IlfiFb`

The artifact root is intentionally not committed: the JSONL is reproducible
measurement output, while this document preserves the protocol, verdict,
aggregate results, and integrity identifiers that the source branch must carry.

## Easy candidate protocol — locked before development measurement

Difficulty and personality are separate axes. The candidate keeps the current
personality-aware heuristic as Standard. Easy asks that same heuristic for its
intent, then on eligible decisions substitutes the best strictly lower-scored
target of the **same** settlement/city move kind. The development-tunable
frequency and eligible set are recorded with each candidate below. Trading,
road planning, trade responses, robber targeting, dev-card use, discards,
rolling, ending a turn, and the heuristic's move-category choice are
unchanged. This is meant to model a coherent player making positional
mistakes, not a policy taking random legal actions.

The lapse denominator is the only development parameter. It may be changed
while using the development bank, then is frozen before held-out evaluation.
The 80000-series anchor-calibration seeds are context only and may not tune it.

| Players | VP | Board | Development seeds | Held-out v1 seeds |
| ---: | ---: | --- | --- | --- |
| 3 | 8 | standard | 100000–100011 | 200000–200039 |
| 3 | 8 | randomized | 100012–100023 | 200040–200079 |
| 3 | 10 | standard | 100024–100035 | 200080–200119 |
| 3 | 10 | randomized | 100036–100047 | 200120–200159 |
| 3 | 12 | standard | 100048–100059 | 200160–200199 |
| 3 | 12 | randomized | 100060–100071 | 200200–200239 |
| 4 | 8 | standard | 100072–100083 | 200240–200279 |
| 4 | 8 | randomized | 100084–100095 | 200280–200319 |
| 4 | 10 | standard | 100096–100107 | 200320–200359 |
| 4 | 10 | randomized | 100108–100119 | 200360–200399 |
| 4 | 12 | standard | 100120–100131 | 200400–200439 |
| 4 | 12 | randomized | 100132–100143 | 200440–200479 |

If held-out v1 causes a policy change, that bank is consumed; v2 begins at
201000 with the same offsets. There is no optional stopping or reusing a bank
whose result has been seen.

### Development candidate log

**v1 — rejected.** Commit `71215da`, lapse denominator 2 (half of eligible
spatial choices), Release binary SHA-256
`049863ee63a33664f6ca584701400c51f944a97670849f3ccfbd8a5e2586ca7c`.
The first four development seeds per cell produced 1,008/1,008 decisive games
with a maximum of 1,056 moves. Aggressive knight-use separation was +20.2 to
+35.5 points and Cautious player-trade separation was +17.7 to +35.7 points,
while the cross axes stayed within the predeclared ±15-point band. The
strength screen failed: Standard minus Easy was -8.3 points in both the
three-player randomized 8-point and three-player standard 12-point cells, and
several other cells were indistinguishable at this sample. v1 was therefore
rejected before promotion rather than rationalized from its pooled result.

The 252-shard raw checksum-manifest SHA-256 is
`e8efcfd1e7fce47faec82659162ef7324a4c84959c8adfecf0a0cc66e2ea767b`;
the 48-report checksum-manifest SHA-256 is
`fdd81ba6c237bd224f9f4697dcfc9d528dacf5f8fcf805600bd7735d6b3c0ec3`.
Artifacts remain under `/private/tmp/empires-easy-development-v1-71215da`.

**v2 — rejected.** Commit `0a40756`, lapse denominator 1 over initial
settlements, initial roads, roads, settlements, and cities. Its 336-game
strength screen was fully decisive and removed every reversed cell, but one
four-player standard-board 12-point game took 1,684 moves, violating the
predeclared 1,500-move ceiling. Standard's advantage was also zero in the
four-player randomized 8-point cell and below ten points in three more cells.
Release binary SHA-256
`d08adc7671483dd4f998a0996e354ce67279327c4dcdffe5d27462e8b67a7b2d`;
raw checksum-manifest SHA-256
`1d2726ba9998bf0dd04fefd76a2e13b237a66a23a68f126cdbc98ecc8627e215`;
12-report checksum-manifest SHA-256
`849100e317580065da1eb8f90449b0495f900943353fbe30147fd222e0bbf809`.
Artifacts remain under
`/private/tmp/empires-easy-development-v2-0a40756-screen`.

**v3 — under development.** The denominator remains 1, but road choices are
no longer eligible. Easy takes the strongest strictly inferior initial
settlement, settlement, or city site and retains the heuristic's road plan so
the handicap cannot strand its network. No held-out seed has been consumed.

### Development ladder

1. First two seeds per cell: prove Standard output equals the frozen shipping
   policy, prove Easy output matches across separate processes, and finish a
   mixed-personality Easy game in every cell.
2. First four seeds per cell with full chair rotation: reject immediately for
   an illegal move, timeout, reversed strength direction, or reversed
   personality axis. Confidence intervals are not interpreted at this size.
3. All 12 seeds per cell: require 100% decisive games below 1,500 moves,
   Standard minus Easy at least +10 points, Easy minus Random at least +5
   points, and at least +5 points on the intended Aggressive knight-use and
   Cautious player-trade axes. No cross-axis shift may exceed 15 points.
4. Freeze source and Release-binary hashes. Only then consume held-out v1.

Strength comparisons rotate the evaluated policy through every occupied chair.
Standard faces all-Easy Balanced; its control is all-Easy Balanced. Easy and
Random each face identical Standard Balanced foils, avoiding an all-Random
table that may not finish. Personality arms put one Easy Aggressive or Easy
Cautious seat against all-Easy Balanced and compare it with an all-Easy
Balanced control.

### Held-out promotion gate

Every criterion must pass independently in all 12 cells; a pooled average
cannot rescue one unsupported game configuration:

1. every strength, personality, and mixed-roster game is decisive below 1,500
   moves;
2. the all-Easy rotation control is exactly 33.3% for three seats or 25% for
   four;
3. Standard minus Easy is at least +15 points and its seed-cluster bootstrap
   95% interval is wholly positive;
4. Easy minus Random is at least +10 points with a wholly positive interval,
   while Easy wins at least 15% against Standard foils with three seats and
   10% with four;
5. Easy Aggressive exceeds Easy Balanced knight use when playable by at least
   10 points with a wholly positive interval;
6. Easy Cautious exceeds Easy Balanced player-trade proposal rate by at least
   10 points with a wholly positive interval;
7. Aggressive's proposal-rate interval and Cautious's knight-use interval each
   remain within ±10 points; and
8. each personality rate has at least 250 opportunities per arm and cell, or
   the result is inconclusive rather than silently promoted.

Passing this statistical gate licenses the two labels for product playtesting,
not a claim that either feels fun. Alex still has to play complete games
against both tiers before the selector can be called finished.
