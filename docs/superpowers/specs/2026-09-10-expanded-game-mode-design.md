# Expanded Game Mode — Design

**Date:** 2026-09-10
**Status:** Revised 2026-09-10 after Jake widened the goal to many future modes, massive maps and 100–1000 point targets. Supersedes the first draft; measured evidence added.
**Branch:** `feat/expanded-game-mode`

## Goal

Add a second playable rule set, **Expanded**: a 37-tile map played to 25 victory
points, with longest road and largest army worth 4 points each and every
quantity in the game — pieces, bank, development deck — scaled to match. The
player picks it on the New Game screen alongside **Classic**.

The larger half of the goal is structural. Jake intends **many** further modes —
new quantities, new board sizes up to hundreds or a thousand tiles, targets of
100–1000 points, and new rule behaviours (a sixth resource, a development-card
bank trade-in, a road remover, a "double city" worth 4) — so the deliverable is
not "one variant" but **a place variants live**, sized for that ambition.

Two things are settled and simplify the design considerably:

- **The win condition is always a victory-point threshold.** No pluggable win
  conditions; `WinCondition` stays a threshold test and only the number moves.
- **The board is always a hex disc.** No arbitrary topologies; `BoardShape`
  stays radius-based.

What is NOT settled — new move shapes — is handled by making `Ruleset` cheap to
extend rather than by building a plugin system for capabilities that do not yet
exist. See *Where the boundary is*.

## Non-Goals

- **No change to the supported table size.** `GameSetup.supportedPlayerCounts`
  stays `3...4`. A doubled map is the natural home for 5–6 seats, but that
  needs new civilizations, a re-laid seat grid, a bot HUD row for five bots,
  the special build phase, and a rework of every layout invariance test. It is
  its own project and should follow this one.
- **No change to the setup phase.** Expanded keeps two settlements per player.
  This was chosen deliberately over a third snake round (see *Accepted risks*).
- **No new move shapes.** `Ruleset` covers quantities and board shape. A future
  mode that adds a development card, a build action or a trade type is a change
  to `GameMove` and `RulesEngine`, not a field on `Ruleset`. Stating that
  boundary is part of the design.
- **No extension of the training encodings.** `StateEncoding` and `ActionSpace`
  stay Classic-only and refuse anything else (see *AI layer*).

## Rule set

| | Classic | Expanded |
|---|---|---|
| victory-point target | 8 / 10 / 12 | **25** (fixed) |
| longest road bonus | 2 | **4** |
| largest army bonus | 2 | **4** |
| longest road minimum | 5 | 5 *(unchanged)* |
| largest army minimum | 3 | 3 *(unchanged)* |
| roads per player | 15 | **30** |
| settlements per player | 5 | **10** |
| cities per player | 4 | **8** |
| discard threshold on a 7 | > 7 cards | **> 10 cards** |
| bank per resource | 19 | **38** |
| development deck | 25 | **50** |
| seats | 3–4 | 3–4 *(unchanged)* |

### Why the piece counts double

25 points is not reachable by building under Classic's piece limits. Five
settlements and four cities cap buildings at 13 VP; with a doubled deck's ten
victory-point cards and both 4-point bonuses the theoretical maximum is 31, so
a win would require hoarding nearly every VP card drawn. The game would stop
being about the board.

Doubling the pieces caps buildings at 26 VP (10 settlements + 8 cities = 10 +
16), so a 25-point game is winnable through the board alone and development
cards return to being a supplement. A typical Classic winner takes about 7 of
their 10 points from buildings; the Expanded equivalent is about 18 of 25, and
both sit comfortably under their cap.

```
                 Classic   Expanded
building VP max     13        26
+ VP cards           5        10
+ longest road       2         4
+ largest army       2         4
================================
theoretical max     22        44
target              10        25
```

### Development deck (50 cards, exactly 2x Classic)

28 knight · 10 victory point · 4 road building · 4 year of plenty · 4 monopoly.

### Discard threshold

Expanded roughly doubles income, so Classic's 7-card limit would trigger for
most players on most sevens — stalling the game and punishing precisely the
large-engine play a 25-point target asks for. 10 scales with the economy while
keeping the robber a real mid-game threat.

## Board

**Radius 3, 37 tiles.** `BoardGenerator.spiralCoordinates(radius:)` already
generalizes, so the coordinate walk is free.

