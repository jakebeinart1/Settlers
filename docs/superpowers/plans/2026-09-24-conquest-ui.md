# Conquest UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Conquest playable by a person in the app: start it from New Game, see who holds each hex on the board, buy army cards and commit them to hexes, then install it on Jake's phone.

**Architecture:** Plan 2 of 2; the engine, bots and price (any 3 cards) are done on this branch. The app adds one match setting (`MatchSetup.variant`), one drawing change (an owner-coloured ring and a strength badge on the number token, inside the existing board `Canvas`), and one popup (`ArmyPopupView`) reached from a new row in the Build popup. The popup commits through the existing `GameViewModel.apply(_:)`, so it needs no new view-model code and no change to the board-decision coordinator. Everything that decides what the popup shows lives in a pure `ArmyPlan` enum, so it is unit-tested without a view.

**Tech Stack:** SwiftUI, Swift 6.3, XcodeGen, swift-testing (app unit tests), XCUITest.

**Spec:** `docs/superpowers/specs/2026-09-23-conquest-mode-design.md` (App section; "Price revision").

**Worktree:** `~/Documents/Catan Game worktrees/conquest`, branch `feat/conquest-mode`. Never the primary checkout.

## Global Constraints

- **Deliberate deviation from the spec, for Jake to confirm in review:** the spec says "tap a hex, pick cards, confirm" via the board-decision pattern. This plan picks the hex from a **list inside the Army popup** instead. The board-decision coordinator selects board targets only; choosing a *set of cards* is not a target, and bolting a card picker onto the fixed-height dock risks `BelowBoardInvarianceTests`. The list is the smallest thing that works; the code carries a `ponytail:` note naming the upgrade.
- The ownership ring is the owner's `Civilization.accentColor` around the number token (Jake: "a simple approach"). Tribes get no ring. Every garrisoned hex shows its strength in a small badge by the token.
- `GameViewModel.swift` is 1,232 lines and `GameView.swift` 1,172; `swiftlint --strict` errors at 1,250. Add no code to `GameViewModel.swift`; add at most ~25 lines to `GameView.swift`. New code goes in new files.
- After adding any `.swift` file under `Settlers/` or `SettlersTests/`/`SettlersUITests/`, run `xcodegen generate` before building.
- Never pipe `xcodebuild` through `tail`/`grep`; redirect to a file and read `$?`.
- Build with `-derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/conquest"` (outside the tree; SwiftLint walks the filesystem).
- Simulator: `SIM=$(python3 scripts/select-qa-simulator.py)`. Quit Simulator and `xcrun simctl shutdown all` before any long run. Never drive the simulator with desktop-coordinate click tools.
- Commits: conventional, body says why, ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. **Do not push** until Task 5.

## Review Focus

1. **A card bought this turn.** It is in the hand but not playable; the popup must show it as not selectable, not let it be committed and fail. Tested in Task 3 (`ArmyPlanTests.cardsBoughtThisTurnAreNotOffered`).
2. **A standard (non-Conquest) game.** No Army row in Build, no rings or badges on the board. Tested in Task 3 (`ArmyPlanTests.aStandardGameOffersNoArmy`) and by the unchanged `NewGameModeFlowTests`.
3. **The preview sentence at the exact-zero boundary.** Committing exactly the garrison's strength empties the hex; the popup must say so, not "takes it". Tested in Task 3 (`ArmyPlanTests.previewSaysEmptyAtExactlyZero`).
4. **A human who touches no producing hex** (possible only in fixtures, never in a real game past setup). The hex list is empty and Commit stays disabled; no crash. Tested in Task 3 (`ArmyPlanTests.noReachableHexMeansNoOptions`).
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
- Produces: `QALaunchFlag.showConquest` (`-qaShowConquest`), `QALaunchFlag.showArmyPopup` (`-qaShowArmyPopup`); `GameViewModel.qaPrepareConquestPosition()`; `TileDrawing.GarrisonMark { strength: Int; ownerColor: Color? }`.

- [ ] **Step 1: The fixture**

`QALaunchFlag.swift`, beside `showIncomingOffer`:

```swift
    /// A Conquest main turn: the human holds one hex, a rival holds another, the
    /// rest are tribes; the human has army cards and resources. For photographing
    /// the ownership rings and exercising the Army popup.
    case showConquest = "-qaShowConquest"
    /// `-qaShowConquest` with the Army popup already open.
    case showArmyPopup = "-qaShowArmyPopup"
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
            HexGeometry.corners(of: six.coordinate)[0], HexGeometry.corners(of: nine.coordinate)[0],
        ])
        fixture.players[rival.index].settlements.formUnion([
            HexGeometry.corners(of: six.coordinate)[3], HexGeometry.corners(of: five.coordinate)[3],
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
            if QALaunchFlag.showConquest.isSet || QALaunchFlag.showArmyPopup.isSet {
                viewModel.qaPrepareConquestPosition()
                showArmyPopup = QALaunchFlag.showArmyPopup.isSet
            }
```

(`showArmyPopup` is declared in Task 3. Until then, write only the `qaPrepareConquestPosition()` line; Task 3 Step 5 adds the second.)

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

### Task 3: The Army popup

**Files:**
- Create: `Settlers/Views/ArmyPopupView.swift` (`ArmyPlan` + `ArmyPopupView`)
- Modify: `Settlers/Views/BuildPopupView.swift` (Army row, `onOpenArmy` callback)
- Modify: `Settlers/Views/GameView.swift` (`showArmyPopup` state and presentation; ~15 lines)
- Modify: `Settlers/Testing/AccessibilityID.swift` (`Build.army`, `enum Army`)
- Test: `SettlersTests/ArmyPlanTests.swift` (new)

**Interfaces:**
- Consumes: `qaPrepareConquestPosition()`, `QALaunchFlag.showArmyPopup` (Task 2).
- Produces: `enum ArmyPlan` with `hexOptions(in:for:) -> [ArmyPlan.HexOption]`, `playableCards(in:for:) -> [Int]`, `label(for:me:name:) -> String`, `preview(total:against:me:name:) -> String`, `rivalSummary(in:me:name:) -> String`; `ArmyPopupView(viewModel:onDismiss:)`; `BuildPopupView(viewModel:onDismiss:onOpenArmy:)`.

- [ ] **Step 1: Write the failing tests**

`SettlersTests/ArmyPlanTests.swift`:

```swift
import Testing
import CatanEngine
@testable import Settlers

/// Seat 0 settled on the first 6, holding [2, 5] with the 5 bought this turn.
private func position(variant: GameVariant = .conquest) -> (GameState, HexCoordinate) {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4_310, variant: variant)
    let six = state.board.tiles.sorted { $0.coordinate < $1.coordinate }.first { $0.numberToken == 6 }!
    state.players[0].settlements.insert(HexGeometry.corners(of: six.coordinate)[0])
    state.armyHands[state.players[0].id] = [2, 5]
    state.armyCardsBoughtThisTurn[state.players[0].id] = [5]
    state.phase = .mainTurn(playerIndex: 0)
    return (state, six.coordinate)
}

private let name: (PlayerID) -> String = { "P\($0.index + 1)" }

@Test func cardsBoughtThisTurnAreNotOffered() {
    let (state, _) = position()
    #expect(ArmyPlan.playableCards(in: state, for: state.players[0].id) == [2])
}

@Test func aStandardGameOffersNoArmy() {
    let (state, _) = position(variant: .standard)
    #expect(ArmyPlan.hexOptions(in: state, for: state.players[0].id).isEmpty)
}

@Test func theHexesOfferedAreTheOnesMyBuildingsTouch() {
    let (state, six) = position()
    let me = state.players[0].id
    let options = ArmyPlan.hexOptions(in: state, for: me)
    #expect(options.contains { $0.id == six })
    #expect(options.allSatisfy { Conquest.canDeploy(to: $0.id, by: me, in: state) })
}

@Test func previewNamesEachOutcome() {
    let me = PlayerID(index: 0), rival = PlayerID(index: 1)
    #expect(ArmyPlan.preview(total: 9, against: Garrison(owner: nil, strength: 5), me: me, name: name)
        == "Takes it, holding at 4")
    #expect(ArmyPlan.preview(total: 2, against: Garrison(owner: rival, strength: 5), me: me, name: name)
        == "Leaves P2 at 3")
    #expect(ArmyPlan.preview(total: 3, against: Garrison(owner: me, strength: 5), me: me, name: name)
        == "Reinforces to 8")
}

@Test func previewSaysEmptyAtExactlyZero() {
    #expect(ArmyPlan.preview(total: 5, against: Garrison(owner: nil, strength: 5), me: PlayerID(index: 0), name: name)
        == "Leaves it empty")
}

@Test func noReachableHexMeansNoOptions() {
    var (state, _) = position()
    state.players[0].settlements = []
    #expect(ArmyPlan.hexOptions(in: state, for: state.players[0].id).isEmpty)
}

@Test func labelsSayWhoHoldsTheHex() {
    var (state, six) = position()
    let me = state.players[0].id
    guard case .resource(let kind) = state.board.tiles.first(where: { $0.coordinate == six })!.kind else {
        Issue.record("a 6 always produces"); return
    }
    let resource = kind.rawValue.capitalized
    func label() -> String {
        ArmyPlan.label(for: ArmyPlan.hexOptions(in: state, for: me).first { $0.id == six }!, me: me, name: name)
    }
    #expect(label() == "6 · \(resource) · Tribe 5")
    state.garrisons[six] = Garrison(owner: me, strength: 7)
    #expect(label() == "6 · \(resource) · Yours 7")
    state.garrisons[six] = Garrison(owner: state.players[2].id, strength: 3)
    #expect(label() == "6 · \(resource) · P3 3")
    state.garrisons[six] = nil
    #expect(label() == "6 · \(resource) · Empty")
}
```

