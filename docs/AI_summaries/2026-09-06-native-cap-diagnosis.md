# Native cap diagnosis — chronological evidence

**Status:** both diagnostic replays and analysis complete, 2026-09-06. No new
training authorized. Implementation/package/tooling checks are recorded below;
consult the branch's current PR/CI for subsequent publication and app verification.
The [victory-target screen](2026-09-06-victory-target-experiment.md#result-and-decision)
is closed and not adopted; this is a separate functional diagnostic, not a retry
or additional strength sample.

## Question and finish line

Both a target-ten candidate and target-seven control reached nine points without
finishing native ten-point games. Determine what was actually selected and
committed before the cap: policy planning, restricted action mapping, session
overrides/trade scheduling, or an engine state issue. Aggregate counters alone
cannot distinguish these. Do not assume the network architecture is the cause.

Add one opt-in chronological diagnostic output to the existing simulator. It
must stream existing observations, ordered legal moves, original policy choice,
effective selection/session override, committed moves/events and terminal state.
It must include deferred trade responses once, in evaluation order, without
evaluating a policy twice. Preserve default stdout, fingerprints, rules, RNG and
policy-call counts. It is not training data and must never invent winner labels
for a capped game. Reject ambiguous/existing paths; bound output to 256 MiB and
retain a clear failed/truncated prefix if the limit or I/O fails.

Ranked predictions, before replay/inspection:

1. **Policy planning:** valuable or winning moves remain legal, but the effective
   policy repeatedly chooses another action without a session override.
2. **Adapter restriction:** useful engine actions are omitted by the mapping or
   a policy decision is replaced; selection/fallback/override context locates it.
3. **Board lock caused by earlier play:** later states lack practical legal VP
   progress, requiring an earlier position to become the minimal regression case.
4. **Scheduling:** evaluation indices, committed choices or turn advancement
   expose repeated/withheld responses or action-backstop interference.

The first feedback-loop task is instrumentation: existing training export
requires a winner and cannot capture a capped trajectory. Minimize only after
the replay matches the original fingerprint and exposes a relevant saved state;
do not pretend an aggregate counter is already a minimal causal reproduction.

Acceptance: trace-on/off cross-process equivalence; ordered/complete queued
responses; forced end-turn overrides; victory and cap terminal records; explicit
file/limit failures. Use ordinary development fixtures for these implementation
tests. No app UI, weights, heuristic tuning or trainer changes.

## Fixed diagnostic replay budget

Only after the implementation is reviewed and focused tests pass:

| Case | Board / evaluated chair | Checkpoint SHA-256 | Required original fingerprint |
| --- | --- | --- | --- |
| seed0 target10 | 961131 / 1 | b5e4ecef685a7ebefe32969c07be4dbf18b5a3ba05aab5b857cf1902535f206e | 4b504877db53efef |
| seed1 control7 | 961105 / 3 | ebf6524fc0e242965e5be3381d448a97dd0a70e9fe43a8f80a52e56f6d709863 | 88e4e5bcbee25ab1 |

- One replay per case, **90-second independent watchdog each**. Four players,
  target ten, randomized board, Greedy in the other chairs, unchanged 3,000-move
  cap and native adapter. Exported models remain outside app resources.
- Freeze the diagnostic executable/resources and compare its final game outcome,
  fingerprint and policy-call count with the original failed shard. A difference
  invalidates the instrumentation; preserve it, stop and fix the implementation
  rather than treating it as policy evidence.
- No new games to improve a win rate. Trace inspection may analyze saved states
  but may not silently launch alternate policies or train another model.
- Replay launch cutoff **2026-09-06 22:00 UTC**; all replay/analysis supervision
  ends **22:30 UTC**. No retries or extensions to this two-case diagnostic budget.
  Functional fixture tests remain separate from these reserved cases.
- Record exact commands, hashes, receipts, trace completeness, observations and
  limitations here. Fix only a demonstrated implementation defect; a strategy or
  architecture change needs its own prospective experiment and evaluation budget.

## Result and decision

**Keep the diagnostic harness; no model promotion or speculative gameplay fix.**
The replay budget is closed. Both runs finished successfully inside their
90-second watchdogs, at 21:57:54 and 21:58:00 UTC. Each retained exactly 3,000
commits and matched its original game JSON (except build identity), fingerprint
and full policy audit. The diagnostic executable SHA-256 is
`30bbc8dd3cc5bd3954c0fae3f6b4fb069c337ad9eb4ff7a280094db346bb5442`.

| Case | Evaluations / trace rows | Verified failure pattern |
| --- | --- | --- |
| seed0 target10, chair 1 | 3,476 / 6,478 | All 15 roads used, longest path only 9; no settlement site. At move 667 the fourth city raises the score to 9 and exhausts city supply. All later building-site counts are zero. |
| seed1 control7, chair 3 | 3,614 / 6,616 | Expansion sites shrink from 5 after setup to zero at observation 761; only 5 roads and 2 cities owned. No legal settlement ever appears after setup. The development deck later empties; the final score is 9. |

Indices are zero-based. These are **resource-independent** placement checks
using the actual engine's `Building.canBuild*` on saved observations, not guesses
from an empty hand or new games. Both traces have zero session overrides.

### Candidate's narrower decision witness

At move **873 / evaluation 1007**, the target-ten model has nine points, enough
ore/grain/wool for a development card, and no legal building or bank-trade move.
The neural action roots are **buy development card (295)** and **end turn (298)**.
It selects and commits end turn, with no fallback or override. The actual adapter
maps buying directly; it throws rather than silently dropping unmapped roots.

After reaching nine points, buying is legal in 121 recorded decisions: the model
chooses 79 bank trades, 39 end turns and 3 purchases. In the narrower move >=1500
window, 93 opportunities divide into 61 bank trades, 29 end turns and 3 purchases.
These are correlated decisions in one game, not independent strength trials.
The saved deck's next card at 873 would win, but deck order is **not encoded** to
the model; this is not evidence that it knowingly ignored a visible guaranteed win.

This narrows the proximate failure to neural preference/resource management and
earlier expansion planning. All 238 candidate proposals receive three ordered
rejections and commit the queued rejection next; no response is lost or resampled.
Trade overhead consumes moves, but removing it was not tested as a remedy.

### What this does and does not establish

- Training/export corruption, a missing buy-card action, and session replacement
  do not explain the specific recorded witness. No implementation defect needing
  a gameplay patch was demonstrated.
- Network capacity, feature encoding, training distribution, optimization and
  greedy inference remain possible explanations for the learned preference.
  This trace does not record logits or prove which mechanism caused it.
- Preserve the exact observation at 873 and the earlier expansion positions as
  capability fixtures. This is a two-action logical witness, **not** a minimized
  full-state failing regression or a runtime-tested alternative policy.
- Next experiment selection should address resource-preserving VP progress and
  expansion under piece limits, comparing a single inference/training change
  against frozen opponents. Declare fresh seeds, practical gain/completion
  criteria and a bounded budget first; neither failed checkpoint is promoted.

## Evidence and implementation checks

Committed [evidence](evidence/native-cap-diagnosis-20260906/) retains manifests,
watchdog receipts, full compressed traces, semantic integrity checks, offline
geometry results, the exact dispatch/inspection source and representative states.
Full uncompressed artifacts and frozen executables/models also remain under
`~/Library/Application Support/EmpiresResearch/experiments/native-cap-diagnosis-20260906/`.
Treat the dated launcher's cutoff as spent, not as a reusable permission to run.

- Five focused CLI tests: cross-process semantic trace/stdout parity, deferred
  replies, forced end-turn, real 3,000-move cap, exclusive paths and I/O/size
  failure. The cap fixture traced 72.65 MB in 4.65s versus 1.67s without tracing.
- Full tooling: **110 tests**. Engine: **235 tests / 95.97% coverage**. AI:
  **146 tests / 96.70% coverage**. Both warnings-as-errors builds passed.
- Independent standards and functional reviews completed. A launcher assertion
  could disappear under optimized Python; explicit failures replaced it before
  dispatch, with four invalid-result checks under `python -O`. Fixture constants
  were named without changing its model bytes. Production hashes stayed frozen.
- The terminal trace and every commit/evaluation link were checked against the
  original receipts. No new predictions, counterfactual moves or training runs
  were used to produce the saved-state analysis.
