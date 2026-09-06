---
name: sim-harness
description: Headless seeded self-play, training-data export, and bounded training-run supervision for Empires research. Use for multi-game measurements, deterministic reproduction, policy training launches, or checking active training. Prove reproducibility across separate processes, never twice inside one.
---

# Sim harness

## First rule of training: timebound and watched

Every training run, including upstream reproductions and smoke runs, needs both
an enforced time limit and a verified watcher. A detached process is persistence,
not monitoring; the trainer's own minute counter is not an independent deadline.

1. Before launch record the run ID, host, exact command/source, stage budgets,
   absolute end deadline, checkpoint/log paths, and scoped stop mechanism.
   Bound training, export, and evaluation; an outer watchdog must terminate the
   owned process group, with finite graceful shutdown then forced termination.
2. For work continuing beyond the turn, create or update a product heartbeat
   before handoff and verify it is active. Record its ID, cadence, and terminal
   stop condition. Short foreground smoke runs may use actively awaited tool
   calls with timeouts. If no watcher can run, remain supervising or report the
   blocker; a promise to check later is not a watcher.
3. Check immediately after launch: the expected process, deadline enforcement,
   advancing updates, fresh logs, finite metrics, and actual requested device.
   Watch process health AND progress; allow for bounded periodic evaluation.
   A disconnected host means unknown status, and a vanished process without
   completion evidence means failure.
4. Use quiet periodic checks (normally ten minutes for hour-scale jobs). Report
   meaningful phase changes, stalled progress, failure, or completion. Keep
   monitoring bounded too: report and disable it at terminal state or after one
   final bounded check at the absolute deadline. Never silently restart or
   extend training, or stop unrelated GPU processes.
5. At completion check exit/status, checkpoint lineage and finite weights,
   native-game completion, and retained evaluation outcomes. Preserve receipts
   and report what was proved; elapsed time and a checkpoint alone do not prove
   reproduced strength. Pause the watcher after reporting the terminal result.

For the upstream two-stage reconstruction, inspect
`scripts/run-catan-reconstruction.py`; its external launcher supplies the outer
deadline. Current run locations and receipts belong in
`docs/AI_summaries/2026-09-05-public-catan-reproduction-log.md`, not in this skill.

**A seed that reproduces twice inside one process is not reproducible.** Swift
seeds `Set` and `Dictionary` iteration order **once per process**, so two runs
in one process share that hash seed, agree with each other, and disagree with
tomorrow's run. This repo has already paid for that mistake: commit `761822f`
"fixed" the RNG and was verified by playing a seed twice in one test process. It
passed. The property was still false, and four more ordering leaks were found
afterwards - a `Double` summed over a filtered `Set` (floating-point addition is
not associative, so a tie broke differently), a best-vertex pick by strict `>`
over a `Set`, a dictionary flat-map, and a `.first` on a `Set`.

Everything this harness is for - A/B-ing a heuristic, bisecting a failing game,
replaying a recorded trajectory - rests on that property, so the harness
measures it the only way that works: two separate processes, byte-compared.

## What has actually run

