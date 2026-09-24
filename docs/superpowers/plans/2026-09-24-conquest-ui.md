# Conquest UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Conquest playable by a person in the app: start it from New Game, see who holds each hex on the board, buy army cards and commit them to hexes, then install it on Jake's phone.

**Architecture:** Plan 2 of 2; the engine, bots and price (any 3 cards) are done on this branch. The app adds one match setting (`MatchSetup.variant`), one drawing change (an owner-coloured ring and a strength badge on the number token, inside the existing board `Canvas`), two Build-popup rows (buy an army card; deploy), and one new board decision, `.deployArmy`, shaped exactly like the robber's: **tap a highlighted hex, pick cards from chips in the dock, confirm**. The decision's path is `[.tile(hex), .armyCards(set)]`, so the existing path-matching coordinator needs no new machinery, and the engine (`Conquest.deployMoves`) enumerates every card set so the coordinator still never invents a rule.

**Tech Stack:** SwiftUI, Swift 6.3, XcodeGen, swift-testing (app unit tests), XCUITest.

**Spec:** `docs/superpowers/specs/2026-09-23-conquest-mode-design.md` (App section; "Price revision").

**Worktree:** `~/Documents/Catan Game worktrees/conquest`, branch `feat/conquest-mode`. Never the primary checkout.

## Global Constraints

