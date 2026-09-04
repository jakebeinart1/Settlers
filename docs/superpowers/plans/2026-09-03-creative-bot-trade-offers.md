# Creative Bot Trade Offers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let bots retry a declined trade proposal with a genuinely different
offer (up to 3 attempts/turn) and, for their single best-blocked build
(settlement or city), propose a trade worse than their own bank/port rate
when it unlocks that build — without breaking determinism, the fixed-size
`ActionSpace` encoding, or checkpoint/save compatibility.

**Architecture:** Add one new `GameState` field
(`declinedTradeOffersThisTurn`) that records, per player, every offer of
theirs declined so far this turn — turn-scoped and reset on `.endTurn`, same
lifecycle as the existing `tradesAcceptedThisTurn`. `TradeHeuristics
.proposeTrades` reads it to (a) stop after `RulesEngine
.maxTradeProposalsPerTurn` attempts and (b) rank give-resource candidates so
a retry is never identical to something already tried. A new, wider
give-quantity ceiling (`RulesEngine.maxGenerousGiveQuantity = 3`, want stays
at the existing `maxEnumeratedTradeQuantity = 2`) lets the generous-unlock
case offer more than today's 2-card max, bounded to strictly better than the
proposer's own best bank/port rate for that resource. `RulesEngine
.tradeProposals` and `ActionSpace`'s `.proposeTrade` segment both widen to
match, or the new offers are either silently dropped (`Bot.swift`'s
`matchLegal` requires containment in `legal`) or crash training/self-play
(`ActionSpace.mask(for:)` traps on an unindexable legal move).
`GameSession`'s session-local `proposedTradeThisTurn` gate is replaced by
reading the new state field directly, which also drops it from
`GameSession.Checkpoint` — one less piece of session-transient bookkeeping to
keep in sync across resume.

**Tech Stack:** Swift 6.3, Swift Testing (`@Test`/`#expect`), SPM (`CatanEngine`,
`CatanAI` packages only — no UIKit/SwiftUI, Linux-testable).

**Spec:** `docs/superpowers/specs/2026-09-03-creative-bot-trade-offers-design.md`

## Global Constraints

- `CatanEngine` and `CatanAI` import only `Foundation` (+ `CatanEngine` from
  `CatanAI`). No UIKit/SwiftUI/Darwin.
- All new randomness (there is none needed here) would go through
  `state.rng`; this feature adds none.
- Any new enumeration must be order-stable: drive off `Resource.allCases`,
  never raw dictionary iteration, and never `Set`/`Dictionary` for anything
  that affects move choice.
- `proposeTrades` must stay a pure function of `GameState` (plus
  `personality`/`weights`) — no new mutable AI-side state.
- Every new `GameState` field must decode with a default
  (`decodeIfPresent`), never throw. Bump `schemaVersion` and add a
  `SaveCompatibilityTests` case.
- `TradeOffer.enumerated` (content-derived id) must be used for every offer
  `TradeHeuristics` composes, exactly matching whatever `RulesEngine
  .tradeProposals` independently enumerates for the same give/want, or
  `Bot.swift`'s `matchLegal` won't find it in `legal` and the move is
  silently dropped.
- `xcodegen generate` is not needed for this plan — no `Settlers/` files are
  touched.
- Run `swift test --package-path Packages/CatanEngine` and
  `swift test --package-path Packages/CatanAI` after each task; both must be
  green before moving on. Use `--package-path`, not `swift test` from repo
  root (no root `Package.swift`).

---

## File Structure

| File | Responsibility |
|---|---|
| `Packages/CatanEngine/Sources/CatanEngine/Models/GameState.swift` | New `declinedTradeOffersThisTurn` field, schema bump |
| `Packages/CatanEngine/Sources/CatanEngine/Trading.swift` | Record a decline into the new field |
| `Packages/CatanEngine/Sources/CatanEngine/RulesEngine.swift` | New quantity/retry-limit constants; widen `tradeProposals`; reset new field on `.endTurn` |
| `Packages/CatanEngine/Sources/CatanEngine/ActionSpace.swift` | Widen `.proposeTrade` segment to the asymmetric give/want ranges |
| `Packages/CatanEngine/Sources/CatanEngine/GameSession.swift` | Replace `proposedTradeThisTurn` gate with a read of the new state field |
| `Packages/CatanAI/Sources/CatanAI/TradeHeuristics.swift` | Retry ranking + generous-unlock override in `proposeTrades` |
| `Packages/CatanEngine/Tests/CatanEngineTests/SaveCompatibilityTests.swift` | New field in the "later additions" list |
| `Packages/CatanEngine/Tests/CatanEngineTests/TradeOfferIDTests.swift` | Extend give-quantity range covered |
| `Packages/CatanEngine/Tests/CatanEngineTests/ActionSpaceTests.swift` | Updated size formula |
| `Packages/CatanEngine/Tests/CatanEngineTests/TradingTests.swift` | New candidates appear in `legalMoves`; decline is recorded; reset on endTurn |
| `Packages/CatanEngine/Tests/CatanEngineTests/GameSessionTests.swift` | Retry reachable through `decideNextDetailed`, capped correctly |
| `Packages/CatanAI/Tests/CatanAITests/TradeHeuristicsTests.swift` | Retry variety, retry cap, generous-unlock scope and bound |
| `docs/AI_summaries/2026-09-03-creative-bot-trade-offers.md` | Summary of what shipped and why (new directory, per `CLAUDE.md`) |

---

### Task 1: `GameState` gains `declinedTradeOffersThisTurn`

