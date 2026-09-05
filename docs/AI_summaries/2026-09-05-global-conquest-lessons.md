# Global Conquest lessons for Empires AI research

**Audit date:** 2026-09-05

**Global Conquest snapshot:** `dev @ ab54c2187831`

**Empires snapshot:** `codex/ai-strategy-discovery @ 6ec560df96d0`

## Scope and conclusion

Global Conquest is useful here as a record of how an ambitious game-AI programme can produce convincing but false conclusions when the game contract, training plumbing, evaluation protocol, deployment path, or compute accounting is not yet trustworthy. Its strongest transferable result is a research process: make the game and measurement systems falsifiable before spending heavily or selecting an algorithm.

This document deliberately makes **no recommendation about which algorithm Empires should use**. Global Conquest is Risk-like; Empires is Catan-like. The former can teach us how to investigate the latter, but its winning model, action factorization, value targets, chance treatment, and tactical conclusions are not evidence about the best Catan agent.

**Critical correction:** Global Conquest's current `GAME_DEPTH_DESIGN.md` contains a section titled “The Catan inversion” that asserts hand-tuned evaluation plus search beat RL in Catan and extrapolates from that to richer Risk rules (`GC/docs/AI_summaries/GAME_DEPTH_DESIGN.md:258-302`). This is not a measured Empires result and is not accepted as evidence here. The same section immediately acknowledges that the repository has no AI-versus-human data even for its own game (`GC/docs/AI_summaries/GAME_DEPTH_DESIGN.md:304-309`). It is a useful example of the exact cross-game overreach this audit must prevent.

Path notation below:

- `GC/…` means `/Users/alex/Documents/Personal Projects/GlobalConquest/…`.
- `EMP/…` means `/Users/alex/Documents/Personal Projects/Settlers/…`.

## Evidence policy used for this audit

1. Current code and current canonical summaries outrank old prose. Global Conquest itself defines the authority map in `GC/CLAUDE.md:6-18` and `GC/docs/AI_summaries/OPERATING_DOCTRINE.md:7-24,189-207`.
2. The four recovered architecture documents are treated as historical hypotheses, not current conclusions. Every one begins with an explicit warning that it predates later experiments and must not be used for planning without reconciliation against the ledger (`GC/docs/AI_summaries/archive/architecture-mandate/ALGORITHM_STRATEGY.md:1-12`; `GC/docs/AI_summaries/archive/architecture-mandate/ACTION_SPACE_DESIGN.md:1-12`; `GC/docs/AI_summaries/archive/architecture-mandate/VALUE_TARGET_DESIGN.md:1-12`; `GC/docs/AI_summaries/archive/architecture-mandate/REPLICATION_NOTES.md:1-12`).
3. The Global Conquest memory index and the relevant notes (`ai-architecture-mandate`, `ai-research-rigor`, `ai-action-space-design`, `ai-value-target-design`, `rigor-harness`, `ai-recommended-direction`, `repo-two-halves`, and `gc-parallel-agent-operations`) were read as historical routing context. No conclusion below rests on memory alone; each is checked against current code, a canonical file, a commit, or a measured ledger row.
4. A ledger citation names both its physical line and row id. The ledger is append-only by policy (`GC/docs/AI_summaries/OPERATING_DOCTRINE.md:129-145,199-200`), so later corrections remain visible rather than rewriting the original belief.

## Transferable process and research-method lessons

### 1. Freeze the actual game contract before comparing algorithm families

The archived strategy formalized a particular Risk target—perfect information, stochastic combat, long within-turn sequences, and a multiplayer ambition (`GC/docs/AI_summaries/archive/architecture-mandate/ALGORITHM_STRATEGY.md:39-53`). The live trainer, however, still separates six-seat **capacity** from a two-seat **runtime arity** (`GC/training/risk_jax/risk/constants.py:43-62`). Conclusions obtained in the latter setting cannot silently answer the former.

**Transfer to Empires:** write down the exact product being optimized before model selection: supported seat counts, which information an agent receives, all decision phases, trade semantics, terminal rules, timeout handling, and the shipped latency budget. A change to one of those is a new experimental condition, not a harmless configuration toggle.

### 2. Treat every algorithm or architecture choice as a hypothesis, not a commitment