- **Deploying is tap-the-hex** (Jake, 2026-09-24): the board highlights deployable hexes in the robber's gold; tapping one puts the army-card chips in the dock; Confirm commits. No army popup.
- **Theme:** everything reuses existing chrome - `GoldRowButton` rows in Build, `DockActionButton`s, and army chips styled exactly like `DockVictimButton` (`TintedTextureBackground` in the actor's civilization tint, `FrameCornerRect`, `playerCardBorder`, the same selection border and mark). No new colours except the owner accent already used for pieces. The dock's height is fixed (`BottomRowMetrics.height`); the chips live in the slot the victim picker uses, so `BelowBoardInvarianceTests` must stay green.
- The ownership ring is the owner's `Civilization.accentColor` around the number token (Jake: "a simple approach"). Tribes get no ring. Every garrisoned hex shows its strength in a small badge by the token.
- `GameViewModel.swift` is 1,232 lines and `GameView.swift` 1,172; `swiftlint --strict` errors at 1,250. Add no code to `GameViewModel.swift`; add at most ~25 lines to `GameView.swift`. New code goes in new files.
- After adding any `.swift` file under `Settlers/` or `SettlersTests/`/`SettlersUITests/`, run `xcodegen generate` before building.
- Never pipe `xcodebuild` through `tail`/`grep`; redirect to a file and read `$?`.
- Build with `-derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/conquest"` (outside the tree; SwiftLint walks the filesystem).
- Simulator: `SIM=$(python3 scripts/select-qa-simulator.py)`. Quit Simulator and `xcrun simctl shutdown all` before any long run. Never drive the simulator with desktop-coordinate click tools.
- Commits: conventional, body says why, ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. **Do not push** until Task 5.

## Review Focus

1. **A card bought this turn.** It is in the hand but not playable; its chip must not appear, so it cannot be committed and fail. Tested in Task 3 (`deployMovesNeverOfferACardBoughtThisTurn`).
2. **A standard (non-Conquest) game.** No army rows in Build, no rings or badges, `.deployArmy` cannot begin. Tested in Task 3 (`aStandardGameCannotBeginADeploy`) and by the unchanged `NewGameModeFlowTests`.
3. **The preview sentence at the exact-zero boundary.** Committing exactly the garrison's strength empties the hex; the dock must say so, not "takes it". Tested in Task 4 (`ArmyPreviewTests.saysEmptyAtExactlyZero`).
4. **Duplicate strengths in one hand** (two 3s). Tapping the second 3 must select a second copy, and tapping a selected 3 must drop exactly one. Tested in Task 4 (`ArmyChipsTests.duplicateStrengthsToggleOneCopyAtATime`).
5. **An old saved match setup** (written before `variant`). Must resume as Standard. Tested in Task 1 (`ConquestSetupTests.aSetupSavedBeforeConquestResumesAsStandard`).

---

### Task 1: Conquest is a New Game choice

**Files:**
- Modify: `Settlers/Persistence/MatchSetup.swift` (field, init, decoder)
- Modify: `Settlers/ViewModels/GameViewModel.swift:388-395` (`makeInitialState`: pass `variant`) — one-line change, net 0 lines
- Modify: `Settlers/Views/NewGameSetupView.swift` (new `rulesRow`, `HelpTopic.rules`)
- Test: `SettlersTests/ConquestSetupTests.swift` (new)
- Test: `SettlersUITests/NewGameModeFlowTests.swift` (one new test)

**Interfaces:**
- Produces: `MatchSetup.variant: GameVariant` (default `.standard`); the started `GameState.variant` equals it.

- [ ] **Step 1: Write the failing tests**

`SettlersTests/ConquestSetupTests.swift`:

```swift
import Testing
import Foundation
import CatanEngine
@testable import Settlers

@MainActor @Suite struct ConquestSetupTests {
    @Test func aSetupSavedBeforeConquestResumesAsStandard() throws {
        let legacy = """
        {"seats":[{"index":0,"isHuman":true,"name":"Jake"},
                  {"index":1,"isHuman":false,"name":""},
                  {"index":2,"isHuman":false,"name":""},
                  {"index":3,"isHuman":false,"name":""}],
         "victoryPointTarget":10,"randomizedBoard":false,"randomizeSeatOrder":false}
        """
        let setup = try JSONDecoder().decode(MatchSetup.self, from: Data(legacy.utf8))
        #expect(setup.variant == .standard)
    }

    @Test func theChosenVariantSurvivesASaveAndReload() throws {
        var setup = MatchSetup.default(preferredName: "Jake", preferredCivilization: .medieval)
        setup.variant = .conquest
        let reloaded = try JSONDecoder().decode(MatchSetup.self, from: try JSONEncoder().encode(setup))
        #expect(reloaded.variant == .conquest)
    }

    @Test func startingAConquestSetupStartsAConquestGame() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConquestSetupTests.\(UUID().uuidString)")
        let defaults = UserDefaults(suiteName: "ConquestSetupTests.\(UUID().uuidString)")!
        let setupStore = MatchSetupStore()
        setupStore.defaults = defaults
        let model = GameViewModel(
            gameStore: GameStore(fileURL: root.appendingPathComponent("save.json")),
            civilizationStore: CivilizationAssignmentStore(fileURL: root.appendingPathComponent("civs.json")),
            matchSetupStore: setupStore,
            gameLogStore: GameLogStore(directoryURL: root.appendingPathComponent("logs"), maxKeptLogs: 2),
            gameStatsStore: GameStatsStore(fileURL: root.appendingPathComponent("stats.json"))
        )
        var setup = MatchSetup.default(preferredName: "Jake", preferredCivilization: .medieval)
        setup.variant = .conquest
        model.startNewGame(setup: setup)
        #expect(model.state.variant == .conquest)
        #expect(!model.state.garrisons.isEmpty, "tribes hold every producing hex")
        try? FileManager.default.removeItem(at: root)
    }
}
```

Append to `SettlersUITests/NewGameModeFlowTests.swift` (inside the class):

```swift
    /// Conquest is a rules layer over the board, chosen beside it.
    func testConquestStartsFromTheNewGameScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"]
        app.launch()
        app.buttons["main-menu.new-game"].tap()
        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: 5))
        app.buttons["Conquest"].tap()
        app.buttons["As Shown"].tap()
        app.buttons["new-game.start"].tap()
        assertOpeningBoard(in: app, vertexCount: 54)
    }
```

- [ ] **Step 2: Run to verify failure**

```bash
xcodegen generate
SIM=$(python3 scripts/select-qa-simulator.py)
xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/conquest" \
  -only-testing:SettlersTests/ConquestSetupTests > /tmp/t1-red.log 2>&1; echo EXIT=$?
```
Expected: `EXIT=65`, `value of type 'MatchSetup' has no member 'variant'` in the log.

- [ ] **Step 3: Add `MatchSetup.variant`**

In `MatchSetup.swift`, after `public var difficulty: BotDifficulty`:

```swift
    /// The rule layer - Standard or Conquest - over the chosen board. Stored with
    /// the match for the same reason `mode` is: a running game keeps its rules.
    public var variant: GameVariant
```

Init: add `variant: GameVariant = .standard` as the last parameter and `self.variant = variant`.
Decoder, after the `difficulty` line:

```swift
        // Absent in every setup written before Conquest. Those were standard games.
        variant = try container.decodeIfPresent(GameVariant.self, forKey: .variant) ?? .standard
```

- [ ] **Step 4: Start the game with it**

In `GameViewModel.makeInitialState`, change the `GameSetup.newGame(...)` call's last argument from `mode: setup.mode)` to `mode: setup.mode, variant: setup.variant)` — same line, no new lines.

- [ ] **Step 5: The New Game row**

In `NewGameSetupView.swift`, add `rulesRow` to `matchSettingsSection` directly after `modeRow`, add `case rules` to `HelpTopic`, and add:

```swift
    /// Conquest crosses every board, so it is its own row beside Game Mode
    /// rather than a third mode.
    private var rulesRow: some View {
        labelledChoice(
            label: "Rules",
            help: .rules,
            helpText: "Conquest: every hex starts held by a tribe. Army cards cost any 3 resource "
                + "cards; spend them on a hex your buildings touch to take it. Whoever holds a hex "
                + "collects all of it, plus one. Works on Classic and Vast.",
            caption: nil
        ) {
            PaintedChoiceRow(
                options: GameVariant.allCases,
                title: \.displayName,
                selection: setup.variant,
                isCompact: true,
                fontSize: SeatCardView.bodyTextSize,
                onSelect: { setup.variant = $0 }
            )
        }
    }
```

If the compiler reports `labelledChoice`'s `help:` switch as non-exhaustive, add the `.rules` case wherever `HelpTopic` is switched on, mirroring `.board`.

- [ ] **Step 6: Run to verify pass**

Re-run Step 2's command. Expected `EXIT=0`, 3 tests passed. Then:

```bash
xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/conquest" \
  -only-testing:SettlersUITests/NewGameModeFlowTests -only-testing:SettlersUITests/MainMenuFlowTests \
  -only-testing:SettlersUITests/NewGameKeyboardInvarianceTests > /tmp/t1-ui.log 2>&1; echo EXIT=$?
swiftlint --strict
```
Expected: `EXIT=0`; lint 0 violations. If `NewGameKeyboardInvarianceTests` fails because the screen grew a row, read its failure message: it measures positions, and a new row legitimately moves rows below it — fix the expectation only if the test's own comment says positions are relative; otherwise stop and report.

- [ ] **Step 7: Commit** — `feat(app): Conquest rules choice on the New Game screen`.

---

### Task 2: A QA fixture, then the ring and badge on the board

**Files:**
- Modify: `Settlers/QALaunchFlag.swift` (two cases)
- Create: `Settlers/Testing/GameViewModel+QAConquest.swift`
- Modify: `Settlers/Views/GameView.swift` (dispatch the fixture, beside `showRobberTargeting`, ~4 lines)
- Modify: `Settlers/Views/Board/TileView.swift` (`drawTile`/`drawNumberToken` take a `GarrisonMark?`)
- Modify: `Settlers/Views/Board/BoardView.swift:234-238` (`drawTiles` passes the mark)

**Interfaces:**
- Produces: `QALaunchFlag.showConquest` (`-qaShowConquest`), `QALaunchFlag.showDeployArmy` (`-qaShowDeployArmy`); `GameViewModel.qaPrepareConquestPosition()`; `TileDrawing.GarrisonMark { strength: Int; ownerColor: Color? }`.

- [ ] **Step 1: The fixture**

`QALaunchFlag.swift`, beside `showIncomingOffer`:

```swift
    /// A Conquest main turn: the human holds one hex, a rival holds another, the
    /// rest are tribes; the human has army cards and resources. For photographing
    /// the ownership rings and exercising a deploy.
    case showConquest = "-qaShowConquest"
    /// `-qaShowConquest` with the Deploy Army board decision already begun.
    case showDeployArmy = "-qaShowDeployArmy"
```

`Settlers/Testing/GameViewModel+QAConquest.swift`:

```swift
#if DEBUG
import CatanEngine

extension GameViewModel {
    /// Main-turn Conquest position on the standard board: the human settled on a
    /// 6 and a 9, holding the 9 at 6; seat 1 settled on the same 6 and holding a
    /// 5 elsewhere at 4; the human has army cards [2, 5] (the 5 bought this turn)
    /// and 5 of each resource.
    func qaPrepareConquestPosition() {
        let human = humanPlayer
        let rival = PlayerID(index: (human.index + 1) % state.players.count)
        var fixture = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4_310,
                                        playerCount: state.players.count, variant: .conquest)
        let tiles = fixture.board.tiles.sorted { $0.coordinate < $1.coordinate }
        let six = tiles.first { $0.numberToken == 6 }!
        let nine = tiles.first { $0.numberToken == 9 }!
        let five = tiles.first { $0.numberToken == 5 }!
        fixture.players[human.index].settlements.formUnion([
            fixture.board.corners(of: six.coordinate)[0], fixture.board.corners(of: nine.coordinate)[0],
        ])
        fixture.players[rival.index].settlements.formUnion([
            fixture.board.corners(of: six.coordinate)[3], fixture.board.corners(of: five.coordinate)[3],
        ])
        fixture.garrisons[nine.coordinate] = Garrison(owner: human, strength: 6)
        fixture.garrisons[five.coordinate] = Garrison(owner: rival, strength: 4)
        fixture.armyHands[human] = [2, 5]
        fixture.armyCardsBoughtThisTurn[human] = [5]
        fixture.armyHands[rival] = [3, 7]
        fixture.players[human.index].resources = Dictionary(uniqueKeysWithValues: Resource.allCases.map { ($0, 5) })
        for resource in Resource.allCases { fixture.bank[resource, default: 0] -= 5 }
        fixture.phase = .mainTurn(playerIndex: human.index)
        replaceStateForTesting(fixture, humanSeat: human)
    }
}
#endif
```

`GameView.swift`, inside the existing `#if DEBUG` block that checks `showRobberTargeting`, add before it:

```swift
            if QALaunchFlag.showConquest.isSet || QALaunchFlag.showDeployArmy.isSet {
                viewModel.qaPrepareConquestPosition()
            }
```

(Task 4 Step 5 adds the `showDeployArmy` begin call once `.deployArmy` exists.)

- [ ] **Step 2: Photograph the board before the change (the "red")**

```bash
xcodegen generate
xcodebuild -project Settlers.xcodeproj -scheme Settlers -destination "platform=iOS Simulator,id=$SIM" \
  -configuration Debug -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/conquest" build > /tmp/t2-build.log 2>&1; echo EXIT=$?
```
Then install and launch with `-qaAutoStart -qaShowConquest` and screenshot, following `.claude/skills/run-settlers/SKILL.md` exactly (it owns install/launch/screenshot). Expected: a normal-looking board — **no** rings or badges, although the state holds garrisons. This screenshot is the failing check.

- [ ] **Step 3: Draw the ring and badge**

In `TileView.swift` (`enum TileDrawing`), add:

```swift
    /// What the board shows about a Conquest garrison. `ownerColor` nil = a tribe:
    /// no ring, grey badge.
    struct GarrisonMark {
        let strength: Int
        let ownerColor: Color?
    }
```

Change `drawTile`'s signature to `static func drawTile(_ tile: Tile, geometry: HexGeometry, garrison: GarrisonMark? = nil, in context: GraphicsContext)` and its token call to `drawNumberToken(number, at: geometry.center(of: tile.coordinate), size: geometry.size, garrison: garrison, in: context)`.

Change `drawNumberToken` to take `garrison: GarrisonMark?` before `in context:` and append, after the number is drawn:

```swift
        guard let garrison else { return }
        if let owner = garrison.ownerColor {
            let ringRadius = radius * 1.14
            let ring = Path(ellipseIn: CGRect(x: point.x - ringRadius, y: point.y - ringRadius,
                                              width: ringRadius * 2, height: ringRadius * 2))
            context.stroke(ring, with: .color(owner), lineWidth: radius * 0.24)
        }
        let badgeRadius = radius * 0.46
        let badgeCenter = CGPoint(x: point.x + radius * 0.98, y: point.y + radius * 0.78)
        let badge = Path(ellipseIn: CGRect(x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius,
                                           width: badgeRadius * 2, height: badgeRadius * 2))
        context.fill(badge, with: .color(garrison.ownerColor ?? Color(white: 0.28)))
        context.stroke(badge, with: .color(.white.opacity(0.9)), lineWidth: 1)
        let strength = Text("\(garrison.strength)")
            .font(.system(size: badgeRadius * 1.2, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
        context.draw(context.resolve(strength), at: badgeCenter, anchor: .center)
```

In `BoardView.swift`, replace `drawTiles` with:

```swift
    private func drawTiles(geometry: HexGeometry, in context: GraphicsContext) {
        for tile in board.tiles {
            TileDrawing.drawTile(tile, geometry: geometry, garrison: garrisonMark(at: tile.coordinate), in: context)
        }
    }

    /// Conquest only; a standard game has no garrisons, so this is always nil there.
    private func garrisonMark(at hex: HexCoordinate) -> TileDrawing.GarrisonMark? {
        guard let garrison = state.garrisons[hex] else { return nil }
        return .init(strength: garrison.strength,
                     ownerColor: garrison.owner.map { playerIdentity($0).civilization.accentColor })
    }
```

- [ ] **Step 4: Photograph again (the "green")**

Rebuild (Step 2's command, `EXIT=0`), reinstall, relaunch with `-qaAutoStart -qaShowConquest`, screenshot. Expected, checked by reading the image at real size: the human's colour rings the 9, the rival's colour rings the 5, every other producing hex shows a grey badge with its pip count (5 on the 6 and 8, 1 on the 2 and 12), the desert shows nothing, and no badge is clipped or overlaps a settlement ring. Save both screenshots under `/tmp/` and name them in the commit body.

- [ ] **Step 5: Board invariance and lint**

```bash
xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/conquest" \
  -only-testing:SettlersUITests/BoardViewportInvarianceTests -only-testing:SettlersTests/BoardFitTests \
  -only-testing:SettlersTests/BoardLayeringTests > /tmp/t2-inv.log 2>&1; echo EXIT=$?
swiftlint --strict
```
Expected: `EXIT=0`, 0 violations. The marks draw inside the existing `Canvas`, so the board frame must not move.

- [ ] **Step 6: Commit** — `feat(board): Conquest ownership ring and garrison strength on the number token`.

---

### Task 3: Deploy is a board decision (engine + coordinator)

**Files:**
- Modify: `Packages/CatanEngine/Sources/CatanEngine/Conquest.swift` (`deployMoves`)
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/ConquestMoveTests.swift` (append)
- Modify: `Settlers/ViewModels/BoardDecisionCoordinator.swift` (intent, target, candidates, path, select, presentation fields)
- Test: `SettlersTests/BoardDecisionCoordinatorTests.swift` (append, reusing its private `context(_:)`)

**Interfaces:**
- Produces: `Conquest.deployMoves(for: PlayerID, in: GameState) -> [GameMove]`; `BoardDecisionIntent.deployArmy`; `BoardTarget.armyCards([Int])`; `BoardDecisionPresentation.legalArmyCards: [Int]` (the playable hand, ascending) and `.selectedArmyCards: [Int]` (ascending).

- [ ] **Step 1: Engine test**

Append to `ConquestMoveTests.swift`:

```swift
@Test func deployMovesOfferEveryCardSetOnEveryReachableHex() {
    let (state, tile) = conquest(hand: [3, 3, 5])
    let sets = Set(Conquest.deployMoves(for: state.players[0].id, in: state).compactMap { move -> [Int]? in
        guard case .deployArmy(let hex, let strengths) = move, hex == tile.coordinate else { return nil }
        return strengths
    })
    #expect(sets == [[3], [5], [3, 3], [3, 5], [3, 3, 5]])
}

@Test func deployMovesNeverOfferACardBoughtThisTurn() {
    var (state, _) = conquest(hand: [2, 5])
    state.armyCardsBoughtThisTurn[state.players[0].id] = [5]
    let offered = Conquest.deployMoves(for: state.players[0].id, in: state).allSatisfy {
        if case .deployArmy(_, let strengths) = $0 { return !strengths.contains(5) } else { return false }
    }
    #expect(offered)
}
```

Run `swift test --package-path Packages/CatanEngine --filter deployMoves` → compile failure (`no member 'deployMoves'`).

- [ ] **Step 2: Engine implementation**

Append inside `enum Conquest`:

```swift
    /// Every deploy `player` could make now: each reachable hex x every distinct
    /// set of its playable cards. `legalMoves` lists a bounded few; a UI that lets
    /// the player pick any set asks here, so the engine stays the authority on
    /// what may be committed. ponytail: 2^n in distinct cards held - fine for
    /// real hands; cap it if hands ever reach the dozens.
    public static func deployMoves(for player: PlayerID, in state: GameState) -> [GameMove] {
        let counts = Dictionary(grouping: playableCards(for: player, in: state), by: { $0 }).mapValues(\.count)
        var sets: [[Int]] = [[]]
        for strength in counts.keys.sorted() {
            sets = sets.flatMap { base in (0...counts[strength]!).map { base + Array(repeating: strength, count: $0) } }
        }
        let chosen = sets.filter { !$0.isEmpty }
        return state.board.tiles.map(\.coordinate).sorted()
            .filter { canDeploy(to: $0, by: player, in: state) }
            .flatMap { hex in chosen.map { GameMove.deployArmy(to: hex, strengths: $0) } }
    }
```

Run the engine suite → all pass. Commit `feat(engine): Conquest.deployMoves - every card set a player may commit`.

- [ ] **Step 3: Coordinator tests**

Append inside `BoardDecisionCoordinatorTests` (it already has `context(_:)` and `actor = PlayerID(index: 0)`):

```swift
    private func conquestTurn(hand: [Int]) -> (GameState, HexCoordinate) {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4_310, variant: .conquest)
        let six = state.board.tiles.sorted { $0.coordinate < $1.coordinate }.first { $0.numberToken == 6 }!
        state.players[0].settlements.insert(fixture.board.corners(of: six.coordinate)[0])
        state.armyHands[actor] = hand
        state.phase = .mainTurn(playerIndex: 0)
        return (state, six.coordinate)
    }

    @Test func deployingIsTapAHexThenChooseCards() throws {
        let (state, six) = conquestTurn(hand: [2, 5])
        var coordinator = BoardDecisionCoordinator()
        #expect(coordinator.begin(.deployArmy, with: context(state)))
        let begun = try #require(coordinator.presentation)
        #expect(begun.legalTiles.contains(six))
        #expect(!begun.canConfirm)

        #expect(coordinator.select(.tile(six)))
        #expect(coordinator.presentation?.legalArmyCards == [2, 5])
        #expect(coordinator.presentation?.canConfirm == false, "a hex alone is not a deploy")

        #expect(coordinator.select(.armyCards([2, 5])))
        #expect(coordinator.presentation?.selectedArmyCards == [2, 5])
        #expect(coordinator.confirmableMove == .deployArmy(to: six, strengths: [2, 5]))

        #expect(coordinator.select(.armyCards([])))
        #expect(coordinator.confirmableMove == nil, "deselecting every card un-stages the deploy")
    }

    @Test func aCardSetTheHandCannotMakeIsRefused() {
        let (state, six) = conquestTurn(hand: [2, 5])
        var coordinator = BoardDecisionCoordinator()
        _ = coordinator.begin(.deployArmy, with: context(state))
        _ = coordinator.select(.tile(six))
        #expect(!coordinator.select(.armyCards([9])))
        #expect(!coordinator.select(.armyCards([2, 2])))
    }

    @Test func aStandardGameCannotBeginADeploy() {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4_310)
        state.phase = .mainTurn(playerIndex: 0)
        var coordinator = BoardDecisionCoordinator()
        #expect(!coordinator.begin(.deployArmy, with: context(state)))
    }