| Path | Status |
|---|---|
| **The executable exists, builds and plays games** | **RUN AND PROVEN 2026-08-29.** `Packages/CatanAI/Sources/sim/main.swift`, wired as `.executableTarget(name: "sim", ...)` in `Packages/CatanAI/Package.swift`. Builds clean under `-Xswiftc -warnings-as-errors` and under `swiftlint --strict`. |
| **Cross-process reproducibility** | **PROVEN 2026-08-29.** Seeds 1000-1009, Release, run in two separate processes: both files `sha256 2dcfd1fb48dceb8adf381bcb8ffe571a5b6d53544656911a0543eca2dcd50c8c`, `cmp` silent. |
| **Agreement with the existing determinism guard** | **RE-PROVEN 2026-09-05.** A fresh Release harness reproduced all five values currently pinned in `Packages/CatanAI/Tests/CatanAITests/SeededGameFingerprintTests.swift`. That test file is the single source of truth; values are deliberately not duplicated here because intentional trade, road, and development-card changes have moved them repeatedly. The harness uses the same seat lineup, bot-RNG derivation, and canonicalization so the test remains an external check on it. |
| **Evaluation configuration matrix** | **RUN AND PROVEN 2026-09-03.** `scripts/tests/test_sim_cli.py` invokes the Release executable for every 3/4-player × 8/10/12-VP × standard/randomized-board combination. These are engine/evaluation smoke cases; four-player 12 VP is no longer a product New Game option after longer runs proved it can saturate without a winner. Every sampled CLI case reaches a winner, reports schema-5 configuration provenance, and emits arrays matching the configured table size. The default invocation remains the historical four-player, 10-VP, randomized-board trajectory. |
| **Throughput** | **MEASURED 2026-08-29** on an 18-core Apple Silicon Mac. **Release, one process: 0.45-0.56 games/sec** (four timed runs of 10 games: 22.45s, 19.48s, 19.05s, 17.96s). **Debug: 0.12 games/sec** (5 games in 41.56s) - about 4x slower, never measure on it. **Release, 10 shards in parallel: 1.76 games/sec** (100 games in 56.79s, 642% CPU). |
| **Game shape** | **MEASURED over 350 historical default-length games** across two seat lineups (seeds 1000-1009, 2000-2099, 3000-3039, 5000-5199): every game finished with a winner, 212-824 moves, mean 462. Later 12-point calibration runs did hit the 3,000-move cap; never generalize the default-game range to a new policy or target. |
| **Sharding into ONE shared output file** | **RAN ONCE, 100/100 lines intact and parseable, but NOT proven safe.** See the trap below - use one file per shard. |
| **Running on Linux / in CI** | **NEVER RUN.** CI builds the whole package, so the sim target will start compiling on `ubuntu-latest` the moment this is pushed. It imports only `CatanEngine`, `CatanAI` and `Foundation`, so it should be fine, and "should be" is not "was". |
| **Strength evaluation using this output** | **RUN 2026-09-03, AND THE CANDIDATES FAILED.** The harness supplied a locked two-arm anchor calibration and four Easy development screens. Turning JSONL into a claim remains the separate **bot-strength** method; raw wins alone are not evidence. |

## Hard preconditions

- **Build Release, always.** `swift build -c release`. Debug is ~4x slower and
  there is no reason to pay it: this target has no debugging story of its own.
- **Nothing else holding the package lock.** SwiftPM takes an exclusive lock on
  `Packages/CatanAI/.build`; a concurrent `swift test` (or `scripts/gate.sh`)
  makes the harness print `Another instance of SwiftPM is already running ...`
  and wait. That is correct behaviour, not a hang.
- **A settled working tree if the numbers are going anywhere.** Fingerprints
  are a function of the bot code. Games played against a half-edited heuristic
  are not comparable with anything.

## The ladder