| | Classic | Expanded |
|---|---|---|
| tiles | 19 | 37 |
| desert | 1 | 1 |
| grain / wool / lumber | 4 / 4 / 4 | 8 / 8 / 8 |
| brick / ore | 3 / 3 | 6 / 6 |
| number tokens | 18 | 36 |
| vertices | 54 | 96 |
| edges | 72 | 132 |
| coastal edges | 30 | 42 |
| ports | 9 (4 generic, 5 resource) | 14 (4 generic, 2 per resource) |

**37 rather than a literal 38.** One desert plus 36 resource tiles is exactly
twice Classic's resource mix, and 36 tokens is exactly twice Classic's
multiset — two 2s, four each of 3–6 and 8–11, two 12s. The dice distribution is
preserved to the card, so a player's probability intuition transfers between
modes instead of quietly shifting. A 38th tile breaks both properties and buys
nothing.

**14 ports preserves density, not composition ratio.** Classic puts ports on 9
of 30 coastal edges (30%). Doubling to 18 would cover 43% of a 42-edge
shoreline and make harbours cheap. 14 holds the density at 33%, and two 2:1
ports per resource is symmetric — which matters more on a map where an entire
corner can be out of a player's reach.

**Both Standard and Randomized layouts are supported.** Port positions must be
authored as fixed vertex pairs either way — that is how Classic's randomizer
works, ports staying put while terrain and tokens shuffle — so a pinned fixed
layout is nearly free once the port authoring is done.

### The randomizer needs a repair pass, not just rejection sampling

`BoardGenerator.randomized(seed:)` reshuffles in an unbounded `repeat` until no
6 or 8 touches another 6 or 8. That terminates quickly with 4 hot tiles among
19. Expanded has 8 among 36 on a graph with far more adjacencies, and the
probability of a clean shuffle falls off sharply — an unbounded loop risks
spinning.

Expanded bounds the retries and then **deterministically repairs** the layout by
swapping offending tokens with non-hot ones. The repair draws from `state.rng`
and enumerates in sorted order, so it stays reproducible across processes.

## Scale: what was measured, and the one thing that does not scale

Measured 2026-09-10 on this machine, before any design was committed to. Guesses
about performance were wrong in both directions, so the numbers are recorded
here rather than the intuitions.

### Board size is not a problem

| radius | tiles | vertices | edges | board generation | `legalMoves` | legal moves |
|---|---|---|---|---|---|---|
| 2 | 19 | 54 | 72 | 0.7ms | 1.9ms | 210 |
| 3 | 37 | 96 | 132 | 1.2ms | 2.2ms | 228 |
| 5 | 91 | 216 | 306 | 2.7ms | 4.2ms | 282 |
| 8 | 217 | 486 | 702 | 6.6ms | 9.1ms | 408 |
| 12 | 469 | 1,014 | 1,482 | 13.6ms | 18.8ms | 660 |
| 18 | 1,027 | 2,166 | 3,192 | 30.2ms | 41.5ms | 1,218 |

Both scale **linearly**. A thousand-tile board is not an engine problem. (It is
still a *rendering* problem — see *Accepted risks*.)

### `LongestRoad` is exponential, and it is the real ceiling

`LongestRoad.longestPath` runs an exhaustive depth-first search from every
vertex, with no pruning, no memoization and no decomposition. Cost against road
count, same machine:

| roads | realistic (path-like network) | worst case (dense clump) |
|---|---|---|
| 15 — *Classic's cap* | 0.6ms | 3.3ms |
| 20 | 0.9ms | 10.2ms |
| 25 | 1.4ms | 27.8ms |
| 30 — *Expanded's cap* | 2.3ms | 157ms |
| 35 | — | 309ms |
| 40 | 4.2ms | 776ms |
| 60 | 9.0ms | — |

Roughly doubling every five roads on the dense curve; one nastier topology at
~24–30 roads ran **over 100 seconds** before it was killed.

**Classic's 15-road limit is the only reason this has never surfaced.** Expanded
at 30 roads is playable (2.3ms realistic, 157ms pathological), but a 100+ road
mode — which a 1000-point target implies — would freeze for minutes on every
road placement.

