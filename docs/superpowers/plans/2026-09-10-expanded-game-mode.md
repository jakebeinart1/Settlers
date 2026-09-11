# Expanded Game Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `LongestRoad` scale, then add a second playable rule set — "Expanded", a 37-tile map played to 25 victory points with 4-point bonuses and doubled quantities — moving every hard-coded rule quantity in `CatanEngine` into one `Ruleset` value, with four seams sized for the many larger modes Jake intends next.

**Architecture:** A `GameMode` enum is stored on `GameState` (one `Codable` field, `?? .classic` on decode); `Ruleset` maps a mode to every quantity the rules need; `BoardShape` declares board geometry as a *composition* expandable to any radius. Engine call sites read `state.rules.x` instead of a literal. Classic's values are unchanged throughout, so the existing suites are the refactor's safety net. Task 1 replaces the exhaustive longest-road search first, because Expanded's doubled road limit reaches its exponential zone and the modes after it would freeze outright.

**Tech Stack:** Swift 6.3, SwiftUI, Swift Testing (`@Test` / `#expect`, not XCTest), SPM packages `CatanEngine` + `CatanAI`, XcodeGen, `scripts/gate.sh`.

**Spec:** `docs/superpowers/specs/2026-09-10-expanded-game-mode-design.md` (committed `98b0778`)

## Global Constraints

- **Branch `feat/expanded-game-mode`. Never push to `main`.** Work goes to Jake as a PR.
- **`CatanEngine` and `CatanAI` import only `Foundation`.** No UIKit/SwiftUI/Darwin — it breaks Linux CI, not just taste.
- **All randomness goes through `state.rng`.** Any `Int.random`, `.randomElement()`, `.shuffled()` or `SystemRandomNumberGenerator` inside `CatanEngine` is a bug. The one existing exception is `BoardGenerator`'s private `SeededGenerator`, which is seeded explicitly.
- **New enumeration must be order-stable.** `Set`/`Dictionary` iteration order is seeded per process. Sort before iterating; drive resource loops off `Resource.allCases`.
- **Every new `GameState` field decodes with a default** via `decodeIfPresent`. Only `board`, `players`, `phase` may throw.
- **Never hand-edit `Settlers.xcodeproj/project.pbxproj`.** Run `xcodegen generate` after adding or removing any `.swift` file under `Settlers/`.
- **Never pipe `xcodebuild` through `tail`/`head`/`grep`** — a pipeline returns the last command's status. Read `${PIPESTATUS[0]}` if you must filter.
- **Conventional commits**: `type(scope): description`. Bodies explain *why*, with measured numbers.
- Commit trailers on every commit:
  ```
  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01TBxaHYvMxcRujKxfhdFdAe
  ```

### Measured facts this plan is built on (spec: *Scale*)

- Board generation and `legalMoves` scale **linearly**: 1,027 tiles = 30ms and 42ms. Board size is not an engine problem.
- `LongestRoad` is **exponential in road count**: 3.3ms at 15 roads, 157ms at 30, 776ms at 40, one topology >100s. Classic's 15-road cap is the only reason it has never surfaced.
- The replacement must return **identical** results — the old implementation is retained as a test oracle.

### Fixed values this plan implements (from the spec)

| | Classic | Expanded |
|---|---|---|
| victory-point target | 8 / 10 / 12 | 25 (fixed) |
| longest road bonus | 2 | 4 |
| largest army bonus | 2 | 4 |
| longest road minimum | 5 | 5 |
| largest army minimum | 3 | 3 |
| roads per player | 15 | 30 |
| piece limits by kind | settlement 5, city 4 | settlement 10, city 8 |
| victory points by kind | settlement 1, city 2 | settlement 1, city 2 |
| discard threshold | > 7 | > 10 |
| bank per resource | 19 | 38 |
| dev deck | 14/5/2/2/2 = 25 | 28/10/4/4/4 = 50 |
| tiles | 19 (radius 2) | 37 (radius 3) |
| desert | 1 | 1 |
| grain / wool / lumber | 4 / 4 / 4 | 8 / 8 / 8 |
| brick / ore | 3 / 3 | 6 / 6 |
| ports | 9 fixed (4 generic, 5 resource) | 14 derived (4 generic, 2 per resource) |
| seats | 3–4 | 3–4 (unchanged) |
| setup settlements | 2 | 2 (unchanged) |

---

## Status

**Updated after every task completes.** `Done` means implemented, reviewed, every Critical and
Important finding fixed, and re-verified. Commits are on `feat/expanded-game-mode`.

| # | Task | Status | Commits | Evidence |
|---|---|---|---|---|
| 1 | Make `LongestRoad` scale | ✅ **Done** 2026-09-10 | `dd53a9d..d1baab9` | 30 roads 80.6ms→4.90ms, 40 roads 719.6ms→45.54ms. 7,440 networks vs retained oracle, 0 disagreements. No fingerprint moved. |
| 2 | Nothing hardcodes five resources | ✅ **Done** 2026-09-10 | `092a3bc` | Audit clean — every enumeration already `Resource.allCases`-driven. Test-only commit; no production change. |
| 3 | `BoardShape` as a composition | ✅ **Done** 2026-09-10 | `3340a3c..5a329f8` | 236/236 + 145/145, no fingerprint moved, swiftlint clean. Cross-process probe: 3 processes byte-identical. 6 findings fixed incl. an unbounded loop that hung forever on a legal all-6/8 composition. |
| 4 | Expanded board shape + token repair | ✅ **Done** 2026-09-10 | `a09e339` | 243/243 + 145/145, no fingerprint moved. Verified independently: 37 tiles, terrain and 36-token multiset exactly 2× Classic, 14 ports (4 generic + 2/resource) on distinct edges, 0 adjacency violations, byte-identical across 3 processes. |
| 5 | `GameMode` and `Ruleset` | ✅ **Done** 2026-09-10 | `6b28341..7bca304` | 251/251. Classic + Expanded values verified directly. `supportedRoadLimit = 38` measured and independently reproduced (5.60ms vs 5.48ms); cliff confirmed at 44 roads (235ms). `scaledFromBoard` rounding pinned both directions; recursion trap removed structurally. |
| 6 | `GameState.mode`, schema v4 | ✅ **Done** 2026-09-11 | `1e9a8e9` | 255/255 + 145/145. Decode order correct (`mode` before target validation). Deck-order conflict resolved via `DevCardType.deckBuildOrder` — **no fingerprint re-recorded**; `git diff main...HEAD -- Packages/CatanAI` still empty. |
| 7 | Route rule sites through `state.rules` | 🔨 **In progress** | | |
| 8 | Expanded full game + fingerprints | ⬜ Not started | | |
| 9 | `StateEncoding`/`ActionSpace` refusal | ⬜ Not started | | |
| 10 | `MatchSetup` carries the mode | ⬜ Not started | | |
| 11 | Mode survives save/resume/replay | ⬜ Not started | | |
| 12 | Mode picker on New Game screen | ⬜ Not started | | |
| 13 | UI stops printing "+2" | ⬜ Not started | | |
| 14 | Verification (gate, sim-harness, screenshot) | ⬜ Not started | | |

### Decisions made during execution

These changed the plan after it was written. Each is a deliberate call, not drift.

| Decision | Why | Cost if wrong |
|---|---|---|
| Fix `LongestRoad` before Expanded (Task 1, new) | Measured exponential blow-up: 3.3ms at 15 roads, 157ms at 30, 776ms at 40, one topology >100s. Classic's 15-road cap was the only thing hiding it. Jake's call. | Expanded ships later |
| `newGame`'s `mode:` parameter moved Task 7 → Task 6 | Task 6's own tests construct Expanded states and could not compile without it | Task 6's diff is larger |
| `Player.victoryPoints` test rewritten | It is a computed read-only property (`Player.swift:35`); the planned test assigned to it | None — the replacement is more faithful |
| `TileKind` gains `Hashable` | Plan specified `[TileKind: Int]` but `TileKind` was only `Equatable` | None — `Resource` is already `Hashable`, so it is synthesized |
| Bounded retry pulled Task 4 → Task 3 | `randomized(seed:shape:)` hangs forever on an all-6/8 composition, newly reachable once shapes became public API | A feasible-but-unlucky shape crashes instead of retrying; Task 4's repair removes that window |
| `DevCardType.deckBuildOrder` added (Task 6) | Building the deck off `allCases` moved all five seeded fingerprints — same 25 cards, different pre-shuffle order. Re-recording would change what every seeded Classic game deals; reordering the enum would silently shift `StateEncoding`'s feature slots | An extra indirection on deck construction; ranks kept in step by an exhaustive switch, not by memory |
| Two tautological tests replaced | Both asserted that a value equals its own definition — `resourceKindCount == Resource.allCases.count`, and `standard(BoardShape.classic)` vs a `standard()` that *is* that call | None — both replacements are strictly more falsifiable |

---

## File Structure

**Modified first — the scaling fix:**
- `LongestRoad.swift` — exhaustive DFS replaced by split → decompose → tree-diameter → bounded search.

**New — `Packages/CatanEngine/Sources/CatanEngine/`:**
- `Models/GameMode.swift` — the `GameMode` enum. One responsibility: name the modes, `Codable`.
- `Ruleset.swift` — the `Ruleset` struct and the exhaustive `GameMode → Ruleset` mapping. The single place a new mode's quantities are written.
- `BoardShape.swift` — `BoardShape` as a composition (`TerrainComposition`, `TokenComposition`, `PortLayout`), the expansion to any radius, and the coastline walk that derives ports.

**Modified — engine:**
- `BoardGeneration.swift` — generalized to build from a `BoardShape`.
- `Models/GameState.swift` — `mode` field, decode, `rules` accessor, VP formulas, `GameSetup.newGame`.
- `Building.swift`, `LongestRoad.swift`, `DevCards.swift`, `Robber.swift`, `WinCondition.swift` — literals become `state.rules` reads.
- `StateEncoding.swift`, `ActionSpace.swift` — named refusal for non-Classic.

**Modified — app:**
- `Settlers/Persistence/MatchSetup.swift`, `GameLogStore.swift`, `MatchCheckpointMigration.swift`, `MatchCheckpointStore.swift`
- `Settlers/ViewModels/GameViewModel.swift`
- `Settlers/Views/NewGameSetupView.swift`, `EndGameView.swift`, `PlayerHUDView.swift`
- `Settlers/Models/VictoryPointBreakdown.swift`
- `Settlers/Theme/AccessibilityID.swift`

**New — app:**
- `Settlers/Views/GameModePickerPopup.swift` — the mode selector, following `CivilizationPickerPopup`.

Why `Ruleset` and `BoardShape` are separate files: they change for different reasons. A new mode with existing geometry touches only `Ruleset`; a new geometry touches only `BoardShape`.

---

## Task 1: Make `LongestRoad` scale, provably without changing any answer

This is the highest-risk task in the project. `LongestRoad` decides who wins games, and every seeded fingerprint in the repo depends on its answers. The replacement must be **exactly equal** to the current implementation, not close.

**Files:**
- Modify: `Packages/CatanEngine/Sources/CatanEngine/LongestRoad.swift`
- Test: Create `Packages/CatanEngine/Tests/CatanEngineTests/LongestRoadEquivalenceTests.swift`
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/LongestRoadTests.swift` (existing — must stay green untouched)

**Interfaces:**
- Consumes: nothing.
- Produces: no public API change. `LongestRoad.compute(for:)` and `LongestRoad.length(for:in:)` keep their exact signatures and results. Internally adds `LongestRoad.referenceLongestPath(for:in:)`, `internal` and documented as test-only, holding today's algorithm verbatim.

### Why this task exists (measured 2026-09-10)

`longestPath` runs an exhaustive DFS from every vertex — no pruning, no memoization, no decomposition. Cost against road count:

| roads | path-like network | dense clump |
|---|---|---|
| 15 (Classic's cap) | 0.6ms | 3.3ms |
| 20 | 0.9ms | 10.2ms |
| 25 | 1.4ms | 27.8ms |
| 30 (Expanded's cap) | 2.3ms | 157ms |
| 35 | — | 309ms |
| 40 | 4.2ms | 776ms |

Doubling every ~5 roads. Classic's 15-road cap is the only reason this has never surfaced. Expanded's 30 is playable but on the shoulder; the 100+ road modes Jake plans next would freeze for minutes.

- [x] **Step 1: Preserve today's algorithm as a reference oracle**

Rename the existing `longestPath(for:in:)` to `referenceLongestPath(for:in:)`, change `private` to `internal`, and leave its body **byte-identical**. Add:

```swift
    /// Today's exhaustive search, kept verbatim as the correctness oracle for
    /// `longestPath`. Exponential in road count (measured: 3.3ms at 15 roads,
    /// 157ms at 30, 776ms at 40 on a dense network), which is why it is no
    /// longer the one that runs — but it is simple enough to be obviously
    /// correct, which is exactly what an oracle needs to be.
    ///
    /// Not `private` so `LongestRoadEquivalenceTests` can compare against it.
    /// Nothing in production may call this.
```

- [x] **Step 2: Write the failing equivalence test**

Create `LongestRoadEquivalenceTests.swift`. This is the whole safety argument — write it before the new algorithm exists.

```swift
import Testing
import Foundation
@testable import CatanEngine

/// Proves the fast longest-road search returns EXACTLY what the exhaustive one
/// returns, across randomly generated networks.
///
/// Equality is the requirement, not approximation: this function decides games,
/// and every seeded fingerprint in the repo is pinned to its answers. A
/// disagreement on any generated network is a bug in the new algorithm, never
/// an acceptable difference.
private func randomNetwork(seed: UInt64, roadCount: Int, blockedCount: Int)
    -> (GameState, Player) {
    var rng = RandomSource(seed: seed)
    let board = BoardGenerator.randomized(seed: seed)
    var state = GameSetup.newGame(board: board, seed: seed)
    let edges = board.onBoardEdges.sorted()
    let vertices = board.onBoardVertices.sorted()

    // Grow from a random seed edge so the network is CONNECTED often enough to
    // be interesting, but jump to a fresh edge sometimes so disconnected
    // components and cycles both occur.
    var roads = Set<EdgeID>()
    var frontier: [VertexID] = []
    while roads.count < min(roadCount, edges.count) {
        let candidates: [EdgeID]
        if frontier.isEmpty || Int.random(in: 0..<5, using: &rng) == 0 {
            candidates = edges.filter { !roads.contains($0) }
        } else {
            let from = frontier[Int.random(in: 0..<frontier.count, using: &rng)]
            candidates = edges.filter { !roads.contains($0) && ($0.a == from || $0.b == from) }
        }
        guard let pick = candidates.isEmpty ? edges.filter({ !roads.contains($0) }).first
                                            : candidates[Int.random(in: 0..<candidates.count, using: &rng)]
        else { break }
        roads.insert(pick)
        frontier.append(pick.a); frontier.append(pick.b)
    }
    state.players[0].roads = roads
    // Opponent buildings that cut the network.
    var blocked = Set<VertexID>()
    while blocked.count < blockedCount && blocked.count < vertices.count {
        blocked.insert(vertices[Int.random(in: 0..<vertices.count, using: &rng)])
    }
    state.players[1].settlements = blocked
    return (state, state.players[0])
}

