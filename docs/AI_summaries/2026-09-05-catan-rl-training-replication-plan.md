# Eli6th `catan-rl` from-scratch training replication plan

**Audit date:** 2026-09-05
**External source:** [`Eli6th/catan-rl` at `021279c56834b6203480e5292e1de7246e47bd68`][eli-commit]
**Empires source:** current `Settlers` checkout at `e361ad589bd5f4249d5f3dc2f34aa59c54c99f29`
**Scope:** determine the exact reproduction path; do not import, modify, or vendor the external project.

## Executive finding

The pinned repository can reproduce the **software shape** of the published agent: its Rust rules engine, 1,350-float observation v1, 299-action codec v1, masked PPO trainer, checkpoint format, CTNN exporter, and AlphaBot search code are public. The repository also contains a published PyTorch checkpoint and its exported CTNN network. [The repository describes this stack directly.][eli-readme-architecture]

It cannot currently reproduce the **historical training run exactly from scratch**. Four load-bearing inputs are absent:

1. The published checkpoint says it resumed from an uncommitted `step_0043376640.pt`; that parent checkpoint is not present in the pinned tree. [The only committed training artifacts are the final checkpoint/export and ten evaluation replays.][eli-models-tree]
2. The published checkpoint records engine commit `eb8da245d2420876aae9ea66f60fc62cb1f3e787`, but that object is not in the public history reachable from the pinned commit. The pinned source is therefore not proven to be the exact source that generated the weights. [The checkpoint is the primary artifact carrying that metadata.][eli-published-pt]
3. The initial fresh `runB` config, metrics, logs, and promotion record are absent even though the experiment ledger points to gitignored `training/runs/<run>/` directories and a `logs/` directory. [The ledger names those missing locations][eli-experiments-header], while [`.gitignore` excludes run artifacts][eli-gitignore] and [the committed `training/configs` directory contains only `.gitkeep`][eli-config-tree].
4. Rust dependencies are locked, but the Rust compiler, Python interpreter, PyTorch, NumPy, and maturin versions used for training are not. The README says Python 3.10+, the binding metadata says Python 3.9+, and the Python dependency files contain ranges rather than a lock; PyTorch is not listed in either dependency manifest. [README prerequisites][eli-readme-prereqs] · [Python requirements][eli-requirements] · [binding build metadata][eli-pyproject]

Therefore there are two different outcomes:

- **Historical exact reproduction:** presently **BLOCKED**. It means rebuilding the same source/toolchain, producing the same training trajectory or weights, and replaying the author's exact evaluation protocol.
- **Source-faithful behavioral replication:** feasible after explicitly freezing our own toolchain and declaring assumptions for the missing initial run. It can test whether fresh training reaches the reported strength, but it must never be described as the exact historical run.

This distinction is the first pass/fail gate, not a footnote.

## Executed calibration record

The source and released artifact were exercised after this plan was written.
Everything ran in `/private/tmp/empires-catan-rl-baseline-20260905`; no external
source or model was copied into Empires, and no system Rust/Python installation
or shell profile was changed.

The source-compatible environment was macOS 26.5.1 on an 18-core Apple M5 Pro,
Rust/Cargo 1.98.1, Python 3.12.14, PyTorch 2.14.0 (CPU/Accelerate), NumPy 2.5.2,
and maturin 1.15.0. These versions describe this execution, not the unknown
historical environment.

1. Source commit `021279c…` and both published artifact hashes matched Phase A.
2. `cargo test --release --locked` passed all 112 Rust tests.
3. The binding's committed nested `rust/catan-py/Cargo.lock` is stale:
   `maturin develop --release --locked` failed because Cargo needed to add the
   already-declared `rand` dependency to `catan-env`. The documented unlocked
   command made that one-line dependency update and built successfully. This is
   a source-packaging defect and another reason the historical environment is
   not exactly frozen.
4. `training/smoke_env.py` passed 200 episodes and 744,704 policy decisions,
   including the 1,350-input observation and 299-action contracts, seeded
   determinism, replay harvesting, first-to-7 construction, and both visibility
   modes.
5. The published PyTorch checkpoint exported successfully. All model weights,
   biases, the 1,350-float test vector, and the value check were byte-identical
   to the published CTNN. Only three low-order bytes in the last three check
   logits differed under PyTorch 2.14.0: `-6.44093323/-5.91172600/-7.11271572`
   became `-6.44093275/-5.91172504/-7.11271524`. The resulting SHA-256 was
   `f9d57b4023f262df31b528f4cf55db782db66f823d19417c04fb9c36914723a9`,
   not the published `21f3…`; both CTNNs passed the Rust loader and produced the
   same 467-step seed-0 game and winner. Artifact semantics calibrated, but the
   stronger byte-identical R4 condition did not pass.
6. The author's published 100-game command produced 83 AlphaBot wins, 4/7/6
   wins for the three Heuristic-v1 chairs, and 50,756 total steps. A separate
   192-game seed-777 run produced 157 AlphaBot wins (81.8%) and 15/9/11
   heuristic wins. Both were first-to-10 because the executable has no target
   argument; neither is the undocumented historical first-to-7 experiment.
