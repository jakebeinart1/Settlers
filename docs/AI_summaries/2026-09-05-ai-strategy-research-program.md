# Empires AI strategy: evidence, architecture, and research program

**Date:** 2026-09-05

**Status:** discovery decision record; no production policy selected

**Scope:** strategic play, trade negotiation, personalities, difficulty, and
character dialogue. Gameplay UI and rules correctness are outside this decision.

## Executive decision

Do **not** choose “heuristics”, “PPO”, “AlphaZero”, “an LLM”, or any other
single algorithm yet. The evidence supports a **measured hybrid research
program**, not a production architecture choice:

1. Keep the current heuristic as the shipping fallback and frozen comparator.
2. Instrument trade and road decisions well enough to diagnose *why* they are
   bad before changing them.
3. Reproduce strong public Catan baselines as external benchmarks, without
   copying incompatible rules or licenses into the app.
4. Establish a structured policy/value baseline on Empires' exact rules,
   masks, player counts, and victory targets.
5. Compare reactive learning, search, and policy-guided search through the
   same evaluation rig; advance only what wins on held-out games and device
   constraints.
6. Keep character language downstream of a typed strategic decision. Begin
   with deterministic, context-rich templates; test an LLM renderer later.

The most plausible eventual shape is a deterministic rules engine plus a
masked strategic policy, optionally strengthened by bounded search, with a
separate opponent model and a separate language renderer. That is a hypothesis
to test, not a conclusion to implement.

## Decision ledger

| ID | Decision for this phase | Status |
| --- | --- | --- |
| AI-1 | Preserve the current heuristic as shipping fallback and frozen comparator. | Decided |
| AI-2 | Select no final strategic algorithm until the ordered gates produce comparable evidence. | Decided |
| AI-3 | Treat strength, style, opponent modelling, negotiation, and voice as independent contracts. | Decided |
| AI-4 | Give every experiment an explicit reveal-all or public-information contract; do not mix their results. | Decided |
| AI-5 | Keep rules and legal-move authority deterministic and outside every learned or language model. | Decided |
| AI-6 | Keep initial character text downstream of typed strategic acts; free-form chat is a later product. | Decided |
| AI-7 | Reproduce promising public agents as external benchmarks before borrowing architecture conclusions. | Decided |
| AI-8 | Profile the complete 4090 pipeline before funding a faster/second simulator. | Decided |
| AI-9 | Profile the current 9,335-action contract before decomposing compound decisions. | Deferred gate |
| AI-10 | Implement R0/R1 observability before tuning trade or road behavior. | Next proposed implementation |

## What Empires has today

### Implemented and usable

- A deterministic rules engine and one game-session loop.
- A replaceable `Policy` seam that receives a `GameObservation` and exact
  legal moves.
- A versioned global action codec and legal-action mask. The current standard
  four-chair head is **9,335** actions; ordered Road Building pairs and discard
  bundles consume about 87% of it.
- A versioned **5,182-feature** state vector and a text rendering for prompt
  experiments. Of those slots, **3,840 (74%)** reserve 256 possible pending
  trade-offer rows; this is a correct fixed contract, but an inefficient dense
  neural input until profiling proves otherwise.
- Two explicit information policies: current perfect information
  (`revealAll`) and shape-compatible public counts (`publicCountsOnly`).
  This switch applies to encodings/exports only; the live `Policy` still
  receives raw `GameState`, so it does not yet enforce no-peeking.
- Versioned deterministic training examples containing provenance, observer,
  player count, victory target, board mode, state/action layout versions,
  sparse legal mask, selected action, and terminal outcome.
- Deterministic headless three- and four-player simulation, configuration
  matrices, chair rotation, frozen anchors, clustered confidence intervals,
  training-data validation, and cross-process fingerprints.
- One shipping hand-scored heuristic policy and a deliberately weaker Greedy
  evaluation anchor.
- Three measured **style** presets—Balanced, Aggressive, and Cautious—and
  stable named opponent profiles.
- Deterministic culture-specific trade phrases selected after the strategic
  action is known.

### Not implemented or not demonstrated

