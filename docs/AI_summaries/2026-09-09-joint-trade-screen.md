# Joint trade accounting — first native game screen

September 9, 2026. **Decision: promising, inconclusive; do not ship.**

The candidate tied the existing Balanced bot in one comparison and had higher
win rates in three. Every 95% interval still includes zero improvement. Keep the
fixed candidate for an independent larger comparison, not as a proven fix.
No training or automatic parameter tuning occurred. The app remains unchanged.

## What changed

The current scorer values incoming and outgoing resources against the original
hand. In a reviewed trade, it credited receiving wool toward buying a development
card while payment removed the sole ore needed for that same purchase.

The experiment scores the entire before/after exchange. Each existing build
target contributes `2 * weight / (1 + missing cards)`; subtract before from after
per target. It reuses native costs and weights. The old acceptance threshold,
including opponent-threat and suspicion adjustments, stays unchanged.

This changes incentives as well as correcting that accounting mechanism: it
values early progress less. It also ignores production scarcity, bank conversion,
multiple purchases and whether a build location or development card is available.
The six new blind/revealed reviews exposed a scarce-grain trade this candidate
rejects that might be useful. Do not tune it merely to match a reviewer's opinion.

Only automatic, single-offer trade replies use this formula. Every other choice
delegates to Balanced, including its RNG use. Mixed main-turn trade choices,
proposing trades and bank trading are unchanged. `joint-balanced` is an explicit
simulator option, not an app setting. Diagnostics never substitute the old bot
for the candidate or claim its scores explain candidate decisions.

## Locked comparison and actual results

Candidate and unchanged Balanced each occupied every chair against the listed
opponents. Three-player rows have two opponent chairs; four-player rows have
three. Each row uses sixteen seed families and complete chair rotations, with
separate seed ranges for each row. Randomized boards; ten victory points.

| Table / other chairs | Candidate wins | Existing Balanced wins | Difference, percentage points | 95% interval for difference |
| --- | ---: | ---: | ---: | ---: |
| 3 players / Balanced | 16/48 (33.3%) | 16/48 (33.3%) | 0.0 | −10.4 to +10.4 |
| 3 players / Aggressive | 15/48 (31.3%) | 9/48 (18.8%) | +12.5 | 0.0 to +25.0 |
| 4 players / Balanced | 18/64 (28.1%) | 16/64 (25.0%) | +3.1 | −6.3 to +12.5 |
| 4 players / Aggressive | 17/64 (26.6%) | 12/64 (18.8%) | +7.8 | −3.1 to +18.8 |

Balanced and Aggressive are the existing rule-based styles, not weaker training
bots. Against Balanced opponents, the candidate actually plays at their table.
Against Aggressive opponents, candidate and baseline play separate matched arms;
that is not a direct candidate-versus-Balanced game.

**448/448 comparison games finished**, plus 28 qualification games forming
14 old/new-binary parity pairs. All parity pairs matched complete result objects
apart from the build label. Candidate trajectories changed in **220/224** paired
games, so the new route is not an unused setting. This does not identify which
changed trade caused a win.

The existing analyzer bootstraps entire seed families, retaining their chair
rotations, with 20,000 resamples. These are approximate pointwise intervals from
only sixteen families per row, not simultaneous guarantees. Do not pool table
sizes or count adjacent decisions as independent samples. Equal starting seeds
do not guarantee equal later dice when branches consume RNG differently.

Predeclared practical target: five percentage points. A wholly negative 95%
interval in any row would reject adoption; otherwise this screen remains
inconclusive/no-ship. No rule, threshold, seed or stopping decision changed after
observing wins. The entire fixed schedule ran; no failed seeds were replaced.

## Runtime, safeguards and verification

- Screen ran **17:28:08–17:34:01 UTC: 5m 53s**, including qualification and
  analysis, within a separate 600-second watchdog. Two simulation workers,
  120-second shard limits; watchdog terminal state `complete`, exit 0.
- Native arithmetic controls match the offline formula, including sole/surplus
  prerequisites, quantities, strict threshold boundaries, unchanged non-trade
  choices/RNG and legal response masks. An engine failure aborts the experiment;
  it is never silently counted as a strategic rejection.
- Release build with warnings as errors, full CatanAI suite **143 tests** and
  complete Python tooling suite **114 tests** passed, including seven real CLI
  integration tests and five runner tests. The earlier
  offline suite also checks 50,000 reversible swaps and 6,075 addition-order
  cases; these are arithmetic checks, not games or strength evidence.
- All **239 archived artifact hashes** were independently checked after
  completion. Python formatting afterward preserved the runner's AST; the exact
  executing pre-format source remains frozen with the results.
- No app/UI gate, phone gameplay test, TestFlight upload or policy-default change
  occurred in this research cycle. Last verified delivery remains Build 1.0 (7),
  September 8, running Balanced for new games. Live distribution was not rechecked.

## Evidence and repeatability

[Frozen results, manifest, binaries, source and receipts](</Users/alex/Library/Application Support/EmpiresResearch/experiments/heuristic-corpus-20260909/joint-game-01/>)
include one `analysis.json` per row, raw chair shards and exact command files.
[Watchdog receipt](</Users/alex/Library/Application Support/EmpiresResearch/experiments/heuristic-corpus-20260909/joint-game-01-watch.watchdog.json>)
records the real clock and terminal status. The baseline executable is pinned to
`f0a362eccbbd515fb65c4fd9f52f4a4fdb14cf876b1855113c6625e984ca905b`,
with its `ec058ab` source archive. The manifest pins the candidate and analyzer.

The current entry point is `scripts/screen_trade_policy.py`. Launch it beneath
the archived watchdog, supplying `--binary`, `--baseline-binary` and a new
`--output`. It freezes inputs, verifies baseline parity, plays the fixed schedule
and runs the existing analyzer; it refuses overwrites and does not retry failures.
The default candidate ID is `experimental-joint-balanced-v1`. This runner is a
locked experiment, not yet a general tuning service or a new agent skill.

## Next decision, not a running job

Keep this candidate unchanged for a larger independent confirmation block,
proposed at 64 new families per row: 1,792 games in four separately bounded
ten-minute runs. Lock those seeds and promotion/non-regression criteria before
launch; do not recycle the 64 families used here as a holdout. Expand the existing
runner's configuration rather than creating another evaluator. No follow-up run
or watcher is active now.

Even confirmation would not prove every rejected human trade is sensible. Native
human-offer scenarios and phone latency remain promotion requirements. Better
road planning, automated tuning and personality stay separate later work.
See the [program plan](AI-PROGRAM.md) and the
[corpus/review findings](2026-09-08-heuristic-corpus-trial.md).
