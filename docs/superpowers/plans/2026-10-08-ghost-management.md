# Ghost Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From main-menu Settings, a player can see their ghost's training status, pause/resume training, rename, reset and remove their ghost, manage old ghosts, and hide other players' ghosts - with rename/reset/remove/pause synced to every phone.

**Architecture:** `GhostProfile` (CatanAI) gains `revision`, `isNameCustom`, `isTrainingPaused`, `isRemoved`. The ladder's existing record field `gamesLearned` carries `revision`, so no CloudKit schema change. `GhostStore` gains the management operations; `GhostTrainer` honours pause via skip markers; a new `ManageGhostsView` drives it from `InGameSettingsView`'s menu mode.

**Tech Stack:** Swift 6.3, SwiftUI, Swift Testing, XCUITest, CloudKit (public DB), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-08-ghost-management-design.md`

## Global Constraints

- `CatanAI` imports only `Foundation` + `CatanEngine` (CLAUDE.md corollary; CI runs it on Linux).
- Every new `GhostProfile` field decodes with a default (`decodeIfPresent`) - a ghost that fails to decode silently leaves the picker.
- Nothing is deleted from disk: removed/reset files move to `Application Support/GhostArchive/` (Jake, 2026-09-25).
- `revision` only ever increases; every rename, reset, remove, pause toggle and learned game adds 1.
- After adding any `.swift` file under `Settlers/`: `xcodegen generate` before building.
- Never pipe `xcodebuild` through `tail`/`grep` without `PIPESTATUS`; use `-only-testing:` (Swift Testing functions need trailing `()`).
- Worktree: `~/Documents/Catan Game worktrees/card-icons-victory-themes`, branch `feat/card-icons-victory-themes`. QA simulator `BC2DF6CD-CD05-4AAB-9EC4-EB43B74A00A8`, DerivedData `~/Library/Caches/settlers-derived-cards`.
- Disk is nearly full (~1 GB): no screen recordings; delete any `.xcresult` after reading it.

## Review Focus

1. A ghost file written by today's app (no `revision`) must load with `revision == gamesLearned`, or every player's ghost re-downloads/loses its place -> Task 1 test.
2. Reset then sync: the server still holds the old ghost at a lower revision than the reset one; the phone must NOT re-download it -> Task 2 test (`downloadGhosts` comparison helper).
3. A game finished while paused, then training resumed: launch catch-up must not teach it -> Task 4 test.
4. A removed ghost seated in a saved game: resume must refuse cleanly via the existing `missingGhostProblem`, not crash -> Task 3 test (`ghost(id:)` returns nil for a tombstone).
5. Renaming to an empty/whitespace name must be refused, keeping the old name -> Task 3 test.

---

### Task 1: GhostProfile management fields (CatanAI)

**Files:**
- Modify: `Packages/CatanAI/Sources/CatanAI/Ghost/GhostProfile.swift`
- Test: `Packages/CatanAI/Tests/CatanAITests/GhostProfileTests.swift`

**Interfaces:**
- Produces: `GhostProfile.revision: Int`, `.isNameCustom: Bool`, `.isTrainingPaused: Bool`, `.isRemoved: Bool` (all `public var`); init gains defaulted params `revision: Int? = nil` (nil -> `gamesLearned`), others `false`.

- [ ] **Step 1: Failing test** - append to `GhostProfileTests`:

```swift
    /// Every ghost on disk and on the server today has no revision; it must
    /// start at the number the server already compares (`gamesLearned`).
    @Test func anOldGhostDecodesWithRevisionEqualToGamesLearned() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as? [String: Any])
        for key in ["revision", "isNameCustom", "isTrainingPaused", "isRemoved"] { object.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(GhostProfile.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.revision == 24)
        #expect(!decoded.isNameCustom && !decoded.isTrainingPaused && !decoded.isRemoved)
    }

    @Test func managementFieldsRoundTrip() throws {
        var ghost = sample
        ghost.revision = 31
        ghost.isNameCustom = true
        ghost.isTrainingPaused = true
        ghost.isRemoved = true
        #expect(try JSONDecoder().decode(GhostProfile.self, from: JSONEncoder().encode(ghost)) == ghost)
    }
