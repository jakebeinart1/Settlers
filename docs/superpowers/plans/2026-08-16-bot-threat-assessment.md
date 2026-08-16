# Bot Threat Assessment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `CatanAI` bots a per-opponent threat score (VP + production + hidden dev cards + proximity to Largest Army/Longest Road) and wire it, proportionally, into robber targeting, build placement (settlement + road denial), trade acceptance, and Monopoly targeting.

**Architecture:** One new file, `ThreatAssessment.swift`, exposes `scores(excluding:in:)` and `relativeWeight(for:excluding:in:)`. Four existing files (`RobberHeuristics`, `BuildPlanner`, `TradeHeuristics`, `DevCardHeuristics`) each get a small, targeted change that calls into it. No new move types, no engine (`CatanEngine`) changes, no search/lookahead.

**Tech Stack:** Swift 6, Swift Testing (`@Test`/`#expect`), Swift Package Manager. Package under test: `Packages/CatanAI` (depends on `Packages/CatanEngine`).

## Global Constraints

- Every heuristic suggestion must still be validated by `Bot.matchLegal` against `RulesEngine.legalMoves` before use — never bypass that contract (see `Bot.swift` header comment).
- No lookahead/search — score each legal move once, in isolation (spec's Non-goals).
- No changes to `TradeOffer`/`CatanEngine` public models — `ThreatAssessment` and its consumers live entirely in `CatanAI`.
- Run tests with: `cd Packages/CatanAI && swift test`
- Design reference: `docs/superpowers/specs/2026-08-16-bot-threat-assessment-design.md`

---

### Task 1: `ThreatAssessment` — base score (VP, production, dev cards)

**Files:**
- Create: `Packages/CatanAI/Sources/CatanAI/ThreatAssessment.swift`
- Test: `Packages/CatanAI/Tests/CatanAITests/ThreatAssessmentTests.swift`

**Interfaces:**
- Produces: `ThreatAssessment.score(for player: PlayerID, in state: GameState) -> Double` (internal, not public — only `scores`/`relativeWeight` need to be `public`, but keep `score` `static func` with no access modifier inside the `enum` so `ThreatAssessmentTests` can call it via `@testable import CatanAI`).

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CatanEngine
@testable import CatanAI

@Test func scoreWeighsVictoryPointsHeavily() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[0].settlements.insert(vertex)

    let withSettlement = ThreatAssessment.score(for: player, in: state)

    var noSettlement = state
    noSettlement.players[0].settlements.removeAll()
    let without = ThreatAssessment.score(for: player, in: noSettlement)

    // 1 VP difference must show up as (at least) the VP weight - other
    // components (production) also shift with the same settlement, so this
    // is a lower bound, not an exact diff.
    #expect(withSettlement - without >= 10.0)
}

@Test func scoreIncludesProductionStrengthWeightedByPips() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    // Pick the two vertices with the most differing pip-weighted production
    // among on-board vertices, so the test isn't sensitive to board layout.
    let scored = state.board.onBoardVertices.map { vertex in
        (vertex, PlacementHeuristics.score(vertex: vertex, board: state.board))
    }.sorted { $0.1 > $1.1 }
    let best = scored.first!
    let worst = scored.last!
    #expect(best.1 > worst.1, "test board too uniform to distinguish production")

    state.players[0].settlements = [best.0]
    let highProduction = ThreatAssessment.score(for: player, in: state)

    state.players[0].settlements = [worst.0]
    let lowProduction = ThreatAssessment.score(for: player, in: state)

    #expect(highProduction > lowProduction)
}

@Test func scoreCountsCityProductionAtDoubleWeight() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let vertex = state.board.onBoardVertices.sorted().first!

    state.players[0].settlements = [vertex]
    let settlementScore = ThreatAssessment.score(for: player, in: state)

    state.players[0].settlements = []
    state.players[0].cities = [vertex]
    let cityScore = ThreatAssessment.score(for: player, in: state)

    // City is worth +10 VP-equivalent (1 more VP than settlement, weighted
    // 10) plus double the production term versus a settlement on the same
    // vertex - so the gap must exceed the flat VP difference alone.
    let production = PlacementHeuristics.score(vertex: vertex, board: state.board)
    #expect(cityScore - settlementScore > 10.0)
    #expect(cityScore - settlementScore >= 10.0 + production - 0.001)
}

@Test func scoreIncludesHeldDevCardCount() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    let baseline = ThreatAssessment.score(for: player, in: state)
    state.players[0].devCards = [.knight, .knight]
    let withDevCards = ThreatAssessment.score(for: player, in: state)

    #expect(withDevCards - baseline == 3.0) // 1.5 per card
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/CatanAI && swift test --filter ThreatAssessmentTests`
Expected: FAIL to compile — `ThreatAssessment` doesn't exist yet.

- [ ] **Step 3: Implement the base score**

```swift
import CatanEngine

/// A single per-opponent "how dangerous is this player" evaluation, used by
/// every other heuristic (`RobberHeuristics`, `BuildPlanner`,
/// `TradeHeuristics`, `DevCardHeuristics`) instead of each one inventing its
/// own notion of "the leader". See
/// `docs/superpowers/specs/2026-08-16-bot-threat-assessment-design.md`.
public enum ThreatAssessment {
    /// Weight applied to each victory point - the single biggest signal,
    /// since it's the actual win condition.
    private static let victoryPointWeight = 10.0
    /// Weight applied to a held (unplayed) dev card - a hidden but real
    /// threat (could be a knight toward Largest Army, or a VP card).
    private static let devCardWeight = 1.5

