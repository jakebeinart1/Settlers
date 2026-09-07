# Empires AI — current work and next decisions

**Updated:** 2026-09-07. This is the live tracker, not a claim that later stages
are complete. Read it before planning AI work, running experiments, or reporting
progress. Detailed evidence and operational recipes stay behind the links below.

## Where we stand

- **Best tested native baseline: Balanced (rule-based).** On the fixed
  [comparison](2026-09-06-balanced-original-decision.md#result), it beat the
  original checkpoint against both opponent groups: **83.6% vs 57.8%** against
  Greedy, **25.0% vs 9.8%** against Balanced. Same 64 held-out boards/all chairs,
  four players/ten points; 1,024 scheduled records completed. Both differences
  cleared the predeclared useful-gain/uncertainty checks. Not human/expert play
  or the upstream search bot. r2 remains a frozen reproduction artifact, not
  the next model to improve by default.
- **Integration:** offline neural/hybrid play is implemented and independently
  reviewed. Full gate, native UI journeys, parity checks, and full games passed.
  [draft PR #40](https://github.com/jakebeinart1/Settlers/pull/40) is stacked on
  [research PR #37](https://github.com/jakebeinart1/Settlers/pull/37); neither is merged.
- **Delivery remains open:** Build 5 is on the manual simulator, not TestFlight
  or the phone. The final archive timed out at its signing-key prompt; the phone
  is unavailable to Xcode. Resume delivery when those external blocks clear.
- **Evaluation works:** one command freezes named policies or two hash-pinned
  compatible checkpoints, rotates chairs and retains audited results. Identical
  weights reproduce through both loading paths; distinct weights change play.
  [PR #42](https://github.com/jakebeinart1/Settlers/pull/42) now includes superseded #41;
  published at `dacef369` with Linux CI green (run `34053389032`) after a full
  local gate, including 310 app/UI tests. Its CI watcher is now paused.
- **Experiment disposition:** optimization and target adaptation were **not
  adopted**. Their safeguards/results and cap diagnosis are consolidated in
  [PR #45](https://github.com/jakebeinart1/Settlers/pull/45); #43/#44 are closed,
  their branches/evidence retained. Open PRs reduced **seven to four**:
  #37 research → #40 integration (draft) → #42 evaluator → #45 experiments.
  No PR has reviewer approval yet; none was self-approved or merged.
- **Neural decision:** original beat r2 in the earlier matched comparison,
  **74/128 vs 46/128** against Greedy. Combined with the new Balanced comparison,
  this ends r2 continuation/target adaptation as the next improvement path.
  Retain current rule-based product behavior; #40's proposed automatic r2
  selection must be removed or made explicit before it can ship. Keep the
  integration seam and frozen models for controlled research.
- **Limit:** trading remains heuristic; native rules differ from training.
  Compatibility and a legal complete game are not strength measurements.

## Execution order and finish lines

| Stage | Status / next action | Done when |
| --- | --- | --- |
| **1. Deliver and retain regressions** | Simulator verified; phone/signing blocked. Keep the rule-based default; do not promote r2. Remove automatic neural selection from draft #40 before review/delivery. | Final artifact is VALID in TestFlight, intended testers can access it, phone version is verified, and reusable gameplay/UI checks remain green. |
| **2. Make comparisons cheap to repeat** | Minimum checkpoint comparison implemented, reviewed and tested; original-versus-r2 diagnostic complete. | Preserve this entry point. Add separate builds/opponent pools only when a concrete experiment needs them; reuse the analyzer. |
| **3. Make training faster without weakening learning** | [Snapshot experiment complete](2026-09-06-rollout-snapshot-experiment.md#result-and-decision): exact equal-update model/Adam parity; +5.57%/+2.02% GPU throughput, below the required 5% in both pairs. **Inconclusive, not adopted.** Budget spent; no owned run active. Retain the guarded comparison rather than chasing this small gain. | A bounded before/after experiment improves time-to-quality without correctness or playing-strength regression. Partial host attribution is not a complete GPU/phase breakdown. |
| **4. Improve strategy and architecture** | Balanced selected by the [fair comparison](2026-09-06-balanced-original-decision.md#result). Stop r2 continuation. Next: original-model look-ahead [feasibility first](2026-09-06-search-next-experiment.md), then one controlled search experiment only if runtime/semantics are viable; otherwise prioritize concrete rule-based road/trade failures. No training is running. | Each attempted change has a recorded hypothesis, fixed budget, result and decision. Promote useful candidates through fresh confirmation and device tests. Stop failed lines rather than automatically extending them. |
| **5. Character, personality, difficulty** | Deferred. Keep strategy, strength and expression separate. | Measured tiers and intentional styles support honest UI labels; authored reactions are grounded in real events. LLM wording/chat needs a separate latency, cost and product decision. |

**Allocation:** retain the working product and close PR debt; the next research
effort belongs to the narrow stage-4 feasibility question, not more profiling,
an architecture sweep or an r2 training extension. Stage 2 is sufficient today.
Keep one implementation and at most one bounded GPU run active; background
reading can continue. A delivery block need not stop independent tooling work.

## Reuse these entry points

Commands run from the repository root. The linked skill owns prerequisites and
the full recipe; this table is a router, not another copy of those instructions.

| Need | Existing entry point |
| --- | --- |
| Fast neural compatibility / full-game regression | `swift test --package-path Packages/CatanAI -c release --filter Upstream` |
| Simulator / phone installation and visual inspection | [run-settlers](../../.claude/skills/run-settlers/SKILL.md) |
| Actual taps and gameplay acceptance | [play-settlers](../../.claude/skills/play-settlers/SKILL.md) |
| Release readiness, hosted app and native UI baselines | `scripts/gate.sh --debug-app`; [verify-settlers](../../.claude/skills/verify-settlers/SKILL.md) |
| TestFlight / signing / tester access | [ship-testflight](../../.claude/skills/ship-testflight/SKILL.md) |
| Seeded runner and bounded training supervision | [sim-harness](../../.claude/skills/sim-harness/SKILL.md); `python3 scripts/training_watchdog.py --help` |
| Bounded upstream throughput profile | `python3 scripts/profile-catan-training.py --help`; [protocol, current budget and results](2026-09-06-training-profile.md) |
| Equal-update rollout experiment | Same profiler, opt-in `--updates` / `--snapshot-mode`; [frozen protocol and decision](2026-09-06-rollout-snapshot-experiment.md) |
| Evaluation statistics and interpretation | [bot-strength](../../.claude/skills/bot-strength/SKILL.md); `python3 scripts/analyze-bot-evaluation.py --help` |
| One-command frozen neural/heuristic smoke comparison | `python3 scripts/evaluate-bots.py --config config/evaluation/neural-r2-smoke.json --output /tmp/empires-eval-unique-name`; [contract and evidence](2026-09-06-reusable-evaluation.md) |
| Training reconstruction and artifact audits | [replication plan](2026-09-05-catan-rl-training-replication-plan.md), [run evidence](2026-09-05-public-catan-reproduction-log.md) |

The reconstruction commands require their isolated upstream Python environment
(`torch`, `catan_py`, pinned source); the Mac system Python is not that environment.
The native comparator must freeze both the executable **and its model resources**.
Copying only `sim` is no longer a complete neural baseline.

## Budgeted evidence, not endless significance hunting

1. **Correctness first:** illegal moves, lost saves, broken UI, model/feature
   mismatch and unaccounted fallbacks fail independently of win rate.
2. **Smoke:** a few complete seed rotations prove that the pipeline works.
   Label these development seeds; they do not establish strength or a tier.
3. **Screen:** before training, record the question, one changed variable,
   minimum useful gain, seed set, training/evaluation time caps and stop rule.
   Compare equal samples **and** equal elapsed time for throughput changes.
4. **Report cheaply:** keep point estimates, absolute percentage-point changes,
   completion, cost and intervals. Computing a 95% interval from existing games
   does not require extra inference. An explicitly chosen 80% exploratory
   interval may guide the next experiment; it is not “80% probability this is
   better.” The current analyzer implements 95%, not an 80% switch.
5. **Confirm selectively:** spend more games only on practically useful leads;
   reserve fresh seeds and several frozen opponents for the finalists. Repeated
   selection on one seed set overfits it. Small samples remain inconclusive,
   not equivalent, even when no conventional significance threshold is met.

Keep configurations separate (players, victory target, board, information
access). Exact dice outcomes need not stay aligned once policies consume random
events differently. Preserve raw failures/caps and include completion beside
decisive-only win rate. A neural *route* can be a forced move: it is not an
inference-call count. Choose practical thresholds per experiment, not one
universal “80% better” target.

## Research and experiment queue

This is a hypothesis backlog, **not a completed 2023–September 2026 literature
review or the active execution order**. The baseline decision above supersedes
this initial cost ordering. Review primary papers and runnable source
in that date range, retaining older foundational baselines when useful. Each
shortlisted idea needs its source, reproducibility/license check, implementation
cost, compatible controls, expected mechanism and failure test before coding.

| Order | Candidate | First question / cost |
| --- | --- | --- |
| 1 | Rollout, environment stepping, batching and data movement | Where is wall time actually spent? Profile first. **S** |
| 2 | Batched inference, compilation, mixed precision, update batching | Can throughput improve without numerical or learning regressions? Each separately. **S/M** |
| 3 | PPO optimization: normalization, clipping, schedules, entropy, batch size | Is the baseline learning stably and using its data well? One controlled change. **M** |
| 4 | Opponent diversity, every-chair training, match-rule curriculum | Does improvement transfer beyond the training opponents/chair/rules? **M** |
| 5 | Residual/normalized MLPs, width/depth and capacity | Does better capacity or conditioning beat the current dense network at comparable budgets? **M** |
| 6 | Value targets, multiplayer critics, distributional value heads | Is poor value estimation limiting learning or search? **M/L** |
| 7 | Phase-specific or autoregressive action heads | Can explicit compound decisions reduce approximation and action-space waste? **L** |
| 8 | Graph or attention-based board representations | Does representing connectivity improve spatial generalization versus the MLP? **L** |
| 9 | Road objectives, trade valuation, auxiliary prediction tasks | Do measured capability failures need better observations, objectives or planning? Fixtures first. **M/L** |
| 10 | League/self-play sampling and exploitability diagnostics | Do gains survive diverse frozen opponents rather than exploiting one? **L** |
| 11 | Bounded policy-guided search and teacher distillation | Is search worth phone latency; can its gains be distilled offline? **L** |
| 12 | Recurrence, history and opponent/belief models | Does history add value under the chosen information contract? Perfect information remains allowed. **L** |
| 13 | Replay/off-policy alternatives and sample reuse | Is the sample-efficiency gain worth new algorithm and stability risk? **L/XL** |
| 14 | Hierarchical goals or learned world models | Can longer-horizon planning beat simpler confirmed candidates? **XL** |

Global Conquest is a source of reusable infrastructure and experiment lessons,
not proof that a Risk algorithm works in Catan. Consult the
[existing lessons audit](2026-09-05-global-conquest-lessons.md) when a concrete
experiment needs it; avoid reopening a broad audit before the first profile.

## The repeatable loop

Hypothesis → bounded train → frozen comparison → recorded decision → export/parity
→ app regressions → phone/TestFlight → freeze promoted baseline → next hypothesis.

Every train/evaluation run gets a deadline and an active watcher **before**
launch. Check the terminal outcome; never silently extend a stopped run or
restart around a driver update. Retain failed runs. A speed change affecting
numerics is also a learning experiment, not proven behavior-preserving cleanup.

For each experiment retain: source/config/model hashes, parent checkpoint,
hardware/dependencies, seeds/opponents/rules, budgets, command, raw results,
uncertainty, practical gain, cost, and **adopt / reject / inconclusive / invalid**.
Record why; a bug-invalid run is not evidence that an idea failed. Keep manifests
machine-readable and decision notes short beside the run's evidence.

## Context maintenance

- Update this tracker's **status and next action**, replacing stale text rather
  than appending daily journals. Add a skill/script only when it removes a real
  repeated step; extend the existing one first.
- Put detailed results beside [integration evidence](2026-09-06-neural-app-integration.md)
  or the relevant experiment. Link them here only when they change the next decision.
- Consult [background research](2026-09-05-ai-strategy-research-program.md) for
  theory/source comparisons, not current task order. Reconcile contradictory
  live instructions; preserve historical results with their date and limits.