**Files:**
- Modify: `Packages/CatanEngine/Sources/CatanEngine/Models/GameState.swift`
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/SaveCompatibilityTests.swift`

**Interfaces:**
- Produces: `GameState.declinedTradeOffersThisTurn: [PlayerID: [TradeOffer]]`
  (public var, default `[:]`), `GameState.currentSchemaVersion == 3`.

- [ ] **Step 1: Write the failing save-compatibility case**

Add `"declinedTradeOffersThisTurn"` to the `laterAdditions` array in
`aSaveMissingFieldsAddedAfterItWasWrittenStillLoads()`:

```swift
let laterAdditions = ["schemaVersion", "rng", "tradesAcceptedThisTurn",
                      "devCardsBoughtThisTurn", "devCardPlayedThisTurn", "log",
                      "declinedTradeOffersThisTurn"]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path Packages/CatanEngine --filter SaveCompatibilityTests`
Expected: FAIL — `GameState` has no such key to omit yet / decode still
succeeds trivially either way at this point, so this step is really a
placeholder check that the harness runs; the meaningful failure comes after
Step 3 if the field is added without a default. Confirm the suite compiles
and the existing cases still pass before proceeding.

- [ ] **Step 3: Add the field**

In `GameState.swift`, immediately below `tradesAcceptedThisTurn`'s
declaration (around line 72-81, matching its doc-comment style):

```swift
/// Every trade offer `PlayerID` has proposed and had declined so far this
/// turn - reset for everyone on `.endTurn`, same lifecycle as
/// `tradesAcceptedThisTurn`. Lets `TradeHeuristics.proposeTrades` retry with
/// a genuinely different offer instead of recomposing the one that was just
/// turned down (which, being a pure function of otherwise-unchanged state,
/// it would otherwise reproduce exactly), and caps how many attempts a
/// player gets per turn without needing separate session-local bookkeeping.
public var declinedTradeOffersThisTurn: [PlayerID: [TradeOffer]]
```

Bump the version comment and constant:

```swift
/// Bumped to 3 when `declinedTradeOffersThisTurn` was added.
public static let currentSchemaVersion = 3
```

Add the initializer parameter (next to `tradesAcceptedThisTurn`'s, in the
memberwise `init`):

```swift
tradesAcceptedThisTurn: [PlayerID: Int] = [:],
declinedTradeOffersThisTurn: [PlayerID: [TradeOffer]] = [:],
```

and the matching `self.` assignment, and in `init(from:)`:

```swift
declinedTradeOffersThisTurn = try container
    .decodeIfPresent([PlayerID: [TradeOffer]].self, forKey: .declinedTradeOffersThisTurn) ?? [:]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/CatanEngine --filter SaveCompatibilityTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/CatanEngine/Sources/CatanEngine/Models/GameState.swift \
        Packages/CatanEngine/Tests/CatanEngineTests/SaveCompatibilityTests.swift
git commit -m "feat(engine): add declinedTradeOffersThisTurn to GameState"
```

---

### Task 2: Record declines; reset on `.endTurn`

**Files:**
- Modify: `Packages/CatanEngine/Sources/CatanEngine/Trading.swift`
- Modify: `Packages/CatanEngine/Sources/CatanEngine/RulesEngine.swift` (the `.endTurn` case, ~line 400)
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/TradingTests.swift` (there is no
  `RulesEngineTests.swift` in this repo — `TradingTests.swift` is the existing home for
  `Trading`/`.endTurn` trade-lifecycle tests; add both new cases there, matching its
  existing style)

**Interfaces:**
- Consumes: `GameState.declinedTradeOffersThisTurn` from Task 1.
- Produces: the field is populated on reject and cleared on `.endTurn` — the
  behavior `TradeHeuristics` and `GameSession` (Tasks 4-5) will read.

- [ ] **Step 1: Write the failing test**

```swift
@Test func decliningATradeRecordsItAgainstTheProposer() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let proposer = state.players[0].id
    let responder = state.players[1].id
    state.players[0].resources = [.lumber: 2]
    let offer = TradeOffer(from: proposer, give: [.lumber: 1], want: [.ore: 1])
    try Trading.proposeTrade(offer, state: &state)

    try Trading.respond(offerID: offer.id, accept: false, by: responder, state: &state)

    #expect(state.declinedTradeOffersThisTurn[proposer] == [offer])
    #expect(state.pendingTradeOffers.isEmpty)
}

@Test func endTurnClearsDeclinedTradeHistory() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let proposer = state.players[0].id
    state.declinedTradeOffersThisTurn[proposer] = [
        TradeOffer(from: proposer, give: [.lumber: 1], want: [.ore: 1])
    ]
    try RulesEngine.apply(.endTurn, by: proposer, to: &state)
    #expect(state.declinedTradeOffersThisTurn.isEmpty)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/CatanEngine --filter TradingTests`
Expected: FAIL — `declinedTradeOffersThisTurn` never gets written to, and
`.endTurn` doesn't clear it either (it stays `[:]` in the first test too, so
that assertion also fails since it expects the offer present).

- [ ] **Step 3: Record the decline in `Trading.respond`**

In `Trading.swift`, `respond(offerID:accept:by:state:)` — add an `else`
branch recording the decline right before the unconditional removal at line
176:

```swift
if accept {
    // ... existing accept branch unchanged ...
    state.tradesAcceptedThisTurn[offer.from, default: 0] += 1
} else {
    state.declinedTradeOffersThisTurn[offer.from, default: []].append(offer)
}

state.pendingTradeOffers.removeAll { $0.id == offerID }
```

- [ ] **Step 4: Reset on `.endTurn` in `RulesEngine.swift`**

Alongside the existing turn-scoped resets (~line 400-403):