```bash
set -euo pipefail
REPO="$(git rev-parse --show-toplevel)"

# 1) BUILD RELEASE AND RESOLVE THE BINARY, rather than using `swift run` for
#    the measured runs. `swift run` is fine and its build chatter goes to
#    stderr (verified - stdout stays pure JSONL), but it re-checks the build
#    on every invocation, which is noise inside a timing loop and a lock
#    contention point when sharding. Ask SwiftPM where the binary is instead
#    of hardcoding `.build/arm64-apple-macosx/release` - that path encodes the
#    host triple and is wrong on the next machine.
swift build --package-path "$REPO/Packages/CatanAI" -c release
SIM="$(swift build --package-path "$REPO/Packages/CatanAI" -c release --show-bin-path)/sim"

# 2) PLAY. Match seeds are CONSECUTIVE from --seed: `--seed 1000 --games 10` plays
#    1000..1009. Record all three configuration flags in any command meant to
#    support a comparison; relying on defaults makes a pasted invocation less
#    self-describing even though defaults remain stable.
#    --jsonl is the machine form; without it you get a text table for
#    eyeballing. The --seats values are the seats in order, and the four-seat
#    default (balanced,aggressive,cautious,balanced) is the SAME lineup
#    SeededGameFingerprintTests uses, which is what makes step 4 possible.
"$SIM" --games 10 --seed 1000 --players 4 --victory-points 10 \
  --board randomized --jsonl > /tmp/runA.jsonl

# 3) PROVE REPRODUCIBILITY THE ONLY WAY THAT COUNTS: a SECOND PROCESS.
#    Not a loop inside one process - Swift's per-process hash seed makes that
#    check pass while the property is false. Fresh process, same seeds, byte
#    compare. `cmp` is silent on success and exits non-zero on the first
#    differing byte, so `set -e` turns a divergence into a stopped script
#    rather than a line of output nobody reads.
#    Note this compares STDOUT only. Timing goes to stderr precisely so that
#    the data stream stays comparable; never print a duration or a path to
#    stdout from this harness.
"$SIM" --games 10 --seed 1000 --players 4 --victory-points 10 \
  --board randomized --jsonl > /tmp/runB.jsonl
cmp /tmp/runA.jsonl /tmp/runB.jsonl
echo "reproducible across processes: $(shasum -a 256 /tmp/runA.jsonl | cut -d' ' -f1)"

# 4) CROSS-CHECK AGAINST THE COMMITTED GUARD. The five seeds below are pinned
#    in SeededGameFingerprintTests.swift. If the harness agrees with them, the
#    harness is playing the same games the test suite guards, and any future
#    divergence is a real bot change rather than a harness bug. Do this after
#    any edit to the harness, and after any edit to the bots.
for seed in 1 42 7 1234 99; do "$SIM" --seed "$seed" --games 1 --jsonl 2>/dev/null; done
# Compare the five outputs with `expectedFingerprints` in
# SeededGameFingerprintTests.swift. That dictionary is authoritative; do not
# cache another copy in this skill.

# 5) SCALE BY SHARDING THE SEED RANGE ACROSS PROCESSES. One process does ~0.5
#    games/sec, so 1,000 games is ~35 minutes of wall clock and 10,000 is most
#    of a working day. Sharding is embarrassingly parallel because a game
#    depends on nothing but its seed - which is a property of the design, not
#    a lucky accident, and it is worth preserving.
#    ONE FILE PER SHARD. Ten processes appending to one redirect happened to
#    come out intact once here; that is not a guarantee, and a torn line in a
#    measurement file is a silent, unattributable error. Concatenate after.
mkdir -p /tmp/shards
seq 2000 10 2090 | xargs -P 10 -I{} sh -c "\"$SIM\" --games 10 --seed {} --jsonl > /tmp/shards/{}.jsonl 2>/dev/null"
cat /tmp/shards/*.jsonl > /tmp/all.jsonl
wc -l < /tmp/all.jsonl
```

## The output format

One object per game, fields in a fixed order, hand-rendered rather than encoded
so the order cannot drift:

```json
{"schemaVersion":5,"buildID":"working-tree","playerCount":4,"victoryPointTarget":10,"boardMode":"randomized","policies":["heuristic-balanced","heuristic-aggressive","heuristic-cautious","heuristic-balanced"],"seed":1000,"moves":406,"winner":3,"vp":[6,5,9,10],"fingerprint":"c047cdd24f0caec1","behavior":[...]}
```

- **`playerCount`**, **`victoryPointTarget`**, and **`boardMode`** identify the
  experimental arm, not decorative copy. Their accepted values are 3 or 4;
  8, 10 or 12; and `standard` or `randomized`. The analyzer includes them in
  pairing keys so equal numeric seeds from different arms cannot be
  mistaken for the same generated game.
- **`winner`** is a seat index, or `null` if the 3000-move cap tripped. A
  `null` is a failed-completion result, not a draw. Historical default-length
  games finished in 212-824 moves; 12-point stress runs have exceeded the cap.
- **`vp`** is final victory points **per seat in seat order**, from
  `GameState.victoryPoints(for:)`, so it includes the +2 longest-road and +2
  largest-army bonuses. The winner's entry can exceed 10 (seen: 11).
- **`fingerprint`** is FNV-1a over the canonical rendering of every move
  played. It has exactly one job: change when the move sequence changes. Two
  runs with the same fingerprint played the same game; a changed fingerprint
  after a bot edit tells you the edit reached play, and an unchanged one tells
  you it did not.

**stdout is data, stderr is diagnostics.** The `sim: N games in Xs (Y
games/sec)` line goes to stderr. That split is what makes step 3's byte
comparison possible at all, so do not "helpfully" move timing onto stdout.

## Training-data mode

`--training-jsonl` writes a separate record for every policy decision while
ordinary game JSONL stays on stdout. Never point it at an existing file: the
harness refuses to overwrite so two incompatible runs cannot be mixed.