    /// Raw threat score for a single player - current standing plus how
    /// close they are to a sudden VP swing. Not comparative on its own; see
    /// `scores`/`relativeWeight` for cross-player comparison.
    static func score(for playerID: PlayerID, in state: GameState) -> Double {
        guard let player = state.players.first(where: { $0.id == playerID }) else { return 0 }

        let production = player.settlements.reduce(0.0) { partial, vertex in
            partial + PlacementHeuristics.score(vertex: vertex, board: state.board)
        } + player.cities.reduce(0.0) { partial, vertex in
            partial + PlacementHeuristics.score(vertex: vertex, board: state.board) * 2.0
        }

        let vp = Double(state.victoryPoints(for: playerID)) * victoryPointWeight
        let devCards = Double(player.devCards.count) * devCardWeight

        return vp + production + devCards
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/CatanAI && swift test --filter ThreatAssessmentTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/CatanAI/Sources/CatanAI/ThreatAssessment.swift Packages/CatanAI/Tests/CatanAITests/ThreatAssessmentTests.swift
git commit -m "Add ThreatAssessment base score (VP + production + dev cards)"
```

---

### Task 2: `ThreatAssessment` — milestone swing bonus (Largest Army / Longest Road)

**Files:**
- Modify: `Packages/CatanAI/Sources/CatanAI/ThreatAssessment.swift`
- Test: `Packages/CatanAI/Tests/CatanAITests/ThreatAssessmentTests.swift`

**Interfaces:**
- Consumes: `LongestRoad.length(for player: Player, in state: GameState) -> Int` (existing, `Packages/CatanEngine/Sources/CatanEngine/LongestRoad.swift:27`).
- Produces: `score(for:in:)`'s return now includes the swing bonus (no signature change).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func scoreAddsLargestArmySwingBonusWhenOneKnightAway() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    let baseline = ThreatAssessment.score(for: player, in: state)
    state.players[0].playedKnights = 2
    let oneAway = ThreatAssessment.score(for: player, in: state)

    #expect(oneAway - baseline == 2.5)
}

@Test func scoreSkipsLargestArmySwingBonusWhenHolderIsFarAhead() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let holder = PlayerID(index: 1)
    state.players[1].playedKnights = 5
    state.largestArmyPlayer = holder

    let baseline = ThreatAssessment.score(for: player, in: state)
    state.players[0].playedKnights = 2
    let stillTwoAway = ThreatAssessment.score(for: player, in: state)

    // Reaching 3 knights wouldn't take Largest Army from a holder already at
    // 5, so no swing bonus applies.
    #expect(stillTwoAway - baseline == 0.0)
}

@Test func scoreAddsLongestRoadSwingBonusWhenOneSegmentFromQualifying() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    let chain = buildChain(from: state.board, length: 4)
    #expect(chain.count == 4, "test board too small to build a 4-edge chain")

    let baseline = ThreatAssessment.score(for: player, in: state)
    state.players[0].roads = Set(chain)
    let fourEdges = ThreatAssessment.score(for: player, in: state)

    #expect(fourEdges - baseline >= 2.5) // production from the new roads' vertices also shifts, so >=, not ==
}

@Test func scoreSkipsLongestRoadSwingBonusWhenFarBehindTheHolder() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let holder = PlayerID(index: 1)

    let holderChain = buildChain(from: state.board, length: 7)
    #expect(holderChain.count == 7, "test board too small to build a 7-edge chain")
    state.players[1].roads = Set(holderChain)
    state.longestRoadPlayer = holder

    let baseline = ThreatAssessment.score(for: player, in: state)
    let shortChain = buildChain(from: state.board, length: 4)
    state.players[0].roads = Set(shortChain)
    let stillBehind = ThreatAssessment.score(for: player, in: state)

    // 4 edges doesn't come close to beating a 7-edge holder, so no bonus -
    // any diff is purely from the roads' own production-adjacent vertices,
    // which the base score doesn't count at all (roads aren't settlements),
    // so this should be exactly 0.
    #expect(stillBehind - baseline == 0.0)
}
```

Add the same `buildChain(from:length:)` test helper `BuildPlannerTests.swift` already defines (`Packages/CatanAI/Tests/CatanAITests/BuildPlannerTests.swift:8-24`) — copy it verbatim into `ThreatAssessmentTests.swift` as a private top-level function (Swift Testing files don't share private helpers across files).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/CatanAI && swift test --filter ThreatAssessmentTests`
Expected: FAIL — the two new "swing bonus" tests fail (`0.0` diffs where bonuses are expected).

- [ ] **Step 3: Implement the swing bonus**

```swift
    /// The VP-equivalent bonus for being one move away from grabbing a
    /// bonus (`Largest Army` or `Longest Road`) that this player doesn't
    /// already hold - each is worth 2 real VP the instant it's claimed, so a
    /// player poised to grab one is more dangerous than their current VP
    /// total alone suggests.
    private static let milestoneSwingBonus = 2.5

    private static func milestoneSwing(for player: Player, in state: GameState) -> Double {
        var bonus = 0.0

        if state.largestArmyPlayer != player.id {
            let holderKnights = state.largestArmyPlayer
                .flatMap { holder in state.players.first(where: { $0.id == holder })?.playedKnights }
                ?? 0
            if player.playedKnights == 2, holderKnights <= 2 {
                bonus += milestoneSwingBonus
            }
        }

        if state.longestRoadPlayer != player.id {
            let length = LongestRoad.length(for: player, in: state)
            let holderLength = state.longestRoadPlayer
                .flatMap { holder in state.players.first(where: { $0.id == holder }) }
                .map { LongestRoad.length(for: $0, in: state) }
                ?? 0
            if length >= max(4, holderLength) {
                bonus += milestoneSwingBonus
            }
        }

        return bonus
    }
```

Then add `+ milestoneSwing(for: player, in: state)` to `score(for:in:)`'s final `return` line.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/CatanAI && swift test --filter ThreatAssessmentTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/CatanAI/Sources/CatanAI/ThreatAssessment.swift Packages/CatanAI/Tests/CatanAITests/ThreatAssessmentTests.swift
git commit -m "Add Largest Army / Longest Road swing bonus to ThreatAssessment"
```

---

### Task 3: `ThreatAssessment` — `scores` and `relativeWeight`

**Files:**
- Modify: `Packages/CatanAI/Sources/CatanAI/ThreatAssessment.swift`
- Test: `Packages/CatanAI/Tests/CatanAITests/ThreatAssessmentTests.swift`

**Interfaces:**
- Produces (public API used by every later task):
  - `ThreatAssessment.scores(excluding player: PlayerID, in state: GameState) -> [(player: PlayerID, score: Double)]`
  - `ThreatAssessment.relativeWeight(for target: PlayerID, excluding player: PlayerID, in state: GameState) -> Double`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func scoresExcludesTheGivenPlayerAndSortsHighestFirst() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[1].settlements.insert(vertex) // player 1 now clearly ahead

    let ranked = ThreatAssessment.scores(excluding: PlayerID(index: 0), in: state)

    #expect(!ranked.contains { $0.player == PlayerID(index: 0) })
    #expect(ranked.first?.player == PlayerID(index: 1))
    #expect(ranked == ranked.sorted { $0.score > $1.score })
}

@Test func relativeWeightIsAboveOneForAnAboveAverageOpponent() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[1].settlements.insert(vertex)
    state.players[1].cities.insert(vertex)

    let weight = ThreatAssessment.relativeWeight(for: PlayerID(index: 1), excluding: PlayerID(index: 0), in: state)
    #expect(weight > 1.0)
}

@Test func relativeWeightIsOneForEveryoneWhenAllScoresAreZero() {
    let state = GameSetup.newGame(board: BoardGenerator.standard())
    for player in state.players where player.id != PlayerID(index: 0) {
        let weight = ThreatAssessment.relativeWeight(for: player.id, excluding: PlayerID(index: 0), in: state)
        #expect(weight == 1.0)
    }
}

@Test func relativeWeightClampsExtremeOutliers() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let vertex = state.board.onBoardVertices.sorted().first!
    // Player 1 gets a huge, artificial lead - real games can't produce
    // scores this lopsided, but the clamp must still hold.
    state.players[1].settlements.insert(vertex)
    state.players[1].cities.insert(vertex)
    state.players[1].devCards = Array(repeating: DevCardType.knight, count: 20)

    let weight = ThreatAssessment.relativeWeight(for: PlayerID(index: 1), excluding: PlayerID(index: 0), in: state)
    #expect(weight <= 3.0)

    let lowWeight = ThreatAssessment.relativeWeight(for: PlayerID(index: 2), excluding: PlayerID(index: 0), in: state)
    #expect(lowWeight >= 0.4)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/CatanAI && swift test --filter ThreatAssessmentTests`
Expected: FAIL to compile — `scores`/`relativeWeight` don't exist yet.

- [ ] **Step 3: Implement `scores` and `relativeWeight`**

```swift
    /// Threat score for every player except `excluding`, highest first.
    public static func scores(excluding player: PlayerID, in state: GameState) -> [(player: PlayerID, score: Double)] {
        state.players
            .filter { $0.id != player }
            .map { (player: $0.id, score: score(for: $0.id, in: state)) }
            .sorted { $0.score > $1.score }
    }

    /// How threatening `target` is relative to the *average* opponent of
    /// `player` - 1.0 means "exactly average". Consumers multiply an
    /// existing effect by this instead of a flat leader/non-leader
    /// constant, so a dominant opponent draws sharply more attention and a
    /// close race doesn't get skewed onto whoever's nominally ahead by a
    /// hair. Clamped to `[0.4, 3.0]` so a single early-game outlier (e.g.
    /// the very first settlement placed) can't produce an extreme swing.
    /// Returns `1.0` for everyone when the average is `0` (e.g. before
    /// setup places anything) - dividing by zero would otherwise produce a
    /// meaningless weight at exactly the moment there's no real signal yet.
    public static func relativeWeight(for target: PlayerID, excluding player: PlayerID, in state: GameState) -> Double {
        let ranked = scores(excluding: player, in: state)
        guard !ranked.isEmpty else { return 1.0 }

        let average = ranked.reduce(0.0) { $0 + $1.score } / Double(ranked.count)
        guard average > 0, let targetScore = ranked.first(where: { $0.player == target })?.score else { return 1.0 }

        return min(3.0, max(0.4, targetScore / average))
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/CatanAI && swift test --filter ThreatAssessmentTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/CatanAI/Sources/CatanAI/ThreatAssessment.swift Packages/CatanAI/Tests/CatanAITests/ThreatAssessmentTests.swift
git commit -m "Add ThreatAssessment.scores/relativeWeight cross-player API"
```

---

### Task 4: Wire `ThreatAssessment` into `RobberHeuristics`

**Files:**
- Modify: `Packages/CatanAI/Sources/CatanAI/RobberHeuristics.swift`
- Modify: `Packages/CatanAI/Sources/CatanAI/Bot.swift:167` (call site)
- Modify: `Packages/CatanAI/Sources/CatanAI/DevCardHeuristics.swift:55` (call site)
- Test: `Packages/CatanAI/Tests/CatanAITests/RobberHeuristicsTests.swift`

**Interfaces:**
- Consumes: `ThreatAssessment.scores(excluding:in:)`, `ThreatAssessment.relativeWeight(for:excluding:in:)` (Task 3).
- Produces: `RobberHeuristics.chooseRobberTarget(state: GameState, player: PlayerID, personality: BotPersonality) -> (HexCoordinate, PlayerID?)` — **signature changes** (adds `personality`). Both existing call sites must be updated in this task or the package won't compile.

- [ ] **Step 1: Write the failing tests**

Add to `RobberHeuristicsTests.swift` (and update the two existing tests' calls to pass `personality: .balanced`):

```swift
@Test func robberDisruptionScalesWithRelativeThreatNotJustRawVictoryPoints() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let tiles = state.board.tiles.map(\.coordinate).filter { $0 != state.board.robberTile }
    let tileA = tiles[0]
    let tileB = tiles[1]

    let vertexA = state.board.onBoardVertices.first { state.board.neighborTiles(of: $0).contains(tileA) }!
    let vertexB = state.board.onBoardVertices.first { state.board.neighborTiles(of: $0).contains(tileB) }!

    // Player 1 sits on tileA with a single settlement; player 2 sits on
    // tileB but is far more developed overall (more dev cards, more
    // production) despite an equal VP count - relative threat should send
    // the robber to tileB, not just wherever VP happens to be highest.
    state.players[1].settlements.insert(vertexA)
    state.players[2].settlements.insert(vertexB)
    state.players[2].devCards = [.knight, .knight, .knight, .knight]

    let (chosenTile, _) = RobberHeuristics.chooseRobberTarget(state: state, player: PlayerID(index: 0), personality: .aggressive)
    #expect(chosenTile == tileB)
}
```

Update the two pre-existing tests' call sites:
```swift
let (chosenTile, victim) = RobberHeuristics.chooseRobberTarget(state: state, player: PlayerID(index: 0), personality: .balanced)
```
(both `robberTargetsLeadingOpponentsTile` and `robberAvoidsOwnTilesWhenAlternativeExists`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/CatanAI && swift test --filter RobberHeuristicsTests`
Expected: FAIL to compile — `chooseRobberTarget` doesn't take `personality` yet.

- [ ] **Step 3: Implement**

In `RobberHeuristics.swift`, replace the whole file's leader-based logic:

```swift
import CatanEngine

/// Picks where to park the robber and (optionally) who to steal from.
public enum RobberHeuristics {
    /// Chooses the tile that maximizes disruption to opponents, weighted by
    /// each occupant's relative threat (see `ThreatAssessment`) and scaled
    /// by how aggressively this bot leans into robber play, while avoiding
    /// tiles that touch the bot's own settlements/cities whenever an
    /// alternative tile exists. Returns the chosen tile plus whichever
    /// occupant is the best victim to name (the highest-threat occupant, or
    /// whoever holds the most resources if threat is a tie).
    ///
    /// This only decides intent - callers (e.g. `Bot.decide`) are
    /// responsible for matching the result against `RulesEngine.legalMoves`,
    /// since a desired victim may not actually be eligible to steal from
    /// (e.g. holds zero resource cards).
    public static func chooseRobberTarget(state: GameState, player: PlayerID, personality: BotPersonality) -> (HexCoordinate, PlayerID?) {
        let candidateTiles = state.board.tiles.map(\.coordinate).filter { $0 != state.board.robberTile }
        guard !candidateTiles.isEmpty else { return (state.board.robberTile, nil) }

        func verticesTouching(_ tile: HexCoordinate) -> [VertexID] {
            state.board.onBoardVertices.filter { $0.touchingTiles.contains(tile) }
        }

        func touchesOwn(_ tile: HexCoordinate) -> Bool {
            guard let me = state.players.first(where: { $0.id == player }) else { return false }
            return verticesTouching(tile).contains { me.settlements.contains($0) || me.cities.contains($0) }
        }

        // Disruption score for `tile`: opponent building weight there,
        // scaled by each occupant's threat relative to the average
        // opponent and by how aggressively this bot leans into robber play.
        func disruption(_ tile: HexCoordinate) -> Double {
            var value = 0.0
            for vertex in verticesTouching(tile) {
                for other in state.players where other.id != player {
                    let weight = 1.0 + ThreatAssessment.relativeWeight(for: other.id, excluding: player, in: state) * personality.aggressiveness * 2.0
                    if other.cities.contains(vertex) { value += 2.0 * weight }
                    else if other.settlements.contains(vertex) { value += 1.0 * weight }
                }
            }
            return value
        }

        let notOwn = candidateTiles.filter { !touchesOwn($0) }
        let pool = notOwn.isEmpty ? candidateTiles : notOwn

        guard let bestTile = pool.max(by: { disruption($0) < disruption($1) }) else {
            return (candidateTiles[0], nil)
        }

        let occupants = state.players.filter { occupant in
            occupant.id != player && verticesTouching(bestTile).contains { occupant.settlements.contains($0) || occupant.cities.contains($0) }
        }
        let threatRanking = ThreatAssessment.scores(excluding: player, in: state)
        let victim = threatRanking
            .first { ranked in occupants.contains { $0.id == ranked.player } }
            .map { $0.player }
            ?? occupants.max(by: { $0.resources.values.reduce(0, +) < $1.resources.values.reduce(0, +) })?.id

        return (bestTile, victim)
    }
}
```

Update the call site in `Bot.swift:167`:
```swift
let (tile, victim) = RobberHeuristics.chooseRobberTarget(state: state, player: player, personality: personality)
```
(`Bot` already has `self.personality` in scope there.)

Update the call site in `DevCardHeuristics.swift:55`:
```swift
let (tile, victim) = RobberHeuristics.chooseRobberTarget(state: state, player: player, personality: personality)
```
(`DevCardHeuristics.choosePlay` already takes `personality` as a parameter.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/CatanAI && swift test --filter RobberHeuristicsTests`
Expected: PASS

Then run the full suite once to confirm the two call-site updates didn't break anything else:
Run: `cd Packages/CatanAI && swift test`
Expected: PASS (or pre-existing failures only, if any existed before this task — there should be none)

- [ ] **Step 5: Commit**

```bash
git add Packages/CatanAI/Sources/CatanAI/RobberHeuristics.swift Packages/CatanAI/Sources/CatanAI/Bot.swift Packages/CatanAI/Sources/CatanAI/DevCardHeuristics.swift Packages/CatanAI/Tests/CatanAITests/RobberHeuristicsTests.swift
git commit -m "Robber targeting uses relative ThreatAssessment weighting"
```

---

### Task 5: `BuildPlanner` — settlement denial bonus

**Files:**
- Modify: `Packages/CatanAI/Sources/CatanAI/BuildPlanner.swift`
- Test: `Packages/CatanAI/Tests/CatanAITests/BuildPlannerTests.swift`

**Interfaces:**
- Consumes: `ThreatAssessment.relativeWeight(for:excluding:in:)` (Task 3).
- Produces: `BuildPlanner.opponentFrontier(for opponentID: PlayerID, in state: GameState) -> Set<VertexID>` (internal, `static`, no access modifier — testable via `@testable import CatanAI`). `.buildSettlement`'s score now includes a denial term (no signature change to `score`/`chooseBuild`).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func opponentFrontierIncludesVacantVertexAdjacentToTheirSettlement() {
    let state = GameSetup.newGame(board: BoardGenerator.standard())
    let opponent = PlayerID(index: 1)
    var withSettlement = state
    let vertex = state.board.onBoardVertices.sorted().first!
    withSettlement.players[1].settlements.insert(vertex)

    let frontier = BuildPlanner.opponentFrontier(for: opponent, in: withSettlement)
    let neighbor = withSettlement.board.adjacentVertices(of: vertex).first { !withSettlement.board.adjacentVertices(of: $0).contains(vertex) == false }
    // Every vertex adjacent to `vertex` should be in the frontier, since
    // nothing else is built anywhere on this fresh board.
    for adjacent in withSettlement.board.adjacentVertices(of: vertex) {
        #expect(frontier.contains(adjacent))
    }
    _ = neighbor // silence unused-var warning if the expect above covers it
}

@Test func opponentFrontierExcludesVerticesTooCloseToAnyExistingBuilding() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let opponent = PlayerID(index: 1)
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[1].settlements.insert(vertex)

    // A third player's settlement one hop past the frontier vertex makes
    // that vertex illegal for anyone (distance rule) - it must drop out.
    guard let frontierVertex = state.board.adjacentVertices(of: vertex).first,
          let blockingVertex = state.board.adjacentVertices(of: frontierVertex).first(where: { $0 != vertex })
    else {
        Issue.record("test board too small for a 2-hop chain")
        return
    }
    state.players[2].settlements.insert(blockingVertex)

    let frontier = BuildPlanner.opponentFrontier(for: opponent, in: state)
    #expect(!frontier.contains(frontierVertex))
}

@Test func buildSettlementScoreIsHigherWhenItDeniesAHighThreatOpponentsFrontier() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let opponentVertex = state.board.onBoardVertices.sorted().first!
    guard let candidate = state.board.adjacentVertices(of: opponentVertex).first else {
        Issue.record("test board too small")
        return
    }

    state.players[1].settlements.insert(opponentVertex)
    let withOpponentNearby = BuildPlanner.score(.buildSettlement(candidate), for: state, player: player, personality: .balanced)!

    var noOpponent = state
    noOpponent.players[1].settlements.removeAll()
    let withoutOpponentNearby = BuildPlanner.score(.buildSettlement(candidate), for: noOpponent, player: player, personality: .balanced)!

    #expect(withOpponentNearby > withoutOpponentNearby)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/CatanAI && swift test --filter BuildPlannerTests`
Expected: FAIL to compile — `opponentFrontier` doesn't exist; the denial-bonus test fails on the `>` assertion (scores currently equal).

- [ ] **Step 3: Implement**

Add to `BuildPlanner.swift` (new members, `internal`/no-modifier so tests can call them):

```swift
    /// Vacant, currently-legal (per the distance rule) vertices `opponentID`
    /// could plausibly reach with one more road from their existing
    /// settlements/cities/roads - a proxy for "their near-term expansion
    /// options", used to value denying opponents a spot as well as taking
    /// one for ourselves. Internal rather than private so
    /// `BuildPlannerTests` can exercise it directly.
    static func opponentFrontier(for opponentID: PlayerID, in state: GameState) -> Set<VertexID> {
        guard let opponent = state.players.first(where: { $0.id == opponentID }) else { return [] }

        var touched = opponent.settlements.union(opponent.cities)
        for edge in opponent.roads {
            let (a, b) = state.board.vertices(of: edge)
            touched.insert(a)
            touched.insert(b)
        }

        let occupied = Set(state.players.flatMap { $0.settlements.union($0.cities) })

        var frontier = Set<VertexID>()
        for vertex in touched {
            for neighbor in state.board.adjacentVertices(of: vertex) {
                guard !occupied.contains(neighbor) else { continue }
                let tooClose = state.board.adjacentVertices(of: neighbor).contains { occupied.contains($0) }
                guard !tooClose else { continue }
                frontier.insert(neighbor)
            }
        }
        return frontier
    }

    /// Bonus for `vertex` sitting in a high-threat opponent's near-term
    /// expansion frontier - taking it denies them a spot, worth close to
    /// (but less than) the production value of taking it for ourselves,
    /// scaled by how threatening that opponent is relative to the average
    /// opponent.
    private static func denialBonus(vertex: VertexID, state: GameState, player: PlayerID) -> Double {
        var bonus = 0.0
        for opponent in state.players where opponent.id != player {
            guard opponentFrontier(for: opponent.id, in: state).contains(vertex) else { continue }
            let production = PlacementHeuristics.score(vertex: vertex, board: state.board)
            bonus += production * 0.4 * ThreatAssessment.relativeWeight(for: opponent.id, excluding: player, in: state)
        }
        return bonus
    }
```

Update `.buildSettlement`'s case in `score(_:for:player:personality:)`:

```swift
        case .buildSettlement(let vertex):
            // A new settlement is close to always worth it - weight
            // production heavily and scale up by expansion appetite. Also
            // adds a bonus for denying a threatening opponent's near-term
            // expansion spot, if this vertex is one.
            let production = PlacementHeuristics.score(vertex: vertex, board: state.board)
            let denial = denialBonus(vertex: vertex, state: state, player: player)
            return 3.0 + production * (0.5 + personality.expansionBias) + denial
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/CatanAI && swift test --filter BuildPlannerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/CatanAI/Sources/CatanAI/BuildPlanner.swift Packages/CatanAI/Tests/CatanAITests/BuildPlannerTests.swift
git commit -m "BuildPlanner settlement scoring denies threatening opponents' frontier spots"
```

---

### Task 6: `BuildPlanner` — road blocking + threat-scaled longest-road claim

**Files:**
- Modify: `Packages/CatanAI/Sources/CatanAI/BuildPlanner.swift`
- Test: `Packages/CatanAI/Tests/CatanAITests/BuildPlannerTests.swift`

**Interfaces:**
- Consumes: `ThreatAssessment.relativeWeight(for:excluding:in:)` (Task 3), `BuildPlanner.claimsLongestRoad` (existing, unchanged signature).
- Produces: `.buildRoad`'s score now includes a blocking term and a threat-scaled claim bonus (no signature change).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func buildRoadScoreIsHigherWhenItBlocksAHighThreatOpponentsNetwork() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let opponentVertex = state.board.onBoardVertices.sorted().first!
    state.players[1].settlements.insert(opponentVertex)

    guard let candidateEdge = state.board.edgesTouching(opponentVertex).first else {
        Issue.record("test board too small")
        return
    }

    let touchingOpponent = BuildPlanner.score(.buildRoad(candidateEdge), for: state, player: player, personality: .balanced)!

    var noOpponent = state
    noOpponent.players[1].settlements.removeAll()
    let notTouchingOpponent = BuildPlanner.score(.buildRoad(candidateEdge), for: noOpponent, player: player, personality: .balanced)!

    #expect(touchingOpponent > notTouchingOpponent)
}

@Test func longestRoadClaimBonusIsLargerWhenTakingItFromAHighThreatHolder() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let holder = PlayerID(index: 1)

    let chain = buildChain(from: state.board, length: 5)
    #expect(chain.count == 5, "test board too small to build a 5-edge chain")
    state.players[0].roads = Set(chain.prefix(4))
    let candidateEdge = chain[4]

    // Nobody holds it yet - baseline claim bonus.
    let baselineScore = BuildPlanner.score(.buildRoad(candidateEdge), for: state, player: player, personality: .balanced)!

    // Now a highly-developed opponent holds it instead - taking it should
    // score higher than the baseline claim.
    var withThreatHolder = state
    withThreatHolder.longestRoadPlayer = holder
    withThreatHolder.players[1].devCards = [.knight, .knight, .knight, .knight, .knight]
    let holderScore = BuildPlanner.score(.buildRoad(candidateEdge), for: withThreatHolder, player: player, personality: .balanced)!

    #expect(holderScore > baselineScore)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Packages/CatanAI && swift test --filter BuildPlannerTests`
Expected: FAIL — both new assertions fail (scores currently equal in each pair).

- [ ] **Step 3: Implement**

Add a new private helper to `BuildPlanner.swift`:

```swift
    /// Bonus for `edge` touching a threatening opponent's existing
    /// road/settlement/city network - building it here denies them that
    /// extension, scaled by how threatening they are relative to the
    /// average opponent.
    private static func blocksOpponentNetwork(_ edge: EdgeID, state: GameState, player: PlayerID) -> Double {
        let (a, b) = state.board.vertices(of: edge)
        var bonus = 0.0
        for opponent in state.players where opponent.id != player {
            guard !opponent.roads.contains(edge) else { continue }
            let opponentRoadVertices = opponent.roads.flatMap { roadEdge -> [VertexID] in
                let (ra, rb) = state.board.vertices(of: roadEdge)
                return [ra, rb]
            }
            let touchesOpponentNetwork = [a, b].contains { vertex in
                opponent.settlements.contains(vertex) || opponent.cities.contains(vertex) || opponentRoadVertices.contains(vertex)
            }
            guard touchesOpponentNetwork else { continue }
            bonus += 1.0 * ThreatAssessment.relativeWeight(for: opponent.id, excluding: player, in: state)
        }
        return bonus
    }
```

Update `.buildRoad`'s case in `score(_:for:player:personality:)`:

```swift
        case .buildRoad(let edge):
            // Roads are cheap groundwork; value them modestly, with a bonus
            // for opening up a newly-reachable high-value settlement spot,
            // a bonus for blocking a threatening opponent's network, plus a
            // large bonus if this exact road would hand *us* the
            // longest-road bonus (2 VP) right now - larger still if it
            // would take that bonus away from a currently-threatening
            // holder, not just claim it fresh.
            let (a, b) = state.board.vertices(of: edge)
            let reachable = [a, b].flatMap { state.board.adjacentVertices(of: $0) }
            let bestReachable = reachable
                .map { PlacementHeuristics.score(vertex: $0, board: state.board) }
                .max() ?? 0
            let blockingBonus = blocksOpponentNetwork(edge, state: state, player: player)
            var longestRoadBonus = 0.0
            if claimsLongestRoad(edge, for: player, in: state) {
                let holderWeight = state.longestRoadPlayer
                    .map { holder in ThreatAssessment.relativeWeight(for: holder, excluding: player, in: state) }
                    ?? 1.0
                longestRoadBonus = 2.5 * (state.longestRoadPlayer == nil ? 1.0 : holderWeight)
            }
            return 0.5 + personality.expansionBias + bestReachable * 0.2 + blockingBonus + longestRoadBonus
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/CatanAI && swift test --filter BuildPlannerTests`
Expected: PASS

Also re-run the pre-existing `buildRoadScoreIncludesLongestRoadBonusOnlyWhenItWouldBeClaimed` test (Task 6 changes the formula it exercises) to confirm it still passes as-is — the "nobody holds it yet" case keeps the `2.5` flat value (`holderWeight` multiplier is `1.0` when `longestRoadPlayer == nil`), so no edit to that test should be needed. If it fails, adjust the formula's `nil`-holder branch (not the test) to preserve the exact `2.5` baseline.

- [ ] **Step 5: Commit**

```bash
git add Packages/CatanAI/Sources/CatanAI/BuildPlanner.swift Packages/CatanAI/Tests/CatanAITests/BuildPlannerTests.swift
git commit -m "BuildPlanner road scoring blocks threatening opponents and scales longest-road claim by their threat"
```

---

### Task 7: `TradeHeuristics` — threat-scaled accept threshold

**Files:**
- Modify: `Packages/CatanAI/Sources/CatanAI/TradeHeuristics.swift`
- Test: `Packages/CatanAI/Tests/CatanAITests/TradeHeuristicsTests.swift`

**Interfaces:**
- Consumes: `ThreatAssessment.relativeWeight(for:excluding:in:)` (Task 3).
- Produces: `TradeHeuristics.evaluate` — same signature, updated threshold logic.

- [ ] **Step 1: Write the failing test**

First read `TradeHeuristicsTests.swift` to match its existing `TradeOffer`/state construction style, then add:

```swift
@Test func evaluateRequiresABetterDealFromAHighThreatProposer() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let receiver = PlayerID(index: 0)
    let proposer = PlayerID(index: 1)

    // Make the receiver's build target genuinely blocked on wool, so
    // `resourceValue` treats the incoming wool as worth something, but the
    // deal is only marginally favorable (a wash on ore).
    state.players[0].resources = [.grain: 2, .ore: 1]
    let offer = TradeOffer(from: proposer, give: [.wool: 1], want: [.ore: 1])

    // Baseline: proposer is an average opponent (nobody else built
    // anything), so this should read the same as today.
    let baselineAccept = TradeHeuristics.evaluate(offer: offer, receiver: receiver, state: state, personality: .balanced)

    // Now make the proposer dramatically more threatening than the other
    // opponents - the same marginal deal should now fail.
    var withThreat = state
    let vertex = state.board.onBoardVertices.sorted().first!
    withThreat.players[1].settlements.insert(vertex)
    withThreat.players[1].cities.insert(vertex)
    withThreat.players[1].devCards = Array(repeating: DevCardType.knight, count: 10)
    let underThreat = TradeHeuristics.evaluate(offer: offer, receiver: receiver, state: withThreat, personality: .balanced)

    #expect(!(underThreat && !baselineAccept)) // threat should never make acceptance *more* likely
    #expect(baselineAccept || !underThreat) // if baseline already rejects, threat case must too (monotonic tightening)
}
```

Adjust the exact `resources`/`offer` numbers if a dry run shows `baselineAccept` isn't `true` — the goal is a case that's a real (if marginal) accept at baseline `relativeWeight == 1.0`, then flips to reject once the proposer's weight is scaled up. Print `TradeHeuristics.evaluate`'s inputs via a throwaway `print` while iterating locally if needed, then remove it before committing.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/CatanAI && swift test --filter TradeHeuristicsTests`
Expected: FAIL — `underThreat` is identical to `baselineAccept` since threat isn't factored in yet (the monotonic assertions should still trivially pass since both sides are equal in this case; iterate the offer numbers until `baselineAccept == true` and confirm the new test fails specifically because `underThreat` also comes back `true` when it should flip to `false` post-implementation — assert `#expect(baselineAccept && !underThreat)` directly instead of the two monotonic checks once you've found numbers that produce a clean accept-then-reject pair, since that's the real behavior under test).

- [ ] **Step 3: Implement**

In `TradeHeuristics.swift`, update `evaluate`:

```swift
    /// Accepts `offer` if what `receiver` would gain (`offer.give`) is worth
    /// more to their current build plan than what they'd give up
    /// (`offer.want`), with the bar lowered the more trade-willing their
    /// personality is - but never low enough to accept a net loss - and
    /// raised the more threatening `offer.from` is relative to the
    /// receiver's other opponents, since accepting hands that player
    /// resources. (`0.5 - tradeWillingness` used to go negative for
    /// high-willingness personalities - e.g. -0.3 for `.cautious` - which
    /// meant they'd accept a real net loss as long as it wasn't too big a
    /// one; clamping the threshold at 0 was the fix.)
    public static func evaluate(offer: TradeOffer, receiver: PlayerID, state: GameState, personality: BotPersonality) -> Bool {
        guard let receiverPlayer = state.players.first(where: { $0.id == receiver }) else { return false }

        let gainValue = offer.give.reduce(0.0) { partial, entry in
            partial + resourceValue(entry.key, for: receiverPlayer, personality: personality) * Double(entry.value)
        }
        let costValue = offer.want.reduce(0.0) { partial, entry in
            partial + resourceValue(entry.key, for: receiverPlayer, personality: personality) * Double(entry.value)
        }

        let netGain = gainValue - costValue
        let proposerWeight = ThreatAssessment.relativeWeight(for: offer.from, excluding: receiver, in: state)
        let threshold = max(0, 0.5 - personality.tradeWillingness) * proposerWeight
        return netGain > threshold
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/CatanAI && swift test --filter TradeHeuristicsTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/CatanAI/Sources/CatanAI/TradeHeuristics.swift Packages/CatanAI/Tests/CatanAITests/TradeHeuristicsTests.swift
git commit -m "TradeHeuristics.evaluate raises the bar for high-threat proposers"
```

---

### Task 8: `DevCardHeuristics` — threat-weighted Monopoly targeting

**Files:**
- Modify: `Packages/CatanAI/Sources/CatanAI/DevCardHeuristics.swift`
- Test: `Packages/CatanAI/Tests/CatanAITests/DevCardHeuristicsTests.swift`

**Interfaces:**
- Consumes: `ThreatAssessment.relativeWeight(for:excluding:in:)` (Task 3).
- Produces: `opponentTotal` now returns `Double` (was `Int`) — internal helper, only used within `DevCardHeuristics.swift`, so this is not a breaking change for other files.

- [ ] **Step 1: Write the failing test**

```swift
@Test func monopolyTargetsResourceHeldByTheHigherThreatOpponent() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    state.players[0].devCards = [.monopoly]
    state.players[0].resources = [.ore: 0, .wool: 0] // both missing for the settlement target below
    state.players[0].settlements = [] // nearest target stays "settlement" (empty cost missing all of it)

    // Both opponents hold 3 of a different resource - equal raw totals -
    // but player 1 is dramatically more threatening than player 2.
    state.players[1].resources = [.wool: 3]
    state.players[2].resources = [.ore: 3]
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[1].settlements.insert(vertex)
    state.players[1].cities.insert(vertex)
    state.players[1].devCards.append(contentsOf: Array(repeating: DevCardType.knight, count: 10))

    let move = DevCardHeuristics.choosePlay(state: state, player: player, personality: .balanced)
    #expect(move.map { if case .playMonopoly(let resource) = $0 { return resource } else { return nil } } == .wool)
}
```

Check `Building.settlementCost`'s exact resource set first (`Packages/CatanEngine/Sources/CatanEngine/Building.swift`) and adjust `state.players[0].resources`/`settlements` so `.wool` and `.ore` are both genuinely "missing" for the nearest build target — the test needs both resources to appear in `missingUnits(nearest)` so either could be picked absent the threat weighting.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/CatanAI && swift test --filter DevCardHeuristicsTests`
Expected: Either FAIL (picks `.ore` or ties) or PASS by coincidence of iteration order — if it passes before the implementation change, strengthen the test (e.g. give player 2 a slightly *higher* raw resource count than player 1, so only threat-weighting can produce the `.wool` result) until it genuinely fails first.

- [ ] **Step 3: Implement**

In `DevCardHeuristics.swift`, change `opponentTotal` and its one call site:

```swift
    private static func opponentTotal(_ resource: Resource, state: GameState, player: PlayerID) -> Double {
        state.players.filter { $0.id != player }.reduce(0.0) { partial, opponent in
            partial + Double(opponent.resources[resource] ?? 0) * ThreatAssessment.relativeWeight(for: opponent.id, excluding: player, in: state)
        }
    }
```

The `choosePlay` Monopoly block already reads `opponentTotal(bestTarget, state: state, player: player) >= 3` — this keeps compiling unchanged since `3 >= 3.0`-style comparisons work between `Int` literal and `Double` in Swift; no other edit needed there.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/CatanAI && swift test --filter DevCardHeuristicsTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/CatanAI/Sources/CatanAI/DevCardHeuristics.swift Packages/CatanAI/Tests/CatanAITests/DevCardHeuristicsTests.swift
git commit -m "DevCardHeuristics Monopoly targets the higher-threat opponent's stash"
```

---

### Task 9: Full-suite sanity check

**Files:** none (verification only).

**Interfaces:** none — this task only runs the existing safety-net tests.

- [ ] **Step 1: Run the full `CatanAI` test suite**

Run: `cd Packages/CatanAI && swift test`
Expected: PASS, including unmodified `FullBotGameSimulationTests` and `BotLegalityTests` — these simulate complete bot-vs-bot games end to end and assert every move a bot picks is a member of `RulesEngine.legalMoves`. If either fails, the failure is almost certainly a `matchLegal`/`RulesEngine` mismatch introduced by an earlier task (e.g. a heuristic now suggesting a move shape `matchLegal` doesn't recognize) — go back to that task, not this one, to fix it.

- [ ] **Step 2: Run the whole repo's test plan (if one exists) to catch any Xcode-side build breakage**

Run: `xcodebuild -project Settlers.xcodeproj -scheme Settlers -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -40`
Expected: `BUILD SUCCEEDED` — `CatanAI` is a local Swift package dependency of the app target, so a signature change (Task 4's `chooseRobberTarget`) must not leave any other consumer (app code, not just `CatanAIements`) uncompiled. Grep first to check there are no other call sites outside `Packages/CatanAI`:

Run: `grep -rn "chooseRobberTarget" --include="*.swift" . | grep -v Packages/CatanAI`
Expected: no output (all call sites already covered in Task 4).

- [ ] **Step 3: Update `TODO.md`**

Replace the "Bot strength" TBD line in `TODO.md`:

```markdown
## 2. Bot strength
Make the bot opponents play meaningfully better.

- [x] Added `ThreatAssessment` (`Packages/CatanAI/Sources/CatanAI/ThreatAssessment.swift`)
      — a per-opponent threat score (VP + production + hidden dev cards +
      proximity to Largest Army/Longest Road) — and wired it, proportionally
      via `relativeWeight`, into robber targeting, settlement/road
      placement (denies threatening opponents' frontier spots, blocks their
      road network), trade acceptance (raises the bar for high-threat
      proposers), and Monopoly targeting. See
      `docs/superpowers/specs/2026-08-16-bot-threat-assessment-design.md`.
```

- [ ] **Step 4: Commit**

```bash
git add TODO.md
git commit -m "Mark bot threat-assessment work done in TODO.md"
```

---

## Self-Review Notes

- **Spec coverage:** base score (Task 1), milestone swing (Task 2), cross-player `scores`/`relativeWeight` (Task 3), robber (Task 4), settlement denial (Task 5), road blocking + threat-scaled claim (Task 6), trade accept-side caution (Task 7), Monopoly targeting (Task 8), full-suite + `FullBotGameSimulationTests` + `BotLegalityTests` safety net (Task 9). All spec sections have a task.
- **Signature-change ripple:** `chooseRobberTarget` gains a `personality` parameter in Task 4 — both known call sites (`Bot.swift`, `DevCardHeuristics.swift`) are updated in that same task, and Task 9 greps the whole repo to confirm no other call site exists before declaring done.
- **Type consistency:** `ThreatAssessment.score`/`scores`/`relativeWeight` names and signatures introduced in Tasks 1–3 are used identically (same parameter labels/order) in Tasks 4–8 — double-checked against each task's "Consumes" line.