```swift
case .endTurn:
    state.devCardsBoughtThisTurn = [:]
    state.devCardPlayedThisTurn = nil
    state.tradesAcceptedThisTurn = [:]
    state.declinedTradeOffersThisTurn = [:]
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --package-path Packages/CatanEngine --filter TradingTests`
Expected: PASS. Also re-run the full `CatanEngine` suite to confirm nothing
else regressed:
Run: `swift test --package-path Packages/CatanEngine`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Packages/CatanEngine/Sources/CatanEngine/Trading.swift \
        Packages/CatanEngine/Sources/CatanEngine/RulesEngine.swift \
        Packages/CatanEngine/Tests/CatanEngineTests/TradingTests.swift
git commit -m "feat(engine): record declined trade offers, reset them on endTurn"
```

---

### Task 3: Widen the give-quantity ceiling for enumeration

**Files:**
- Modify: `Packages/CatanEngine/Sources/CatanEngine/RulesEngine.swift` (constants + `tradeProposals`, ~lines 145-187)
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/TradingTests.swift` (again, no
  `RulesEngineTests.swift` exists — trade-enumeration tests belong in `TradingTests.swift`)
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/TradeOfferIDTests.swift`

**Interfaces:**
- Produces: `RulesEngine.maxGenerousGiveQuantity = 3`,
  `RulesEngine.maxTradeProposalsPerTurn = 3`. `tradeProposals(for:)` now
  enumerates give counts `1...min(maxGenerousGiveQuantity, held - 1)` (want
  side unchanged at `maxEnumeratedTradeQuantity`).
- Consumes nothing new from earlier tasks.

- [ ] **Step 1: Write the failing test**

```swift
@Test func legalMovesIncludeGiveCountsUpToTheGenerousCeiling() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.players[0].resources = [.lumber: 5, .ore: 1]
    state.phase = .mainTurn(playerIndex: 0)
    let legal = RulesEngine.legalMoves(for: state, seat: state.players[0].id)
    let giveThree = legal.contains {
        if case .proposeTrade(let offer) = $0 { return offer.give == [.lumber: 3] }
        return false
    }
    #expect(giveThree)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/CatanEngine --filter TradingTests`
Expected: FAIL — today's ceiling is `maxEnumeratedTradeQuantity` (2), so a
give count of 3 is never enumerated.

- [ ] **Step 3: Add the constants and widen enumeration**

In `RulesEngine.swift`, right after `maxEnumeratedTradeQuantity` (~line 161):

```swift
/// How many of one resource a *generous* proposal (see
/// `TradeHeuristics`'s unlock-override) may offer, wider than
/// `maxEnumeratedTradeQuantity` on the give side only. Fixed at 3 - one more
/// than a bot would ever need to beat its own worst bank rate (4:1, no
/// port), which is the bound that actually matters: a generous offer only
/// exists to be a genuinely better deal than paying the bank, and above
/// that ceiling it never can be. The want side stays at
/// `maxEnumeratedTradeQuantity`; nothing asks for more.
public static let maxGenerousGiveQuantity = 3

/// How many trade offers one player may propose in a single turn before
/// `GameSession` stops offering `.proposeTrade` as a legal move for them.
/// Three, not one: a declined offer should get a genuinely different retry
/// (see `TradeHeuristics.proposeTrades`), not silence for the rest of the
/// turn, but a policy that just keeps trying forever crowds out every other
/// move and never reaches `.endTurn` on its own.
public static let maxTradeProposalsPerTurn = 3
```

Widen the give loop in `tradeProposals(for:)` (~line 177):

```swift
for giveCount in 1...min(maxGenerousGiveQuantity, held - 1) {
```

Update the doc comment above `tradeProposals` (~lines 163-168) to match the
new count:

```swift
/// Bounded at `maxGenerousGiveQuantity` on the give side and
/// `maxEnumeratedTradeQuantity` on the want side, one resource type per
/// side: 5 give types x 4 want types x 3 x 2 = 120 at the absolute most, and
/// far fewer in practice since the proposer must hold what they offer.
```

- [ ] **Step 4: Extend the id-determinism test range**

In `TradeOfferIDTests.swift`, the give-side loop bound changes from
`RulesEngine.maxEnumeratedTradeQuantity` to `RulesEngine.maxGenerousGiveQuantity`
(want stays as-is):

```swift
for giveCount in 1...RulesEngine.maxGenerousGiveQuantity {
    for want in Resource.allCases where want != give {
        for wantCount in 1...RulesEngine.maxEnumeratedTradeQuantity {
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --package-path Packages/CatanEngine --filter TradingTests`
Run: `swift test --package-path Packages/CatanEngine --filter TradeOfferIDTests`
Expected: both PASS

- [ ] **Step 6: Commit**

```bash
git add Packages/CatanEngine/Sources/CatanEngine/RulesEngine.swift \
        Packages/CatanEngine/Tests/CatanEngineTests/TradingTests.swift \
        Packages/CatanEngine/Tests/CatanEngineTests/TradeOfferIDTests.swift
git commit -m "feat(engine): widen enumerated trade give-quantity to 3"
```

---

### Task 4: Widen `ActionSpace`'s `.proposeTrade` segment to match

