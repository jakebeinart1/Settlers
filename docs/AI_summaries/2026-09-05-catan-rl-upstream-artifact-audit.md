# `catan-rl` upstream artifact audit

**Audit date:** 2026-09-05
**Purpose:** revise the Empires baseline decision after finding public upstream
branches newer than the released `main` commit.

## Decision

Two upstream artifacts now have different, useful roles:

1. **Historical reproduction oracle:** pin
   [`021279c`](https://github.com/Eli6th/catan-rl/tree/021279c56834b6203480e5292e1de7246e47bd68).
   Its first-to-7 PPO gate reproduced exactly at 126/192 (65.625%), and its
   AlphaBot command reproduced at about 82% in the repository's evaluator.
   Keep it unchanged when checking that our environment can reproduce the
   original published behavior.
2. **Later pretrained candidate, not yet selected:** pin
   [`7046c6b`](https://github.com/Eli6th/catan-rl/tree/7046c6bc942f7ebeb2638a46d3f8b5f728643202).
   It publishes a later V5A-derived, first-to-10, realistic-information model
   and a corrected topology-v2 observation contract. It runs, but our two
   evaluation setups differ in engine and sampling. Those scores do not
   establish that this policy is stronger than the original.

This revises the earlier conclusion that the released `main` model was the
only reusable artifact. It remains our historical reproduction priority;
the later model is a candidate for a future controlled comparison.

Do **not** enable AlphaBot search around the newer model yet. Its own
[`deployment-champion.json`](https://github.com/Eli6th/catan-rl/blob/7046c6bc942f7ebeb2638a46d3f8b5f728643202/models/deployment-champion.json)
sets `search_enabled` and `search_qualified` to false after the topology
migration. The old 82% search result and the new model are not one qualified
artifact.

## What changed upstream

| Revision | What is actually public | Evidence verdict |
| --- | --- | --- |
| `021279c` (`main`) | Original step-46,497,792 PPO checkpoint, CTNN export, Rust engine, trainer, and AlphaBot | Fully runnable artifact; historical training lineage remains incomplete |
| `e081ff6` (`rl-outcome-head`) | Better seat routing, outcome head, first-to-10 balanced evaluation, realistic visibility, and promotion code | Valuable harness design, but its model files are byte-identical to `main`; the reported promoted checkpoint and raw runs are absent |
| `7046c6b` (`catan-showcase-studio`) | New step-77,400,886 checkpoint, matching CTNN, deployment manifest, snapshots, expanded training/evaluation code, and aggregate reports | Runnable newer artifact; exact training lineage and many manifest-bound raw files are still absent |

The intermediate `e081ff6` branch must not be described as shipping its
reported `robust-v3` policy. Its two model Git blobs are identical to
`021279c`, and its new outcome head is randomly initialized when that legacy
checkpoint is loaded. The referenced step-52,148,508 candidate lives only in a
gitignored `training/runs/` path.

The showcase branch is different. It commits new model bytes:

- PyTorch checkpoint SHA-256:
  `2e505d08bccbbdcb4f30307a2a7060d8db78ae51e2fe18c697876b4e7f10532b`
- CTNN SHA-256:
  `9f78cdfc5d66aa553c51e48ba9c5c8bb71e3c4a07b2dc5c6dbbabb3bd74593f7`
- Contract: observation v2, topology v2, codec v1, 1,350 inputs, 299
  actions, two 512-unit hidden layers, outcome head, first to 10, realistic
  visibility, and no VP shaping.
- Lineage: the pre-migration source was V5A phase 4 at step 77,400,886 with
  SHA-256 `4533f39b7dd102ec8530fa107f82cb575d584da657bca1510bb316a36745ec0e`;
  the committed model deterministically remaps affected harbor-input columns
  into the corrected topology-v2 contract.

The V5A aggregate report says the pre-migration policy won 63.4% against
Heuristic-v1 and 60.2% against Heuristic-v2 under realistic information. Those
raw report files are not committed, so they remain author claims. Our results
below evaluate the committed **post-migration** model directly and do not rely
on those missing files.

## Independent local results

All runs used the upstream code without patches in temporary worktrees. The
machine was an 18-core Apple M5 Pro running macOS 26.5.1, with Rust/Cargo
1.98.1, Python 3.12.14, PyTorch 2.14.0, NumPy 2.5.2, and maturin 1.15.0.

### Historical fixed-chair checks

The old checkpoint's exact documented policy gate reproduced:

| Rules | Information | Opponent table | Result |
| --- | --- | --- | ---: |
| First to 7 | Perfect | Policy in chair 0 vs 3× Heuristic-v1, seed 777 | **126/192 = 65.625%** |
| First to 10 | Perfect | Same fixed chair and seed | 98/192 = 51.04% |
| First to 10 | Realistic | Same fixed chair and seed | 86/192 = 44.79% |

This explains why the old 65.6% cannot be carried into Empires as a
first-to-10, hidden-information expectation.

### First-to-10 calibration runs (not a controlled comparison)

Each row below is 768 games: 192 in each physical chair, with zero turn caps.
Both used the declared seed base `14,100,010,000`, but **not the same schedule**.
The old weights ran in `e081ff6`, whose evaluator reuses the base across chairs
and selects games by lane completion order. The new weights ran in `7046c6b`,
whose evaluator uses disjoint chair seeds and fixed per-lane quotas. Engine
topology also changed. Per-game rows were not retained for these initial runs.
Parenthesized Wilson intervals are descriptive binomial summaries, not valid
paired evidence of an improvement (especially with repeated old chair seeds).

| Information and opponents | `021279c` weights in `e081ff6` evaluator | `7046c6b` weights and evaluator |
| --- | ---: | ---: |
| Perfect, 3× Random | 766/768 = 99.74% (99.06–99.93) | 761/768 = 99.09% (98.13–99.56) |
| Perfect, 3× Heuristic-v1 | 421/768 = 54.82% (51.28–58.30) | **444/768 = 57.81%** (54.29–61.26) |
| Perfect, 3× Heuristic-v2 | 373/768 = 48.57% (45.05–52.10) | **410/768 = 53.39%** (49.85–56.89) |
| Realistic, 3× Random | 765/768 = 99.61% (98.86–99.87) | 765/768 = 99.61% (98.86–99.87) |
| Realistic, 3× Heuristic-v1 | 387/768 = 50.39% (46.86–53.92) | **423/768 = 55.08%** (51.54–58.56) |
| Realistic, 3× Heuristic-v2 | 358/768 = 46.61% (43.11–50.15) | **406/768 = 52.86%** (49.33–56.37) |

The numerical differences cannot select a winner: policy lineage, engine/input
semantics, and episode selection all changed. The earlier version of this memo
called them strong selection evidence and incorrectly said the schedules were
the same. That conclusion is withdrawn. A future comparison must hold those
factors fixed, save outcomes, and use a predeclared held-out evaluation plan.

### Runtime and test checks

- `e081ff6`: locked full Rust suite passed; 21 focused Python tests passed;
  three dashboard JavaScript tests passed; the 200-episode binding smoke
  completed 744,704 policy decisions and passed.
- `7046c6b`: locked full Rust suite passed; its PyO3 binding built with the
  committed lock; the six 768-game scenarios above all completed; its CTNN
  loaded in Rust and completed an AlphaBot game.
- The showcase branch's selected Python suite produced 32 passes and three
  failures from a clean checkout. All three failures require files under
  gitignored `training/runs/` paths that are named by the deployment manifest
  but not committed. That is a packaging/reproducibility defect, not a model
  inference failure.

## What is and is not reproduced

**Reproduced:**

- the old fixed-chair 65.625% PPO gate;
- the old approximately 82% AlphaBot behavior in its own evaluator;
- both public checkpoint/CTNN pairs loading and completing games;
- the new model's first-to-10 calibration scores against Random,
  Heuristic-v1, and Heuristic-v2 under both visibility modes;
- the newer observation/action contracts, seat routing, and benchmark code.

**Not reproduced:**

- byte-for-byte historical training for either model;
- the missing `robust-v3` candidate claimed by `e081ff6`;
- the complete 178-phase V5A training lineage or its 2.2-million-game raw
  evaluation ledger;
- the pre-migration V5A aggregate percentages from raw rows;
- a search-strength result for the topology-v2 model;
- any cross-engine claim that the model already plays Empires correctly.

## Consequence for Empires

Finish source-faithful fresh training in the original upstream environment
first. Preserve three distinct roles for later transfer experiments:

1. **Empires heuristic anchor:** the current Swift bot, measured in the Empires
   engine.
2. **Historical compatibility oracle:** `021279c`, used to prove that an
   adapter reproduces known 1,350/299 decisions and the exact old gate.
3. **Later external candidate:** `7046c6b` plus checkpoint hash `2e505d…`,
   greedy-only until search is independently qualified. Not a selected champion.

Do not replace Empires' 5,182-input and 9,335-action versioned contracts. Add a
separate sequential model adapter that exposes the external 1,350/299 contract,
retains partial Road Building/discard/robber choices internally, and emits a
compound Swift `GameMove` only after the choice is complete. The Swift rules
engine remains authoritative.

After upstream training reproduction, the adapter must pass deterministic slot
mapping, legal-mask, and full-game conformance tests. Only then evaluate the
transferred policies inside Empires. Global Conquest improvements and
personality/dialogue work remain later stages, exactly as requested.

## Provenance and reuse boundary

The upstream repository is MIT-licensed. If code or weights are imported,
retain its copyright/license notice and record the exact source commit and
artifact hashes in-repo. Do not copy upstream Catan branding or art. The model
selection decision does not itself authorize product claims such as
"strongest Catan AI". This audit establishes runnable artifacts and evidence
limits, not a strongest-policy ranking.