- [ ] **Step 2: Run to verify failure**

```bash
xcodegen generate
xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/conquest" \
  -only-testing:SettlersTests/ArmyPlanTests > /tmp/t3-red.log 2>&1; echo EXIT=$?
```
Expected: `EXIT=65`, `cannot find 'ArmyPlan' in scope`.

- [ ] **Step 3: `ArmyPlan` and `ArmyPopupView`**

`Settlers/Views/ArmyPopupView.swift`:

```swift
import SwiftUI
import CatanEngine

/// What the Army popup shows, as pure functions of the game - so it is tested
/// without a view.
enum ArmyPlan {
    struct HexOption: Identifiable, Equatable {
        let id: HexCoordinate
        let number: Int
        let resource: Resource?
        let garrison: Garrison?
    }

    /// Producing hexes one of `seat`'s buildings touches, in board order.
    static func hexOptions(in state: GameState, for seat: PlayerID) -> [HexOption] {
        state.board.tiles.sorted { $0.coordinate < $1.coordinate }.compactMap { tile in
            guard let number = tile.numberToken, Conquest.canDeploy(to: tile.coordinate, by: seat, in: state) else {
                return nil
            }
            let resource: Resource? = if case .resource(let kind) = tile.kind { kind } else { nil }
            return HexOption(id: tile.coordinate, number: number, resource: resource,
                             garrison: state.garrisons[tile.coordinate])
        }
    }

    /// Cards that may be committed now: bought-this-turn cards are held back.
    static func playableCards(in state: GameState, for seat: PlayerID) -> [Int] {
        Conquest.playableCards(for: seat, in: state)
    }

    static func label(for option: HexOption, me: PlayerID, name: (PlayerID) -> String) -> String {
        let resource = option.resource.map { $0.rawValue.capitalized } ?? "Desert"
        let holder: String
        switch option.garrison {
        case .none: holder = "Empty"
        case .some(let garrison) where garrison.owner == nil: holder = "Tribe \(garrison.strength)"
        case .some(let garrison) where garrison.owner == me: holder = "Yours \(garrison.strength)"
        case .some(let garrison): holder = "\(name(garrison.owner!)) \(garrison.strength)"
        }
        return "\(option.number) · \(resource) · \(holder)"
    }

    /// One sentence for what committing `total` does, from the engine's own rule.
    static func preview(total: Int, against current: Garrison?, me: PlayerID, name: (PlayerID) -> String) -> String {
        if current?.owner == me {
            return "Reinforces to \((current?.strength ?? 0) + total)"
        }
        guard let after = Conquest.outcome(of: total, against: current, by: me) else { return "Leaves it empty" }
        if after.owner == me { return "Takes it, holding at \(after.strength)" }
        return after.owner.map { "Leaves \(name($0)) at \(after.strength)" } ?? "Leaves the tribe at \(after.strength)"
    }

    /// Public: how many army cards each rival holds.
    static func rivalSummary(in state: GameState, me: PlayerID, name: (PlayerID) -> String) -> String {
        state.players.map(\.id).filter { $0 != me }.sorted()
            .map { "\(name($0)) \(state.armyHands[$0, default: []].count)" }
            .joined(separator: " · ") + " cards"
    }
}

/// Conquest's army screen: raise a card, then commit cards to a hex.
/// ponytail: the hex is picked from a list, not by tapping the board; move it to
/// a `BoardDecisionIntent` if players find the list hard to map onto the board.
public struct ArmyPopupView: View {
    public let viewModel: GameViewModel
    public let onDismiss: () -> Void

    @State private var selectedHex: HexCoordinate?
    @State private var selected: [Int] = []          // indices into the playable list
    @State private var errorMessage: String?

    public init(viewModel: GameViewModel, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let state = viewModel.state
        let me = viewModel.humanPlayer
        let name: (PlayerID) -> String = { viewModel.playerIdentity(for: $0).displayName }
        let playable = ArmyPlan.playableCards(in: state, for: me)
        let held = state.armyHands[me, default: []].count
        let options = ArmyPlan.hexOptions(in: state, for: me)
        let total = selected.map { playable[$0] }.reduce(0, +)
        let target = options.first { $0.id == selectedHex }

        PopupCard(onDismiss: onDismiss) {
            VStack(spacing: 10) {
                Text("Army").font(.headline)
                GoldRowButton(
                    title: "Raise army card",
                    subtitle: "Any 3 cards · \(state.armyDeck.count) left",
                    systemImage: "shield.lefthalf.filled", iconColor: .red,
                    isEnabled: RulesEngine.legalMoves(for: state).contains(.buyArmyCard),
                    action: { perform(.buyArmyCard) }
                )
                .accessibilityIdentifier(AccessibilityID.Army.buy)

                HStack(spacing: 6) {
                    ForEach(Array(playable.enumerated()), id: \.offset) { index, strength in
                        let isOn = selected.contains(index)
                        Button("\(strength)") {
                            if isOn { selected.removeAll { $0 == index } } else { selected.append(index) }
                        }
                        .font(.headline.monospacedDigit())
                        .frame(width: 36, height: 44)
                        .background(isOn ? Color.red : Color(white: 0.25), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier(AccessibilityID.Army.card(index))
                    }
                    if held > playable.count {
                        Text("+\(held - playable.count) next turn").font(.caption2).foregroundStyle(.secondary)
                    }
                }

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(options) { option in
                            GoldRowButton(
                                title: ArmyPlan.label(for: option, me: me, name: name),
                                systemImage: selectedHex == option.id ? "largecircle.fill.circle" : "circle",
                                action: { selectedHex = option.id }
                            )
                            .accessibilityIdentifier(AccessibilityID.Army.hex(option.id))
                        }
                    }
                }
                .frame(maxHeight: 220)

                if let target, total > 0 {
                    Text(ArmyPlan.preview(total: total, against: target.garrison, me: me, name: name))
                        .font(.caption).accessibilityIdentifier(AccessibilityID.Army.preview)
                }
                GoldRowButton(
                    title: "Commit \(total) strength", systemImage: "flag.fill", iconColor: .red,
                    isEnabled: target != nil && total > 0,
                    action: {
                        guard let hex = selectedHex else { return }
                        perform(.deployArmy(to: hex, strengths: selected.map { playable[$0] }.sorted()))
                    }
                )
                .accessibilityIdentifier(AccessibilityID.Army.commit)

                Text(ArmyPlan.rivalSummary(in: state, me: me, name: name)).font(.caption2).foregroundStyle(.secondary)
                if let errorMessage { Text(errorMessage).font(.caption2).foregroundStyle(.red) }
                GoldRowButton(title: "Close", systemImage: "xmark", action: onDismiss)
            }
            .padding(16)
            .frame(maxWidth: 340)
        }
        .accessibilityIdentifier(AccessibilityID.Army.popup)
    }

    private func perform(_ move: GameMove) {
        do {
            try viewModel.apply(move)
            errorMessage = nil
            selected = []            // indices refer to the old hand
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

`AccessibilityID.swift`: add `static let army = "build.army"` to `enum Build`, and:

```swift
    enum Army {
        static let popup = "army.popup"
        static let buy = "army.buy"
        static let commit = "army.commit"
        static let preview = "army.preview"
        static func card(_ index: Int) -> String { "army.card.\(index)" }
        static func hex(_ hex: HexCoordinate) -> String { "army.hex.\(hex.q).\(hex.r)" }
    }
