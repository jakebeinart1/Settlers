# Ghost Opponents, Elo and Leaderboard: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Jake seat ghosts (starting with his own) as opponents, remove pass-and-play, rate everyone with Elo against fixed Classic and Expert anchors, retrain a person's ghost after each of their games, show a leaderboard, and fix the game-over buttons.

**Architecture:** Ghost data is a small `Codable` `GhostProfile` shared by the `ghost` CLI and the app, bundled for Jake and stored locally for anyone else. Seats gain `ghostID`. `GameViewModel.makePolicies` seats a `GhostPolicy` for a ghost chair. A finished game triggers one idempotent Elo update (keyed by match id) and a background `GhostTrainer` run. The New Game screen fixes seat 1 as the human and gives the other seats AI | Ghost.

**Tech Stack:** Swift 6, SwiftUI, XcodeGen, swift-testing (packages), XCTest (`SettlersTests`, `SettlersUITests`).

**Spec:** `docs/superpowers/specs/2026-09-25-ghost-opponents-design.md` (Jake approved it 2026-09-25). This plan also carries a bug Jake reported the same day: the game-over buttons (Task 1).

**Branch:** create worktree `feat/ghost-opponents` **from `feat/ghost-player`** (it needs `GhostPolicy`):
`git -C "<repo>" worktree add -b feat/ghost-opponents "$HOME/Documents/Catan Game worktrees/ghost-opponents" feat/ghost-player`

## Global Constraints

- Follow `CLAUDE.md` exactly. Run `xcodegen generate` after adding or removing any `.swift` file under `Settlers/`. Never edit `project.pbxproj`. Never pipe `xcodebuild` output through `tail`/`grep` without `${PIPESTATUS[0]}`. Do not hand-run `scripts/gate.sh`. Push once, at the end, and only when Jake says so.
- `CatanEngine` and `CatanAI` import only `Foundation` (plus `CatanEngine`). Anything SwiftUI stays in the app.
- `GameViewModel.swift` is at SwiftLint's 1,250-line limit. New view-model code goes in `GameViewModel+Ghosts.swift`.
- Every new `Codable` field decodes with `decodeIfPresent` and a default (CLAUDE.md, "Determinism invariants" 4).
- The engine never learns which seat is human (CLAUDE.md, "Seat 0 is the human"). "Seat 1 is the human" is a **New Game screen** rule and lives in `MatchSetup` validation only.
- Ghosts are offered only when `mode == .classic && variant == .standard`.
- Elo constants: Classic anchor **1000**, Expert anchor **1229**, start rating 1000, K = 32/3 per pair (spec §6).
- Targeted test commands:
  - `swift test --package-path Packages/CatanAI --filter Ghost`
  - `xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination "platform=iOS Simulator,id=$SIM" -only-testing:SettlersTests/<Suite>`, with `SIM` from `scripts/select-qa-simulator.py`
  - `swiftlint --strict`

## Review Focus