**Files:**
- Modify: `Packages/CatanEngine/Sources/CatanEngine/ActionSpace.swift`
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/ActionSpaceTests.swift`

**Interfaces:**
- Consumes: `RulesEngine.maxGenerousGiveQuantity`, `RulesEngine
  .maxEnumeratedTradeQuantity` from Task 3.
- Produces: `.proposeTrade` segment size
  `resources * (resources - 1) * maxGenerousGiveQuantity * maxEnumeratedTradeQuantity`;
  `proposeSlot`/`proposal` encode/decode give and want with their own,
  now-different, ranges; `ActionSpace.layoutVersion` bumped from 1 to 2 (it
  exists precisely so a shape change like this one is acknowledged, not
  silently absorbed — see `ActionSpace.swift:68` and
  `ActionSpaceTests.swift:36`'s "if this moved, bump ActionSpace.layoutVersion").

- [ ] **Step 1: Write the failing test**

In `ActionSpaceTests.swift`, the give-side widening (2 → 3) changes the
total space size: today's hardcoded `9_295` (`theSpaceIsTheSizeItClaims`,
~line 36) is `... + resources * (resources - 1) * 2 * 2 + ...`; the propose-
trade term goes from `5*4*2*2 = 80` to `5*4*3*2 = 120`, a `+40` delta, so the
new total is `9_335`. Update both the formula and the literal, and bump
`layoutVersion`'s expected value alongside it:

```swift
@Test func actionSpaceRoundTripsAGenerousGiveCountOfThree() {
    let space = ActionSpace(board: BoardGenerator.standard(), playerCount: 4)
    let offer = TradeOffer.enumerated(from: PlayerID(index: 0), give: [.lumber: 3], want: [.ore: 1])
    let index = space.index(of: .proposeTrade(offer))
    #expect(index != nil)
    let decoded = space.move(at: index!)
    guard case .proposeTrade(let decodedOffer) = decoded else {
        Issue.record("expected a proposeTrade move")
        return
    }
    #expect(decodedOffer.give == [.lumber: 3])
    #expect(decodedOffer.want == [.ore: 1])
}
```

Also update the existing size-formula test (`theSpaceIsTheSizeItClaims`) to
use the two constants and the new total:

```swift
+ resources * (resources - 1) * RulesEngine.maxGenerousGiveQuantity * RulesEngine.maxEnumeratedTradeQuantity
...
#expect(space.size == expected)
#expect(space.size == 9_335, "if this moved, bump ActionSpace.layoutVersion")
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/CatanEngine --filter ActionSpaceTests`
Expected: FAIL — `proposeSlot`/`proposal` both use a single `quantity`
variable bound to `maxEnumeratedTradeQuantity` (2), so a give count of 3
returns `nil` from `index(of:)` (fails the `(1...quantity).contains(...)`
guard) and the size formula is still symmetric.

- [ ] **Step 3: Update the size formula and bump `layoutVersion`**

In `init` (~line 143):

```swift
resources * (resources - 1)
    * RulesEngine.maxGenerousGiveQuantity * RulesEngine.maxEnumeratedTradeQuantity,
```

And at `ActionSpace.swift:68`:

```swift
public static let layoutVersion = 2
```

(it exists precisely so a shape change like this is acknowledged rather than
silently absorbed by anything reading `ActionSpace.layoutVersion` — e.g.
`TrainingExample.actionLayoutVersion`, `Packages/CatanAI/Sources/CatanAI/TrainingExample.swift:76`)

- [ ] **Step 4: Update `proposeSlot`/`proposal` for asymmetric ranges**

Replace the single `quantity` local in both functions (~lines 345-365) with
two:

```swift
private func proposeSlot(give: [Resource: Int], want: [Resource: Int]) -> Int? {
    let giveMax = RulesEngine.maxGenerousGiveQuantity
    let wantMax = RulesEngine.maxEnumeratedTradeQuantity
    guard give.count == 1, want.count == 1,
          let giveEntry = give.first, let wantEntry = want.first,
          giveEntry.key != wantEntry.key,
          (1...giveMax).contains(giveEntry.value), (1...wantMax).contains(wantEntry.value)
    else { return nil }
    let pair = resourceIndex(giveEntry.key) * (Resource.allCases.count - 1)
        + otherIndex(wantEntry.key, excluding: giveEntry.key)
    return (pair * giveMax + (giveEntry.value - 1)) * wantMax + (wantEntry.value - 1)
}

