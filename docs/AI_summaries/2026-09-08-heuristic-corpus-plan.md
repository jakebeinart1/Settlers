# Heuristic improvement: representative evidence before tuning

September 8, 2026. **Longer-term protocol; first trade-only trial now run.**
The [closeout handoff](2026-09-09-heuristic-handoff.md) is the current entry point;
the [trial report](2026-09-08-heuristic-corpus-trial.md) separates implemented
parts from proposals below. A simulator-only candidate was subsequently tested;
the app's default was not changed by this trial. Source inspection at planning
time: product `81065c9`; archived diagnostic
source `64ddf534` through the [research restart map](2026-09-08-research-handoff.md).

## Trial-driven revision

Alex authorized trying the method before creating a skill. Start smaller and
deeper: **24 games, trade acceptance only**, at 10 VP, both table sizes and both
boards. Four mixed-roster seed families rotate through every chair (14 games);
ten fresh all-Balanced families supply ten more games. These 14 independent
families are development evidence, not prevalence/strength estimates.

The first implementation captures actual scorer arithmetic, every policy
invocation/return, committed moves and checkpoints. It compares traced and plain
processes and uses the existing bounded watchdog. Twelve family-sampled packets
were reviewed blind, then with the actual choice/score revealed. Nine had only
rejection available; the three optional trades lacked enough spatial/production
evidence for strategic judgment. This is a useful abstention, not a failed move
prediction. Keep representative sampling and separately labelled optional-trade
sampling; do not turn a curated sample into a frequency estimate.

The larger cohorts below remain **conditional proposals**, not queued runs or
prerequisites for closing Alex's bounded Stage 4 iteration.
Before scaling: add native before/after resource and legal-build context,
per-resource scoring inputs and explicit branch reasons; try another small
review and verify that a proposed weakness has a refutable test. Do not create
the reusable skill, tune weights or launch thousands of games merely because
the exporter works.

## Decision and finish line

Put strategic quality before personality. Combine representative self-play,
mechanically faithful decision explanations, falsifiable strategic hypotheses,
and independent full-game evaluation. LLM analysis proposes hypotheses; neither
its confidence nor its preferred move is ground truth. Automated parameter
tuning follows a coherent strategy and a reliable evaluator, not vice versa.

An improvement must address a recurring decision weakness without material
regressions in completion, supported configurations, human-facing behavior or
phone latency. Beating one familiar opponent is insufficient. Personality and
later neural/search work remain separate stages.

## What we have versus what we need

| Component | Inspected evidence | Reuse or gap |
| --- | --- | --- |
| Native bot-vs-bot runner | `Packages/CatanAI/Sources/sim/main.swift` drives `GameSession` | Reuse the real rules/session, not a second game implementation. |
| Behavior summaries | `PolicyBehaviorMetrics.swift`: 27 per-seat counters, including opportunities | Useful denominators, not explanations of why a move was chosen. |
| Learning export | `TrainingExample.swift`: features, legal/chosen indices, final outcome | Not replay-complete. Winner-dependent export is unsuitable as the sole corpus: retain failed/unfinished games too. |
| App game histories | `Settlers/Persistence/GameLogStore.swift`: initial state and committed moves | Replays effects, but not every uncommitted policy consultation or scoring reason. App roster requires a human; don't force simulated tables into that store. |
| Text observations | `StateEncoding.promptDescription` | Reuse terminology; add explicit graph adjacency and readable resource names for spatial reasoning, not thousands of anonymous features. |
| Full research trace | Archived `Sources/sim/DecisionTraceWriter.swift` | Already streams observations, evaluations, commits, final state/RNG with size bounds. Reuse selectively after parity tests; do not merge neural/search dependencies just to get tracing. |
| Selection provenance | Archived `PolicySelection.swift` | Source, fallback and session override exist. Not per-candidate heuristic score explanations. |
| Direct tournaments | Archived `evaluate-bots.py`, `tournament_runner.py`, `tournament_analysis.py`, watchdog | Reuse reviewed scheduling, artifact manifests and board-cluster analysis. Archived capability is not an installed command on product main. |

The missing instrumentation must report the values used by the actual scorer:
candidate generation, skipped branches, features, weights, score contributions,
thresholds, within-category ranking, final category selection and overrides.
Do not reconstruct a plausible explanation afterwards or call the policy again
to obtain it. Tracing enabled/disabled must preserve chosen moves and RNG state
across separate processes, including trade responders and queued decisions.

## Collection: concrete starting size, not a claim of statistical sufficiency

