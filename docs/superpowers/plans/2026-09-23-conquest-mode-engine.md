# Conquest Mode (Engine, Bots, Measurement) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Conquest playable end-to-end by bots in `CatanEngine` + `CatanAI`, and measure its snowball risk with the `sim` harness, before any UI is built.

**Architecture:** Conquest is a `GameVariant` tag on `GameState`, orthogonal to `GameMode` (board). All Conquest rules live in one new engine file, `Conquest.swift`, called from three seams: `GameSetup.newGame` (tribes + deck), `SetupPhase` (starting card), `RulesEngine` (two moves) and `MainPhase.payouts` (takeover). Bots get one new heuristic file. The app only gains what it needs to keep compiling (narrator lines); the UI is a separate plan, written after the measurement in Task 5 confirms or changes the rules.

**Tech Stack:** Swift 6.3, SwiftPM, swift-testing (`@Test`, `#expect`).

**Spec:** `docs/superpowers/specs/2026-09-23-conquest-mode-design.md`

**Worktree:** `~/Documents/Catan Game worktrees/conquest`, branch `feat/conquest-mode`. All paths below are relative to it. Never work in the primary checkout.

## Global Constraints

- `CatanEngine` and `CatanAI` import only `Foundation` (plus `CatanEngine` from `CatanAI`).
- All randomness goes through a seeded generator; never `Int.random`/`.shuffled()` without `using:`.
- Every enumeration is order-stable: sort coordinates/IDs; never iterate a `Set`/`Dictionary` into a decision.
- **A standard (non-Conquest) game must consume exactly the same random sequence as today.** `SeededGameFingerprintTests` must pass unchanged.
- Every new `GameState` field decodes with `decodeIfPresent` + default; `currentSchemaVersion` becomes **5**.
- Army card cost: `1 brick, 1 lumber, 1 wool, 1 grain, 1 ore`.
- Classic army deck: `1×5, 2×5, 3×4, 4×4, 5×3, 6×3, 7×2, 8×2, 9×1` (29). Vast and Expanded: every count doubled (58).
- Tribe strength = `DiceOdds.pips(for: token)`. Desert: no garrison, never deployable.
- `swiftlint --strict` must pass (`file_length` error at 1600, `function_body_length` error at 200).
- Commits: conventional (`feat(engine): ...`), long body with the why, ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. **Do not push.** Pushing runs the ~50-minute gate; this branch pushes once, after the UI plan lands too.
- Never pipe `xcodebuild`/`swift test` through `tail`/`grep` without reading `${PIPESTATUS[0]}`.

## Review Focus

1. **A card bought this turn sharing a strength with an older card.** Hold `[3]`, buy another `3` → exactly one `3` is playable this turn. Tested in Task 2 (`aCardBoughtThisTurnIsNotPlayableEvenWhenAnOlderTwinIs`).
2. **Deploying cards the player does not hold** (wrong strengths, duplicates beyond the hand, empty list). Must throw and leave state untouched. Tested in Task 2 (`deployingCardsNotHeldIsRefusedWithoutMutation`).
3. **Occupier bonus when the bank is short.** Bank holding 1 grain, occupier's settlement + bonus demand 2 → occupier gets the 1 (single-claimant rule). Tested in Task 3 (`occupierBonusRespectsBankShortage`).
4. **A standard game is untouched.** No army moves listed, `.deployArmy` refused, payouts identical, fingerprints unchanged. Tested in Tasks 1–3 and by the existing `SeededGameFingerprintTests`.
5. **Saves.** A v4 save loads as `.standard`; a Conquest save round-trips garrisons (a non-String-keyed dictionary) and hands. Tested in Task 1.

---

### Task 1: Conquest state, tribes and the army deck

**Files:**
- Create: `Packages/CatanEngine/Sources/CatanEngine/Models/GameVariant.swift`
- Create: `Packages/CatanEngine/Sources/CatanEngine/Conquest.swift`
- Modify: `Packages/CatanEngine/Sources/CatanEngine/Ruleset.swift` (new `armyDeck` field; values in `forMode`)
- Modify: `Packages/CatanEngine/Sources/CatanEngine/Models/GameState.swift` (fields, init, decoder, schema 5, `newGame` overloads)
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/ConquestSetupTests.swift`
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/SaveCompatibilityTests.swift` (append)

**Interfaces:**
- Produces:
  - `public enum GameVariant: String, Codable, CaseIterable, Sendable { case standard, conquest }` with `displayName`
  - `public struct Garrison: Codable, Sendable, Hashable { public var owner: PlayerID?; public var strength: Int }` (`owner == nil` ⇒ tribe)
  - `GameState.variant: GameVariant`, `.garrisons: [HexCoordinate: Garrison]` (no entry ⇒ unoccupied or desert), `.armyDeck: [Int]`, `.armyHands: [PlayerID: [Int]]`, `.armyCardsBoughtThisTurn: [PlayerID: [Int]]`
  - `Ruleset.armyDeck: [Int: Int]`, `Ruleset.classicArmyDeck`
  - `GameSetup.newGame(..., variant: GameVariant = .standard)` on all three overloads
  - `enum Conquest` with `static let armyCardCost: [Resource: Int]`, `static func initialGarrisons(board: Board) -> [HexCoordinate: Garrison]`, `static func buildArmyDeck(_ counts: [Int: Int]) -> [Int]`

- [ ] **Step 1: Write the failing tests**

`Packages/CatanEngine/Tests/CatanEngineTests/ConquestSetupTests.swift`:

```swift
import Testing
@testable import CatanEngine

@Test func aConquestGameStartsWithEveryProducingHexHeldByATribeAtItsPipCount() {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 3, variant: .conquest)
    for tile in state.board.tiles {
        guard let token = tile.numberToken else {
            #expect(state.garrisons[tile.coordinate] == nil, "the desert is never garrisoned")
            continue
        }
        #expect(state.garrisons[tile.coordinate] == Garrison(owner: nil, strength: DiceOdds.pips(for: token)))
    }
}

@Test func aConquestGameShufflesTheFullClassicArmyDeck() {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 3, variant: .conquest)
    #expect(state.armyDeck.count == 29)
    #expect(state.armyDeck.sorted() == Conquest.buildArmyDeck(Ruleset.classicArmyDeck))
    #expect(state.armyDeck != Conquest.buildArmyDeck(Ruleset.classicArmyDeck), "the deck is shuffled")
}

@Test func vastDoublesTheArmyDeck() {
    #expect(Ruleset.forMode(.vast).armyDeck.values.reduce(0, +) == 58)
    #expect(Ruleset.forMode(.vast).armyDeck[9] == 2)
}

@Test func aStandardGameHasNoConquestStateAndDrawsTheSameRandomSequence() {
    let before = GameSetup.newGame(board: BoardGenerator.standard(), seed: 42)
    let explicit = GameSetup.newGame(board: BoardGenerator.standard(), seed: 42, variant: .standard)
    #expect(before == explicit)
    #expect(before.garrisons.isEmpty && before.armyDeck.isEmpty && before.armyHands.isEmpty)
}

@Test func conquestDoesNotChangeTheDevDeckOrDiceSeedOfTheSameSeed() {
    let standard = GameSetup.newGame(board: BoardGenerator.standard(), seed: 42)
    let conquest = GameSetup.newGame(board: BoardGenerator.standard(), seed: 42, variant: .conquest)
    #expect(standard.devCardDeck == conquest.devCardDeck)
    #expect(standard.rng == conquest.rng)
}
```