The recovered mandate confidently recommended a Gumbel-AlphaZero/chance-node/GNN direction, but its own archive banner now records that later experiments closed or weakened parts of that direction (`GC/docs/AI_summaries/archive/architecture-mandate/ALGORITHM_STRATEGY.md:1-12`). Conversely, the early conclusion that more PPO training was spent was later overturned after correcting the training signal: the same recipe/architecture/observation family improved by roughly 95–150 Elo (`GC/docs/AI_summaries/EXPERIMENT_LEDGER.jsonl:23`, row `exp-014-FINAL`; commit `23a1fda`). Global Conquest later graded its original confidence ledger and found that its diagnostic claims largely held while its prescriptive bets mostly did not (`GC/docs/AI_summaries/RESEARCH_NOTES.md:243-262`).

**Transfer to Empires:** compare candidate approaches only after defining falsifiers, costs, and evaluation bars. Preserve “unknown” as a valid outcome; do not turn an attractive theoretical fit or another game's result into the default plan.

### 3. Audit signal correctness before attributing a ceiling to model capability

Global Conquest paid for three distinct examples:

- Legacy search previewed the real dice outcome and therefore measured clairvoyance, not deployable search strength. Honest 32-simulation search then scored below greedy play (`GC/docs/AI_summaries/EXPERIMENT_LEDGER.jsonl:13,19`, rows `exp-012-T1` and `E1-honest-rebaseline`; `GC/docs/AI_summaries/MODEL_REGISTRY.md:12-19`).
- Correcting the training signal produced the new champion under the same recipe/architecture/observation family (`GC/docs/AI_summaries/EXPERIMENT_LEDGER.jsonl:23`, row `exp-014-FINAL`; commits `41415f3`, `23a1fda`).
- The CLI printed a seed that did not reach network initialization, while Python's opponent schedule used system entropy. The historical record was therefore one initial weight draw, despite appearing seeded (`GC/docs/AI_summaries/EXPERIMENT_LEDGER.jsonl:59`, row `fix-training-honesty-2026-07-27`; current fixes at `GC/training/risk_jax/scripts/train.py:403-411,538-543` and `GC/training/risk_jax/training/ppo.py:385-405,427-432`).

**Transfer to Empires:** validate rule fidelity, legal-action masks, terminal rewards, perspective/sign conventions, randomness plumbing, save/replay determinism, and deployed observation parity before interpreting a plateau as an algorithm limitation.

### 4. Build known-answer diagnostics and prove that they fail under injected defects

Global Conquest's Tic-Tac-Toe verifier checks 16,167 state/action pairs with zero errors; re-injecting the old negamax sign bug corrupts more than 10% of Q-values (`GC/docs/AI_summaries/RIGOR_HARNESS.md:38-55`; bug-fix commit `c6bc410`). Its full-loop test also separates policy-target corruption from value-target corruption: the latter remains invisible to shallow gameplay metrics and is exposed only by the direct value probe (`GC/docs/AI_summaries/RIGOR_HARNESS.md:57-86`). The same document explicitly records that this ladder still does not ground-truth chance nodes or deep value use (`GC/docs/AI_summaries/RIGOR_HARNESS.md:21-36`).

**Transfer to Empires:** establish small solved scenarios, rule invariants, deterministic replays, and negative controls for each subsystem. A test suite has evidentiary value only when a deliberately reintroduced defect is seen to make it fail.

### 5. Design the evaluation protocol before running the experiment

Old Global Conquest comparisons used 64 games on different seeds, with observed run-to-run noise around 0.06. The replacement evaluates both agents on shared board seeds, rotates seats, uses deterministic inference for the comparison, bootstraps by board, and separates statistical significance from minimum practical effect (`GC/docs/AI_summaries/RIGOR_HARNESS.md:88-110`; current implementation rationale at `GC/training/risk_jax/training/paired_eval.py:1-29`).

**Transfer to Empires:** predefine the scenario/randomness pairing, seat rotation, outcome convention, resampling unit, effect size, and promotion rule. The exact design must be derived for Empires; the transferable lesson is that it exists before results are visible.

### 6. Never use one easy opponent as the definition of strength

