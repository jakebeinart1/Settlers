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
| `Packages/CatanEngine/Tests/CatanEngineTests/RulesEngineTests.swift` | New candidates appear in `legalMoves`; decline is recorded; reset on endTurn |
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
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/RulesEngineTests.swift`

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

Run: `swift test --package-path Packages/CatanEngine --filter RulesEngineTests`
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

Run: `swift test --package-path Packages/CatanEngine --filter RulesEngineTests`
Expected: PASS. Also re-run the full `CatanEngine` suite to confirm nothing
else regressed:
Run: `swift test --package-path Packages/CatanEngine`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Packages/CatanEngine/Sources/CatanEngine/Trading.swift \
        Packages/CatanEngine/Sources/CatanEngine/RulesEngine.swift \
        Packages/CatanEngine/Tests/CatanEngineTests/RulesEngineTests.swift
git commit -m "feat(engine): record declined trade offers, reset them on endTurn"
```

---

### Task 3: Widen the give-quantity ceiling for enumeration

**Files:**
- Modify: `Packages/CatanEngine/Sources/CatanEngine/RulesEngine.swift` (constants + `tradeProposals`, ~lines 145-187)
- Test: `Packages/CatanEngine/Tests/CatanEngineTests/RulesEngineTests.swift`
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
    let legal = RulesEngine.legalMoves(for: state, seat: state.players[0].id)
    let giveThree = legal.contains {
        if case .proposeTrade(let offer) = $0 { return offer.give == [.lumber: 3] }
        return false
    }
    #expect(giveThree)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/CatanEngine --filter RulesEngineTests`
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

Run: `swift test --package-path Packages/CatanEngine --filter RulesEngineTests`
Run: `swift test --package-path Packages/CatanEngine --filter TradeOfferIDTests`
Expected: both PASS

- [ ] **Step 6: Commit**

```bash
git add Packages/CatanEngine/Sources/CatanEngine/RulesEngine.swift \
        Packages/CatanEngine/Tests/CatanEngineTests/RulesEngineTests.swift \
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
  now-different, ranges.

- [ ] **Step 1: Write the failing test**

In `ActionSpaceTests.swift`, alongside the existing size-formula assertion
(~line 32), update the expected multiplier and add a round-trip case for a
give count of 3:

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

Update the existing size-formula test to use the two constants:

```swift
* RulesEngine.maxGenerousGiveQuantity * RulesEngine.maxEnumeratedTradeQuantity
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/CatanEngine --filter ActionSpaceTests`
Expected: FAIL — `proposeSlot`/`proposal` both use a single `quantity`
variable bound to `maxEnumeratedTradeQuantity` (2), so a give count of 3
returns `nil` from `index(of:)` (fails the `(1...quantity).contains(...)`
guard) and the size formula is still symmetric.

- [ ] **Step 3: Update the size formula**

In `init` (~line 143):

```swift
resources * (resources - 1)
    * RulesEngine.maxGenerousGiveQuantity * RulesEngine.maxEnumeratedTradeQuantity,