private func proposal(_ local: Int) -> ([Resource: Int], [Resource: Int]) {
    let giveMax = RulesEngine.maxGenerousGiveQuantity
    let wantMax = RulesEngine.maxEnumeratedTradeQuantity
    let wantCount = local % wantMax + 1
    let giveCount = (local / wantMax) % giveMax + 1
    let pair = local / (giveMax * wantMax)
    let span = Resource.allCases.count - 1
    let give = Resource.allCases[pair / span]
    return ([give: giveCount], [other(pair % span, excluding: give): wantCount])
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --package-path Packages/CatanEngine --filter ActionSpaceTests`
Expected: PASS. Then the full package:
Run: `swift test --package-path Packages/CatanEngine`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Packages/CatanEngine/Sources/CatanEngine/ActionSpace.swift \
        Packages/CatanEngine/Tests/CatanEngineTests/ActionSpaceTests.swift
git commit -m "feat(engine): widen ActionSpace's proposeTrade segment to match"
```

---

### Task 5: Replace `GameSession.proposedTradeThisTurn` with a state-derived gate

**Files:**
- Modify: `Packages/CatanEngine/Sources/CatanEngine/GameSession.swift`
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/GameSessionTests.swift`

**Interfaces:**
- Consumes: `state.declinedTradeOffersThisTurn`, `state.pendingTradeOffers`,
  `RulesEngine.maxTradeProposalsPerTurn` (Tasks 1-3).
- Produces: `.proposeTrade` moves are legal for `seat` in
  `decideNextDetailed()` while `seat` has no offer of its own currently
  pending *and* has fewer than `maxTradeProposalsPerTurn` declines recorded
  this turn. `GameSession.Checkpoint` no longer carries
  `proposedTradeThisTurn`.

- [ ] **Step 1: Write the failing test**

`GameSessionTests.swift` already has a private `FirstLegalPolicy` (returns
`observation.legalMoves[0]` verbatim) and a private `session(seed:policies:)`
helper, but that helper always builds a fresh `GameSetup.newGame` internally
with no way to seed extra state — this test constructs its own
`GameSession` directly instead, since it needs
`declinedTradeOffersThisTurn` set on the starting state before the session
ever sees it:

```swift
@Test func proposeTradeStopsBeingLegalAtTheTurnRetryLimit() {
    func legalIncludesProposeTrade(declinedCount: Int) -> Bool {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
        let seat = state.players[0].id
        state.players[0].resources = [.lumber: 5, .ore: 1]
        state.phase = .mainTurn(playerIndex: 0)
        state.declinedTradeOffersThisTurn[seat] = Array(
            repeating: TradeOffer(from: seat, give: [.lumber: 1], want: [.ore: 1]),
            count: declinedCount
        )
        var game = GameSession(state: state, policies: [seat: FirstLegalPolicy()], policySeed: 1)
        let decision = game.decideNextDetailed()
        return decision?.observation.legalMoves.contains {
            if case .proposeTrade = $0 { return true }
            return false
        } ?? false
    }

    #expect(legalIncludesProposeTrade(declinedCount: 0))
    #expect(!legalIncludesProposeTrade(declinedCount: RulesEngine.maxTradeProposalsPerTurn))
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/CatanEngine --filter GameSessionTests`
Expected: FAIL — today's gate is the single `proposedTradeThisTurn` bool,
which starts `false` regardless of `declinedTradeOffersThisTurn`, so both
calls return `true` and the second `#expect` fails.

- [ ] **Step 3: Replace the gate**

In `GameSession.swift`:

- Remove the `private var proposedTradeThisTurn = false` declaration (line 102).
- Remove `let proposedTradeThisTurn: Bool` from `Checkpoint` (line 130), its
  entry in `checkpoint`'s constructor call (line 187), and its restore in
  `init(checkpoint:policies:)` (line 204). No test in this repo constructs a
  `Checkpoint` by naming this field directly (confirmed by grep), so no
  other call site needs updating for this removal specifically.
- Replace the masking condition inside `decideNextDetailed()` (line 295-298):

```swift
let legal = RulesEngine.legalMoves(for: state, seat: seat).filter {
    guard case .proposeTrade = $0 else { return true }
    let alreadyPendingFromSeat = state.pendingTradeOffers.contains { $0.from == seat }
    let attemptsUsed = state.declinedTradeOffersThisTurn[seat]?.count ?? 0
    return !alreadyPendingFromSeat && attemptsUsed < RulesEngine.maxTradeProposalsPerTurn
}
```

- Remove `proposedTradeThisTurn = true` from `commit(seat:move:)`'s
  `.proposeTrade` branch (line 325).
- In `recordAction(by:move:)` (lines 382-394), remove the
  `proposedTradeThisTurn = false` line inside the `.endTurn` branch (line 385)
  — the gate above already re-derives correctly every call, since
  `declinedTradeOffersThisTurn` itself is reset to `[:]` on `.endTurn`
  (Task 2), so nothing session-side needs to mirror that reset anymore.
- Simplify `restorePendingTradeBookkeeping()` (lines 402-408) to just:

```swift
private mutating func restorePendingTradeBookkeeping() {
    queuedTradeResponse = nil
    guard let offer = state.pendingTradeOffers.first else { return }
    queueAutomatedResponse(to: offer)
}
```

(dropping its `proposedTradeThisTurn = false` and the restore-from-offer
line — both were only ever feeding the field this task removes).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/CatanEngine --filter GameSessionTests`
Expected: PASS. Then the full package:
Run: `swift test --package-path Packages/CatanEngine`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/CatanEngine/Sources/CatanEngine/GameSession.swift \
        Packages/CatanEngine/Tests/CatanEngineTests/GameSessionTests.swift
git commit -m "refactor(engine): derive the propose-trade turn gate from GameState"
```

---

### Task 6: `TradeHeuristics.proposeTrades` — retry with a different offer

**Files:**
- Modify: `Packages/CatanAI/Sources/CatanAI/TradeHeuristics.swift`
- Test: `Packages/CatanAI/Tests/CatanAITests/TradeHeuristicsTests.swift`

**Interfaces:**
- Consumes: `GameState.declinedTradeOffersThisTurn`,
  `RulesEngine.maxTradeProposalsPerTurn` (Tasks 1-2), and `Trading.bestRate`
  (pre-existing, already used by `bestBankTrade` in this same file) for the
  generous-unlock ceiling. Task 3's wider `RulesEngine.maxGenerousGiveQuantity`
  enumeration is what makes the resulting offer *legal*
  (`matchLegal`/`RulesEngine.legalMoves`) — `TradeHeuristics` itself never
  references that constant directly, since its own ceiling comes from
  `Trading.bestRate`, which is always ≤ `maxGenerousGiveQuantity` by
  construction (see Task 3's doc comment on why 3 was chosen).
- Produces: `proposeTrades(state:player:personality:weights:)` unchanged in
  signature; now returns a ranked-but-untried candidate (still at most one
  offer) instead of always the single cheapest-give candidate, and returns
  `[]` once `maxTradeProposalsPerTurn` attempts have already been declined
  this turn.

- [ ] **Step 1: Write the failing test — retry produces a different offer**

```swift
/// After a first proposal is declined, `proposeTrades` should float a
/// genuinely different offer rather than recomposing the identical one -
/// which, being a pure function of otherwise-unchanged state, it would
/// otherwise reproduce forever.
@Test func proposeTradesRetriesWithADifferentOfferAfterADecline() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    // Two surplus resources it could give up (wool, brick), either a
    // plausible cheapest-first pick depending on target weighting - the
    // point is the second call must not repeat whichever the first chose.
    state.players[0].resources = [.brick: 3, .lumber: 0, .grain: 1, .wool: 3, .ore: 0]

    let first = TradeHeuristics.proposeTrades(state: state, player: player, personality: .balanced)
    #expect(first.count == 1)

    state.declinedTradeOffersThisTurn[player] = [first[0]]
    let second = TradeHeuristics.proposeTrades(state: state, player: player, personality: .balanced)
    #expect(second.count == 1)
    #expect(second[0].give != first[0].give || second[0].want != first[0].want)
}

/// Stops retrying once `maxTradeProposalsPerTurn` attempts have already
/// been declined this turn - the bot gives up rather than looping forever
/// even though every remaining candidate is still, in principle, favorable.
@Test func proposeTradesGivesUpAfterTheTurnRetryLimit() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    state.players[0].resources = [.brick: 3, .lumber: 0, .grain: 1, .wool: 3, .ore: 0]
    state.declinedTradeOffersThisTurn[player] = Array(
        repeating: TradeOffer(from: player, give: [.brick: 1], want: [.lumber: 1]),
        count: RulesEngine.maxTradeProposalsPerTurn
    )
    #expect(TradeHeuristics.proposeTrades(state: state, player: player, personality: .balanced).isEmpty)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/CatanAI --filter TradeHeuristicsTests`
Expected: FAIL — `proposeTrades` doesn't read `declinedTradeOffersThisTurn`
at all yet, so both new tests fail (the retry test because the second call
returns the identical offer or `[]` via the existing `alreadyPending` guard
depending on whether `first[0]` is still in `pendingTradeOffers`; the limit
test because nothing stops it).

- [ ] **Step 3: Implement ranked retry**

Both `proposeTrades` and its new private helper below are members of `enum
TradeHeuristics` (add the helper inside the enum body, alongside
`resourceValue`/`nearestBlockedTarget`/`mostNeededResource` — it calls
`resourceValue`, which is `private`, so it must live in the same type to see
it). Replace the single-candidate selection in `proposeTrades` (~lines
165-247) entirely with:

```swift
public static func proposeTrades(
    state: GameState,
    player: PlayerID,
    personality: BotPersonality,
    weights: BotWeights = .default
) -> [TradeOffer] {
    guard let me = state.players.first(where: { $0.id == player }) else { return [] }
    let declined = state.declinedTradeOffersThisTurn[player] ?? []
    guard declined.count < RulesEngine.maxTradeProposalsPerTurn else { return [] }

    guard let target = nearestBlockedTarget(personality: personality, holding: me.resources, weights: weights)
    else { return [] }
    guard let mostNeeded = mostNeededResource(for: target, holding: me.resources) else { return [] }
    let wantValue = resourceValue(mostNeeded, for: me, personality: personality, weights: weights)

    let deficit = max(0, (target.cost[mostNeeded] ?? 0) - (me.resources[mostNeeded] ?? 0))
    let wantCount = min(max(1, deficit), RulesEngine.maxEnumeratedTradeQuantity)

    // Every give resource that's a genuine surplus (more than one card) AND
    // genuinely worth less to us than what we're asking for - the same
    // self-favorable bar this always enforced, just applied per-candidate
    // instead of to one pre-chosen resource, so a retry can rank past the
    // first candidate instead of only ever considering it. Sorted cheapest-
    // to-us first; `Resource.allCases` breaks ties the same way every time
    // (see the file-level note on why `min(by:)` over a dictionary wasn't
    // safe here).
    let rankedGive = Resource.allCases
        .filter {
            $0 != mostNeeded && (me.resources[$0] ?? 0) > 1
                && resourceValue($0, for: me, personality: personality, weights: weights) < wantValue
        }
        .sorted {
            let (lhs, rhs) = (resourceValue($0, for: me, personality: personality, weights: weights),
                               resourceValue($1, for: me, personality: personality, weights: weights))
            return lhs == rhs ? Resource.allCases.firstIndex(of: $0)! < Resource.allCases.firstIndex(of: $1)!
                              : lhs < rhs
        }

    func untried(give: Resource, giveCount: Int) -> TradeOffer? {
        let giveTable = [give: giveCount]
        let wantTable = [mostNeeded: wantCount]
        let alreadyTried = declined.contains { $0.give == giveTable && $0.want == wantTable }
            || state.pendingTradeOffers.contains { $0.from == player && $0.give == giveTable && $0.want == wantTable }
        return alreadyTried ? nil : TradeOffer.enumerated(from: player, give: giveTable, want: wantTable)
    }

    // Ordinary pass: walk ranked candidates at the usual 1-2 card quantity -
    // unchanged from before, just no longer limited to a single pre-chosen
    // candidate, so a decline can move to the next-cheapest resource instead
    // of regenerating the same offer forever.
    for give in rankedGive {
        let held = me.resources[give] ?? 0
        let generous = held >= weights.generousOfferSurplusThreshold
        let giveCount = min(generous ? 2 : 1, max(1, held - 1), RulesEngine.maxEnumeratedTradeQuantity)
        if let offer = untried(give: give, giveCount: giveCount) { return [offer] }
    }

    // Generous-unlock pass: every ordinary candidate for this target has
    // already been proposed-and-declined this turn. For the two highest-
    // value targets only (settlement/city - same scope
    // `enablesImmediateBuild` uses elsewhere in this file), escalate
    // quantity - not favorability, which every candidate above already
    // cleared - up to one card better than this bot's own best bank/port
    // rate for the cheapest candidate. See the design doc for why this
    // bound, not "uncapped": `Trading.bestRate` is the ceiling a rational
    // bot would never trade a *player* worse than, since the bank always
    // says yes.
    guard target.cost == Building.settlementCost || target.cost == Building.cityCost,
          let cheapest = rankedGive.first else { return [] }
    let held = me.resources[cheapest] ?? 0
    let ceiling = max(0, Trading.bestRate(for: cheapest, player: player, state: state) - 1)
    let giveCount = min(ceiling, max(1, held - 1))
    guard giveCount > 0, let offer = untried(give: cheapest, giveCount: giveCount) else { return [] }
    return [offer]
}
```

Remove the now-superseded single-candidate code this replaces (the old
`giveCandidates.min(by:)` block, the standalone self-favorable `guard`, and
the old `alreadyPending` check) — all folded into the version above. Leave
`bestBankTrade`, `mostNeededResource`, `nearestBlockedTarget`,
`totalDeficit`, `buildTargets`, `resourceValue`, and `evaluate` unchanged.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/CatanAI --filter TradeHeuristicsTests`
Expected: PASS, including the two new tests and every pre-existing one
(`tradeHeuristicsAcceptsClearNetGainTowardNextBuild`,
`proposeTradesSkipsWhenIdenticalOfferAlreadyPending`, etc.) — the pending-
offer dedup that test guards is now covered by the `alreadyTried` check
inside the local `untried(give:giveCount:)` function, so re-verify that
specific test still passes unmodified.

- [ ] **Step 5: Commit**

```bash
git add Packages/CatanAI/Sources/CatanAI/TradeHeuristics.swift \
        Packages/CatanAI/Tests/CatanAITests/TradeHeuristicsTests.swift
git commit -m "feat(ai): retry declined trade proposals with a different offer"
```

---

### Task 7: Generous-unlock override — targeted tests

**Files:**
- Test: `Packages/CatanAI/Tests/CatanAITests/TradeHeuristicsTests.swift`

**Interfaces:**
- Consumes: `TradeHeuristics.proposeTrades` from Task 6.

- [ ] **Step 1: Write the tests**

All three depend on `Building.roadCost = [.brick: 1, .lumber: 1]`,
`Building.settlementCost = [.brick: 1, .lumber: 1, .grain: 1, .wool: 1]`,
`Building.cityCost = [.ore: 3, .grain: 2]` (`Building.swift:3-5`) — the exact
resource amounts below are hand-computed against those costs, not
placeholders.

```swift
/// The TODO's own example: heavy ore surplus, missing exactly the 1 lumber
/// a settlement needs. The *first* call is still the ordinary 1-2 card
/// offer (favorability alone doesn't require overpaying); only once that
/// ordinary offer has itself been declined does the second call escalate to
/// a genuinely generous ratio - 3 ore for 1 lumber, one better than this
/// bot's own no-port bank rate of 4, and still a target only settlement/city
/// can trigger.
@Test func proposesAGenerousUnlockTradeAfterTheOrdinaryOfferIsDeclined() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    state.players[0].resources = [.brick: 1, .lumber: 0, .grain: 1, .wool: 1, .ore: 4]

    let first = TradeHeuristics.proposeTrades(state: state, player: player, personality: .balanced)
    #expect(first.count == 1)
    #expect(first.first?.give == [.ore: 2])
    #expect(first.first?.want == [.lumber: 1])

    state.declinedTradeOffersThisTurn[player] = first
    let second = TradeHeuristics.proposeTrades(state: state, player: player, personality: .balanced)
    #expect(second.count == 1)
    #expect(second.first?.give == [.ore: 3])
    #expect(second.first?.want == [.lumber: 1])
}

/// Never generous for a road - only the two highest-value targets
/// (settlement/city) can trigger the override. A road is the nearest-
/// blocked target here (deficit 1, versus 3+ for every other target), so
/// the ordinary offer is still made and declined normally, but the bot
/// gives up afterward instead of escalating quantity the way it would for
/// a settlement/city.
@Test func generousUnlockDoesNotApplyToARoad() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    state.players[0].resources = [.brick: 0, .lumber: 5, .grain: 0, .wool: 0, .ore: 0]

    let first = TradeHeuristics.proposeTrades(state: state, player: player, personality: .balanced)
    #expect(first.count == 1)
    #expect(first.first?.give == [.lumber: 2])
    #expect(first.first?.want == [.brick: 1])

    state.declinedTradeOffersThisTurn[player] = first
    #expect(TradeHeuristics.proposeTrades(state: state, player: player, personality: .balanced).isEmpty)
}

/// A 2:1 port for the give resource leaves no room to be "generous" at all
/// - the ceiling (`bestRate - 1`) collapses to 1, same as an ordinary offer,
/// so the escalation after a decline should ask for at most 1 more ore, not
/// 3, because the bank/port already beats any bigger player-to-player deal.
/// Skips (via `Issue.record`) if the standard board has no ore port, the
/// same fallback `TradingTests.swift`'s port tests use for a port that
/// might not exist on a given generated board.
@Test func generousUnlockCeilingCollapsesWithAGoodPort() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    guard let port = state.board.ports.first(where: { $0.kind == .resource(.ore) }) else {
        Issue.record("no ore port on standard board")
        return
    }
    let player = PlayerID(index: 0)
    state.players[0].settlements = [port.vertexA]
    state.players[0].resources = [.brick: 1, .lumber: 0, .grain: 1, .wool: 1, .ore: 4]

    let first = TradeHeuristics.proposeTrades(state: state, player: player, personality: .balanced)
    #expect(first.count == 1)

    state.declinedTradeOffersThisTurn[player] = first
    let second = TradeHeuristics.proposeTrades(state: state, player: player, personality: .balanced)
    #expect(second.first?.give == [.ore: 1])
}
```

- [ ] **Step 2: Run to verify the first three assertions fail, confirm the port test compiles**

Run: `swift test --package-path Packages/CatanAI --filter TradeHeuristicsTests`
Expected: FAIL on the escalation assertions specifically (`second.first?.give
== [.ore: 3]` in the first test, `second.first?.give == [.ore: 1]` in the
third) if Task 6's ceiling math has an off-by-one — verify the concrete
numbers: `Trading.bestRate` with no port is 4 (so ceiling 3), with a 2:1 port
is 2 (so ceiling 1). If everything already passes, Task 6 is correct as
written — this task exists to pin the exact numbers down with a regression
test, not necessarily to change code.

- [ ] **Step 3: Fix any discrepancy in `TradeHeuristics.swift` from Task 6**

Only if Step 2 surfaced a mismatch — adjust the generous-unlock pass's
ceiling/guard math to match the intended `bestRate(give) - 1` bound exactly.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/CatanAI --filter TradeHeuristicsTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/CatanAI/Tests/CatanAITests/TradeHeuristicsTests.swift \
        Packages/CatanAI/Sources/CatanAI/TradeHeuristics.swift
git commit -m "test(ai): pin the generous-unlock trade bound to the bank rate"
```