Global Conquest's win rate against its heuristic rose from 0.83 to 0.95 while true head-to-head Elo stayed flat (`GC/docs/AI_summaries/OPERATING_DOCTRINE.md:77-85`). The 555-wide run repeated the mirage: performance versus the heuristic improved monotonically, yet the 343M checkpoint beat the final 687M checkpoint 0.546 with a 95% CI of `[0.523, 0.569]` (`GC/docs/AI_summaries/EXPERIMENT_LEDGER.jsonl:84`, row `p3v3-555-REFERENCE-EVAL`). Relative-generation gates also chained downhill until an absolute champion anchor caught the regression (`GC/docs/AI_summaries/EXPERIMENT_LEDGER.jsonl:9-10`, rows `exp-009` and `exp-010`).

**Transfer to Empires:** retain multiple frozen baselines and an absolute anchor. Report matchup matrices and behavioral diagnostics separately from an aggregate strength number.

### 7. Size evaluations for the effect being claimed

Global Conquest's doctrine states that 16 boards yield roughly ±70 Elo resolution, which cannot answer a 30-Elo question (`GC/docs/AI_summaries/OPERATING_DOCTRINE.md:86-91`). A published 48-board champion estimate moved from 1552 with a 93-Elo half-width to 1584 with a 42-Elo half-width at 196 boards, without changing the model, pool, seed, or scoring convention (`GC/docs/AI_summaries/MODEL_REGISTRY.md:53-108`). Current guards fail loudly when a run cannot resolve its stated effect and record a distinct underpowered exit (`GC/training/risk_jax/training/eval_guards.py:1-50,126-142,358-432`). Halving an interval requires approximately four times as many boards (`GC/training/risk_jax/training/eval_guards.py:323-355`).

**Transfer to Empires:** choose the minimum meaningful improvement first, perform power analysis second, and label “could not resolve” separately from “no effect.”

### 8. Separate every source of randomness in both controls and provenance

Global Conquest now distinguishes training seed, board seed, seat assignment, rollout/action randomness, opponent sampling, and bootstrap randomness. Its result schema requires both training and board seed fields—even when the correct value is explicitly `None`—because omitting them made non-comparable results look comparable (`GC/training/risk_jax/training/results_store.py:99-155,240-272`). The current status still warns that the champion and historical Elo record are `n=1` in training seed (`GC/docs/AI_summaries/STATUS.md:9-25`).

**Transfer to Empires:** define and log each randomness layer separately. Repeating many games from one trained artifact does not measure sensitivity to initialization or training order.

### 9. Multiplayer evaluation is not a two-player metric with more seats

Global Conquest had to replace the two-player null of 0.5 with the first-place null `1/N`; at four seats, 0.25 is parity, not failure (`GC/training/risk_jax/training/eval_guards.py:52-67,91-124`). Its common-random-number layout uses cyclic seat rotations rather than all `N!` permutations and documents the residual adjacency bias (`GC/training/risk_jax/training/crn.py:9-51`). The fixed gauntlet also checks non-transitive cycles because a scalar Elo can hide `A > B > C > A` (`GC/docs/AI_summaries/RIGOR_HARNESS.md:112-130`). The current Track C design makes evaluation infrastructure a prerequisite to the first multiplayer training run, not a cleanup step after it (`GC/docs/AI_summaries/TRACK_C_EVAL_TRAINING_PLAN.md:115-229`; `GC/docs/AI_summaries/TRACK_A_CLASSIC_RL_PLAN.md:219-229`).

**Transfer to Empires:** derive fairness, null performance, seat balancing, ranking, and uncertainty for each supported player count. Do not reuse a two-player win-rate interpretation for a multiplayer table.

### 10. State and action encodings are versioned model APIs

The old Risk encoder silently made a third player's territory bit-identical to unowned land, dropped an out-of-range continent update, and wrapped an opponent-card lookup to the last seat (`GC/training/risk_jax/risk/observation.py:21-53`). Correcting this widened the observation from 323 to 555 and invalidated warm-start compatibility with every 323-wide checkpoint; the layout was pre-registered before implementation (`GC/docs/AI_summaries/EXPERIMENT_LEDGER.jsonl:80`, row `p2-v3-obs-PREREG`; commits `a503eb5`, `d92c159`). The Risk action space also replaced 200 discrete conquest counts after measuring a 34% structural bias toward “move one” (`GC/training/risk_jax/risk/constants.py:94-129`).