```

- [ ] **Step 2: Run, expect compile failure** - `swift test --package-path Packages/CatanAI --filter GhostProfileTests`

- [ ] **Step 3: Implement** - in `GhostProfile`: add stored vars with doc comments

```swift
    /// Bumped by every learned game, rename, reset, remove and pause toggle.
    /// The ladder accepts a ghost only when this goes up; it rides in the
    /// CloudKit record field still named `gamesLearned` (no schema change).
    public var revision: Int
    /// Set by the owner's rename; `LiveSync.refreshNames` then leaves `name` alone.
    public var isNameCustom: Bool
    /// The owner stopped training; finished games are skipped, never taught later.
    public var isTrainingPaused: Bool
    /// A tombstone: the owner removed this ghost. Kept so the removal syncs.
    public var isRemoved: Bool
```

init: add params `revision: Int? = nil, isNameCustom: Bool = false, isTrainingPaused: Bool = false, isRemoved: Bool = false`, assign `self.revision = revision ?? gamesLearned`. CodingKeys: add the four. `init(from:)`: after `gamesLearned`:

```swift
        revision = try values.decodeIfPresent(Int.self, forKey: .revision) ?? gamesLearned
        isNameCustom = try values.decodeIfPresent(Bool.self, forKey: .isNameCustom) ?? false
        isTrainingPaused = try values.decodeIfPresent(Bool.self, forKey: .isTrainingPaused) ?? false
        isRemoved = try values.decodeIfPresent(Bool.self, forKey: .isRemoved) ?? false
```

- [ ] **Step 4: Run, expect PASS** (same command).
- [ ] **Step 5: Commit** `feat(ai): ghost profiles carry a revision and management flags`

### Task 2: Sync compares revision

**Files:**
- Modify: `Settlers/Sync/CloudKitBackend.swift` (`prepareGhostUpload`, ~line 217)
- Modify: `Settlers/Sync/LiveSync.swift` (`uploadGhost` ~284, `downloadGhosts` ~365, `refreshNames` ~234)
- Test: `SettlersTests/CloudKitBackendTests.swift`, `SettlersTests/LiveSyncTests.swift`

**Interfaces:**
- Consumes: Task 1 fields.
- Produces: `static func LiveSync.accepts(_ incoming: GhostProfile, over local: GhostProfile?) -> Bool` (revision strictly higher).

- [ ] **Step 1: Failing tests** - in `CloudKitBackendTests`:

```swift
    /// A reset ghost has fewer games than the server's but a higher revision.
    @Test func aResetGhostWithAHigherRevisionUploadsOverMoreGames() throws {
        let server = CKRecord(recordType: "Ghost", recordID: CKRecord.ID(recordName: "ghost-jake"))
        server["gamesLearned"] = 30
        var reset = ghost(gamesLearned: 0)
        reset.revision = 31
        let upload = try #require(try CloudKitBackend.prepareGhostUpload(reset, existing: server))
        defer { try? FileManager.default.removeItem(at: upload.assetFile) }
        #expect(upload.record["gamesLearned"] as? Int == 31)
    }
```

in `LiveSyncTests` (pure helper, no backend):

```swift
    @Test func aGhostIsAcceptedOnlyAtAHigherRevision() {
        let base = GhostProfile(id: "jake", name: "Jake's Ghost", person: .anchored(at: .forMode(.classic)),
                                lambda: 0.01, gamesLearned: 30)
        var reset = base
        reset.gamesLearned = 0
        reset.revision = 31
        #expect(LiveSync.accepts(reset, over: base))
        #expect(!LiveSync.accepts(base, over: reset), "the server's old ghost must not undo a reset")
        #expect(LiveSync.accepts(base, over: nil))
    }
```

- [ ] **Step 2: Build tests, expect failure** (`accepts` undefined; upload returns nil).
- [ ] **Step 3: Implement**
  - `prepareGhostUpload`: compare and write `ghost.revision` instead of `ghost.gamesLearned` (keep the field name; comment why).
  - `LiveSync`: add

```swift
    /// The one rule every phone applies to a ghost from the server.
    static func accepts(_ incoming: GhostProfile, over local: GhostProfile?) -> Bool {
        incoming.revision > (local?.revision ?? -1)
    }
