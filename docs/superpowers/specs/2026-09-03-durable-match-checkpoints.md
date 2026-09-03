# Durable match checkpoints

Status: production integration implemented and verified; pending PR review/merge.
Scope: process interruption, not power-loss durability.

## Product contract

1. After closing or crashing, Resume opens one complete committed match revision:
   board, hands, RNG, realized seats/names/profiles, and recorded moves agree.
2. New Game and Restart switch the match identity and roster with the board.
   An interrupted replacement must never attach the old recording to the new game.
3. A completed solo match affects lifetime totals once, even if finalization is
   retried after a crash. Hot-seat matches never affect personal totals.
4. A failed durable write keeps the previous revision authoritative and displays
   an actionable error. The app must not continue making unsaved bot moves.
5. Logs are generated from committed history. A failed export may lag, but must
   be retried without duplicate moves or a fabricated result.
6. Clearing/replacing a game cannot discard an unexported completed recording
   or its accounting receipt. Resetting stats cannot recount old results.
7. Existing saves and totals migrate without deleting their original bytes.
   Inconsistent legacy history must be reported, not silently invented.
8. Accumulated active duration survives checkpoint/relaunch and is frozen at
   completion. Time spent with the app closed does not become play duration.

## Source-confirmed gaps

At recovery branch `939520c`, both move paths append a log before saving state.
Winning moves finalize that log and update stats before saving the terminal
state. An interruption can therefore leave a log ahead of the save, remove its
active identity early, or count a completion whose winning move was not saved.
`MatchPersistenceTransaction` rolls back ordinary thrown errors, but its
snapshots exist only in memory and cannot repair process death between writes.
These orderings are source-confirmed; process-kill reproduction is still required.

## Decisions

- Keep application match identity outside engine `GameState`.
- One versioned authoritative document owns active state, realized roster,
  numbered history, duration, completion receipts, and lifetime accounting.
- Apply to a candidate session, commit atomically, then publish state/events.
  Human, policy, and automatic trade-response paths share that boundary.
- JSONL archives are derived exports, not a second authority. Atomic exports
  use stable match IDs and can be retried after relaunch.
- Keep unexported completed history until successful export; retention cannot
  evict it. Existing legacy totals become an explicit migration baseline.
- `.atomic` replacement is a process-interruption contract here, not a claim
  of power-loss durability. The latter requires separate synchronization tests.
- Start with a whole-document implementation; measure per-move latency and
  size over long games before considering a journal or database.

## Acceptance evidence required

- Fault injection immediately before and after authoritative replacement:
  recreate readers and observe the complete old or new revision, never a mix.
- Separate-process termination/recovery at commit and export checkpoints;
  exception tests alone are insufficient.
- Replay committed history to exact saved state, including RNG, after each
  recovery point for human, bot, and automatic trade-response moves.
- Repeated winning submission and post-commit/pre-acknowledgement interruption
  leave exactly one accounting receipt and one totals increment.
- Cover solo human/bot victories, hot-seat exclusion, stats reset, completed
  clear, restart, export failure, retention pressure, and partial legacy tails.
- Legacy valid/corrupt/mismatched save-log migration preserves original bytes.
- Run the supported complete-match matrix, native resume/recovery flows,
  Release build, and full gate on the dedicated QA simulator.

None of these requirements is complete merely because this document exists.

## Verified first slice

The app-hosted `MatchCheckpointStoreTests` suite currently proves document
round-trip, exception injection immediately before/after atomic replacement,
and rejection of a deliberately mismatched move history. The mismatch test
was observed failing before replay validation was implemented. Completion
receipts and totals now share the document: tests cover a post-write/pre-ack
exception, reload/retry, hot-seat exclusion, frozen completion duration, and
stats reset without erasing receipts. Five tests (seven parameter cases) pass;
scoped SwiftLint is clean. These are synthetic terminal fixtures for accounting,
not evidence of full gameplay or operating-system process termination.

This is not production persistence yet. Pending: semantic/roster validation,
receipt validation and lifecycle duration checkpoints, candidate-session integration, migration/export,
separate-process termination, performance measurement, and full release gate.

The candidate transition now applies a real engine move to an unpublished
copy, records elapsed active time, and creates its completion receipt in that
same revision when it wins. Seven hosted tests pass, including a winning
position reached through seeded self-play and then committed/reloaded through
the store. This proves the winning transition, not yet a whole match using the
new persistence path. Production integration must preserve GameSession's
policy RNG and negotiation bookkeeping; replacing the session after every
persisted move would incorrectly reset those counters.