Empires already has the right seam: an invertible, masked, versioned action numbering (`EMP/Packages/CatanEngine/Sources/CatanEngine/ActionSpace.swift:1-28,61-103`) and a versioned shared numeric/text state encoding (`EMP/Packages/CatanEngine/Sources/CatanEngine/StateEncoding.swift:3-15,51-75`).

**Transfer to Empires:** keep schema meaning, ordering, legality, hidden-information policy, and artifact compatibility explicit and tested. Changing slot meaning is a new lineage, even when the app still compiles.

### 11. Monitoring instruments can lie; reconcile them against physical work

On WSL2, `nvidia-smi` reported 3–4% utilization while the trainer sustained about 189k steps/s; a utilization gate would have killed a healthy run four times (`GC/docs/AI_summaries/OPERATING_DOCTRINE.md:41-64`). Another experiment's logged throughput could not be reconciled with timestamps and step counts; recomputation showed 173,743 versus 92,077/92,453 steps/s and exposed both a 1.88× data confound and 6.05× parameter confound (`GC/docs/AI_summaries/EXPERIMENT_LEDGER.jsonl:75`, row `exp-024-ATT-SPS-CORRECTION`). A single-sample entropy kill gate also fired on ordinary ±0.4 oscillation and had to be amended to a windowed trend before the outcome was visible (`GC/docs/AI_summaries/EXPERIMENT_LEDGER.jsonl:82`, row `p3-v3-classic-2p-GATE-AMENDMENT`).

**Transfer to Empires:** prefer completed work deltas and end-to-end throughput over proxy utilization; reconcile counters arithmetically; define noisy health gates over windows and trends.

### 12. “It trains” is not “it is strong,” and “final” is not “best”

The 555-wide run completed 687M steps in eight hours and passed its structural trainability bar, but its ledger row explicitly made no strength claim (`GC/docs/AI_summaries/EXPERIMENT_LEDGER.jsonl:83`, row `p3-v3-classic-2p-RESULT`). Powered evaluation then found that the 343M checkpoint beat the 687M final checkpoint, and the absence of an independent 555-wide anchor made a reference rating impossible (`GC/docs/AI_summaries/EXPERIMENT_LEDGER.jsonl:84`, row `p3v3-555-REFERENCE-EVAL`; `GC/docs/AI_summaries/STATUS.md:23-28`).

**Transfer to Empires:** separately label technical trainability, policy improvement, calibrated strength, gameplay quality, latency viability, and release readiness. Evaluate periodic checkpoints instead of assuming the last checkpoint is the best one.

### 13. Evaluate the exact agent that ships

Global Conquest's browser and iOS product use greedy inference, not MCTS, so only greedy Elo describes deployed strength (`GC/docs/AI_summaries/MODEL_REGISTRY.md:12-19`; `GC/docs/AI_summaries/OPERATING_DOCTRINE.md:99-111`). Commit `23a1fda` did not stop at a promotion number: it verified hashes, export tensors, browser loading, a complete decision, and the default difficulty.

**Transfer to Empires:** measure the same observation policy, action decoder, inference mode, resource limits, and fallback behavior used on-device. A stronger offline-only configuration is a research artifact until the shipped path is proven equivalent.

### 14. Change one lever, pre-register the bar, and preserve failed branches as evidence

Global Conquest's operating doctrine requires one lever per experiment, a named revert, pre-registration, staged T0→T3 spend, an isolated worktree, and merging only after the relevant measured bar passes (`GC/docs/AI_summaries/OPERATING_DOCTRINE.md:122-127,151-187`). This prevents an architecture change, data increase, seed change, and evaluator change from collapsing into one uninterpretable result.

**Transfer to Empires:** make each AI change answer one named question. Keep failed experiments in an append-only decision record so later work does not repeat them or misremember their scope.

### 15. A strength number needs a complete comparability key

Global Conquest's result store now keys strength by game mode, player count, map or map pool, engine, rating system, comparator pool, training seed, and board seed; malformed or incomplete rows fail before GPU time is spent (`GC/training/risk_jax/training/results_store.py:26-73,99-155,240-272`). Its Track C design states the same comparability doctrine before defining a rating (`GC/docs/AI_summaries/TRACK_C_EVAL_TRAINING_PLAN.md:40-114`). Its model registry keeps immutable model identities and hashes and warns that an Elo without a named pool is not a fact (`GC/docs/AI_summaries/MODEL_REGISTRY.md:1-19`). Commit `71a9931` added the append-only result store after results had been stranded in console logs, chat, and gitignored files.