Use ten product rule configurations: three players at 8/10/12 VP and four
players at 8/10 VP, each standard/randomized board. Four-player 12 VP remains
a separately labelled legacy stress case, not mixed into product averages.

Within each configuration use two frozen roster families: all Balanced, and
a mixed table (Balanced/Aggressive/Cautious; second Balanced at four seats).
These are twenty strata. Rotate the mixed roster cyclically through every chair;
this balances seat exposure but is not every possible opponent permutation.
All-Balanced rotations are duplicate games: spend those slots on new seeds.
External bots become a separate comparison cohort only after rules compatibility.

| Cohort | Proposed games | Purpose |
| --- | ---: | --- |
| Instrumentation pilot | 240: 12 per stratum | Check trace fidelity, replay, storage and throughput; not strength. |
| Discovery | 2,400: 120 per stratum | Estimate broad behavior coverage and generate hypotheses. |
| Development validation | 1,200: 60 per stratum | Test changes without reusing discovery positions; repeated use makes this development data. |
| Locked final evaluation | Initially 1,200: 60 per stratum | Reserved seed schedule, generated/evaluated only once a candidate is frozen; expand by declared precision/budget rules if needed. |

Within a mixed stratum, 120 games means 40 fresh seeds x 3 chairs or 30 x 4;
60 means 20 x 3 or 15 x 4. Assign nonoverlapping seed families before collection.
All descendants, rotations, counterfactual forks and derived decision packets
of a seed family stay in one split, across roster/configuration variants. A
different seed on the standard board is new stochastic play, not a new layout.
Record the independent family count alongside game/decision counts.

Do not run all 5,040 games upfront. Pilot first, discovery next; validation and
final cells are matched schedules for each arm, so actual candidate-comparison
cost is larger than this single-roster inventory. Hundreds of thousands of moves
are plausible from historical match lengths, not a measured new corpus size.
Sixty games per cell is coverage, not enough to promise a small improvement.

Proposed pilot limits: 20 minutes wall time, 256 MiB per trace shard, 2 GiB
aggregate. Measure overhead before setting discovery limits. Every later job
needs a declared game count, wall/storage bounds, process-group watchdog,
progress record and terminal receipt. Hitting a limit is an incomplete run,
never success or a reason to quietly discard long games. Keep failed prefixes.

## Machine truth and LLM-readable views

Keep immutable, versioned JSONL per shard plus a manifest: source/configuration/
policy hashes, rules, seed family/split, engine and policy RNG state, session
checkpoint (including queued responses/counters), initial board and final status.
Record all committed actions and all policy consultations, including rejections,
forced end-turns, timeouts and crashes. Chunk/checkpoint so random access does not
require replaying every earlier game. Verify replay hashes before analysis.

LLMs receive small deterministic **decision packets**, generated from that truth:

- Match/decision ID and a retrieval reference; seat, phase, target and standing.
- Resources, production probabilities, piece limits, ports, bank stock and
  relevant opponent threats under the declared information policy.
- Stable vertex/edge/hex IDs with explicit endpoints/adjacency; a reusable board
  graph and local neighborhood plus computed path costs. A screenshot is optional
  for a spatial dispute, never the primary data or a replacement for legality.
- Recent 5–10 relevant events and longer plan history on demand.
- Legal actions, generated candidates, chosen action, strongest alternatives
  per category, score arithmetic and exact exclusion/threshold reasons.
- Which information was unavailable. Full replay state, future RNG/deck order,
  later dice and eventual winner stay outside the initial judgment packet.

The shortlist is a view, not the entire action space: provide counts and retrieval
of all legal/rejected candidates. Explicitly distinguish engine-legal actions,
policy-pruned actions and actions absent from the current engine enumeration.
Do not compare incomparable internal category scores as if they were calibrated
win probabilities. Private opponent hands are shown only if the evaluated policy
was allowed to use them; no accidental hidden-information policy change here.

Aim for 1,000–2,000 tokens per packet; overflow becomes linked detail, never silent
truncation. Review one decision or short sequence at a time, then aggregate issue
records. Do not pour thousands of games into one context window.

## Selection and classification without cherry-picking

Compute opportunity denominators across the full discovery corpus, including
winning seats, losing seats, early/mid/late phases, all configurations and failures.
Keep the representative sample separate from anomaly-enriched samples.

First review 120 packets: 60 stratified random, 40 detector-flagged, 20 matched
unflagged controls. If useful, expand to at most 600 (300/200/100) before another
scope decision. Sample games first then eligible decisions so long trade loops
do not dominate. Preserve inclusion probabilities, sampling seeds and packet IDs.
Matched controls include situations where the superficially odd move is sensible.
Neither flags nor the review mixture estimate population error frequency; use
the weighted probability sample for that, with clustering by seed family.