- No learned policy or model is loaded by the iOS app.
- No calibrated Easy/Standard/Hard ladder exists. Personality is not
  difficulty.
- No evidence establishes expert-level play against strong humans or a strong
  external Catan agent.
- No belief model estimates hidden resources, development cards, intent, or
  opponent type.
- No persistent social model tracks reciprocity, trust, grudges, deception,
  or adaptation to an individual player.
- No free-form chat is understood by the policy, and no LLM is used.
- Current trade metrics say what was proposed or accepted, not the component
  values, threshold, alternative, or rejection reason.
- The trade evaluator returns only a Boolean. Affordability is checked outside
  it, so “cannot pay” and “strategically rejects” collapse into the same UI
  result. Balanced and Cautious also hit the same `0.4` base-threshold floor,
  which explains why their measured acceptance rates do not separate.
- A current trade comment overstates `expansionBias`: acceptance sums every
  build-target contribution, so reordering city and settlement targets cannot
  affect that sum. “Immediate build” also means resource-affordable, not that a
  legal build location and piece actually exist.
- Current road metrics count roads, but do not identify a destination,
  blocking objective, connection objective, Longest Road objective, dead end,
  or whether a multi-turn plan was followed.
- Existing style labels are only partially validated: Aggressive knight use
  and Cautious player-trade preference separated on held-out simulations.
  Blind human recognition has not been demonstrated.
- The existing 208 authored trade lines are deterministic but receive no
  resource bundle, ratio, score, threshold, or reason. They provide voice, not
  truthful contextual explanation, and need an editorial/cultural safety pass.

## Evidence already earned in this repository

Negative experiments are constraints, not embarrassments:

- A small short-horizon rollout candidate lost to the existing heuristic
  (**60.0% versus 87.5%** against the same Greedy table; paired difference
  -27.5 points, 95% interval -42.5 to -12.5). This rejects that horizon,
  rollout policy, and evaluator combination—not search as a family.
- A phase-only imitation baseline achieved **31.5%** top-1 versus **14.1%**
  uniform. That proved the dataset plumbing, not policy strength.
- A state-conditioned projected baseline improved imitation to **42.4%** but
  went **0/40** in live games and exhibited pathological trade/build behavior.
  Offline imitation accuracy is therefore not a promotion metric.
- A 3,360-game anchor run showed the shipping heuristic was substantially
  stronger than Greedy in most cells, but the predeclared all-cell margin and
  completion gate failed. Greedy is not an honest product “Easy” tier.
- A 3,024-game personality-preserving Easy prototype was weaker, but failed
  its random floor and long-game completion criteria and was removed.

These results rule out shortcuts: neither a low offline loss, a random-bot win
rate, nor “it looked smarter in a few games” is sufficient.

## The AI is six systems, not one

| Layer | Responsibility | Current state | Rule |
| --- | --- | --- | --- |
| Rules and legality | State transitions, randomness, legal mask | Strong deterministic engine | Never delegate authority to a model |
| Strategic policy | Build, card, robber, trade, and turn choices | Hand-scored heuristic | Every candidate consumes the same typed observation and mask |
| Opponent/belief model | Hidden holdings, goals, tendencies, reciprocity | Absent | Version independently from policy |
| Style/personality | Risk, expansion, hostility, trade posture | Three numeric strategy presets | Must not imply strength |
| Difficulty | Calibrated probability of winning against named populations | Absent | Earn labels through frozen, held-out evaluation |
| Language/character | Express a known offer, reason, reaction, or intent | Deterministic trade templates | Text may explain or decorate; it does not create legal moves |

Free-form chat is a seventh, optional input channel. It requires intent
parsing, abuse/safety handling, latency, cost controls, and a safe mapping into
typed dialogue acts. It should not be bundled into the first language pass.

## Public Catan evidence: useful, but not a settled state of the art

There is no credible public consensus that one algorithm has solved full
three/four-player Catan with standard-length games, realistic hidden hands,
unrestricted player trading, and human-quality negotiation. Most results
remove at least one of those hard parts, use private or weak comparators, or
report only their own rules variant.