**Transfer to Empires:** every reported result should identify the ruleset, player count, policy ids, state/action layout versions, hidden-information mode, seed families, evaluator version, source commit, artifact hash, inference mode, and timeout convention.

### 16. Plan compute from measured end-to-end throughput, not GPU ownership

The same 4090 produced very different regimes: the corrected-signal champion used 5.25B steps in about 7.5 hours at roughly 229k steps/s (`GC/docs/AI_summaries/MODEL_REGISTRY.md:42-50`), while the 555-wide run managed 687M steps in eight hours at about 29.2k steps/s (`GC/docs/AI_summaries/EXPERIMENT_LEDGER.jsonl:83`, row `p3-v3-classic-2p-RESULT`). Host sleep corrupted one 24-hour measurement, and an undetached SSH run died at 74% (`GC/docs/AI_summaries/TWO_MACHINE_SETUP.md:47-57,151-161`). The live budget module exists because an earlier generation ran silently for about 8,000 seconds; it supplies hard caps, progress, slowdown detection, and append-only timing records (`GC/training/risk_jax/training/budget.py:1-38,81-157,340-470`).

**Transfer to Empires:** benchmark the complete simulator→policy→training/evaluation loop, then budget staged probes, replications, checkpoints, storage, monitoring, and failure recovery. Available compute cannot rescue a confounded or underpowered experiment.

### 17. Adversarially review the evaluator, not only the policy

One focused Global Conquest review found 15 verified bugs, three capable of poisoning a five-hour run (`GC/docs/AI_summaries/OPERATING_DOCTRINE.md:113-127`). A later statistics review found five more edge-case defects—including a one-board divide-by-zero/unanimous-sweep collapse, 37% Elo compression, and phantom non-transitive cycles—despite happy-path tests passing (`GC/docs/AI_summaries/RIGOR_HARNESS.md:132-155`).

**Transfer to Empires:** independently review small-sample, unanimous, tie, timeout, low-decisiveness, missing-data, and incompatible-artifact paths before trusting a long run or a promotion result.

## Global Conquest conclusions that do **not** transfer to Empires

The following are explicitly out of scope as evidence for a Catan-like agent. Each may become an Empires hypothesis later, but none is inherited as a conclusion.