@Test func fastSearchAgreesWithTheExhaustiveOneOnManyRandomNetworks() {
    var checked = 0
    for seed in UInt64(1)...300 {
        for roadCount in [1, 3, 5, 8, 12, 15, 18, 22] {
            for blockedCount in [0, 2, 5] {
                let (state, player) = randomNetwork(seed: seed, roadCount: roadCount,
                                                    blockedCount: blockedCount)
                let fast = LongestRoad.length(for: player, in: state)
                let reference = LongestRoad.referenceLongestPath(for: player, in: state)
                #expect(fast == reference,
                        "seed \(seed), \(roadCount) roads, \(blockedCount) blocked: fast \(fast) != reference \(reference)")
                checked += 1
            }
        }
    }
    #expect(checked >= 7_000, "equivalence sweep covered only \(checked) networks")
}

@Test func fastSearchHandlesTheShapesThatBreakNaiveSearches() {
    // A closed loop of roads around one hex: a cycle, so the tree shortcut
    // must NOT be taken.
    let board = BoardGenerator.standard()
    var state = GameSetup.newGame(board: board, seed: 1)
    let hex = board.tiles[0].coordinate
    state.players[0].roads = Set(HexGeometry.edges(of: hex))
    #expect(LongestRoad.length(for: state.players[0], in: state)
            == LongestRoad.referenceLongestPath(for: state.players[0], in: state))

    // Two disconnected clusters: the answer is the longer one, never the sum.
    var disjoint = GameSetup.newGame(board: board, seed: 2)
    let edges = board.onBoardEdges.sorted()
    disjoint.players[0].roads = Set(edges.prefix(3)).union(Set(edges.suffix(4)))
    #expect(LongestRoad.length(for: disjoint.players[0], in: disjoint)
            == LongestRoad.referenceLongestPath(for: disjoint.players[0], in: disjoint))

    // An empty network.
    var empty = GameSetup.newGame(board: board, seed: 3)
    empty.players[0].roads = []
    #expect(LongestRoad.length(for: empty.players[0], in: empty) == 0)
}
```

- [x] **Step 3: Run to verify it fails for the right reason**

Run: `swift test --package-path Packages/CatanEngine --filter LongestRoadEquivalence`
Expected: FAIL — `referenceLongestPath` exists but `longestPath` is still the same function, so the test is comparing a function to itself and passes vacuously, OR it fails to compile. **Either way it proves nothing yet** — that is expected at this step, and Step 5 is where it becomes meaningful.

- [x] **Step 4: Write the fast search**

Replace `longestPath(for:in:)` with the four-stage version. All four stages are exact; none approximates.

```swift
    /// The longest simple path through `player`'s road graph, cut at any vertex
    /// holding an opposing settlement or city.
    ///
    /// Longest simple path is NP-hard in general, so this does not find a
    /// clever formula - it removes work that never needed doing:
    ///
    /// 1. **Split at blocked vertices.** A road may END at an opponent's
    ///    building but never continue through it, so a blocked vertex is
    ///    duplicated into one copy per incident edge. That is exactly
    ///    equivalent to the old rule and it breaks one tangled graph into
    ///    several small ones.
    /// 2. **Decompose into connected components.** Separate clusters cannot
    ///    form one path, so the answer is the maximum over components rather
    ///    than a search across all of them at once.
    /// 3. **A component with no cycle is a tree** - the common case for real
    ///    road networks - and a tree's longest path is its diameter, found by
    ///    two linear traversals with no search at all.
    /// 4. **Only a component containing a cycle searches**, and then with a
    ///    branch-and-bound cut: a branch whose current length plus every
    ///    remaining unvisited edge in its component cannot beat the best
    ///    answer so far is abandoned.
    ///
    /// Proven equal to `referenceLongestPath` across thousands of generated
    /// networks by `LongestRoadEquivalenceTests`. If those ever disagree, this
    /// function is wrong - the oracle is the definition.
    private static func longestPath(for player: Player, in state: GameState) -> Int {
```

Implement it. Guidance the plan can give but cannot write for you, because it depends on the split representation you choose:

- Represent a split vertex as a `struct SplitVertex: Hashable { let vertex: VertexID; let copy: Int }` where unblocked vertices always use `copy: 0` and a blocked vertex uses a distinct copy per incident edge. Build adjacency over `SplitVertex`.
- **Enumerate in sorted order everywhere.** Build adjacency by iterating `player.roads.sorted()`, and take component members in sorted order. `Set` iteration order is seeded per process; a non-deterministic traversal order would not change the *maximum* here, but it would make any future tie-break non-reproducible. Sort anyway.
- A component is a tree exactly when `edgeCount == vertexCount - 1`.
- Tree diameter: from any vertex, find the farthest vertex `u` by BFS; from `u`, find the farthest vertex `v`; the distance `u`→`v` is the diameter in edges.
- Keep the recursion depth bounded — a 3,192-edge board can hold long components; prefer an explicit stack or confirm the recursion depth stays within the default stack for the road limits `Ruleset` permits.

- [x] **Step 5: Run the equivalence sweep**

Run: `swift test --package-path Packages/CatanEngine --filter LongestRoadEquivalence`
Expected: PASS, ≥7,000 networks compared, zero disagreements.

**Any disagreement is a bug in the new code.** Do not adjust the oracle, do not relax the assertion, and do not exclude a failing shape. Print the failing network's roads and blocked vertices and fix the algorithm.

- [x] **Step 6: Prove the whole engine and the bots are unchanged**

Run: `swift test --package-path Packages/CatanEngine`
Run: `swift test --package-path Packages/CatanAI`
Expected: PASS, both, with **`SeededGameFingerprintTests` unchanged and un-repinned.**

The fingerprints are the strongest evidence available: identical move sequences across full seeded games mean the new search returned the same answer at every decision of every game. **If a fingerprint moves, stop.** Do not re-record it — that would be re-pinning the tests to a bug. Report it.

- [x] **Step 7: Measure the improvement and record it**

Re-run the dense-network measurement at 15, 20, 25, 30, 35 and 40 roads and put the before/after numbers in the commit message. A performance fix without a measured number is a claim, not a result.

- [x] **Step 8: Commit**

```bash
git add Packages/CatanEngine/Sources/CatanEngine/LongestRoad.swift \
        Packages/CatanEngine/Tests/CatanEngineTests/LongestRoadEquivalenceTests.swift
git commit -m "perf(engine): make longest-road search scale, with identical results

The search was an exhaustive DFS from every vertex with no pruning,
memoization or decomposition, and its cost doubled roughly every five roads:
measured 3.3ms at 15 roads, 157ms at 30, 776ms at 40 on a dense network, and
over 100 seconds on one topology. Classic's 15-road piece limit is the only
reason this never surfaced. Expanded doubles that limit to 30, and the larger
modes planned next would freeze outright.

Replaced with four exact stages: split the graph at opponent-blocked vertices
(equivalent to the old rule, since a road may end at a building but not pass
through it), decompose into connected components, solve any acyclic component
as a tree diameter in linear time, and branch-and-bound only components that
actually contain a cycle.

<BEFORE/AFTER TABLE FROM STEP 7>

The old implementation is retained as referenceLongestPath and is now the
correctness oracle: LongestRoadEquivalenceTests compares the two across 7,000+
generated networks spanning trees, cycles, disconnected clusters and blocked
vertices. Every seeded fingerprint in CatanAI is unchanged and was NOT
re-recorded, which is the real evidence - identical move sequences across full
games mean identical answers at every decision.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TBxaHYvMxcRujKxfhdFdAe"
```

---

## Task 2: Nothing hardcodes five resources

A small audit task, serving a named future feature (a sixth resource). It adds no resource.

**Files:**
- Modify: whatever the audit finds.
- Test: Create `Packages/CatanEngine/Tests/CatanEngineTests/ResourceCountAgnosticTests.swift`

**Interfaces:**
- Consumes: nothing. Produces: no API change.

- [x] **Step 1: Find every place the count 5 is baked in**

```bash
grep -rn "allCases" --include="*.swift" Packages/CatanEngine/Sources Packages/CatanAI/Sources | grep -i resource
grep -rn "\b5\b" --include="*.swift" Packages/CatanEngine/Sources | grep -iv "test\|//" | grep -i "resource\|kind\|count"
grep -rn "\[\.brick\|\.grain, \.wool\|\.lumber, \.ore" --include="*.swift" Packages/CatanEngine/Sources Packages/CatanAI/Sources
```

Write the findings into your report. Expect most of the engine to be clean already — `StateEncoding.resourceKindCount` is `Resource.allCases.count`, and the bank loop drives off `Resource.allCases`.

- [x] **Step 2: Write the failing test**

```swift
import Testing
@testable import CatanEngine

/// Pins the behaviour a sixth resource depends on: everything that enumerates
/// resources does it through `Resource.allCases`, so adding a case is a
/// one-line change rather than a hunt.
@Test func everyResourceGetsBankStockAndAFeatureSlot() {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    // Every case, not five named ones.
    for resource in Resource.allCases {
        #expect(state.bank[resource] != nil, "\(resource) has no bank stock")
    }
    #expect(state.bank.count == Resource.allCases.count)
    #expect(StateEncoding.resourceKindCount == Resource.allCases.count)
}

@Test func startingBankIsUniformAcrossEveryResource() {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    let stocks = Set(Resource.allCases.map { state.bank[$0] ?? -1 })
    #expect(stocks.count == 1, "bank stock differs by resource: \(stocks)")
}
```

- [x] **Step 3: Run it**

Run: `swift test --package-path Packages/CatanEngine --filter ResourceCountAgnostic`
Expected: PASS immediately if the engine is already clean. **That is a valid outcome** — the test's job is to keep it clean, not to prove it was broken. If it fails, fix the source, not the test.

- [x] **Step 4: Fix anything the audit found**

Only what Step 1 actually found. Do not add a resource, do not make `Resource` dynamic, do not touch `CatanAI` heuristic weights keyed by resource — per-resource *tuning* is legitimately per-resource.

- [x] **Step 5: Run the full engine suite**

Run: `swift test --package-path Packages/CatanEngine`
Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add Packages/CatanEngine
git commit -m "test(engine): pin resource enumeration to Resource.allCases

A sixth resource is a named future mode. Most of the engine already enumerates
through allCases; this adds the test that keeps it that way, plus fixes for
whatever the audit turned up, so adding a case stays a one-line change instead
of a hunt through six files.

Adds no resource and changes no behaviour.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TBxaHYvMxcRujKxfhdFdAe"
```

---

## Task 3: `BoardShape` as a composition, expandable to any radius

Pure refactor. Classic's board must come out **byte-identical**, and `BoardGenerationTests` plus the CatanAI fingerprints are the proof.

**Files:**
- Create: `Packages/CatanEngine/Sources/CatanEngine/BoardShape.swift`
- Modify: `Packages/CatanEngine/Sources/CatanEngine/BoardGeneration.swift`
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/BoardGenerationTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `BoardShape(radius:terrain:tokens:ports:)`, `TerrainComposition`, `TokenComposition`, `PortLayout`, `BoardShape.classic`, `BoardShape.tileCount`, `BoardGenerator.standard(_:)`, `BoardGenerator.randomized(seed:shape:)`, `BoardGenerator.spiralCoordinates(radius:)` (drop its `private`). The existing no-argument `standard()` and `randomized(seed:)` stay as Classic-defaulting wrappers — 17 call sites depend on them.

### Why a composition and not per-tile arrays

Jake intends boards of hundreds or a thousand tiles. One literal entry per tile is unwritable past ~50, and an earlier draft of this plan proved it: it could not *write* a 37-entry terrain array and generated it with a stride trick instead. Declare proportions; let the generator expand them.

Classic keeps literal-order cases, because its arrangement is the authentic physical board and is not derivable from any rule.

- [x] **Step 1: Write the failing test**

```swift
@Test func classicShapeReproducesTheStandardBoardExactly() {
    let viaShape = BoardGenerator.standard(BoardShape.classic)
    let original = BoardGenerator.standard()
    #expect(viaShape.tiles == original.tiles)
    #expect(viaShape.ports == original.ports)
    #expect(viaShape.onBoardVertices == original.onBoardVertices)
    #expect(viaShape.onBoardEdges == original.onBoardEdges)
    #expect(viaShape.robberTile == original.robberTile)
}

@Test func tileCountFollowsTheHexFormulaAtEveryRadius() {
    // 3r^2 + 3r + 1
    #expect(BoardShape.tileCount(radius: 0) == 1)
    #expect(BoardShape.tileCount(radius: 2) == 19)
    #expect(BoardShape.tileCount(radius: 3) == 37)
    #expect(BoardShape.tileCount(radius: 12) == 469)
    #expect(BoardShape.tileCount(radius: 18) == 1_027)
}

@Test func aCompositionExpandsToExactlyTheDeclaredCounts() {
    let shape = BoardShape(
        radius: 3,
        terrain: .counts([.desert: 1, .resource(.grain): 12, .resource(.ore): 24]),
        tokens: .counts([6: 18, 8: 18]),
        ports: .derived(kinds: [.generic, .generic])
    )
    let board = BoardGenerator.standard(shape)
    #expect(board.tiles.count == 37)
    #expect(board.tiles.filter { $0.kind == .desert }.count == 1)
    #expect(board.tiles.filter { $0.kind == .resource(.grain) }.count == 12)
    #expect(board.tiles.filter { $0.kind == .resource(.ore) }.count == 24)
    #expect(board.tiles.compactMap(\.numberToken).count == 36)
}

@Test func aCompositionThatDoesNotFillTheBoardIsRejected() {
    // 10 tiles declared for a 37-tile radius. Trapping here beats dealing a
    // board with silent holes in it.
    #expect(BoardShape(radius: 3, terrain: .counts([.desert: 10]),
                       tokens: .counts([:]), ports: .derived(kinds: []))
        .compositionProblem != nil)
}
```

- [x] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/CatanEngine`
Expected: FAIL — `cannot find 'BoardShape' in scope`.

- [x] **Step 3: Create `BoardShape.swift`**

```swift
/// The geometry and terrain composition of one board, independent of the rules
/// played on it.
///
/// Separate from `Ruleset` because the two change for different reasons: a mode
/// reusing an existing map with different quantities touches only `Ruleset`; a
/// mode adding a map touches only this file.
///
/// ## Declared as a composition, not as a list of tiles
/// Boards of hundreds or a thousand tiles are planned, and one literal entry
/// per tile stops being writable long before that. A shape therefore states how
/// many of each terrain and each token it wants, and the generator expands that
/// onto the spiral. Classic is the exception: its arrangement is the authentic
/// physical board, so it declares a literal order.
public struct BoardShape: Sendable, Equatable {
    /// Rings of hexes around the centre. Radius 2 is the 19-tile classic board.
    public let radius: Int
    public let terrain: TerrainComposition
    public let tokens: TokenComposition
    public let ports: PortLayout

    public init(radius: Int, terrain: TerrainComposition,
                tokens: TokenComposition, ports: PortLayout) {
        self.radius = radius
        self.terrain = terrain
        self.tokens = tokens
        self.ports = ports
    }

    /// Tiles a hex board of `radius` holds: 3r^2 + 3r + 1.
    public static func tileCount(radius: Int) -> Int {
        3 * radius * radius + 3 * radius + 1
    }

    public var tileCount: Int { Self.tileCount(radius: radius) }

    /// Why this shape cannot be dealt, or `nil` if it can.
    ///
    /// Checked rather than trusted: a composition that does not fill the board
    /// would otherwise deal tiles with holes, and a token count that does not
    /// match the non-desert tiles would leave hexes that never produce.
    public var compositionProblem: String? {
        let terrainTotal = terrain.expanded(tileCount: tileCount).count
        guard terrainTotal == tileCount else {
            return "terrain declares \(terrainTotal) tiles for a \(tileCount)-tile board"
        }
        let producing = terrain.expanded(tileCount: tileCount).filter { $0 != .desert }.count
        let tokenTotal = tokens.expanded(count: producing).count
        guard tokenTotal == producing else {
            return "tokens declare \(tokenTotal) for \(producing) producing tiles"
        }
        return nil
    }
}

/// How a shape's terrain is specified.
public enum TerrainComposition: Sendable, Equatable {
    /// Classic's authentic arrangement, in spiral order. Not derivable from a
    /// rule, so it is written down.
    case literalOrder([TileKind])
    /// How many tiles of each kind. Expanded onto the spiral by interleaving,
    /// so a fixed board is playable rather than five solid wedges of one
    /// terrain. Deterministic: a fixed walk over a sorted array, no RNG.
    case counts([TileKind: Int])

    func expanded(tileCount: Int) -> [TileKind] { /* implement */ }
}

/// How a shape's number tokens are specified.
public enum TokenComposition: Sendable, Equatable {
    case literalOrder([Int])
    /// How many of each pip value.
    case counts([Int: Int])

    func expanded(count: Int) -> [Int] { /* implement */ }
}

/// How a shape's ports are placed.
///
/// Classic's nine are `.fixed`: they reproduce the physical board and are not
/// derivable. Anything larger is `.derived` — hand-authoring vertex triples for
/// a 42-edge coastline is error-prone, and a walk generalizes to radii nobody
/// has drawn.
public enum PortLayout: Sendable, Equatable {
    case fixed([Port])
    /// One port per entry, spread evenly around the coastline in this order.
    case derived(kinds: [Port.Kind])
}
```

**Implement both `expanded` functions deterministically.** `counts` must be walked in a **sorted** order (sort `TileKind`/`Int` keys), never in dictionary order — `Dictionary` iteration order is seeded per process, and an unstable expansion would deal a different board per launch for the same seed. Interleave rather than concatenating runs, so `.counts` produces a playable fixed board.

- [x] **Step 4: Add `BoardShape.classic`**

```swift
public extension BoardShape {
    /// The 19-tile board every game of Catan opens on. Literal orders, because
    /// this arrangement IS the physical board.
    static let classic = BoardShape(
        radius: 2,
        terrain: .literalOrder(BoardGenerator.standardResourceOrder),
        tokens: .literalOrder(BoardGenerator.standardNumberOrder),
        ports: .fixed(BoardGenerator.standardPorts)
    )
}
```

- [x] **Step 5: Generalize `BoardGeneration.swift`**

Drop `private` from `spiralCoordinates(radius:)`. Keep the `tileCoordinates` constant as classic's 19 — `standardPorts` and both standard orders are written against that exact ordering. **Do not** add a `tileCoordinates(radius:)` overload beside it; Swift permits it but a property and method sharing a name reads as a typo in a load-bearing file.

```swift
    public static func standard() -> Board { standard(BoardShape.classic) }

    public static func standard(_ shape: BoardShape) -> Board {
        precondition(shape.compositionProblem == nil,
                     "cannot deal this board: \(shape.compositionProblem!)")
        let coordinates = spiralCoordinates(radius: shape.radius)
        let kinds = shape.terrain.expanded(tileCount: shape.tileCount)
        var numbers = shape.tokens
            .expanded(count: kinds.filter { $0 != .desert }.count)
            .makeIterator()
        let tiles = zip(coordinates, kinds).map { coordinate, kind -> Tile in
            let number = (kind == .desert) ? nil : numbers.next()
            return Tile(coordinate: coordinate, kind: kind, numberToken: number)
        }
        return makeBoard(tiles: tiles, shape: shape)
    }
```

Thread `shape` through `makeBoard` and resolve ports:

```swift
    private static func makeBoard(tiles: [Tile], shape: BoardShape) -> Board {
        var vertices = Set<VertexID>()
        var edges = Set<EdgeID>()
        for tile in tiles {
            vertices.formUnion(HexGeometry.corners(of: tile.coordinate))
            edges.formUnion(HexGeometry.edges(of: tile.coordinate))
        }
        let robberTile = tiles.first(where: { $0.kind == .desert })?.coordinate ?? tiles[0].coordinate
        return Board(tiles: tiles, ports: resolvePorts(shape.ports, tiles: tiles),
                     onBoardVertices: vertices, onBoardEdges: edges, robberTile: robberTile)
    }

    private static func resolvePorts(_ layout: PortLayout, tiles: [Tile]) -> [Port] {
        switch layout {
        case .fixed(let ports): return ports
        case .derived(let kinds): return derivedPorts(kinds: kinds, tiles: tiles)
        }
    }
```

- [x] **Step 6: Write the coastline walk**

Append to `BoardShape.swift`:

```swift
extension BoardGenerator {
    /// Places `kinds.count` ports evenly around the coastline.
    ///
    /// A coastal edge is an edge of an on-board tile whose neighbour in that
    /// direction is off the board. Walking tiles in spiral order and directions
    /// in index order visits the outer ring the way the ring is wound, so
    /// consecutive coastal edges are physically adjacent and an even stride
    /// spreads ports around the shore rather than clumping them.
    ///
    /// Deterministic by construction: no `Set` is iterated and the stride is
    /// integer arithmetic. No RNG — ports stay put while terrain and tokens
    /// shuffle, exactly as on the classic board.
    static func derivedPorts(kinds: [Port.Kind], tiles: [Tile]) -> [Port] {
        let onBoard = Set(tiles.map(\.coordinate))
        var coastal: [EdgeID] = []
        for tile in tiles {
            let edges = HexGeometry.edges(of: tile.coordinate)
            for direction in 0..<6 where !onBoard.contains(tile.coordinate.neighbor(direction)) {
                // `edges(of:)` indexes edge `i` as the one shared with the
                // neighbour in direction `i`.
                coastal.append(edges[direction])
            }
        }
        guard !kinds.isEmpty else { return [] }
        precondition(coastal.count >= kinds.count,
                     "coastline holds \(coastal.count) edges, cannot place \(kinds.count) ports")
        let stride = coastal.count / kinds.count
        return kinds.enumerated().map { offset, kind in
            let edge = coastal[offset * stride]
            return Port(vertexA: edge.a, vertexB: edge.b, kind: kind)
        }
    }
}
```

- [x] **Step 7: Point `randomized` at the shape**

```swift
    public static func randomized(seed: UInt64) -> Board {
        randomized(seed: seed, shape: BoardShape.classic)
    }

    public static func randomized(seed: UInt64, shape: BoardShape) -> Board {
        var rng = SeededGenerator(seed: seed)
        let baseKinds = shape.terrain.expanded(tileCount: shape.tileCount)
        let baseNumbers = shape.tokens.expanded(count: baseKinds.filter { $0 != .desert }.count)
        var kinds = baseKinds
        var numbers = baseNumbers
        repeat {
            kinds = baseKinds.shuffled(using: &rng)
            numbers = baseNumbers.shuffled(using: &rng)
        } while hasAdjacentSixOrEight(kinds: kinds, numbers: numbers, radius: shape.radius)
        // ... deal tiles as in `standard(_:)`, then makeBoard(tiles:shape:)
    }
```

Give `hasAdjacentSixOrEight` a `radius: Int` parameter using `spiralCoordinates(radius:)`. Task 4 replaces this loop — leave it alone for now.

- [x] **Step 8: Run the tests**

Run: `swift test --package-path Packages/CatanEngine`
Run: `swift test --package-path Packages/CatanAI`
Expected: PASS, both, with fingerprints unchanged. **If a fingerprint moves, the board changed — find out why; do not re-pin.**

- [x] **Step 9: Commit**

```bash
git add Packages/CatanEngine
git commit -m "refactor(engine): declare board shape as a composition

Radius, terrain, tokens and port layout become a value the generator reads, so
a second map is data rather than a second generator. Classic's board is
unchanged and asserted byte-identical against the previous entry point.

Terrain and tokens are declared as COUNTS, not as one literal entry per tile.
Boards of hundreds or a thousand tiles are planned and a per-tile literal stops
being writable long before that - an earlier draft of this work could not write
its own 37-entry array and generated it with a stride trick instead. Classic
keeps literal orders because its arrangement is the authentic physical board
and is not derivable from any rule.

Ports gain a derived layout beside the fixed one, walking the coastline at an
even stride, which generalizes to radii nobody has drawn and avoids
hand-authoring vertex triples for a 42-edge shore.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TBxaHYvMxcRujKxfhdFdAe"
```

---
## Task 4: The Expanded board shape and deterministic token repair

**Files:**
- Modify: `Packages/CatanEngine/Sources/CatanEngine/BoardShape.swift`
- Modify: `Packages/CatanEngine/Sources/CatanEngine/BoardGeneration.swift`
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/BoardGenerationTests.swift`

**Interfaces:**
- Consumes: `BoardShape`, `TerrainComposition`, `TokenComposition`, `PortLayout`, `BoardGenerator.standard(_:)`, `randomized(seed:shape:)` from Task 3.
- Produces: `BoardShape.expanded`.

- [x] **Step 1: Write the failing tests**

```swift
@Test func expandedBoardHasThirtySevenTilesAndOneDesert() {
    let board = BoardGenerator.standard(BoardShape.expanded)
    #expect(board.tiles.count == 37)
    #expect(board.tiles.filter { $0.kind == .desert }.count == 1)
}

@Test func expandedTerrainIsExactlyTwiceClassic() {
    let board = BoardGenerator.standard(BoardShape.expanded)
    func count(_ resource: Resource) -> Int {
        board.tiles.filter { $0.kind == .resource(resource) }.count
    }
    #expect(count(.grain) == 8)
    #expect(count(.wool) == 8)
    #expect(count(.lumber) == 8)
    #expect(count(.brick) == 6)
    #expect(count(.ore) == 6)
}

@Test func expandedTokenMultisetIsExactlyTwiceClassic() {
    let board = BoardGenerator.standard(BoardShape.expanded)
    let expanded = board.tiles.compactMap(\.numberToken).sorted()
    let doubledClassic = (BoardGenerator.standardNumberOrder
                          + BoardGenerator.standardNumberOrder).sorted()
    #expect(expanded == doubledClassic)
    #expect(expanded.count == 36)
}

@Test func expandedHasFourteenPortsOnDistinctCoastalEdges() {
    let board = BoardGenerator.standard(BoardShape.expanded)
    #expect(board.ports.count == 14)
    #expect(Set(board.ports.map { EdgeID($0.vertexA, $0.vertexB) }).count == 14)
    for port in board.ports {
        #expect(board.onBoardVertices.contains(port.vertexA))
        #expect(board.onBoardVertices.contains(port.vertexB))
    }
    #expect(board.ports.filter { $0.kind == .generic }.count == 4)
    for resource in Resource.allCases {
        #expect(board.ports.filter { $0.kind == .resource(resource) }.count == 2)
    }
}

@Test func expandedRandomizedBoardNeverAdjoinsSixAndEight() {
    for seed in UInt64(1)...50 {
        let board = BoardGenerator.randomized(seed: seed, shape: .expanded)
        let tokens = Dictionary(uniqueKeysWithValues: board.tiles.map { ($0.coordinate, $0.numberToken) })
        for tile in board.tiles where tile.numberToken == 6 || tile.numberToken == 8 {
            for direction in 0..<6 {
                if let neighbor = tokens[tile.coordinate.neighbor(direction)] ?? nil {
                    #expect(!(neighbor == 6 || neighbor == 8), "seed \(seed)")
                }
            }
        }
    }
}

@Test func expandedRandomizedBoardIsReproducibleFromItsSeed() {
    let first = BoardGenerator.randomized(seed: 99, shape: .expanded)
    let second = BoardGenerator.randomized(seed: 99, shape: .expanded)
    #expect(first.tiles == second.tiles)
    #expect(first.ports == second.ports)
}
```

- [x] **Step 2: Run to verify they fail**

Run: `swift test --package-path Packages/CatanEngine`
Expected: FAIL — `type 'BoardShape' has no member 'expanded'`.

- [x] **Step 3: Add the Expanded shape**

Beside `classic` in `BoardShape.swift`. Note how much shorter this is than a literal array — that is the composition earning its place.

```swift
    /// The 37-tile board (radius 3) that `GameMode.expanded` is played on.
    ///
    /// One desert plus 36 resource tiles is exactly twice classic's mix, and
    /// the 36 tokens are exactly twice classic's multiset — so the dice
    /// distribution is preserved to the card and a player's probability
    /// intuition transfers between modes. A 38th tile would break both and buy
    /// nothing.
    static let expanded = BoardShape(
        radius: 3,
        terrain: .counts([
            .desert: 1,
            .resource(.grain): 8, .resource(.wool): 8, .resource(.lumber): 8,
            .resource(.brick): 6, .resource(.ore): 6,
        ]),
        // Twice each of classic's 18: one 2 and one 12 become two; the pairs
        // of 3-6 and 8-11 become fours.
        tokens: .counts([2: 2, 3: 4, 4: 4, 5: 4, 6: 4, 8: 4, 9: 4, 10: 4, 11: 4, 12: 2]),
        // 14 ports holds classic's ~30% shoreline density (9 of 30 coastal
        // edges) on a 42-edge coast, rather than its 4:5 generic-to-resource
        // ratio — doubling to 18 would cover 43% of the shore and make
        // harbours cheap. Two 2:1 ports per resource is symmetric, which
        // matters more on a map where a whole corner can be out of reach.
        ports: .derived(kinds: [
            .generic, .resource(.grain), .resource(.ore), .resource(.wool),
            .generic, .resource(.brick), .resource(.lumber), .resource(.grain),
            .generic, .resource(.ore), .resource(.wool), .resource(.brick),
            .generic, .resource(.lumber),
        ])
    )
```

- [x] **Step 4: Replace the bound's hard failure with a deterministic repair**

**CHANGED DURING EXECUTION.** The bounded retry itself was pulled forward into Task 3, because
`randomized(seed:shape:)` had an *unbounded* loop that hangs forever on a legal all-6/8
composition — a hang could not wait a task. Task 3 therefore already added
`maxShuffleAttempts` and a `preconditionFailure` on exhaustion.

**So do not re-add the bound.** Read `randomized(seed:shape:)` first and confirm what is
already there. Your job is to replace that `preconditionFailure` with the repair pass below, so
an infeasible-by-shuffling shape is *fixed* rather than crashed on. Keep the bound; only the
exhaustion branch changes.

The loop should end up as:

```swift
        // The bound is already present from Task 3 - keep it.
        var attemptsRemaining = maxShuffleAttempts
        // Classic clears this in a handful of shuffles — 4 hot tiles among 19.
        // Expanded has 8 among 36 on a graph with far more adjacencies, where a
        // clean shuffle is rare enough that an unbounded loop can spin, and a
        // thousand-tile board would never clear it. Try, then repair.
        repeat {
            kinds = baseKinds.shuffled(using: &rng)
            numbers = baseNumbers.shuffled(using: &rng)
            attemptsRemaining -= 1
        } while attemptsRemaining > 0
            && hasAdjacentSixOrEight(kinds: kinds, numbers: numbers, radius: shape.radius)

        numbers = repairingAdjacentSixOrEight(kinds: kinds, numbers: numbers, radius: shape.radius)
```

`maxShuffleAttempts` already exists from Task 3; leave it. Add only the repair:

```swift
    /// Swaps every 6/8 that touches another 6/8 onto a cool tile, walking tiles
    /// in spiral order and taking the first cool partner that does not itself
    /// create an adjacency.
    ///
    /// Deterministic and RNG-free: the walk is over an ordered array, never a
    /// `Set`, and the partner is "first that works" rather than a random pick.
    /// Two calls with the same input return the same board, in this process and
    /// in tomorrow's.
    private static func repairingAdjacentSixOrEight(
        kinds: [TileKind], numbers: [Int], radius: Int
    ) -> [Int] {
        let coordinates = spiralCoordinates(radius: radius)
        var tokenIndexByCoordinate: [HexCoordinate: Int] = [:]
        var nextToken = 0
        for (coordinate, kind) in zip(coordinates, kinds) where kind != .desert {
            tokenIndexByCoordinate[coordinate] = nextToken
            nextToken += 1
        }
        var result = numbers
        func isHot(_ token: Int) -> Bool { token == 6 || token == 8 }
        func touchesHot(_ coordinate: HexCoordinate, ignoring: HexCoordinate?) -> Bool {
            (0..<6).contains { direction in
                let neighbor = coordinate.neighbor(direction)
                guard neighbor != ignoring, let index = tokenIndexByCoordinate[neighbor] else { return false }
                return isHot(result[index])
            }
        }
        for coordinate in coordinates {
            guard let index = tokenIndexByCoordinate[coordinate], isHot(result[index]) else { continue }
            guard touchesHot(coordinate, ignoring: nil) else { continue }
            let partner = coordinates.first { candidate in
                guard let candidateIndex = tokenIndexByCoordinate[candidate],
                      !isHot(result[candidateIndex]) else { return false }
                return !touchesHot(candidate, ignoring: coordinate)
            }
            guard let partner, let partnerIndex = tokenIndexByCoordinate[partner] else { continue }
            result.swapAt(index, partnerIndex)
        }
        return result
    }
```

- [x] **Step 5: Prove the shape that used to crash now deals**

Add the case that closes the loop on Task 3's emergency fix:

```swift
@Test func aShapeNoShuffleCanSatisfyIsRepairedRatherThanRefused() {
    // Every token hot. No shuffle can ever satisfy the no-adjacent-6/8 rule,
    // so Task 3's bound would exhaust and crash. The repair must deal a board
    // instead - and the rule is unsatisfiable here, so what it must NOT do is
    // loop, crash, or silently drop tokens.
    let shape = BoardShape(
        radius: 2,
        terrain: .counts([.desert: 1, .resource(.grain): 9, .resource(.ore): 9]),
        tokens: .counts([6: 9, 8: 9]),
        ports: .derived(kinds: [.generic])
    )
    let board = BoardGenerator.randomized(seed: 7, shape: shape)
    #expect(board.tiles.count == 19)
    #expect(board.tiles.compactMap(\.numberToken).count == 18)
    // Reproducible despite going through the repair path.
    #expect(BoardGenerator.randomized(seed: 7, shape: shape).tiles == board.tiles)
}
```

If the repair cannot satisfy the rule (as here, where it is unsatisfiable), it must still
return a complete, reproducible board. Document that in the repair's doc comment: it is
best-effort on the 6/8 rule and absolute on completeness and determinism.

- [x] **Step 6: Run the tests**

Run: `swift test --package-path Packages/CatanEngine`
Expected: PASS, all seven new cases plus every Classic case. The 50-seed sweep is the important one: if any seed leaves an adjacency, the repair needs a second pass. **Do not weaken the test.**

- [x] **Step 7: Commit**

```bash
git add Packages/CatanEngine
git commit -m "feat(engine): add the 37-tile Expanded board shape

One desert plus 36 resource tiles is exactly twice classic's mix, and the 36
tokens are exactly twice classic's multiset, so the dice distribution is
preserved to the card and probability intuition transfers between modes.

Replaces the bounded retry's hard failure with a deterministic repair pass.
Task 3 bounded the previously unbounded loop and crashed on exhaustion, which
was the right emergency fix for a hang but refuses a board it could have
repaired. Classic clears the no-adjacent-6/8 rule in one or two shuffles with 4
hot tiles among 19; Expanded has 8 among 36 on a graph with far more
adjacencies, and a thousand-tile board would never clear it by shuffling. The
repair walks tiles in spiral order and uses no RNG, so a seed still reproduces
its board across processes.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TBxaHYvMxcRujKxfhdFdAe"
```

---

## Task 5: `GameMode` and `Ruleset`

**Files:**
- Create: `Packages/CatanEngine/Sources/CatanEngine/Models/GameMode.swift`
- Create: `Packages/CatanEngine/Sources/CatanEngine/Ruleset.swift`
- Test: Create `Packages/CatanEngine/Tests/CatanEngineTests/RulesetTests.swift`

**Interfaces:**
- Consumes: `BoardShape.classic`, `BoardShape.expanded` from Tasks 3–4.
- Produces: `GameMode` (`.classic`, `.expanded`; `String`-raw `Codable`, `CaseIterable`, `Sendable`), `GameMode.displayName`, `GameMode.summary`, `Ruleset`, `Ruleset.forMode(_:)`, `PieceAllowance`, `BankAllowance`, `Ruleset.pieceLimit(for:)`, `Ruleset.victoryPoints(for:)`, `Ruleset.bankPerResource`, `Ruleset.validationProblem`.

- [x] **Step 1: Write the failing test**

```swift
import Testing
@testable import CatanEngine

@Test func classicRulesetMatchesTheValuesTheEngineShippedWith() {
    let rules = Ruleset.forMode(.classic)
    #expect(rules.victoryPointTargets == 8...12)
    #expect(rules.defaultVictoryPointTarget == 10)
    #expect(rules.longestRoadBonus == 2)
    #expect(rules.largestArmyBonus == 2)
    #expect(rules.longestRoadMinimum == 5)
    #expect(rules.largestArmyMinimum == 3)
    #expect(rules.maxRoadsPerPlayer == 15)
    #expect(rules.pieceLimit(for: .settlement) == 5)
    #expect(rules.pieceLimit(for: .city) == 4)
    #expect(rules.victoryPoints(for: .settlement) == 1)
    #expect(rules.victoryPoints(for: .city) == 2)
    #expect(rules.bankPerResource == 19)
    #expect(rules.discardThreshold == 7)
    #expect(rules.devCardDeckSize == 25)
    #expect(rules.board == BoardShape.classic)
}

@Test func expandedRulesetMatchesTheSpec() {
    let rules = Ruleset.forMode(.expanded)
    #expect(rules.victoryPointTargets == 25...25)
    #expect(rules.defaultVictoryPointTarget == 25)
    #expect(rules.longestRoadBonus == 4)
    #expect(rules.largestArmyBonus == 4)
    #expect(rules.longestRoadMinimum == 5)
    #expect(rules.largestArmyMinimum == 3)
    #expect(rules.maxRoadsPerPlayer == 30)
    #expect(rules.pieceLimit(for: .settlement) == 10)
    #expect(rules.pieceLimit(for: .city) == 8)
    #expect(rules.victoryPoints(for: .settlement) == 1)
    #expect(rules.victoryPoints(for: .city) == 2)
    #expect(rules.bankPerResource == 38)
    #expect(rules.discardThreshold == 10)
    #expect(rules.devCardDeckSize == 50)
    #expect(rules.board == BoardShape.expanded)
}

@Test func expandedDeckIsExactlyTwiceClassic() {
    let classic = Ruleset.forMode(.classic).devCardDeck
    let expanded = Ruleset.forMode(.expanded).devCardDeck
    for type in DevCardType.allCases {
        #expect(expanded[type, default: 0] == classic[type, default: 0] * 2)
    }
}

@Test func everyModeIsCoherentAndReachable() {
    for mode in GameMode.allCases {
        let rules = Ruleset.forMode(mode)
        #expect(rules.validationProblem == nil, "\(mode): \(rules.validationProblem ?? "")")
        // Buildings are the only source of points a player can grow without
        // limit in time; a target above their ceiling is a game that cannot end.
        let ceiling = BuildingKind.allCases.reduce(0) {
            $0 + rules.pieceLimit(for: $1) * rules.victoryPoints(for: $1)
        }
        #expect(ceiling >= rules.victoryPointTargets.upperBound,
                "\(mode) targets \(rules.victoryPointTargets.upperBound) with a \(ceiling)-point ceiling")
        #expect(!mode.displayName.isEmpty)
        #expect(!mode.summary.isEmpty)
    }
}

@Test func aModeWhoseRoadLimitOutrunsTheSearchIsRefused() {
    // The tripwire: a future mode must fail at construction, not by freezing
    // the game on a road placement.
    let reckless = Ruleset(
        board: .expanded, victoryPointTargets: 25...25, defaultVictoryPointTarget: 25,
        longestRoadBonus: 4, largestArmyBonus: 4, longestRoadMinimum: 5, largestArmyMinimum: 3,
        pieceLimits: .explicit([.settlement: 10, .city: 8]),
        victoryPointsPerBuilding: [.settlement: 1, .city: 2],
        maxRoadsPerPlayer: LongestRoad.supportedRoadLimit + 1,
        bank: .explicit(38),
        devCardDeck: [.knight: 28, .victoryPoint: 10, .roadBuilding: 4, .yearOfPlenty: 4, .monopoly: 4],
        discardThreshold: 10
    )
    #expect(reckless.validationProblem != nil)
}
```

- [x] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/CatanEngine --filter RulesetTests`
Expected: FAIL — `cannot find 'Ruleset' in scope`.

- [x] **Step 3: Make `BuildingKind` enumerable**

`BuildingKind` (`Models/Player.swift:1`) is `Codable, Sendable` but **not** `CaseIterable`, and both the ceiling check and `validationProblem` enumerate it. Add the conformance:

```swift
public enum BuildingKind: Codable, Sendable, CaseIterable, Hashable {
    case settlement, city
}
```

`Hashable` too — it is a dictionary key in `Ruleset` now. Adding a third case later then automatically reaches every loop that drives off `allCases`, which is the point of keying by kind.

- [x] **Step 4: Create `Models/GameMode.swift`**

```swift
/// Which rule set a game is played under.
///
/// A tag, not a bag of values: the quantities live in `Ruleset`, keyed by this.
/// Storing the tag rather than the numbers means a save cannot carry an
/// incoherent combination — a 25-point target beside classic's five-settlement
/// limit — and adding a mode needs one decode default rather than one per
/// quantity.
///
/// `String`-raw on purpose: saves store this, and a `String` survives
/// reordering the cases where an `Int` would not.
public enum GameMode: String, Codable, CaseIterable, Sendable {
    /// The 19-tile board played to 8, 10 or 12 points. Every save written
    /// before modes existed is this one.
    case classic
    /// The 37-tile board played to 25, with doubled pieces, bank and deck, and
    /// 4-point bonuses.
    case expanded

    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .expanded: return "Expanded"
        }
    }

    /// One line, shown under the name in the mode picker.
    public var summary: String {
        switch self {
        case .classic: return "The standard 19-tile board, played to 8, 10 or 12 points."
        case .expanded: return "A 37-tile map played to 25 points, with twice the pieces and 4-point bonuses."
        }
    }
}
```

- [x] **Step 5: Create `Ruleset.swift`**

```swift
/// How many of each piece a player owns.
public enum PieceAllowance: Sendable, Equatable {
    case explicit([BuildingKind: Int])
    /// Scaled from the board's tile count against classic's ratio, for a mode
    /// that wants supplies proportional to its map without hand-computing them.
    case scaledFromBoard