Jake's call (2026-09-10): **fix it before building Expanded**, so the large
modes are unblocked from the start.

### The replacement

Longest simple path is NP-hard in general, so the fix is not a clever formula —
it is removing the work that never needed doing. Four steps, all exact:

1. **Split the network at opponent-blocked vertices.** A road may end at an
   opponent's building but not continue through it, so splitting there is
   exactly equivalent to today's rule and breaks one tangled graph into several
   small ones.
2. **Decompose into connected components.** Separate clusters cannot form one
   path; the answer is the maximum over components.
3. **A component with no cycle is a tree, which is the common case.** Its
   longest path is its diameter — two linear passes, no search at all.
4. **Only a component containing a cycle searches**, and then with a
   branch-and-bound cut: abandon any branch whose length plus all remaining
   unvisited edges in the component cannot beat the best answer so far.

**The result must be identical to today's, not merely close.** This function
decides games and every seeded fingerprint in the repo depends on its answers.
So the current implementation is kept in the test target as a **reference
oracle**, and the replacement is proven equal to it across thousands of randomly
generated networks — trees, cycles, disconnected clusters, and blocked vertices
— before it is trusted. Any fingerprint change is then evidence of a bug, not an
expected re-pinning.

### The tripwire

`Ruleset` validation refuses a mode whose road limit exceeds what the algorithm
can serve, with a message naming the measured limit. A future mode gets a build
-time error rather than a frozen game.

## Architecture

### `GameMode` is a tag; `Ruleset` is the data

One new `Codable` enum field on `GameState`, defaulting to `.classic`. Each mode
maps to a `Ruleset` — a flat value type holding every quantity the rules
currently hard-code:

```swift
struct Ruleset {
    let board: BoardShape
    /// Targets a game in this mode may be started at.
    let victoryPointTargets: ClosedRange<Int>
    let defaultVictoryPointTarget: Int
    let longestRoadBonus: Int
    let largestArmyBonus: Int
    let longestRoadMinimum: Int
    let largestArmyMinimum: Int
    /// Per building KIND, not per named field. Adding `.doubleCity` later is
    /// two dictionary entries; three flat fields would be an edit to every
    /// rule site that reads a limit.
    let pieceLimits: PieceAllowance          // [BuildingKind: Int] or .scaledFromBoard
    let victoryPointsPerBuilding: [BuildingKind: Int]
    let maxRoadsPerPlayer: Int
    let bankPerResource: BankAllowance       // explicit or .scaledFromBoard
    let devCardDeck: [DevCardType: Int]
    /// A player holding MORE than this many resource cards discards on a 7.
    let discardThreshold: Int
}
```

Three properties make this survive modes four and five:

1. **Every existing literal moves into `Ruleset`, not only the ones Expanded
   changes.** `Building.maxRoadsPerPlayer`, the `19` bank loop in
   `GameSetup.newGame`, the deck composition beside it, `LongestRoad.minimumLength`,
   the `> 7` in `Robber.playersMustDiscard`, and both `2`s in
   `GameState.publicVictoryPoints` / `victoryPoints`. A future mode that changes
   only the deck then costs one line. This is most of the work in this project
   and nearly all of its long-term value.
2. **Adding a mode is one enum case plus one `Ruleset` literal.** The switch
   producing rule sets is exhaustive, so the compiler names any omission.
   Nothing in `RulesEngine`, `Building`, `WinCondition` or `DevCards` is touched
   again.
3. **A mode needing an axis `Ruleset` lacks** adds a field with a Classic-valued
   default; every other mode keeps compiling. That is why `Ruleset` is a plain
   struct rather than a protocol with per-mode conformances.

### Four seams built now, against named future features

These are not speculation — each is a shape Jake has named, and each is cheap
today and a cross-cutting refactor later. Nothing below *adds* a feature; they
only stop the feature from being a rewrite.

