# Public Catan AI reproduction log

**Date:** 2026-09-05

**Purpose:** distinguish runnable evidence from repository claims before Empires
selects an external agent, checkpoint, or algorithm.

## Verdict

**Update after auditing newer public branches:** upstream commit `7046c6b`
publishes a later V5A-derived checkpoint. It is a candidate for later
first-to-10, realistic-information comparisons; the `021279c` artifact below
remains the reproduction priority. The newer model completed a fresh
balanced 768-game gate per scenario and won 55.1% against Heuristic-v1 and
52.9% against Heuristic-v2 under realistic information. See
[`2026-09-05-catan-rl-upstream-artifact-audit.md`](2026-09-05-catan-rl-upstream-artifact-audit.md)
for the non-comparable engines/seed schedules and missing-run-artifact caveat.
The earlier preferred-baseline claim is withdrawn; these scores do not select
a stronger policy.

Only [Eli6th/catan-rl](https://github.com/Eli6th/catan-rl) supplied both a
usable checkpoint and a runnable headline-strength command. Its current code
produced a result close to the published 82%, but did **not** exactly reproduce
the historical protocol: the experiment ledger says first-to-7, while the
current command exposes no victory-target option and uses the engine's 10-point
default.

No audited project supplied an executable cross-project benchmark under a
shared Catan ruleset. “Independently executed” below means the author's pinned
code was run locally; it does not make the author's engine, heuristic opponent,
or metric independent.

## Isolation

- Temporary checkouts, virtual environments, Cargo cache, and Rust toolchain
  lived under a temporary directory.
- No persistent system package or shell profile was changed.
- Rust 1.98.1 was installed only into the temporary audit root.
- Candidate repositories were not patched to make a failing command pass.
- The final calibration used macOS 26.5.1 on an Apple M5 Pro, Python 3.12.14,
  PyTorch 2.14.0, NumPy 2.5.2, and maturin 1.15.0.

## Result matrix

| Candidate | Executed evidence | Outcome | Meaning |
| --- | --- | --- | --- |
| Eli6th/catan-rl `021279c` | `cargo test --release`; shipped 100-game AlphaBot command; 192-game seed-777 run | 112 tests passed; AlphaBot 83/100; AlphaBot 157/192 = 81.8% | Strongest runnable package; first-party evaluator only, fixed chair 0, and historical 7-VP protocol is not reconstructible from the current CLI |
| nogulong/rust-catan-rl `f734fc7` | Core Rust tests | 142 passed | Core is real; full workspace/evaluator requires an omitted, unpinned JSettlers checkout and unavailable exact Java build path |
| Catanatron `d3f4ad0` | Full test suite and random/weighted-random smoke | 199 passed; 93% reported coverage; 100 games completed | Strong engine correctness evidence, not learned-agent strength evidence; historical benchmark script has API drift |
| PeterLP catanatron-1v1 `37b60be` | Focused 1v1 tests and `F,F` smoke | 38 tests passed; 10 games completed | Current rules path runs; learned-policy checkpoint bytes are absent, so reported strength could not be replayed |
| Henry Charlesworth `62a1c04` | Artifact/runtime inspection | Checkpoint present; no run | Exact 2021 Python/Torch/SB3 stack does not fit the available interpreters without an auditor-authored compatibility port |
| SamiKoneru/Catan_bot `600f29c` | Artifact inspection | No run | Required `checkpoints/final.pt` is absent; its audit script otherwise falls back to an untrained policy, which would be a false reproduction |
| Monte Catano `64edc0a` | Source/harness inspection | No run before cutoff | MCTS and SPRT harness exist, but no retained external strength result was found |

## Eli6th executable result

The pinned source publishes the following command:

```sh
cd rust
cargo run -p catan-sim --release -- \
  --games 100 --players A,H,H,H \
  --net ../models/catan-512.ctnn --alpha-config 8,96,300
```

Observed result:

- exit 0;
- 100 completed games and 50,756 steps;
- AlphaBot 83 wins; the three heuristic chairs won 4, 7, and 6;
- simulator elapsed time 22.754 seconds after compilation.

The ledger-aligned seed run was:

```sh
cargo run -p catan-sim --release -- \
  --games 192 --players A,H,H,H --seed 777 \
  --net ../models/catan-512.ctnn --alpha-config 8,96,300
```

Observed result:

- exit 0;
- 192 completed games and 91,548 steps;
- AlphaBot 157 wins; heuristic chairs won 15, 9, and 11;
- 81.77%, reported as 81.8%;
- simulator elapsed time 42.281 seconds.

The local run supports “the current package gets about 82% in its own
evaluator.” It does not support “AlphaBot is the strongest standard Catan AI.”
It remained in chair 0, saw the project's perfect-information observation,
used bounded trading, and faced only the project's frozen heuristic.

## Checkpoint and training-pipeline calibration

- Both released blobs matched their pinned hashes: checkpoint `c4258f23…` and
  CTNN `21f3b380…`.
- The full Rust suite passed 112 tests. The Python binding smoke passed 200
  episodes and 744,704 policy decisions.
- The binding could not build with its committed nested lockfile under
  `--locked`; the documented unlocked command added `rand` to `catan-env` in
  that lock and then built. The root locked Rust build remained clean.
- Re-exporting the checkpoint preserved every tensor byte and changed only
  three low-order bytes in the final self-check logits under PyTorch 2.14.0.
  Both CTNN files loaded and chose the same seed-0 trajectory and winner.
- A one-minute checkpoint continuation completed 1,671,168 policy steps,
  wrote a checkpoint, exported it, and played it through Rust. This verifies
  the current train-to-inference pipeline; it does not recreate the missing
  historical parent run or validate a new strength claim.

The protocol mismatch is source-verifiable: the
[experiment ledger](https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/results/EXPERIMENTS.md)
says first-to-7; the current
[CLI](https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-sim/src/main.rs)
does not parse a victory target; and the
[engine state](https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-core/src/state.rs)
defaults to 10.

## Repeatable original-policy runner and fresh-training smoke

The original source now has its own environment at
`/Users/alex/Library/Application Support/EmpiresResearch/catan-rl/original-v1`.
It is independent of the newer branches: changing their bindings cannot replace
this one's engine. The checkout is pinned at `021279c…`. Python 3.12.14,
PyTorch 2.14.0, NumPy 2.5.2, maturin 1.15.0 and the recorded Rust 1.98.1 build
describe our environment, not the unavailable historical one.

[`scripts/reproduce-catan-policy.py`](../../scripts/reproduce-catan-policy.py)
checks the source revision/edits, imported trainer, checkpoint hash, native
binary hash, Python wrapper identity, and observation/action contract before
creating any output. It refuses to overwrite an existing result directory.
The adaptation of the upstream evaluation loop retains its MIT notice.

Two separate-process runs with the final runner each produced **126/192 wins,
zero caps**, and the same reported-outcome multiset hash:
`36177758a7223345bf3253db1d2499de7445c6ef8f84ff8edb585086588c326b`.
Their complete manifests, summaries and raw outcomes are retained in
[`evidence/catan-original-policy/`](evidence/catan-original-policy/).
Within a batch, Rust workers append statistics under a mutex in scheduling
order; raw line order differs. The comparison removes only arrival ordinal,
preserving batch, winner, VP, turns, cap status, and duplicate multiplicity.
This proves repeated reported outcomes, **not identical move trajectories**;
the v1 statistics API exposes neither lane identity nor the action trace.

To replay on this machine, from the Empires repository:

```bash
CATAN_UPSTREAM='/Users/alex/Library/Application Support/EmpiresResearch/catan-rl/original-v1'
CATAN_BINDING_SHA256=aa0ca44fcde0a75374115912c67dca264e993d79bed5058f1c7db50c0253423d
PYTHONPATH="$CATAN_UPSTREAM/training" "$CATAN_UPSTREAM/.venv/bin/python" \
  scripts/reproduce-catan-policy.py --source "$CATAN_UPSTREAM" \
  --binding-sha256 "$CATAN_BINDING_SHA256" \
  --expected-outcomes 36177758a7223345bf3253db1d2499de7445c6ef8f84ff8edb585086588c326b \
  --output '/Users/alex/Library/Application Support/EmpiresResearch/catan-rl/runs/next-replay'

CATAN_UPSTREAM="$CATAN_UPSTREAM" CATAN_BINDING_SHA256="$CATAN_BINDING_SHA256" \
  PYTHONPATH="scripts:$CATAN_UPSTREAM/training" "$CATAN_UPSTREAM/.venv/bin/python" \
  -m unittest discover -s scripts/catan-replication-tests -v
```

For another machine, clone the public repository at the pinned revision, create
a **separate** Python environment, install the manifest's pinned dependencies,
and build `maturin develop --release -m rust/catan-py/Cargo.toml` from the upstream
root. Record the one-line binding-lock repair and new compiler/binary identity.
The macOS native hash above is not expected on Linux. Independently verify that
new build before using its hash as the runner's trust anchor. The manifest's
editable dependency URL reflects the original local clone source; use the
public Git revision, not that temporary URL, when recreating it elsewhere.

**Fresh smoke, completed:** started from random weights with no `--resume`;
348 updates / **8,552,448 policy decisions** in the five-minute training window.
All recorded floating-point training metrics and final model tensors were
finite. Final upstream seed-999 evaluations were 181/192 versus Random and
44/192 versus Heuristic-v1, with no caps. These are short-run diagnostics, not
the seed-777 reported gate and not a strength improvement.

The fresh checkpoint (`fd2bcecf452b0c9b2e61796833e70deee76cde2547baf83a11c017a0ac0cd62b`)
exported to CTNN (`df8c9c8e366772bc2b016431a9ca3e40411188795aa6ef848943bb4410c99e5e`).
The Rust loader accepted it and an `A,H,H,H`, seed-0, first-to-10 game completed
in 413 actions with search `8,96,300`. One game verifies execution, not strength.
Artifacts and metrics remain under the persistent `catan-rl` directory above:
`original-v1/training/runs/20260905-2033-empires-fresh-smoke/` and `runs/fresh-smoke*`.
Metrics SHA-256: `52a1c2217b79c4275bff4aa1652ac93640c5c5a5d6919dae55e417550a58f1ab`.

Exact smoke command, from that original upstream checkout:

```bash
source .venv/bin/activate
PYTHONPATH=training python -u -c 'import numpy as np, runpy; np.random.seed(0); runpy.run_path("training/ppo.py", run_name="__main__")' \
  --name empires-fresh-smoke --minutes 5 --num-envs 256 --rollout 96 \
  --victory-target 7 --vp-delta 0.05 --vp-delta-final 0 --visibility perfect \
  --lr 0.00025 --epochs 4 --minibatch 4096 --hidden 512 --device cpu --seed 0 \
  --eval-every 16 --entropy-coef 0.02 --train-seats policy,heuristic,policy,heuristic_v2
```

The hidden width, shaping anneal and entropy come from the initial run ledger.
Missing initial opponent mix, rollout, evaluation interval and other parameters
are explicitly **assumed from the published continuation config**. Seeding
NumPy is an explicit wrapper-level reproducibility correction; upstream omits
it. No upstream tracked trainer/rules source was changed. Five minutes compresses
the annealing schedule; this is not the fifty-minute first stage.

Validation: 62 dependency-free evaluation-tool tests pass, including the four
new evidence-accounting tests; six isolated-environment integration guards pass.
Independent review found two false-green risks (score-only success and an
unchecked Python wrapper); both were addressed and tested. The app and its
production AI have not changed.

## Linux / RTX 4090 compatibility (September 5)

The existing SSH alias `gc-gpu` reaches Alex's Linux/WSL machine. Research is
isolated under `/home/alex_ubuntu/empires-research`; no GlobalConquest environment,
system driver, or shell profile was changed. Rust/Cargo 1.98.1, Python 3.12.13,
PyTorch 2.14.0+cu126, NumPy 2.5.2, and maturin 1.15.0 were installed there.
The original Rust tests and release simulator build passed. CUDA availability,
device identity (RTX 4090), and an actual CUDA matrix multiplication passed.

Both Linux CPU and CUDA replay the original policy at **126 wins / 192 games,
zero caps**. Their outcome-multiset hash matches both Mac runs:
`36177758a7223345bf3253db1d2499de7445c6ef8f84ff8edb585086588c326b`.
Raw outcomes and manifests are retained in
[`evidence/catan-original-policy/linux-cpu`](evidence/catan-original-policy/linux-cpu)
and [`linux-cuda`](evidence/catan-original-policy/linux-cuda).
This is inference compatibility, not proof of reproduced training.

`scripts/run-catan-reconstruction.py` supervises the two-stage training chain:
random initialization, then continuation from that run's final checkpoint,
finite-weight/optimizer/metric validation, CTNN export, a completed native game,
and final-policy diagnostics against the published model. Four seeds are fixed
before training: 777, 930011, 930043, 930071. These remain first-chair diagnostics,
not an every-chair strength tournament or hyperparameter-selection objective.
Each command has a deadline; failures are recorded and propagated, not retried.
Fourteen isolated-environment guard tests and 62 evaluation-tool tests pass.
Review caught and corrected an exit-zero-without-winner false green and an
unbounded evaluation stage before the full training launch.

## Full GPU reconstruction — stopped incomplete

**Correction after the September 6 03:15 UTC stop:** the assistant incorrectly
treated the run directory's local Eastern time as UTC. Converting the actual
start epoch `1788661944.1607244` yields **02:32:24 UTC September 6**, not 22:32 UTC
September 5. The correct three-hour deadline was **05:32:24 UTC**, so it had NOT
expired. The stop epoch `1788664552.7859533` yields 03:15:52 UTC, agreeing with
the observed 43m28s process runtime. Python, native date, and the recorded epochs
are consistent. The earlier claim of a GPU clock/suspension problem is withdrawn:
the error was the assistant's manual conversion and handwritten watcher deadline.

The watcher sent TERM only to the verified job process group 55549 and confirmed
the timeout, supervisor, and training child had exited. Status now reads
`failed`, with `InterruptedError('received signal 15')`. The latest checkpoint
remains `step_0063307776.pt` (63,307,776 decisions) in the fresh-stage directory.
No checkpoint was deleted or promoted. Continuation, final export, and final
evaluation did not run. This is **not a completed training reproduction**.

Receipts: `evidence/catan-reconstruction/gpu-baseline/status-at-stop.json` and
the copied `fresh-at-stop.log`; full artifacts remain on the GPU host. Heartbeat
`watch-empires-gpu-reconstruction` was paused at the stop. The launch record
below is historical, not current status. Upstream resume restores weights and
Adam but resets environments, RNG, counters, and shaping schedule, so tacking
seven minutes onto this checkpoint would change the declared fresh experiment.
Preserve this artifact and use a new run ID for a complete 50+60 reconstruction.

The 30-second fresh + 30-second continuation rehearsal completed successfully:
both stages produced finite checkpoints, the exported network loaded in Rust,
the native game reached a winner, and all eight policy diagnostic batches ran.
This short rehearsal does not establish strength. Its manifest, completion
status, evaluation counts, and native-game metrics are retained under
[`evidence/catan-reconstruction/gpu-smoke`](evidence/catan-reconstruction/gpu-smoke).

The real **50-minute fresh + 60-minute continuation** job started on
September 6 at **02:32 UTC / September 5 22:32 Eastern** in detached tmux session
`empires-reconstruction-20260905`. It starts from random weights, not the
rehearsal checkpoint. CUDA training and advancing updates were observed.
Expected end was approximately 04:25 UTC September 6 / 00:25 Eastern September 6,
including export/evaluation; this is an estimate, not a completion receipt.

- Remote job directory: `/home/alex_ubuntu/empires-research/runs/gpu-baseline-20260905`.
- Current phase and errors: `status.json` in that directory; detailed stage
  output is in `fresh.log`, `continuation.log`, and `evaluation.log`.
- Upstream checkpoints stay under `original-v1/training/runs/`; each completed
  stage records its exact checkpoint path/hash in job status.
- Launch stderr: sibling `gpu-baseline-20260905-launch.log`.
- Parent job has a three-hour deadline; training stages allow ten minutes to
  finish, and native export/inference/evaluation each have ten-minute deadlines.
- tmux survives SSH disconnects, not a host reboot. No automatic retry or
  checkpoint promotion is configured. Do not launch a duplicate job.
- The local `gpu-baseline/status-at-launch.json` is explicitly a snapshot,
  **not live status or completed-training evidence**.
- Follow-up watcher: Codex thread heartbeat `watch-empires-gpu-reconstruction`,
  configured at ten-minute intervals, now paused after the terminal check. It checks process health and progress, reports
  meaningful transitions/failure/completion, and pauses after its terminal report
  or a final check at the absolute deadline. A post-launch check observed the
  fresh stage advancing beyond 38.6M decisions. The remote timeout is independent
  of this desktop watcher.

Read-only status check:

```bash
ssh -a gc-gpu 'cat /home/alex_ubuntu/empires-research/runs/gpu-baseline-20260905/status.json'
```

## Replacement run with machine-owned deadlines

`gpu-baseline-20260906-r2` is the active replacement, launched from random
weights with the unchanged 50+60 protocol after the user authorized fixing the
monitoring bugs and continuing. The interrupted checkpoint remains untouched.
Machine receipt: start `2026-09-06T03:40:12.729306+00:00`, absolute deadline
`2026-09-06T06:40:12.729306+00:00`. These strings are generated from numeric epochs
by code, not converted from the run directory's local timestamp.

`scripts/training_watchdog.py` now owns an independent on-host process-group
watchdog. It stops at the first exhausted wall-clock or Linux CLOCK_BOOTTIME
budget, escalates TERM to KILL after five seconds, shields cleanup from repeated
stop signals, and records cleanup failure as failure. An outer GNU timeout adds
a 10,830-second backstop with 15-second kill escalation. Its `inspect` command
checks host boot identity, guardian start ticks, and receipt freshness; stale or
dead supervision cannot report healthy `running` status.

The existing heartbeat `watch-empires-gpu-reconstruction` is ACTIVE again, now
targeting only r2 and reading `inspect` output. It must not reuse the old wrong
deadline, restart training, promote models, or interfere with unrelated work.
The heartbeat pauses after reporting completion/failure. The on-host watchdog
does not depend on the desktop scheduler waking up.

Verification: 71 dependency-free tooling tests passed locally; 23 isolated
integration checks passed on Linux. Regression cases cover the original epoch
conversion, forward/backward clock changes, deadline termination of a child
that ignores TERM, repeated TERM during cleanup, cleanup failures, dead guardian
and reboot detection, and real CLI execution. Review findings were fixed and
the follow-up review found no remaining blocker. The 30s+30s GPU rehearsal
completed export, a native game and all eight evaluation batches under the new
guardian (before the subsequent signal-shield/liveness hardening, which was
tested separately). Receipts are under
`evidence/catan-reconstruction/gpu-watchdog-smoke/`.

Current run root: `/home/alex_ubuntu/empires-research/runs/gpu-baseline-20260906-r2`.
The sibling `.watchdog.json` is live on the host; the local
`evidence/catan-reconstruction/gpu-baseline-20260906-r2/watchdog-at-launch.json`
is only a launch snapshot. Initial runtime inspection reported live supervision,
CUDA selected, and training beyond 565,248 decisions. The new run is not yet a
completed reproduction or a strength claim.

```bash
ssh -a -o ConnectTimeout=10 gc-gpu \
  '/home/alex_ubuntu/empires-research/original-v1/.venv/bin/python /home/alex_ubuntu/empires-research/tools/training_watchdog.py inspect --output /home/alex_ubuntu/empires-research/runs/gpu-baseline-20260906-r2'
```

## Completion audit prepared while r2 trains (2026-09-06)

At 05:12 UTC, the on-host watchdog still reported live supervision and the
continuation stage was running. The fresh stage completed its 50-minute budget
with 121,626,624 decisions and 4,949 updates. Its final checkpoint SHA-256 is
`f31527270a1e15231b54d94a1ab01896e4b13db63374e5a63f75c9e072cedba1`;
the continuation resumes that exact file. A hash-verified local backup is at
`/Users/alex/Library/Application Support/EmpiresResearch/checkpoints/gpu-baseline-20260906-r2/step_0121626624.pt`.

`scripts/audit_catan_reconstruction.py` is now deployed alongside the supervisor.
It is read-only, dependency-free, and runs after terminal success under a
60-second timeout. It verifies the watchdog/pipeline identity and deadline,
checkpoint and metrics hashes, exact continuation parent, native export/game,
and all eight predeclared model/seed cells against retained raw outcomes. It
rejects missing or duplicated cells and inflated summary counts. Batch overshoot
is retained; capped episodes never count as wins. Tensor finiteness remains the
supervisor's check, not a claim this hash-only auditor independently makes.

The actual completed 30s+30s GPU smoke artifacts pass this audit; its report is
`evidence/catan-reconstruction/gpu-watchdog-smoke/completion-audit.json`. Twelve
new regression cases exercise corrupt checkpoints, wrong parents, missing cells,
truncated outcomes, fabricated wins, running/failed/mismatched receipts, changed
protocols, native caps and overdue completion. A passed artifact audit explicitly
leaves `training_reproduction_verdict` as `not_assessed`: it is not a strength
claim, and the smoke is not the 50+60-minute reconstruction.

The ACTIVE ten-minute heartbeat now explicitly runs this audit on terminal r2
success, preserves the report and final checkpoint locally, and reports the
original/reconstructed win/game/cap counts with their limitations before pausing.
The trainer already queues export, native-game verification and evaluation
automatically; no further user instruction is needed for those stages.

## r2 completed and audited (2026-09-06, 05:30 UTC)

The full 50-minute fresh + 60-minute continuation reconstruction completed
without interruption. The independent watchdog recorded exit 0 at
05:30:35 UTC, before its 06:40:12 UTC deadline. A subsequent process-group check
found no remaining owned processes. The completion auditor passed against the
actual GPU artifacts, including raw outcomes and checkpoint/metrics hashes.

- Fresh: 121,626,624 decisions, 4,949 updates, 3,005.04 seconds.
- Continuation: 148,807,680 additional decisions, 6,055 updates, 3,604.99 seconds.
- Total: 270,434,304 decisions. These are the actual GPU sample counts, not the
  historical CPU sample budget; matching 50+60 minutes does not make them equal.
- Continuation parent: the exact fresh final checkpoint recorded above.
- Final checkpoint SHA-256:
  `b2b65d569ef2e56bbca9e6f6ecfd41b4c0905842803e62c3aff2aeec7d96dace`.
- Exported CTNN SHA-256:
  `a3c957a8765ccbb3c9afd1a8ebee45b7cbaff134c40ce0456e5024560b3ef94e`.
- Native search smoke: seat 0 won at 10 VP after 448 actions / 112 turns,
  without hitting the cap. This is one integration game, not a strength estimate.

Predeclared policy evaluation against three upstream heuristic opponents:

| Evaluation seed | Original wins/games | Reconstructed wins/games | Caps (both) |
| --- | --- | --- | --- |
| 777 | 126/192 | 134/192 | 0 |
| 930011 | 123/192 | 134/193 | 0 |
| 930043 | 126/192 | 142/192 | 0 |
| 930071 | 129/192 | 138/192 | 0 |
| Total | 504/768 (65.63%) | 548/769 (71.26%) | 0 |

The extra reconstructed episode is retained batch overshoot, not a denominator
typo. Both policies use chair 0, perfect information and a 7-VP target. The
reconstructed policy scored higher in each diagnostic batch. This is encouraging
evidence that the reconstruction learns useful play, not proof of statistical
superiority, human-level strength, the AlphaBot search headline, or exact
historical training reproduction. There is only one training seed, no chair
rotation, and the upstream parallel API exposes no per-game pairing IDs.

Final weights, CTNN, full stage logs and metrics are backed up outside git in
`/Users/alex/Library/Application Support/EmpiresResearch/checkpoints/gpu-baseline-20260906-r2/`.
The local final checkpoint hash matches the GPU receipt. All eight raw evaluation
files, status, terminal watchdog receipt and completion audit are retained in
`evidence/catan-reconstruction/gpu-baseline-20260906-r2/`.
No new training was launched, and nothing was merged or deployed to the app.
The watcher is paused after this terminal report; the next experiment needs its
own declared protocol, finite budget and watcher.

## Reproduction gates still open

The original interrupted run remains incomplete, but the replacement 50+60 run
has completed and its artifacts passed audit. The final checkpoint was selected
by completion, not by maximizing the seed-777 score. Exact historical lineage
and broader playing strength remain unproved. The five-minute pilot was not an
initialization for this experiment.

Additional evidence questions, not authorization to contact upstream authors:

1. Ask Eli6th to identify the exact engine commit embedded in the model and the
   precise sample behind 82%, then expose the historical target in the CLI.
2. Rotate AlphaBot through every chair and retain one row per game.
3. Run the same agent under realistic visibility and standard 10-VP rules,
   labeling that as a new experiment rather than a reproduction.
4. Obtain nogulong's exact JSettlers revision and model/result provenance before
   repairing its evaluator.
5. Treat Catanatron and PeterLP as correctness/methodology controls until a
   runnable learned artifact and common rules track exist.

The detailed compatibility implications are in
[`2026-09-05-catan-agent-integration-fit.md`](2026-09-05-catan-agent-integration-fit.md).