    func limit(for kind: BuildingKind, board: BoardShape) -> Int { /* implement */ }
}

/// How many cards of each resource the bank starts with.
public enum BankAllowance: Sendable, Equatable {
    case explicit(Int)
    case scaledFromBoard

    func perResource(board: BoardShape) -> Int { /* implement */ }
}

/// Every quantity the rules need, for one mode.
///
/// ## Why one value rather than constants per rule
/// These numbers were literals scattered across `Building`, `LongestRoad`,
/// `DevCards`, `Robber`, `WinCondition` and `GameSetup`. Adding a second rule
/// set that way means finding all of them; adding a third means finding them
/// again. Here a new mode is one case in `forMode(_:)`, and the switch is
/// exhaustive, so the compiler names anything left out.
///
/// ## Keyed by building KIND, not by named field
/// `pieceLimits` and `victoryPointsPerBuilding` are dictionaries because a
/// third building tier is planned (a "double city" worth 4). As three flat
/// fields, adding it would edit every limit check and both victory-point
/// formulas; as dictionary entries it edits neither.
///
/// ## Where the boundary is
/// This covers quantities and board shape. A mode that changes the *shape* of a
/// move — a new development card, a build action, a trade type — is a change to
/// `GameMove` and `RulesEngine`, not a field here. Adding a field with a
/// classic-valued default is the supported way to grow this; every other mode
/// keeps compiling.
public struct Ruleset: Sendable, Equatable {
    public let board: BoardShape
    public let victoryPointTargets: ClosedRange<Int>
    public let defaultVictoryPointTarget: Int
    public let longestRoadBonus: Int
    public let largestArmyBonus: Int
    /// Shortest road that can claim the bonus.
    public let longestRoadMinimum: Int
    /// Fewest played knights that can claim the bonus.
    public let largestArmyMinimum: Int
    public let pieceLimits: PieceAllowance
    public let victoryPointsPerBuilding: [BuildingKind: Int]
    public let maxRoadsPerPlayer: Int
    public let bank: BankAllowance
    public let devCardDeck: [DevCardType: Int]
    /// A player holding MORE than this many resource cards discards on a 7.
    public let discardThreshold: Int