| Seam | Serves | Why now |
|---|---|---|
| **Per-kind piece limits and points** (`[BuildingKind: Int]` rather than `maxSettlements` / `maxCities` / a `settlementPoints` constant) | the "double city worth 4" | Adding a third building tier becomes two dictionary entries. As flat fields it is an edit to every limit check and both victory-point formulas. |
| **Board declared as composition, not per-tile arrays** | maps of hundreds or a thousand tiles | A literal entry per tile is unwritable past ~50 tiles. The first draft of this spec already had to *generate* its 37-entry array with a stride trick rather than write it — the design saying it was wrong. |
| **Piece counts and bank derivable from board size** | any new map size | `.scaledFromBoard` or an explicit override, so a new radius does not need hand-computed supplies. Every mode may still state its numbers outright. |
| **No hardcoded resource count** | a sixth resource | Most of the engine already drives off `Resource.allCases`. This audits for literal `5`s and hardcoded resource lists and fixes what it finds. It does not add a resource. |

**`BoardShape` becomes a composition:**

```swift
struct BoardShape: Equatable, Sendable {
    let radius: Int
    /// Tile counts by terrain, summing to the radius's tile count. Expanded
    /// into a spiral layout deterministically; no per-tile literal.
    let terrain: TerrainComposition
    /// The token multiset, declared as counts per pip value.
    let tokens: TokenComposition
    /// Port kinds, placed by walking the coastline at an even stride.
    let ports: PortLayout
}
```

`PortLayout` keeps a `.fixed([Port])` case, and `TerrainComposition` /
`TokenComposition` each keep a literal-order case, **used only by Classic**,
whose arrangement is the authentic physical board and is not derivable from any
rule.

### Why a tag and not stored values

`GameState.victoryPointTarget` is already a stored per-game value, and its doc
comment explains why: a global would make `checkForWinner` depend on process
state rather than on the position, and a resumed 12-point game would silently
revert to ten. That reasoning rules out a static or global mode outright — it
would break replay and resume, the same defect class as the four `Set`-ordering
bugs this repo has already paid for.

Storing each rule *value* on `GameState` instead would honour that precedent but
admits incoherent saves: 25 points carrying Classic's 5-settlement limit. Each
field would also need its own `decodeIfPresent` default and its own
`SaveCompatibilityTests` case. One tag makes the illegal combination
unrepresentable and needs one decode default.

`victoryPointTarget` remains a stored field, because Classic genuinely dials it.
The mode supplies its *permitted range*; Expanded's range is the single value 25.

## Persistence

- **`GameState.mode`** decodes `?? .classic`, so every existing save loads
  untouched and keeps playing the rules it started under. `schemaVersion` → 4.
  A new `SaveCompatibilityTests` case pins a v3 save decoding as Classic.
- **`GameState.init(from:)` decodes `mode` before it validates
  `victoryPointTarget`.** That guard currently rejects anything outside
  `WinCondition.supportedTargets` (8...12) and must become
  `ruleset(for: mode).victoryPointTargets`. Decode order is load-bearing here:
  validating the target against a mode not yet read would reject every Expanded
  save as corrupt. The guard itself stays — it exists because a corrupt `0`
  would otherwise make the next build declare seat 0 the winner.
- **`MatchSetup.mode`**, beside its existing `victoryPointTarget`.
  `MatchSetup.validate` and `newGameVictoryPointTargets(for:)` become
  mode-aware: the permitted targets come from the mode's `Ruleset`.
- **`GameLogStore.SeatRoster`** and **`MatchCheckpointMigration`** already carry
  `victoryPointTarget` and must carry `mode` beside it. Without this a resumed
  or replayed Expanded game decodes as Classic and the board stops matching the
  rules that govern it — a silent, mid-game divergence.
- **`MatchCheckpointStore`** compares setup against session state in two places;
  both comparisons gain `mode`.

## AI layer

`StateEncoding` and `ActionSpace` are fixed-width against 19 tiles / 54 vertices
/ 72 edges, and both already trap on a board of another size. Expanded does not
extend them; it gives them a **named refusal keyed on mode**.

This is deliberate. `StateEncoding`'s own doc comment describes the dangerous
failure as the silent one — a padded or truncated vector runs without error and
merely plays badly, and "the bots got worse" is among the most expensive things
to diagnose in this repo. A loud, named refusal is the correct behaviour for a
board the layout was never defined against.

The three heuristic bots need no change: `CatanAI` carries no board-size or
victory-target literals (verified 2026-09-10 — only `TrainingExample` passes the
target through, as data). Bots will play Expanded through the same legal-move
API.

## UI