Formally, Empires is best treated as a finite-horizon partially observable
stochastic game. A sole-winner reward is n-player constant-sum, but that does
not reduce three/four-player play to ordinary two-player minimax: bilateral
trades, threat response, kingmaking, and policy cycles remain chair-specific.

### Highest-value references

| Work | What is genuinely useful | Transfer boundary | License / reuse |
| --- | --- | --- | --- |
| [Catanatron](https://github.com/bcollazo/catanatron) | Maintained simulator, Gym interface, heuristic/value/search agents, and unusually candid negative learned-model results | Its result log is not an independent modern leaderboard; rules and action representation differ | GPL-3.0: benchmark externally; do not copy/link into a proprietary app without accepting GPL obligations |
| [JSettlers2](https://github.com/jdmonin/JSettlers2) and [STAC](https://homepages.inf.ed.ac.uk/alex/stac.html) | Mature full-game server/bots and the strongest public lineage for Catan trading/dialogue research | Java architecture and research variants differ; STAC corpus/data terms require separate review | GPLv3 for JSettlers2; verify every dataset's terms separately |
| [Gendre & Kaneko 2020](https://arxiv.org/abs/2008.07079) | Shows learned structured representations can beat a JSettlers comparator in its experiment | Actual experiment is two-player and disables player trading; authors list full four-player/trading as future work | Ideas/paper are usable; code/license must be checked independently |
| [Szita, Chaslot & Spronck, MCTS in Catan](https://doi.org/10.1007/978-3-642-12993-3_3) | Establishes that domain-informed MCTS is viable for multiplayer Catan | Older engine/comparators; implementation is not a drop-in Empires policy | Paper evidence, not reusable product code |
| [Strategic Dialogue Management via DRL](https://arxiv.org/abs/1511.08099) | Treats offer/accept/reject/counteroffer as a learnable semantic sub-policy in four-player JSettlers | It learns negotiation decisions, not full-game policy or natural-language generation | Architecture evidence; inspect any code/data license before use |
| [Keizer et al. 2017](https://aclanthology.org/E17-2077/) | Human evaluation found persuasion and learned negotiation strategies improved over prior dialogue baselines | Small research setting; does not establish general strategic strength | Supports human testing and semantic dialogue architecture |
| [Henry Charlesworth's Settlers RL](https://github.com/henrycharlesworth/settlers_of_catan_RL) and [write-up](https://settlers-rl.github.io/) | Full four-player PPO experiment with trading, multiple conditional action heads, recurrent trade composition, historical-policy opponents, a pretrained checkpoint, and root forward search | Author explicitly says it is not superhuman; training took about a month on 32 CPU cores + GTX 3090, and several design choices were not ablated | No license file found in the inspected repository: run/study as a reference, but do not copy code or weights into Empires |
| [Eli6th/catan-rl](https://github.com/Eli6th/catan-rl) | New MIT Rust engine with masked PPO, frozen opponents, an experiment ledger, and policy-prior-guided full rollouts; self-reports 82% versus three heuristics | Headline is first-to-7, perfect information, restricted trades, 192 fixed-seed games, and self-authored opponent/evaluator. Very new and not independently reproduced here | MIT; strongest current reproduction candidate, not evidence to copy its conclusion |
| [nogulong/rust-catan-rl](https://github.com/nogulong/rust-catan-rl) | MIT Rust engine, 3/4-player support, PPO/archive training, separate trade model, visibility modes, ONNX artifacts, JSettlers bridge | Paper is still “in preparation” and no independently interpretable headline benchmark is published | MIT; audit rules, checkpoints, and provenance before reuse |
| [kvombatkere/Catan-AI](https://github.com/kvombatkere/Catan-AI) | MIT multiplayer framework with hierarchical strategy/action design | Older student/research system; no result justifies calling it strongest | MIT; ideas or isolated code only after rule and quality audit |
| [BenjaminL1/catan_rl](https://github.com/BenjaminL1/catan_rl) | Clear modern design reference: graph/tile encoder, six autoregressive heads, heuristic bootstrap, league PPO | 1v1, 15 VP, no player trades; no established independent strength result | No license found in the inspected repository: do not copy code or assets |

The new MIT `Eli6th/catan-rl` result is particularly informative even with its
limits. Its own ledger says a reactive PPO policy plateaued around 65% against
its heuristic, unguided deep rollouts reached 72.5%, and policy-prior-guided
full rollouts reached 82%. Attempts to use its PPO critic as a leaf evaluator
performed much worse. That is a concrete reason to test policy-guided search
and outcome-trained values here. It is **not** proof the same ranking survives
10-point Empires, realistic visibility, our trades, our opponents, or an
iPhone latency budget. The local machine lacked a Rust toolchain, so this
branch inspected source, tests, artifacts, and experiment records but did not
independently execute that result.

## Algorithm-family fit for Empires

| Family | Best use here | Main risk | Discovery verdict |
| --- | --- | --- | --- |
| Hand heuristics / tuned evaluator | Shipping fallback, explanations, style controls, rollout policy, scenario oracle | Brittle interactions and a likely long-horizon ceiling | Keep and instrument; do not mistake more weights for a final answer |
| Flat supervised policy | Validate data/codec and bootstrap a stronger learner | Copies teacher flaws; class imbalance rewards locally common actions | Plumbing baseline only; already shown insufficient |
| Structured behavior cloning | Initialize board-aware policy heads from heuristic/search choices | Still imitates the target quality | Worth a bounded prototype after action/representation audit |
| PPO / masked actor-critic | High-throughput self-play improvement with one network for all seats | Sparse delayed reward, multiplayer nonstationarity, cycles, action imbalance, policy collapse | Plausible, not privileged; require mixed/frozen league evaluation |
| MCTS / stochastic rollouts | Long-horizon tactical lookahead and a teacher independent of heuristic scores | Chance/trade branching and current Swift throughput make full rollouts expensive | Re-test only with a better evaluator, faster simulator, or learned prior |
| ISMCTS / POMCP-style search | Search under hidden hands and sampled beliefs | Requires a credible generative belief/opponent model; huge variance and branching | Later hidden-information track, not the first baseline |
| AlphaZero-like policy/value search | Combine a learned prior, search, and search-improved targets | Ordinary AlphaZero assumptions do not cover 3/4-player general-sum hidden-information negotiation; value quality is hard | Promising empirical hypothesis after throughput and structured baseline gates |
| CFR / NFSP / ReBeL-like methods | Potentially useful for bounded negotiation or simplified information subgames | Most guarantees/results target two-player zero-sum games; full Catan is multiplayer general-sum | Research reference, not first full-game implementation |
| Direct LLM move selection | Low-frequency hypothesis generation or explanations | Cost, latency, nondeterminism, hallucinated state, weak numeric planning, no strong Catan evidence | Do not use as per-action authority |
| Hybrid typed policy + language renderer | Strong/cheap legal play with expressive, replaceable character voice | Requires disciplined boundary and coherent context | Preferred product architecture hypothesis |

Relevant general primary sources include [PPO](https://arxiv.org/abs/1707.06347),
[ISMCTS](https://eprints.whiterose.ac.uk/id/eprint/75048/),
[NFSP](https://arxiv.org/abs/1603.01121),
[ReBeL](https://arxiv.org/abs/2007.13544), and
[Gumbel AlphaZero](https://openreview.net/forum?id=bERaNdoegnO). Their algorithmic
results do not erase Empires' multiplayer, general-sum, stochastic,
partial-information, and negotiation-specific constraints.

## Trade AI: diagnose before tuning

The current accept/reject result is a single thresholded score. To explain
“they reject all my trades” and to support personality or learning, every
evaluated offer should emit a structured decision record with:

- game/build/seed/turn/seat/offer identifiers and information policy;
- exact offered and requested bundles;
- value of each resource before and after the trade;
- closest build objective and cards still missing;
- immediate-build unlocks for each party;
- best bank/port alternative and opportunity cost;
- proposer threat, receiver standing, and repeat-trade adjustment;
- personality/style adjustment;
- raw utility, final threshold, decision, and one stable reason code;
- best acceptable counteroffer, if one exists;
- later outcome labels: accepted, build achieved, points gained, and winner.

The semantic policy should return a typed result such as `accept`, `reject`,
`counter(offer)`, or `propose(offer)`, plus reason codes. A renderer can then
say the same strategic fact in fifty civilization-specific ways without
changing the decision. “Crazy trades” should mean a bounded, recognizable
style—risk appetite, generosity, bluff, urgency, grudge, or kingmaking guard—
not random illegal or obviously losing offers.

The first trade benchmark should be a hand-written scenario corpus: obvious
accepts, obvious rejects, build-unlocking concessions, bad bank alternatives,
leader feeding, reciprocal trades, repeated exploitation, and counteroffers.
Simulation aggregates come second; human judgment comes third.

## Road AI: represent intent, not just an edge score

A good road is usually the first step of a plan. The evaluator therefore needs
to log a plan and alternatives, not merely “edge 17 scored 4.8”:

- target settlement vertex and expected production/diversity gain;
- target port and conversion value;
- path length, remaining resource cost, and probability the target survives;
- connection of fragmented networks;
- block/contest value against each opponent;
- Longest Road claim, defense, or denial value;
- dead-end and self-block penalties;
- whether the chosen edge advances the prior turn's target;
- component score for every legal edge and why the winner beat runner-up;
- realized follow-through: target reached, stolen, abandoned, or made obsolete.

Start with curated board-state tests drawn from the failures Alex saw. A future
learned policy/search can then be compared on the exact same scenarios and
intent outcomes rather than on win rate alone.

## Personality, difficulty, and dialogue contracts

### Personality is a vector of behavior, not a label

An opponent profile may independently specify:

- expansion versus consolidation preference;
- development-card/army appetite;
- blocking and robber hostility;
- trade frequency, concession budget, reciprocity, and exploitation response;
- risk tolerance and willingness to pursue long plans;
- preferred strategic archetype and plan persistence;
- emotional/social state used only for future decisions explicitly designed
  to consume it.

Each axis needs an opportunity-normalized metric and blind recognition test.
If players cannot identify “aggressive” above chance from replays or games,
the label is decoration.

### Difficulty is calibrated strength

Difficulty may vary checkpoint/policy quality, search budget, or bounded
decision noise. It must not silently change a character's identity. A tier is
shippable only when it:

- occupies a declared win-rate band against a frozen opponent population in
  every supported product cell;
- remains ordered on untouched seeds with chair rotation and confidence
  intervals;
- completes games and preserves legality/determinism;
- preserves the profile's declared style within tolerance; and
- feels ordered in human playtests, not only bot-vs-bot statistics.

### Dialogue renders strategy

Use a typed `DialogueAct` containing speaker, target, strategic event, offer,
reason code, relationship state, urgency, and tone. The initial renderer should
choose deterministic, authored variants keyed by opponent voice and context.
This is cheap, offline, testable, and can be much richer than the current one
line per offer outcome.

An optional LLM renderer can later paraphrase that act under a strict schema,
cache, latency deadline, moderation policy, and deterministic fallback. It must
never receive authority to alter an offer, choose a move, reveal hidden state,
or invent a rule. Free-form player chat affecting policy is a separate product
and safety decision.

| Language path | Advantage | Product cost / constraint |
| --- | --- | --- |
| Authored tagged phrases or grammar | Offline, instant, exhaustive factual/editorial control, exact replay | Authoring coverage and repetition management |
| [Apple's on-device Foundation Models](https://developer.apple.com/documentation/FoundationModels/) | Offline generation without bundling a custom model | Only Apple-Intelligence-capable devices; system model changes with OS, so save output and retain authored fallback |
| [Custom Core ML language model](https://developer.apple.com/documentation/coreml/) | Pin exact artifact and run locally | App/download size, conversion, memory, energy, device matrix, model/data license |
| Hosted LLM | Fastest iteration and broadest fluency | Backend/credentials, metered cost, variable latency/output, privacy/retention review, moderation, outage fallback |

No path should be selected from capability alone. Benchmark it against the
authored baseline on blind preference, semantic fidelity, repetition,
p50/p95/p99 latency, cost per median game, offline behavior, and exact replay.

This separation follows the broader negotiation result that strategic acts
and language generation are easier to control when decoupled
([He et al. 2018](https://aclanthology.org/D18-1256/)).

## Evaluation contract

No candidate advances on one metric. Every report must include:

1. **Correctness:** zero illegal moves, invariant failures, crashes, or codec
   mismatches; deterministic reproduction where the policy promises it.
2. **Completion:** decisive rate and move-count distribution for every
   supported player-count × VP-target × board-mode cell.
3. **Strength:** paired common seeds, complete chair rotation, clustered
   intervals, and a frozen *pool* (shipping heuristic, Greedy, random only as
   a floor, prior candidates, and reproduced external agents where possible).
4. **Robustness:** a cross-play matrix, not one Elo number. Multiplayer policy
   cycles and opponent exploitation can hide behind a scalar rating.
5. **Behavior:** opportunity-normalized trade, road, build, card, robber, plan,
   and style metrics.
6. **Human experience:** blind style recognition, perceived fairness,
   frustration, negotiation quality, and fun.
7. **Product cost:** p50/p95/p99 decision latency on target iPhones, model and
   peak-memory size, energy/thermal behavior, offline availability, cloud cost,
   and failure fallback.
8. **Provenance:** source commit, executable/model hashes, layout versions,
   seeds, hyperparameters, information policy, and retained raw reports.

Strength claims use table-size-aware nulls (1/3 or 1/4), never 50%, and do not
pool unlike configurations merely to produce a narrower interval.

## Ordered research program and kill gates

### R0 — freeze the question and benchmark suite

**Build:** an AI evaluation manifest listing exact product configurations,
frozen policies, development seeds, untouched final seeds, scenario fixtures,
latency devices, and promotion metrics.

**Exit:** one command produces a reproducible current-policy report and a
cross-play matrix; trade/road scenario fixtures reproduce Alex's complaints.

### R1 — add decision observability

**Build:** structured trade explanations and road-plan traces described above,
plus analyzers that use opportunity denominators.

**Exit:** every rejection and road choice has a stable reason, runner-up, and
component breakdown; replay can connect choice to later outcome.

**Kill:** do not tune weights if a failure cannot first be expressed as a
fixture or trace.

### R2 — reproduce public reference systems

**Build:** separate, disposable benchmark adapters for the most promising MIT
systems, starting with `Eli6th/catan-rl` and `nogulong/rust-catan-rl`; run their
own checks before cross-engine comparison.

**Exit:** reproduce or falsify headline results, document exact rule deltas,
then play same-policy or matched-scenario comparisons where valid.

**Kill:** do not port a model whose result cannot be reproduced, whose license
is incompatible, or whose rules/observation contract explains the advantage.

### R3 — profile the 4090 path before redesigning the engine

**Measure separately:** Swift environment steps, JSON/data transfer, batch
observation encoding, GPU inference/training, and evaluation. A 4090 speeds
matrix work; it does not accelerate a serial Swift simulator by itself.

**Exit:** measured steps/second and games/hour identify the actual bottleneck,
and a small end-to-end training run reproduces byte/version provenance.

**Decision:** keep Swift plus batched inference, add a narrow FFI simulator, or
build a second fast environment only after the profile. A second engine must
pass cross-engine differential traces before training data is trusted.

### R4 — structured policy/value baseline

**Build:** a board-aware encoder (graph or canonical board blocks), phase-aware
or autoregressive action heads, exact masks, and whole-game train/test splits.
Begin with behavior cloning only to validate optimization and deployment.

**Exit:** beats phase and flat baselines offline, then completes legal live
games without pathological action distributions. It is not promoted on
imitation accuracy alone.

**Decision:** profile the existing 9,335-way masked head before changing it.
If gradients/data are dominated by Road Building pairs and discard bundles,
decompose them into sequential atomic choices under a new action-layout
version. The new MIT Rust reference uses exactly that pattern—one discard card
or road location per decision—and fits its more restricted trade rules into
299 global actions. That is useful design evidence, not proof that 299 is the
right Empires shape. Do not refactor pre-emptively.

### R5 — self-play and opponent-population experiment

**Build:** masked PPO or another reactive learner initialized from R4, trained
against self-play plus frozen/mixed opponents and a checkpoint league.

**Exit:** beats the structured imitation candidate and at least one frozen
competent policy on development seeds; no collapse, illegal moves, completion
regression, or exploitative cycle in the cross-play matrix.

**Kill:** random-bot dominance or training loss improvement alone is failure.

### R6 — policy-guided search experiment

**Build:** compare unguided stochastic rollouts, learned-prior candidate
selection, and outcome-trained value leaves under equal decision budgets.
Label perfect-information runs as diagnostic upper bounds.

**Exit:** paired strength gain over R5 with target-device p95 inside the pacing
budget. The value must be trained/evaluated as a position-outcome estimator,
not assumed useful because a PPO critic has good aggregate explained variance.

### R7 — hidden-information experiment

**Build:** train/evaluate under `publicCountsOnly`; then compare recurrence,
opponent models, belief sampling, and information-set search only if simple
partial-observation learning leaves measurable headroom.

Masking today's private values is necessary but not sufficient. Two positions
with the same public snapshot can imply different holdings because their
public production, spending, stealing, and offer histories differ. The fair
policy contract therefore needs either a versioned public history, recurrent
state, or explicit belief—not just zeroes in opponent hand slots.

**Exit:** no private-information leakage; fair-play strength and behavior are
measured anew. Perfect-information results are not carried over.

### R8 — difficulty calibration and product integration

**Build:** freeze candidates into explicit tiers, convert/export with strict
layout checks, benchmark real devices, and retain the heuristic fallback.

**Exit:** all evaluation-contract dimensions pass and human play supports the
labels. Only then add a difficulty selector.

### R9 — character language, then optional chat

**Build first:** typed dialogue acts plus authored contextual variants for
trades, blocks, robber moves, races, victories, and grudges.

**Experiment later:** LLM paraphrase and, separately, chat intent parsing.

**Exit:** no hidden-state leak, semantic drift, move mutation, unacceptable
latency/cost, or missing offline fallback. Human raters prefer the experience.

## Decisions deliberately deferred

- Final strategic algorithm and model architecture.
- Whether a second high-speed engine is worth its differential-testing cost.
- Reveal-all versus realistic hidden holdings for the shipping bot.
- Exact network topology and whether the global action space is decomposed.
- Difficulty names, number of tiers, and which characters occupy them.
- Whether relationship state ever affects strategy rather than dialogue only.
- Any cloud LLM dependency or free-form chat feature.

## Immediate next deliverable

The next implementation should be **R0 + R1 only**: freeze an evaluation
manifest, add trade-decision explanations, add road-plan/alternative traces,
and encode the observed bad decisions as scenario tests. This is the smallest
work that improves every later path—better heuristics, supervised learning,
RL, search, personality, and dialogue—without selecting an algorithm by taste.

After that evidence exists, R2 and R3 can run in parallel: reproduce public
agents and profile the 4090 pipeline. Their measured results determine whether
the first serious Empires candidate is a structured learned policy, a faster
search hybrid, or both.

## Related Empires evidence

- [`2026-09-05-current-ai-baseline.md`](2026-09-05-current-ai-baseline.md)
- [`2026-09-05-algorithm-options.md`](2026-09-05-algorithm-options.md)
- [`2026-09-05-global-conquest-lessons.md`](2026-09-05-global-conquest-lessons.md)
- [`2026-09-05-personality-trade-dialogue.md`](2026-09-05-personality-trade-dialogue.md)
- [`2026-09-03-ai-approach-evaluation.md`](2026-09-03-ai-approach-evaluation.md)
- [`2026-09-02-ai-baseline-and-personality-audit.md`](2026-09-02-ai-baseline-and-personality-audit.md)
- [`2026-09-02-personality-separation-results.md`](2026-09-02-personality-separation-results.md)
- [`2026-09-02-consolidation-metric-results.md`](2026-09-02-consolidation-metric-results.md)
- [`2026-09-02-opponent-profile-decision-log.md`](2026-09-02-opponent-profile-decision-log.md)
- [`2026-09-03-creative-bot-trade-offers.md`](2026-09-03-creative-bot-trade-offers.md)