```

Run:
```bash
xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/conquest" \
  -only-testing:SettlersTests/BoardDecisionCoordinatorTests > /tmp/t3-red.log 2>&1; echo EXIT=$?
```
Expected `EXIT=65`: `type 'BoardDecisionIntent' has no member 'deployArmy'`.

- [ ] **Step 4: Coordinator implementation**

In `BoardDecisionCoordinator.swift`:

1. `BoardDecisionIntent`: add `case deployArmy`; in `canCancel` add it to the `true` list.
2. `BoardTarget`: add `case armyCards([Int])` with a doc line "Conquest: the chosen set of army-card strengths, ascending."
3. `BoardDecisionPresentation`: add
   ```swift
   /// Conquest: the actor's playable army cards, ascending; empty for other intents.
   public var legalArmyCards: [Int] = []
   /// Conquest: the cards chosen so far, ascending.
   public var selectedArmyCards: [Int] = []
   ```
   and in `presentation`, set them after constructing (the struct's memberwise init keeps working because both have defaults):
   ```swift
        var result = BoardDecisionPresentation( /* existing arguments unchanged */ )
        if draft.intent == .deployArmy {
            result.legalArmyCards = draft.candidates.compactMap { path(for: $0, intent: .deployArmy)?.last?.armyCards }
                .max { $0.count < $1.count } ?? []
            result.selectedArmyCards = draft.selection.dropFirst().first?.armyCards ?? []
        }
        return result
   ```
4. `candidateMoves`: before the existing `return`, add
   ```swift
        if intent == .deployArmy {
            guard case .mainTurn = context.state.phase else { return [] }
            return Conquest.deployMoves(for: context.actor, in: context.state)
        }
   ```
5. `select(_:in:)`: add `case .deployArmy: return selectArmy(target, in: &draft)` and
   ```swift
    private func selectArmy(_ target: BoardTarget, in draft: inout Draft) -> Bool {
        switch target {
        case .tile where firstTargets(in: draft).contains(target):
            draft.selection = [target]
            return true
        case .armyCards(let cards):
            guard let hex = draft.selection.first, hex.tile != nil else { return false }
            if cards.isEmpty { draft.selection = [hex]; return true }
            guard nextTargets(in: draft, after: 1).contains(target) else { return false }
            draft.selection = [hex, target]
            return true
        default:
            return false
        }
    }
   ```
6. `path(for:intent:)`: add `case (.deployArmy, .deployArmy(let hex, let strengths)): return [.tile(hex), .armyCards(strengths)]`.
7. Private `BoardTarget` extension: `var armyCards: [Int]? { if case .armyCards(let value) = self { value } else { nil } }`.

Every other `switch` over `BoardDecisionIntent` the compiler now names (dock title/detail/confirmTitle, piece cradle) gets a `.deployArmy` case in Task 4; to compile this task alone, add them now with the Task 4 values.

- [ ] **Step 5:** Re-run Step 3's command → `EXIT=0`. Commit `feat(app): deployArmy board decision - tap a hex, then a card set`.

---

### Task 4: Deploy in the dock, army rows in Build

**Files:**
- Create: `Settlers/ViewModels/GameViewModel+Conquest.swift` (`ArmyPreview`, `ArmyChips`, `armyDeploymentPreview`)
- Test: `SettlersTests/ArmyUITests.swift` (new; `ArmyPreviewTests`, `ArmyChipsTests`)
- Modify: `Settlers/Views/GameActionPanels.swift` (army picker + `DockArmyCardButton`, strings)
- Modify: `Settlers/Views/BuildPopupView.swift` (two rows)
- Modify: `Settlers/Views/Board/BoardView.swift:241` (gold highlight for `.deployArmy` too)
- Modify: `Settlers/Views/GameView.swift` (two dock arguments; QA begin; ~5 lines)
- Modify: `Settlers/Testing/AccessibilityID.swift`
- Test: `SettlersUITests/ConquestFlowTests.swift` (new)

- [ ] **Step 1: Tests for the pure parts**

`SettlersTests/ArmyUITests.swift`:

```swift
import Testing
import CatanEngine
@testable import Settlers