| Global Conquest conclusion or fact | Why it does not transfer |
|---|---|
| **“The Catan inversion”: RL allegedly failed in Catan while hand-tuned value plus search won.** (`GC/docs/AI_summaries/GAME_DEPTH_DESIGN.md:258-302`) | This is an uncited cross-game assertion inside a Risk design document, not an Empires experiment or a reconciled Catan literature result. It must not bias the Empires algorithm comparison. The document itself concedes that even its Risk evidence is AI-vs-AI only and says nothing about difficulty for humans (`GC/docs/AI_summaries/GAME_DEPTH_DESIGN.md:304-309`). |
| **The historical target was perfect-information Risk.** (`GC/docs/AI_summaries/archive/architecture-mandate/ALGORITHM_STRATEGY.md:39-53`) | Empires has private resource and development-card information. Its current encoder deliberately supports both reveal-all and public-count-only policies (`EMP/Packages/CatanEngine/Sources/CatanEngine/StateEncoding.swift:219-290`). The information model must be decided and evaluated for Empires itself. |
| **The current learned lineage is a two-player runtime padded for six seats.** (`GC/training/risk_jax/risk/constants.py:43-62`) | Empires' supported player counts, coalition incentives, seat effects, and evaluation nulls are separate facts. Risk's measured two-player or planned six-player behavior says nothing quantitative about three- or four-seat Catan. |
| **Risk's action decomposition is deploy → attack → conquest → fortify → cash-in, with map-derived territory-pair actions and ten conquest bins.** (`GC/training/risk_jax/risk/constants.py:94-129`) | Empires' decisions include roads, settlements, cities, robber movement, discards, bank trades, player offers, trade responses, and development cards. Its current action schema is independently defined and versioned (`EMP/Packages/CatanEngine/Sources/CatanEngine/ActionSpace.swift:94-125`). Risk's 397-era or map-derived dimensions are not Catan dimensions. |
| **Territory/continent graph features and per-node/per-edge heads fit Risk's board.** (`GC/docs/AI_summaries/archive/architecture-mandate/ACTION_SPACE_DESIGN.md:33-71`) | Empires has hex tiles, vertices, edges, ports, production numbers, resources, hands, offers, and phase-specific choices. A graph-shaped Risk board does not establish the right Catan representation or head factorization. |
| **Exact battle distributions, dice-clairvoyance, and Carr-style re-synchronization dominated Risk chance handling.** (`GC/docs/AI_summaries/archive/architecture-mandate/REPLICATION_NOTES.md:20-31,35-52`; ledger rows `exp-012-T1` and `E1-honest-rebaseline` at `GC/docs/AI_summaries/EXPERIMENT_LEDGER.jsonl:13,19`) | Catan's dice production, card draws, robber/discard sequence, trades, and hidden holdings create different chance and information boundaries. The Risk combat result does not choose an Empires chance treatment. |
| **Honest search was weaker than greedy for the shipped Risk checkpoint.** (`GC/docs/AI_summaries/EXPERIMENT_LEDGER.jsonl:19`, row `E1-honest-rebaseline`) | This is a result about one Risk model, one search implementation, one budget, one observation lineage, and one comparator pool. It is neither evidence for nor against search in Empires. |
| **Corrected-signal PPO produced Global Conquest's champion.** (`GC/docs/AI_summaries/MODEL_REGISTRY.md:25-54`; commit `23a1fda`) | Success of one optimizer/recipe on Risk does not recommend PPO—or rule it out—for a trading, hidden-information, Catan-like game. Even the Global Conquest champion remains an `n=1` training-seed result (`GC/docs/AI_summaries/STATUS.md:9-25`). |
| **Risk-specific value proposals used troop/territory margin, continent control, placement share, turn-boundary targets, and particular discount/auxiliary choices.** (`GC/docs/AI_summaries/archive/architecture-mandate/VALUE_TARGET_DESIGN.md:20-121`) | Empires has a different scoring system, victory-point visibility, resource economy, longest-road/largest-army incentives, trade effects, and horizon. The archived file also states that its Risk ablations were not performed (`GC/docs/AI_summaries/archive/architecture-mandate/VALUE_TARGET_DESIGN.md:120-121`). |
| **Published Risk agents favored particular GNNs, TD(λ), BFS, determinization, or action pruning.** (`GC/docs/AI_summaries/archive/architecture-mandate/REPLICATION_NOTES.md:35-105`) | Those results were obtained on Risk variants, including a tiny six-country map and heavily simplified actions; the same notes record important evaluation and implementation caveats (`GC/docs/AI_summaries/archive/architecture-mandate/REPLICATION_NOTES.md:56-72`). They are literature leads, not Catan evidence. |
| **Risk has measured first-mover, continent, choke-point, turtling, alliance, and kingmaking concerns.** (`GC/training/risk_jax/risk/constants.py:190-218`; `GC/docs/AI_summaries/RIGOR_HARNESS.md:117-130`) | Empires may have its own seat and interaction effects, but their direction and magnitude must be measured from Empires games. Risk-specific tactical features and failure modes should not be copied into Catan rewards. |
| **The 4090 delivered 29k–229k Risk steps/s and billions of steps per run.** (`GC/docs/AI_summaries/MODEL_REGISTRY.md:42-50`; `GC/docs/AI_summaries/EXPERIMENT_LEDGER.jsonl:83`) | Empires' simulator cost, action branching, observation width, batching efficiency, model size, and evaluation duration are different. Those numbers justify benchmarking; they do not estimate Empires training time. |
| **Greedy inference is the deployable product mode.** (`GC/docs/AI_summaries/MODEL_REGISTRY.md:12-19`) | That is a Global Conquest browser/iOS constraint and result. Empires must establish its own on-device latency, memory, determinism, and quality envelope before defining its deployable mode. |
| **Global Conquest says nothing empirical about trade acceptance, negotiation language, character personality, or chat behavior.** Its action layout contains no player-to-player trading (`GC/training/risk_jax/risk/constants.py:94-112`). | These are central Empires product questions. No Global Conquest result supports using an LLM, canned phrases, heuristic personality modifiers, learned negotiation, or any particular combination. They require separate product and evaluation definitions. |
| **Global Conquest's current champion, Elo 1617, and pool ordering are reusable benchmarks.** (`GC/docs/AI_summaries/MODEL_REGISTRY.md:25-108`) | Elo is pool-relative even within Global Conquest; the same net reads differently under other board seeds and conventions. A cross-game Elo comparison has no meaning. |