7. A one-minute continuation smoke used the checkpoint-recorded `runB2` flags,
   resumed the published final model, completed 1,671,168 new policy steps,
   wrote metrics/checkpoints, exported a new CTNN, and played that CTNN through
   the Rust AlphaBot. This proves the current train-to-inference path. It is not
   R6: it starts from the final public model instead of the missing 43,376,640-
   step parent and intentionally runs for one minute rather than sixty.

The observed result is therefore precise: **the released AlphaBot artifact and
current training pipeline are runnable; the public repository still cannot
recreate the historical training lineage or its stated first-to-7 headline.**

## 1. What the published system actually is

`Rust` here means the **Rust programming language**. The external project implements its own Catan rules engine and batched simulator in Rust, exposes that simulator to Python through PyO3, trains a neural network in Python/PyTorch with PPO, exports the trained tensors to a custom CTNN binary, and loads that binary back into Rust for AlphaBot inference. [Architecture diagram and commands][eli-readme-architecture]

The final playing agent is two layers:

1. **Reactive PPO network:** a two-hidden-layer ReLU MLP receives 1,350 floats and produces 299 masked policy logits plus one value estimate. The hidden width is configurable; the shipped model uses 512 units in each hidden layer. [Network definition][eli-ppo-network] · [published checkpoint][eli-published-pt]
2. **AlphaBot planner:** at a decision, the network ranks legal non-trade actions; AlphaBot keeps the top `root_k`, runs `samples` random continuations for each, and selects the candidate with the best mean result. At a nonterminal horizon it evaluates the leaf with the PPO value head. [AlphaBot implementation][eli-alpha]

This implementation is described as “AlphaZero-lite,” but it is not the full AlphaZero training loop: the pinned code does not build a persistent MCTS tree, use PUCT, train on search visit distributions, or feed AlphaBot games back into PPO. The experiment ledger lists search-as-teacher and value-head retraining as future work. [Current AlphaBot loop][eli-alpha] · [ledger next steps][eli-experiments-next]

## 2. Exact observation and action contracts

### 2.1 Eli observation v1: 1,350 floats

The external observation is seat-relative: player blocks are ordered as the acting player, then the next three chairs. Categorical values are one-hot, scalar counts are normalized, and the same shape supports perfect information or realistic visibility. In realistic mode only opponents' exact resource/dev-card blocks are zeroed; public card counts remain. [Observation contract][eli-observation]

| Block | Width | Exact contents | Source |
|---|---:|---|---|
| Tiles | `19 × 8 = 152` | Six-way resource/desert one-hot, production probability, robber flag | [layout][eli-observation-layout] |
| Vertices | `54 × 14 = 756` | Settlement/city ownership by four relative seats plus six-way port one-hot | [layout][eli-observation-layout] |
| Edges | `72 × 4 = 288` | Road owner by relative seat | [layout][eli-observation-layout] |
| Players | `4 × 17 = 68` | Public card/dev counts, knights, public VP, pieces, road length, awards, ports, turn-owner flag | [slots][eli-observation-player] |
| Acting seat private | `15` | Five resources, five dev-card types, five dev-card types bought this turn | [encoder][eli-observation-private] |
| Opponents private | `3 × 10 = 30` | Five resources and five dev-card types per opponent; zero in realistic mode | [encoder][eli-observation-private] |
| Bank | `5` | Remaining stock by resource | [encoder][eli-observation-context] |
| Context | `20` | Game/turn phase, roll, turn, target, roads to place, trades left, discard debt | [encoder][eli-observation-context] |
| One open trade | `16` | Presence, relative proposer, give resource/amount, requested resource | [encoder][eli-observation-trade] |
| **Total** | **1,350** | `OBS_VERSION = 1` | [constants][eli-observation-layout] |

### 2.2 Eli action codec v1: 299 logits

The external action IDs encode what and where, not the acting seat. Initial and ordinary settlement placement share 54 IDs; initial, paid, and Road Building road placement share 72 IDs. The legal-action mask selects the IDs valid in the current phase. [Codec rationale and layout][eli-codec]

| Action family | IDs | Important compression |
|---|---:|---|
| Settlement / city / road locations | `54 + 54 + 72` | Setup and ordinary placement reuse IDs where their phases cannot overlap |
| Robber move / victim | `19 + 4` | Tile selection and stealing are separate decisions |
| Discard | `5` | One resource is discarded per decision until the quota is met |
| Monopoly / Year of Plenty | `5 + 15` | Year of Plenty uses unordered resource pairs |
| Bank / player trade proposal | `20 + 40` | Bank rate is inferred from state; player offer is 1–2 of one type for one of another |
| Trade response / confirmation | `2 + 4` | One open offer, accept/reject, then partner-or-cancel |
| Roll / buy / Knight / Road Building / end turn | `5` | Road Building is activated once, then uses ordinary road-location IDs |
| **Total** | **299** | `CODEC_VERSION = 1` |

Every count above is defined by the pinned codec's canonical table and encode/decode implementation. [Codec source][eli-codec]

### 2.3 Why Empires currently has 5,182 inputs and 9,335 actions

The two projects model the same broad board game, but their tensor contracts are not interchangeable:

1. Both use the standard `19` tiles, `54` vertices, `72` edges, and four seat slots. Empires state layout v3 fixes those dimensions and traps if another board shape is supplied. [Empires state constants][empires-state-layout]
2. Empires allocates **3,881 global features**, of which `256 × 15 = 3,840` describe up to 256 pending trade offers. Eli allocates 16 features for one open offer. This trade-protocol difference explains almost the entire width increase. [Empires global layout][empires-state-layout] · [Eli one-offer layout][eli-observation-layout]
3. Empires then uses `4 × 31` per-seat, `19 × 7` per-tile, `54 × 14` per-vertex, and `72 × 4` per-edge features, producing **5,182** total under state layout v3. [Empires block table][empires-state-blocks]
4. Eli's tiles keep the robber flag inside each eight-slot tile row; Empires uses seven-slot tile rows and a separate 19-way robber block. [Eli tile encoder][eli-observation-tiles] · [Empires block definitions][empires-state-layout]
5. Empires action layout v2 has **9,335** outputs. Two compound decisions consume 8,114 of them: 5,112 ordered two-road combinations and 3,002 complete discard multisets. [Empires action-space size][empires-action-summary]
6. Eli makes those decisions sequentially: Road Building activates once and then reuses a 72-edge choice twice, while discarding uses one of five resource IDs per card. [Eli action codec][eli-codec] · [Eli discard behavior][eli-game-actions]
7. Empires combines robber tile and victim into `19 × 5 = 95` slots for each of Knight and ordinary robber movement. Eli first chooses one of 19 tiles and then one of four steal/skip IDs. [Empires segment construction][empires-action-construction] · [Eli action codec][eli-codec]
8. Empires enumerates 60 bank-trade actions because the 2:1, 3:1, and 4:1 rates receive separate IDs; Eli has 20 resource-pair IDs and derives the applicable rate from the player's ports. [Empires bank encoding][empires-action-compounds] · [Eli codec][eli-codec]
9. Empires enumerates 120 one-resource-per-side player offers: give 1–3 and request 1–2. Eli enumerates 40: give 1–2 and request exactly one. [Empires proposal encoding][empires-action-compounds] · [Empires enumeration limits][empires-trade-enumeration] · [Eli proposal actions][eli-trade-enumeration]
10. Empires reserves 512 response logits for accept/reject across 256 offer positions; Eli has two response logits because only one offer can be open. [Empires action construction][empires-action-construction] · [Eli trade state machine][eli-trade-flow]

Consequently, the Eli checkpoint cannot be resized, padded, or directly loaded into Empires. Its first-layer columns and policy-head rows have meanings fixed by observation v1 and codec v1; Empires persists different state/action versions for the same reason. [Eli checkpoint checks][eli-ppo-checkpoint] · [Empires training-example contract][empires-training-example]

The baseline must first be reproduced in Eli's unchanged `1,350 → 512 → 512 → 299` contract. Translation or retraining against Empires is a later experiment, not part of baseline replication.

## 3. Toolchain and dependency freeze audit

| Component | What is frozen in the pinned source | What is missing for historical exactness | Verdict |
|---|---|---|---|
| External source | Git commit `021279c56834b6203480e5292e1de7246e47bd68` | The checkpoint names unavailable engine commit `eb8da245…` | **Blocked** for exact training source; [commit][eli-commit] · [checkpoint][eli-published-pt] |
| Rust crates | Root and PyO3 binding `Cargo.lock` files pin crate versions/checksums | No `rust-toolchain` file or compiler version | **Partially frozen**; [workspace lock][eli-cargo-lock] · [binding lock][eli-py-cargo-lock] · [Rust tree][eli-rust-tree] |
| Rust code generation | Release uses LTO, one codegen unit, and `target-cpu=native` | Exact Apple CPU model, OS, `rustc`, and Cargo versions | **Not historically frozen**; [release profile][eli-workspace] · [native CPU flag][eli-cargo-config] |
| Python | README says Python 3.10+ | Binding metadata says 3.9+; no exact interpreter/build | **Not frozen**; [README][eli-readme-prereqs] · [pyproject][eli-pyproject] |
| PyTorch | Trainer imports `torch`; checkpoint identifies CPU use | PyTorch version/build is absent from dependency files and checkpoint config | **Not frozen**; [trainer imports/config][eli-ppo-top] · [requirements][eli-requirements] · [checkpoint][eli-published-pt] |
| NumPy | Trainer imports NumPy; requirements specify `numpy>=1.24.0` | No exact version or lock | **Not frozen**; [trainer][eli-ppo-top] · [requirements][eli-requirements] |
| maturin / PyO3 | `maturin>=1.5,<2`, PyO3 `0.22`, NumPy Rust crate `0.22`; binding Cargo lock pins resolved Rust crates | Exact maturin release and Python wheel ABI are absent | **Partially frozen**; [pyproject][eli-pyproject] · [binding manifest][eli-py-cargo] · [binding lock][eli-py-cargo-lock] |
| Training hardware | Ledger says Apple Silicon CPU at about 16–20k policy steps/s; trainer forces four PyTorch CPU threads | Exact Mac model, core count, memory, OS, thermal state | **Not frozen**; [ledger][eli-experiments-header] · [thread setting][eli-ppo-main] |

The 4090 should not be used for the historical baseline gate: the published lineage records `device=cpu` and the author describes CPU training. GPU work belongs to a later throughput-equivalence experiment after CPU behavioral parity. [Checkpoint][eli-published-pt] · [ledger][eli-experiments-header]

## 4. Training algorithm and exact known configuration

### 4.1 PPO mechanics