```bash
"$SIM" --games 20 --seed 53000 --jsonl \
  --build-id policy-baseline-v1 \
  --training-information reveal-all \
  --training-jsonl /tmp/examples.jsonl > /tmp/games.jsonl
python3 scripts/validate-training-data.py \
  --build-id policy-baseline-v1 --information-policy revealAll /tmp/examples.jsonl
python3 scripts/train-policy-baseline.py \
  --build-id policy-baseline-v1 \
  --information-policy revealAll \
  --model-output /tmp/checkpoint.json /tmp/examples.jsonl
```

Each schema-2 example carries the dataset schema, state/action layout versions,
build and policy provenance, seed and decision index, player count, victory
target, board mode, observer/table identity, 5,182 features, sparse legal-action
indices, chosen global action, and final seat-relative outcome. The validator
checks the serialized contract, including configuration/layout provenance,
feature bounds, per-seed-and-configuration contiguous decision indices,
winner-derived outcomes, and that the chosen action belongs to the serialized
legal mask. The
Swift constructor remains the authority for recomputing the mask from live game
state; compact feature vectors intentionally cannot reconstruct that state.

Both table sizes use the same 9,335-wide four-chair action head. In a
three-player example the nonexistent fourth victim slots are simply illegal.
Shrinking the head would shift every later segment, making one action index mean
different moves depending on table size and silently corrupting mixed training.

The baseline is deliberately modest and dependency-free: phase-conditioned
action counts behind the legal mask, plus a linear value estimator. It proves
the pipeline and supplies lower-bound metrics; it is not a shipping bot or a
strength result. Splitting is by whole game seed, never by decision, because
adjacent states from one trajectory in train and test would be leakage.

## Trap: the RNG overload that can never be reproducible

`Bot` has two `decide` methods and they are not interchangeable:

```swift
// Bot.swift:29 - CONVENIENCE. Builds a fresh SystemRandomNumberGenerator per
// call. Correct for the live app, fatal for a harness.
public func decide(for state: GameState, player: PlayerID) -> GameMove

// Bot.swift:37 - the one to use. Seeded RandomSource threaded through the
// whole game, so build near-ties (BuildPlanner.chooseBuild's tieMargin) break
// the same way every run.
public func decide(for state: GameState, player: PlayerID, rng: inout some RandomNumberGenerator) -> GameMove
```

The failure mode is quiet: the harness runs, prints plausible numbers, and the
fingerprints differ every time for reasons that have nothing to do with the
bots. If fingerprints move on a run where you changed nothing, check this first.