## Research gates Empires should establish before selecting an algorithm

These are process deliverables, not an algorithm recommendation:

1. **Game contract:** one canonical specification of supported rules, player counts, hidden information, terminal conditions, timeouts, and trade semantics.
2. **Decision contract:** a phase-by-phase inventory proving that every legal move is representable, every encoded move round-trips, and masks match the rules engine.
3. **Observation contract:** versioned numeric and text encodings, explicit private/public fields, perspective invariants, and artifact-load refusal on incompatible versions.
4. **Deterministic simulation contract:** reproducible replay across separate processes, with each source of randomness named and independently seeded.
5. **Baseline suite:** frozen random and heuristic policies plus scenario-specific behavioral anchors; no single opponent becomes the definition of strength.
6. **Evaluation protocol:** player-count-specific nulls, seat balancing, shared scenario/chance controls where valid, timeout convention, effect size, power, confidence intervals, and non-transitivity reporting.
7. **Diagnostic ladder:** solved micro-scenarios and negative controls for rules, perspective, value/score semantics, legal masks, chance, long-horizon behavior, and multiplayer accounting.
8. **Experiment ledger and registry:** pre-registered hypothesis/bar/kill rule, immutable artifacts and hashes, full comparability key, periodic checkpoints, and append-only corrections.
9. **Deployment-parity gate:** the exact on-device observation, policy, decoder, latency, and fallback path is the one evaluated.
10. **Compute plan:** measured end-to-end throughput on the actual Empires workload, then staged T0/T1 probes before multi-hour or multi-day 4090 runs.

Only after these gates exist can an algorithm comparison produce evidence rather than another evaluation mirage.

## Audit trail

### Current Global Conquest authorities read

- `GC/CLAUDE.md`
- `GC/docs/AI_summaries/STATUS.md`
- `GC/docs/AI_summaries/OPERATING_DOCTRINE.md`
- `GC/docs/AI_summaries/RIGOR_HARNESS.md`
- `GC/docs/AI_summaries/MODEL_REGISTRY.md`
- `GC/docs/AI_summaries/RESEARCH_NOTES.md`
- `GC/docs/AI_summaries/TRACK_A_CLASSIC_RL_PLAN.md`
- `GC/docs/AI_summaries/TRACK_C_EVAL_TRAINING_PLAN.md`
- `GC/docs/AI_summaries/MULTIPLAYER.md`
- `GC/docs/AI_summaries/GAME_DEPTH_DESIGN.md`
- `GC/docs/AI_summaries/LINEAGE.md`
- `GC/docs/AI_summaries/TWO_MACHINE_SETUP.md`
- `GC/docs/AI_summaries/EXPERIMENT_LEDGER.jsonl`
- `GC/training/risk_jax/risk/constants.py`
- `GC/training/risk_jax/risk/observation.py`
- `GC/training/risk_jax/training/crn.py`
- `GC/training/risk_jax/training/paired_eval.py`
- `GC/training/risk_jax/training/eval_guards.py`
- `GC/training/risk_jax/training/results_store.py`
- `GC/training/risk_jax/training/budget.py`
- `GC/training/risk_jax/scripts/train.py`
- `GC/training/risk_jax/training/ppo.py`

### Historical Global Conquest design documents read and reconciled

- `GC/docs/AI_summaries/archive/architecture-mandate/ALGORITHM_STRATEGY.md`
- `GC/docs/AI_summaries/archive/architecture-mandate/ACTION_SPACE_DESIGN.md`
- `GC/docs/AI_summaries/archive/architecture-mandate/VALUE_TARGET_DESIGN.md`
- `GC/docs/AI_summaries/archive/architecture-mandate/REPLICATION_NOTES.md`

### Empires contracts inspected for contrast

- `EMP/CLAUDE.md`
- `EMP/Packages/CatanEngine/Sources/CatanEngine/GameSession.swift`
- `EMP/Packages/CatanEngine/Sources/CatanEngine/ActionSpace.swift`
- `EMP/Packages/CatanEngine/Sources/CatanEngine/StateEncoding.swift`