    public func pieceLimit(for kind: BuildingKind) -> Int {
        pieceLimits.limit(for: kind, board: board)
    }
    public func victoryPoints(for kind: BuildingKind) -> Int {
        victoryPointsPerBuilding[kind, default: 0]
    }
    /// Starting stock of each resource. Named apart from the stored `bank`
    /// allowance it resolves, because Swift will not take a property and a
    /// computed property of the same name.
    public var bankPerResource: Int { bank.perResource(board: board) }
    public var devCardDeckSize: Int { devCardDeck.values.reduce(0, +) }

    /// Why this rule set cannot be played, or `nil` if it can.
    ///
    /// The road limit is checked against what the longest-road search can
    /// actually serve. A mode that exceeds it must fail here, at construction,
    /// rather than by freezing the game on a road placement — which is what the
    /// old exhaustive search did past roughly 40 roads.
    public var validationProblem: String? {
        if let boardProblem = board.compositionProblem { return boardProblem }
        guard maxRoadsPerPlayer <= LongestRoad.supportedRoadLimit else {
            return "\(maxRoadsPerPlayer) roads exceeds the \(LongestRoad.supportedRoadLimit) "
                + "the longest-road search is measured to support"
        }
        guard victoryPointTargets.contains(defaultVictoryPointTarget) else {
            return "default target \(defaultVictoryPointTarget) is outside \(victoryPointTargets)"
        }
        for kind in BuildingKind.allCases where victoryPointsPerBuilding[kind] == nil {
            return "\(kind) has no victory-point value"
        }
        return nil
    }

