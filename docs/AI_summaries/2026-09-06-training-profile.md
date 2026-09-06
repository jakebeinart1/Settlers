# Checkpoint fidelity and first training profile

**Date:** 2026-09-06. Current priorities: [AI-PROGRAM.md](AI-PROGRAM.md).
This follows the [native checkpoint comparison](2026-09-06-reusable-evaluation.md#result-and-decision),
which reversed the upstream ranking. No new model is approved for app promotion.

## Diagnostic questions

1. **Export corruption:** re-exporting each original PyTorch checkpoint should
   reproduce every retained tensor byte. Compare CPU/Rust predictions separately;
   a changed self-check float is not necessarily a changed weight.
2. **Compound observation mismatch:** real staged Road Building, Knight/victim
   and out-of-turn discard observations should agree with the pinned Rust oracle.
   Prescribed logits alone cannot prove that input encoding is correct.
3. **Training generalization:** if the first two checks pass, isolate rules,
   opponents and training curriculum in subsequent experiments. A stronger
   seven-point calibration score does not establish native ten-point strength.

## Fidelity result

Both models reproduce all **1,108,268** parameter floats and the CTNN header
bit-for-bit using the unchanged upstream exporter. Their stored probe inputs
also match. Across platforms the probe predictions differ by at most 0.000000954
(original) and 0.000011445 (r2), below the loader's 0.001 tolerance.

Each checkpoint also passed 70 CPU/Rust numerical cases: the existing 31 probe
inputs plus 39 frozen real upstream positions. Separate Rust processes agree
bit-for-bit; CPU/Rust maximum absolute logit difference is 0.000305176 and no
unmasked top-output choice differs. These are **numerical checks, not masked
gameplay or exhaustive parity**. The first numerical attempt failed because
`rustc` was absent from PATH; the rerun used the existing isolated compiler.

[Raw audit, script, logs and bounded receipts](evidence/training-profile-20260906/fidelity/audit.json).
Large checkpoints and re-exports remain outside git; their hashes are recorded.

## Compound observation parity

The real policy path now checks **34 staged observations** against independently
generated Rust vectors (1,350 features each), covering Road Building, Knight
before/after rolling, robber victim selection and out-of-turn discards at both
table sizes. Moves remain legal, the caller's state/RNG stays unchanged until
commit, and no heuristic fallback occurs in these fixtures. All 23 focused tests
passed in two processes. Deliberately giving the second road the wrong remaining
road count fails feature 1331 on both tables; the mutation was removed.

These cases found **no adapter mismatch**, not proof of exhaustive equivalence.
Award ties/transfers and the complete seven/discards-to-robber transition remain
uncovered by these new oracle fixtures; they are not confirmed defects.
The generator preserves the original 39 fixtures byte-for-byte. Reproduction
commands/hashes are in the
[fixture provenance](../../Packages/CatanAI/Tests/CatanAITests/Fixtures/upstream-compound-observations.provenance.json).

## Predeclared profiling protocol

### Existing-checkpoint continuation diagnostic

Before spending another training budget, compare the saved fresh-final model
(121,626,624 decisions) with r2 (a further 148,807,680 decisions). New development
seeds **960901–960932**, four players, target 10, randomized native boards,
three fixed Greedy opponents, every chair: 128 games per arm, ten-minute total
watchdog. Use the existing native evaluator and identical adapter/fallback.
A **10-point** paired difference would warrant investigating this training stage;
smaller or uncertain results remain inconclusive. This single lineage cannot
establish overtraining as the cause or select a shipping checkpoint.

The published checkpoint records 46,497,792 continuation decisions and a parent
named for 43,376,640 decisions (about 89.9M combined, historical lineage partly
unavailable). r2 records 270.4M across its two verified stages. Adam counters
reconcile: 127,540 fresh optimizer steps + 156,016 additional steps = 283,556.
Resume restores weights/optimizer, but restarts environment, RNG, run counters
and wall-clock reward schedule. These are upstream semantics, not newly fixed bugs.

**Result: failed completion gate, not a paired ranking.** The fresh-final arm
finished 126/128 games, with 77 wins among those 126. In chair 3, seeds 960920
and 960922 reached the 3,000-action cap (final VP [7,6,4,9] and [7,3,9,8]).
The smoke wrapper exited 1 before running r2, as designed. Keep that failure;
there is no baseline result or paired interval for this seed set. The earlier
checkpoint is not a promotion candidate on this evidence.
[Raw shards and failed receipt](evidence/training-profile-20260906/fresh-continuation-diagnostic/run.watchdog.json).

### Throughput measurement

- **Question:** where does the actual RTX 4090 training pipeline spend host
  time, and how much does the profiler itself distort throughput?
- **Control / instrumented arm:** unmodified pinned `training/ppo.py`, same
  r2 parent checkpoint and reconstruction continuation flags; only cProfile
  instrumentation differs. No annealing, architecture or policy changes.
- **Budget:** one minute of training per run, three-minute independent watchdog
  including startup, final evaluation and artifact validation. Run sequentially;
  actively supervise the foreground job. Two runs per mode if the first pair
  finishes correctly, at most four minutes of training in this diagnostic.
- **Evidence:** retain exact commands, source/binding/parent hashes, hardware,
  dependencies, full metrics/logs, raw profile and exit receipt. Verify finite
  checkpoints, unchanged parent/source, nonzero updates and the actual CUDA device.
- **Interpretation:** report training decisions and wall time including final
  evaluation separately. cProfile measures host calls including waits, not
  isolated GPU-kernel duration; cumulative times overlap. Warmup, final evaluation
  and profiling overhead must not become a claimed training speedup.
- **Stop / next decision:** any invalid artifact, non-finite metric, failed
  command or deadline stops that run and is retained. No automatic retries or
  promotion. Choose the next measured bottleneck, then predeclare a separate
  optimization with equal-sample and time-to-quality checks.

### First pair: timing invalidated by shared GPU work

Both runs completed inside their 180-second watchdogs and produced finite
checkpoints. The retained numbers are **not clean throughput measurements**:

| Run | Training decisions | Updates | Trainer elapsed incl. final evaluation | Median reported update SPS |
| --- | ---: | ---: | ---: | ---: |
| control-1 | 1,449,984 | 59 | 65.03 s | 25,659 |
| cprofile-1 | 1,671,168 | 68 | 64.18 s | 39,202 |

At 17:49 UTC a foreign GPU training process was observed, started at 17:34 UTC,
overlapping both runs. Its shared exclusive lock was held. We did not stop or
modify it. [Contention evidence](evidence/training-profile-20260906/gpu-contention.json).
The faster instrumented run is **not** evidence that profiling improves speed.

The contaminated host profile suggests places to inspect: `VecEnv.step` 19.03 s,
`torch.as_tensor` 5.69 s, `.cpu()` 3.97 s and `.item()` 3.44 s of self time;
evaluation totals 9.06 s cumulatively and overlaps these calls. These are not
isolated kernel/phase costs or a reliable bottleneck ranking under contention.
[Raw control](evidence/training-profile-20260906/control-1/run.watchdog.json) /
[raw profile](evidence/training-profile-20260906/cprofile-1/profile.json).

**Protocol amendment, before the next launch:** keep this invalid pair. Use the
remaining two one-minute training slots for one clean control/profile pair,
with the same parent/flags and 180-second watchdog each. Require an explicit,
nonblocking shared GPU lock and check for other compute processes. Refuse a
busy device; no waiting process, forced takeover, automatic retry or budget
extension. Any scheduler may check availability only until **2026-09-06 19:00
UTC**, then report and pause. Run IDs: `profile-20260906-control-2` and
`profile-20260906-cprofile-2`. A failed launched arm ends this diagnostic.
The existing `watch-empires-gpu-reconstruction` heartbeat covered availability
at ten-minute cadence. Both runs finished under active foreground supervision
before the cutoff; the heartbeat was then paused.

The wrapper also now starts its watchdog before importing Torch/the binding,
and validates all nested metric numbers, including evaluation and game rows.
The old wrappers/receipts are retained unchanged; post-run checks are separate.

### Clean pair: complete, diagnostic budget exhausted

At 18:24 UTC the device listed no compute processes and the shared lock was
available. Both runs acquired that lock, used the same frozen parent/flags,
passed full artifact validation and ended with watchdog exit 0. No foreign
compute process was observed during the recorded checks. Advisory locking is
not proof against a job that ignores the lock.

| Run | Training decisions | Updates | Trainer elapsed incl. final evaluation | Median reported update SPS |
| --- | ---: | ---: | ---: | ---: |
| control-2 | 2,703,360 | 110 | 62.62 s | 50,218 |
| cprofile-2 | 2,408,448 | 98 | 62.82 s | 44,963 |

The instrumented run collected 10.9% fewer decisions. That is consistent with
measurement overhead, **not a tested speed optimization**. One clean pair does
not estimate run-to-run variation. The contaminated first pair is not a second
clean replicate, and the exhausted four-minute budget is not extended.

Host self-time reports `VecEnv.step` **22.49 s** (13,969 calls), `as_tensor`
**4.30 s**, `numpy.array` **3.23 s**, and array copies **2.30 s** (4.82M calls).
`.cpu()` and `.item()` report 1.22/1.48 s. These are host-call measurements,
including waits, not isolated GPU-kernel time. They mix rollout/update/evaluation;
main-loop bookkeeping and GAE are not separately reported. Cumulative caller
times overlap and cannot be added into a pipeline breakdown.

**Decision:** retain this as the first exclusive-device profile, with no new
checkpoint promotion or throughput claim. The next small investigation is
phase attribution and rollout data handling (millions of per-transition copies
and repeated array assembly), alongside the larger environment-step cost.
Measure those phases before choosing a buffer/batching optimization; leave
architecture, precision, learning rules and opponents fixed. Any implementation
needs a separate predeclared equal-sample/time-to-quality comparison, not another
run under this spent budget.

[Control evidence](evidence/training-profile-20260906/control-2/run.watchdog.json) /
[instrumented evidence](evidence/training-profile-20260906/cprofile-2/profile.json)
include exact source/worker/model hashes, raw metrics, profiles and receipts.
These short-run checkpoints are timing artifacts, not candidate game AIs.

## Verification and review

- Export/numerical receipts and compound red/green logs are retained above and
  in [verification/](evidence/training-profile-20260906/verification/).
- Isolated reconstruction suite: **33 tests**, green with one Linux-only skip
  on Mac. All **18 profiler tests** passed on Linux, including real temporary-lock
  refusal, release and lock lifetime; no GPU training in those tests.
- A regression injecting nested NaN, infinity and overflow into evaluation/game
  rows failed in ten cases before the validator fix, then passed. Both original
  profiling runs passed a separate post-run check of every metric and checkpoint;
  that does not repair their timing contamination.
- Independent standards/spec review closed the startup-watchdog and finite-metric
  findings. Format checks and both edited skill validators passed. These isolated
  Torch tests are separate from the dependency-free gate and Linux CI.
- Full pre-push gate passed on **2631a11**: 105 tool tests, 234 engine tests,
  146 AI tests, 262 hosted app tests and 48 UI tests (310 logical app/UI tests,
  373 parameterized runs in Xcode's device summary). Release build passed;
  standalone Debug build was not requested. Coverage: 95.97% engine / 96.66% AI.
  [Raw gate](evidence/training-profile-20260906/verification/pre-push-gate.log)
  and [Xcode summary](evidence/training-profile-20260906/verification/app-ui-summary.json).
  The enclosing push exited **141** after its idle SSH connection closed;
  that is a failed upload despite a green gate, not remote publication.
  Retry uses SSH keepalives with the normal pre-push hook intact.

**Status:** fidelity and sampled compound parity passed; the exclusive-device
profile is complete and its watcher paused. No training remains active from this
diagnostic. Phase attribution and an isolated optimization are next, not done.