The bot RNG is a **second, separate** generator from the engine's. `GameSetup.
newGame(board:seed:)` seeds the one inside `GameState` (dice, robber steals,
dev card shuffle); the harness seeds its own `RandomSource(seed: seed * 31 + 7)`
for bot tie-breaks. Both must be seeded or the game is only half reproducible -
and `seed * 31 + 7` is copied verbatim from `SeededGameFingerprintTests` so the
two agree.

**Note a doc bug in that test while you are there.** Its comment reads "a
measurement harness must use this overload" immediately after explaining that
the no-RNG overload can never be reproducible. It means the `rng:` one, which
is what the code on the next line actually calls - but read as written it says
the opposite of the rule.

## Trap: ordering leaks into the OUTPUT, not just into play

The engine can be perfectly deterministic and the harness still print different
bytes each run, because rendering a `[Resource: Int]` by iterating the
dictionary orders the keys per process. Every dictionary payload therefore goes
through `Rendering.table`, which walks **`Resource.allCases`** and looks each
key up, rather than walking the dictionary. Three move cases carry one:
`.discard`, `.bankTrade`, `.proposeTrade`.

The same rule applies to `Set`: `.discarding(pending:)` carries a `Set<PlayerID>`
and the harness `.sorted()`s it before taking `.first`. Taking `.first` of the
set directly picks a per-process-arbitrary seat - which is precisely the bug
that was found in `SetupPhase.unroadedSettlement`.

If you add a field to the JSON record, this is the question to ask about it
before anything else.

## Trap: a new file under `Sources/` is linted more strictly than a test

`force_try` and `force_cast` are disabled by
`Packages/CatanAI/Tests/.swiftlint.yml` and
`Packages/CatanEngine/Tests/.swiftlint.yml` - **nested configs that apply to
the test directories only**. `SeededGameFingerprintTests` therefore uses
`try! RulesEngine.apply(...)` legitimately, and copying that line into
`Sources/sim/main.swift` failed `swiftlint --strict` immediately:

```
Packages/CatanAI/Sources/sim/main.swift:243:9: error: Force Try Violation (force_try)
```

The harness uses an explicit `do/catch` that `fatalError`s with the seed and
the move instead. That is not merely lint compliance - it is better fail-fast:
a `try!` dies with no context, while a measurement tool that swallowed the
throw would emit a record that looks like a finished game and is not one, which
is the worst possible outcome for a measurement tool.

## Trap: adding a PRODUCT, rather than a target, would show up as project drift

`Packages/CatanAI/Package.swift` declares `sim` as an `.executableTarget` and
**deliberately does not add a `products:` entry**. `project.yml` links the
package by package name (`dependencies: - package: CatanAI`), so a second
product changes what XcodeGen resolves and lands as a diff in
`Settlers.xcodeproj/project.pbxproj` - which `scripts/gate.sh`'s first gate
reports as drift. SwiftPM synthesizes an implicit executable product for an
executable target, which is all `swift run sim` needs.

**The coverage floors are unaffected, and that is by construction, not luck.**
`scripts/coverage.sh` measures the `.xctest` bundle binary with
`-ignore-filename-regex='(Tests/|\.build/)'`. `sim` is a separate binary that
the test target does not depend on, so not one of its lines is counted either
way. If you ever make the harness a library that tests import, that stops being
true and the floors move.

## Honest limits (do not overpromise)

- **It plays three or four bots and no human.** There is no human-policy seat,
  no interactive path, and nothing here says anything about how the app behaves
  under a real player.
- **Three personalities exist**: `balanced`, `aggressive`, `cautious`. Bot
  *weights* (`BotWeights`, the full numeric policy, explicitly built "to be
  swept or trained") are **not exposed on the command line**. Comparing two
  weight sets today means editing the source, which means the two arms are not
  the same binary - see **bot-strength** before drawing a conclusion from that.
- **It is slow.** ~0.5 games/sec per process. 1,000 games is ~35 minutes
  single-process, ~10 minutes across 10 shards. Any plan that says "run 100,000
  games" needs a profiler first, not more processes.
- **The fingerprint proves the sequence, not its quality.** Identical
  fingerprints mean identical play. They say nothing about whether the play was
  good, and a changed fingerprint is not evidence of improvement.
- **The record is opportunity-aware but not a decision trace.** Schema 5 has
  27 per-seat event/opportunity counters for builds, development cards, robber
  targeting, and trade proposals/responses. It still lacks per-turn resource
  curves, time-to-milestone data, trade score/rejection reasons, road-plan
  intent, and runner-up action scores. Those require versioned new fields, not
  inference from aggregate counters.
- **The executable is integration-tested, but fingerprints still matter.**
  `scripts/tests/test_sim_cli.py` builds and invokes Release `sim`, checks strict
  CLI failures, runs all twelve engine/evaluation configurations, and validates a real training
  export. If you change move rendering or policy flow, still run step 4 against
  the independently pinned fingerprints and compare separate processes.
- **Never run on Linux.** See the table.

## Related

- **`Packages/CatanAI/Tests/CatanAITests/SeededGameFingerprintTests.swift`** -
  the committed determinism guard, and the source of the five constants in
  step 4. It runs in every `swift test`; the harness does not.
- **`.claude/skills/bot-strength/SKILL.md`** - what to do with the games once
  you have them, and why a win rate against your own current bot is not
  strength.
- **`.claude/skills/verify-settlers/SKILL.md`** - the other half of the loop.
  This skill never opens a simulator; that one never plays a game.
- **`CLAUDE.md`, "Determinism invariants"** - the four rules any engine change
  must preserve for this harness to keep meaning anything.
- **`Packages/CatanEngine/Sources/CatanEngine/Models/RandomSource.swift`** -
  the SplitMix64 generator and, in its doc comment, the reason it lives inside
  `GameState` rather than being threaded through `apply`.