1. **An old pass-and-play save** (two or more humans) must still load and play to the end with no hand-off cover, never trap or crash. Test in Task 6.
2. **A ghost seat whose ghost is missing** (bundled ghost removed in an update, or a local file deleted) must be refused before the game starts, with a message naming the seat. On resume, it falls back to an Expert policy for that chair and the fallback is logged. Tests in Tasks 5 and 6.
3. **Self-play counts for Elo.** Jake playing his own ghost is a rated game for both (Jake's rule). Only the human seat's decisions ever train a ghost, never the ghost's own moves. Test in Task 7: after a Jake-vs-Jake's-ghost game, the new decision records all belong to the human seat.
3b. **Elo applied twice** for one match (resume after an unacknowledged commit, or the app killed during the update) must be a no-op the second time. Test in Task 3.
4. **Retraining that fails or is killed** must leave the previous ghost file intact and readable. Test in Task 7.
5. **The same ghost picked for two seats** is refused on New Game. Test in Task 5.

---

### Task 1: Game-over buttons (Jake's bug, 2026-09-25)

**Problem, from the code:** `EndGameView` (`Settlers/Views/EndGameView.swift:85-92`) has one button, titled "New Game". Its handler (`ContentView.swift:51`) calls `clearCompletedMatch()` and returns to the **main menu**, so "New Game" behaves like "Main Menu". Jake: *"New game should be the same as restart game. Main menu should take you to main menu."*

**Files:**
- Modify: `Settlers/Views/EndGameView.swift` (replace the single `onNewGame` with `onNewGame` + `onMainMenu`; add a Main Menu `GoldRowButton`)
- Modify: `Settlers/ContentView.swift:48-52`
- Modify: `Settlers/ViewModels/GameViewModel.swift` (`restartCompletedMatch()`, beside `clearCompletedMatch`, about line 410)
- Modify: `Settlers/Testing/AccessibilityID.swift:209` (add `GameOver.mainMenu = "game-over.main-menu"`)
- Test: `SettlersTests/CompleteMatchTests.swift` (unit) and `SettlersUITests/GameplayBoundaryFlowTests.swift` (UI; it already reaches game over with `-qaPlayToEnd`, per the run-settlers skill)

- [ ] **Step 1: Failing unit test.** In `CompleteMatchTests`, drive a match to `.gameOver` the way the existing tests there do, then call `viewModel.restartCompletedMatch()`. Assert:
  - `state.phase` is a setup phase;
  - the seats and civilizations equal the finished match's realized setup;
  - `currentGameLogID` differs from the finished one;
  - the finished match's completion receipt still exists (statistics were not lost).

  Run it: FAIL, `value of type 'GameViewModel' has no member 'restartCompletedMatch'`.
- [ ] **Step 2: Implement.**
  ```swift
  /// "New Game" on the game-over screen: the same table again. It is the
  /// in-game Restart, but it first clears the finished match the way Main
  /// Menu does, so the completion receipt and recording stay committed
  /// before the new match replaces the document.
  @discardableResult
  public func restartCompletedMatch() -> Bool {
      guard let finished = checkpointDocument?.activeMatch?.setup else { return false }
      guard clearCompletedMatch() else { return false }
      var table = finished
      table.randomizeSeatOrder = false
      table.normalizeNewGameOptions()
      var prefill = matchSetupStore.load().value ?? table
      prefill.normalizeNewGameOptions()
      startNewGame(setup: table, configuredAs: prefill)
      return true
  }
  ```
- [ ] **Step 3: Wire the view.**
  - `EndGameView` gains `let onMainMenu: () -> Void` and a second `GoldRowButton(title: "Main Menu", systemImage: "house.fill")` below "New Game", with `.accessibilityIdentifier(AccessibilityID.GameOver.mainMenu)`.
  - In `ContentView`:
    - `onNewGame: { if viewModel.restartCompletedMatch() { hasStartedThisSession = true } }`
    - `onMainMenu: { if viewModel.clearCompletedMatch() { hasStartedThisSession = false } }`
  - Update the `#Preview` at `EndGameView.swift:200`.
- [ ] **Step 4:** The unit test passes.
- [ ] **Step 5: UI test** in `GameplayBoundaryFlowTests`. Launch with `-qaPlayToEnd`, tap `game-over.new-game`, and expect the game board (`game.command-row` exists). Relaunch, tap `game-over.main-menu`, and expect `AccessibilityID.MainMenu.newGame`. Run it with `-only-testing`.
- [ ] **Step 6: Commit** as `fix(ui): game-over New Game restarts the table; Main Menu goes to the menu`.

---

### Task 2: `GhostProfile`, λ calibration, and Jake's bundled ghost

**Files:**
- Create: `Packages/CatanAI/Sources/CatanAI/Ghost/GhostProfile.swift`
- Modify: `Packages/CatanAI/Sources/ghost/main.swift` (add `calibrate` and `bundle` subcommands)
- Create: `Settlers/Resources/Ghosts/jake.json` (generated; the `sources: [Settlers]` glob in `project.yml` bundles it once `xcodegen generate` runs)
- Test: `Packages/CatanAI/Tests/CatanAITests/GhostProfileTests.swift`

**Interfaces, produced:**
```swift
public struct GhostProfile: Codable, Sendable, Equatable, Identifiable {
    public let id: String            // stable slug, e.g. "jake"
    public var name: String          // shown in the picker and leaderboard: "Jake's Ghost"
    public var person: PersonModel
    public var lambda: Double
    public var gamesLearned: Int
    public var civilization: String? // Civilization.rawValue the person plays most; the app maps it
}
```

- [ ] **Step 1: Failing test.** A `GhostProfile` round-trips through JSON, and it decodes when `civilization` is absent (`decodeIfPresent`). Run `--filter GhostProfileTests`: FAIL (type missing).
- [ ] **Step 2: Implement** `GhostProfile` with a hand-written `init(from:)`, where `civilization` uses `decodeIfPresent`. The test passes.
- [ ] **Step 3: `ghost calibrate --person P.json --target 0.54 --games 200 [--difficulty classic|expert]`.**
  - For λ in `[0, 0.25, 0.5, 1, 2, 4]`, play `--games` seeded games: `GhostPolicy(person:lambda:)` in a rotating chair, the other three seats the chosen tier (`HeuristicPolicy(.balanced)` for Classic, `EvaluationPolicy()` for Expert).
  - Print each λ's win rate with a 95% Wilson interval, then the λ whose rate is closest to `--target`.
  - Use the rotation and seed discipline from the `bot-strength` skill: every chair per seed, held-out seeds from 900_000.
  - **Measure before assuming a size.** Run `--games 40` first and time it. Then pick a `--games` value that keeps the whole sweep under about 1 hour.
- [ ] **Step 4: Run it on Jake.** His 54% came from games against his usual tier; `MatchSetup` default is Classic. Record the table in `docs/AI_summaries/2026-09-25-ghost-player-research.md`, section 7.
  - If **no λ reaches 54%**, record the closest one and do not stretch the grid.
  - Tell Jake that his ghost, if weaker than him, will rate lower than he does.
- [ ] **Step 5: `ghost bundle --person P.json --lambda L --id jake --name "Jake's Ghost" --games 24 --civilization <his most-used> --out Settlers/Resources/Ghosts/jake.json`** writes a `GhostProfile`. Run it, `xcodegen generate`, and confirm the file is in the built `.app` (`find <DerivedData>/…/Empires.app -name jake.json`).
- [ ] **Step 6: Commit** as `feat(ai): GhostProfile, lambda calibration, and Jake's bundled ghost`, with the calibration table in the body.

---

### Task 3: Elo and `RatingStore`

**Files:**
- Create: `Settlers/Models/Elo.swift` (pure math)
- Create: `Settlers/Persistence/RatingStore.swift`
- Test: `SettlersTests/EloTests.swift`, `SettlersTests/RatingStoreTests.swift`

**Interfaces, produced:**
```swift
enum RatedEntity: Hashable, Codable, Sendable { case person(String), ghost(String), classic, expert }
struct Elo {
    static let start = 1000.0, classicAnchor = 1000.0, expertAnchor = 1229.0, pairK = 32.0 / 3.0
    /// New ratings after one four-player game. Anchors never change.
    static func update(_ ratings: [RatedEntity: Double], seats: [RatedEntity], winner: Int) -> [RatedEntity: Double]
}
struct RatingStore {
    func load() -> Ratings                    // { ratings: [key: Double], games: [key: Int], ratedMatches: Set<UUID> }
    func record(match: UUID, seats: [RatedEntity], winner: Int) throws   // idempotent per match id
}
```

- [ ] **Step 1: Failing tests (`EloTests`).**
  - Four players at 1000; seat 0 wins. Seat 0 gains `3 × (32/3) × 0.5 = 16`. Each loser loses `(32/3) × 0.5 = 5.333`, and their mutual 0.5-vs-0.5 pairs change nothing.
  - An anchor seat's rating is unchanged after both a win and a loss.
  - Two Classic seats both read 1000 (anchors are per tier, not per chair).
  - The Expert anchor derivation: `400 * log10(0.789 / 0.211)` rounds to 229. Pin the 0.789 arithmetic from the spec in a comment on the constant.
  - Run: FAIL, `Elo` missing.
- [ ] **Step 2: Implement `Elo.update`.**
  - For each unordered pair (i, j): `S_ij` is 1 if i won, 0 if j won, else 0.5.
  - `E_ij = 1 / (1 + 10^((R_j − R_i)/400))`.
  - Accumulate `Δ_i += K (S_ij − E_ij)` from the **pre-game** ratings.
  - Anchor entities (`.classic`, `.expert`) are read from the constants and never written.
  - Seats are in turn order and iterated by index, never by `Set`/`Dictionary` order.
- [ ] **Step 3: Failing `RatingStoreTests`.**
  - Record a match, then record the same match id again: ratings are unchanged the second time (Review Focus 3).
  - Records survive a new store instance on the same directory.
  - A corrupt file loads as empty ratings and is preserved beside itself as `ratings.corrupt.json`, never overwritten silently.
- [ ] **Step 4: Implement `RatingStore`.** It is a JSON file in Application Support, written atomically (`Data.write(options: .atomic)`), with an injectable directory like `GameLogStore.init(directoryURL:)`. Doc comment: why the match-id set exists (resume after an unacknowledged commit replays the completion).
- [ ] **Step 5:** Tests pass. `xcodegen generate`, then commit as `feat(app): Elo against fixed Classic and Expert anchors`.

---

### Task 4: `GhostStore` (bundled + local, precedence)

**Files:** create `Settlers/Persistence/GhostStore.swift`; test in `SettlersTests/GhostStoreTests.swift`.

**Interfaces, produced:**
```swift
struct GhostStore {
    init(localDirectory: URL, bundle: Bundle)
    func all() -> [GhostProfile]               // local wins over bundled for the same id; sorted by name
    func ghost(id: String) -> GhostProfile?
    func save(_ ghost: GhostProfile) throws    // atomic, local only
    func decisionsDirectory(for id: String) -> URL
}
```

- [ ] **Step 1: Failing tests.**
  - With only the bundled `jake` present, `all()` returns it.
  - After saving a local `jake`, `ghost(id: "jake")` returns the local copy.
  - An unreadable local file is skipped, and the bundled copy is still returned.
  - The test bundle is a temp directory containing `Ghosts/jake.json`.
- [ ] **Step 2: Implement.** Bundled files come from `bundle.urls(forResourcesWithExtension: "json", subdirectory: "Ghosts")`. Local files live in `Application Support/Ghosts/<id>.json`.
- [ ] **Step 3:** Tests pass. `xcodegen generate`, then commit as `feat(app): ghost store - bundled ghosts, local ghosts win`.

---

### Task 5: `MatchSetup` - ghost seats and the one-human rule

**Files:**
- Modify: `Settlers/Persistence/MatchSetup.swift` (`Seat.ghostID`, decoding, `validationProblem`, `resize`)
- Test: `SettlersTests/NewGameSetupTests.swift`

- [ ] **Step 1: Failing tests.**
  - A seat decodes with and without `ghostID`.
  - `validationProblem` (the new-game rules only, **not** `matchProblem`):
    - A setup with two humans is refused: "Pass-and-play has been removed. Seat 1 is you."
    - A human anywhere but seat 0 is refused.
    - A ghost seat outside Classic standard is refused: "Ghosts play Classic only."
    - Two seats with the same `ghostID` are refused (Review Focus 5).
    - A `ghostID` the injected `GhostStore` does not know is refused, naming the seat (Review Focus 2).
  - `matchProblem` still accepts a two-human setup, so old saves resume.
- [ ] **Step 2: Implement.**
  - `Seat.ghostID: String?` via `decodeIfPresent`.
  - The new-game checks go in a new `newGameProblem(knownGhosts: Set<String>)`, called from `NewGameSetupView`, so `matchProblem` and resume are untouched.
  - `resize` never creates a human beyond seat 0.
- [ ] **Step 3:** Tests pass. Commit as `feat(app): ghost seats and a single human in new games`.

---

### Task 6: Seating a ghost; removing pass-and-play

**Files:**
- Create: `Settlers/ViewModels/GameViewModel+Ghosts.swift`
- Modify: `Settlers/ViewModels/GameViewModel+Policies.swift` (`makePolicies` gains `ghosts: [PlayerID: GhostProfile]`)
- Modify: `makeSession` and its three call sites (`GameViewModel.swift:327`, `+Checkpoints.swift`, new-game start)
- Delete: `Settlers/Views/HandoffCoverView.swift` and `SettlersTests/HotSeatTests.swift`
- Modify: every `needsHandoff` use (14 sites in `GameView.swift`, `GameViewLayoutSupport.swift`, `ContentView.swift`, `GameViewModel.swift`)
- Test: `SettlersTests/OpponentProfileIntegrationTests.swift`, plus a new `SettlersTests/GhostSeatTests.swift`

- [ ] **Step 1: Failing tests (`GhostSeatTests`).**
  - Start a Classic game with seat 2 as ghost `jake`, using a test `GhostStore`. `session.policies[seat2]` is a `GhostPolicy` with the stored λ.
  - Resume that checkpoint: still a `GhostPolicy`.
  - Resume with the ghost file gone: an `EvaluationPolicy` sits in that chair and `persistenceErrorMessage` names the seat (Review Focus 2).
  - An old two-human checkpoint resumes, and both humans' turns are playable with no hand-off gate (Review Focus 1). Build the fixture the way `HotSeatTests` did before deleting that file.
- [ ] **Step 2: Implement `makePolicies`.** A chair with a ghost gets `GhostPolicy(person: ghost.person, lambda: ghost.lambda, id: "ghost-\(ghost.id)")`, otherwise `difficulty.policy(for:)`. A ghost chair still carries an `opponentProfile` (it names the voice and civilization), chosen from the ghost's `civilization` and falling back to the seat's.
- [ ] **Step 3: Remove pass-and-play.**
  - Delete `HandoffCoverView` and `needsHandoff`, and strip their call sites.
  - `seatAtDevice`/`seatOwedATurn` stay only while something still reads them. Delete what becomes dead.
  - Run `xcodegen generate`, then build Debug **and** Release (CLAUDE.md: they are different programs once `#if` is involved).
- [ ] **Step 3b: Show the ghost as the opponent.** A ghost chair's display name is the ghost's `name`. Route it through `playerIdentity`, not a new copy (CLAUDE.md: "If you find yourself adding a fifth copy, pass the seat instead").
- [ ] **Step 4:** `GhostSeatTests` and `OpponentProfileIntegrationTests` pass. Commit as `feat(app): seat ghosts as opponents; remove pass-and-play`.

---

### Task 7: `GhostTrainer` - relearn after every game

**Files:**
- Create: `Settlers/ViewModels/GhostTrainer.swift` (actor)
- Modify: `GameViewModel+Ghosts.swift` (the completion hook)
- Test: `SettlersTests/GhostTrainerTests.swift`

**Behaviour (spec §4):** on a completed Classic standard game with exactly one human:
1. `DecisionExtractor.decisions(in:anchor: EvaluationWeights(vector: ghost.person.weights), humanTrading: true)` on that game's `LoggedGame`. Build it from the checkpoint's initial state and moves, not by re-reading the JSONL.
2. Write the decisions to `decisionsDirectory/<matchID>.json`.
3. `PersonFitter.fit(allStoredDecisions, anchor: .forMode(.classic), start: ghost.person)`, then `gamesLearned += 1`.
4. `GhostStore.save` (atomic).
5. Every 10th game, re-extract all stored games at the new weights (the full refresh).

The ghost's id is the human's name, slugged. The first game creates the ghost, but it only appears in the picker at **10** games (spec default).

- [ ] **Step 1: Failing tests.**
  - After a synthetic completed game, `gamesLearned` rises by 1 and the decisions file exists.
  - A fit that throws, via an injected fitter closure, leaves the previous ghost file byte-identical (Review Focus 4).
  - Two completions of the same match id train once.
  - A ghost with 9 games is absent from `GhostStore.pickable()`; with 10, it is present.
- [ ] **Step 2: Implement.** The actor runs off the main actor. Log the time each step takes (`os.Logger`). The hook in `+Ghosts` runs after `recordCompletion` has committed, together with the `RatingStore.record` call from Task 3, and is keyed by match id.
- [ ] **Step 3: Measure on the device.** Install on Jake's iPhone 13 (the run-settlers skill; his signing team is the committed default), finish one game, and read the logged timings. Record them in the spec, section 4.
  - **If the fit takes more than about 60s,** lower `FitOptions.iterations` for incremental fits and re-measure. Do not redesign on a guess.
- [ ] **Step 4:** Tests pass. Commit as `feat(app): retrain a person's ghost after each finished game`.

---

### Task 8: New Game screen

**Files:**
- Modify: `Settlers/Views/SeatCardView.swift` (the role picker: seat 0 has none; other seats show `AI | Ghost`)
- Modify: `Settlers/Views/NewGameSetupView.swift`:
  - `setSeat` becomes `setSeatKind(_:ghost:)`
  - `difficultyRow`'s label changes from "Opponents" to **"AI Opponents"**
  - the ghost picker is presented
- Create: `Settlers/Views/GhostPickerPopup.swift`, modelled on `CivilizationPickerPopup`, with rows showing name, games learned and Elo; ghosts already seated are disabled
- Modify: `Settlers/Testing/AccessibilityID.swift` (`NewGame.seatKind(i)`, `NewGame.ghostRow(id)`)
- Test: `SettlersUITests/NewGameModeFlowTests.swift`, `SettlersUITests/MainMenuFlowTests.swift`

- [ ] **Step 1: Failing UI tests.**
  - Seat 1 has no role control.
  - Seat 2 shows "AI" and "Ghost".
  - Choosing Ghost opens the picker with "Jake's Ghost".
  - Picking it shows the name on the card.
  - Switching mode to Expanded turns the ghost seat back to AI, with the caption "Ghosts play Classic only".
  - Starting a game with a ghost seat reaches the board, and the ghost's first move is legal (the game advances past its setup turn).
- [ ] **Step 2: Implement.**
  - The picker lists `GhostStore.pickable()`.
  - Refusals speak through the existing `refusal` banner, the same pattern as today's "only human seat" message.
  - Remove the old last-human refusal, which is now unreachable.
- [ ] **Step 3:** UI tests pass (`-only-testing` for both suites).
- [ ] **Step 4: Screenshots** (run-settlers skill, Debug build): New Game with a ghost seat, and the ghost picker. **Read the screenshots** before claiming anything (memory: verify UI before declaring done).
- [ ] **Step 5: Commit** as `feat(ui): New Game - you in seat 1, AI or Ghost opponents`.

---

### Task 9: Per-seat game stats (`SeatStats`) and the Expert baseline

**Files:**
- Create: `Settlers/Models/SeatStats.swift` (the six measures, VP, won, and `matchID`)
- Create: `Settlers/Persistence/SeatStatsStore.swift`
- Modify: `GameViewModel+Ghosts.swift` (the completion hook computes stats for every seat, next to the Elo and trainer calls)
- Modify: `Packages/CatanAI/Sources/ghost/main.swift` (add a `baseline` subcommand)
- Create: `Settlers/Models/RadarBaseline.swift` (constants plus their source)
- Test: `SettlersTests/SeatStatsTests.swift`

- [ ] **Step 1: Failing test.** Replay a seeded fixture game with known events. Assert each measure for one seat:
  - production cards per turn
  - settlements + cities built
  - completed trades
  - dev cards played, and Largest Army
  - leader-hit share of robber moves
  - final VP ÷ target

  The expected numbers are computed by hand from the fixture's event list. Write them into the test as literals, with a comment deriving each one.
- [ ] **Step 2: Implement `SeatStats.compute(initial:moves:)`.** Replay through `GameSession.applyExternal` and read `Step.events`. The leader is judged by public VP before the robber move, the same rule as `StyleFeatures.isLeader`.
- [ ] **Step 3: `SeatStatsStore`.** One JSON file per match, written in the completion hook and idempotent by match id. Test: recording twice leaves one record.
- [ ] **Step 4: `ghost baseline --games 200`.** Run Expert self-play on held-out seeds and print each measure's mean. Put the means in `RadarBaseline.expert`, with the command, the date and the sample size in its doc comment. `rating = clamp(1...99, round(75 × value / expertMean))`, except for Finishing, which is already a ratio: `75 × (vpRatio / expertVpRatio)`.
- [ ] **Step 5:** Tests pass. Commit as `feat(app): per-seat game stats and an Expert radar baseline`.

---

### Task 9b: Leaderboard and detail page

**Files:**
- Create: `Settlers/Views/LeaderboardView.swift`
- Create: `Settlers/Views/RatedEntityDetailView.swift`
- Create: `Settlers/Views/RadarChartView.swift` (SwiftUI `Path`, six axes, 0–99 scale, solid or dashed outline)
- Modify: `Settlers/Views/MainMenuView.swift` (a "Leaderboard" `GoldRowButton` beside `historyButton`)
- Modify: `Settlers/Testing/AccessibilityID.swift`
- Test: `SettlersTests/LeaderboardModelTests.swift`, `SettlersUITests/MainMenuFlowTests.swift`

- [ ] **Step 1: Failing unit tests.**
  - `LeaderboardModel.rows`:
    - sorts by Elo, descending, with ties broken by name;
    - marks anchors `isFixed`;
    - shows "unrated" when a non-anchor has 0 games.
  - `DetailModel(for: .ghost(id))`, for any ghost (bundled or local, the user's or an opponent's):
    - `gamesLearned` comes from the ghost's profile;
    - games against humans (played, won, lost, win rate) come from `SeatStatsStore`, with self-play against its own person on a separate line;
    - the radar uses the ghost's games once it has 3 or more, and its person's games (flagged `isLearnedFrom`) below that;
    - style lines are the top 3 habits by |θ|, phrased from a fixed table and never showing the size;
    - there is no recent-games list (Jake dropped it).
- [ ] **Step 2: Implement** the models and views. Use the painted chrome from `GameHistoryView`.
- [ ] **Step 3: UI test.**
  - Main menu → Leaderboard shows "Classic AI 1000" and "Expert AI 1229".
  - Tapping "Jake's Ghost" opens a page with the radar (`AccessibilityID.Leaderboard.radar`) and the record.
- [ ] **Step 4: Screenshot** the leaderboard and the detail page with the run-settlers skill, and read both. Commit as `feat(ui): leaderboard with ghost and player detail pages`.

---

### Task 9c: Keep everything, and the ghost-vs-Expert test

**Files:**
- Modify: `Settlers/Persistence/GameLogStore.swift` (no pruning; doc comment with the ~0.5 GB-per-10k-games ceiling)
- Modify: `RatingStore` (append a history entry per update)
- Modify: `GhostStore.save` (writes `ghosts/<id>/v<n>.json`, never overwriting; the latest version wins)
- Modify: `Packages/CatanAI/Sources/ghost/main.swift` (add `strength`)
- Test: `SettlersTests/GameLogStoreTests.swift` (the pruning test flips: 600 logs are all kept), `RatingStoreTests`, `GhostStoreTests`

- [ ] **Step 1: Failing tests.**
  - All 600 logs survive.
  - Two rating updates leave two history entries.
  - Saving a ghost twice leaves v1 and v2 on disk, and `ghost(id:)` returns v2.
- [ ] **Step 2: Implement.** The existing pruning test encodes the old rule on purpose. Change it, and say why in the commit.
- [ ] **Step 3: `ghost strength --person P.json --lambda L --games 1248 --vs expert`.** It follows the `bot-strength` skill: ghost in every chair, held-out seeds, and a Wilson 95% CI against the 25% null. Run it on Jake's calibrated ghost and record the result in the research doc. **If the CI is above 25%, it is better than Expert.** Tell Jake before anything else, because that result opens "adopt the ghost as Expert", which is its own plan.
- [ ] **Step 4:** Commit as `feat(app,sim): keep every game, rating and ghost version; ghost-vs-Expert strength test`.

---

### Task 10: Finish

- [ ] Update `design-references/STATUS.md` only if art changed. Add the leaderboard and ghost flows to the run-settlers skill's flag list if new `-qa*` flags were added.
- [ ] Append results to the research doc: calibration, device timings, and screenshots paths.
- [ ] Final whole-branch review (fresh reviewer), then fix Critical and Important findings.
- [ ] **Ask Jake before pushing.** Then `git fetch && git rebase origin/main` and one push to `main` (CLAUDE.md "Concurrent agents"). The hook's gate is the verification.