private let name: (PlayerID) -> String = { "P\($0.index + 1)" }
private let me = PlayerID(index: 0)

@Suite struct ArmyPreviewTests {
    @Test func namesEachOutcome() {
        #expect(ArmyPreview.sentence(total: 9, against: Garrison(owner: nil, strength: 5), me: me, name: name)
            == "Takes it, holding at 4")
        #expect(ArmyPreview.sentence(total: 2, against: Garrison(owner: PlayerID(index: 1), strength: 5), me: me, name: name)
            == "Leaves P2 at 3")
        #expect(ArmyPreview.sentence(total: 3, against: Garrison(owner: me, strength: 5), me: me, name: name)
            == "Reinforces to 8")
        #expect(ArmyPreview.sentence(total: 1, against: nil, me: me, name: name) == "Takes it, holding at 1")
    }

    @Test func saysEmptyAtExactlyZero() {
        #expect(ArmyPreview.sentence(total: 5, against: Garrison(owner: nil, strength: 5), me: me, name: name)
            == "Leaves it empty")
    }
}

@Suite struct ArmyChipsTests {
    @Test func duplicateStrengthsToggleOneCopyAtATime() {
        let hand = [3, 3, 5]
        var selected: [Int] = []
        selected = ArmyChips.toggle(1, hand: hand, selected: selected)     // either 3 selects "a 3"
        #expect(selected == [3])
        #expect(ArmyChips.isOn(0, hand: hand, selected: selected))
        #expect(!ArmyChips.isOn(1, hand: hand, selected: selected))
        selected = ArmyChips.toggle(1, hand: hand, selected: selected)
        #expect(selected == [3, 3])
        selected = ArmyChips.toggle(0, hand: hand, selected: selected)
        #expect(selected == [3])
    }
}
```

Run `-only-testing:SettlersTests/ArmyPreviewTests -only-testing:SettlersTests/ArmyChipsTests` → `EXIT=65`, `cannot find 'ArmyPreview'`.

- [ ] **Step 2: `GameViewModel+Conquest.swift`**

```swift
import CatanEngine

