# Balanced versus the published model: baseline decision

**Question:** which existing bot deserves the next improvement effort in Empires?
This protocol is recorded before running any of its games. No training or policy
change is part of this comparison.

## Fixed comparison

- Existing Balanced versus the author's original published CTNN, SHA-256
  `21f3b380786a53998172896caac44191dea3d44efd11d3bf8c92150d8b18c8a5`.
- Same native engine/adapter, reveal-all information, four players, ten points,
  randomized boards, held-out seeds **962001–962064**, all four seat rotations.
- Two separate opponent groups: three Balanced bots, then three Greedy bots.
  Report each group independently, not a pooled claim of universal strength.
- Each group plays Balanced first, then the original model: 256 games per bot,
  512 per group, **1,024 planned games** total. All-Balanced must yield exactly
  25% for its designated rotated seat when every game completes.
- The original model uses the same native neural adapter and declared heuristic
  trade/pre-roll fallback as earlier tests. This is **not AlphaBot search**, a
  reproduction of its full upstream system, or a human-opponent evaluation.
- Reuse `scripts/evaluate-bots.py` and the two named configs in
  `config/evaluation/`. Its `purpose: smoke`/report label remains unchanged:
  this prospective screen selects a next baseline; it does not certify expert
  strength, all game configurations, or a product difficulty tier.

## Budget and stop rules

Each config has its existing independent **600-second** process-group watchdog,
including build, games and analysis. Run groups sequentially, exactly once each,
even if the first group fails; do not alter sources between them. Launch neither
after **2026-09-07 00:00 UTC**; both must be terminal by **00:10 UTC**. The current
thread supervises actively; heartbeat `verify-empires-evaluation-ci` is enabled
before launch as backup, quiet unless completion/failure requires action.

Retain raw games, route audits, config/source/artifact hashes, commands and
terminal receipts. Do not weaken the existing cap/fallback checks or retry failed
shards. A cap/timeout prevents an adoption verdict; report any unplayed remainder.
No new GPU run, checkpoint selection or evaluation extension is implicit here.

### Time-only execution amendment, before model evaluation

At 23:48 UTC the unchanged all-Balanced control had completed 144/256 games in
about 268 seconds; the original-model arm had not started. The ten-minute group
budget was underestimated from earlier mixed-opponent timings. Preserve the
original watchdog/deadline and its possible timeout as an execution failure.
Reserve **one 600-second completion job** for that group's original-model arm,
only if the control completes but the wrapper times out. It reuses the exact
frozen executable/model/config, reruns no control games, and verifies any already
completed model-game prefix byte-for-byte. Those repeated IDs are not additional
samples. Original incomplete files remain unchanged. No new boards, additional
sample size, cap waiver or policy change is permitted. This reserve is declared
before reading model outcomes; it is not a significance-driven extension.

The two primary groups remain sequential. The repair may run alongside the second
group on a separate frozen copy; it must launch before 00:00 UTC and terminate by
00:10 UTC under its independent watchdog. Use the existing runner's arm,
validation and analysis functions. Only a complete, independently reconciled set
of the originally scheduled games can support the selection rule below. A game
cap or audit failure remains a failed comparison, not a reason for repair.

## Decision made from the result

- A difference of **10 percentage points** in each opponent group is the practical
  selection threshold. Require all games complete, clean route audits, and the
  existing seed-cluster 95% difference interval exclude zero in that direction.
- If Balanced wins both groups by this rule: keep it as the app/improvement
  baseline; stop further r2 continuation/target adaptation. Only a separately
  justified experiment from the stronger published model or its omitted search
  deserves new research budget; do not assume more training improves it.
- If the original wins both: use it as the next neural research baseline;
  retain Balanced as the control. App promotion still needs supported settings,
  gameplay/latency checks and review; this screen does not authorize a default swap.
- Mixed/close outcomes: retain Balanced in the app and report a context-dependent
  or inconclusive ranking. No forced winner, pooled average or adaptive rerun.
- Before more training, record which earlier PR work to keep versus archive.
  Failed experiment findings are worth retaining, not shipping as improvements.

## Result

