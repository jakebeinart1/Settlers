# Training victory target — matched continuation screen

**Status:** protocol frozen before training, 2026-09-06. Implementation and both
real CPU preflights passed; GPU sequence ready, no result yet.
This is a new experiment/budget, not a continuation of the spent snapshot trials.

## Hypothesis and comparison

Training stops at seven points; our native game needs ten. The target also affects
the encoded target and normalized victory-point inputs. Test whether target-ten
adaptation improves native ten-point results versus an equally continued target-seven
control. This isolates a training-distribution change, not network architecture.

Every arm reloads the same frozen r2 model **and Adam state**:
`step_0148807680.pt`, SHA
`b2b65d569ef2e56bbca9e6f6ecfd41b4c0905842803e62c3aff2aeec7d96dace`.
No arm resumes another arm's output. Upstream commit remains
`021279c56834b6203480e5292e1de7246e47bd68`; PPO source SHA remains
`720ecfa3971314b0feeed6cd11283ecbeea158b7d70d4deab1b73b0948bb7f42`.

Only `victory_target` changes within a training-seed pair. Preserve 256 environments,
96 rollout, four PPO epochs, 512-wide network, terminal-only reward, no annealing,
policy chairs 0/2 and fixed heuristic opponents, board generator, precision, and
native adapter. Use original row copies: the snapshot candidate did not qualify.
NumPy, Torch and environment seeds must agree with the declared training seed.

## Fixed budget and run order

Before GPU launch: unit tests, source/command review, then **two CPU preflights**
(seed 1, target 7 then 10), **one update each**, inner **30 seconds**, outer
**150 seconds**. These prove configuration reaches the real trainer, not strength.

GPU order on `gc-gpu` / RTX 4090:

| Run | Training seed | Victory target | Updates / decisions | Inner / outer limit |
| --- | ---: | ---: | --- | --- |
| `seed0-control7` | 0 | 7 | 800 / 19,660,800 | 600 s / 720 s |
| `seed0-target10` | 0 | 10 | 800 / 19,660,800 | 600 s / 720 s |
| `seed1-target10` | 1 | 10 | 800 / 19,660,800 | 600 s / 720 s |
| `seed1-control7` | 1 | 7 | 800 / 19,660,800 | 600 s / 720 s |

Four GPU runs maximum; **40 minutes total inner allowance**. Require exactly 800
train rows, all scheduled checkpoints/evaluations, finite weights/Adam/metrics and
unchanged parent/source. A normal return with less work still fails. No retries,
extensions, best-checkpoint selection, altered seeds or cherry-picked timepoints.
Retain the final checkpoint at 800 even if intermediate scores look better.

The existing independent process-group watchdog owns each deadline. Verify the
shared nonblocking GPU lease, actual device, progress, and device processes; never
stop another project. Memory abort at sampled **8 GiB process RSS** remains active.
Before any handoff, install a bounded heartbeat for these exact run IDs/deadlines;
no heartbeat means remain actively supervising. A failure halts the sequence.
Do not start a GPU arm after **2026-09-06 21:30 UTC**. All training/evaluation
supervision ends by **22:30 UTC**; unfinished work is reported, not extended.

Here an "update" means one outer PPO iteration. Equal budgets fix **19,660,800
surfaced policy decisions**, not episodes, completed transitions or Adam steps:
target-dependent episode endings and minibatch rounding can change those counts.
Retain batch sizes, episode/cap totals and Adam-counter deltas versus the parent.
These are expected outcome differences, not snapshot-style equality failures.
At 800 iterations require 50 distinct saved checkpoints and 102 eval rows.

## Export and evaluation

After successful training, use upstream `training/export_net.py` unchanged,
retaining checkpoint/export hashes and validating all exported parameter floats.
The native CTNN loader must accept its embedded numerical probe. Budget **300 s**
for all four exports/parity checks; no architecture/observation changes.

For each training seed, use existing `scripts/evaluate-bots.py` with target-ten
checkpoint as candidate and target-seven checkpoint as baseline, same frozen
Release executable/resources and native adapter:

- Four players, native randomized boards, target 10, three frozen Greedy opponents.
- **32 held-out board seeds, 961101–961132**, all four evaluated chairs: 128 games
  per arm, 256 per training-seed comparison, **512 total native games**.
- **600-second watchdog per comparison**, run seed-0 pair then seed-1 pair.
- Preserve the wrapper's `purpose: smoke` designation: this is an exploratory
  development screen, not difficulty calibration or confirmation. Keep its route
  audit, failure/cap reporting and seed-cluster 95% intervals.
- Do not pool the two training seeds as hundreds of independent trained models.
  Report each paired gain, chair results, completion, fallbacks and intervals.

Retention check: reuse `reproduce-catan-policy.collect_outcomes` in the upstream
seven-point setting on **961201 and 961202**, 192 requested games each/model
(retain overshoot), all four checkpoints. **300-second total watchdog**, CPU
permitted; record outcomes and caps. Compare target-ten versus matched target-seven
checkpoint within each training seed, with a predeclared **five-point loss margin**.
Periodic training evaluations use their respective targets and cannot substitute
for this common-rule retention check.
For each training seed, pool wins and actual returned-game counts across the two
retention seeds, including batch overshoot and caps. Count caps as nonwins and report them
separately; any cap prevents advancement. Loss is `control wins/control games −
treatment wins/treatment games`; **greater than 0.05** fails the retention gate.
Also report each evaluation seed separately. Do not pair rows by arrival ordinal,
reuse the historical 126-win artifact gate or label these runs with default seed
777. This point-estimate screen does not establish statistical equivalence;
native seed-cluster intervals and later confirmation carry the stronger claims.

## Decision rules

- **Advance to fresh confirmation** only if both native paired gains are at least
  **+10 percentage points**, all games complete, numerical/legality/fallback checks
  pass, and neither seed's seven-point retention loss exceeds five points.
- **Regression rejection:** noncompletion or new unexpected fallbacks fail
  independently of wins. A broken export, incorrect flags or insufficient work
  makes the experiment **invalid**, not evidence against target adaptation.
- **Do not advance** below practical thresholds. Mixed native signs/training-seed
  outcomes are **inconclusive**; record the limitation without extending budget.
- No default promotion or TestFlight upload from this screen. Confirmation needs
  fresh boards, additional frozen opponents, supported configurations, comparison
  against Balanced and device regressions. Beating weak r2 alone is insufficient.

This budget tests bounded adaptation from r2, not target-ten training from scratch,
all possible training durations, or whether this network can ever play expertly.

## Execution evidence

- Isolated tests: 63 run, one Linux-only skip; source review found no remaining
  seed, target, budget or default-propagation issues.
- Both CPU preflights exited 0, completed exactly one update / 24,576 decisions,
  and saved finite model/Adam states with seed 1 and the intended targets 7/10.
  Their model/Adam digests differ, proving the target changes actual training.
- [Retained CPU receipts, commands and frozen tool hashes](evidence/victory-target-20260906/).
  The one-shot sequence is retained there; it is an experiment artifact, not a
  second general-purpose training harness. Each arm uses the existing watchdog.
- The active thread heartbeat `verify-empires-evaluation-ci` supervises this
  experiment and PR #43 CI together (the app permits only one active heartbeat
  per thread). The old GPU-profile heartbeat remains paused.