```


- [ ] **Step 4: The Build row**

`BuildPopupView`: add `public let onOpenArmy: () -> Void` with init parameter `onOpenArmy: @escaping () -> Void = {}`, and after the Dev Card row:

```swift
                    if viewModel.state.variant == .conquest {
                        GoldRowButton(title: "Army", subtitle: "Raise and commit army cards",
                                      systemImage: "shield.lefthalf.filled", iconColor: .red,
                                      isEnabled: true, action: onOpenArmy)
                        .accessibilityIdentifier(AccessibilityID.Build.army)
                    }
```

- [ ] **Step 5: Present it from `GameView`**

1. `@State private var showArmyPopup = false` beside `showBuildPopup`.
2. The Build presentation becomes `BuildPopupView(viewModel: viewModel, onDismiss: { showBuildPopup = false }, onOpenArmy: { showBuildPopup = false; showArmyPopup = true })`.
3. Directly after it:

```swift
            if !isDiscardPresented, viewModel.boardDecisionPresentation == nil, showArmyPopup {
                ArmyPopupView(viewModel: viewModel, onDismiss: { showArmyPopup = false })
                    .accessibilityHidden(viewModel.needsHandoff)
            }
```

4. Add `|| showArmyPopup` to `isBlockingOverlayPresented`'s return; add `showArmyPopup = false` beside `showBuildPopup = false` in both the discard `onChange` and `clearSeatInteractionState()`.
5. In the Task 2 QA dispatch, add `showArmyPopup = QALaunchFlag.showArmyPopup.isSet`.

Check `wc -l Settlers/Views/GameView.swift` stays under 1,240.

- [ ] **Step 6: Run to verify pass**

Re-run Step 2's command → `EXIT=0`, 7 tests passed.

- [ ] **Step 7: A UI test that plays it**

`SettlersUITests/ConquestFlowTests.swift`:

```swift
import XCTest