```

  - `downloadGhosts`: replace the `gamesLearned >` clause with `Self.accepts(ghost, over: stores.ghosts.ghost(id: ghost.id, includingRemoved: true))`.
  - `uploadGhost`: use `ghost(id: me, includingRemoved: true)`; compare/store `revision` in `ghostGamesUploadedByID` (keep the key; it now holds revisions).
  - `refreshNames`: `guard !ghost.isNameCustom, ...` before rewriting `name`.
- [ ] **Step 4: Run** `xcodebuild test ... -only-testing:SettlersTests/CloudKitBackendTests -only-testing:SettlersTests/LiveSyncTests`, expect PASS.
- [ ] **Step 5: Commit** `feat(sync): ghosts sync by revision so rename, reset and remove propagate`

### Task 3: GhostStore management operations

**Files:**
- Modify: `Settlers/Persistence/GhostStore.swift`
- Test: `SettlersTests/GhostStoreTests.swift`

**Interfaces:**
- Produces (all `throws` unless noted):
  - `ghost(id:includingRemoved:) -> GhostProfile?` (default `false`; tombstones invisible otherwise; `all()`/`pickable()` exclude tombstones)
  - `rename(_ id: String, to name: String)` - trims; throws `GhostStore.ManagementError.emptyName` if empty
  - `setTrainingPaused(_ id: String, _ paused: Bool)`
  - `reset(_ id: String, keepingOld: Bool) -> GhostProfile` (returns the fresh ghost)
  - `oldGhosts(of id: String) -> [GhostProfile]` (ids `"<id>~<n>"`, non-throwing)
  - `removeOld(_ oldID: String)`
  - `hiddenIDs() -> Set<String>` (non-throwing), `setHidden(_ id: String, _ hidden: Bool)`; `pickable()` excludes hidden
  - `archiveDirectory: URL` = `localDirectory/../GhostArchive`

- [ ] **Step 1: Failing tests** - append to `GhostStoreTests` (uses existing `fixture()`/`ghost(_:name:games:)`):

```swift
    @Test func renameIsCustomBumpsRevisionAndRefusesBlank() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try store.save(ghost("sam", name: "Sam's Ghost", games: 12))
        try store.rename("sam", to: "  The Wall  ")
        let renamed = try #require(store.ghost(id: "sam"))
        #expect(renamed.name == "The Wall" && renamed.isNameCustom && renamed.revision == 13)
        #expect(throws: GhostStore.ManagementError.emptyName) { try store.rename("sam", to: "   ") }
        #expect(store.ghost(id: "sam")?.name == "The Wall")
    }

    @Test func resetKeepsTheOldGhostAndStartsFresh() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try store.save(ghost("sam", name: "Sam's Ghost", games: 12))
        let fresh = try store.reset("sam", keepingOld: true)
        #expect(fresh.gamesLearned == 0 && fresh.decisionsLearned == 0 && fresh.revision == 13)
        #expect(store.ghost(id: "sam")?.gamesLearned == 0)
        let old = store.oldGhosts(of: "sam")
        #expect(old.map(\.id) == ["sam~1"] && old.first?.gamesLearned == 12)
        #expect(!store.pickable().contains { $0.id == "sam" }, "a fresh ghost leaves the picker until 10 games")
    }

    @Test func removingLeavesATombstoneThatResumeTreatsAsGone() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try store.save(ghost("sam", name: "Sam's Ghost", games: 12))
        _ = try store.reset("sam", keepingOld: false)
        try store.setRemoved("sam")
        #expect(store.ghost(id: "sam") == nil)
        #expect(store.ghost(id: "sam", includingRemoved: true)?.isRemoved == true)
        #expect(store.oldGhosts(of: "sam").isEmpty)
        #expect(!store.all().contains { $0.id == "sam" })
    }

    @Test func hiddenGhostsLeaveOnlyThePicker() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try store.save(ghost("sam", name: "Sam's Ghost", games: 12))
        try store.setHidden("sam", true)
        #expect(!store.pickable().contains { $0.id == "sam" })
        #expect(store.all().contains { $0.id == "sam" })
        try store.setHidden("sam", false)
        #expect(store.pickable().contains { $0.id == "sam" })
    }

    @Test func pauseBumpsRevision() throws {
        let (store, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try store.save(ghost("sam", name: "Sam's Ghost", games: 12))
        try store.setTrainingPaused("sam", true)
        #expect(store.ghost(id: "sam")?.isTrainingPaused == true)
        #expect(store.ghost(id: "sam")?.revision == 13)
    }
```

(`setRemoved(_ id:)` is part of the produced interface: marks `isRemoved = true`, `isTrainingPaused = true`, revision+1.)

- [ ] **Step 2: Run, expect compile failure** - `xcodebuild test ... -only-testing:SettlersTests/GhostStoreTests`
- [ ] **Step 3: Implement** in `GhostStore`:

```swift
    enum ManagementError: Error, Equatable { case emptyName, noSuchGhost }

    var archiveDirectory: URL {
        localDirectory.deletingLastPathComponent().appendingPathComponent("GhostArchive")
    }

    func ghost(id: String, includingRemoved: Bool) -> GhostProfile? { ... }  // existing body, then filter isRemoved unless includingRemoved
    // existing `ghost(id:)` becomes `ghost(id: id, includingRemoved: false)`

    /// Applies one owner edit as a new version, revision + 1.
    private func update(_ id: String, _ change: (inout GhostProfile) -> Void) throws -> GhostProfile {
        guard var ghost = ghost(id: id, includingRemoved: true) else { throw ManagementError.noSuchGhost }
        change(&ghost)
        ghost.revision += 1
        try save(ghost)
        return ghost
    }

    func rename(_ id: String, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ManagementError.emptyName }
        _ = try update(id) { $0.name = trimmed; $0.isNameCustom = true }
    }

    func setTrainingPaused(_ id: String, _ paused: Bool) throws {
        _ = try update(id) { $0.isTrainingPaused = paused; if !paused { $0.isRemoved = false } }
    }

    func setRemoved(_ id: String) throws {
        _ = try update(id) { $0.isRemoved = true; $0.isTrainingPaused = true }
    }

    /// Fresh start. The decision records stay under `id`: they are the
    /// "already taught" markers, so catch-up never re-teaches a pre-reset game.
    @discardableResult
    func reset(_ id: String, keepingOld: Bool) throws -> GhostProfile {
        guard let current = ghost(id: id, includingRemoved: true) else { throw ManagementError.noSuchGhost }
        if keepingOld {
            let n = (oldGhosts(of: id, includingRemoved: true).count) + 1
            var old = current
            old = GhostProfile(id: "\(id)~\(n)", name: "\(current.name) (old \(n))", person: current.person,
                               lambda: current.lambda, gamesLearned: current.gamesLearned,
                               decisionsLearned: current.decisionsLearned, civilization: current.civilization,
                               isNameCustom: true)
            try save(old)
        }
        try archiveVersions(of: id)
        var fresh = GhostProfile(id: id, name: current.name, person: .anchored(at: .forMode(.classic)),
                                 lambda: current.lambda, gamesLearned: 0, civilization: current.civilization,
                                 revision: current.revision + 1, isNameCustom: current.isNameCustom)
        fresh.isTrainingPaused = current.isTrainingPaused
        try save(fresh)
        return fresh
    }

    func oldGhosts(of id: String, includingRemoved: Bool = false) -> [GhostProfile] {
        localIDs().filter { $0.hasPrefix("\(id)~") }.compactMap { ghost(id: $0, includingRemoved: includingRemoved) }
    }

    /// An old ghost never syncs, so it is archived outright.
    func removeOld(_ oldID: String) throws {
        guard oldID.contains("~") else { throw ManagementError.noSuchGhost }
        try archiveVersions(of: oldID)
        try? FileManager.default.removeItem(at: localDirectory.appendingPathComponent(oldID))
    }

    /// Moves `v*.json` to `GhostArchive/<id>-<timestamp>/`; decisions stay.
    private func archiveVersions(of id: String) throws { ... }

    private var hiddenFile: URL { localDirectory.appendingPathComponent("hidden.json") }
    func hiddenIDs() -> Set<String> { (try? JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: hiddenFile))) ?? [] }
    func setHidden(_ id: String, _ hidden: Bool) throws { ... write sorted array ... }