---

### Task 8: Full-suite verification and AI summary

**Files:**
- Create: `docs/AI_summaries/2026-09-03-creative-bot-trade-offers.md` (new directory)

**Interfaces:** None — this task verifies the whole feature end-to-end and
records it, producing no new code interfaces.

- [ ] **Step 1: Run both package suites in full**

Run: `swift test --package-path Packages/CatanEngine`
Run: `swift test --package-path Packages/CatanAI`
Expected: both PASS. `CatanAI` dominates runtime (~55-175s); do not
interrupt it.

- [ ] **Step 2: Run the determinism guard explicitly**

Run: `swift test --package-path Packages/CatanEngine --filter SeededGameFingerprintTests`
Run: `swift test --package-path Packages/CatanEngine --filter DeterminismTests`
Expected: both PASS unchanged — this feature adds no new randomness, but a
`Set`/`Dictionary`-order regression in the ranked-give walk (Task 6) would
show up here first if `Resource.allCases` tie-breaking were dropped
somewhere.

- [ ] **Step 3: Run the full gate**

Run: `scripts/gate.sh`
Expected: all 10 gates green (or `SKIP` where a gate legitimately can't run
in this environment — never a silent pass). This exercises the app/UI test
target too, which doesn't touch this feature's files but must still be
green before anything ships.