/// The dock's one line about what the chosen cards will do, from the engine's rule.
enum ArmyPreview {
    static func sentence(total: Int, against current: Garrison?, me: PlayerID, name: (PlayerID) -> String) -> String {
        if let current, current.owner == me { return "Reinforces to \(current.strength + total)" }
        guard let after = Conquest.outcome(of: total, against: current, by: me) else { return "Leaves it empty" }
        if after.owner == me { return "Takes it, holding at \(after.strength)" }
        return after.owner.map { "Leaves \(name($0)) at \(after.strength)" } ?? "Leaves the tribe at \(after.strength)"
    }
}

/// Chip toggling for a hand that may hold the same strength twice: chip `index`
/// is "on" while fewer copies of its strength sit before it than are selected.
enum ArmyChips {
    static func isOn(_ index: Int, hand: [Int], selected: [Int]) -> Bool {
        let value = hand[index]
        return hand[..<index].filter { $0 == value }.count < selected.filter { $0 == value }.count
    }

    static func toggle(_ index: Int, hand: [Int], selected: [Int]) -> [Int] {
        var next = selected
        if isOn(index, hand: hand, selected: selected), let existing = next.firstIndex(of: hand[index]) {
            next.remove(at: existing)
        } else {
            next.append(hand[index])
        }
        return next.sorted()
    }
}