```

  - `all()`: skip ghosts with `isRemoved`, and skip ids containing `"~"` only when `isRemoved` (old ghosts ARE listed, so they can be seated).
  - `pickable()`: also `!hiddenIDs().contains($0.id)`.
  - Add `isNameCustom`/`revision` params to the `GhostProfile` init call in `move(_:to:)` so a move keeps them.
  - `removeOld` deletes only the now-empty directory after archiving; versions are preserved in the archive.
- [ ] **Step 4: Run, expect PASS** (plus the existing `GhostStoreTests`).
- [ ] **Step 5: Commit** `feat(ghosts): rename, reset, remove, pause and hide in the ghost store`

### Task 4: Training honours pause; training status

**Files:**
- Modify: `Settlers/ViewModels/GhostTrainer.swift`
- Create: `Settlers/ViewModels/GhostTrainingStatus.swift`
- Test: `SettlersTests/GhostTrainerTests.swift`

**Interfaces:**
- Consumes: Task 3 `ghost(id:includingRemoved:)`.
- Produces: `GhostTrainer.skippedMarker(for match: UUID, ghost: String) -> URL`; `@MainActor @Observable final class GhostTrainingStatus { static let shared; private(set) var trainingIDs: Set<String> }` with `begin(_:)`/`end(_:)`.

- [ ] **Step 1: Failing test** - in `GhostTrainerTests` (uses existing `store()`/`game()`):

```swift
    /// Jake: pause when happy. A game played while paused is never taught,
    /// not even by launch catch-up after training is switched back on.
    @Test func aGamePlayedWhilePausedIsNeverTaught() throws {
        let (ghosts, root) = store(); defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        let trainer = GhostTrainer(store: ghosts)
        _ = try trainer.learn(match: UUID(), game: logged, human: human, personID: "sam", personName: "Sam")
        try ghosts.setTrainingPaused("sam", true)
        let paused = UUID()
        #expect(try trainer.learn(match: paused, game: logged, human: human, personID: "sam", personName: "Sam") == nil)
        try ghosts.setTrainingPaused("sam", false)
        #expect(try trainer.learn(match: paused, game: logged, human: human, personID: "sam", personName: "Sam") == nil)
        #expect(ghosts.ghost(id: "sam")?.gamesLearned == 1)
    }

    @Test func learningBumpsRevision() throws {
        let (ghosts, root) = store(); defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        let learned = try #require(try GhostTrainer(store: ghosts).learn(match: UUID(), game: logged, human: human,
                                                                         personID: "sam", personName: "Sam"))
        #expect(learned.revision == 1)
    }
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** in `learn(...)` after computing `id` and `record`:

```swift
        let skipped = Self.skippedMarker(for: match, ghost: id, store: store)
        guard !FileManager.default.fileExists(atPath: skipped.path) else { return nil }
        if let current = store.ghost(id: id, includingRemoved: true), current.isTrainingPaused {
            try FileManager.default.createDirectory(at: skipped.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: skipped)
            return nil
        }
```

  `previous` lookup uses `store.ghost(id: id)` (a tombstone is not trained from); after `learned.gamesLearned += 1` add `learned.revision = (store.ghost(id: id, includingRemoved: true)?.revision ?? 0) + 1`. Keep the custom name: only set `learned.name` when `!previous.isNameCustom`.

  `static func skippedMarker(for match: UUID, ghost: String, store: GhostStore) -> URL` = `store.localDirectory/<ghost>/skipped/<match>`.

  `GhostTrainingStatus.swift`:

```swift
import Observation

/// Which ghosts are mid-training right now, for the "Training now..." line.
@MainActor @Observable
final class GhostTrainingStatus {
    static let shared = GhostTrainingStatus()
    private(set) var trainingIDs: Set<String> = []
    func begin(_ id: String) { trainingIDs.insert(id) }
    func end(_ id: String) { trainingIDs.remove(id) }
}
```

  In `GhostTrainingQueue.learn`, wrap: `await MainActor.run { GhostTrainingStatus.shared.begin(personID) }` before and `end` after (make `learn` `async`; update its two callers in `GameViewModel+Ghosts.swift` and `catchUp` to `await`).
- [ ] **Step 4:** `xcodegen generate`; run `GhostTrainerTests`, `GhostTrainingQueueTests`, `GhostCompletionIsolationTests`; expect PASS.
- [ ] **Step 5: Commit** `feat(ghosts): pausing training skips games for good; publish training status`

### Task 5: Manage Ghosts screen

**Files:**
- Create: `Settlers/Views/ManageGhostsView.swift`
- Create: `Settlers/Models/GhostStatusText.swift`
- Modify: `Settlers/Views/InGameSettingsView.swift` (menu-mode Ghosts section above Your Data)
- Modify: `Settlers/Testing/AccessibilityID.swift` (`enum Ghosts`)
- Test: `SettlersTests/GhostStatusTextTests.swift`, `SettlersUITests/MainMenuFlowTests.swift`

**Interfaces:**
- Consumes: Tasks 3-4.
- Produces: `enum GhostStatusText { static func line(for: GhostProfile, isTraining: Bool) -> String }`.