- [ ] **Step 4: Write the AI summary**

Create `docs/AI_summaries/2026-09-03-creative-bot-trade-offers.md`
summarizing: the two TODO items closed, the retry mechanism and its 3-attempt
cap, the generous-unlock override and its bank-rate-derived bound, and the
`GameSession.Checkpoint` simplification (dropped `proposedTradeThisTurn`).
Link to `docs/superpowers/specs/2026-09-03-creative-bot-trade-offers-design.md`.

- [ ] **Step 5: Update `TODO.md`**

Check off both boxes in TODO.md section 4:

```markdown
- [x] Bots should get more creative/aggressive with trade offers instead of
      giving up after one decline - if a first offer is turned down, a bot
      can float another (different ratio, different give/want) rather than
      falling back straight to the bank or dropping the plan.
- [x] Bots should be willing to be generous/sacrifice value when the trade
      unlocks their best play, even at worse than 3:1 - e.g. a bot sitting
      on 3 ore and missing exactly one resource for a settlement (its best
      available move) should offer those 3 ore for the 1 it needs, even
      without a 3:1 port, rather than only proposing trades at or better
      than bank rate.
```

- [ ] **Step 6: Commit**

```bash
git add docs/AI_summaries/2026-09-03-creative-bot-trade-offers.md TODO.md
git commit -m "docs: summarize creative bot trade offers work, close TODO items"
```