The trainer uses one shared policy for every policy-controlled chair, seat-specific trajectory chains, undiscounted episodic return (`gamma=1.0`), GAE λ `0.95`, PPO clip `0.2`, value coefficient `0.5`, gradient norm cap `0.5`, Adam with ε `1e-5`, action masking, and categorical sampling during training. [Trainer constants/network][eli-ppo-top] · [rollout and update][eli-ppo-update]

Bot-controlled seats are advanced inside the Rust environment and never surfaced to the policy. A policy-controlled seat produces a training decision only when that seat has at least two legal choices because forced one-action states are auto-resolved by default. [Environment seat semantics][eli-env-seats] · [forced-action handling][eli-env-advance]

Terminal rewards are `+1` for the winner and `-1` for every other chair. `vp_delta` optionally adds reward for changes in victory points; `0` makes the objective terminal-only. Episodes truncate at 1,000 turns with no terminal winner bonus. [Reward and environment defaults][eli-env-config] · [reward accumulation][eli-env-reward]

### 4.2 Published training lineage

The experiment ledger says the shipped 512-wide lineage was:

- `runB`: fresh two-layer 512-wide network, VP shaping annealed from `0.05` to `0`, entropy `0.02`, 50 minutes, 43.4M reported policy steps, 54.2% on the fixed-seed gate. [Ledger run table][eli-experiments-runs]
- `runB2`: resume `runB` for 60 minutes, adding 46.5M reported policy steps and reaching 65.6% on the fixed-seed gate. [Ledger run table][eli-experiments-runs]
- The ledger says `catan-512.ctnn` was exported from `runB2 best.pt`. [AlphaBot ledger][eli-experiments-alpha]

The shipped `.pt` checkpoint recovers the exact **second-stage** config below. These values were decoded from the committed primary artifact; its `global_step` is `46,497,792`, and its resume path names parent step `43,376,640`. [Published checkpoint][eli-published-pt]

| `runB2` field | Value in checkpoint |
|---|---|
| name | `runB2-512ext` |
| minutes | `60.0` |
| num_envs | `256` |
| rollout | `96` |
| victory_target | `7` |
| vp_delta | `0.0` |
| visibility | `perfect` |
| learning rate | `0.00025` |
| epochs | `4` |
| minibatch | `4096` |
| hidden | `512` |
| device | `cpu` |
| seed | `0` |
| eval_every | `16` updates |
| metrics | `/tmp/catan-metrics.jsonl` |
| resume | `…/20260611-0326-runB-512cap/checkpoints/step_0043376640.pt` |
| entropy_coef | `0.02` |
| vp_delta_final | `None` |
| train_seats | `policy,heuristic,policy,heuristic_v2` |
| codec / observation | codec v1, 299 actions; observation v1, 1,350 floats |
| recorded engine commit | `eb8da245d2420876aae9ea66f60fc62cb1f3e787` |

The second-stage opponent mixture therefore has the shared learned policy in chairs 0 and 2, frozen Heuristic-v1 in chair 1, and frozen evolved Heuristic-v2 in chair 3. [Checkpoint config][eli-published-pt] · [seat parser][eli-py-bindings] · [heuristic-v2 definition][eli-players]

The initial fresh `runB` opponent mixture, rollout length, evaluation interval, seed, and other default/override choices are **not recoverable** from the ledger. The final checkpoint contains only `runB2`'s config, not its parent's config. [Checkpoint save payload][eli-ppo-checkpoint] · [ledger run summary][eli-experiments-runs]

### 4.3 Seed behavior and why bitwise reproduction is impossible today

- `--seed` defaults to `0`; the shipped `runB2` config records `0`. The trainer seeds PyTorch and the Rust vector environment from it. [Arguments and initialization][eli-ppo-main] · [checkpoint][eli-published-pt]
- Each vector lane and episode receives a deterministic SplitMix64-derived seed, and bot RNG streams are deterministically derived from each episode seed. [Vector seed stream][eli-env-vector] · [bot seed derivation][eli-env-seeds]
- When VP shaping is annealed, the trainer recreates the environment for each of three phases with seeds `seed + phase`. [Annealing code][eli-ppo-anneal]
- PPO minibatches are shuffled with `np.random.shuffle`, but the trainer never calls `np.random.seed` or creates a seeded NumPy generator. [Seed initialization][eli-ppo-main] · [unseeded shuffle][eli-ppo-update]
- A checkpoint saves model, optimizer, step, config, layout IDs, and engine commit, but not PyTorch, NumPy, or environment RNG states. Loading a checkpoint restores model and optimizer only; it then starts `global_step` again at zero. [Save/load code][eli-ppo-checkpoint] · [counter initialization][eli-ppo-main]
- This contradicts the README's stated checkpoint contract, which says `rng_states` should be bundled. Code and the committed checkpoint are the operative evidence. [Documented contract][eli-training-readme-checkpoint] · [actual save code][eli-ppo-checkpoint]

Even with the missing parent checkpoint, the public trainer cannot reproduce a continuation bit-for-bit: NumPy minibatch order is unseeded and RNG state is not restored. A successful public reproduction must therefore be judged behaviorally unless the author supplies both the original environment and missing RNG/run artifacts.

## 5. Evaluation contracts

### 5.1 Reactive PPO evaluation