Initial issue taxonomy (multi-label; unknown is allowed):
1. Rules, legality or implementation defect.
2. Missed/incorrectly pruned candidate action or sequence.
3. Resource/opportunity-cost misvaluation.
4. Incoherent plan, unreachable target or premature plan switching.
5. Opponent threat, trade benefit or endgame timing misjudgment.
6. Defensible decision with unlucky outcome, or reviewer misconception.
7. Inadequate evidence/trace or unresolved strategic trade-off.

Examples of detectors: prolonged spending without reachable expansion, repeated
trade rejection with an available alternative, mutually inconsistent resource
targets, missed immediate wins, stagnation. These flag investigation; a branchy
road, low trade acceptance or a loss is not automatically an error.

A reviewer first judges state/options without seeing the chosen action, final
winner or candidate identity. Then reveal chosen action and scorer evidence.
For proposed high-priority issues a separate critic must defend the original
move, find a counterexample to the proposed rule and check missing context.
Calibrate on clear mechanical errors and valid-but-unusual moves; double-review
20% of the initial random sample. Agreement is reliability evidence, not truth.

Each issue has IDs, eligible opportunities/affected games, suspected causal term
or branch, observed evidence versus interpretation, alternatives, counterexamples,
severity, uncertainty and a falsification test. LLM confidence is not a probability.
Rank recurring mechanisms by prevalence x potential harm, keeping catastrophic
rare defects visible separately. Don't rank by memorable dialogue or screenshots.

## Test a proposed fix before believing it

1. Replay the original position with pinned source/state. Check legality and
   independently recompute decisive arithmetic. A code explanation is not proof
   that the strategic recommendation is good.
2. Form one general hypothesis, not `if this board then choose that edge`.
   Write expected benefits, plausible regressions and rejection criteria first.
3. Local counterfactual screen: proposed first budget is 20 development positions
   from different seed families x 32 stochastic continuations per option. Compare
   original, proposed and a credible third choice when available. Keep downstream
   policies fixed for a forced-action comparison; separately test the full revised
   policy because it may choose differently later. Report interval and ambiguity.
4. Use fresh future chance samples rather than rewarding knowledge of the recorded
   dice. Never reveal future deck/RNG to the decision maker. An equal RNG seed alone
   does not guarantee equal future dice after different actions consume randomness;
   event-aligned chance coupling needs explicit validation. Otherwise report paired
   starting states without claiming identical luck. Future samples must respect
   whatever information was available at the decision.
5. Include neighboring positions with changed resources, threats, blocked routes,
   targets and seats, plus cases where the original action is correct. These are
   development tests, not the locked evaluation set.
6. Only a surviving candidate gets full-game testing against frozen Balanced and
   multiple frozen styles, with direct shared tables, balanced seats, unseen seed
   families and separate results by table/rule cell. Use the archived tournament
   machinery rather than building a new rating system. Policy substitution affects
   others' trade behavior; this is part of full-game evaluation, not an independent
   per-move sample.
7. Report wins, seed-cluster uncertainty, completion/failures, behavior regressions
   and phone latency. A single Elo average cannot erase a rules-cell regression.
   Predeclare a worthwhile gain and precision/maximum-budget stopping rule; no
   repeatedly peeking and stopping at the first favorable 95% interval. A noisy
   result stays inconclusive. Keep incomplete games visible, never manufacture
   wins from final VP or silently omit them from the headline denominator.
8. After locked-test use, that set is spent. A revision needs a new final set.
   Ship only after app/UI and physical latency checks. Human playtesting remains
   necessary: bot-vs-bot data does not establish enjoyable negotiations with people.

## External bots and reusable tuning tools

Two research subagents investigated bots and optimizers independently; the
parent inspected native/archived instrumentation. No external bot was run
against Balanced, and no optimizer was installed. Investigation order is not
a proven strength ranking.

### Catan heuristic candidates