Append to `SaveCompatibilityTests.swift`:

```swift
@Test func aSaveWrittenBeforeConquestExistedLoadsAsStandard() throws {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 9)
    let data = try encodeOmitting(["variant", "garrisons", "armyDeck", "armyHands",
                                   "armyCardsBoughtThisTurn"], from: state)
    let decoded = try JSONDecoder().decode(GameState.self, from: data)
    #expect(decoded.variant == .standard)
    #expect(decoded.garrisons.isEmpty && decoded.armyHands.isEmpty)
}

@Test func aConquestSaveRoundTripsGarrisonsAndHands() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 9, variant: .conquest)
    let hex = state.board.tiles.first { $0.numberToken != nil }!.coordinate
    state.garrisons[hex] = Garrison(owner: state.players[2].id, strength: 17)
    state.armyHands[state.players[1].id] = [9, 1, 4]
    let decoded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state))
    #expect(decoded == state)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/CatanEngine --filter "Conquest|SaveCompatibility"`
Expected: compile failure, `cannot find 'Garrison' in scope` / `extra argument 'variant'`.

- [ ] **Step 3: Add `GameVariant`**

`Packages/CatanEngine/Sources/CatanEngine/Models/GameVariant.swift`:

```swift
/// Which rule layer a game is played under, on top of its board (`GameMode`).
///
/// Separate from `GameMode` because Conquest crosses every board: folding it in
/// would need a `classicConquest` and a `vastConquest`, doubling the modes for
/// every future layer. `String`-raw for the same save-stability reason as
/// `GameMode`.
public enum GameVariant: String, Codable, CaseIterable, Sendable {
    case standard
    /// Hexes are held by tribes and taken with army cards; an occupied hex pays
    /// only its occupier, plus one. See `Conquest`.
    case conquest

    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .conquest: return "Conquest"
        }
    }
}
```

- [ ] **Step 4: Add `Ruleset.armyDeck`**

In `Ruleset.swift`, add the stored property after `devCardDeck`:

```swift
    /// Army cards by strength, for the Conquest variant. Unused by a standard
    /// game. Weighted low so a 9 is an event, and finite so it can be counted.
    public let armyDeck: [Int: Int]
```

Add the init parameter after `discardThreshold: Int` **with a default** so no other construction site changes:

```swift
        discardThreshold: Int,
        armyDeck: [Int: Int] = Ruleset.classicArmyDeck
```

and `self.armyDeck = armyDeck` in the body. Add the constant inside `Ruleset`:

```swift
    /// Classic's army deck: 29 cards, mean strength ~4.0.
    public static let classicArmyDeck: [Int: Int] = [1: 5, 2: 5, 3: 4, 4: 4, 5: 3, 6: 3, 7: 2, 8: 2, 9: 1]
```

In `forMode`, pass for `.expanded` and `.vast` (Classic takes the default):

```swift
                discardThreshold: 10,
                armyDeck: Ruleset.classicArmyDeck.mapValues { $0 * 2 }
```

(`discardThreshold: 12,` for `.vast`, same `armyDeck` line.)

- [ ] **Step 5: Add `Conquest.swift` with setup helpers**

```swift
/// The Conquest variant: tribes hold every producing hex, army cards take them.
///
/// One file so the whole variant can be read in one place; `RulesEngine`,
/// `SetupPhase` and `MainPhase` each call in at exactly one seam.
public enum Conquest {
    public static let armyCardCost: [Resource: Int] = [.brick: 1, .lumber: 1, .wool: 1, .grain: 1, .ore: 1]

    /// Every producing hex held by a tribe at its number's pip count. The
    /// desert gets no entry, which is what makes it un-deployable.
    public static func initialGarrisons(board: Board) -> [HexCoordinate: Garrison] {
        var garrisons: [HexCoordinate: Garrison] = [:]
        for tile in board.tiles {
            guard let token = tile.numberToken else { continue }
            garrisons[tile.coordinate] = Garrison(owner: nil, strength: DiceOdds.pips(for: token))
        }
        return garrisons
    }

    /// The unshuffled deck, ascending. Driven off sorted keys, never dictionary
    /// order, so a seeded shuffle deals the same deck in every process.
    public static func buildArmyDeck(_ counts: [Int: Int]) -> [Int] {
        counts.keys.sorted().flatMap { repeatElement($0, count: counts[$0, default: 0]) }
    }
}

/// Who holds a hex and how strongly. `owner == nil` is a tribe.
public struct Garrison: Codable, Sendable, Hashable {
    public var owner: PlayerID?
    public var strength: Int

    public init(owner: PlayerID?, strength: Int) {
        self.owner = owner
        self.strength = strength
    }
}
```

- [ ] **Step 6: Add the `GameState` fields**

In `GameState.swift`:

1. Bump the version and extend its comment: `/// Bumped to 5 when the Conquest fields were added.` and `public static let currentSchemaVersion = 5`.
2. After `declinedTradeOffersThisTurn`, add:

```swift
    /// The rule layer. `.standard` for every game that is not Conquest.
    public var variant: GameVariant
    /// Conquest only: who holds each hex. No entry means unoccupied (or the desert).
    public var garrisons: [HexCoordinate: Garrison]
    /// Conquest only: undealt army cards, top first.
    public var armyDeck: [Int]
    /// Conquest only: each seat's hidden army cards, by strength. Kept here
    /// rather than on `Player` because `Player` decodes synthesized, and a new
    /// non-optional field there would reject every existing save.
    public var armyHands: [PlayerID: [Int]]
    /// Army cards bought this turn, not yet playable. Cleared on `.endTurn`.
    public var armyCardsBoughtThisTurn: [PlayerID: [Int]]
```

3. In `init(...)`, add parameters after `victoryPointTarget:` and assign them:

```swift
        victoryPointTarget: Int = Ruleset.forMode(.classic).defaultVictoryPointTarget,
        variant: GameVariant = .standard,
        garrisons: [HexCoordinate: Garrison] = [:],
        armyDeck: [Int] = [],
        armyHands: [PlayerID: [Int]] = [:],
        armyCardsBoughtThisTurn: [PlayerID: [Int]] = [:]
```