    /// The rules for `mode`. Exhaustive on purpose: a new `GameMode` case fails
    /// to compile until it is given values here, which is the point of the tag.
    public static func forMode(_ mode: GameMode) -> Ruleset { /* both cases */ }
}
```

Fill in both cases from the Global Constraints table. Classic: targets `8...12`, default 10, bonuses 2/2, minimums 5/3, pieces `.explicit([.settlement: 5, .city: 4])`, points `[.settlement: 1, .city: 2]`, 15 roads, `bank: .explicit(19)`, deck `[.knight: 14, .victoryPoint: 5, .roadBuilding: 2, .yearOfPlenty: 2, .monopoly: 2]`, discard 7. Expanded: targets `25...25`, default 25, bonuses 4/4, minimums 5/3, pieces `.explicit([.settlement: 10, .city: 8])`, points `[.settlement: 1, .city: 2]`, 30 roads, `bank: .explicit(38)`, deck doubled, discard 10.

Comment the Expanded case with the *reasons*: pieces double because classic's limits cap buildings at 13 VP and 25 would otherwise need nearly every VP card; the discard threshold rises because doubled income would trigger classic's 7 for most players on most sevens; **the two bonus minimums deliberately do not move (Jake, 2026-09-10)**.

- [x] **Step 6: Add `LongestRoad.supportedRoadLimit`**

In `LongestRoad.swift`, from Task 1's measured curve:

```swift
    /// The largest per-player road limit the search is measured to serve
    /// comfortably. `Ruleset.validationProblem` refuses a mode above this.
    ///
    /// Set from the measurement in Task 1's commit, not guessed. Raising it
    /// requires re-running that measurement and pasting the new numbers.
    public static let supportedRoadLimit = <FROM TASK 1's MEASURED CURVE>
```

Pick the value from Task 1's after-numbers: the largest road count whose **dense** case stays under 20ms. Record the number and its measurement in the commit message.

- [x] **Step 7: Run the tests**

Run: `swift test --package-path Packages/CatanEngine`
Expected: PASS — the five new cases and the whole existing suite, since `BuildingKind` gained conformances but no behaviour changed.

- [x] **Step 8: Commit**

```bash
git add Packages/CatanEngine
git commit -m "feat(engine): add GameMode and Ruleset

Every rule quantity the engine hard-codes gets a home keyed by mode, so a third
rule set is one enum case plus one literal instead of an archaeology pass
across six files. The switch in forMode(_:) is exhaustive, so a new mode fails
to compile until it is given values.

A tag rather than per-value fields on GameState: storing the numbers separately
would admit an incoherent save - a 25-point target beside classic's
five-settlement limit - and cost a decode default and a compatibility case
each.

Piece limits and victory points are keyed by BuildingKind rather than named
per-field, because a third building tier is planned. As flat fields that
feature would edit every limit check and both victory-point formulas; as
dictionary entries it edits neither.

validationProblem refuses a mode whose road limit outruns the longest-road
search, so a future large mode fails at construction instead of freezing the
game on a road placement.

Nothing reads any of this yet; the call sites move in a later commit.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TBxaHYvMxcRujKxfhdFdAe"
```

---
## Task 6: `GameState.mode`, decoding, and schema version 4

**Files:**
- Modify: `Packages/CatanEngine/Sources/CatanEngine/Models/GameState.swift`
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/SaveCompatibilityTests.swift`

**Interfaces:**
- Consumes: `GameMode`, `Ruleset.forMode(_:)` from Task 5.
- Produces: `GameState.mode: GameMode`, `GameState.rules: Ruleset` (computed), `GameState.init(..., mode: GameMode = .classic, ...)`, `GameState.currentSchemaVersion == 4`, and **all three `GameSetup.newGame` overloads taking `victoryPointTarget: Int? = nil, mode: GameMode = .classic`** (moved here from Task 7 — see Step 5).

- [x] **Step 1: Write the failing test**

Add to `SaveCompatibilityTests.swift`:

```swift
@Test func aSaveWrittenBeforeModesExistedLoadsAsClassic() throws {
    let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 7), seed: 7)
    let data = try encodeOmitting(["mode"], from: state)
    let decoded = try JSONDecoder().decode(GameState.self, from: data)
    #expect(decoded.mode == .classic)
    #expect(decoded.victoryPointTarget == 10)
    #expect(decoded.rules.longestRoadBonus == 2)
}

@Test func anExpandedSaveRoundTripsWithItsModeAndTarget() throws {
    let state = GameSetup.newGame(board: BoardGenerator.standard(BoardShape.expanded),
                                  seed: 11, mode: .expanded)
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(GameState.self, from: data)
    #expect(decoded.mode == .expanded)
    #expect(decoded.victoryPointTarget == 25)
    #expect(decoded.rules.longestRoadBonus == 4)
    #expect(decoded.board.tiles.count == 37)
}

@Test func aClassicSaveCarryingAnExpandedTargetIsRefused() throws {
    // 25 is legal for Expanded and corrupt for Classic. The guard exists
    // because an out-of-range target would otherwise let the very next build
    // declare a winner.
    var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 3), seed: 3)
    state.victoryPointTarget = 10
    var object = try JSONSerialization.jsonObject(
        with: try JSONEncoder().encode(state)) as! [String: Any]
    object["victoryPointTarget"] = 25
    object["mode"] = "classic"
    let data = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(GameState.self, from: data)
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/CatanEngine --filter SaveCompatibilityTests`
Expected: FAIL — `value of type 'GameState' has no member 'mode'`.

- [x] **Step 3: Add the stored property and the accessor**

In `GameState.swift`, bump the version constant and document the bump beside the existing note:

```swift
    /// Bumped to 4 when `mode` was added.
    public static let currentSchemaVersion = 4
```

Add beside `victoryPointTarget`:

```swift
    /// Which rule set THIS game is played under.
    ///
    /// Beside the position for the same reason `victoryPointTarget` is: the
    /// rules are a property of the game, not of the process. A global would
    /// make every rule read depend on which screen was last opened, and a
    /// resumed Expanded game would silently revert to classic's quantities
    /// while keeping its 37-tile board — the rules and the board disagreeing
    /// mid-game.
    public var mode: GameMode

    /// The quantities this game is played with. Derived, never stored, so a
    /// save cannot carry a rule set that disagrees with its own mode.
    public var rules: Ruleset { Ruleset.forMode(mode) }
```

Add `mode: GameMode = .classic` to the memberwise `init` parameter list (after `schemaVersion`, before `victoryPointTarget`) and assign `self.mode = mode` before `self.victoryPointTarget`.

- [x] **Step 4: Decode `mode` before validating the target**

In `init(from:)`, insert immediately after the `schemaVersion` line and **before** the `victoryPointTarget` block:

```swift
        // Absent in every save written before modes existed. Those games were
        // played under the only rules there were.
        mode = try container.decodeIfPresent(GameMode.self, forKey: .mode) ?? .classic
```

Then change the target guard to ask the mode rather than a global range:

```swift
        let decodedTarget = try container.decodeIfPresent(Int.self, forKey: .victoryPointTarget)
            ?? Ruleset.forMode(mode).defaultVictoryPointTarget
        // Range-checked on the way in, not only at construction. A save
        // carrying 0 - corruption, or a future version widening the range -
        // would otherwise make the very next build declare seat 0 the winner.
        //
        // Decode order is load-bearing: `mode` is read above, because
        // validating the target against a range not yet known would reject
        // every Expanded save as corrupt.
        guard Ruleset.forMode(mode).victoryPointTargets.contains(decodedTarget) else {
            throw DecodingError.dataCorruptedError(
                forKey: .victoryPointTarget,
                in: container,
                debugDescription: "Target \(decodedTarget) is outside \(mode.displayName)'s range"
            )
        }
        victoryPointTarget = decodedTarget
```

- [x] **Step 5: Run tests to verify they pass**

**PREFLIGHT RULING (controller, before execution):** the `newGame` change moved from Task 7 into this task. The tests above construct Expanded states, so they cannot compile without it, and a task whose own tests do not compile is not independently reviewable. Apply Task 7's Step 3 verbatim **here**:

```swift
    public static func newGame(board: Board, rng: inout some RandomNumberGenerator,
                               playerCount: Int = GameSetup.standardPlayerCount,
                               victoryPointTarget: Int? = nil,
                               mode: GameMode = .classic) -> GameState {
        precondition(supportedPlayerCounts.contains(playerCount),
                     "playerCount \(playerCount) is outside \(supportedPlayerCounts)")
        let rules = Ruleset.forMode(mode)
        let target = victoryPointTarget ?? rules.defaultVictoryPointTarget
        precondition(rules.victoryPointTargets.contains(target),
                     "victoryPointTarget \(target) is outside \(mode.displayName)'s \(rules.victoryPointTargets)")
        precondition(board.tiles.count == rules.board.tileCount,
                     "a \(board.tiles.count)-tile board cannot host \(mode.displayName), "
                     + "which is played on \(rules.board.tileCount) tiles")
        let players = (0..<playerCount).map { Player(id: PlayerID(index: $0)) }

        var bank: [Resource: Int] = [:]
        for resource in Resource.allCases {
            bank[resource] = rules.bankPerResource
        }

        // Driven off `DevCardType.allCases`, not off the dictionary, so the
        // deck is built in a stable order before it is shuffled. Dictionary
        // iteration order is seeded per process; shuffling an
        // unstably-ordered array gives a different deck per launch for the
        // same seed, which is the determinism bug this repo has paid for four
        // times.
        var devCardDeck: [DevCardType] = []
        for type in DevCardType.allCases {
            devCardDeck.append(contentsOf: repeatElement(type, count: rules.devCardDeck[type, default: 0]))
        }
        devCardDeck.shuffle(using: &rng)

        return GameState(
            board: board,
            players: players,
            phase: .setupForward(playerIndex: 0),
            bank: bank,
            devCardDeck: devCardDeck,
            rng: RandomSource(seed: rng.next()),
            mode: mode,
            victoryPointTarget: target
        )
    }
```

Add the same `victoryPointTarget: Int? = nil, mode: GameMode = .classic` tail to the `seed:` and no-argument overloads, forwarding both. Fix any caller the `Int?` change breaks.

- [x] **Step 6: Run tests to verify they pass**

Run: `swift test --package-path Packages/CatanEngine`
Expected: PASS. The whole engine suite must stay green — `mode` defaults to `.classic` everywhere, so no existing behaviour changes.

- [x] **Step 7: Commit**

```bash
git add Packages/CatanEngine/Sources/CatanEngine/Models/GameState.swift \
        Packages/CatanEngine/Tests/CatanEngineTests/SaveCompatibilityTests.swift
git commit -m "feat(engine): store the game mode on GameState

One Codable field defaulting to .classic, so every existing save decodes
untouched and keeps playing the rules it started under. Schema version 4.

Decode order is load-bearing and is documented as such: mode is read before
the victory-point target, because that guard validates the target against the
mode's permitted range, and checking it against a range not yet known would
reject every Expanded save as corrupt - the failure mode that silently deleted
every player's in-progress game once already.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TBxaHYvMxcRujKxfhdFdAe"
```

---

## Task 7: Route every engine rule site through `state.rules`

The largest task, and a pure refactor: Classic's numbers do not change, so the existing suites are the net.

**Files:**
- Modify: `Packages/CatanEngine/Sources/CatanEngine/Building.swift:23-25,48,75,94`
- Modify: `Packages/CatanEngine/Sources/CatanEngine/LongestRoad.swift:3,11`
- Modify: `Packages/CatanEngine/Sources/CatanEngine/DevCards.swift:282`
- Modify: `Packages/CatanEngine/Sources/CatanEngine/Robber.swift:7`
- Modify: `Packages/CatanEngine/Sources/CatanEngine/WinCondition.swift`
- Modify: `Packages/CatanEngine/Sources/CatanEngine/Models/GameState.swift` (VP formulas, `GameSetup.newGame`)
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/RulesetRoutingTests.swift` (create)

**Interfaces:**
- Consumes: `GameState.rules` from Task 6.
- Consumes additionally: `GameSetup.newGame(board:seed:playerCount:victoryPointTarget:mode:)` — **built in Task 6**, not here (preflight ruling).
- Produces: `WinCondition.standardTarget` and `WinCondition.supportedTargets` are **deleted**; callers ask the ruleset.

- [ ] **Step 1: Write the failing test**

Create `RulesetRoutingTests.swift`:

```swift
import Testing
@testable import CatanEngine

/// Proves each rule site reads its number from the ruleset rather than from a
/// literal. Each case sets up a position that classic and Expanded score or
/// permit differently, so a missed call site fails here rather than surfacing
/// as a 25-point game that ends at 10.
private func expandedGame(seed: UInt64 = 1) -> GameState {
    GameSetup.newGame(board: BoardGenerator.standard(BoardShape.expanded),
                      seed: seed, mode: .expanded)
}

@Test func expandedBonusesAreWorthFourPointsInBothFormulas() {
    var state = expandedGame()
    let seat = state.players[0].id
    // A fresh game: no buildings, so both formulas start at zero and the 8
    // below is purely the two bonuses.
    #expect(state.victoryPoints(for: seat) == 0)
    state.longestRoadPlayer = seat
    state.largestArmyPlayer = seat
    #expect(state.victoryPoints(for: seat) == 8)
    #expect(state.publicVictoryPoints(for: seat) == 8)
}

@Test func expandedSeatsAThirtyEightCardBankAndAFiftyCardDeck() {
    let state = expandedGame()
    for resource in Resource.allCases {
        #expect(state.bank[resource] == 38)
    }
    #expect(state.devCardDeck.count == 50)
    #expect(state.devCardDeck.filter { $0 == .knight }.count == 28)
    #expect(state.devCardDeck.filter { $0 == .victoryPoint }.count == 10)
}

@Test func expandedDiscardThresholdIsTenNotSeven() {
    var state = expandedGame()
    for resource in Resource.allCases {
        state.players[0].resources[resource] = 2   // 10 cards total
    }
    #expect(Robber.playersWhoMustDiscard(state).isEmpty)
    state.players[0].resources[.grain, default: 0] += 1   // 11
    #expect(Robber.playersWhoMustDiscard(state).contains(state.players[0].id))
}

@Test func classicDiscardThresholdIsStillSeven() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    for resource in Resource.allCases {
        state.players[0].resources[resource] = 1   // 5 cards
    }
    #expect(Robber.playersWhoMustDiscard(state).isEmpty)
    state.players[0].resources[.grain] = 4   // 8 cards
    #expect(Robber.playersWhoMustDiscard(state).contains(state.players[0].id))
}

@Test func expandedWinsAtTwentyFiveNotTen() {
    var state = expandedGame()
    let seat = state.players[0].id
    // `Player.victoryPoints` is COMPUTED and read-only (`Player.swift:35`) -
    // it cannot be assigned. Build the total out of real pieces instead:
    // 8 cities (16) + 1 settlement (1) = 17, so the two 4-point bonuses are
    // exactly what carries this seat from 21 to 25.
    let vertices = state.board.onBoardVertices.sorted()
    state.players[0].cities = Set(vertices.prefix(8))
    state.players[0].settlements = Set(vertices.dropFirst(8).prefix(1))
    #expect(state.victoryPoints(for: seat) == 17)

    state.longestRoadPlayer = seat   // 17 + 4 = 21
    WinCondition.checkForWinner(&state)
    if case .gameOver = state.phase { Issue.record("ended at 21 of 25") }

    state.largestArmyPlayer = seat   // 21 + 4 = 25
    #expect(state.victoryPoints(for: seat) == 25)
    WinCondition.checkForWinner(&state)
    #expect(state.phase == .gameOver(winner: seat))
}