1. **StacSettlers heuristic: first investigation priority.** Guhe and Lascarides
   report 43% wins against three original JSettlers opponents, using simulations
   of 10,000 four-player games. Their work combines behavioral corpus analysis
   with controlled strategic changes. Useful concepts include build-plan ranking
   by estimated acquisition time, diversified opening production and development
   card valuation. This historical benchmark is not against native Balanced,
   today's JSettlers2 or expert humans. [2014 paper](https://homepages.inf.ed.ac.uk/alex/papers/cig2014_gs.pdf).
   The public repo separately contains heuristic, MCTS and learned agents; pin
   the heuristic/configuration, not the repository name as an algorithm.
   [Repository/configuration](https://github.com/sorinMD/StacSettlers).
2. **Catanatron ValueFunctionPlayer: compact comparison and design reference.**
   It scores immediate successor states using handcrafted features: one-step
   lookahead, not RL or full tree search. Its base evaluator notes that it only
   considers one enemy. The player interface exposes full state, and current
   generated turn actions do not originate domestic trade offers even though
   trade-response support exists. Audit these mismatches before comparing or
   adopting it. [Evaluator](https://github.com/bcollazo/catanatron/blob/master/catanatron/catanatron/players/value.py),
   [actions](https://github.com/bcollazo/catanatron/blob/master/catanatron/catanatron/models/actions.py),
   [player interface](https://github.com/bcollazo/catanatron/blob/master/catanatron/catanatron/models/player.py).
3. **JSettlers2 SMART robot: planning reference and comparator.** Its code uses
   building-speed, threats and estimated winning-time considerations. Do not
   confuse it with SmartSettlers, an MCTS system. No common current tournament
   found here establishes it as strongest. [Decision source](https://github.com/jdmonin/JSettlers2/blob/main/src/main/java/soc/robot/SOCRobotDM.java).

All three inspected repository licenses contain GPLv3: [Stac](https://github.com/sorinMD/StacSettlers/blob/master/LICENSE.txt),
[Catanatron](https://github.com/bcollazo/catanatron/blob/master/LICENSE),
[JSettlers2](https://github.com/jdmonin/JSettlers2/blob/main/COPYING-GPLv3.txt).
Do not assume free/noncommercial use permits unrestricted source incorporation.
Source redistribution/porting into the iPhone app requires a separate licensing
assessment. Reading published approaches and benchmarking a separate external
program are different proposals from copying its source; neither is authorized
as implementation by this note. Pin revisions/configs and audit dependencies
before any run. Rules, trading, observability and table size must match or the
comparison must explicitly remain in a separate engine/pool.

### Automated tuning: reuse a tool, not its game-specific assumptions

**First candidate to assess: irace**, if our inventory includes mixed numeric
weights, integer thresholds, switches or conditional settings. It offers those
parameter types and racing to discard weak configurations. A small external
runner can invoke the Swift executable and return a scalar game-outcome cost;
no optimizer belongs in the iPhone binary. It requires R and is GPL-2.0-or-later.
[Official project](https://mlopez-ibanez.github.io/irace/),
[guide](https://mlopez-ibanez.github.io/irace/irace-package.pdf).

If the first experiment varies only a fixed numeric weight vector, assess
**Optuna with CMA-ES** instead; Optuna's TPE is another mixed-space option.
CMA-ES is not the categorical/conditional-space default. Optuna supports an
external ask/tell loop and has an MIT license. [CMA-ES sampler](https://optuna.readthedocs.io/en/stable/reference/samplers/generated/optuna.samplers.CmaEsSampler.html),
[ask/tell](https://optuna.readthedocs.io/en/stable/tutorial/20_recipes/009_ask_and_tell.html),
[license](https://github.com/optuna/optuna/blob/master/LICENSE).

**Stockfish SPSA is a useful numeric-tuning precedent, not our default platform.**
Fishtest's worker execution is tied to Stockfish/fastchess; its chess result
models do not establish multiplayer Catan statistics. Don't rebuild that service
or silently import its license assumptions. [SPSA workflow](https://official-stockfish.github.io/docs/fishtest-wiki/Creating-my-first-test.html#tuning-with-spsa),
[worker architecture](https://github.com/official-stockfish/fishtest/blob/master/docs/6-worker.md).

The tuner gets only development seeds. Optimize whole-game outcomes against a
frozen diverse pool with completion/latency constraints, not our heuristic's own
score, LLM approval, trade frequency or road aesthetics. Reserve final-test
compute first. irace's accumulated runner-time budget is not an independent
wall-clock kill switch; keep the existing process watchdog. Any staged allocation
must compare matching whole-seed blocks before dropping a configuration.
[Budget controls](https://mlopez-ibanez.github.io/irace/reference/irace_cmdline.html).

## Scope of the first implementation, if approved later

Reuse/export the existing replay and diagnostic pieces, add scorer-owned reasons,
verify instrumentation parity, run the bounded pilot and produce its first 120
packets plus a coverage/issue report. That is a concrete stopping point. Do not
start heuristic edits until the data is trustworthy; do not build a dashboard or
a general LLM platform. Reusable CLI stages should collect, validate, summarize,
retrieve a decision and compare candidates; these are desired operations, not
claims that new commands already exist.
