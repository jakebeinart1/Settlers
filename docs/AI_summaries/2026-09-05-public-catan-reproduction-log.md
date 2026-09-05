# Public Catan AI reproduction log

**Date:** 2026-09-05

**Purpose:** distinguish runnable evidence from repository claims before Empires
selects an external agent, checkpoint, or algorithm.

## Verdict

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

## Reproduction gates still open

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