/// The Army popup commits a real deploy: pick the 9 the fixture holds at 6,
/// reinforce it with the 2, and the row reads "Yours 8".
@MainActor
final class ConquestFlowTests: XCTestCase {
    func testReinforcingAHeldHexFromTheArmyPopup() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaShowArmyPopup"]
        app.launch()
        XCTAssertTrue(app.otherElements["army.popup"].waitForExistence(timeout: 10))
        let held = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Yours 6")).firstMatch
        XCTAssertTrue(held.waitForExistence(timeout: 5))
        held.tap()
        app.buttons["army.card.0"].tap()
        XCTAssertEqual(app.staticTexts["army.preview"].label, "Reinforces to 8")
        app.buttons["army.commit"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Yours 8"))
            .firstMatch.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "conquest-army-popup"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
```

```bash
xcodegen generate
xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/conquest" \
  -only-testing:SettlersUITests/ConquestFlowTests -only-testing:SettlersUITests/BelowBoardInvarianceTests \
  -only-testing:SettlersUITests/DevelopmentCardFlowTests > /tmp/t3-ui.log 2>&1; echo EXIT=$?
swiftlint --strict
```
Expected: `EXIT=0`; lint clean. Open the `conquest-army-popup` attachment from the `.xcresult` and look at it: nothing clipped, card chips legible.

- [ ] **Step 8: Commit** — `feat(app): Army popup - raise army cards and commit them to hexes`.

---

### Task 4: Play it for real

**Files:** none unless a defect is found.

- [ ] **Step 1:** Follow `.claude/skills/play-settlers/SKILL.md` to play a Conquest game on the simulator from the real New Game screen (no QA flags): complete setup, take a tribe hex with the starting card, buy a card, end turns until a bot deploys, and screenshot a board with at least two rings of different colours.
- [ ] **Step 2:** Repeat Step 1's first deploy on **Vast** (choose Vast + Conquest), and screenshot. The question is legibility of badges on 61 hexes at phone size; if badges collide, record it rather than fixing it here.
- [ ] **Step 3:** Write what was seen, with screenshot paths, into the commit body of an empty commit only if nothing needed fixing: `git commit --allow-empty -m "test(app): Conquest played end to end on Classic and Vast"`. Any defect found gets its own failing test and fix first.

---

### Task 5: Land it and put it on Jake's phone

- [ ] **Step 1:** `git fetch origin && git rebase origin/main` in the worktree; resolve conflicts; re-run `swift test --package-path Packages/CatanEngine` and `swiftlint --strict`.
- [ ] **Step 2:** Quit Simulator, `xcrun simctl shutdown all`, then **ask Jake before pushing** — the push runs the ~50-minute gate and lands on `main`: `git push origin HEAD:main`. The pre-push hook is the full verification.
- [ ] **Step 3:** Install on Jake's phone with the `run-settlers` skill's device path (it signs to team `KDM65HE483`, which is Jake's). Jake must have the phone connected and unlocked.
- [ ] **Step 4:** After it lands, clean up exactly as CLAUDE.md's "Concurrent agents" section says: remove the worktree, delete the branch, `reset --hard origin/main` in the primary checkout.
