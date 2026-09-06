# Rollout snapshots — predeclared experiment

**Status:** complete; **inconclusive, not adopted**. Protocol below was frozen
before implementation/runs, 2026-09-06; thresholds were not changed afterwards.
**Question:** can batch-owned snapshots reduce Python allocation overhead without
changing a single training decision or optimizer update?

## One change, fixed control

Control A copies each observation/mask row into its transition. Candidate B copies
the two complete arrays once per environment step and retains row views. It does
not reuse scratch storage. Pending records span updates, so views must keep their
original snapshots alive. Basic NumPy indexing shares storage; a copy owns new
storage ([NumPy documentation](https://numpy.org/doc/stable/user/basics.copies.html)).

Keep model, PPO, rewards, seeds, opponents, chain insertion/reverse GAE order,
minibatch ordering, periodic evaluation and saving unchanged. Both arms receive
the same explicit update limit AND wall-clock deadline. No clock monkeypatching.
Continuation uses `vp_delta=0` with no annealing option: time-driven environment
resets would invalidate equal-update comparison. Frozen upstream stays untouched;
retain the exact generated source and its SHA alongside each run.

- Upstream commit: `021279c56834b6203480e5292e1de7246e47bd68`.
- PPO SHA: `720ecfa3971314b0feeed6cd11283ecbeea158b7d70d4deab1b73b0948bb7f42`.
- Parent: r2 final `step_0148807680.pt`, SHA
  `b2b65d569ef2e56bbca9e6f6ecfd41b4c0905842803e62c3aff2aeec7d96dace`.
- Existing continuation flags: 256 environments × 96 rollout, seed 0,
  512-wide model, four PPO epochs. Every arm reloads that parent.

## Budget and supervision

This is a NEW budget, not an extension of the exhausted profiling diagnostic.

1. CPU correctness: A then B, **3 updates each**, inner limit **120 seconds**,
   existing outer watchdog **240 seconds** each. Two runs maximum.
2. Only if correctness passes and the shared GPU is idle: **A1 B1 B2 A2**,
   **80 updates / 1,966,080 decisions each**, inner limit **60 seconds**,
   outer watchdog **180 seconds**. Four runs maximum, unprofiled (`--mode none`).
3. Nonblocking shared GPU lease plus compute-process check before each arm;
   retain device samples during each run. Foreign contention invalidates timing.
   Do not stop other projects. A failure stops the series, without automatic retry.

Monitor owned-process peak RSS while training; terminate at **8 GiB** (sampled
guard, not an allocation barrier). Acceptance is stricter: candidate peak RSS
**≤4 GiB and ≤512 MiB above its paired control**. Record CUDA allocated/reserved
peaks separately. Snapshot views may retain whole batches through lone pending
records; summing row sizes is not a memory measurement.

## Required evidence and decision

- Storage tests overwrite source buffers, retain pending across updates, and
  exercise terminal/repeated-seat handling. Unsafe no-copy behavior must fail.
- Exactly requested updates/decisions and expected periodic/final eval rows;
  all finite metrics, weights and optimizer state. A normal early timeout fails.
- Model tensors and complete Adam state match exactly at **every saved step**,
  not checkpoint-file bytes (run names/configuration differ). Also compare ordered
  training/evaluation metrics excluding wall time/SPS. A/A disagreement invalidates
  the determinism premise before judging B.
- Primary performance: existing worker elapsed, including cold initialization,
  periodic/final evaluation and saves. Require **A/B ≥1.05 in both pairs**;
  report training SPS secondarily. These are timing replicates, not learning seeds.
- **Reject** below-threshold gains or unacceptable memory; **invalid** for broken
  equivalence/incomplete work/contamination; **inconclusive** for mixed pairs.
  A pass is a throughput lead requiring equal-time/time-to-quality confirmation,
  not an expert-play claim or permission to promote the weak r2 app default.

The clean profile charged 2.30/62.82 seconds to row copies. This is a modest
opportunity; a negative result is useful and will be retained. No app changes.

## Result and decision

| Pair | Control A | Snapshot B | Throughput gain | Additional peak RSS |
| --- | ---: | ---: | ---: | ---: |
| A1 → B1 | 46.970 s | 44.491 s | +5.57% | 13.0 MiB |
| B2 → A2 | 46.998 s | 46.065 s | +2.02% | 16.6 MiB |

All four GPU arms completed 80 updates, 1,966,080 decisions and 12 evaluation
rows. Every model tensor and full Adam state matched at all five saved steps;
all 80 ordered training rows and 12 evaluation rows matched after removing only
`unix_ms`/`sps`. The separate CPU pair matched at three updates. These are
within-device comparisons, not a claim of bit-identical CPU/CUDA arithmetic.
GPU peak process RSS was 1.91–1.92 GiB. GPU allocated/reserved peaks also matched.
All six watchdogs exited successfully; sampled compute processes showed only
the owned worker during training. Sampling cannot exclude unsampled short jobs.

**Decision:** do not enable batch snapshots in reconstruction or app training.
The second pair missed the predeclared 5% requirement. This is an inconclusive
practical speedup, **not an implementation or model-architecture failure**:
correctness and memory checks passed. Copies accounted for a small part of the
original profile, so a modest/noisy gain is plausible; two pairs do not identify
the source of timing variation. No extra repetitions were added to chase a pass.
The equal-time follow-up was conditional on both pairs passing and was not run.

Keep the opt-in experiment and equal-work validators for repeatable comparisons;
the default still executes the unchanged upstream trainer. Prioritize the
[native target-mismatch experiment](2026-09-06-training-profile.md#native-transfer-diagnosis-and-next-target-experiment-2026-09-06)
over extending this small optimization. The weak r2 default remains held.

### Evidence and reproduction

- [Machine verdict and every checkpoint digest](evidence/rollout-snapshot-20260906/result.json).
- Per-arm subdirectories retain exact command/source/dependency manifests,
  watchdog receipts, peak memory, and the complete ordered train/eval rows.
  `raw_metrics_sha256` binds the unfiltered game/metric stream; the reduced
  `train-eval.jsonl` files are explicitly not that full stream.
- [Device samples](evidence/rollout-snapshot-20260906/device-samples.json) retain
  observed timestamps and worker PIDs. The manifest records each owning PID.
- Full streams, generated trainer source and measured helper versions:
  `/Users/alex/Library/Application Support/EmpiresResearch/experiments/rollout-snapshot-20260906/`;
  remote GPU artifacts: `/home/alex_ubuntu/empires-research/snapshot-20260906/`.
  Checkpoints remain in the unique upstream run directories named by receipts.
- Reuse each manifest's command through `scripts/profile-catan-training.py`
  with a **new** output directory and separately authorized/predeclared budget.
  `--updates 80 --snapshot-mode row|batch --mode none` selects this experiment.
  Do not reuse spent run IDs or silently rerun this six-run budget.

Review subsequently strengthened checkpoint-inventory validation, made memory
termination survive a receipt-write failure, and kept experimental CUDA/memory
instrumentation out of default profiling. Formatting/validation changes did not
change generated trainer bytes; measured source/helper hashes remain in the
original manifests. Revalidate retained artifacts instead of retraining to update
their receipts.

Focused verification: **45 isolated reconstruction/profile tests passed** (one
Linux-only lease test skipped on macOS), including 12 snapshot/guard regressions.
An in-memory unsafe no-copy mutant was observed red: two tests produced six
snapshot/batch assertion failures, exit 1. Terminal flushing, repeated seats,
empty updates, pending across multiple updates and exact ordered GAE/tensors
are covered using snippets from the executed source, not a second trainer.
The logs and receipts are retained beside the machine verdict. Black and
`git diff --check` pass. The ordinary repository pre-push gate remains mandatory.