```

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

```swift
@Test func aSeatMayRetryAfterADeclineUpToTheTurnLimit() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let seat = state.players[0].id
    state.players[0].resources = [.lumber: 5, .ore: 1]
    state.phase = .mainTurn(playerIndex: 0)

    // Nothing declined yet: proposeTrade should be legal.
    var legal = RulesEngine.legalMoves(for: state, seat: seat)
        .filter { if case .proposeTrade = $0 { return true }; return false }
    #expect(!legal.isEmpty)

    // Fill up to the per-turn limit with declines.
    state.declinedTradeOffersThisTurn[seat] = Array(
        repeating: TradeOffer(from: seat, give: [.lumber: 1], want: [.ore: 1]),
        count: RulesEngine.maxTradeProposalsPerTurn
    )
    let session = try GameSession(
        checkpoint: .init(
            version: 1, state: state, policyIDs: [:], policyRNG: RandomSource(seed: 1),
            policyEvaluationCount: 0, queuedTradeResponse: nil,
            currentTurnSeat: seat, actionsThisTurn: 0
        ),
        policies: [:]
    )
    let observation = session.observation(for: seat)
    legal = observation.legalMoves.filter { if case .proposeTrade = $0 { return true }; return false }
    #expect(legal.isEmpty)
}
```

(Adjust the `Checkpoint` initializer call and `observation(for:)` accessor
names to whatever `GameSessionTests.swift`'s existing tests use for
constructing a session mid-game and reading legal moves — match the file's
established pattern rather than inventing a new one; the meaningful
assertion is the two `legal` checks.)

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/CatanEngine --filter GameSessionTests`
Expected: FAIL to compile at first (the `Checkpoint` initializer above still
has `proposedTradeThisTurn` as a required argument) — that's expected until
Step 3 removes it. After removing it from the call above to match the
in-progress signature, expect a real behavioral failure: today's gate is the
single `proposedTradeThisTurn` bool, not a count, so this scenario isn't
expressible yet.

- [ ] **Step 3: Replace the gate**

In `GameSession.swift`:

- Remove the `private var proposedTradeThisTurn = false` declaration (~line 102).
- Remove `let proposedTradeThisTurn: Bool` from `Checkpoint` (~line 130), its
  entry in `checkpoint`'s constructor call (~line 187), and its restore in
  `init(checkpoint:policies:)` (~line 204).
- Remove the two reset sites (`proposedTradeThisTurn = true` at ~line 325 on
  a committed propose, `= false` at ~line 385 on `.endTurn`, `= false` at
  ~line 404, and the restore-from-checkpoint special case at ~line 406) —
  all of this bookkeeping is now derived from `state` instead of tracked
  session-side.
- Replace the masking condition at ~line 294-298:

```swift
let legal = RulesEngine.legalMoves(for: state, seat: seat).filter {
    guard case .proposeTrade = $0 else { return true }
    let alreadyPendingFromSeat = state.pendingTradeOffers.contains { $0.from == seat }
    let attemptsUsed = state.declinedTradeOffersThisTurn[seat]?.count ?? 0
    return !alreadyPendingFromSeat && attemptsUsed < RulesEngine.maxTradeProposalsPerTurn
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/CatanEngine --filter GameSessionTests`
Expected: PASS. Then the full package:
Run: `swift test --package-path Packages/CatanEngine`
Expected: PASS — pay particular attention to any `Checkpoint`-round-trip or
determinism test that referenced `proposedTradeThisTurn` by name; update
those call sites the same way as Step 1's test.

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
  `RulesEngine.maxTradeProposalsPerTurn`, `RulesEngine.maxGenerousGiveQuantity`
  (Tasks 1-3).
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

