# AI approach evaluation and prototype order

Date: 2026-09-03
Status: short-horizon P1 configuration rejected; P2 is next

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

## Next gate

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

The exporter must fail if a legal or chosen move has no index, and a validator
must reconstruct every sparse mask and verify the chosen action is legal before
training sees a byte.