```swift
        self.variant = variant
        self.garrisons = garrisons
        self.armyDeck = armyDeck
        self.armyHands = armyHands
        self.armyCardsBoughtThisTurn = armyCardsBoughtThisTurn
```

4. At the end of `init(from:)`:

```swift
        // Absent in every save written before Conquest (schema < 5).
        variant = try container.decodeIfPresent(GameVariant.self, forKey: .variant) ?? .standard
        garrisons = try container.decodeIfPresent([HexCoordinate: Garrison].self, forKey: .garrisons) ?? [:]
        armyDeck = try container.decodeIfPresent([Int].self, forKey: .armyDeck) ?? []
        armyHands = try container.decodeIfPresent([PlayerID: [Int]].self, forKey: .armyHands) ?? [:]
        armyCardsBoughtThisTurn = try container
            .decodeIfPresent([PlayerID: [Int]].self, forKey: .armyCardsBoughtThisTurn) ?? [:]
```

- [ ] **Step 7: Thread `variant` through `GameSetup.newGame`**

Add `variant: GameVariant = .standard` as the last parameter of all three overloads and pass it through the two that delegate. In the `rng:` overload, replace the `return GameState(...)` with:

```swift
        // The state's seed is drawn BEFORE the army deck is shuffled, in the
        // same position it always was, so a standard game - which draws
        // nothing further - consumes exactly the sequence it did before
        // Conquest existed, and `SeededGameFingerprintTests` stays green.
        let stateSeed = rng.next()
        var armyDeck: [Int] = []
        var garrisons: [HexCoordinate: Garrison] = [:]
        if variant == .conquest {
            armyDeck = Conquest.buildArmyDeck(rules.armyDeck)
            armyDeck.shuffle(using: &rng)
            garrisons = Conquest.initialGarrisons(board: board)
        }

        return GameState(
            board: board,
            players: players,
            phase: .setupForward(playerIndex: 0),
            bank: bank,
            devCardDeck: devCardDeck,
            rng: RandomSource(seed: stateSeed),
            mode: mode,
            victoryPointTarget: target,
            variant: variant,
            garrisons: garrisons,
            armyDeck: armyDeck
        )
```

- [ ] **Step 8: Run tests**

Run: `swift test --package-path Packages/CatanEngine`
Expected: all pass, including the 7 new tests.

- [ ] **Step 9: Commit**

```bash
git add Packages/CatanEngine
git commit -m "feat(engine): add Conquest variant state, tribe garrisons and army deck"
```
(Body: why `variant` is separate from `mode`; why hands live on `GameState` not `Player`; that the state seed is drawn before the army shuffle so standard fingerprints are unchanged.)

---

### Task 2: Army moves — buy, deploy, starting card

**Files:**
- Modify: `Packages/CatanEngine/Sources/CatanEngine/Conquest.swift`
- Modify: `Packages/CatanEngine/Sources/CatanEngine/Models/Move.swift` (2 cases)
- Modify: `Packages/CatanEngine/Sources/CatanEngine/Models/GameEvent.swift` (2 cases)
- Modify: `Packages/CatanEngine/Sources/CatanEngine/RulesEngine.swift` (legalMoves, apply, endTurn)
- Modify: `Packages/CatanEngine/Sources/CatanEngine/SetupPhase.swift:131` (deal on setup end)
- Modify: `Packages/CatanEngine/Sources/CatanEngine/PublicLedger.swift:251` (debit army purchase)
- Modify: `Settlers/Models/GameReplayNarrator.swift:43` (two narration lines; exhaustive switch)
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/ConquestMoveTests.swift`

**Interfaces:**
- Consumes: Task 1's `Garrison`, `GameState.garrisons/armyDeck/armyHands/armyCardsBoughtThisTurn`, `Conquest.armyCardCost`.
- Produces:
  - `GameMove.buyArmyCard`, `GameMove.deployArmy(to: HexCoordinate, strengths: [Int])`
  - `GameEvent.boughtArmyCard(PlayerID)`, `GameEvent.deployedArmy(PlayerID, hex: HexCoordinate, total: Int, result: Garrison?)`
  - `Conquest.playableCards(for: PlayerID, in: GameState) -> [Int]` (sorted ascending)
  - `Conquest.canDeploy(to: HexCoordinate, by: PlayerID, in: GameState) -> Bool`
  - `Conquest.outcome(of total: Int, against: Garrison?, by: PlayerID) -> Garrison?`
  - `Conquest.buy(by:state:) throws -> Int`, `Conquest.deploy(_:to:by:state:) throws -> Garrison?`, `Conquest.dealStartingCards(_ state: inout GameState)`, `Conquest.moves(for: Player, in: GameState) -> [GameMove]`

- [ ] **Step 1: Write the failing tests**

`Packages/CatanEngine/Tests/CatanEngineTests/ConquestMoveTests.swift`:

```swift
import Testing
@testable import CatanEngine

/// Seat 0 in its main turn, holding `hand`, with a settlement on `tile`.
private func conquest(hand: [Int] = [], seed: UInt64 = 1) -> (GameState, Tile) {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: seed, variant: .conquest)
    state.phase = .mainTurn(playerIndex: 0)
    let tile = state.board.tiles.first { $0.numberToken == 6 }!
    state.players[0].settlements.insert(HexGeometry.corners(of: tile.coordinate)[0])
    state.armyHands[state.players[0].id] = hand
    return (state, tile)
}

private let everyResource: [Resource: Int] = [.brick: 1, .lumber: 1, .wool: 1, .grain: 1, .ore: 1]

@Test func buyingCostsOneOfEachAndDrawsTheTopCardUnplayableThisTurn() throws {
    var (state, _) = conquest()
    state.players[0].resources = everyResource
    let top = state.armyDeck[0]
    try RulesEngine.apply(.buyArmyCard, by: state.players[0].id, to: &state)
    #expect(state.players[0].resources.values.allSatisfy { $0 == 0 })
    #expect(state.armyHands[state.players[0].id] == [top])
    #expect(Conquest.playableCards(for: state.players[0].id, in: state).isEmpty)
}

@Test func aCardBoughtThisTurnIsNotPlayableEvenWhenAnOlderTwinIs() throws {
    var (state, _) = conquest(hand: [3])
    state.armyDeck[0] = 3
    state.players[0].resources = everyResource
    try RulesEngine.apply(.buyArmyCard, by: state.players[0].id, to: &state)
    #expect(Conquest.playableCards(for: state.players[0].id, in: state) == [3])
}