Replace the single-candidate selection in `proposeTrades` (~lines 165-247)
with a ranked walk that skips anything already declined this turn:

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

    let wantCount = min(max(1, (target.cost[mostNeeded] ?? 0) - (me.resources[mostNeeded] ?? 0)),
                         RulesEngine.maxEnumeratedTradeQuantity)

    // Every give resource we hold a genuine surplus of (more than one card),
    // ranked cheapest-to-us first via `resourceValue` - same ordering
    // `giveCandidates.min(by:)` used before, just kept as a full ranking
    // instead of collapsing to the single winner, so a retry can move on to
    // the next-cheapest instead of repeating the first. `Resource.allCases`
    // order breaks ties the same way every time (see the file-level note on
    // why `min(by:)` over a dictionary wasn't safe here).
    let rankedGive = Resource.allCases
        .filter { $0 != mostNeeded && (me.resources[$0] ?? 0) > 1 }
        .sorted {
            let (lhs, rhs) = (resourceValue($0, for: me, personality: personality, weights: weights),
                               resourceValue($1, for: me, personality: personality, weights: weights))
            return lhs == rhs ? Resource.allCases.firstIndex(of: $0)! < Resource.allCases.firstIndex(of: $1)!
                              : lhs < rhs
        }

    if let favorable = firstUntried(rankedGive, want: mostNeeded, wantCount: wantCount, target: target,
                                     me: me, player: player, state: state, declined: declined,
                                     personality: personality, weights: weights, requireFavorable: true) {
        return [favorable]
    }

    // Nothing favorable left untried - allow a self-unfavorable "generous
    // unlock" offer, but only toward the two highest-value targets
    // (settlement/city) and only strictly better than what the bank/port
    // would already give us for the same resource. See the design doc for
    // why this bound, not "uncapped": `Trading.bestRate` is the ceiling a
    // rational bot would never trade a *player* worse than, since the bank
    // always says yes.
    guard target.cost == Building.settlementCost || target.cost == Building.cityCost else { return [] }
    if let generous = firstUntried(rankedGive, want: mostNeeded, wantCount: wantCount, target: target,
                                    me: me, player: player, state: state, declined: declined,
                                    personality: personality, weights: weights, requireFavorable: false) {
        return [generous]
    }
    return []
}

/// Walks `rankedGive` for the first candidate offer that (a) hasn't already
/// been proposed-and-declined this turn and (b) either clears the
/// self-favorable bar or, when `requireFavorable` is false, at least stays
/// within the generous-unlock quantity ceiling (see `proposeTrades`).
private static func firstUntried(
    _ rankedGive: [Resource], want: Resource, wantCount: Int,
    target: (cost: [Resource: Int], weight: Double), me: Player, player: PlayerID, state: GameState,
    declined: [TradeOffer], personality: BotPersonality, weights: BotWeights, requireFavorable: Bool
) -> TradeOffer? {
    for give in rankedGive {
        let held = me.resources[give] ?? 0
        let ceiling = requireFavorable
            ? RulesEngine.maxEnumeratedTradeQuantity
            : max(0, Trading.bestRate(for: give, player: player, state: state) - 1)
        guard ceiling > 0 else { continue }
        let generous = held >= weights.generousOfferSurplusThreshold
        let giveCount = min(requireFavorable ? (generous ? 2 : 1) : ceiling, max(1, held - 1), ceiling)
        guard giveCount > 0 else { continue }

        if requireFavorable {
            guard resourceValue(want, for: me, personality: personality, weights: weights)
                > resourceValue(give, for: me, personality: personality, weights: weights) else { continue }
        }

        let giveTable = [give: giveCount]
        let wantTable = [want: wantCount]
        let alreadyTried = declined.contains { $0.give == giveTable && $0.want == wantTable }
            || state.pendingTradeOffers.contains { $0.from == player && $0.give == giveTable && $0.want == wantTable }
        guard !alreadyTried else { continue }

        return TradeOffer.enumerated(from: player, give: giveTable, want: wantTable)
    }
    return nil
}
```

Remove the now-superseded single-candidate code this replaces (the old
`giveCandidates.min(by:)` block, the standalone self-favorable `guard`, and
the old `alreadyPending` check) — all folded into `firstUntried` above.
Leave `bestBankTrade`, `mostNeededResource`, `nearestBlockedTarget`,
`totalDeficit`, `buildTargets`, `resourceValue`, and `evaluate` unchanged.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/CatanAI --filter TradeHeuristicsTests`
Expected: PASS, including the two new tests and every pre-existing one
(`tradeHeuristicsAcceptsClearNetGainTowardNextBuild`,
`proposeTradesSkipsWhenIdenticalOfferAlreadyPending`, etc.) — the pending-
offer dedup that test guards is now covered by the `alreadyTried` check
inside `firstUntried`, so re-verify that specific test still passes
unmodified.

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