During training, every `eval_every` updates the trainer evaluates the greedy network in chair 0 for 96 games against three copies of one scripted opponent. The seed is `10,000 + update`; it separately tests Random and Heuristic-v1. [In-run evaluation][eli-ppo-evaluation]

After the wall-clock deadline, the trainer saves once and evaluates 192 games at seed `999` against each of those two opponent types. [Final evaluation][eli-ppo-final]

The fixed gate used in the experiment ledger is different: greedy policy in chair 0, first to 7, perfect information by default, 192 games, base seed `777`, versus three frozen Heuristic-v1 bots. `elo.py promote` evaluates `latest.pt`, records up to 60 replays, and promotes it when there is no incumbent or it beats the incumbent by more than 0.02. [Ledger protocol][eli-experiments-header] · [promotion implementation][eli-elo-promote]

The training README says this promotion gate uses 400 games, while the executable's default is 192. For replication, pass `--games 192` explicitly because 192 is both the executable default and the experiment-ledger protocol. [README discrepancy][eli-training-readme-promotion] · [CLI default][eli-elo-cli]

### 5.2 AlphaBot evaluation

The public headline command is:

```bash
cd rust
cargo run -p catan-sim --release -- \
  --games 100 \
  --players A,H,H,H \
  --net ../models/catan-512.ctnn \
  --alpha-config 8,96,300
```

This means AlphaBot is fixed in chair 0; chairs 1–3 are Heuristic-v1; `root_k=8`; `samples=96` per root candidate; and `depth=300` turns before a nonterminal value-head evaluation. With no `--seed`, `catan-sim` uses base seed 0 and deterministically derives one seed per game. [README command][eli-readme-alpha-command] · [CLI parsing][eli-sim-cli] · [seed generation][eli-sim-seeds] · [AlphaBot implementation][eli-alpha]

AlphaBot removes player-trade proposals from its candidate set whenever any other legal action exists, uses perfect-information observations, and evaluates random rollout leaves with the value head unless a real winner or turn cap is reached. [AlphaBot candidate and rollout code][eli-alpha]

The command above does **not** reproduce the documented first-to-7 headline. `catan-sim` has no victory-target argument and constructs each game with `CatanGame::new`, whose default target is 10. [Simulator arguments/game creation][eli-sim-cli] · [simulator run loop][eli-sim-run] · [engine default target][eli-game-target]

The source also gives three incompatible sample descriptions for the 82% number: the README command uses 100 games and default seed 0; the ledger's general fixed gate says 192 games at seed 777; and the AlphaBot section says design iterations used 120–150 games each without naming each variant's seed/count. [README command][eli-readme-alpha-command] · [ledger gate][eli-experiments-header] · [AlphaBot experiments][eli-experiments-alpha]

Accordingly, the pinned repository supports an **as-shipped 10-VP smoke evaluation**, but not an exact rerun of the reported first-to-7 AlphaBot result. The historical AlphaBot strength gate remains blocked until its exact evaluator commit/command, seed set, and game count are supplied.

## 6. Reproduction procedure

### Phase A — immutable source and artifact oracle

These commands identify the source and published artifacts; they do not count as from-scratch training:

```bash
git clone https://github.com/Eli6th/catan-rl.git catan-rl
cd catan-rl
git checkout --detach 021279c56834b6203480e5292e1de7246e47bd68
test "$(git rev-parse HEAD)" = "021279c56834b6203480e5292e1de7246e47bd68"

shasum -a 256 models/catan-512-best.pt models/catan-512.ctnn
```

Audited SHA-256 values for the pinned blobs are:

```text
c4258f235c673efe6968b0aa4de66a1411f01012fa14fe71f548dfff681525a3  models/catan-512-best.pt
21f3b380786a53998172896caac44191dea3d44efd11d3bf8c92150d8b18c8a5  models/catan-512.ctnn
```

The hashes above are auditor-computed identities of the linked [published checkpoint][eli-published-pt] and [published CTNN file][eli-published-ctnn], not author-reported performance evidence.

### Phase B — toolchain manifest before installation

Historical exactness must stop here until the author supplies the missing lock. A source-compatible exploratory environment may be created, but its manifest must record at least:

```text
OS build and architecture
CPU model and core count
rustc -Vv
cargo -V
python --version
python -m pip --version
python -m pip freeze
PyTorch version and build configuration
NumPy version
maturin version
repository commit and dirty status
both Cargo.lock SHA-256 values
```

The source-compatible, **not historically frozen**, dependency envelope is Python 3.10+ per the README, `maturin>=1.5,<2`, NumPy, PyTorch, and the two committed Cargo locks. [README prerequisites][eli-readme-prereqs] · [binding build requirements][eli-pyproject] · [trainer imports][eli-ppo-top]

### Phase C — build and contract verification

Use the source's own build path and lockfiles:

```bash
cd rust
cargo test --release --locked
cd catan-py
maturin develop --release
cd ../..
python training/smoke_env.py
```

The smoke test must prove observation v1/1,350 floats, codec v1/299 actions, legal-mask shape, finite observations/rewards, deterministic seeded smoke fingerprints, replay harvesting, first-to-7 construction, and both visibility modes. [Source quickstart][eli-readme-quickstart] · [binding smoke test][eli-smoke]

### Phase D — published-artifact calibration

Before spending time on training, verify that the selected Python/Rust toolchain can load and re-export the published checkpoint:

```bash
python training/export_net.py \
  models/catan-512-best.pt \
  /tmp/catan-512-reexport.ctnn

shasum -a 256 /tmp/catan-512-reexport.ctnn models/catan-512.ctnn

cd rust
cargo run -p catan-sim --release --locked -- \
  --games 1 --players A,H,H,H \
  --net /tmp/catan-512-reexport.ctnn \
  --alpha-config 8,96,300
```

The exporter writes CTNN v1 with dimensions, tensors, and a deterministic self-check vector; the Rust loader rejects a wrong CTNN version, observation width, action count, or self-check result. [Exporter][eli-export] · [Rust loader][eli-net-loader]

### Phase E — recover the missing fresh `runB` stage

There is no honest exact command for this phase in the public snapshot. The maximum source-supported template is:

```bash
python training/ppo.py \
  --name runB-512cap \
  --minutes 50 \
  --victory-target 7 \
  --vp-delta 0.05 \
  --vp-delta-final 0 \
  --hidden 512 \
  --device cpu \
  --entropy-coef 0.02 \
  <MISSING_RUN_B_FLAGS>
```

The shown fields come from the experiment ledger and the parent path embedded in the final checkpoint. The missing flags include, at minimum, the exact opponent seats, rollout length, number of environments, evaluation interval, seed, and whether trainer defaults were used for learning rate, epochs, and minibatch. [Ledger][eli-experiments-runs] · [published checkpoint][eli-published-pt] · [trainer defaults][eli-ppo-args]

Do not silently substitute `runB2`'s values. That is a reasonable reconstruction hypothesis, not evidence about `runB`.

### Phase F — exact known `runB2` continuation flags

Once a valid parent checkpoint exists, the second-stage command recoverable from the published checkpoint is:

```bash
python training/ppo.py \
  --name runB2-512ext \
  --minutes 60 \
  --num-envs 256 \
  --rollout 96 \
  --victory-target 7 \
  --vp-delta 0.0 \
  --visibility perfect \
  --lr 0.00025 \
  --epochs 4 \
  --minibatch 4096 \
  --hidden 512 \
  --device cpu \
  --seed 0 \
  --eval-every 16 \
  --metrics /tmp/catan-metrics.jsonl \
  --resume <RUN_B_STEP_0043376640_PT> \
  --entropy-coef 0.02 \
  --train-seats policy,heuristic,policy,heuristic_v2
```

Those are checkpoint-recorded values. The source initializes `global_step = 0` after loading the parent, so the final checkpoint's `46,497,792` means second-stage steps, not cumulative steps; parent plus second stage is `43,376,640 + 46,497,792 = 89,874,432` policy steps. [Checkpoint][eli-published-pt] · [resume and counter code][eli-ppo-main]

Training is controlled by wall-clock minutes, not a target-step argument. A different CPU may therefore finish a different number of steps even with identical flags. [Trainer deadline][eli-ppo-main]

### Phase G — select and export the reactive checkpoint

For the fixed gate implemented at the pinned commit:

```bash
PYTHONPATH=training python training/elo.py promote \
  training/runs/<RUN_B2_DIRECTORY> \
  --games 192

python training/export_net.py \
  training/runs/<RUN_B2_DIRECTORY>/checkpoints/best.pt \
  training/runs/<RUN_B2_DIRECTORY>/checkpoints/best.ctnn
```

This evaluates `latest.pt` at seed 777 in chair 0 versus three Heuristic-v1 bots and promotes by the implementation's two-point rule. [Promotion code][eli-elo-promote]

The published selection cannot be reconstructed exactly because its `best_eval.json`, run directory, and raw 192-game result are absent; only the ledger's rounded 65.6% and the claim that the CTNN came from `runB2 best.pt` remain. [Ledger][eli-experiments-runs] · [Alpha export statement][eli-experiments-alpha]

### Phase H — AlphaBot evaluation

Run the pinned source's current smoke protocol exactly as written:

```bash
cd rust
cargo run -p catan-sim --release --locked -- \
  --games 100 \
  --players A,H,H,H \
  --seed 0 \
  --net ../training/runs/<RUN_B2_DIRECTORY>/checkpoints/best.ctnn \
  --alpha-config 8,96,300
```

This is explicitly a 10-VP smoke under the pinned executable, not the claimed first-to-7 replication. [Simulator default and game creation][eli-sim-run] · [engine target][eli-game-target]

Do not declare the 82% headline reproduced until an evaluator can set first-to-7 and the author-provided game count/seed protocol has been run. No change to that evaluator is made by this research task.

## 7. Required missing-evidence request

The minimum package needed from the author to turn historical exactness from blocked to executable is:

1. Source for engine commit `eb8da245d2420876aae9ea66f60fc62cb1f3e787`, or a signed statement that pinned commit `021279c…` is training-semantics-equivalent. [Checkpoint metadata][eli-published-pt]
2. `runB`'s frozen config plus `step_0043376640.pt`, or every flag and the exact checkpoint-selection rule needed to regenerate it. [Resume path][eli-published-pt] · [missing run layout described by the repo][eli-training-readme-layout]
3. Exact Python, PyTorch, NumPy, maturin, Rust, OS, and hardware versions. [Current unfrozen manifests][eli-requirements] · [binding metadata][eli-pyproject] · [Rust tree][eli-rust-tree]
4. `runB` and `runB2` metrics/logs, `best_eval.json`, and the raw 192-game fixed-gate outcomes. [Repository's artifact contract][eli-training-readme-layout] · [promotion outputs][eli-elo-promote]
5. The AlphaBot first-to-7 evaluator commit, exact command, base seed or seed list, exact number of games, and raw per-game outcomes behind 82.0%. [Conflicting public descriptions][eli-readme-alpha-command] · [ledger protocol][eli-experiments-header] · [Alpha experiments][eli-experiments-alpha]
6. RNG state at the `runB → runB2` boundary, or confirmation that the published run was never bitwise reproducible. [Documented RNG contract][eli-training-readme-checkpoint] · [actual checkpoint implementation][eli-ppo-checkpoint]

## 8. Explicit milestone ledger

| ID | Milestone | Pass condition | Current status |
|---|---|---|---|
| R0 | Pin source and artifact oracle | Commit is exactly `021279c…`; both published hashes match §6 Phase A | **PASS in this audit**; [commit][eli-commit] · [model blobs][eli-models-tree] |
| R1 | Identify historical source | Checkpoint's `engine_commit` is available and builds, or equivalence to the pinned source is proven | **FAIL / BLOCKED**; [checkpoint][eli-published-pt] |
| R2 | Freeze historical toolchain | Exact compiler/interpreter/library/hardware manifest is available and reproducibly installable | **FAIL / BLOCKED**; [current manifests][eli-requirements] · [pyproject][eli-pyproject] · [Rust tree][eli-rust-tree] |
| R3 | Build source contracts | `cargo test --release --locked`, binding build, and `smoke_env.py` all exit 0; smoke asserts v1/1,350 and v1/299 | **PASS WITH PACKAGING DEFECT**; 112 Rust tests and the full smoke contract passed, but the nested binding lock needed a one-line dependency refresh before maturin could build |
| R4 | Calibrate export/inference | Published `.pt` re-exports to byte-identical CTNN SHA-256 `21f3…` and Rust self-check loads it | **PARTIAL PASS**; weights and behavior match and both files load, but three final low-order check-logit bytes differ under PyTorch 2.14.0, producing SHA-256 `f9d5…` rather than `21f3…` |
| R5 | Recover fresh `runB` | Exact config and parent checkpoint provenance exist; fresh stage ends at the recorded parent step without NaN/Inf | **FAIL / BLOCKED**; [ledger][eli-experiments-runs] · [checkpoint][eli-published-pt] |
| R6 | Reproduce `runB2` continuation | Exact parent is loaded; second-stage config matches §4.2; final checkpoint records 46,497,792 second-stage steps and compatible versions | **BLOCKED by R1/R2/R5**; [checkpoint][eli-published-pt] |
| R7 | Reproduce reactive fixed gate | Greedy chair-0 policy records exactly 126 wins in 192 seed-777 first-to-7 games versus three Heuristic-v1 bots, matching rounded 65.6% | **BLOCKED**; target from [ledger][eli-experiments-runs], protocol from [promotion code][eli-elo-promote] |
| R8 | Export fresh CTNN | `export_net.py` succeeds; Rust loader passes dimensions and self-check; artifact hash and parent `.pt` hash are recorded | **BLOCKED by R6/R7**; [exporter][eli-export] · [loader][eli-net-loader] |
| R9 | Run pinned Alpha smoke | 100 seed-0 10-VP `A,H,H,H` games complete; loader errors, illegal actions, winners, and turn-capped games are all reported explicitly | **PASS**; 83/100 AlphaBot wins, 50,756 steps, no loader or rules failure; a second seed-777 run produced 157/192 (81.8%) |
| R10 | Reproduce Alpha headline | Author's exact first-to-7 evaluator, seeds, count, and raw outcomes are available; the fresh model reproduces the corresponding 82.0% result | **FAIL / BLOCKED**; [public mismatch][eli-readme-alpha-command] · [simulator construction][eli-sim-run] · [ledger][eli-experiments-alpha] |
| R11 | Begin Empires adaptation | R3–R10 results, failures, configs, hashes, and raw outcomes are archived; no historical claim remains ambiguous | **INTENTIONALLY NOT STARTED** |

`126 / 192 = 65.625%`, which rounds to the ledger's 65.6%; that is why R7 uses an exact win count rather than a floating-point tolerance. The AlphaBot ledger does not provide enough information to derive an equivalent exact numerator for 82.0%. [Reactive target][eli-experiments-runs] · [Alpha sample ambiguity][eli-experiments-alpha]

## 9. Decision boundary for Empires

No Empires state/action change should be made to make the checkpoint “fit” before this baseline is reproduced. Empires already records state layout v3, action layout v2, feature/action counts, legal actions, chosen action, seed, policy identity, player count, target, board mode, and hidden-information policy in each training example. [Empires training-example source][empires-training-example]

After R10, adaptation should be a separately versioned experiment with one of three explicit contracts:

1. Preserve Eli's 1,350/299 interface in an isolated compatibility environment and measure the unchanged agent.
2. Build a semantics-audited adapter only for states/actions that map exactly, with unsupported decisions counted rather than guessed.
3. Reproduce the architecture and training recipe against Empires-native 5,182/9,335 tensors, initializing new weights and treating the result as a new model lineage.

Only option 1 can be called the external baseline. Option 2 is a transfer experiment. Option 3 is an Empires-native retraining experiment. None permits reusing the published tensors under different slot meanings.

## Primary-source link index

[eli-commit]: https://github.com/Eli6th/catan-rl/tree/021279c56834b6203480e5292e1de7246e47bd68
[eli-readme-architecture]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/README.md#L1-L53
[eli-readme-prereqs]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/README.md#L55-L58
[eli-readme-quickstart]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/README.md#L60-L85
[eli-readme-alpha-command]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/README.md#L65-L70
[eli-models-tree]: https://github.com/Eli6th/catan-rl/tree/021279c56834b6203480e5292e1de7246e47bd68/models
[eli-published-pt]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/models/catan-512-best.pt
[eli-published-ctnn]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/models/catan-512.ctnn
[eli-gitignore]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/.gitignore#L8-L16
[eli-config-tree]: https://github.com/Eli6th/catan-rl/tree/021279c56834b6203480e5292e1de7246e47bd68/training/configs
[eli-requirements]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/requirements.txt#L1-L5
[eli-pyproject]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-py/pyproject.toml#L1-L13
[eli-workspace]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/Cargo.toml#L1-L10
[eli-cargo-config]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/.cargo/config.toml#L1-L3
[eli-cargo-lock]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/Cargo.lock
[eli-py-cargo]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-py/Cargo.toml#L1-L18
[eli-py-cargo-lock]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-py/Cargo.lock
[eli-rust-tree]: https://github.com/Eli6th/catan-rl/tree/021279c56834b6203480e5292e1de7246e47bd68/rust
[eli-ppo-top]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/ppo.py#L1-L34
[eli-ppo-args]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/ppo.py#L37-L61
[eli-ppo-network]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/ppo.py#L64-L78
[eli-ppo-checkpoint]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/ppo.py#L92-L116
[eli-ppo-main]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/ppo.py#L151-L205
[eli-ppo-anneal]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/ppo.py#L196-L222
[eli-ppo-update]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/ppo.py#L224-L347
[eli-ppo-evaluation]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/ppo.py#L118-L148
[eli-ppo-final]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/ppo.py#L349-L363
[eli-training-readme-layout]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/README.md#L19-L39
[eli-training-readme-checkpoint]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/README.md#L41-L58
[eli-training-readme-promotion]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/README.md#L60-L72
[eli-experiments-header]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/results/EXPERIMENTS.md#L1-L12
[eli-experiments-runs]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/results/EXPERIMENTS.md#L24-L35
[eli-experiments-alpha]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/results/EXPERIMENTS.md#L68-L93
[eli-experiments-next]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/results/EXPERIMENTS.md#L95-L102
[eli-observation]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/obs.rs#L1-L14
[eli-observation-layout]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/obs.rs#L16-L49
[eli-observation-player]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/obs.rs#L51-L64
[eli-observation-tiles]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/obs.rs#L80-L127
[eli-observation-private]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/obs.rs#L129-L171
[eli-observation-context]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/obs.rs#L173-L196
[eli-observation-trade]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/obs.rs#L198-L207
[eli-codec]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/codec.rs#L1-L46
[eli-game-actions]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-core/src/game.rs#L116-L141
[eli-trade-enumeration]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-core/src/game.rs#L482-L508
[eli-trade-flow]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-core/src/game.rs#L873-L955
[eli-alpha]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/alpha.rs#L1-L147
[eli-env-config]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/env.rs#L1-L85
[eli-env-seats]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/env.rs#L46-L70
[eli-env-seeds]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/env.rs#L132-L179
[eli-env-reward]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/env.rs#L210-L247
[eli-env-advance]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/env.rs#L242-L301
[eli-env-vector]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/env.rs#L328-L366
[eli-py-bindings]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-py/src/lib.rs#L19-L53
[eli-players]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-core/src/players.rs#L59-L179
[eli-elo-promote]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/elo.py#L135-L184
[eli-elo-cli]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/elo.py#L187-L202
[eli-export]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/export_net.py#L1-L61
[eli-net-loader]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/net.rs#L92-L161
[eli-sim-cli]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-sim/src/main.rs#L42-L170
[eli-sim-run]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-sim/src/main.rs#L283-L345
[eli-sim-seeds]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-sim/src/main.rs#L476-L522
[eli-game-target]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-core/src/state.rs#L9-L14
[eli-smoke]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/smoke_env.py#L1-L105

[empires-state-layout]: ../../Packages/CatanEngine/Sources/CatanEngine/StateEncoding.swift#L71-L217
[empires-state-blocks]: ../../Packages/CatanEngine/Sources/CatanEngine/StateEncoding.swift#L480-L531
[empires-action-summary]: ../../Packages/CatanEngine/Sources/CatanEngine/ActionSpace.swift#L30-L46
[empires-action-construction]: ../../Packages/CatanEngine/Sources/CatanEngine/ActionSpace.swift#L61-L155
[empires-action-compounds]: ../../Packages/CatanEngine/Sources/CatanEngine/ActionSpace.swift#L300-L395
[empires-trade-enumeration]: ../../Packages/CatanEngine/Sources/CatanEngine/RulesEngine.swift#L114-L176
[empires-training-example]: ../../Packages/CatanAI/Sources/CatanAI/TrainingExample.swift#L12-L106
