# Empires AI — current work and next decisions

**Updated:** 2026-09-06. This is the live tracker, not a claim that later stages
are complete. Read it before planning AI work, running experiments, or reporting
progress. Detailed evidence and operational recipes stay behind the links below.

## Where we stand

- **Baseline:** the bounded fresh-plus-continuation reconstruction is complete.
  Frozen `gpu-baseline-20260906-r2` is our reproducible starting artifact, not
  proof of expert play or exact recovery of unavailable historical training.
- **Integration:** offline neural/hybrid play is implemented and independently
  reviewed. Full gate, native UI journeys, parity checks, and full games passed.
  [draft PR #40](https://github.com/jakebeinart1/Settlers/pull/40) is stacked on
  [research PR #37](https://github.com/jakebeinart1/Settlers/pull/37); neither is merged.
- **Delivery remains open:** Build 5 is on the manual simulator, not TestFlight
  or the phone. The final archive timed out at its signing-key prompt; the phone
  is unavailable to Xcode. Resume delivery when those external blocks clear.
- **Evaluation first slice works:** one command freezes r2, runs both arms,
  rotates chairs and retains a report. Automated tests repeat it in separate
  processes, with strict decision-route auditing. No new training was launched.
- **Quality warning:** the audited 32-board follow-up gave r2 **52/128** versus
  Balanced **112/128** wins against Greedy, all chairs rotated, no unexpected
  fallbacks. This is one native configuration, not a universal ranking.
  Default promotion is held: next compare checkpoint/adapter/rule-distribution
  effects before assuming the transferred baseline is a stronger default.
- **Limit:** trading remains heuristic; native rules differ from training.
  Compatibility and a legal complete game are not strength measurements.

## Execution order and finish lines

| Stage | Status / next action | Done when |
| --- | --- | --- |
| **1. Deliver and retain regressions** | Simulator verified; phone/signing blocked; native strength warning under assessment. | Resolve the default-promotion warning; final artifact is VALID in TestFlight, intended testers can access it, phone version is verified, and reusable gameplay/UI checks remain green. |
| **2. Make comparisons cheap to repeat** | First slice implemented, reviewed and tested: frozen r2 versus a named heuristic, all chairs, one rules cell per report. | Next accept two hash-identified compatible checkpoints for the transfer investigation; incompatible architectures use separate frozen builds. Keep the existing analyzer. |
| **3. Make training faster without weakening learning** | Next major effort after the minimum evaluator works. Profile the actual 4090 pipeline before choosing an optimization. | Repeated profiles identify rollout/inference/transfer/update/evaluation costs; a bounded before/after experiment improves time-to-quality without correctness or playing-strength regression. |
| **4. Improve strategy and architecture** | Main multi-week effort. Research and reprioritize the candidate queue below; run isolated experiments. | Each attempted change has a recorded hypothesis, fixed budget, result and decision. Promote promising candidates through fresh confirmation and device tests, then freeze the new baseline. This stage repeats. |
| **5. Character, personality, difficulty** | Deferred. Keep strategy, strength and expression separate. | Measured tiers and intentional styles support honest UI labels; authored reactions are grounded in real events. LLM wording/chat needs a separate latency, cost and product decision. |

**Allocation:** unblock delivery promptly; spend only enough on stage 2 to make
the next comparison reproducible. Then put the bulk of effort into stages 3–4.
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

This is a hypothesis queue, **not a completed 2023–September 2026 literature
review or a predicted ranking of gains**. Order is initial cost/diagnostic value;
revise it after profiles and evidence. Review primary papers and runnable source
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