```swift
/// The TODO's own example: 3 ore surplus, missing exactly the 1 lumber a
/// settlement needs, no port for ore (bank rate 4) - a generous offer of 3
/// ore for 1 lumber beats the bank (which would cost 4 ore) and unlocks the
/// bot's nearest-blocked target, so it should be proposed even though 3 ore
/// is worth more to this bot in isolation than 1 lumber under the ordinary
/// value function.
@Test func proposesAGenerousUnlockTradeForItsNearestBlockedSettlement() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    state.players[0].resources = [.brick: 1, .lumber: 0, .grain: 1, .wool: 1, .ore: 4]

    let offers = TradeHeuristics.proposeTrades(state: state, player: player, personality: .balanced)
    #expect(offers.count == 1)
    #expect(offers.first?.give == [.ore: 3])
    #expect(offers.first?.want == [.lumber: 1])
}

/// Never generous for a road or dev card - only the two highest-value
/// targets (settlement/city) can trigger the override.
@Test func generousUnlockDoesNotApplyToARoad() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    // Missing only brick for a road, but holds nothing else in genuine
    // surplus toward it and no other target is closer - the ordinary
    // self-favorable check should still gate this.
    state.players[0].resources = [.brick: 0, .lumber: 4, .grain: 0, .wool: 0, .ore: 0]

    let offers = TradeHeuristics.proposeTrades(state: state, player: player, personality: .balanced)
    // Either empty, or (if some other target's favorable trade exists) not
    // a generous give of the whole lumber stock toward a road.
    #expect(offers.allSatisfy { $0.give != [.lumber: 4] })
}

/// A 2:1 port for the give resource leaves no room to be "generous" at all
/// - the ceiling (`bestRate - 1`) collapses to 1, same as an ordinary offer,
/// so the bot should not overpay a player when the bank already beats any
/// player-to-player deal it could make.
@Test func generousUnlockCeilingCollapsesWithAGoodPort() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    state.players[0].resources = [.brick: 1, .lumber: 0, .grain: 1, .wool: 1, .ore: 4]
    // Give the player a 2:1 ore port by placing a settlement on it -
    // match however BoardGenerator.standard()/existing port tests in this
    // suite or RulesEngineTests establish a port for a seeded standard
    // board (reuse that helper rather than hand-rolling vertex/port lookup
    // here).
    // ... apply whatever the existing port-trade tests use to grant seat 0
    // a 2:1 ore port ...

    let offers = TradeHeuristics.proposeTrades(state: state, player: player, personality: .balanced)
    #expect(offers.allSatisfy { $0.give != [.ore: 3] })
}
```

(The port-setup ellipsis in the third test is intentional: grep
`Trading.bestRate`'s existing test coverage — likely `TradingTests.swift` —
for the established helper that grants a seat a specific port on
`BoardGenerator.standard()`, and reuse it verbatim rather than inventing new
board-setup code.)

- [ ] **Step 2: Run to verify the first two fail, confirm the port test compiles**

Run: `swift test --package-path Packages/CatanAI --filter TradeHeuristicsTests`
Expected: `proposesAGenerousUnlockTradeForItsNearestBlockedSettlement` FAILs
if Task 6's `firstUntried`/ceiling math has an off-by-one (verify the
concrete numbers: `Trading.bestRate` with no port is 4, so `ceiling = 3`,
matching the test's expected `.ore: 3`). If it already passes, Task 6 is
correct as written — this task exists to pin the exact numbers down with a
regression test, not necessarily to change code.

- [ ] **Step 3: Fix any discrepancy in `TradeHeuristics.swift` from Task 6**

Only if Step 2 surfaced a mismatch — adjust `firstUntried`'s ceiling/guard
math to match the intended `bestRate(give) - 1` bound exactly.

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

**Type consistency:** `firstUntried` and `proposeTrades` (Task 6) use the
same parameter names/types throughout; `RulesEngine.maxGenerousGiveQuantity`
and `RulesEngine.maxTradeProposalsPerTurn` are named identically everywhere
they're referenced (Tasks 3-7).

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