@MainActor
extension GameViewModel {
    /// The dock's title while choosing army cards, or nil outside a deploy.
    public var armyDeploymentPreview: String? {
        guard let decision = boardDecisionPresentation, decision.intent == .deployArmy,
              let hex = decision.selectedTile else { return nil }
        let total = decision.selectedArmyCards.reduce(0, +)
        guard total > 0 else { return "Choose army cards" }
        return ArmyPreview.sentence(total: total, against: state.garrisons[hex], me: humanPlayer,
                                    name: { self.playerIdentity(for: $0).displayName })
    }
}
```

Run Step 1's tests → `EXIT=0`.

- [ ] **Step 3: The dock**

In `GameActionPanels.swift`:

1. `BoardDecisionDockView` gains `let armyPreview: String?` and `let onSelectArmyCards: ([Int]) -> Void`; init parameters `armyPreview: String? = nil, onSelectArmyCards: @escaping ([Int]) -> Void = { _ in }` (defaulted, so every existing call site compiles).
2. `messageOrVictims`:
   ```swift
        if presentation.requiresArmyChoice {
            armyPicker
        } else if presentation.requiresVictimChoice {
            victimPicker
        } else {
            decisionMessage
        }
   ```
3. Add, beside `victimPicker`:
   ```swift
    private var armyPicker: some View {
        let actor = playerIdentity(presentation.actor)
        let hand = presentation.legalArmyCards
        return VStack(alignment: .leading, spacing: 2) {
            Text(presentation.errorMessage ?? armyPreview ?? "Choose army cards")
                .font(.system(.caption2, design: .serif, weight: .bold))
                .foregroundStyle(presentation.errorMessage == nil ? CatanTheme.onWaterText : Color.red)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier(AccessibilityID.Army.preview)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Layout.victimSpacing) {
                    ForEach(hand.indices, id: \.self) { index in
                        DockArmyCardButton(
                            strength: hand[index],
                            civilization: actor.civilization,
                            isSelected: ArmyChips.isOn(index, hand: hand, selected: presentation.selectedArmyCards),
                            action: { onSelectArmyCards(ArmyChips.toggle(index, hand: hand, selected: presentation.selectedArmyCards)) }
                        )
                        .accessibilityIdentifier(AccessibilityID.Army.card(index))
                    }
                }
            }
        }
    }
   ```
4. Add a chip view after `DockVictimButton`, copying its chrome so the two read as one family:
   ```swift