- [ ] **Step 1: Failing unit test** `SettlersTests/GhostStatusTextTests.swift`:

```swift
import CatanAI
import Testing
@testable import Settlers

@Suite struct GhostStatusTextTests {
    private func ghost(games: Int, paused: Bool = false) -> GhostProfile {
        var g = GhostProfile(id: "me", name: "Me's Ghost", person: .anchored(at: .forMode(.classic)), lambda: 0.01, gamesLearned: games)
        g.isTrainingPaused = paused
        return g
    }

    @Test func eachStateReadsAsSpecified() {
        #expect(GhostStatusText.line(for: ghost(games: 3), isTraining: true) == "Training now...")
        #expect(GhostStatusText.line(for: ghost(games: 7), isTraining: false) == "Learning - 3 more games until others can play it")
        #expect(GhostStatusText.line(for: ghost(games: 9), isTraining: false) == "Learning - 1 more game until others can play it")
        #expect(GhostStatusText.line(for: ghost(games: 12), isTraining: false) == "Learning from every game")
        #expect(GhostStatusText.line(for: ghost(games: 12, paused: true), isTraining: false) == "Paused - your games are not being taught")
    }
}
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** `GhostStatusText.line`: paused first, then `isTraining`, then `remaining = GhostStore.minimumGamesToPlay - games` (singular "game" at 1), else "Learning from every game".

  `ManageGhostsView(store: GhostStore = .shared, me: String = PlayerDirectory.shared.me, onClose:)`: `SettingsChrome.screenBackground` + `ScrollView` of three `SettingsSectionHeader` sections:
  - **Your Ghost** (`store.ghost(id: me, includingRemoved: true)`; if nil or removed show "You have no ghost yet. Play a rated Classic game to start one." and, if removed, a "Start a new ghost" `GoldRowButton` -> `setTrainingPaused(me, false)` + `reset(me, keepingOld: false)`): name, status line (`GhostStatusText`, `GhostTrainingStatus.shared.trainingIDs.contains(me)`), "N games learned", a `PaintedChoiceRow` Training Off/On (identifier `AccessibilityID.Ghosts.training(isOn)`), buttons Rename / Reset / Remove (each through `ConfirmationPopupCard`; Rename uses an inline `TextField` + Save; errors shown as a red caption).
  - **Old Ghosts** (`store.oldGhosts(of: me)`): rows with Rename + Remove.
  - **Other Players' Ghosts** (`store.all()` minus `me` and `~` ids): rows with a Hide/Show toggle.
  After every action, `refresh()` re-reads the store (`@State var revision = 0` bumped to re-render), and kicks `Task { await LiveSync.shared?.sync() }` for own-ghost changes.

  In `InGameSettingsView` menu mode add a `ghostsSection` above `dataSection`: header "Ghosts", status line of the player's ghost, `GoldRowButton("Manage Ghosts", systemImage: "person.2.fill")` -> `@State isShowingGhosts` -> overlay `ManageGhostsView(onClose:)`.
- [ ] **Step 4: UI test** - add to `MainMenuFlowTests`:

```swift
    func testManageGhostsOpensFromSettings() {
        continueAfterFailure = false
        let app = launchResetApp()
        app.buttons["main-menu.settings"].tap()
        let manage = app.buttons["settings.manage-ghosts"]
        for _ in 0..<5 where !manage.isHittable { app.swipeUp() }
        manage.tap()
        XCTAssertTrue(app.otherElements["screen.manage-ghosts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You have no ghost yet. Play a rated Classic game to start one."].exists)
    }
```

- [ ] **Step 5:** `xcodegen generate`; run `GhostStatusTextTests` + `MainMenuFlowTests`; screenshot the screen (no recordings - disk); commit `feat(ui): manage ghosts - status, training toggle, rename, reset, remove, hide`.

### Task 6: Full verification

- [ ] `swift test --package-path Packages/CatanAI --filter Ghost` and `swift test --package-path Packages/CatanEngine`
- [ ] `xcodebuild test` on `SettlersTests` (whole bundle) with `-parallel-testing-enabled NO`; read `${PIPESTATUS[0]}`.
- [ ] `swiftlint --strict`
- [ ] Update `docs/live-sync.md` "Identity"/ghost section: revision rule, tombstones, custom names.
- [ ] Commit `docs(sync): ghosts sync by revision`.
