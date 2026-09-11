# Expanded bot strength and late-game responsiveness

## Request and evidence

Complete two items sequentially: first investigate/fix weak 25-point bots, then improve late-game speed and smoothness. The supplied final-board screenshot shows a 704-move Expanded game, human 25 VP versus bots 10/11/14. It establishes the outcome and board ownership, but cannot establish early move choices or timing. “25-person” is interpreted as this four-seat 25-point mode.

New games ship Balanced heuristic opponents; civilization changes appearance/dialogue, not a difficulty tier. Existing saves preserve their strategy. No calibrated difficulty selector currently exists.

## 1. Bot strength

Trace setup, build selection, resource saving/trading and mode-specific limits. Reproduce economy failures with deterministic Expanded fixtures and compare bounded seeded play. Fix demonstrated decisions without claiming human-level strength from self-play. Run AI regressions and document results before starting item 2.

## 2. Responsiveness (pending item 1)

Measure late-game decision/state/persistence work and inspect the app scheduling path. Remove repeated expensive work or main-thread stalls supported by measurements; preserve rules, save durability, and visible turn feedback. Verify relevant app/engine tests and release compilation, with before/after timings where reproducible.

## Completion

Record changes, tests, measurements and limits here; mark each to-do complete only after its implementation and relevant verification finish. Leave unrelated artwork untouched.

## Source audit (item 1)

- `OpponentProfile.catalog` creates Balanced opponents for every civilization; the screenshot cannot identify a different strategic difficulty.
- `BuildPlanner` strongly values an immediately affordable settlement/city, but also gives roads and card purchases positive scores. `Bot.decideMainTurn` only considers bank trades and outgoing offers if that planner returns no build. This can consume prerequisites while a better production build is still one card short.
- `DevCardHeuristics.shouldBuyDevCard` is an affordability-only fallback, so a planner-side purchase rejection alone would be bypassed.
- Legacy bank-trade selection checks held cards against the target cost and trade rate separately; it does not reserve the target cost after paying the rate. Its nearest target is resource-only, independent of available sites/pieces.
- Expanded doubles pieces and raises the finish to 25 VP; the existing setup/build strategy was inherited from Classic. The September 11 mode delivery measured two unfinished Expanded self-play games out of twenty. These observations justify investigating economy planning, but do not prove the attached game's exact opening sequence.

### Comparison protocol

Frozen source: `0f8a65c` (all files in `Packages/CatanAI/Sources/CatanAI`, compiled as a separate module against the same engine). Release-mode harness uses randomized Expanded boards, seeds 11001–11012, four Balanced seats, policy seed `seed * 31 + 7`, and a 3,000-move cap. Arms: all old, all revised, and one revised seat against three old seats with the revised seat rotating. Track completion, turns/moves, and building/card/road actions during the first 40 completed seat turns. This is a bounded development screen; the sample does not establish calibrated human difficulty.

### Item 1 comparison results

All 36 games finished within the original 3,000-move cap. Across the first 40 completed seat turns, all-old versus all-revised mean building actions rose **5.08 → 10.67**, card purchases fell **12.83 → 0.75**, and road builds were **18.17 → 18.67**. Mean total turns fell **122.33 → 113.75**; mean moves were **802.00 → 809.08**. The revised hero won **3/12** mixed games, exactly the four-seat null rate: this screen supports the production-opening correction, but does not establish stronger overall play against the old policy or a skilled human. Raw records and the harness are in [comparison evidence](../evaluations/2026-09-11-expanded/README.md).

The shipped change deliberately preserves Classic behavior. Expanded opening roads evaluate the outward endpoint rather than their common occupied endpoint. Expanded card scoring reserves resources near an available city/settlement build; the old affordability-only fallback cannot override that decision. Card valuation still permits an immediate army-race opportunity and releases the reserve when physical building options are exhausted. Road count alone is not a useful quality metric: roads enable expansion, and this screen did not reduce total opening roads. Ownership-aware multi-turn road planning and calibrated human difficulty remain broader work.

### Item 1 completion

`SeededGameFingerprintTests.expectedExpandedFingerprints` was re-recorded for the two Expanded-only policy changes; the Classic table is untouched, which is the check that the change really is mode-scoped. All five new values were bit-identical across three separate processes before being pinned, per that file's own rule. Full `CatanAI` suite: 149 tests, green.

## 2. Responsiveness - measurement

`SettlersTests/LateGameCostProbe.swift` (temporary probe, removed after the fix) drove one Expanded 25-point match through the production persistence path with **no pacing delay at all** and timed each committed move. 770 moves cost **126.6s of blocking MainActor work**. Means per committed move:

| moves | decide | record | commit | export | total |
|---|---|---|---|---|---|
| 0-99 | 2.9ms | 0.1ms | 25.3ms | 8.2ms | **36.5ms** |
| 400-499 | 34.2ms | 0.2ms | 84.5ms | 37.6ms | **156.5ms** |
| 700-769 | 77.3ms | 0.4ms | 215.8ms | 101.2ms | **394.7ms** |