- **A Game Mode selector** on the New Game screen's Match Settings section,
  built as a **popup** rather than a `PaintedChoiceRow` of chips.
  `CivilizationPickerPopup` and `SeatNumberPickerPopup` are the existing pattern
  for exactly this. `PaintedChoiceRow` is already tight with three chips at
  375pt; with further modes planned, a chip row would need replacing at mode
  four. The row shows the current mode's name; the popup lists each mode with a
  one-line description.
- **The Match Length row** shows Classic's 8/10/12 chips as today, and a fixed
  "25 VP" statement in Expanded, because there the target is part of the rule
  set rather than a dial.
- **Board and Turn Order** rows work unchanged in both modes.
- **`EndGameView`, `PlayerHUDView` and `VictoryPointBreakdown`** read bonus
  values from the rule set instead of printing "+2".

`BoardView.contentBounds(for:geometry:)` derives the fit from the board, so the
viewport adapts to 37 tiles with no change (verified 2026-09-10). See
*Accepted risks* for what that does not guarantee.

## Determinism

The invariants in `CLAUDE.md` apply unchanged, and two are specifically at risk:

- The token-repair pass draws from `state.rng` and enumerates in sorted order.
  No `Int.random`, `.randomElement()`, `.shuffled()` or bare
  `SystemRandomNumberGenerator` enters `BoardGenerator`.
- **`SeededGameFingerprintTests` gains Expanded cases.** It pins exact move
  sequences and gets a fresh hash seed per process, which is what makes it fail
  rather than flake on an ordering regression.

## Testing

- `CatanEngine`: `Ruleset` values reach every rule site; Expanded piece caps
  enforced; 25-point win detection; 4-point bonuses in both VP formulas;
  10-card discard threshold.
- `BoardGenerator`: 37 tiles, exact resource mix and token multiset, 14 ports on
  distinct coastal edges, no adjacent 6/8 after repair, and identical boards
  from identical seeds.
- `SaveCompatibilityTests`: a v3 save decodes as Classic; an Expanded save round
  -trips.
- `SeededGameFingerprintTests`: Expanded seeds pinned.
- App tests: mode popup selection persists into `MatchSetup`; Match Length row
  shows 25 VP in Expanded; a resumed Expanded checkpoint stays Expanded.
- **Headless measurement** via the `sim-harness` skill: actual Expanded game
  length in turns, reported as a number.
- **An inspected screenshot** of a 37-tile board at the resting fit on the
  simulator, per the repo rule that a green build is a compile claim and not a
  runtime one.

## Accepted risks

1. **Game length — MEASURED 2026-09-11, and the estimate was wrong in the safe
   direction.** Two setup settlements to a 25-point target is a long ramp, and a
   third snake round was declined in favour of leaving `SetupPhase` and every
   setup fixture, QA flag and UI test untouched. The estimate below was that
   Expanded would run *well over twice* a Classic game, possibly 3x. It does not.

   | method | Classic | Expanded | ratio |
   |---|---|---|---|
   | random play, 10 seeded games/mode | median 4,835 moves (1,850–13,459) | median 9,128 (4,806–11,866) | **1.89x** |
   | bot self-play, 8 seeded games/mode | median 490 moves (358–702) | median 903 (653–1,049) | **1.84x** |

   Two unrelated methods agree: **Expanded costs 2.5x the victory points but only
   ~1.85x the game length.** The doubled map and doubled piece supplies raise
   income enough to outpace the higher target.

   A second finding nobody predicted: **Expanded is *more consistent* than
   Classic**, with a lower maximum (11,866 vs 13,459 under random play) and a far
   higher minimum. More land means fewer boxed-in games that grind.

   Task 14's `sim-harness` run remains the authoritative paired figure. If it
   ever disagreed with both of these, the target and the two bonus values are the
   dials, and all three are `Ruleset` fields.
2. **Legibility at the resting fit.** 37 tiles in the same viewport means
   roughly 40%-smaller hexes. Number tokens and pieces may not survive it. Pan
   and zoom already exist, but this needs the inspected screenshot before any
   claim, and may need a legibility pass or a mode-specific opening zoom.
3. **Bot quality on a bigger map.** The heuristics are tuned against 19 tiles
   and a 10-point target. They will play Expanded legally; whether they play it
   *well* is unknown. Measuring that is the `bot-strength` skill's job and is
   out of scope here — but it should not be claimed either way without it.