@Test func expandedAllowsThirtyRoadsWhereClassicStopsAtFifteen() {
    #expect(Ruleset.forMode(.expanded).maxRoadsPerPlayer == 30)
    #expect(Ruleset.forMode(.classic).maxRoadsPerPlayer == 15)
    // The supply check reads the ruleset: a classic game must still refuse a
    // 16th road. `PieceSupplyTests` covers the classic path in full.
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    let seat = state.players[0].id
    state.players[0].roads = Set(state.board.onBoardEdges.sorted().prefix(15))
    let spare = state.board.onBoardEdges.sorted().dropFirst(15).first!
    #expect(!Building.canBuildRoad(spare, for: seat, in: state))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/CatanEngine --filter RulesetRoutingTests`
Expected: FAIL — `newGame` has no `mode:` parameter.

- [ ] **Step 3: Give `GameSetup.newGame` a mode**

In `GameState.swift`, replace the bank loop and deck construction in the `rng:` overload, and add `mode` to all three overloads:

```swift
    public static func newGame(board: Board, rng: inout some RandomNumberGenerator,
                               playerCount: Int = GameSetup.standardPlayerCount,
                               victoryPointTarget: Int? = nil,
                               mode: GameMode = .classic) -> GameState {
        precondition(supportedPlayerCounts.contains(playerCount),
                     "playerCount \(playerCount) is outside \(supportedPlayerCounts)")
        let rules = Ruleset.forMode(mode)
        let target = victoryPointTarget ?? rules.defaultVictoryPointTarget
        precondition(rules.victoryPointTargets.contains(target),
                     "victoryPointTarget \(target) is outside \(mode.displayName)'s \(rules.victoryPointTargets)")
        precondition(board.tiles.count == rules.board.tileCount,
                     "a \(board.tiles.count)-tile board cannot host \(mode.displayName), "
                     + "which is played on \(rules.board.tileCount) tiles")
        let players = (0..<playerCount).map { Player(id: PlayerID(index: $0)) }

        var bank: [Resource: Int] = [:]
        for resource in Resource.allCases {
            bank[resource] = rules.bankPerResource
        }

        // Driven off `DevCardType.allCases`, not off the dictionary, so the
        // deck is built in a stable order before it is shuffled. Dictionary
        // iteration order is seeded per process; shuffling an
        // unstably-ordered array gives a different deck per launch for the
        // same seed, which is the determinism bug this repo has paid for four
        // times.
        var devCardDeck: [DevCardType] = []
        for type in DevCardType.allCases {
            devCardDeck.append(contentsOf: repeatElement(type, count: rules.devCardDeck[type, default: 0]))
        }
        devCardDeck.shuffle(using: &rng)

        return GameState(
            board: board,
            players: players,
            phase: .setupForward(playerIndex: 0),
            bank: bank,
            devCardDeck: devCardDeck,
            rng: RandomSource(seed: rng.next()),
            mode: mode,
            victoryPointTarget: target
        )
    }
```

Add the same `victoryPointTarget: Int? = nil, mode: GameMode = .classic` tail to the `seed:` and no-argument overloads, forwarding both.

- [ ] **Step 4: Route the five rule sites**

**First, delete `Player.victoryPoints` — it is a second scoring formula.**

`Models/Player.swift:35` computes `settlements.count + cities.count * 2 + <VP cards>`, hardcoding
settlement = 1 and city = 2. `Player` has no access to a `Ruleset` and should not gain one — it is
a bag of pieces, not a scorer. Left in place, adding the planned `.doubleCity` tier means editing
this too, which defeats the whole reason piece points are keyed by `BuildingKind`.

`GameState` owns the mode, so `GameState` owns the scoring. Delete the property and fold its
logic into `GameState.victoryPoints(for:)`. Its only production reader is `GameState.swift:212`;
`grep -rn "\.victoryPoints\b"` confirms nothing in `Settlers/` reads it. Fix any test that does.

This also removes a duplicate formula the codebase already warns about: `publicVictoryPoints`'s own
doc comment says a second victory-point formula is "the worst possible thing to maintain in two
places."

```swift
    /// Buildings scored at this mode's rates, plus VP dev cards. Driven off
    /// `BuildingKind.allCases` so a new building tier is a `Ruleset` entry
    /// rather than an edit here.
    private func buildingAndCardPoints(for player: Player) -> Int {
        let buildings = BuildingKind.allCases.reduce(0) { total, kind in
            let count: Int
            switch kind {
            case .settlement: count = player.settlements.count
            case .city: count = player.cities.count
            }
            return total + count * rules.victoryPoints(for: kind)
        }
        return buildings + player.devCards.filter { $0 == .victoryPoint }.count
    }
```

The `switch` is exhaustive on purpose: a new `BuildingKind` fails to compile here until it is told
which collection holds it, which is the one thing `Ruleset` genuinely cannot know.

Then `GameState.publicVictoryPoints` and `victoryPoints` — replace both `+= 2` pairs, and route
their building terms through the helper above:

```swift
        if longestRoadPlayer == id { total += rules.longestRoadBonus }
        if largestArmyPlayer == id { total += rules.largestArmyBonus }
```

`Robber.playersWhoMustDiscard`:

```swift
    /// Players holding more than `Ruleset.discardThreshold` resource cards;
    /// each must discard half (rounded down) when a 7 is rolled.
    public static func playersWhoMustDiscard(_ state: GameState) -> Set<PlayerID> {
        Set(state.players.filter { totalResources($0) > state.rules.discardThreshold }.map(\.id))
    }
```

`LongestRoad.compute` — delete the `minimumLength` constant, read the state:

```swift
        guard let maxLength = lengths.map(\.1).max(),
              maxLength >= state.rules.longestRoadMinimum else { return nil }
```

`DevCards.computeLargestArmy`:

```swift
        guard let maxCount = counts.map(\.1).max(),
              maxCount >= state.rules.largestArmyMinimum else { return nil }
```

`Building` — the three limits become parameters of the state. Delete the three `static let`s and change the three guards:

```swift
        guard owner.roads.count < state.rules.maxRoadsPerPlayer else { return false }
        guard owner.settlements.count < state.rules.pieceLimit(for: .settlement) else { return false }
        guard owner.cities.count < state.rules.pieceLimit(for: .city) else { return false }
```

Keep the piece-supply comment block in `Building.swift`, retargeted: the *reason* pieces are limited is unchanged; only where the numbers live moves. Add a line saying the values are now `Ruleset`'s.

`WinCondition` — delete `standardTarget` and `supportedTargets`, keeping the reasoning that justified the range in `Ruleset.forMode`'s classic case. `checkForWinner` already reads `state.victoryPointTarget` and needs no change.

- [ ] **Step 5: Fix every caller the deletions break**

`WinCondition.standardTarget` and `.supportedTargets` had callers outside the engine. Find them:

```bash
grep -rn "standardTarget\|supportedTargets\|Building.maxRoads\|Building.maxSettlements\|Building.maxCities" \
  --include="*.swift" Packages/ Settlers/ SettlersTests/ SettlersUITests/
```

Replace each with `Ruleset.forMode(<mode>).<field>`. In app code the mode comes from `setup.mode` or `state.mode`; in tests that predate modes, `Ruleset.forMode(.classic)`.

- [ ] **Step 6: Run the full engine and AI suites**

Run: `swift test --package-path Packages/CatanEngine`
Run: `swift test --package-path Packages/CatanAI`
Expected: PASS, both. `CatanAI` takes 55–175s. Every pre-existing test must stay green — Classic's numbers did not change, so a failure here means a call site was rerouted to the wrong field.

- [ ] **Step 7: Commit**

```bash
git add -A Packages/CatanEngine Packages/CatanAI
git commit -m "refactor(engine): read every rule quantity from the ruleset

Piece limits, bank size, deck composition, both bonus values, both bonus
minimums, the discard threshold and the victory-point range now come from
Ruleset rather than from literals in six files. Classic's values are
unchanged, so the existing suites are the proof: no fingerprint, determinism
or save-compatibility test moves.

Deletes WinCondition.standardTarget and .supportedTargets. A global 'the'
target is exactly the assumption a second rule set breaks, and leaving them
as classic-flavoured aliases would let a caller silently validate an Expanded
game against classic's range.

Builds the dev deck off DevCardType.allCases rather than the composition
dictionary, so the pre-shuffle order is stable. Dictionary iteration order is
seeded per process, and shuffling an unstably-ordered array yields a different
deck per launch for the same seed.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TBxaHYvMxcRujKxfhdFdAe"
```

---

## Task 8: Expanded plays a full game, and its seeds are pinned

**Files:**
- Modify: `Packages/CatanEngine/Tests/CatanEngineTests/FullGameSimulationTests.swift`
- Modify: `Packages/CatanAI/Tests/CatanAITests/SeededGameFingerprintTests.swift:136,264`

**Interfaces:**
- Consumes: everything from Tasks 1–7. Adds no production code — if a test here fails, the bug is in an earlier task.

> **Note:** `SeededGameFingerprintTests.swift` lives in **`Packages/CatanAI/Tests/CatanAITests/`**, not in `CatanEngineTests`. `CLAUDE.md`'s determinism section implies the engine package; it is wrong. The fingerprints are of *bot self-play*, which is why they are in the AI package — so they run under `swift test --package-path Packages/CatanAI`, the 55–175s suite.

- [ ] **Step 1: Extract the existing simulation driver into a reusable helper**

`FullGameSimulationTests.swift` drives its game with an inline `while` loop inside `randomLegalPlayReachesGameOverWithoutErrors` (lines 4–44). There is no `playToCompletion` helper — write one by lifting that loop verbatim, then have the existing test call it, so the Expanded cases share exactly one driver rather than a second copy that can drift.

```swift
/// Plays `state` to `.gameOver` by picking uniformly among legal moves.
/// Lifted unchanged from `randomLegalPlayReachesGameOverWithoutErrors` so the
/// classic and Expanded cases cannot drift apart. Returns the winner, or
/// `nil` if `moveLimit` was reached first.
private func playRandomlyToCompletion(
    _ state: inout GameState, rng: inout SeededGenerator, moveLimit: Int
) -> PlayerID? {
    var iterations = 0
    while true {
        if case .gameOver(let winner) = state.phase { return winner }
        iterations += 1
        if iterations >= moveLimit { return nil }
        let moves = RulesEngine.legalMoves(for: state)
        #expect(!moves.isEmpty, "no legal moves in phase \(state.phase)")

        // `.discarding` is the one phase where several players can act
        // concurrently and `legalMoves` returns the union of every pending
        // player's legal `.discard` combinations. A `GameMove.discard` payload
        // carries no player identity, so a move picked at random from that
        // merged list isn't necessarily legal for an arbitrarily-picked
        // pending player. Pick the acting player first, then restrict.
        let player: PlayerID
        let candidateMoves: [GameMove]
        if case .discarding(let pending) = state.phase {
            player = pending.sorted().randomElement(using: &rng)!
            let hand = state.players[player.index].resources
            let count = Robber.discardCount(for: state.players[player.index])
            candidateMoves = moves.filter { move in
                guard case .discard(let discarded) = move else { return false }
                guard discarded.values.reduce(0, +) == count else { return false }
                return discarded.allSatisfy { resource, amount in (hand[resource] ?? 0) >= amount }
            }
        } else {
            player = activePlayer(state.phase)
            candidateMoves = moves
        }
        #expect(!candidateMoves.isEmpty, "no legal moves for acting player in phase \(state.phase)")
        guard let move = candidateMoves.randomElement(using: &rng) else { return nil }
        try! RulesEngine.apply(move, by: player, to: &state)
    }
}
```

Rewrite the existing test as a call to it, keeping its 20,000 limit and its `#expect(iterations < 20_000, "game did not terminate")` intent:

```swift
@Test func randomLegalPlayReachesGameOverWithoutErrors() {
    var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 7))
    var rng = SeededGenerator(seed: 7)
    let winner = playRandomlyToCompletion(&state, rng: &rng, moveLimit: 20_000)
    #expect(winner != nil, "game did not terminate")
}
```

- [ ] **Step 2: Run to confirm the extraction changed nothing**

Run: `swift test --package-path Packages/CatanEngine --filter FullGameSimulation`
Expected: PASS. This step has no new behaviour — if it fails, the lift was not verbatim.

- [ ] **Step 3: Write the failing Expanded cases**

```swift
@Test func anExpandedGamePlaysToTwentyFiveWithoutStalling() {
    var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 2_501, shape: .expanded),
                                  seed: 2_501, mode: .expanded)
    var rng = SeededGenerator(seed: 2_501)
    // Raised from the classic 20,000 because a 25-point game on twice the map
    // is legitimately longer. A stall shows up as exhausting this cap.
    let winner = playRandomlyToCompletion(&state, rng: &rng, moveLimit: 60_000)
    #expect(winner != nil, "Expanded game did not finish inside 60,000 moves")
    if let winner {
        #expect(state.victoryPoints(for: winner) >= 25)
    }
    #expect(state.mode == .expanded)
}

@Test func expandedPieceSuppliesAreNeverExceededOverAFullGame() {
    var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 2_502, shape: .expanded),
                                  seed: 2_502, mode: .expanded)
    var rng = SeededGenerator(seed: 2_502)
    _ = playRandomlyToCompletion(&state, rng: &rng, moveLimit: 60_000)
    for player in state.players {
        #expect(player.roads.count <= 30)
        #expect(player.settlements.count <= 10)
        #expect(player.cities.count <= 8)
    }
}
```

- [ ] **Step 4: Run them**

Run: `swift test --package-path Packages/CatanEngine --filter FullGameSimulation`
Expected: PASS.

**Random play is not bot play** — it is a termination and legality check, not a length measurement. The real number comes from Task 14. If the game does not finish inside 60,000 random moves, **do not raise the cap**: report the number and stop. That is Accepted Risk 1 surfacing, and which dial to turn is Jake's call.

- [ ] **Step 5: Pin Expanded fingerprints in the AI package**

`SeededGameFingerprintTests.swift` keys its expectations by seed alone (`expectedFingerprints: [UInt64: String]`, line 136), so Expanded needs its own dictionary rather than a new key format:

```swift
/// Expanded-mode fingerprints. A separate table because the existing one is
/// keyed by seed alone, and a seed means a different game in each mode.
private let expectedExpandedFingerprints: [UInt64: String] = [
    // Filled in by Step 6. Do not guess these.
]
```

and a third `@Test` inside the same suite type as the existing two (line 264), mirroring `seededSelfPlayReproducesExactly` exactly but starting its games with:

```swift
GameSetup.newGame(board: BoardGenerator.standard(BoardShape.expanded), seed: seed, mode: .expanded)
```

- [ ] **Step 6: Record the fingerprints, then verify across processes**

Record the observed values into the dictionary — a fingerprint is pinned from an observed run, never invented. **Only do this after Step 4 passes**, so a fingerprint is never pinned over a broken game.

Then run the suite **twice, as two separate processes**:

Run: `swift test --package-path Packages/CatanAI --filter SeededGameFingerprint`
Run: `swift test --package-path Packages/CatanAI --filter SeededGameFingerprint`

Both must pass. Swift seeds `Set`/`Dictionary` iteration order once per process, so two runs *inside* one process agree with each other and disagree with tomorrow's — that exact mistake shipped a broken RNG fix here once and left the property false for four more places. Two separate processes agreeing is the actual evidence.

- [ ] **Step 7: Commit**

```bash
git add Packages/CatanEngine/Tests/CatanEngineTests/FullGameSimulationTests.swift \
        Packages/CatanAI/Tests/CatanAITests/SeededGameFingerprintTests.swift
git commit -m "test: play Expanded to completion and pin its seeded fingerprints

Lifts the inline simulation loop into a shared driver so the classic and
Expanded cases cannot drift, then plays a full Expanded game to 25 points and
asserts no player exceeds the doubled piece supplies.

Fingerprints were recorded only after the game was observed finishing, and
verified across two separate test processes. Swift seeds Set iteration order
once per process, so two runs inside one process agree with each other and
disagree with tomorrow's - the mistake that once shipped a broken RNG fix here.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TBxaHYvMxcRujKxfhdFdAe"
```

---

## Task 9: `StateEncoding` and `ActionSpace` refuse a non-Classic board

**Files:**
- Modify: `Packages/CatanEngine/Sources/CatanEngine/StateEncoding.swift:336-341`
- Modify: `Packages/CatanEngine/Sources/CatanEngine/ActionSpace.swift:118`
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/StateEncodingTests.swift`

**Interfaces:**
- Consumes: `GameMode`, `Ruleset` from Task 5.
- Produces: `StateEncoding.supportedModes: Set<GameMode>` — `[.classic]`.

- [ ] **Step 1: Write the failing test**

```swift
@Test func theLayoutDeclaresWhichModesItIsDefinedAgainst() {
    #expect(StateEncoding.supportedModes == [.classic])
    #expect(!StateEncoding.supportedModes.contains(.expanded))
}
```

A `precondition` cannot be caught in-process, so the trap itself is not unit-testable; this pins the declaration a caller checks against instead.

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/CatanEngine --filter StateEncodingTests`
Expected: FAIL — no member `supportedModes`.

- [ ] **Step 3: Declare and enforce**

In `StateEncoding.swift`, beside the board-shape constants:

```swift
    /// The modes `layoutVersion` is defined against.
    ///
    /// The layout is fixed-width, so it is fixed-width against ONE board. A
    /// board of another size is not "mostly compatible" — it shifts every slot
    /// after the first board block, and the dangerous version of that failure
    /// is silent: no shape error, no crash, just a model that plays badly.
    /// "The bots got worse" is among the most expensive things to diagnose
    /// here, so this refuses loudly instead.
    ///
    /// Widening this is a real project — new slot counts and a `layoutVersion`
    /// bump — not a one-line edit.
    public static let supportedModes: Set<GameMode> = [.classic]
```

Add to the `BoardIndex` precondition block at line 336:

```swift
            precondition(StateEncoding.supportedModes.contains(state.mode),
                         "layout v\(StateEncoding.layoutVersion) is defined against "
                         + "\(StateEncoding.supportedModes.map(\.rawValue).sorted().joined(separator: ", ")), "
                         + "got \(state.mode.rawValue)")
```

Add the same guard to `ActionSpace.init(board:playerCount:)`. It takes a `Board`, not a `GameState`, so check the tile count against the classic ruleset and name the mode in the message:

```swift
        precondition(board.tiles.count == Ruleset.forMode(.classic).board.tileCount,
                     "ActionSpace is numbered against the \(Ruleset.forMode(.classic).board.tileCount)-tile "
                     + "classic board; got \(board.tiles.count) tiles. Widening it means renumbering every "
                     + "index, which invalidates any artifact trained against the old numbering.")
```

- [ ] **Step 4: Verify the corpus tooling still builds**

Run: `swift build --package-path Packages/CatanAI`
Run: `swift test --package-path Packages/CatanAI`
Expected: PASS. The tooling only ever sees classic boards; if anything now trips the precondition, it was already relying on an unchecked assumption.

- [ ] **Step 5: Commit**

```bash
git add Packages/CatanEngine/Sources/CatanEngine/StateEncoding.swift \
        Packages/CatanEngine/Sources/CatanEngine/ActionSpace.swift \
        Packages/CatanEngine/Tests/CatanEngineTests/StateEncodingTests.swift
git commit -m "feat(engine): refuse to encode a board the layout was not defined against

Both the feature vector and the global action numbering are fixed-width
against the 19-tile classic board. Expanded does not extend them; it makes
them say so. A padded or truncated vector runs without error and merely plays
badly, which looks exactly like a tuning problem and sends you sweeping
weights for a week.

The three heuristic bots are unaffected - they never touch either type. Only
the training and corpus tooling does, and it only ever sees classic boards.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TBxaHYvMxcRujKxfhdFdAe"
```

---

## Task 10: `MatchSetup` carries the mode

**Files:**
- Modify: `Settlers/Persistence/MatchSetup.swift:53-62,102-104,117-119,176-182,200-202,241-242`
- Test: `SettlersTests/NewGameSetupTests.swift`

**Interfaces:**
- Consumes: `GameMode`, `Ruleset` from Task 5.
- Produces: `MatchSetup.mode: GameMode`, `MatchSetup.init(seats:mode:victoryPointTarget:randomizedBoard:randomizeSeatOrder:)`, `MatchSetup.newGameVictoryPointTargets(for:mode:)`.

- [ ] **Step 1: Write the failing test**

```swift
@Test func aSetupDecodedWithoutAModeIsClassic() throws {
    let setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
    var object = try JSONSerialization.jsonObject(
        with: try JSONEncoder().encode(setup)) as! [String: Any]
    object.removeValue(forKey: "mode")
    let data = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(MatchSetup.self, from: data)
    #expect(decoded.mode == .classic)
}

@Test func expandedOffersOnlyTwentyFiveAtEveryTableSize() {
    #expect(MatchSetup.newGameVictoryPointTargets(for: 3, mode: .expanded) == [25])
    #expect(MatchSetup.newGameVictoryPointTargets(for: 4, mode: .expanded) == [25])
    #expect(MatchSetup.newGameVictoryPointTargets(for: 3, mode: .classic) == [8, 10, 12])
    #expect(MatchSetup.newGameVictoryPointTargets(for: 4, mode: .classic) == [8, 10])
}

@Test func anExpandedSetupAtTwentyFiveIsStartable() {
    var setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
    setup.mode = .expanded
    setup.victoryPointTarget = 25
    #expect(setup.validationProblem == nil)
}

@Test func aClassicSetupCarryingTwentyFiveIsRefused() {
    var setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
    setup.mode = .classic
    setup.victoryPointTarget = 25
    #expect(setup.matchProblem != nil)
}
```

If `MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])` is named differently in the file, use the existing prefill factory at `MatchSetup.swift:200` rather than inventing one.

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination 'platform=iOS Simulator,name=Empires QA' -only-testing:SettlersTests/NewGameSetupTests`
Expected: FAIL — no member `mode`. **Do not pipe this through `tail`/`grep`.**

- [ ] **Step 3: Add the property**

```swift
    /// The rule set this match is played under. Duplicated from `GameState`
    /// for the same reason `victoryPointTarget` is: it is the value the next
    /// game will be started with, and the running game owns its own copy.
    public var mode: GameMode
```

Add `mode: GameMode = .classic` to `init` (after `seats`), assign it, and add an explicit `init(from:)`-free default by giving the property a decode fallback — `MatchSetup` uses the synthesized `Codable`, so add a custom `init(from:)` mirroring the synthesized one with `decodeIfPresent` for `mode` only:

```swift
    /// Hand-written for one field. `MatchSetup` is written to disk beside a
    /// running game, so a setup saved before modes existed must still decode -
    /// the synthesized initializer would throw on the missing key and take the
    /// player's configured table with it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seats = try container.decode([Seat].self, forKey: .seats)
        mode = try container.decodeIfPresent(GameMode.self, forKey: .mode) ?? .classic
        victoryPointTarget = try container.decode(Int.self, forKey: .victoryPointTarget)
        randomizedBoard = try container.decode(Bool.self, forKey: .randomizedBoard)
        randomizeSeatOrder = try container.decode(Bool.self, forKey: .randomizeSeatOrder)
    }