Every cost except `record` grows with the length of the history, because the work per move is proportional to the whole game so far. Spot measurements at move 600: `validateHistory` 39.0ms, `store.load` 55.4ms, whole-document encode 12.6ms.

Three full-history replays happen on **every** committed move: `MatchCheckpointStore.commit` calls `load()`, which validates the document it just read (replay #1), then validates the candidate (replay #2), and `GameLogStore.export` validates again before rewriting the entire JSONL archive (replay #3). The document is also JSON-decoded and re-encoded in full, and the whole archive rewritten, per move. So a game costs O(moves squared), and at 25 points there are enough moves for that to be felt: roughly 0.4s of frozen UI per bot action on top of the pacing delay, which is exactly "slow and laggy toward the end".

### Fix

1. **Validate the delta, not the whole history, on the commit hot path.** A candidate that is the previous committed document plus one recorded move only needs that move replayed onto the previous state; the prefix was validated when it was committed. Full-history validation stays on every cold path - load, resume, recovery, migration, export.
2. **Do not re-decode and re-validate the current document on every commit.** Read the bytes (cheap) and compare them against the bytes this store last wrote; identical bytes mean the cached document is current. Any file written by anything else still takes the full decode-and-validate path, so nothing is trusted that was not verified.
3. **Export the JSONL archive on turn boundaries, not on every move.** It is a derived projection - the checkpoint is the resume authority - so rewriting it 25 times per turn buys nothing. Flush it on `.endTurn`, on game over, and when the app resigns active.
4. **Pace against a deadline.** Sleeping a fixed interval *after* doing the work makes the visible turn rhythm inflate with whatever the work costs. Sleep until the interval has passed since the action began, so the chosen speed is the speed the player gets.

Bot decision time (`decide`, 2.9ms -> 77.3ms) is a separate growth curve inside `CatanAI` and is measured again after the persistence work lands.

### Item 2 results

Same probe, same seed, same 770-move Expanded match, after the change. Means per committed move, with the archive now exported the way the app exports it:

| moves | decide | record | commit | export | total | was |
|---|---|---|---|---|---|---|
| 0-99 | 2.8ms | 0.1ms | 8.6ms | 1.4ms | **12.9ms** | 36.5ms |
| 400-499 | 27.4ms | 0.1ms | 11.5ms | 4.3ms | **43.3ms** | 156.5ms |
| 700-769 | 59.9ms | 0.3ms | 17.1ms | 10.1ms | **87.4ms** | 394.7ms |

Persistence work at the end of the game: **317ms -> 27.6ms per move**, 11.5x. Whole match: 126.6s -> 40.9s. `store.load` went from 55.4ms to 0.1ms at move 600; `commit` from 215.8ms to 17.1ms.

These are **Debug simulator** numbers, which is what makes them comparable to each other, not what the shipped app costs. Re-measured in Release against the same seed, a bot decision costs 7.4ms late-game rather than 60ms, and `RulesEngine.legalMoves` only 0.44ms of it.

Bot decision time is now the largest remaining per-action cost. It grows 0.37ms -> 7.4ms (Release) but **plateaus after about move 500** - it scales with how much is on the board, which is bounded, not with how long the game has run, which is not. It is left alone: it is not the quadratic term, and nothing measured says it is worth trading bot quality for.

What still grows linearly with history is the whole-document JSON encode (12.6ms at move 600) and its atomic write, since a checkpoint is rewritten in full on every move. That is the next thing to do if a much longer game ever needs it; an append-only journal is the shape, and it is a bigger change than this one.

### Verification

- `IncrementalCheckpointValidationTests` - a candidate whose appended move does not produce its recorded state is refused (the tamper the delta replay exists to catch), a candidate that rewrites an already-recorded move is refused, a save rewritten outside the store is decoded and validated rather than served from the cache, and a match committed entirely through delta validation still passes a cold full replay on resume.
- `ArchiveFlushPointTests` - the archive appears on the first move, is current at every turn boundary, is deliberately stale mid-turn, and is flushed when the app resigns active.
- `CompleteMatchTests` gains one Expanded 25-point case: a whole 25-point match played through the real session, checkpoint, statistics, game log, replay comparison and cold resume. It is the only case in that suite long enough to reach the history sizes this work is about, and it passes in 178s.
- `scripts/gate.sh`: all 11 gates green, including both package suites, the app suite, the native UI suite and the Release build.
- Runtime: built and installed fresh on the QA simulator, played a complete match through the app with `-qaAutoStart -qaPlayToEnd`, and read back the end-game standings screen.

### Not verified

An Expanded match has not been played to its late phase **through the UI by hand** - at the shipped pacing that is roughly an hour of wall clock. What is measured is the same code path (`CompleteMatchTests`'s Expanded case and the probe both drive the production stores), not the same pair of hands.