/// One army card in the deploy dock. Same chrome as `DockVictimButton` - tinted
/// civilization texture, notched frame, painted border, selection mark - so the
/// robber and army choosers read as one family. Narrower: it carries one number.
private struct DockArmyCardButton: View {
    let strength: Int
    let civilization: Civilization
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 10, weight: .bold))
                Text("\(strength)").font(.system(size: 20, weight: .heavy, design: .serif))
            }
            .frame(width: Layout.armyCardWidth, height: Layout.victimHeight)
            .background(TintedTextureBackground(tint: civilization.cardBackgroundColor(active: true)))
            .clipShape(FrameCornerRect(cornerRadius: 8, notchScale: 0.7))
            .playerCardBorder(color: civilization.accentColor, cornerRadius: 8, lineWidth: 2)
            .overlay {
                if isSelected {
                    FrameCornerRect(cornerRadius: 8, notchScale: 0.7)
                        .stroke(CatanTheme.cityPennantGold, lineWidth: 3)
                }
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Army card, strength \(strength)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
   ```
   Before writing the overlay, read `DockVictimButton`'s `selectionBorder`/`selectionMark` and copy them verbatim if they differ from the above - matching them exactly is the requirement.
5. `Layout`: `static let armyCardWidth: CGFloat = 38`.
6. `BoardDecisionPresentation` private extension: `var requiresArmyChoice: Bool { intent == .deployArmy && selectedTile != nil }`; `title`: `case .deployArmy: "Deploy army"`; `detail`: `case .deployArmy: selectedTile == nil ? "Tap a hex your buildings touch." : "Choose cards, then commit."`; `confirmTitle`: `case .deployArmy: "Commit"`. Where the clear button switches on `requiresVictimChoice` (its title, width, visible title and icon), use `requiresVictimChoice || requiresArmyChoice`, so Clear reads "Change territory" after a hex is chosen, exactly as for the robber. The piece cradle shows nothing for `.deployArmy`.

- [ ] **Step 4: Board highlight**

`BoardView.swift:241`: `guard let decision, decision.intent.isRobber || decision.intent == .deployArmy else { return }`. (Tile taps already work for any decision with `legalTiles`, via `BoardDecisionInteractionLayer`.)

- [ ] **Step 5: Build rows, dock wiring, QA begin**

`BuildPopupView`, after the Dev Card row:

```swift
                    if viewModel.state.variant == .conquest {
                        let me = viewModel.humanPlayer
                        let hand = viewModel.state.armyHands[me, default: []].sorted()
                        GoldRowButton(
                            title: "Army Card",
                            subtitle: (hand.isEmpty ? "No cards" : "Yours: " + hand.map(String.init).joined(separator: ", "))
                                + " · \(viewModel.state.armyDeck.count) left",
                            systemImage: "shield.lefthalf.filled",
                            iconColor: .red,
                            isEnabled: legalMoves.contains(.buyArmyCard),
                            trailing: {
                                Text("Any 3").font(.caption2.bold()).foregroundStyle(CatanTheme.cityPennantGold)
                            },
                            action: { perform(.buyArmyCard) }
                        )
                        .accessibilityIdentifier(AccessibilityID.Build.armyCard)
                        GoldRowButton(
                            title: "Deploy Army",
                            subtitle: "Tap a hex to take or hold it",
                            systemImage: "flag.fill",
                            iconColor: .red,
                            isEnabled: !Conquest.deployMoves(for: me, in: viewModel.state).isEmpty,
                            action: { beginBoardDecision(.deployArmy, pieceName: "army") }
                        )
                        .accessibilityIdentifier(AccessibilityID.Build.deployArmy)
                    }
```

`AccessibilityID`: in `Build` add `static let armyCard = "build.army-card"` and `static let deployArmy = "build.deploy-army"`; add
```swift
    enum Army {
        static let preview = "army.preview"
        static func card(_ index: Int) -> String { "army.card.\(index)" }
    }
```

`GameView`: where `BoardDecisionDockView(` is constructed, add the two arguments `armyPreview: viewModel.armyDeploymentPreview,` and `onSelectArmyCards: { _ = viewModel.selectBoardTarget(.armyCards($0)) },`. In the Task 2 QA dispatch add, after `qaPrepareConquestPosition()`:
```swift
                if QALaunchFlag.showDeployArmy.isSet { _ = viewModel.beginBoardDecision(.deployArmy) }
```

`wc -l Settlers/Views/GameView.swift` must stay under 1,240.

- [ ] **Step 6: UI test that taps the hex**

`SettlersUITests/ConquestFlowTests.swift`:

```swift
import XCTest

/// Deploying is tap-a-hex: from Build, Deploy Army; tap a highlighted hex; pick
/// the 2 in the dock; the preview names the outcome; Commit lands it.
@MainActor
final class ConquestFlowTests: XCTestCase {
    func testDeployingByTappingAHex() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaShowConquest"]
        app.launch()
        XCTAssertTrue(app.buttons["Build"].waitForExistence(timeout: 10))
        app.buttons["Build"].tap()
        app.buttons["build.deploy-army"].tap()
        let hex = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.tile.")).firstMatch
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        hex.tap()
        let two = app.buttons["army.card.0"]
        XCTAssertTrue(two.waitForExistence(timeout: 5))
        two.tap()
        XCTAssertNotEqual(app.staticTexts["army.preview"].label, "Choose army cards")
        let commit = app.buttons["board-decision.confirm"]
        XCTAssertTrue(commit.isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "conquest-deploy-dock"
        shot.lifetime = .keepAlways
        add(shot)
        commit.tap()
        XCTAssertTrue(app.buttons["Build"].waitForExistence(timeout: 5), "the dock gave way to the action row")
    }
}
```

(If the Build button's identifier is not its label, use the one `DevelopmentCardFlowTests` taps.)

```bash
xcodegen generate
xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/conquest" \
  -only-testing:SettlersUITests/ConquestFlowTests -only-testing:SettlersUITests/BelowBoardInvarianceTests \
  -only-testing:SettlersUITests/DevelopmentCardFlowTests -only-testing:SettlersTests/BoardDecisionCoordinatorTests \
  -only-testing:SettlersTests/BoardDecisionViewModelTests > /tmp/t4-ui.log 2>&1; echo EXIT=$?
swiftlint --strict
```
Expected `EXIT=0`; lint clean. Open the `conquest-deploy-dock` attachment and compare it side by side with a robber-victim dock screenshot (`-qaAutoStart -qaShowRobberVictimPicker` via run-settlers): same fonts, frame, tint, spacing. Any visible mismatch is a defect to fix before committing.

- [ ] **Step 7: Commit** — `feat(app): deploy armies by tapping a hex; army rows in Build`.

---

### Task 5: Play it for real

**Files:** none unless a defect is found.

- [ ] **Step 1:** Follow `.claude/skills/play-settlers/SKILL.md` to play a Conquest game on the simulator from the real New Game screen (no QA flags): complete setup, take a tribe hex with the starting card, buy a card, end turns until a bot deploys, and screenshot a board with at least two rings of different colours.
- [ ] **Step 2:** Repeat Step 1's first deploy on **Vast** (choose Vast + Conquest), and screenshot. The question is legibility of badges on 61 hexes at phone size; if badges collide, record it rather than fixing it here.
- [ ] **Step 3:** Write what was seen, with screenshot paths, into the commit body of an empty commit only if nothing needed fixing: `git commit --allow-empty -m "test(app): Conquest played end to end on Classic and Vast"`. Any defect found gets its own failing test and fix first.

---

### Task 6: Land it and put it on Jake's phone

- [ ] **Step 1:** `git fetch origin && git rebase origin/main` in the worktree; resolve conflicts; re-run `swift test --package-path Packages/CatanEngine` and `swiftlint --strict`.
- [ ] **Step 2:** Quit Simulator, `xcrun simctl shutdown all`, then **ask Jake before pushing** — the push runs the ~50-minute gate and lands on `main`: `git push origin HEAD:main`. The pre-push hook is the full verification.
- [ ] **Step 3:** Install on Jake's phone with the `run-settlers` skill's device path (it signs to team `KDM65HE483`, which is Jake's). Jake must have the phone connected and unlocked.
- [ ] **Step 4:** After it lands, clean up exactly as CLAUDE.md's "Concurrent agents" section says: remove the worktree, delete the branch, `reset --hard origin/main` in the primary checkout.