The engine now exposes a Codable session checkpoint covering policy RNG,
evaluation count, queued trade decision, proposal guard, and action counters.
Restoration checks schema and policy identities without re-evaluating a pending
response. Three new engine tests cover continuing the same move sequence,
preserving a sampled response, and rejecting a changed policy roster; the full
181-test engine suite passes. Hostile-checkpoint validation remains pending.

App documents now include the actual candidate session checkpoint, and reject
a snapshot whose board disagrees with recorded history. Nine hosted tests pass.
One entire seeded match wrote every move and reloaded its session every 25
moves, finishing with one completion receipt and exact final state in 22.611s
on the simulator. This is a functional storage-path test, not a phone latency
benchmark or proof of production GameViewModel wiring, which remains pending.

Session loading now rejects invalid schema/phase/current-turn seats, policy
rosters, action/evaluation counters, and queued offer decisions before any
unchecked index or increment can execute. Nineteen validation tests were first
observed with 27 failed rejection expectations; after validation, the full 197
engine tests pass.

Actual process termination is now proven on the dedicated `Empires Recovery QA`
simulator. A host harness launched the app into each commit boundary, waited for
an app-written marker, terminated PID 12629 before atomic replacement and PID
12672 after replacement, then launched different reader processes. Recovery
returned exactly revision/moves/settlements `0,0,0` before and `1,1,1` after.
The probe uses its own per-run Application Support directory and never reads,
resets, or replaces the player save. This proves process interruption around
atomic replacement; it does not claim power-loss durability.

Migration preparation now reads historical totals strictly, preserves them as
a baseline, and reconstructs any supplied active recording to verify exact
agreement with the save. Tests cover unchanged source bytes, corrupt totals,
and a recording one move ahead of its saved board. Preparation writes no
legacy artifacts. A legacy terminal save gets a receipt without adding to the
baseline, since old totals cannot establish whether it was already counted.
Caller-side selection of the active recording, archival of original bytes,
and production adoption still require integration tests before rollout.

Replacing or clearing the active match now queues its full recording in the
same revision. Queued recordings are replay-validated on commit and reload,
and their IDs cannot be reused by a new match. The corruption regression was
observed failing when a displaced recording's moves were removed while its
final board remained unchanged; validation now rejects that document. Fourteen
hosted persistence tests pass, including two consecutive replacements across
reload and clearing a genuine seeded winner while preserving its receipt and
totals. Export acknowledgement/retention and production wiring remain pending;
these queued histories are not yet a user-visible archive.

The export/migration/duration slice was verified separately from the in-progress
GameViewModel cutover. Nineteen hosted tests pass on the isolated snapshot:
export retry replaces a deliberately truncated JSONL file without duplicate
moves; filesystem export failure retains the queued recording until an exact
snapshot acknowledgement; stats-only migration preserves original totals and
bytes; foreground duration survives reload without inventing a move and stays
frozen after completion. Strict scoped lint and Release simulator compilation
also pass. This evidence covers the storage slice, not the concurrent
production integration, which still needs its full app/UI and release checks.

Archive retention now protects active/pending match IDs even when they are
older than every other file, retaining the newest configured number of
additional unprotected archives. Recovery replacement requires an independent
backup with exact source bytes and rechecks both files at the write boundary.
Ten targeted lifecycle/export tests and Release compilation pass, including
rejection of a mismatched backup, using the source itself as backup, and a
source changed at the injected pre-replacement boundary. These checks do not
claim cross-process locking against arbitrary external writers.

Completion accounting now computes checked integer totals and a finite duration
before publishing any receipt or revision. The oversized-duration regression
first failed with four issues (infinite totals, a recorded receipt, and a bumped
revision instead of an error). Integer-count and duration-overflow cases now
leave the document unchanged. Seventeen targeted lifecycle/storage tests,
strict scoped lint, and Release compilation pass on the isolated snapshot.

Production cutover verification completed on the dedicated Empires QA simulator.
The unified gate passed with 176 app tests in 21 suites, 201 engine tests, 99 AI
tests, all 24 supported match configurations, deterministic training export,
95.86% engine and 96.72% AI coverage, strict lint, leak scanning, and both
Release and Debug builds. Nine separate-process termination cases now cover
human, bot, and automatic trade-response commits plus export before and after
acknowledgement. A fresh install launched, survived, produced no new crash
report, and its main menu, New Game, In-Game Settings, and Trade surfaces were
visually inspected at 402 points wide.

The whole-document format still makes launch validation proportional to retained
unexported history. Retention bounds exported archives, and normal successful
exports empty the pending queue, but a quantitative worst-case launch benchmark
remains a follow-up before increasing archive retention or adopting a journal.