@Test func anEmptyArmyDeckCannotBeBoughtFrom() {
    var (state, _) = conquest()
    state.armyDeck = []
    state.players[0].resources = everyResource
    #expect(!RulesEngine.legalMoves(for: state).contains(.buyArmyCard))
    #expect(throws: (any Error).self) { try RulesEngine.apply(.buyArmyCard, by: state.players[0].id, to: &state) }
}

@Test func attackingPastATribeTakesTheHexWithTheOverflow() throws {
    var (state, tile) = conquest(hand: [9])
    try RulesEngine.apply(.deployArmy(to: tile.coordinate, strengths: [9]), by: state.players[0].id, to: &state)
    #expect(state.garrisons[tile.coordinate] == Garrison(owner: state.players[0].id, strength: 4))
    #expect(state.armyHands[state.players[0].id] == [])
}

@Test func anAttackThatFallsShortWeakensTheDefender() throws {
    var (state, tile) = conquest(hand: [2])
    try RulesEngine.apply(.deployArmy(to: tile.coordinate, strengths: [2]), by: state.players[0].id, to: &state)
    #expect(state.garrisons[tile.coordinate] == Garrison(owner: nil, strength: 3))
}

@Test func anExactlyEqualAttackLeavesTheHexUnoccupied() throws {
    var (state, tile) = conquest(hand: [2, 3])
    try RulesEngine.apply(.deployArmy(to: tile.coordinate, strengths: [2, 3]), by: state.players[0].id, to: &state)
    #expect(state.garrisons[tile.coordinate] == nil)
}

@Test func deployingOnYourOwnHexReinforcesIt() throws {
    var (state, tile) = conquest(hand: [4])
    state.garrisons[tile.coordinate] = Garrison(owner: state.players[0].id, strength: 10)
    try RulesEngine.apply(.deployArmy(to: tile.coordinate, strengths: [4]), by: state.players[0].id, to: &state)
    #expect(state.garrisons[tile.coordinate] == Garrison(owner: state.players[0].id, strength: 14))
}

@Test func aHexYourBuildingsDoNotTouchCannotBeDeployedTo() {
    var (state, tile) = conquest(hand: [9])
    let far = state.board.tiles.first { tile2 in
        tile2.numberToken != nil && tile2.coordinate != tile.coordinate
            && !HexGeometry.corners(of: tile2.coordinate).contains(HexGeometry.corners(of: tile.coordinate)[0])
    }!
    #expect(!Conquest.canDeploy(to: far.coordinate, by: state.players[0].id, in: state))
    #expect(throws: (any Error).self) {
        try RulesEngine.apply(.deployArmy(to: far.coordinate, strengths: [9]), by: state.players[0].id, to: &state)
    }
}

@Test func theDesertCannotBeDeployedTo() {
    var (state, _) = conquest(hand: [9])
    let desert = state.board.tiles.first { $0.numberToken == nil }!
    state.players[0].settlements.insert(HexGeometry.corners(of: desert.coordinate)[0])
    #expect(!Conquest.canDeploy(to: desert.coordinate, by: state.players[0].id, in: state))
}

@Test func deployingCardsNotHeldIsRefusedWithoutMutation() {
    let (start, tile) = conquest(hand: [3, 5])
    for strengths in [[9], [3, 3], [], [5, 5, 3]] {
        var state = start
        #expect(throws: (any Error).self) {
            try RulesEngine.apply(.deployArmy(to: tile.coordinate, strengths: strengths),
                                  by: state.players[0].id, to: &state)
        }
        #expect(state == start)
    }
}

@Test func legalMovesOfferEachSingleCardAndTheCheapestWinningSet() {
    let (state, tile) = conquest(hand: [1, 2, 4, 9])
    let deploys = RulesEngine.legalMoves(for: state).filter {
        if case .deployArmy(let hex, _) = $0 { return hex == tile.coordinate } else { return false }
    }
    // Tribe on a 6 holds at 5: the cheapest set that takes it sums to 6 ([2, 4]).
    #expect(Set(deploys) == [
        .deployArmy(to: tile.coordinate, strengths: [1]),
        .deployArmy(to: tile.coordinate, strengths: [2]),
        .deployArmy(to: tile.coordinate, strengths: [4]),
        .deployArmy(to: tile.coordinate, strengths: [9]),
        .deployArmy(to: tile.coordinate, strengths: [2, 4]),
    ])
}

@Test func setupEndDealsEveryPlayerOnePlayableArmyCard() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 5, variant: .conquest)
    let top4 = Array(state.armyDeck.prefix(4))
    Conquest.dealStartingCards(&state)
    for (index, player) in state.players.enumerated() {
        #expect(state.armyHands[player.id] == [top4[index]])
        #expect(Conquest.playableCards(for: player.id, in: state) == [top4[index]])
    }
    #expect(state.armyDeck.count == 25)
}

@Test func aStandardGameListsNoArmyMovesAndRefusesThem() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    state.phase = .mainTurn(playerIndex: 0)
    state.players[0].resources = everyResource
    let tile = state.board.tiles.first { $0.numberToken == 6 }!
    #expect(!RulesEngine.legalMoves(for: state).contains(.buyArmyCard))
    #expect(throws: (any Error).self) {
        try RulesEngine.apply(.deployArmy(to: tile.coordinate, strengths: [1]), by: state.players[0].id, to: &state)
    }
}

