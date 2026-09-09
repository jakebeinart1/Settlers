# Joint trade accounting — final decision and historical screen

September 9, 2026. **Final decision: retain Balanced; reject this candidate for
adoption and close the bounded Stage 4 iteration.** No further tuning is queued.

The first screen looked promising. Fresh confirmation against current main did
not meet the predeclared promotion rule, and four-player point estimates were
worse. This is a decision against shipping the change, not proof that every
atomic inventory evaluator is bad. The candidate remains an explicitly selected
simulator comparator for reproducibility, never an app default. No training or
automatic parameter tuning occurred.

## Final fresh-main confirmation

Both arms include Jake's hidden-VP fix from `4737471`. Candidate and Balanced
each occupied every evaluated chair, against two or three opponents of the named
style. Randomized boards, 10 VP, **64 fresh families per row**; no old-screen
games pooled in. Balanced opponents share the candidate's actual table; the
Aggressive rows compare separate matched arms against Aggressive opponents.

| Table / other chairs | Candidate wins | Balanced wins | Difference, pp | 95% interval, pp |
| --- | ---: | ---: | ---: | ---: |
| 3 / Balanced | 69/192 (35.9%) | 64/192 (33.3%) | +2.6 | −4.2 to +9.4 |
| 3 / Aggressive | 70/192 (36.5%) | 62/192 (32.3%) | +4.2 | −4.2 to +12.0 |
| 4 / Balanced | 53/256 (20.7%) | 64/256 (25.0%) | −4.3 | −8.6 to 0.0 |
| 4 / Aggressive | 56/256 (21.9%) | 60/256 (23.4%) | −1.6 | −7.8 to +4.7 |

**1,792/1,792 comparisons and 28/28 qualification games finished**, with no
replacement seeds, failed games or deadline extensions. All four independent
600-second watchdogs ended `complete`, exit 0; runtimes were 155.00s / 175.18s /
536.01s / 576.25s in table order. All **908** receipt-indexed artifact hashes
were independently recomputed. The same 20,000-resample seed-family bootstrap
and pointwise-interval limitations below apply. These results do not establish
equivalence or expert human-level strength; an Elo league was not run here.

The five-point improvement requirement failed, the four-player Balanced point
estimate was negative, and both four-player lower bounds crossed −5 points.
Therefore **do not integrate the candidate into human trade resolution or the
phone app**. The original accounting mechanism remains a documented research
finding; this replacement did not establish a safe improvement.

Evidence: the four `confirmation-p{3,4}-{balanced,aggressive}/` directories in
the [September 9 archive](</Users/alex/Library/Application Support/EmpiresResearch/experiments/heuristic-corpus-20260909/>).
Each contains exact invocation, raw chunks, complete chair shards, frozen native
source, runner source, binary locks, analysis and receipt. Sibling `*-watch`
receipts retain terminal deadlines. `confirmation-protocol.md` preserves the
declaration written before launch; its archive copy was made while runs were
active, before any result analysis was read. The candidate binary SHA-256 is
`b5aad82468ab5a0829236ab8d25406caba05f5f998f0b73e549142a436667d42`;
the current-main baseline is
`5ff37c59a5d44c78a2e08479268a3d350e6183fccd6ad96dc04062b9edd149b9`.

The [closeout handoff](2026-09-09-heuristic-handoff.md) records final verification,
merge/archive disposition and known limits. Personality is the next separate
stage. Road planning, human-offer evaluation, automatic tuning and search remain
future work, not additional rounds required before this closeout.

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

## Historical first screen — pre-hidden-VP-fix baseline

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

## Final closeout comparison — declared before launch

The first screen above predates Jake's hidden-victory-point fix. The final
comparison therefore rebuilds **both arms from main `4737471`**, adding only
the fixed experimental trade policy to the candidate. It does not pool these
results with the historical screen or change the candidate's formula.

Four randomized-board, 10-VP strata use 64 fresh seed families each, every chair:
3/Balanced **990000–990063**, 3/Aggressive **990100–990163**,
4/Balanced **990200–990263**, 4/Aggressive **990300–990363**.
That is 1,792 comparison games, plus unchanged-policy binary qualification.
Each stratum has its own 600-second independent watchdog; simulation chunks
remain limited to 16 games and 120 seconds. No failed seed is replaced.

Promotion requires at least a five-percentage-point gain against Balanced at
one table size with its 95% difference interval above zero, nonnegative point
estimates against Balanced at both sizes, and all four lower interval bounds
above −5 points. These are screening criteria, not simultaneous statistical
guarantees. Native human-offer compatibility and phone verification would still
be required before changing the app default. If these criteria are not met,
**retain current Balanced, archive the candidate, and close this Stage 4
iteration without another tuning round**. A timeout or invalid comparison is
an incomplete experiment, never evidence of equivalence or a candidate loss.

The confirmation is now complete; no Stage 4 simulation or training watcher
remains active. See the [program plan](AI-PROGRAM.md) and
[corpus/review findings](2026-09-08-heuristic-corpus-trial.md).