```

- [ ] **Step 4: Make the two validators mode-aware**

In `matchProblem`, replace the `WinCondition.supportedTargets` guard:

```swift
        guard Ruleset.forMode(mode).victoryPointTargets.contains(victoryPointTarget) else {
            return "That match length is not available in \(mode.displayName)."
        }
```

Replace `newGameVictoryPointTargets(for:)` with the mode-aware form:

```swift
    /// Targets the New Game screen offers. A product rule, deliberately
    /// narrower than the engine's range: 9 and 11 are legal and nobody asks
    /// for them by name, and 12 is a three-player length.
    ///
    /// Expanded offers exactly one, because there the target is part of the
    /// rule set rather than a dial.
    public static func newGameVictoryPointTargets(for playerCount: Int, mode: GameMode) -> [Int] {
        guard GameSetup.supportedPlayerCounts.contains(playerCount) else { return [] }
        switch mode {
        case .classic: return playerCount == 3 ? [8, 10, 12] : [8, 10]
        case .expanded: return [25]
        }
    }
```

Update `validationProblem`'s call and its message (`"12 VP is available with 3 players."` stays correct only for classic — make it `"That match length is not available at this table size."`), and the normalizer at line 241 to pass `mode`.

- [ ] **Step 5: Run tests**

Run: `xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination 'platform=iOS Simulator,name=Empires QA' -only-testing:SettlersTests/NewGameSetupTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Settlers/Persistence/MatchSetup.swift SettlersTests/NewGameSetupTests.swift
git commit -m "feat(app): carry the game mode in MatchSetup

The match contract gains the rule set beside the target it already held, and
both validators ask the mode's ruleset instead of a global range. Adds a
hand-written init(from:) for the one field: MatchSetup is written to disk
beside a running game, and the synthesized initializer would throw on the
missing key in every setup saved before modes existed.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TBxaHYvMxcRujKxfhdFdAe"
```

---

## Task 11: The mode survives save, resume, replay and export

**Files:**
- Modify: `Settlers/ViewModels/GameViewModel.swift:377-385`
- Modify: `Settlers/Persistence/GameLogStore.swift:97-122` (`SeatRoster`) and the summary type at `:13`
- Modify: `Settlers/Persistence/MatchCheckpointMigration.swift:37`
- Modify: `Settlers/Persistence/MatchCheckpointStore.swift:37,208-209`
- Test: `SettlersTests/MatchCheckpointStoreTests.swift`, `SettlersTests/GameLogStoreTests.swift`

**Interfaces:**
- Consumes: `MatchSetup.mode` (Task 10), `GameState.mode` (Task 6).
- Produces: no new public API — this task makes an existing invariant hold for a new field.

- [ ] **Step 1: Write the failing test**

In `MatchCheckpointStoreTests.swift`:

```swift
@Test func anExpandedMatchResumesAsExpanded() throws {
    // Same fixture shape as `fullMatchCheckpointsResumeWithoutChangingTheSession`
    // (line 10). There is no shared `makeTemporaryStore()` helper in this
    // file - every test builds its own root inline and deletes it.
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) } // Test-owned directory only.
    let store = MatchCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.json"))

    var setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
    setup.mode = .expanded
    setup.victoryPointTarget = 25
    let initial = GameSetup.newGame(board: BoardGenerator.standard(BoardShape.expanded),
                                    seed: 31, mode: .expanded)
    let document = MatchCheckpointDocument(
        activeMatch: MatchCheckpoint(id: UUID(), initialState: initial, setup: setup))
    try store.commit(document, replacingRevision: nil)

    let reloaded = try #require(try store.load())
    let match = try #require(reloaded.activeMatch)
    #expect(match.setup.mode == .expanded)
    #expect(match.state.mode == .expanded)
    #expect(match.state.board.tiles.count == 37)
}

@Test func aCheckpointWhoseSetupAndStateDisagreeOnModeIsRefused() throws {
    var setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
    setup.mode = .expanded
    setup.victoryPointTarget = 25
    // A classic state under an Expanded setup: 19 tiles while the rules say
    // 37. Refuse rather than resume into a game whose board and rules
    // disagree.
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 31)
    #expect(MatchCheckpoint(id: UUID(), initialState: state, setup: setup).setup.mode != state.mode)
}
```

The second case asserts the disagreement the guard in Step 4 must reject. If `MatchCheckpointMigration.prepare` is reachable from the test target with a fixture you can build cheaply, prefer asserting it throws `MigrationError.incompatibleRoster` directly — read the existing `CheckpointMigrationTests.swift` for how it constructs its arguments, and mirror that rather than inventing a `GameSession` initializer.

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination 'platform=iOS Simulator,name=Empires QA' -only-testing:SettlersTests/MatchCheckpointStoreTests`
Expected: FAIL — a classic state under an Expanded setup is currently accepted.

- [ ] **Step 3: Start the right board and mode**

`GameViewModel.makeInitialState`:

```swift
    private static func makeInitialState(for setup: MatchSetup, playerCount: Int) -> GameState {
        let shape = Ruleset.forMode(setup.mode).board
        let board = setup.randomizedBoard
            ? BoardGenerator.randomized(seed: UInt64.random(in: .min ... .max), shape: shape)
            : BoardGenerator.standard(shape)
        return GameSetup.newGame(board: board,
                                 seed: UInt64.random(in: .min ... .max),
                                 playerCount: playerCount,
                                 victoryPointTarget: setup.victoryPointTarget,
                                 mode: setup.mode)
    }
```

- [ ] **Step 4: Make the three agreement checks include the mode**

`MatchCheckpointMigration.prepare` (line 37):

```swift
        guard setup.isValidMatch, setup.seats.count == session.state.players.count,
              setup.mode == session.state.mode,
              setup.victoryPointTarget == session.state.victoryPointTarget else {
            throw MigrationError.incompatibleRoster
        }
```

`MatchCheckpointStore` line 37 (equality) and lines 208-209 (validation) — add `mode` beside each `victoryPointTarget` comparison, using the identical shape the existing line uses.

`GameLogStore`: add `public let mode: GameMode` to `GameLogSummary` beside `victoryPointTarget`, populate it at line 355 from `initialState.mode`, and give `SeatRoster` nothing — the roster describes chairs, not rules, so the mode belongs on the summary. Where `GameLogSummary` is decoded from an archived file, decode `mode` with `?? .classic`.

- [ ] **Step 5: Run the app suite**

Run: `xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination 'platform=iOS Simulator,name=Empires QA' -only-testing:SettlersTests`
Expected: PASS. `CheckpointExportTests.retryReplacesATruncatedArchiveWithoutDuplicatingMoves` is a known unexplained flake — if only that fails, re-run it in isolation before believing it, and say so in the report rather than treating it as caused by this change.

- [ ] **Step 6: Commit**

```bash
git add Settlers/ViewModels/GameViewModel.swift Settlers/Persistence/ SettlersTests/
git commit -m "feat(app): carry the game mode through save, resume, replay and export

The mode joins the victory-point target in all three places a checkpoint's
setup is checked against its session state, and the game log's summary records
it. Without this a resumed or replayed Expanded game decodes as classic and
keeps its 37-tile board while playing classic's quantities - a silent mid-game
divergence between the rules and the board they are played on.

makeInitialState now builds the board from the mode's shape, so choosing
Expanded on the New Game screen actually deals 37 tiles.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TBxaHYvMxcRujKxfhdFdAe"
```

---

## Task 12: The mode picker on the New Game screen

**Files:**
- Create: `Settlers/Views/GameModePickerPopup.swift`
- Modify: `Settlers/Views/NewGameSetupView.swift:460-495,549-568`
- Modify: `Settlers/Theme/AccessibilityID.swift`
- Test: `SettlersTests/NewGameSetupTests.swift`; create `SettlersUITests/NewGameModeFlowTests.swift`

**Interfaces:**
- Consumes: `MatchSetup.mode`, `MatchSetup.newGameVictoryPointTargets(for:mode:)` (Task 10), `GameMode.displayName`, `GameMode.summary` (Task 5).
- Produces: `GameModePickerPopup(selection:onSelect:onCancel:)`, `AccessibilityID.NewGame.modeRow` / `.modePicker` / `.modeOption(GameMode)`.

- [ ] **Step 1: Read the pattern before writing**

Run: `cat Settlers/Views/SeatNumberPickerPopup.swift`
Run: `grep -rn "struct PopupCard" -A 20 Settlers/Views/`
Run: `grep -n "enum NewGame" -A 20 Settlers/Theme/AccessibilityID.swift`

`SeatNumberPickerPopup` is the smaller of the two existing popups and the closer model. Match its chrome, dismissal and identifier conventions exactly — this screen's whole design rationale is that its surfaces read as one family.