**Decision: retain Balanced as the current product/improvement baseline. Stop
r2 continuation and target adaptation.** Both opponent groups clear the locked
10-point selection threshold and their paired 95% intervals exclude zero.

| Opponents in the other three chairs | Balanced wins | Original-model wins | Balanced advantage, paired 95% interval |
| --- | ---: | ---: | --- |
| Balanced | 64/256 = 25.0% | 25/256 = 9.8% | +15.2 points; +10.5 to +19.1 |
| Greedy | 214/256 = 83.6% | 148/256 = 57.8% | +25.8 points; +17.6 to +34.0 |

All **1,024 scheduled evaluated-seat/game records** completed with winners,
the exact held-out seeds and all four chairs. The four all-Balanced control
files contain identical game trajectories: one winner per board means exactly
25% across labelled chairs, not four independent observations. Analysis
resamples whole boards, retaining all chairs together. Counts independently
reconciled: Balanced-opponent wins by chair `[18,19,17,10]` versus `[9,2,11,3]`;
Greedy-opponent wins `[48,52,56,58]` versus `[35,33,42,38]`.

These are **native four-player, ten-point bot games**, not human matches,
three-player evidence, a calibrated difficulty tier, or a test of the complete
upstream AlphaBot with search. The frozen generic report says “smoke” and
“development seeds”; the prospective protocol above establishes the narrower
held-out baseline-selection use. No report template or policy was changed to
upgrade the result. The original remains the stronger of the two **neural**
checkpoints in the earlier original-versus-r2 comparison, but not the best
native bot in this new comparison.

### Execution accounting

The first wrapper reached its unchanged deadline at 23:54:12 UTC and exited
124. Its receipt records `failed` plus a cleanup `PermissionError`, not success.
Its process group was independently absent at 23:56 UTC. All control games and
117 original-model games had completed without caps. The predeclared time-only
completion started at 23:56:56 under a separate 600-second watchdog and ended
successfully at **00:02:36 UTC, September 7**. Its guard accepts an exit-124
cleanup failure only after proving the old group is absent; it does not admit a
game cap or ordinary evaluation failure. All 117 repeated game rows **and their
audit prefixes matched byte-for-byte** and count once. No control was rerun in
the repair. The separate Greedy group completed at **00:00:32 UTC**, exit zero.
The heartbeat is paused; no training/evaluation job remains active.

Both completed groups share executable SHA-256
`843cb3cffbb486d876527209a1d09638f14d4e2f945efe9534334b40239d3978`
and build ID `frozen-140f9f7ac53512671687e5d5b77b209a273af7858e6525877812710a81c1573d`.
Frozen models/resources, evaluator sources, configurations, complete shards and
audits were validated. No unexpected fallbacks: original versus Balanced used
19,393 neural and 17,660 declared heuristic selections; versus Greedy used
33,741 neural and 11,413 heuristic selections. These include forced choices,
not just inference calls. Trade negotiation/proposals and unsupported pre-roll
development-card decisions are the disclosed heuristic paths.

Raw attempts, successful outputs, exact completion helper and watchdog receipts:
[evidence](evidence/balanced-original-20260906/). Frozen executables/models and
an identical durable copy of these runs are retained outside git under
`/Users/alex/Library/Application Support/EmpiresResearch/experiments/balanced-original-20260906`.
The first failure is never overwritten or recast as a successful run.

### What happens next

Keep the integration/evaluation machinery, not the weak r2 default. PR #40
remains draft; its automatic neural selection must be removed or made explicit
before promotion. No production model, app default or TestFlight build changed
in this comparison. PRs #41, #43 and #44 were closed as superseded by #42/#45;
all source, evidence and branches are retained. Four PRs remain, with no reviewer
approval yet; none was merged or self-approved.

The next research question is whether the original model's omitted look-ahead
search can justify its native runtime cost. The [focused source review](2026-09-06-search-next-experiment.md)
supports a small feasibility probe, not an immediate full port. Establish feasibility before a
substantial port, then compare against both original-without-search and Balanced.
Do not restart r2 training or embark on a broad architecture sweep. A failed
feasibility/strength check ends that line; product improvement then targets
specific road/trade failures in the stronger rule-based baseline.
