# Durable match checkpoints

Status: isolated store prototype; production integration pending.
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
receipt validation and active duration, candidate-session integration, migration/export,
separate-process termination, performance measurement, and full release gate.