- [ ] **Step 2: Write the failing test**

In `NewGameSetupTests.swift`:

```swift
@Test func switchingToExpandedSnapsTheTargetToTwentyFive() {
    var setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
    setup.mode = .classic
    setup.victoryPointTarget = 8
    setup.mode = .expanded
    setup.normalizeNewGameOptions()
    #expect(setup.victoryPointTarget == 25)
    #expect(setup.validationProblem == nil)
}

@Test func switchingBackToClassicRestoresAnOfferedTarget() {
    var setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: Civilization.allCases[0])
    setup.mode = .expanded
    setup.victoryPointTarget = 25
    setup.mode = .classic
    setup.normalizeNewGameOptions()
    #expect(MatchSetup.newGameVictoryPointTargets(for: setup.seats.count, mode: .classic)
        .contains(setup.victoryPointTarget))
}
```

`normalizeNewGameOptions()` is the existing normalizer (`MatchSetup.swift:240`). It is `internal`, so the test reaches it through `@testable import Settlers`, which this file already does.

- [ ] **Step 3: Run to verify it fails**

Run: `xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination 'platform=iOS Simulator,name=Empires QA' -only-testing:SettlersTests/NewGameSetupTests`
Expected: FAIL — the target stays 8 after switching to Expanded.

- [ ] **Step 4: Make the normalizer snap the target to the mode**

At `MatchSetup.swift:241`, replace the existing target reset:

```swift
        let offered = Self.newGameVictoryPointTargets(for: seats.count, mode: mode)
        if !offered.contains(victoryPointTarget) {
            // Snap rather than refuse. Changing mode is not an error, and a
            // Start button that greys out because a setting the player cannot
            // see is now out of range is the failure this screen's validation
            // was written to avoid.
            victoryPointTarget = Ruleset.forMode(mode).defaultVictoryPointTarget
        }
```

- [ ] **Step 5: Create the popup**

`Settlers/Views/GameModePickerPopup.swift` — modelled on `SeatNumberPickerPopup`:

```swift
import SwiftUI
import CatanEngine

/// Picks the rule set a new match is played under.
///
/// A popup rather than a `PaintedChoiceRow` of chips: the row is already tight
/// with three chips at 375pt, more modes are planned, and a name alone does
/// not tell a player what "Expanded" changes. The list has room for the
/// one-line summary that does.
struct GameModePickerPopup: View {
    let selection: GameMode
    let onSelect: (GameMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        // `PopupCard` + `GoldRowButton` is the chrome both existing popups
        // use. Do not introduce a second one.
        PopupCard(onDismiss: onCancel) {
            VStack(spacing: 14) {
                Text("Game Mode")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                ForEach(GameMode.allCases, id: \.self) { mode in
                    Button { onSelect(mode) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.displayName)
                                    .font(.system(size: SeatCardView.bodyTextSize, weight: .semibold, design: .serif))
                                Text(mode.summary)
                                    .font(.system(size: SeatCardView.bodyTextSize - 3, design: .serif))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if mode == selection {
                                Image(systemName: "checkmark")
                                    .font(.system(size: SeatCardView.bodyTextSize, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier(AccessibilityID.NewGame.modeOption(mode))
                }
                GoldRowButton(title: "Close", systemImage: "xmark", action: onCancel)
            }
            .padding(16)
            .foregroundStyle(.white)
        }
        .accessibilityIdentifier(AccessibilityID.NewGame.modePicker)
    }
}
```

`PopupCard(onDismiss:)` wrapping a `VStack` that ends in a `GoldRowButton` titled "Close" is what `SeatNumberPickerPopup` and `CivilizationPickerPopup` both do. Match it exactly.

- [ ] **Step 6: Add the row and fix the match-length row**

In `NewGameSetupView.swift`, add `@State private var isPickingMode = false`, put `modeRow` first in `matchSettingsSection`, and present `GameModePickerPopup` in the same `ZStack` the other two popups use (line ~140).

```swift
    private var modeRow: some View {
        labelledChoice(
            label: "Game Mode",
            help: .mode,
            helpText: "Classic is the standard 19-tile board played to 8, 10 or 12 points. "
                + "Expanded doubles the map to 37 tiles and plays to 25, with twice the pieces, "
                + "a bigger bank and deck, and longest road and largest army worth 4 points each.",
            caption: nil
        ) {
            Button { isPickingMode = true } label: {
                HStack(spacing: 6) {
                    Text(setup.mode.displayName)
                    Image(systemName: "chevron.down").font(.system(size: SeatCardView.bodyTextSize - 4))
                }
            }
            .accessibilityIdentifier(AccessibilityID.NewGame.modeRow)
        }
    }
```

Add `case mode` to the `HelpTopic` enum at line 542.

Then make `matchLengthRow` mode-aware. `MatchLength` is a `private enum` of named classic lengths and must not gain a 25 case — Expanded's target is not a named length. Branch instead:

```swift
    private var matchLengthRow: some View {
        labelledChoice(
            label: "Match Length",
            help: .matchLength,
            helpText: "The game ends when a player reaches this many victory points. "
                + "A saved game resumes at the target it started with. "
                + "Epic (12 VP) is available at three-player tables. "
                + "Expanded is always played to 25.",
            caption: nil
        ) {
            let offered = MatchSetup.newGameVictoryPointTargets(for: setup.seats.count, mode: setup.mode)
            if offered.count == 1 {
                // Expanded's target is part of the rule set, not a dial. A
                // one-chip picker would look tappable and do nothing.
                Text("\(offered[0]) VP")
                    .font(.system(size: SeatCardView.bodyTextSize, design: .serif))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(AccessibilityID.NewGame.fixedMatchLength)
            } else {
                PaintedChoiceRow(
                    options: MatchLength.allCases.filter { offered.contains($0.rawValue) },
                    title: \.displayName,
                    selection: MatchLength(rawValue: setup.victoryPointTarget) ?? .standard,
                    isCompact: true,
                    fontSize: SeatCardView.bodyTextSize,
                    onSelect: { setup.victoryPointTarget = $0.rawValue }
                )
            }
        }
    }
```

Add the four identifiers to `AccessibilityID.NewGame`. **These exact strings are what the UI test in Step 8 matches on** — the UI test target cannot import `Settlers`, so the two are kept in step by hand:

```swift
        static let modeRow = "new-game.mode"
        static let modePicker = "new-game.mode.picker"
        static let fixedMatchLength = "new-game.match-length.fixed"
        static func modeOption(_ mode: GameMode) -> String { "new-game.mode.\(mode.rawValue)" }
```

- [ ] **Step 7: Regenerate the project — a new file will not compile without it**

Run: `xcodegen generate`

Skipping this produces `cannot find 'GameModePickerPopup' in scope`, which names the symbol and not the missing file, and sends people hunting an import bug that does not exist.

- [ ] **Step 8: Write the UI test**

Create `SettlersUITests/NewGameModeFlowTests.swift`. **UI tests here are XCTest, not Swift Testing, and they cannot import `Settlers`** — identifiers are raw string literals, matching `NewGameKeyboardInvarianceTests.swift`. Keep the strings in step with the `AccessibilityID` values added in Step 6.

```swift
import XCTest

/// The mode picker is the only control on this screen that changes another
/// control's shape, so it gets a flow test: choosing Expanded must replace the
/// match-length chips with a fixed 25 VP, and Start must stay enabled.
@MainActor
final class NewGameModeFlowTests: XCTestCase {
    func testPickingExpandedShowsAFixedTwentyFivePointTarget() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaShowNewGame"]
        app.launch()

        let modeRow = app.buttons["new-game.mode"]
        XCTAssertTrue(modeRow.waitForExistence(timeout: 10))
        modeRow.tap()

        let expanded = app.buttons["new-game.mode.expanded"]
        XCTAssertTrue(expanded.waitForExistence(timeout: 5), "The mode picker never appeared")
        expanded.tap()

        let fixed = app.staticTexts["new-game.match-length.fixed"]
        XCTAssertTrue(fixed.waitForExistence(timeout: 5),
                      "Expanded did not replace the match-length chips with a fixed target")
        XCTAssertEqual(fixed.label, "25 VP")
        XCTAssertTrue(app.buttons["new-game.start"].isEnabled,
                      "Switching mode left Start disabled: the target did not snap into range")
    }
}
```

**Do not add `.accessibilityElement(children: .contain)` plus an identifier to any container** to make this resolve. Doing that to `GameView.bottomPanel` once made the row an accessibility ancestor of the board decision dock and broke eleven unrelated tests, each reporting nothing but a bare `XCTAssertTrue failed`.

- [ ] **Step 9: Run the tests**

Run: `xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination 'platform=iOS Simulator,name=Empires QA' -only-testing:SettlersTests -only-testing:SettlersUITests`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add Settlers/Views/GameModePickerPopup.swift Settlers/Views/NewGameSetupView.swift \
        Settlers/Theme/AccessibilityID.swift Settlers.xcodeproj/project.pbxproj \
        SettlersTests/ SettlersUITests/
git commit -m "feat(app): pick the game mode on the New Game screen

A popup rather than a chip row: PaintedChoiceRow is already tight with three
chips at 375pt, more modes are planned, and a name alone does not tell a
player what Expanded changes - the list has room for the line that does. It
follows SeatNumberPickerPopup so the screen's surfaces stay one family.

The Match Length row shows Expanded's 25 as a statement rather than a
one-option picker, because there the target is part of the rule set and a
single chip would look tappable and do nothing. Switching mode snaps an
out-of-range target rather than greying out Start over a setting the player
cannot see.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TBxaHYvMxcRujKxfhdFdAe"
```

---

## Task 13: The UI stops printing "+2"

**Files:**
- Modify: `Settlers/Models/VictoryPointBreakdown.swift:52-56`
- Modify: `Settlers/Views/EndGameView.swift`, `Settlers/Views/PlayerHUDView.swift`
- Test: `SettlersTests/VictoryPointBreakdownTests.swift`

**Interfaces:**
- Consumes: `GameState.rules` (Task 6).
- Produces: no new API. `VictoryPointBreakdown.bonusPoints` stops being a constant.

- [ ] **Step 1: Write the failing test**

```swift
@Test func anExpandedBreakdownScoresBonusesAtFourAndStillSumsToTheEngineTotal() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(BoardShape.expanded),
                                  seed: 5, mode: .expanded)
    let seat = state.players[0].id
    state.longestRoadPlayer = seat
    state.largestArmyPlayer = seat
    let breakdown = VictoryPointBreakdown(seat: seat, state: state)
    #expect(breakdown.lines.first { $0.source == .longestRoad }?.points == 4)
    #expect(breakdown.lines.first { $0.source == .largestArmy }?.points == 4)
    // The invariant this type exists to hold.
    #expect(breakdown.lines.reduce(0) { $0 + $1.points } == breakdown.total)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination 'platform=iOS Simulator,name=Empires QA' -only-testing:SettlersTests/VictoryPointBreakdownTests`
Expected: FAIL — lines score 2 each and sum to 4 below `total`.

This is the failure the file's own doc comment predicts: "a rules change that adds a new source of points fails a test here rather than silently showing 10 VP over lines that add to eight."

- [ ] **Step 3: Read the bonus values from the state**

In `VictoryPointBreakdown.swift`, delete `private static let bonusPoints = 2` and, in `init(seat:state:)`, score the two bonus lines with `state.rules.longestRoadBonus` and `state.rules.largestArmyBonus` respectively. The settlement, city and victory-card values stay constants — those are not `Ruleset` fields and no mode varies them.

- [ ] **Step 4: Find and fix every other hard-coded bonus in the UI**

```bash
grep -rn '"+2"\|+ 2 VP\|bonusPoints\|longestRoadPlayer\|largestArmyPlayer' --include="*.swift" Settlers/Views/
```

Replace any literal 2 that means "the bonus is worth two" with the ruleset read. Leave alone any 2 that means a city is worth two points.

- [ ] **Step 5: Run the tests**

Run: `xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination 'platform=iOS Simulator,name=Empires QA' -only-testing:SettlersTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Settlers/Models/VictoryPointBreakdown.swift Settlers/Views/ SettlersTests/
git commit -m "fix(app): score bonus lines from the ruleset instead of a literal 2

The victory-point breakdown promised its lines add up to the engine's total
and asserted it across a replayed game. Under Expanded's 4-point bonuses the
literal made them add up to four short, which is exactly the drift the type's
doc comment warns a second victory-point formula in a view produces.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TBxaHYvMxcRujKxfhdFdAe"
```

---

## Task 14: Verification

No production code. This task produces evidence, and its deliverable is a report with numbers in it.

**Files:** none modified except a possible follow-up fix, which gets its own commit.

- [ ] **Step 1: Regenerate and run the full gate**

Run: `xcodegen generate`
Run: `scripts/gate.sh`

All 10 gates must pass. A gate that cannot run prints `SKIP`, and a `SKIP` is not verification — install the missing tool rather than reporting it. Expect 12–20 minutes; CatanAI and the native UI tests dominate.

If `CheckpointExportTests.retryReplacesATruncatedArchiveWithoutDuplicatingMoves` fails, re-run it serially before believing it — it is a known unexplained flake, documented in `CLAUDE.md`. Report it as such rather than as a regression, and do not "fix" it by changing this feature.

- [ ] **Step 2: Measure how long an Expanded game actually runs**

**REQUIRED SUB-SKILL:** invoke the `sim-harness` skill.

Play at least 20 headless seeded Expanded games and 20 Classic games as a baseline. Report:
- median and max turns to a win, both modes
- how many Expanded games failed to finish inside the move cap
- median final score spread

This is Accepted Risk 1 in the spec. **Report the number; do not adjust the target to make it look better.** If Expanded runs past roughly 3x Classic, stop and give Jake the figure — the target, the two bonus values and the piece counts are all `Ruleset` fields, and which dial to turn is his call, not this plan's.

- [ ] **Step 3: Look at the board**

**REQUIRED SUB-SKILL:** invoke the `run-settlers` skill to build, install fresh and launch on the simulator.

Start an Expanded game through the UI — the mode popup, then Start — and capture the board at its resting fit.

Confirm by **looking at the screenshot**, not by the build succeeding:
- 37 tiles are drawn and the whole board is inside the viewport
- number tokens are legible at the resting fit
- all 14 port badges are on-screen and not clipped
- settlements and roads are placeable and drawn inside the board's bounds

This is Accepted Risk 2. If the tokens are not legible, say so and stop — a legibility pass is a real design change, not a tweak to slip into this branch.

- [ ] **Step 4: Play it**

**REQUIRED SUB-SKILL:** invoke the `play-settlers` skill.

Play through the setup placements and several full turns of an Expanded game by tapping. A green build is a compile claim and a correct-looking screenshot survives a game that cannot be played. Confirm a settlement can be placed, a turn ends, the bots take theirs, and the HUD shows the target as 25.

- [ ] **Step 5: Write the summary**

Write `docs/AI_summaries/2026-09-10-expanded-game-mode.md` with: what shipped, the measured game-length numbers from Step 2, the screenshot path from Step 3, what was verified by hand in Step 4, and anything left open. Create the directory if it does not exist.

- [ ] **Step 6: Commit and open the PR**

```bash
git add docs/AI_summaries/2026-09-10-expanded-game-mode.md
git commit -m "docs(ai): summarize the Expanded game mode work

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TBxaHYvMxcRujKxfhdFdAe"
git push -u origin feat/expanded-game-mode
gh pr create --base main --title "feat: add the Expanded game mode" --body "..."
```

The PR body states the measured game length, links the screenshot, and names the three accepted risks. PR into `main`; **never push to `main` directly.**