@Test func endTurnMakesBoughtCardsPlayable() throws {
    var (state, _) = conquest()
    state.players[0].resources = everyResource
    try RulesEngine.apply(.buyArmyCard, by: state.players[0].id, to: &state)
    try RulesEngine.apply(.endTurn, by: state.players[0].id, to: &state)
    #expect(Conquest.playableCards(for: state.players[0].id, in: state).count == 1)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/CatanEngine --filter ConquestMove`
Expected: compile failure, `type 'GameMove' has no member 'buyArmyCard'`.

- [ ] **Step 3: Add the move and event cases**

`Move.swift`, after `case buyDevCard`:

```swift
    /// Conquest: 1 of each resource for the top army card.
    case buyArmyCard
    /// Conquest: spend these army cards on `to`. Reinforces a hex you hold,
    /// attacks any other. `strengths` is sorted ascending by convention.
    case deployArmy(to: HexCoordinate, strengths: [Int])
```

`GameEvent.swift`, after `case boughtDevCard(PlayerID)`:

```swift
    /// Conquest. Public: everyone sees that a card was bought, never its strength.
    case boughtArmyCard(PlayerID)
    /// Conquest. `result` is the hex's garrison afterwards; `nil` = unoccupied.
    case deployedArmy(PlayerID, hex: HexCoordinate, total: Int, result: Garrison?)
```

- [ ] **Step 4: Add the rules to `Conquest.swift`**

Append inside `enum Conquest`:

```swift
    /// `player`'s army cards minus those bought this turn, ascending.
    public static func playableCards(for player: PlayerID, in state: GameState) -> [Int] {
        var hand = state.armyHands[player, default: []].sorted()
        for card in state.armyCardsBoughtThisTurn[player, default: []] {
            if let index = hand.firstIndex(of: card) { hand.remove(at: index) }
        }
        return hand
    }

    /// A producing hex one of `player`'s buildings touches, in a Conquest game.
    public static func canDeploy(to hex: HexCoordinate, by player: PlayerID, in state: GameState) -> Bool {
        guard state.variant == .conquest,
              state.board.tiles.contains(where: { $0.coordinate == hex && $0.numberToken != nil }),
              let owner = state.players.first(where: { $0.id == player }) else { return false }
        return HexGeometry.corners(of: hex).contains { owner.settlements.contains($0) || owner.cities.contains($0) }
    }

    /// The garrison after `total` strength from `player` lands on `current`.
    public static func outcome(of total: Int, against current: Garrison?, by player: PlayerID) -> Garrison? {
        if let current, current.owner == player {
            return Garrison(owner: player, strength: current.strength + total)
        }
        let remaining = (current?.strength ?? 0) - total
        if remaining > 0 { return Garrison(owner: current?.owner, strength: remaining) }
        if remaining == 0 { return nil }
        return Garrison(owner: player, strength: -remaining)
    }

    @discardableResult
    static func buy(by player: PlayerID, state: inout GameState) throws -> Int {
        guard state.variant == .conquest else { throw MoveError.wrongPhase }
        guard let index = state.players.firstIndex(where: { $0.id == player }) else {
            throw MoveError.other("unknown player")
        }
        guard !state.armyDeck.isEmpty else { throw MoveError.other("The army deck is empty.") }
        try RulesEngine.deduct(armyCardCost, from: &state, playerIndex: index)
        let card = state.armyDeck.removeFirst()
        state.armyHands[player, default: []].append(card)
        state.armyCardsBoughtThisTurn[player, default: []].append(card)
        return card
    }

    static func deploy(_ strengths: [Int], to hex: HexCoordinate, by player: PlayerID,
                       state: inout GameState) throws -> Garrison? {
        guard !strengths.isEmpty, canDeploy(to: hex, by: player, in: state) else {
            throw MoveError.illegalPlacement
        }
        var playable = playableCards(for: player, in: state)
        for card in strengths {
            guard let index = playable.firstIndex(of: card) else {
                throw MoveError.other("You don't hold those army cards.")
            }
            playable.remove(at: index)
        }
        for card in strengths {
            let index = state.armyHands[player, default: []].firstIndex(of: card)!
            state.armyHands[player]!.remove(at: index)
        }
        let result = outcome(of: strengths.reduce(0, +), against: state.garrisons[hex], by: player)
        state.garrisons[hex] = result
        return result
    }

    /// One card to every seat, in seat order, when setup ends. A no-op outside
    /// Conquest. Not recorded as bought, so each is playable on turn one.
    static func dealStartingCards(_ state: inout GameState) {
        guard state.variant == .conquest else { return }
        for player in state.players where !state.armyDeck.isEmpty {
            state.armyHands[player.id, default: []].append(state.armyDeck.removeFirst())
        }
    }

    /// Buy, plus per deployable hex: each distinct playable card alone, and -
    /// for a hex held by someone else - the cheapest set that takes it.
    /// Bounded: listing every subset would grow as 2^n on the rendering path.
    /// `apply` still accepts any held subset.
    static func moves(for player: Player, in state: GameState) -> [GameMove] {
        guard state.variant == .conquest else { return [] }
        var moves: [GameMove] = []
        if RulesEngine.canAfford(armyCardCost, player: player), !state.armyDeck.isEmpty {
            moves.append(.buyArmyCard)
        }
        let playable = playableCards(for: player.id, in: state)
        guard !playable.isEmpty else { return moves }
        let hexes = state.board.tiles.map(\.coordinate).sorted().filter { canDeploy(to: $0, by: player.id, in: state) }
        for hex in hexes {
            let singles = Array(Set(playable)).sorted().map { [$0] }
            var candidates = singles
            let garrison = state.garrisons[hex]
            if garrison?.owner != player.id,
               let cheapest = cheapestSet(exceeding: garrison?.strength ?? 0, from: playable),
               !singles.contains(cheapest) {
                candidates.append(cheapest)
            }
            moves += candidates.map { .deployArmy(to: hex, strengths: $0) }
        }
        return moves
    }

    /// The subset of `cards` with the smallest total strictly above `target`,
    /// ascending; ties go to the first found in ascending-card order. `nil` if
    /// the whole hand cannot beat it. Subset-sum over at most 9 x deck-size.
    static func cheapestSet(exceeding target: Int, from cards: [Int]) -> [Int]? {
        var best: [Int: [Int]] = [0: []]
        for card in cards.sorted() {
            for (sum, set) in best.sorted(by: { $0.key > $1.key }) where best[sum + card] == nil {
                best[sum + card] = set + [card]
            }
        }
        return best.keys.sorted().first { $0 > target }.flatMap { best[$0] }
    }
```

- [ ] **Step 5: Wire into `RulesEngine`**

In `legalMoves`, `.mainTurn` case, immediately before `moves.append(contentsOf: tradeProposals(for: player))`:

```swift
            moves += Conquest.moves(for: player, in: state)
```

In `applyReportingPrivateEvents`, `.mainTurn` inner switch, after the `.buyDevCard` case:

```swift
            case .buyArmyCard:
                try Conquest.buy(by: player, state: &state)
                events.append(.boughtArmyCard(player))

            case .deployArmy(let hex, let strengths):
                let result = try Conquest.deploy(strengths, to: hex, by: player, state: &state)
                events.append(.deployedArmy(player, hex: hex, total: strengths.reduce(0, +), result: result))
```

In the `.endTurn` case, beside `state.devCardsBoughtThisTurn = [:]`:

```swift
                state.armyCardsBoughtThisTurn = [:]
```

- [ ] **Step 6: Deal on setup end**

`SetupPhase.swift:131`:

```swift
                state.phase = .rollDice(playerIndex: 0)
                Conquest.dealStartingCards(&state)
```

- [ ] **Step 7: Ledger and narrator**

`PublicLedger.swift`, after the `.boughtDevCard` case:

```swift
        case .boughtArmyCard(let seat):
            debit(seat, Conquest.armyCardCost)

        case .deployedArmy:
            break
```

`Settlers/Models/GameReplayNarrator.swift`, after the `.boughtDevCard` case:

```swift
        case .boughtArmyCard(let player):
            return "\(name(player, roster)) raised an army card"
        case .deployedArmy(let player, _, let total, let result):
            let outcome = result?.owner == player ? "holds the hex at \(result!.strength)" : "did not take the hex"
            return "\(name(player, roster)) committed \(total) strength and \(outcome)"
```

- [ ] **Step 8: Run all engine tests**

Run: `swift test --package-path Packages/CatanEngine`
Expected: all pass. Then `swiftlint --strict` → 0 violations.

- [ ] **Step 9: Build the app** (the narrator switch is exhaustive; this proves it compiles)

```bash
SIM=$(python3 scripts/select-qa-simulator.py)
xcodegen generate
xcodebuild -project Settlers.xcodeproj -scheme Settlers -destination "platform=iOS Simulator,id=$SIM" \
  -configuration Debug -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/conquest" build > /tmp/conquest-build.log 2>&1
echo "EXIT=$?"
```
Expected: `EXIT=0`. On failure, read `/tmp/conquest-build.log` for the next exhaustive switch the compiler names and add the case the same way.

- [ ] **Step 10: Commit**

```bash
git add Packages/CatanEngine Settlers/Models/GameReplayNarrator.swift
git commit -m "feat(engine): Conquest army moves - buy, deploy and the starting card"
```
(Body: why one `deployArmy` move covers attack and reinforce; why `legalMoves` lists singles + cheapest winning set instead of all subsets.)

---

### Task 3: Takeover production

**Files:**
- Modify: `Packages/CatanEngine/Sources/CatanEngine/MainPhase.swift` (`payouts`)
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/ConquestProductionTests.swift`

**Interfaces:**
- Consumes: `GameState.garrisons`, `Garrison.owner`.
- Produces: no new API; `MainPhase.payouts` now honours occupation (so `PublicLedger` stays correct for free).

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import CatanEngine

/// A Conquest game with seat 0 and seat 1 each settled on the same 6.
private func sharedSix() -> (GameState, Tile, Resource) {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 2, variant: .conquest)
    let tile = state.board.tiles.first { $0.numberToken == 6 && $0.coordinate != state.board.robberTile }!
    let corners = HexGeometry.corners(of: tile.coordinate)
    state.players[0].settlements.insert(corners[0])
    state.players[1].settlements.insert(corners[3])
    guard case .resource(let resource) = tile.kind else { fatalError("6 is always a resource") }
    return (state, tile, resource)
}

@Test func aTribeHeldHexPaysEveryoneAsNormal() {
    var (state, tile, resource) = sharedSix()
    MainPhase.rollDice(state: &state, roll: tile.numberToken!)
    #expect(state.players[0].resources[resource] == 1)
    #expect(state.players[1].resources[resource] == 1)
}

@Test func anOccupiedHexPaysOnlyTheOccupierPlusOne() {
    var (state, tile, resource) = sharedSix()
    state.garrisons[tile.coordinate] = Garrison(owner: state.players[0].id, strength: 3)
    MainPhase.rollDice(state: &state, roll: tile.numberToken!)
    #expect(state.players[0].resources[resource] == 2)
    #expect((state.players[1].resources[resource] ?? 0) == 0)
}

@Test func theRobberBlocksAnOccupiedHexIncludingTheBonus() {
    var (state, tile, resource) = sharedSix()
    state.garrisons[tile.coordinate] = Garrison(owner: state.players[0].id, strength: 3)
    state.board.robberTile = tile.coordinate
    MainPhase.rollDice(state: &state, roll: tile.numberToken!)
    #expect((state.players[0].resources[resource] ?? 0) == 0)
}

@Test func occupierBonusRespectsBankShortage() {
    var (state, tile, resource) = sharedSix()
    state.garrisons[tile.coordinate] = Garrison(owner: state.players[0].id, strength: 3)
    state.bank[resource] = 1
    MainPhase.rollDice(state: &state, roll: tile.numberToken!)
    #expect(state.players[0].resources[resource] == 1, "a sole claimant takes what is left")
}

@Test func anUnoccupiedHexPaysEveryoneAsNormal() {
    var (state, tile, resource) = sharedSix()
    state.garrisons[tile.coordinate] = nil
    MainPhase.rollDice(state: &state, roll: tile.numberToken!)
    #expect(state.players[1].resources[resource] == 1)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/CatanEngine --filter ConquestProduction`
Expected: `anOccupiedHexPaysOnlyTheOccupierPlusOne` and `occupierBonusRespectsBankShortage` fail.

- [ ] **Step 3: Implement**

In `MainPhase.payouts`, replace the vertex loop inside `for tile in state.board.tiles { ... }` with:

```swift
            // Conquest: an occupied hex pays only its occupier, plus one. A
            // tribe (`owner == nil`) or an unoccupied hex pays as normal, and
            // a standard game has no garrisons, so this is a no-op there.
            let occupier = state.garrisons[tile.coordinate]?.owner
            for vertex in HexGeometry.corners(of: tile.coordinate) {
                for (index, player) in state.players.enumerated() where occupier == nil || player.id == occupier {
                    if player.cities.contains(vertex) {
                        demand[resource, default: []].append((index, 2))
                    } else if player.settlements.contains(vertex) {
                        demand[resource, default: []].append((index, 1))
                    }
                }
            }
            if let occupier, let index = state.players.firstIndex(where: { $0.id == occupier }) {
                demand[resource, default: []].append((index, 1))
            }
```

Update the doc comment on `rollDice` with one sentence: "In Conquest, an occupied hex pays only its occupier, plus one."

- [ ] **Step 4: Run all engine tests**

Run: `swift test --package-path Packages/CatanEngine`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/CatanEngine
git commit -m "feat(engine): occupied hexes pay only their occupier, plus one"
```
(Body: the hand-worked economics from the spec — denial alone is a wash; the +1 makes a card pay for itself.)

---

### Task 4: Bots play Conquest

**Files:**
- Create: `Packages/CatanAI/Sources/CatanAI/ConquestHeuristics.swift`
- Modify: `Packages/CatanAI/Sources/CatanAI/Bot.swift` (`decideMainTurn`, `matchLegal`)
- Test: `Packages/CatanAI/Tests/CatanAITests/ConquestBotTests.swift`

**Interfaces:**
- Consumes: `GameMove.buyArmyCard/.deployArmy`, `Conquest.outcome(of:against:by:)`, `Conquest.armyCardCost`, `DiceOdds.pips(for:)`, `GameState.garrisons/armyHands`.
- Produces: `enum ConquestHeuristics { static func chooseDeploy(state:player:legal:) -> GameMove?; static func shouldBuyArmyCard(state:player:) -> Bool }`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CatanEngine
@testable import CatanAI

private func conquestMainTurn(seed: UInt64 = 1) -> GameState {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: seed, variant: .conquest)
    // Finish setup the way bots would, so buildings exist.
    var session = GameSession(state: state, policies: Dictionary(uniqueKeysWithValues:
        state.players.map { ($0.id, Bot(personality: .balanced) as any Policy) }), policySeed: seed)
    while case .setupForward = session.state.phase { _ = try? session.step() }
    while case .setupBackward = session.state.phase { _ = try? session.step() }
    state = session.state
    state.phase = .mainTurn(playerIndex: 0)
    return state
}

@Test func aBotTakesAHexWhenItHoldsEnoughToWinIt() {
    var state = conquestMainTurn()
    state.armyHands[state.players[0].id] = [9]
    let legal = RulesEngine.legalMoves(for: state)
    let move = ConquestHeuristics.chooseDeploy(state: state, player: state.players[0].id, legal: legal)
    guard case .deployArmy(let hex, let strengths)? = move else {
        Issue.record("expected a deploy, got \(String(describing: move))"); return
    }
    let after = Conquest.outcome(of: strengths.reduce(0, +), against: state.garrisons[hex], by: state.players[0].id)
    #expect(after?.owner == state.players[0].id)
}

@Test func aBotDoesNotThrowCardsAtAHexItCannotTake() {
    var state = conquestMainTurn()
    state.armyHands[state.players[0].id] = [1]
    for (hex, _) in state.garrisons { state.garrisons[hex] = Garrison(owner: nil, strength: 5) }
    let legal = RulesEngine.legalMoves(for: state)
    #expect(ConquestHeuristics.chooseDeploy(state: state, player: state.players[0].id, legal: legal) == nil)
}

@Test func aStandardGameNeverAsksForArmyMoves() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    state.phase = .mainTurn(playerIndex: 0)
    #expect(!ConquestHeuristics.shouldBuyArmyCard(state: state, player: state.players[0].id))
}

@Test func seededConquestGamesFinishWithOnlyLegalMoves() throws {
    for seed: UInt64 in 1...3 {
        let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed, variant: .conquest)
        var session = GameSession(state: state, policies: Dictionary(uniqueKeysWithValues:
            state.players.map { ($0.id, Bot(personality: .balanced) as any Policy) }), policySeed: seed)
        var armyMoves = 0
        for _ in 0..<6_000 {
            guard let step = try session.step() else { break }
            if case .deployArmy = step.move { armyMoves += 1 }
        }
        #expect({ if case .gameOver = session.state.phase { true } else { false } }(), "seed \(seed) did not finish")
        #expect(armyMoves > 0, "seed \(seed): bots never deployed")
    }
}
```

`GameSession(state:policies:policySeed:)` and `step() throws -> Step?` are the real API (`GameSession.swift:128`, `:422`).

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/CatanAI --filter Conquest`
Expected: compile failure, `cannot find 'ConquestHeuristics' in scope`.

- [ ] **Step 3: Implement `ConquestHeuristics.swift`**

```swift
import CatanEngine

/// Conquest decisions for `Bot`. Heuristic, untrained: this exists to make the
/// variant playable and measurable, not to be strong.
enum ConquestHeuristics {
    /// Mean strength of the Classic deck, used as a rival card's expected value.
    /// ponytail: ignores cards already seen; count spent cards via `PublicLedger` if bots over-reinforce.
    static let expectedCardStrength = 4.0

    /// The best legal deploy that takes a hex, else a reinforcement of a held hex
    /// a rival could plausibly break next turn, else nil. Never a losing attack.
    static func chooseDeploy(state: GameState, player: PlayerID, legal: [GameMove]) -> GameMove? {
        var best: (move: GameMove, score: Double)?
        for move in legal {
            guard case .deployArmy(let hex, let strengths) = move else { continue }
            let total = strengths.reduce(0, +)
            let current = state.garrisons[hex]
            let score: Double
            if current?.owner == player {
                guard isThreatened(hex, garrison: current!.strength, state: state, player: player),
                      strengths.count == 1 else { continue }
                score = hexValue(hex, for: player, in: state) * 0.5 / Double(total)
            } else {
                guard Conquest.outcome(of: total, against: current, by: player)?.owner == player else { continue }
                score = hexValue(hex, for: player, in: state) / Double(total)
            }
            if best == nil || score > best!.score { best = (move, score) }
        }
        return best?.move
    }

    /// Buy only in Conquest, only when affordable, and only if some reachable
    /// hex is still not ours - otherwise the card has nothing to do.
    static func shouldBuyArmyCard(state: GameState, player: PlayerID) -> Bool {
        guard state.variant == .conquest, !state.armyDeck.isEmpty,
              let owner = state.players.first(where: { $0.id == player }),
              RulesEngine.canAfford(Conquest.armyCardCost, player: owner) else { return false }
        return state.board.tiles.map(\.coordinate).sorted().contains {
            Conquest.canDeploy(to: $0, by: player, in: state) && state.garrisons[$0]?.owner != player
        }
    }

    /// Pips x (the +1 bonus, plus every rival building the takeover silences).
    private static func hexValue(_ hex: HexCoordinate, for player: PlayerID, in state: GameState) -> Double {
        guard let token = state.board.tiles.first(where: { $0.coordinate == hex })?.numberToken else { return 0 }
        let corners = HexGeometry.corners(of: hex)
        let silenced = state.players.filter { $0.id != player }.reduce(0) { total, rival in
            total + corners.reduce(0) { $0 + (rival.cities.contains($1) ? 2 : rival.settlements.contains($1) ? 1 : 0) }
        }
        return Double(DiceOdds.pips(for: token)) * Double(1 + silenced)
    }

    /// A rival touching `hex` whose visible hand, at expected strength, breaks it.
    private static func isThreatened(_ hex: HexCoordinate, garrison: Int, state: GameState, player: PlayerID) -> Bool {
        state.players.contains { rival in
            rival.id != player && Conquest.canDeploy(to: hex, by: rival.id, in: state)
                && Double(state.armyHands[rival.id, default: []].count) * expectedCardStrength >= Double(garrison)
        }
    }
}
```

`HexGeometry` is an `internal enum` (`Board.swift:66`). Make the enum `public` and `corners(of:)` (`Board.swift:83`) `public static`; leave its other members internal.

- [ ] **Step 4: Wire into `Bot.decideMainTurn`**

After the `consider(DevCardHeuristics.choosePlay(...), ...)` block:

```swift
        // Deploying spends cards already paid for, so like playing a dev card
        // it never competes with a build for resources.
        consider(
            ConquestHeuristics.chooseDeploy(state: state, player: player, legal: legal),
            score: weights.playDevCardMoveBase
        )
```

Inside `if buildMove == nil {`, after the dev-card buy block:

```swift
            if ConquestHeuristics.shouldBuyArmyCard(state: state, player: player) {
                consider(.buyArmyCard, score: weights.buyDevCardMoveBase)
            }
```

In `matchLegal`, before `case (.endTurn, .endTurn)`:

```swift
            case (.buyArmyCard, .buyArmyCard): return candidate
            case (.deployArmy, .deployArmy) where desired == candidate: return candidate
```

- [ ] **Step 5: Run the AI tests**

Run: `swift test --package-path Packages/CatanAI --filter "Conquest|SeededGameFingerprint"`
Expected: all pass; **the standard fingerprints are unchanged**. If `seededConquestGamesFinishWithOnlyLegalMoves` hits the move cap, record the final VPs and army-deck count in the failure and stop — that is a rules finding for Jake, not something to tune around.

- [ ] **Step 6: Full AI suite + lint**

Run: `swift test --package-path Packages/CatanAI` (55–175s) and `swiftlint --strict`.
Expected: all pass, 0 violations.

- [ ] **Step 7: Commit**

```bash
git add Packages/CatanAI Packages/CatanEngine/Sources/CatanEngine/Board.swift
git commit -m "feat(ai): heuristic Conquest play - take hexes, reinforce threatened ones, buy when idle"
```

---

### Task 5: Measure it

**Files:**
- Modify: `Packages/CatanAI/Sources/sim/main.swift` (`--variant` flag, three JSONL metrics)
- Create: `Packages/CatanAI/Tests/CatanAITests/ConquestFingerprintTests.swift`
- Create: `docs/AI_summaries/2026-09-23-conquest-first-measurement.md`

**Interfaces:**
- Consumes: everything above.
- Produces: JSONL fields `variant`, `armyCardsBought`, `pvpCaptures`, `firstPrimeHolder` (seat index or `null`).

- [ ] **Step 1: Add the flag and metrics**

In `SimulationConfiguration`: `var variant = GameVariant.standard`, and pass `variant: variant` in `state(seed:)`.

In the option parser, beside `case "--mode":`:

```swift
        case "--variant":
            guard let variant = GameVariant(rawValue: uniqueValue(for: "--variant")) else {
                fail("--variant must be standard or conquest")
            }
            options.configuration.variant = variant
```

Add `[--variant standard|conquest]` to `usage`.

Add to `GameResult`: `let armyCardsBought: Int`, `let pvpCaptures: Int`, `let firstPrimeHolder: PlayerID?`.

In `playGame`, before the loop: `var armyCardsBought = 0, pvpCaptures = 0` and `var firstPrimeHolder: PlayerID?`. Capture `let before = session.state.garrisons` immediately before `session.commit(...)`, and after `guard let step else { break }`:

```swift
        for event in step.events {
            switch event {
            case .boughtArmyCard: armyCardsBought += 1
            case .deployedArmy(let actor, let hex, _, let result) where result?.owner == actor:
                if let previous = before[hex]?.owner, previous != actor { pvpCaptures += 1 }
                let token = session.state.board.tiles.first { $0.coordinate == hex }?.numberToken
                if firstPrimeHolder == nil, token == 6 || token == 8 { firstPrimeHolder = actor }
            default: break
            }
        }
```

Pass the three into `GameResult(...)`. In `jsonLine`, before `"behavior"`:

```swift
        + "\"variant\":\"\(configuration.variant.rawValue)\","
        + "\"armyCardsBought\":\(result.armyCardsBought),\"pvpCaptures\":\(result.pvpCaptures),"
        + "\"firstPrimeHolder\":\(result.firstPrimeHolder.map { "\($0.index)" } ?? "null"),"
```

Bump `resultSchemaVersion` to 6.

- [ ] **Step 2: Prove cross-process determinism**

```bash
for i in 1 2 3; do swift run -c release --package-path Packages/CatanAI sim --variant conquest --seed 1 --games 3 --jsonl \
  | python3 -c "import sys,json; print([json.loads(l)['fingerprint'] for l in sys.stdin])"; done
```
Expected: three identical lines (three separate processes, three hash seeds). If they differ, ordering leaked into Conquest code — find it before going on.

- [ ] **Step 3: Pin it**

`ConquestFingerprintTests.swift` — copy the `fingerprint` and game-loop helpers from `SeededGameFingerprintTests.swift` (they are `private` there), play seeds 1–3 with `variant: .conquest` and default seats, and `#expect` the three fingerprints from Step 2 verbatim. Doc comment: why this exists (cross-process, not same-process), date recorded.

Run: `swift test --package-path Packages/CatanAI --filter ConquestFingerprint` → PASS.

- [ ] **Step 4: Run the measurement**

```bash
xcrun simctl shutdown all
for mode in classic vast; do
  nohup swift run -c release --package-path Packages/CatanAI sim --variant conquest --mode $mode \
    --seed 1000 --games 200 --jsonl > "$HOME/conquest-$mode.jsonl" 2> "$HOME/conquest-$mode.err" &
done; disown -a
```
(Detached per the "Detached gate runs" memory; the low-memory watchdog kills tracked jobs.) Then summarise:

```bash
python3 - <<'EOF'
import json, os
for mode in ("classic", "vast"):
    games = [json.loads(l) for l in open(os.path.expanduser(f"~/conquest-{mode}.jsonl"))]
    held = [g for g in games if g["firstPrimeHolder"] is not None and g["winner"] is not None]
    rate = sum(g["winner"] == g["firstPrimeHolder"] for g in held) / max(1, len(held))
    avg = lambda k: sum(g[k] for g in games) / len(games)
    finished = sum(g["winner"] is not None for g in games)
    print(f"{mode}: {len(games)} games, {finished} finished, first-6/8 holder wins {rate:.1%} "
          f"(n={len(held)}, baseline 25%), army cards/game {avg('armyCardsBought'):.1f}, "
          f"PvP captures/game {avg('pvpCaptures'):.1f}")
EOF
```

- [ ] **Step 5: Write it up**

`docs/AI_summaries/2026-09-23-conquest-first-measurement.md`: the command lines, the table from Step 4, and a verdict per spec hypothesis — (a) snowball: holder win rate vs 25%, flag if the 95% interval (`p ± 1.96·sqrt(p(1-p)/n)`) excludes 25%; (b) armies bought per game; (c) whether PvP happens at all. State plainly that these are Balanced-heuristic bots, not humans. If snowball is confirmed, list the spec's brakes in order (price, flatter deck, upkeep) — **do not change rules; that is Jake's call.**

- [ ] **Step 6: Commit**

```bash
git add Packages/CatanAI docs/AI_summaries
git commit -m "feat(sim): measure Conquest - army purchases, PvP captures, first 6/8 holder"
```

Do not push. Report the Step 4 table to Jake; the UI plan is written after he has seen it.