---

## Self-Review

**Spec coverage:**
- Retry after decline (up to 3 attempts, genuinely different offer) → Tasks
  1, 2, 5, 6.
- Generous/sacrifice trade to unlock best move, bounded by bank rate,
  scoped to settlement/city → Tasks 3, 4, 6, 7.
- Both human and bot-to-bot scope → no partner-type branching anywhere in
  the plan; `proposeTrades` never distinguishes, by design.
- Determinism/order-stability → `rankedGive`'s explicit tie-break via
  `Resource.allCases.firstIndex`, called out in Task 8 Step 2.
- Save/schema safety → Task 1.
- `ActionSpace`/training-export safety → Task 4, verified in Task 8 Step 3
  via the gate's training-export-validation stage.

**Placeholder scan:** every step above shows the actual diff/code, not a
description of one; the one intentional ellipsis (Task 7, Step 1's port
setup) is explicitly flagged as "find and reuse the existing helper," which
is a real, boundable instruction, not a "handle it later."

**Type consistency:** the local `untried(give:giveCount:)` helper and
`proposeTrades` (Task 6) use the same parameter names/types throughout;
`RulesEngine.maxGenerousGiveQuantity` and `RulesEngine.maxTradeProposalsPerTurn`
are named identically everywhere they're referenced (Tasks 3-7).

---

## Execution Handoff

Plan complete and saved to
`docs/superpowers/plans/2026-09-03-creative-bot-trade-offers.md`. Two
execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task,
   review between tasks, fast iteration.
2. **Inline Execution** — Execute tasks in this session using
   executing-plans, batch execution with checkpoints.

Which approach?
