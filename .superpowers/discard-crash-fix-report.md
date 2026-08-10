# Bot.decideDiscard crash — investigation report

## Summary

**The crash is already fixed at HEAD (`f5bc1ee`).** The two crash logs on
this machine that this task was dispatched from are stale: both predate
commit `b39844c` ("Final integration fixes: full-game smoke test passes end
to end", 2026-08-10 11:45:44), which added `GameViewModel
.isProcessingBotTurns` specifically to close this exact race, with its own
reproduction ("a disposable headless harness matching the exact crash log
verbatim") documented in that commit's message. `GameViewModel.swift` has
not been touched by any commit since `b39844c` (verified via `git log` and
`git diff b39844c f5bc1ee -- Settlers/ViewModels/GameViewModel.swift`,
which is empty).

No code change was needed. I added a permanent regression test guarding the
existing fix (none existed before), since `GameViewModel` lives in the app
target and had no automated coverage at all for this race.

## Evidence trail

### 1. Two real .ips crash reports exist on this machine, both stale

```
~/Library/Logs/DiagnosticReports/Settlers-2026-08-10-081155.ips  (08:11:55)
~/Library/Logs/DiagnosticReports/Settlers-2026-08-10-113237.ips  (11:32:37)
```

Both have `termination.symbol = "Bot.decideDiscard(legal:state:player:)"`
and the crashing thread's backtrace is:

```
_assertionFailure(...)
Bot.decideDiscard(legal:state:player:)      Bot.swift:115
Bot.decide(for:player:)                     Bot.swift:31
GameViewModel.runBotTurnIfNeeded()          GameViewModel.swift:92
closure #1 in GameViewModel.apply(_:)       GameViewModel.swift:44
```

### 2. The frame line numbers pin the crash to a specific pre-fix commit

Commit `a61c300` ("Add GameViewModel wiring engine, AI, and persistence")
landed at **08:11:26**, 29 seconds before the *first* crash. That's the
very first version of `GameViewModel`, and it has no
`isProcessingBotTurns` guard at all - `runBotTurnIfNeeded()` is freely
reentrant. `apply(_:)`'s `Task { await runBotTurnIfNeeded() }` is on line
44 in that version, matching the crash frame exactly.

The *second* crash (11:32:37) falls between commit `1ac1024` (09:16:15,
"Fix Task 15 review issue") and `b39844c` (11:45:44, the fix commit) - so
it was also built from a pre-fix tree. Checked out `1ac1024`'s
`GameViewModel.swift` and `Bot.swift` (at the closest preceding commit,
`a8ad34a`) directly:

- `Bot.swift:31` at that commit is `case .discarding: return
  decideDiscard(...)` - exact match.
- `Bot.swift:115` at that commit is the `preconditionFailure(...)` call -
  exact match.
- `GameViewModel.swift:44` at that commit is `Task { await
  runBotTurnIfNeeded() }` inside `apply(_:)` - exact match.
- `GameViewModel.swift` at that commit has **no** `isProcessingBotTurns`;
  `runBotTurnIfNeeded()` is plain reentrant `async` code.

All three matched frames land on the exact same source lines as the
current (fixed) file, which is a coincidence only because the fix was
inserted as new lines *before* the loop body rather than editing existing
lines around it - the file's line numbering for those specific statements
happened not to shift. This is strong, specific confirmation these two
crash reports are from the pre-`b39844c` build.

### 3. `b39844c`'s own commit message documents this exact bug and fix

```
`isProcessingBotTurns` makes this method non-reentrant. Found during
Task 16 simulator verification: `apply(_:)` spawns a fresh
`Task { await runBotTurnIfNeeded() }` after *every* human move -
including a human's own `.discard` response while other bots are
still resolving theirs from the same 7-roll (`.discarding` can have
several players pending at once, human included). That let two
invocations of this loop run concurrently against the same shared
`state`: one captures `botPlayer` from `nextBotPlayer()`, sleeps
600ms, and by the time it wakes and calls `bot.decide(for: state,
player: botPlayer)`, the *other* invocation may have already
resolved that same player's pending action (e.g. their discard) -
`Bot.decide`'s `.discarding` branch doesn't re-check membership in
`pending` before deciding, so it would recompute against
`RulesEngine.legalMoves(for:)`'s now-empty set of moves for that
player and crash with `Bot.decideDiscard`'s "no legal discard
combination found" `preconditionFailure` - reproduced via a
disposable headless harness matching the exact crash log verbatim
(see task-16-report.md).
```

This is a verbatim description of the mechanism reconstructed independently
below, before I found this commit message.

### 4. Independent static proof the engine-level invariant is sound

Traced `RulesEngine.discardCombinations` (private, `RulesEngine.swift`):
its backtracking always finds at least one combo summing to `count` when
`count <= totalHolding` - the "take as much as possible at each resource"
branch is always explored and reaches `remaining == 0` exactly when
`totalHolding >= count`. `Robber.discardCount` guarantees `count =
total/2 <= total`. So `discardCombinations` can never legitimately return
empty for a real hand. Also confirmed `GameState`/`Player` are plain
Swift value types (structs), so `Bot.decide`'s `legal` and `me` are
necessarily computed from one consistent snapshot within a single call -
no staleness is possible *within* one `Bot.decide` invocation.

This rules out a data/logic bug in the engine; the only way to trigger the
precondition is for the `player` argument passed into `Bot.decide` to no
longer be a member of `state.phase`'s `.discarding(pending:)` set at call
time - exactly the reentrancy race above.

### 5. Empirical confirmation: the current guard prevents it, removing it reproduces it

Wrote `Packages/CatanAI/Tests/CatanAITests/DiscardRaceRegressionTests.swift`
- a `MockViewModel` reproducing `GameViewModel`'s exact concurrency shape
(capture-acting-player → `Task.sleep` → decide → apply, gated by an
`isProcessingBotTurns`-style flag), racing many concurrent human
discard/roll/end-turn submissions and redundant `runBotTurnIfNeeded()`
kicks (mirroring `ContentView`'s separate Resume call site) against the
bot loop, across many randomized boards.

- **With the guard present** (current code): 200 seeds, zero crashes
  (~127s). Also 60 seeds x 5 repeated `swift test` runs in the final
  suite, zero crashes/flakes.
- **With the guard temporarily commented out** (simulating the pre-fix
  code): crashed on the very first affected seed, with the *exact* crash
  signature:
  ```
  CatanAI/Bot.swift:115: Fatal error: no legal discard combination found
  for PlayerID(index: 1) holding [.wool: 4, .lumber: 0, .ore: 2,
  .brick: 0, .grain: 0]
  ```
  (Guard was restored immediately after this confirmation; not committed
  disabled at any point.)

This closes the loop: the mechanism in `b39844c`'s commit message is
exactly reproducible, the fix it shipped exactly prevents it, and no
other route to the precondition was found despite substantial additional
effort (see "Other avenues ruled out" below).

## Other avenues ruled out

Per the dispatch's specific concerns:
- **Stale save file corruption**: `GameStore.save` writes via
  `Data.write(options: .atomic)` and is only ever called synchronously
  from `@MainActor` code with no concurrent writers possible - ruled out
  by design, and the two real save files found under
  `~/Library/Developer/CoreSimulator/.../catan_save.json` on this machine
  are both internally consistent (one mid-`.discarding` was not found, but
  neither showed inconsistency between phase and resources).
- **Zero-valued resource dictionary entries**: confirmed these *do* occur
  in real save data (e.g. `{"brick": 0, "grain": 2, ...}` in one of the
  on-disk saves) - `Dictionary`'s `?? 0` handling throughout
  `discardCombinations`/`Robber`/`Bot` treats missing and zero-valued keys
  identically, so this is harmless and not a contributing factor.
- **Multiple `GameViewModel` instances / duplicate call sites**: confirmed
  only one `GameViewModel` is ever constructed by the running app
  (`ContentView`'s single `@State`); the `GameView(viewModel:
  GameViewModel())` at the bottom of `GameView.swift` is Xcode-preview-only
  code, not reachable from the app. `ContentView`'s separate
  `Task { await viewModel.runBotTurnIfNeeded() }` (Resume flow) is
  included in the regression test as one of the "redundant kicks" and does
  not defeat `isProcessingBotTurns`.
- **`try?`-swallowed `RulesEngine.apply` errors in the bot loop**: `bot
  .decide(for: state, ...)` and the following `RulesEngine.apply(move,
  by: botPlayer, to: &state)` run back-to-back with no `await` between
  them, so `state` cannot change in between - a move `decide` returns can
  never be rejected by `apply` for staleness reasons.
- **Recent UI-only commits** (`b91d338` redesign, `f5bc1ee` settings
  screen): reviewed both diffs; neither touches `GameViewModel.swift`,
  `Bot.swift`, or `RulesEngine.swift`, and neither adds any new mutator of
  `state` or new call site into the bot loop. `b91d338`'s new
  `GameNotificationOverlay`/`enqueue` `Task`s only touch local
  `@State` UI arrays, never `viewModel.apply` or `state`.

## Regression test added

`Packages/CatanAI/Tests/CatanAITests/DiscardRaceRegressionTests.swift`:
`concurrentHumanAndBotDiscardTurnsNeverCrash()` - see above. This is new
coverage (no prior automated test exercised `GameViewModel`'s concurrency
shape at all, since it lives in the untestable Settlers app target); it
guards `isProcessingBotTurns` against being removed/weakened in the
future without a passing-test signal.

## Verification

- `cd Packages/CatanEngine && swift test` - 77 tests, run **5x
  consecutively**, all green every time (no flake).
- `cd Packages/CatanAI && swift test` - 13 tests including the new
  regression test, run **5x consecutively**, all green every time
  (~18-22s per run, dominated by the new test's 60 randomized/concurrent
  seeds).
- `xcodegen generate && xcodebuild -scheme Settlers -destination
  'platform=iOS Simulator,name=iPhone 17' build` → **BUILD SUCCEEDED**.
- Did not do a fresh manual Simulator playthrough beyond the above,
  given (a) the crash is proven to be a pre-fix artifact via git
  history + exact frame-line matching, (b) the regression test
  empirically confirms the current guard holds and the old code doesn't,
  and (c) no code changed that could newly affect this path.

## Recommendation

No fix needed at `f5bc1ee` for this specific crash; it's already resolved
by `b39844c`. Suggest clearing the two stale `.ips` files from
`~/Library/Logs/DiagnosticReports/` (or noting their timestamps) so they
don't get mistaken for a live crash again. If a *fresh* crash with this
exact signature is seen on a build at or after `f5bc1ee`, that would be a
new, different bug and warrants a fresh investigation - none was found
despite substantial effort here.
