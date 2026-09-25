# Ghost Player (Phases 1–4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn recorded games into a fitted model of one person, and a `GhostPolicy` that plays Expert's judgement pulled toward that person's habits. Prove the whole pipeline by recovering a *known* synthetic person before Jake's logs arrive.

**Architecture:** Replay each log through `GameSession`. At every human decision, score every candidate move with Expert's real scorer, take finite-difference gradients of those scores with respect to the evaluation weights, and add style features. A conditional-logit fit on the linearised scores recovers the person's weights `w`, sharpness `β` and style `θ`. `GhostPolicy` picks `argmax S_Expert(m) + λ·(β·S_w(m) + θ·style(m))` (piKL).

**Tech Stack:** Swift 6, SwiftPM (`Packages/CatanAI`), swift-testing. No new dependencies.

**Spec:** `docs/AI_summaries/2026-09-25-ghost-player-research.md`

## Global Constraints

- `CatanAI` imports only `Foundation` and `CatanEngine`. No UIKit/SwiftUI/Darwin: CI runs this package on Linux.
- Determinism: no `Int.random`, `.shuffled()` or `SystemRandomNumberGenerator`. Randomness goes through a `RandomSource`. Never let `Set` or `Dictionary` iteration order reach a decision; use `Set`s for membership only.
- Weight vector layout is `EvaluationWeights.vectorLabels` (24 slots). The frozen slots are `victoryPoint` (0, the ruler), `tradeMargin` (16) and `winning` (18). The Conquest slots 19–23 are free only when `state.variant == .conquest`.
- Anchor weights for Classic: `EvaluationWeights.forMode(.classic)`.
- No push until all tasks are done. Commits are local, in the worktree `~/Documents/Catan Game worktrees/ghost-player` on branch `feat/ghost-player`. Use conventional commits with the attribution trailer.
- Iterate with `swift test --package-path Packages/CatanAI --filter Ghost` and `swiftlint --strict`. Do not hand-run `scripts/gate.sh`.
- The `CatanAI` coverage floor is 90% (`scripts/coverage.sh`), so every new library file needs tests. The `ghost` executable is not covered.
- Out of scope (plan 2, after Jake's logs arrive): in-app drills, λ calibration against Jake's win rate, the blind test, think-time pacing, knight-before-roll (roll decisions are skipped in v1), and "Jake backed out of an accepted trade" (logged under the bot's seat, so it is invisible here).

## Review Focus

1. **A log whose moves don't replay** (older build, rules change). Expect: extraction throws `divergedAt(game:index:reason:)` naming the game and move, never a silent partial record. Test in Task 3.
2. **A human move not among the candidates** (for example a composed offer the composer never generates). Expect: the offer is added via `extraProposals`, and if it is still missing, a loud error. Covered by Task 1's `aHumanOfferExpertWouldNeverMakeIsScored`; the loud path is `ChoiceMissing`, wrapped in `divergedAt` (Task 3).
3. **Hot-seat logs with several humans.** Expect: the CLI skips them with a printed warning, so they never pollute a one-person model. Task 6.
4. **Fitting on zero or one decision.** Expect: the anchored model back, with no NaN. Test in Task 4.
5. **Linearisation drift:** fitted weights far from the anchor make `s0 + g·Δ` wrong. Expect: `ghost fit` prints the mean absolute error between linearised and exactly re-scored logits on a sample, so the drift is visible and not assumed away. Task 6.

---

### Task 1: `candidateScores`: Expert's value for every candidate, including offers Expert would never make

**Files:**
- Create: `Packages/CatanAI/Sources/CatanAI/Ghost/CandidateScoring.swift`
- Modify: `Packages/CatanAI/Sources/CatanAI/Evaluation/EvaluationPolicy.swift:165` (`private func score` → `func score`)
- Modify: `Packages/CatanAI/Sources/CatanAI/Evaluation/TradeCascade.swift:116` (`private func appeal` → `func appeal`)
- Test: `Packages/CatanAI/Tests/CatanAITests/GhostCandidateScoringTests.swift`

**Interfaces:**
- Produces: `public struct ScoredCandidate { let move: GameMove; let score: Double }`
- Produces: `extension EvaluationPolicy { public func candidateScores(_ observation: GameObservation, ledger: PublicLedger, extraProposals: [TradeOffer] = []) -> [ScoredCandidate] }`. The candidate *order and count* depend only on the observation, never on the weights. Task 3 relies on this.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CatanEngine
@testable import CatanAI

@Suite struct GhostCandidateScoringTests {

    private func table(seed: UInt64 = 81) -> (GameState, PlayerID) {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        playOpeningPlacements(in: &state, seed: seed)
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].resources = [.ore: 3, .grain: 1, .brick: 2, .lumber: 2]
        return (state, state.players[0].id)
    }

    private func observation(_ state: GameState, _ seat: PlayerID) -> GameObservation {
        GameObservation(seat: seat, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: seat))
    }

    /// Every move the engine accepts, other than a proposal, is scored.
    @Test func everyNonProposalLegalMoveIsScored() {
        let (state, me) = table()
        let obs = observation(state, me)
        let scored = EvaluationPolicy().candidateScores(obs, ledger: .fromPositionAlone(state, observer: me))
        let nonProposals = obs.legalMoves.filter { if case .proposeTrade = $0 { false } else { true } }
        for move in nonProposals where move != .rollDice {
            #expect(scored.contains { $0.move == move }, "missing \(move)")
        }
    }

    /// A person's offer that Expert would filter out still gets a value.
    @Test func aHumanOfferExpertWouldNeverMakeIsScored() {
        let (state, me) = table()
        let greedy = TradeOffer(from: me, give: [.brick: 1], want: [.ore: 2, .grain: 1])
        let scored = EvaluationPolicy().candidateScores(
            observation(state, me), ledger: .fromPositionAlone(state, observer: me), extraProposals: [greedy]
        )
        #expect(scored.contains { if case .proposeTrade(let o) = $0.move { o.sameProposition(as: greedy) } else { false } })
    }

    /// Weights change scores, never the candidate list. The gradient in Task 3 depends on it.
    @Test func candidateOrderDoesNotDependOnWeights() {
        let (state, me) = table()
        let obs = observation(state, me)
        let ledger = PublicLedger.fromPositionAlone(state, observer: me)
        var shifted = EvaluationWeights.forMode(.classic).vector
        shifted[1] *= 1.5
        let a = EvaluationPolicy().candidateScores(obs, ledger: ledger).map(\.move)
        let b = EvaluationPolicy(weights: EvaluationWeights(vector: shifted)).candidateScores(obs, ledger: ledger).map(\.move)
        #expect(a == b)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --package-path Packages/CatanAI --filter GhostCandidateScoringTests`
Expected: compile error, `value of type 'EvaluationPolicy' has no member 'candidateScores'`.

- [ ] **Step 3: Widen the two access levels.** In `EvaluationPolicy.swift`, change `private func score(` to `func score(`. In `TradeCascade.swift`, change `private func appeal(` to `func appeal(`.

- [ ] **Step 4: Implement `CandidateScoring.swift`**

```swift
import CatanEngine

/// One move a policy weighed, and what it scored.
public struct ScoredCandidate: Sendable, Equatable {
    public let move: GameMove
    public let score: Double
}

extension EvaluationPolicy {

    /// Every candidate at this decision with Expert's value for it, including
    /// offers Expert itself would never make.
    ///
    /// ## Why not reuse `best`
    /// `best` filters: a proposal that fails the cascade's bar is never scored.
    /// A model of a person needs a value for the move the person actually made,
    /// and people make offers Expert filters out. So proposals are valued, not
    /// judged: the worst plausible acceptance plus the purchase it opens, less
    /// the purchase already open (the same correction bank trades use). An
    /// offer nobody could accept is worth standing still.
    ///
    /// The list depends only on the observation, never on the weights, so two
    /// weight vectors give lists that line up index for index.
    public func candidateScores(
        _ observation: GameObservation,
        ledger: PublicLedger,
        extraProposals: [TradeOffer] = []
    ) -> [ScoredCandidate] {
        var counted = ledger
        counted.reconcileObserverHand(from: observation.state)
        let state = observation.state
        let evaluator = PositionEvaluator(seat: observation.seat, weights: weights(for: state))
        var purchases: PurchaseGains? = PurchaseGains(
            valuation: TradeValuation(evaluator: evaluator, state: state, ledger: counted)
        )
        var result: [ScoredCandidate] = []
        for move in observation.legalMoves where move != .rollDice {
            if case .proposeTrade = move { continue }
            if let value = score(move, state: state, ledger: counted, evaluator: evaluator, purchases: &purchases) {
                result.append(ScoredCandidate(move: move, score: value))
            }
        }
        return result + proposalScores(observation, ledger: counted, evaluator: evaluator, extra: extraProposals)
    }

    private func proposalScores(
        _ observation: GameObservation,
        ledger: PublicLedger,
        evaluator: PositionEvaluator,
        extra: [TradeOffer]
    ) -> [ScoredCandidate] {
        let state = observation.state
        let legal = observation.legalMoves
        let enumerated = legal.compactMap { move -> TradeOffer? in
            if case .proposeTrade(let offer) = move { offer } else { nil }
        }
        guard !enumerated.isEmpty, let me = state.players.first(where: { $0.id == observation.seat }) else { return [] }

        var offers: [TradeOffer] = []
        for offer in enumerated + TradeComposer.offers(from: me) + extra
        where !offers.contains(where: { $0.sameProposition(as: offer) }) {
            offers.append(offer)
        }
        let valuation = TradeValuation(evaluator: evaluator, state: state, ledger: ledger)
        let payers = PlannerTradeEvaluator(seat: observation.seat)
        var purchases = PurchaseGains(valuation: valuation)
        let openNow = purchases.gain(with: me.resources)
        var result: [ScoredCandidate] = []
        for offer in offers {
            let move = GameMove.proposeTrade(offer)
            guard legal.contains(move)
                || RulesEngine.isPermittedComposedProposal(move, by: observation.seat, in: state, legal: legal)
            else { continue }
            let settled = appeal(of: offer, payers: payers, valuation: valuation)?.worst ?? valuation.standingStill
            result.append(ScoredCandidate(move: move, score: settled + purchases.gain(with: me.resources.trading(offer)) - openNow))
        }
        return result
    }
}
```

`// ponytail: O(n²) dedupe over at most a few hundred offers per decision. Switch to a content-keyed Set if extraction profiling shows it.` Put this comment above the dedupe loop.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `swift test --package-path Packages/CatanAI --filter GhostCandidateScoringTests`
Expected: 3 tests pass. Then run the whole `EvaluationPolicy` suite to confirm the access change broke nothing: `--filter Evaluation`.

- [ ] **Step 6: Commit**

```bash
git add Packages/CatanAI/Sources/CatanAI/Ghost Packages/CatanAI/Sources/CatanAI/Evaluation Packages/CatanAI/Tests/CatanAITests/GhostCandidateScoringTests.swift
git commit -m "feat(ai): score every candidate move, including offers Expert filters out"
```

---

### Task 2: Style features

**Files:**
- Create: `Packages/CatanAI/Sources/CatanAI/Ghost/StyleFeatures.swift`
- Test: `Packages/CatanAI/Tests/CatanAITests/GhostStyleFeaturesTests.swift`

**Interfaces:**
- Produces: `public enum StyleFeatures { public static let labels: [String]; public static func of(_ move: GameMove, by seat: PlayerID, in state: GameState) -> [Double] }`. The result always has `labels.count` entries.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CatanEngine
@testable import CatanAI

@Suite struct GhostStyleFeaturesTests {

    private func state(seed: UInt64 = 82) -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        playOpeningPlacements(in: &state, seed: seed)
        state.phase = .mainTurn(playerIndex: 0)
        return state
    }

    private func value(_ label: String, _ features: [Double]) -> Double {
        features[StyleFeatures.labels.firstIndex(of: label)!]
    }

    @Test func aLopsidedProposalIsDescribed() {
        let s = state()
        let me = s.players[0].id
        let f = StyleFeatures.of(.proposeTrade(TradeOffer(from: me, give: [.brick: 2, .lumber: 2], want: [.grain: 1])), by: me, in: s)
        #expect(value("propose", f) == 1)
        #expect(value("proposeCardsGiven", f) == 4)
        #expect(value("proposeLopsided", f) == 3)
        #expect(value("proposeAfterRefusal", f) == 0)
    }

    @Test func reOfferingAfterARefusalIsFlagged() {
        var s = state()
        let me = s.players[0].id
        s.declinedTradeOffersThisTurn[me] = [TradeOffer(from: me, give: [.ore: 1], want: [.wool: 1])]
        let f = StyleFeatures.of(.proposeTrade(TradeOffer(from: me, give: [.ore: 2], want: [.wool: 1])), by: me, in: s)
        #expect(value("proposeAfterRefusal", f) == 1)
    }

    @Test func robbingTheLeaderIsFlagged() {
        var s = state()
        let me = s.players[0].id
        let leader = s.players[2].id
        s.players[2].settlements.append(contentsOf: s.players[1].settlements) // more public points than anyone
        let hex = s.board.tiles[0].coordinate
        #expect(value("robberHitsLeader", StyleFeatures.of(.moveRobber(hex, stealFrom: leader), by: me, in: s)) == 1)
        #expect(value("robberHitsLeader", StyleFeatures.of(.moveRobber(hex, stealFrom: s.players[1].id), by: me, in: s)) == 0)
    }

    @Test func everyMoveHasOneValuePerLabel() {
        let s = state()
        for move in RulesEngine.legalMoves(for: s, seat: s.players[0].id) {
            #expect(StyleFeatures.of(move, by: s.players[0].id, in: s).count == StyleFeatures.labels.count)
        }
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --package-path Packages/CatanAI --filter GhostStyleFeaturesTests`
Expected: compile error, `cannot find 'StyleFeatures' in scope`.

- [ ] **Step 3: Implement**

```swift
import CatanEngine

/// Habits Expert's position score cannot see: how a person trades, whom they
/// rob, what they do with a turn. Each is a number per candidate move, so the
/// person model can learn how much this person leans toward it.
///
/// Values are what the move *is*, not whether it is good. Goodness is the
/// score's job, and mixing the two would let a habit hide inside a value.
public enum StyleFeatures {

    public static let labels = [
        "propose", "proposeCardsGiven", "proposeLopsided", "proposeAfterRefusal",
        "bankTrade", "acceptOffer", "robberHitsLeader", "robberHitsBiggestHand",
        "buyDevCard", "playDevCard", "endTurn", "buildCity", "buildSettlement", "buildRoad",
    ]

    public static func of(_ move: GameMove, by seat: PlayerID, in state: GameState) -> [Double] {
        var features = [Double](repeating: 0, count: labels.count)
        func set(_ label: String, _ value: Double) { features[labels.firstIndex(of: label)!] = value }
        switch move {
        case .proposeTrade(let offer):
            let given = offer.give.values.reduce(0, +)
            set("propose", 1)
            set("proposeCardsGiven", Double(given))
            set("proposeLopsided", Double(given - offer.want.values.reduce(0, +)))
            set("proposeAfterRefusal", state.declinedTradeOffersThisTurn[seat, default: []].isEmpty ? 0 : 1)
        case .bankTrade: set("bankTrade", 1)
        case .respondToTrade(_, let accept): set("acceptOffer", accept ? 1 : 0)
        case .moveRobber(_, stealFrom: let victim), .playKnight(moveRobberTo: _, stealFrom: let victim):
            guard let victim else { break }
            set("robberHitsLeader", isLeader(victim, seat: seat, state: state) ? 1 : 0)
            set("robberHitsBiggestHand", hasBiggestHand(victim, seat: seat, state: state) ? 1 : 0)
        case .buyDevCard: set("buyDevCard", 1)
        case .endTurn: set("endTurn", 1)
        case .buildCity: set("buildCity", 1)
        case .buildSettlement: set("buildSettlement", 1)
        case .buildRoad: set("buildRoad", 1)
        default: break
        }
        if case .playKnight = move { set("playDevCard", 1) }
        if case .playRoadBuilding = move { set("playDevCard", 1) }
        if case .playYearOfPlenty = move { set("playDevCard", 1) }
        if case .playMonopoly = move { set("playDevCard", 1) }
        return features
    }

    /// Ties count as leading: robbing any co-leader is robbing the leader.
    private static func isLeader(_ victim: PlayerID, seat: PlayerID, state: GameState) -> Bool {
        let others = state.players.map(\.id).filter { $0 != seat }
        let top = others.map { state.publicVictoryPoints(for: $0) }.max() ?? 0
        return state.publicVictoryPoints(for: victim) == top
    }

    /// Hand size is public at a real table; composition is not, and is not used.
    private static func hasBiggestHand(_ victim: PlayerID, seat: PlayerID, state: GameState) -> Bool {
        func size(_ id: PlayerID) -> Int { state.players.first { $0.id == id }?.resources.values.reduce(0, +) ?? 0 }
        let top = state.players.map(\.id).filter { $0 != seat }.map(size).max() ?? 0
        return size(victim) == top
    }
}
```

If `robbingTheLeaderIsFlagged`'s fixture does not make seat 2 the sole public leader (for example because setup ties it with seat 0), adjust the fixture: raise seat 2's points with an extra settlement from the legal setup list. Leave the implementation alone.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --package-path Packages/CatanAI --filter GhostStyleFeaturesTests`
Expected: 4 pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/CatanAI/Sources/CatanAI/Ghost/StyleFeatures.swift Packages/CatanAI/Tests/CatanAITests/GhostStyleFeaturesTests.swift
git commit -m "feat(ai): describe a move's style - trade shape, robber target, tempo"
```

---

### Task 3: Decision records and the extractor

**Files:**
- Create: `Packages/CatanAI/Sources/CatanAI/Ghost/DecisionRecord.swift`
- Create: `Packages/CatanAI/Sources/CatanAI/Ghost/DecisionExtractor.swift`
- Test: `Packages/CatanAI/Tests/CatanAITests/GhostDecisionExtractorTests.swift`

**Interfaces:**
- Consumes: `candidateScores` (Task 1), `StyleFeatures.of` (Task 2).
- Produces:
  - `public enum Facet: String, Codable, CaseIterable { case opening, turn, tradeResponse, robber, discard }`
  - `public struct CandidateRecord: Codable, Equatable { move: GameMove; score: Double; gradient: [Double] /*24*/; style: [Double] }`
  - `public struct DecisionRecord: Codable, Equatable { game: String; facet: Facet; anchor: [Double] /*24*/; candidates: [CandidateRecord]; chosen: Int }`
  - `public struct LoggedGame { id: String; initialState: GameState; humanSeats: Set<PlayerID>; events: [LoggedMove] }` with `public struct LoggedMove { player: PlayerID; move: GameMove }`
  - `public enum ExtractionError: Error, Equatable { case divergedAt(game: String, index: Int, reason: String) }`
  - `public enum DecisionExtractor { static let frozen: Set<Int>; static func decisions(in: LoggedGame, anchor: EvaluationWeights) throws -> [DecisionRecord] }`

- [ ] **Step 1: Write the failing tests.** The "person" is an Expert seat, so the logged move is always legal.

```swift
import Testing
import CatanEngine
@testable import CatanAI

@Suite struct GhostDecisionExtractorTests {

    /// A short real game: every seat Expert, first 120 moves, seat 0 treated as the human.
    private func loggedGame(seed: UInt64 = 91, moves: Int = 120) throws -> LoggedGame {
        let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        var session = GameSession(
            state: initial,
            policies: Dictionary(uniqueKeysWithValues: initial.players.map { ($0.id, EvaluationPolicy() as any Policy) }),
            policySeed: seed
        )
        var events: [LoggedMove] = []
        while events.count < moves, let step = try session.step() {
            events.append(LoggedMove(player: step.actor, move: step.move))
        }
        return LoggedGame(id: "g\(seed)", initialState: initial, humanSeats: [initial.players[0].id], events: events)
    }

    @Test func everyRecordNamesAChosenCandidateAndHasFullVectors() throws {
        let records = try DecisionExtractor.decisions(in: loggedGame(), anchor: .forMode(.classic))
        #expect(!records.isEmpty)
        for r in records {
            #expect(r.candidates.indices.contains(r.chosen))
            #expect(r.candidates.count > 1)
            #expect(r.candidates.allSatisfy { $0.gradient.count == 24 && $0.style.count == StyleFeatures.labels.count })
        }
        #expect(records.contains { $0.facet == .opening })
    }

    /// The linearisation must predict a real re-score for a small weight change.
    @Test func gradientPredictsARescore() throws {
        let game = try loggedGame(moves: 40)
        let anchor = EvaluationWeights.forMode(.classic)
        let record = try #require(DecisionExtractor.decisions(in: game, anchor: anchor).last)
        var shifted = anchor.vector
        shifted[1] += 0.02
        let rescored = try DecisionExtractor.decisions(in: game, anchor: EvaluationWeights(vector: shifted)).last!
        for (a, b) in zip(record.candidates, rescored.candidates) {
            #expect(abs(a.score + a.gradient[1] * 0.02 - b.score) < 1e-3)
        }
    }

    @Test func frozenWeightsHaveZeroGradient() throws {
        let records = try DecisionExtractor.decisions(in: loggedGame(moves: 40), anchor: .forMode(.classic))
        for r in records { for c in r.candidates { for i in DecisionExtractor.frozen { #expect(c.gradient[i] == 0) } } }
    }

    /// Review Focus 1: a log that stops replaying fails loudly, naming where.
    @Test func aMoveThatDoesNotReplayThrowsWithItsIndex() throws {
        var game = try loggedGame(moves: 20)
        var events = game.events
        events[12] = LoggedMove(player: events[12].player, move: .buildCity(VertexID(touchingTiles: [])))
        game = LoggedGame(id: game.id, initialState: game.initialState, humanSeats: game.humanSeats, events: events)
        #expect(throws: ExtractionError.self) { try DecisionExtractor.decisions(in: game, anchor: .forMode(.classic)) }
    }
}
```

Check `VertexID`'s initializer in `CatanEngine/Models`. If `VertexID(touchingTiles: [])` does not compile, use any vertex that is certainly not the seat's settlement, such as the first vertex of `state.board`. The point is only that the move is illegal.

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --package-path Packages/CatanAI --filter GhostDecisionExtractorTests`
Expected: compile error, `cannot find 'LoggedGame' in scope`.

- [ ] **Step 3: Implement `DecisionRecord.swift`**

```swift
import CatanEngine

/// Which part of the game a decision belongs to. Accuracy is reported per
/// facet, because "plays like me" is judged facet by facet.
public enum Facet: String, Codable, CaseIterable, Sendable {
    case opening, turn, tradeResponse, robber, discard
}

public struct CandidateRecord: Codable, Sendable, Equatable {
    public let move: GameMove
    /// Expert's value at the anchor weights.
    public let score: Double
    /// d score / d weight, per `EvaluationWeights.vectorLabels` slot.
    public let gradient: [Double]
    public let style: [Double]
}

/// One decision a person made, with everything they could have done instead.
public struct DecisionRecord: Codable, Sendable, Equatable {
    public let game: String
    public let facet: Facet
    /// The weights `score` and `gradient` were taken at.
    public let anchor: [Double]
    public let candidates: [CandidateRecord]
    public let chosen: Int
}

public struct LoggedMove: Sendable {
    public let player: PlayerID
    public let move: GameMove
    public init(player: PlayerID, move: GameMove) { self.player = player; self.move = move }
}

/// A recorded game, independent of where it was stored.
public struct LoggedGame: Sendable {
    public let id: String
    public let initialState: GameState
    public let humanSeats: Set<PlayerID>
    public let events: [LoggedMove]
    public init(id: String, initialState: GameState, humanSeats: Set<PlayerID>, events: [LoggedMove]) {
        self.id = id; self.initialState = initialState; self.humanSeats = humanSeats; self.events = events
    }
}
```

- [ ] **Step 4: Implement `DecisionExtractor.swift`**

```swift
import CatanEngine

public enum ExtractionError: Error, Equatable {
    case divergedAt(game: String, index: Int, reason: String)
}

/// Replays a recorded game and writes down every choice its human made.
///
/// ## Why gradients, not features
/// Expert's score is not one tidy weighted sum. It caps at a win, subtracts
/// the strongest rival, and adds purchase corrections to trades. Refactoring it
/// to expose features would touch the shipping bot. Instead, each candidate is
/// re-scored at slightly nudged weights, and the slope is recorded. The fit then
/// works on `score + gradient · Δw`, which is exact wherever the score is linear
/// in the weights (almost everywhere) and is checked where it is not (`ghost fit`
/// prints the drift).
public enum DecisionExtractor {

    /// The ruler, the no-worse-trades rule, and the win constant. See `EvaluationWeights`.
    public static let frozen: Set<Int> = [0, 16, 18]
    static let conquestSlots = 19..<24

    public static func decisions(in game: LoggedGame, anchor: EvaluationWeights) throws -> [DecisionRecord] {
        var session = GameSession(state: game.initialState, policies: [:], policySeed: 0)
        var records: [DecisionRecord] = []
        for (index, event) in game.events.enumerated() {
            if game.humanSeats.contains(event.player) {
                do {
                    if let found = try decision(for: event, in: session, game: game.id, anchor: anchor) { records.append(found) }
                } catch {
                    throw ExtractionError.divergedAt(game: game.id, index: index, reason: "\(error)")
                }
            }
            do { _ = try session.applyExternal(event.move, by: event.player) } catch {
                throw ExtractionError.divergedAt(game: game.id, index: index, reason: "\(error)")
            }
        }
        return records
    }

    struct ChoiceMissing: Error { let move: GameMove }

    static func decision(for event: LoggedMove, in session: GameSession, game: String, anchor: EvaluationWeights) throws -> DecisionRecord? {
        let state = session.state
        let legal = RulesEngine.legalMoves(for: state, seat: event.player)
        // A roll is not a decision; v1 does not model knight-before-roll.
        guard legal.count > 1, !legal.contains(.rollDice) else { return nil }
        let observation = GameObservation(seat: event.player, state: state, legalMoves: legal)
        let ledger = session.ledger(for: event.player)
        var extra: [TradeOffer] = []
        if case .proposeTrade(let offer) = event.move { extra.append(offer) }

        let base = EvaluationPolicy(weights: anchor).candidateScores(observation, ledger: ledger, extraProposals: extra)
        guard base.count > 1 else { return nil }
        guard let chosen = base.firstIndex(where: { same($0.move, event.move) }) else { throw ChoiceMissing(move: event.move) }
        let gradients = slopes(observation, ledger: ledger, extra: extra, anchor: anchor, count: base.count)
        let candidates = base.enumerated().map { i, c in
            CandidateRecord(move: c.move, score: c.score, gradient: gradients[i],
                            style: StyleFeatures.of(c.move, by: event.player, in: state))
        }
        return DecisionRecord(game: game, facet: facet(of: state, legal: legal), anchor: anchor.vector,
                              candidates: candidates, chosen: chosen)
    }

    /// Central differences, one free weight at a time. `result[candidate][slot]`.
    static func slopes(_ observation: GameObservation, ledger: PublicLedger, extra: [TradeOffer],
                       anchor: EvaluationWeights, count: Int) -> [[Double]] {
        var result = [[Double]](repeating: [Double](repeating: 0, count: anchor.vector.count), count: count)
        for slot in freeSlots(for: observation.state) {
            let step = 0.01 * max(abs(anchor.vector[slot]), 0.05)
            let up = scores(observation, ledger, extra, anchor, slot, +step)
            let down = scores(observation, ledger, extra, anchor, slot, -step)
            precondition(up.count == count && down.count == count, "candidate list moved with the weights")
            for i in 0..<count { result[i][slot] = (up[i] - down[i]) / (2 * step) }
        }
        return result
    }

    private static func scores(_ observation: GameObservation, _ ledger: PublicLedger, _ extra: [TradeOffer],
                               _ anchor: EvaluationWeights, _ slot: Int, _ delta: Double) -> [Double] {
        var vector = anchor.vector
        vector[slot] += delta
        return EvaluationPolicy(weights: EvaluationWeights(vector: vector))
            .candidateScores(observation, ledger: ledger, extraProposals: extra).map(\.score)
    }

    static func freeSlots(for state: GameState) -> [Int] {
        EvaluationWeights.vectorLabels.indices.filter {
            !frozen.contains($0) && (state.variant == .conquest || !conquestSlots.contains($0))
        }
    }

    static func facet(of state: GameState, legal: [GameMove]) -> Facet {
        switch state.phase {
        case .setupForward, .setupBackward: return .opening
        case .discarding: return .discard
        case .movingRobber: return .robber
        default:
            return legal.allSatisfy { if case .respondToTrade = $0 { true } else { false } } ? .tradeResponse : .turn
        }
    }

    /// A person's offer carries a fresh id; it matches by what it says.
    static func same(_ a: GameMove, _ b: GameMove) -> Bool {
        if case .proposeTrade(let x) = a, case .proposeTrade(let y) = b { return x.sameProposition(as: y) }
        return a == b
    }
}
```

`// ponytail: 2 × free-slot re-scorings per decision (33 in Classic). Fine offline; memoise per-state evaluations if extraction of 100+ games is too slow.` Put this comment on `slopes`.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `swift test --package-path Packages/CatanAI --filter GhostDecisionExtractorTests`
Expected: 4 pass. If `gradientPredictsARescore` fails on a trade candidate by more than 1e-3, that candidate's score is not linear there. Print which move, and report it; do not loosen the tolerance silently.

- [ ] **Step 6: Commit**

```bash
git add Packages/CatanAI/Sources/CatanAI/Ghost Packages/CatanAI/Tests/CatanAITests/GhostDecisionExtractorTests.swift
git commit -m "feat(ai): extract a person's decisions from a replayed game, with score slopes"
```

---

### Task 4: `PersonModel` and the fit

**Files:**
- Create: `Packages/CatanAI/Sources/CatanAI/Ghost/PersonModel.swift`
- Create: `Packages/CatanAI/Sources/CatanAI/Ghost/PersonFitter.swift`
- Test: `Packages/CatanAI/Tests/CatanAITests/GhostPersonModelTests.swift`

**Interfaces:**
- Consumes: `DecisionRecord` (Task 3), `DecisionExtractor.frozen`.
- Produces:
  - `public struct PersonModel: Codable, Equatable { var weights: [Double]; var beta: Double; var theta: [Double]; static func anchored(at: EvaluationWeights) -> PersonModel; func logits(_:) -> [Double]; func probabilities(_:) -> [Double]; func top1Accuracy(_:) -> Double; func meanLogLikelihood(_:) -> Double }`
  - `public struct FitOptions { iterations = 3000; learningRate = 0.02; weightPrior = 1.0; stylePrior = 0.1 }`
  - `public enum PersonFitter { static func fit(_ decisions: [DecisionRecord], anchor: EvaluationWeights, options: FitOptions = FitOptions()) -> PersonModel }`

- [ ] **Step 1: Write the failing tests.** They use synthetic decisions with a known person, so they are fast and need no games.

```swift
import Testing
import CatanEngine
@testable import CatanAI

@Suite struct GhostPersonModelTests {

    private let anchor = EvaluationWeights.forMode(.classic)
    private let styleCount = StyleFeatures.labels.count

    /// A known person: values production more than Expert, is sharp, loves proposing, hates ending turns.
    private var truth: PersonModel {
        var model = PersonModel.anchored(at: anchor)
        model.weights[1] += 0.3
        model.beta = 3
        model.theta[0] = 1.5
        model.theta[10] = -1.0
        return model
    }

    private func synthetic(count: Int, seed: UInt64) -> [DecisionRecord] {
        var rng = RandomSource(seed: seed)
        return (0..<count).map { n in
            let candidates = (0..<6).map { _ -> CandidateRecord in
                var gradient = [Double](repeating: 0, count: 24)
                gradient[1] = Double.random(in: -1...1, using: &rng)
                var style = [Double](repeating: 0, count: styleCount)
                style[0] = Double.random(in: 0...1, using: &rng) < 0.3 ? 1 : 0
                style[10] = Double.random(in: 0...1, using: &rng) < 0.3 ? 1 : 0
                return CandidateRecord(move: .endTurn, score: Double.random(in: -1...1, using: &rng), gradient: gradient, style: style)
            }
            let draft = DecisionRecord(game: "s\(n % 20)", facet: .turn, anchor: anchor.vector, candidates: candidates, chosen: 0)
            let p = truth.probabilities(draft)
            var roll = Double.random(in: 0..<1, using: &rng), chosen = 0
            while chosen < p.count - 1, roll >= p[chosen] { roll -= p[chosen]; chosen += 1 }
            return DecisionRecord(game: draft.game, facet: .turn, anchor: draft.anchor, candidates: candidates, chosen: chosen)
        }
    }

    @Test func probabilitiesSumToOne() {
        let d = synthetic(count: 1, seed: 1)[0]
        #expect(abs(PersonModel.anchored(at: anchor).probabilities(d).reduce(0, +) - 1) < 1e-9)
    }

    @Test func theFitRecoversAKnownPerson() {
        let train = synthetic(count: 1500, seed: 2)
        let heldOut = synthetic(count: 500, seed: 3)
        let fitted = PersonFitter.fit(train, anchor: anchor)
        #expect(fitted.theta[0] > 0.9, "proposal habit not recovered: \(fitted.theta[0])")
        #expect(fitted.theta[10] < -0.5, "end-turn aversion not recovered: \(fitted.theta[10])")
        #expect(fitted.weights[1] - anchor.vector[1] > 0.1, "production shift not recovered")
        #expect((1.5...5).contains(fitted.beta), "beta \(fitted.beta)")
        #expect(fitted.meanLogLikelihood(heldOut) > PersonModel.anchored(at: anchor).meanLogLikelihood(heldOut))
    }

    @Test func frozenSlotsNeverMove() {
        let fitted = PersonFitter.fit(synthetic(count: 300, seed: 4), anchor: anchor)
        for slot in DecisionExtractor.frozen { #expect(fitted.weights[slot] == anchor.vector[slot]) }
    }

    /// Review Focus 4: no data means the anchor, not NaN.
    @Test func fittingNothingReturnsTheAnchor() {
        #expect(PersonFitter.fit([], anchor: anchor) == PersonModel.anchored(at: anchor))
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --package-path Packages/CatanAI --filter GhostPersonModelTests`
Expected: compile error, `cannot find 'PersonModel' in scope`.

- [ ] **Step 3: Implement `PersonModel.swift`**

```swift
import CatanEngine
import Foundation

/// How likely one person is to make each candidate move.
///
/// `P(m) ∝ exp(beta · S_w(m) + theta · style(m))`, where `S_w` is Expert's
/// score under this person's weights. `weights` says what they value, `beta`
/// how consistently they play their own best move, and `theta` the habits the
/// score cannot see.
public struct PersonModel: Codable, Sendable, Equatable {
    public var weights: [Double]
    public var beta: Double
    public var theta: [Double]

    public static func anchored(at anchor: EvaluationWeights) -> PersonModel {
        PersonModel(weights: anchor.vector, beta: 1, theta: [Double](repeating: 0, count: StyleFeatures.labels.count))
    }

    /// Score under this person's weights, by the recorded slope.
    public func personalScore(_ c: CandidateRecord, anchor: [Double]) -> Double {
        var shift = 0.0
        for i in c.gradient.indices { shift += c.gradient[i] * (weights[i] - anchor[i]) }
        return c.score + shift
    }

    public func logits(_ d: DecisionRecord) -> [Double] {
        d.candidates.map { c in
            beta * personalScore(c, anchor: d.anchor) + zip(theta, c.style).reduce(0) { $0 + $1.0 * $1.1 }
        }
    }

    public func probabilities(_ d: DecisionRecord) -> [Double] {
        let l = logits(d)
        let top = l.max() ?? 0
        let e = l.map { exp($0 - top) }
        let total = e.reduce(0, +)
        return e.map { $0 / total }
    }

    /// Ties go to the earlier candidate, as in `EvaluationPolicy.best`.
    public func top1Accuracy(_ ds: [DecisionRecord]) -> Double {
        guard !ds.isEmpty else { return 0 }
        let hits = ds.filter { d in
            let l = logits(d)
            return l.firstIndex(of: l.max()!) == d.chosen
        }.count
        return Double(hits) / Double(ds.count)
    }

    public func meanLogLikelihood(_ ds: [DecisionRecord]) -> Double {
        guard !ds.isEmpty else { return 0 }
        return ds.reduce(0) { $0 + log(max(probabilities($1)[$1.chosen], 1e-300)) } / Double(ds.count)
    }
}
```

- [ ] **Step 4: Implement `PersonFitter.swift`**

```swift
import CatanEngine
import Foundation

public struct FitOptions: Sendable {
    public var iterations = 3000
    public var learningRate = 0.02
    /// Pull of each weight toward Expert's, in units of the weight's own size.
    public var weightPrior = 1.0
    /// Pull of each habit toward "no habit".
    public var stylePrior = 0.1
    public init() {}
}

/// Maximum-likelihood fit of a `PersonModel`, pulled toward Expert.
///
/// ## Why a prior
/// A few games say little about rare decisions. With no pull, a weight nobody's
/// choices touched drifts on noise. With the pull, it stays at Expert's value:
/// thin data yields Expert's play, not random play. This is Maia4All's lesson
/// (a strong shared base plus a small personal part) in 24 numbers instead of a
/// network.
public enum PersonFitter {

    public static func fit(_ decisions: [DecisionRecord], anchor: EvaluationWeights,
                           options: FitOptions = FitOptions()) -> PersonModel {
        let start = PersonModel.anchored(at: anchor)
        guard !decisions.isEmpty else { return start }
        let movable = movableSlots(decisions)
        var params = pack(start)
        var adam = Adam(count: params.count)
        for _ in 0..<options.iterations {
            let grad = gradient(unpack(params), decisions: decisions, anchor: anchor.vector,
                                movable: movable, options: options)
            adam.step(&params, grad, rate: options.learningRate)
            params[24] = max(params[24], 0.01) // beta stays positive
        }
        return unpack(params)
    }

    /// Weights some decision's score actually depends on, minus the frozen ones.
    static func movableSlots(_ ds: [DecisionRecord]) -> [Bool] {
        (0..<24).map { slot in
            !DecisionExtractor.frozen.contains(slot)
                && ds.contains { $0.candidates.contains { $0.gradient[slot] != 0 } }
        }
    }

    static func pack(_ m: PersonModel) -> [Double] { m.weights + [m.beta] + m.theta }

    static func unpack(_ p: [Double]) -> PersonModel {
        PersonModel(weights: Array(p[0..<24]), beta: p[24], theta: Array(p[25...]))
    }

    /// Gradient of (mean negative log-likelihood + priors), in `pack` order.
    static func gradient(_ m: PersonModel, decisions: [DecisionRecord], anchor: [Double],
                         movable: [Bool], options: FitOptions) -> [Double] {
        var g = [Double](repeating: 0, count: 25 + m.theta.count)
        for d in decisions {
            let p = m.probabilities(d)
            for (j, c) in d.candidates.enumerated() {
                let r = (p[j] - (j == d.chosen ? 1 : 0)) / Double(decisions.count)
                for i in 0..<24 where movable[i] { g[i] += r * m.beta * c.gradient[i] }
                g[24] += r * m.personalScore(c, anchor: d.anchor)
                for k in c.style.indices { g[25 + k] += r * c.style[k] }
            }
        }
        for i in 0..<24 where movable[i] {
            let scale = max(abs(anchor[i]), 0.05)
            g[i] += 2 * options.weightPrior * (m.weights[i] - anchor[i]) / (scale * scale) / Double(decisions.count)
        }
        for k in m.theta.indices { g[25 + k] += 2 * options.stylePrior * m.theta[k] / Double(decisions.count) }
        return g
    }
}

/// Adam, because the weights, beta and habits live on very different scales.
struct Adam {
    private var m: [Double], v: [Double], t = 0
    init(count: Int) { m = .init(repeating: 0, count: count); v = m }
    mutating func step(_ x: inout [Double], _ g: [Double], rate: Double) {
        t += 1
        for i in x.indices {
            m[i] = 0.9 * m[i] + 0.1 * g[i]
            v[i] = 0.999 * v[i] + 0.001 * g[i] * g[i]
            let mh = m[i] / (1 - pow(0.9, Double(t))), vh = v[i] / (1 - pow(0.999, Double(t)))
            x[i] -= rate * mh / (sqrt(vh) + 1e-8)
        }
    }
}
```

Frozen and unmovable slots get a zero gradient, so Adam never moves them. `frozenSlotsNeverMove` pins this.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `swift test --package-path Packages/CatanAI --filter GhostPersonModelTests`
Expected: 4 pass in a few seconds. If recovery misses a threshold, try `iterations = 6000` before touching any threshold, and note which one it was.

- [ ] **Step 6: Commit**

```bash
git add Packages/CatanAI/Sources/CatanAI/Ghost Packages/CatanAI/Tests/CatanAITests/GhostPersonModelTests.swift
git commit -m "feat(ai): fit a person model - weights, sharpness and habits - toward Expert"
```

---

### Task 5: `GhostPolicy`

**Files:**
- Create: `Packages/CatanAI/Sources/CatanAI/Ghost/GhostPolicy.swift`
- Test: `Packages/CatanAI/Tests/CatanAITests/GhostPolicyTests.swift`

**Interfaces:**
- Consumes: `PersonModel` (Task 4), `candidateScores` (Task 1), `StyleFeatures` (Task 2).
- Produces: `public struct GhostPolicy: LedgerAwarePolicy { init(person: PersonModel, lambda: Double, id: String = "ghost") }`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CatanEngine
@testable import CatanAI

@Suite struct GhostPolicyTests {

    /// piKL's promise, at its crudest: a ghost with a strong habit shows it.
    @Test func aStrongHabitDominatesAtHighLambda() {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 83), seed: 83)
        playOpeningPlacements(in: &state, seed: 83)
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].resources = [.brick: 1, .lumber: 1]
        let me = state.players[0].id
        var person = PersonModel.anchored(at: .forMode(.classic))
        person.theta[StyleFeatures.labels.firstIndex(of: "endTurn")!] = 100
        let obs = GameObservation(seat: me, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: me))
        var rng = RandomSource(seed: 1)
        #expect(GhostPolicy(person: person, lambda: 1).decide(obs, rng: &rng) == .endTurn)
    }

    /// The engine term keeps the ghost playing: an anchored person at moderate
    /// lambda finishes a real game with only legal moves. This guards against the
    /// 0/40 collapse of the old imitation policy.
    @Test func aGhostFinishesAGame() throws {
        let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: 84), seed: 84)
        var policies: [PlayerID: any Policy] = [:]
        for p in initial.players { policies[p.id] = EvaluationPolicy() }
        policies[initial.players[0].id] = GhostPolicy(person: .anchored(at: .forMode(.classic)), lambda: 0.5)
        var session = GameSession(state: initial, policies: policies, policySeed: 84)
        _ = try session.run()
        if case .gameOver = session.state.phase {} else { Issue.record("game did not finish: \(session.state.phase)") }
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --package-path Packages/CatanAI --filter GhostPolicyTests`
Expected: compile error, `cannot find 'GhostPolicy' in scope`.

- [ ] **Step 3: Implement**

```swift
import CatanEngine

/// Expert's judgement, pulled toward one person's habits.
///
/// Picks `argmax S_Expert(m) + lambda · (beta · S_person(m) + theta · style(m))`.
/// This is human-regularized search (piKL, Jacob et al. 2022). `lambda` slides
/// from Expert (0) toward the person (large). It is set so the ghost wins as
/// often as the person does, and there it makes the person's kinds of
/// mistakes rather than random ones. The Expert term is what stops the collapse
/// a pure imitation policy showed here (0/40, stopped building).
///
/// `lambda · log Z` is the same for every candidate, so it is dropped.
public struct GhostPolicy: LedgerAwarePolicy {
    public let id: String
    public let person: PersonModel
    public let lambda: Double
    private let expert = EvaluationPolicy()
    private let personal: EvaluationPolicy

    public init(person: PersonModel, lambda: Double, id: String = "ghost") {
        self.id = id
        self.person = person
        self.lambda = lambda
        self.personal = EvaluationPolicy(weights: EvaluationWeights(vector: person.weights))
    }

    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        decide(observation, ledger: .fromPositionAlone(observation.state, observer: observation.seat), rng: &rng)
    }

    public func decide(_ observation: GameObservation, ledger: PublicLedger, rng: inout RandomSource) -> GameMove {
        let legal = observation.legalMoves
        guard legal.count > 1 else { return legal[0] }
        if legal.contains(.rollDice) { return .rollDice }
        let judged = expert.candidateScores(observation, ledger: ledger)
        let habits = personal.candidateScores(observation, ledger: ledger)
        guard !judged.isEmpty else { return legal[0] }
        var best = 0
        var bestValue = -Double.greatestFiniteMagnitude
        for i in judged.indices {
            let style = StyleFeatures.of(judged[i].move, by: observation.seat, in: observation.state)
            let habit = person.beta * habits[i].score + zip(person.theta, style).reduce(0) { $0 + $1.0 * $1.1 }
            let value = judged[i].score + lambda * habit
            if value > bestValue { best = i; bestValue = value }
        }
        return judged[best].move
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --package-path Packages/CatanAI --filter GhostPolicyTests`
Expected: 2 pass. If `aGhostFinishesAGame` hits `GameSession.maxActionsPerTurn` in a loop of proposals, that is a real finding: the ghost re-proposes refused offers. Report it, and do not raise the cap.

- [ ] **Step 5: Commit**

```bash
git add Packages/CatanAI/Sources/CatanAI/Ghost/GhostPolicy.swift Packages/CatanAI/Tests/CatanAITests/GhostPolicyTests.swift
git commit -m "feat(ai): GhostPolicy - Expert's choice regularised toward a person model"
```

---

### Task 6: `ghost` CLI: extract, profile, fit, selftest

**Files:**
- Modify: `Packages/CatanAI/Package.swift` (add the target after `trade-bench`)
- Create: `Packages/CatanAI/Sources/ghost/main.swift`
- Create: `Packages/CatanAI/Sources/ghost/LogFile.swift`
- Create: `Packages/CatanAI/Sources/ghost/Selftest.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `swift run --package-path Packages/CatanAI -c release ghost <extract|profile|fit|selftest> ...`

- [ ] **Step 1: Add the target** to `Package.swift`, after the `trade-bench` line:

```swift
        // A person model from recorded games, and its ghost. Not a product, for
        // the reason `sim` is not.
        .executableTarget(name: "ghost", dependencies: ["CatanAI", "CatanEngine"]),
```

- [ ] **Step 2: `LogFile.swift`.** Read a `GameLogStore` JSONL export without the app target.

```swift
import CatanAI
import CatanEngine
import Foundation

/// The app's `GameLogStore` lines, as far as a replay needs them. Kept apart
/// from the app type on purpose: the app target cannot be imported here, and
/// this reader needs only the start state, the roster's human seats, and the
/// moves. Timestamps are not read.
private struct LogLine: Decodable {
    struct Roster: Decodable { let humanSeats: Set<PlayerID>?; let humanSeat: PlayerID? }
    let kind: String
    let initialState: GameState?
    let roster: Roster?
    let player: PlayerID?
    let move: GameMove?
}

enum LogFileError: Error { case noStart(String), malformed(String, line: Int) }

func loadGame(_ url: URL) throws -> LoggedGame {
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    let decoder = JSONDecoder()
    var start: LogLine?
    var events: [LoggedMove] = []
    for (number, line) in lines.enumerated() {
        guard let parsed = try? decoder.decode(LogLine.self, from: Data(line.utf8)) else {
            throw LogFileError.malformed(url.lastPathComponent, line: number + 1)
        }
        if parsed.kind == "start" { start = parsed }
        if parsed.kind == "move", let player = parsed.player, let move = parsed.move {
            events.append(LoggedMove(player: player, move: move))
        }
    }
    guard let start, let initial = start.initialState else { throw LogFileError.noStart(url.lastPathComponent) }
    let humans = start.roster?.humanSeats ?? start.roster?.humanSeat.map { [$0] } ?? []
    return LoggedGame(id: url.deletingPathExtension().lastPathComponent, initialState: initial,
                      humanSeats: humans, events: events)
}
```

- [ ] **Step 3: `Selftest.swift`.** A known synthetic person plays real games, and the pipeline must find them.

```swift
import CatanAI
import CatanEngine

/// A person who samples from a known `PersonModel`. The recovery test: if the
/// fit cannot find this person's weights and habits in real games, it will not
/// find Jake's.
struct SamplingPersona: LedgerAwarePolicy {
    let id = "persona"
    let person: PersonModel

    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        decide(observation, ledger: .fromPositionAlone(observation.state, observer: observation.seat), rng: &rng)
    }

    func decide(_ observation: GameObservation, ledger: PublicLedger, rng: inout RandomSource) -> GameMove {
        let legal = observation.legalMoves
        guard legal.count > 1 else { return legal[0] }
        if legal.contains(.rollDice) { return .rollDice }
        let scored = EvaluationPolicy(weights: EvaluationWeights(vector: person.weights))
            .candidateScores(observation, ledger: ledger)
        guard !scored.isEmpty else { return legal[0] }
        let logits = scored.map { c in
            person.beta * c.score
                + zip(person.theta, StyleFeatures.of(c.move, by: observation.seat, in: observation.state)).reduce(0) { $0 + $1.0 * $1.1 }
        }
        let top = logits.max()!
        let weights = logits.map { exp($0 - top) }
        var roll = Double.random(in: 0..<weights.reduce(0, +), using: &rng)
        for (i, w) in weights.enumerated() { if roll < w { return scored[i].move }; roll -= w }
        return scored[scored.count - 1].move
    }
}

/// The persona Jake's pipeline has to find: likes production, proposes often, robs the leader.
func selftestPersona() -> PersonModel {
    var person = PersonModel.anchored(at: .forMode(.classic))
    person.weights[1] += 0.25
    person.beta = 4
    person.theta[StyleFeatures.labels.firstIndex(of: "propose")!] = 1.0
    person.theta[StyleFeatures.labels.firstIndex(of: "robberHitsLeader")!] = 1.5
    return person
}

func selftestGames(count: Int, seed: UInt64) throws -> [LoggedGame] {
    try (0..<count).map { n in
        let s = seed + UInt64(n)
        let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: s), seed: s)
        var policies: [PlayerID: any Policy] = [:]
        for p in initial.players { policies[p.id] = HeuristicPolicy(personality: .balanced, id: "balanced") }
        let human = initial.players[n % initial.players.count].id // rotate the chair
        policies[human] = SamplingPersona(person: selftestPersona())
        var session = GameSession(state: initial, policies: policies, policySeed: s)
        var events: [LoggedMove] = []
        while let step = try session.step() { events.append(LoggedMove(player: step.actor, move: step.move)) }
        return LoggedGame(id: "selftest-\(s)", initialState: initial, humanSeats: [human], events: events)
    }
}
```

`import Foundation` in this file too (for `exp`).

- [ ] **Step 4: `main.swift`.** Four subcommands. Games are split for holdout by id: every fourth game in sorted order is held out, so the split is deterministic.

```swift
import CatanAI
import CatanEngine
import Foundation

// A model of one person from their recorded games, and its ghost.
//
// Usage:
//   ghost extract --out decisions.jsonl LOG.jsonl...   (one human seat per game; others skipped)
//   ghost profile decisions.jsonl                        (what this person does, per facet)
//   ghost fit decisions.jsonl --out person.json          (fit on 3/4 of games, report on the held-out 1/4)
//   ghost selftest [--games 12] [--seed 700000]          (recover a known synthetic person)

let anchor = EvaluationWeights.forMode(.classic)
var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail("usage: ghost extract|profile|fit|selftest") }
arguments.removeFirst()

func fail(_ message: String) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }

func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
    defer { arguments.removeSubrange(i...(i + 1)) }
    return arguments[i + 1]
}

func writeDecisions(_ records: [DecisionRecord], to path: String) throws {
    let encoder = JSONEncoder()
    var data = Data()
    for r in records { data.append(try encoder.encode(r)); data.append(0x0A) }
    try data.write(to: URL(fileURLWithPath: path))
}

func readDecisions(_ path: String) throws -> [DecisionRecord] {
    try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
        .map { try JSONDecoder().decode(DecisionRecord.self, from: Data($0.utf8)) }
}

func extract(_ games: [LoggedGame]) throws -> [DecisionRecord] {
    var records: [DecisionRecord] = []
    for game in games.sorted(by: { $0.id < $1.id }) {
        guard game.humanSeats.count == 1 else {
            print("skip \(game.id): \(game.humanSeats.count) human seats; a ghost is one person")
            continue
        }
        let found = try DecisionExtractor.decisions(in: game, anchor: anchor)
        print("\(game.id): \(found.count) decisions")
        records += found
    }
    return records
}

func split(_ records: [DecisionRecord]) -> (train: [DecisionRecord], heldOut: [DecisionRecord]) {
    let games = Array(Set(records.map(\.game))).sorted()
    let heldOut = Set(games.enumerated().filter { $0.offset % 4 == 3 }.map(\.element))
    return (records.filter { !heldOut.contains($0.game) }, records.filter { heldOut.contains($0.game) })
}

func report(_ fitted: PersonModel, heldOut: [DecisionRecord]) {
    let expert = PersonModel.anchored(at: anchor)
    print("facet            n   expert-top1  person-top1  expert-ll  person-ll")
    for facet in Facet.allCases {
        let ds = heldOut.filter { $0.facet == facet }
        guard !ds.isEmpty else { continue }
        print(String(format: "%-14@ %4d   %9.3f   %10.3f   %8.3f   %8.3f", facet.rawValue as NSString, ds.count,
                     expert.top1Accuracy(ds), fitted.top1Accuracy(ds), expert.meanLogLikelihood(ds), fitted.meanLogLikelihood(ds)))
    }
    print(String(format: "beta %.3f", fitted.beta))
    for (label, value) in zip(StyleFeatures.labels, fitted.theta) { print(String(format: "habit %-22@ %+.3f", label as NSString, value)) }
    for (i, label) in EvaluationWeights.vectorLabels.enumerated() where fitted.weights[i] != anchor.vector[i] {
        print(String(format: "weight %-18@ %.4f -> %.4f", label as NSString, anchor.vector[i], fitted.weights[i]))
    }
}

/// Review Focus 5: how far the linearised score is from an exact re-score at the fitted weights.
func linearisationDrift(_ fitted: PersonModel, _ records: [DecisionRecord], games: [LoggedGame]) throws {
    let exact = try games.prefix(2).flatMap { try DecisionExtractor.decisions(in: $0, anchor: EvaluationWeights(vector: fitted.weights)) }
    let linear = records.filter { r in games.prefix(2).contains { $0.id == r.game } }
    var total = 0.0, n = 0
    for (l, e) in zip(linear, exact) {
        for (lc, ec) in zip(l.candidates, e.candidates) { total += abs(fitted.personalScore(lc, anchor: l.anchor) - ec.score); n += 1 }
    }
    print(String(format: "linearisation drift: mean |linear - exact| = %.4f over %d candidates", n > 0 ? total / Double(n) : 0, n))
}

switch command {
case "extract":
    guard let out = option("--out") else { fail("extract needs --out") }
    let games = try arguments.map { try loadGame(URL(fileURLWithPath: $0)) }
    let records = try extract(games)
    try writeDecisions(records, to: out)
    print("\(records.count) decisions -> \(out)")
case "profile":
    guard let path = arguments.first else { fail("profile needs a decisions file") }
    let records = try readDecisions(path)
    for facet in Facet.allCases {
        let ds = records.filter { $0.facet == facet }
        guard !ds.isEmpty else { continue }
        print("\(facet.rawValue): \(ds.count) decisions")
        for (k, label) in StyleFeatures.labels.enumerated() {
            let mean = ds.reduce(0) { $0 + $1.candidates[$1.chosen].style[k] } / Double(ds.count)
            if mean != 0 { print(String(format: "  %-22@ %.3f per decision", label as NSString, mean)) }
        }
    }
case "fit":
    guard let path = arguments.first, let out = option("--out") else { fail("fit needs a decisions file and --out") }
    let (train, heldOut) = split(try readDecisions(path))
    let fitted = PersonFitter.fit(train, anchor: anchor)
    try JSONEncoder().encode(fitted).write(to: URL(fileURLWithPath: out))
    print("trained on \(train.count), held out \(heldOut.count)")
    report(fitted, heldOut: heldOut)
case "selftest":
    let count = Int(option("--games") ?? "12") ?? 12
    let seed = UInt64(option("--seed") ?? "700000") ?? 700_000
    let games = try selftestGames(count: count, seed: seed)
    let records = try extract(games)
    let (train, heldOut) = split(records)
    let fitted = PersonFitter.fit(train, anchor: anchor)
    print("TRUE person:"); report(selftestPersona(), heldOut: heldOut)
    print("FITTED person:"); report(fitted, heldOut: heldOut)
    try linearisationDrift(fitted, records, games: games)
default:
    fail("unknown command \(command)")
}
```

- [ ] **Step 5: Build, then run the selftest**

```bash
swift build --package-path Packages/CatanAI -c release --product ghost
nohup swift run --package-path Packages/CatanAI -c release ghost selftest --games 12 > /tmp/ghost-selftest.txt 2>&1 &
disown
```

Detached, because of the low-memory watchdog (see memory `detached-gate-runs`). When it finishes, read `/tmp/ghost-selftest.txt`.

**Pass criteria (write the real numbers into Task 7's doc):**
- The fitted `propose` and `robberHitsLeader` habits are both positive, and each is at least half its true value.
- The fitted `production` weight moved up from the anchor.
- On `turn`, the held-out person-model log-likelihood beats the anchored model's.
- Linearisation drift is below 0.05 (score units, where 1.0 = one victory point).

If a criterion fails, do not tune until it passes. Report which one failed and by how much; that is the finding. 12 games may be too few. Rerun once at `--games 24` before concluding anything.

- [ ] **Step 6: Lint, then commit**

```bash
swiftlint --strict
git add Packages/CatanAI/Package.swift Packages/CatanAI/Sources/ghost
git commit -m "feat(sim): ghost CLI - extract, profile, fit, and a known-persona selftest"
```

---

### Task 7: Record the result

**Files:**
- Modify: `docs/AI_summaries/2026-09-25-ghost-player-research.md` (append a "Results, phases 1–4" section)
- Modify: `TODO.md:135-137` (point the ghost item at the research doc and state which phases are done)

- [ ] **Step 1:** Append the selftest numbers verbatim: the true vs fitted habits, the per-facet table, and the drift. Add what passed and what did not, plus the exact command for Jake's logs:

```bash
swift run --package-path Packages/CatanAI -c release ghost extract --out jake.jsonl ~/Downloads/GameLogs/*.jsonl
swift run --package-path Packages/CatanAI -c release ghost profile jake.jsonl
swift run --package-path Packages/CatanAI -c release ghost fit jake.jsonl --out jake-person.json
```

- [ ] **Step 2:** In `TODO.md`, append one line to the ghost item: phases 1–4 are built on `feat/ghost-player`, and the next step is Jake's exported logs, then plan 2 (drills, λ calibration, blind test).

- [ ] **Step 3: Commit**

```bash
git add docs/AI_summaries/2026-09-25-ghost-player-research.md TODO.md
git commit -m "docs(ai): ghost pipeline selftest results and how to run it on real logs"
```

Do not push. Landing is a separate decision for Jake: one gate run, per CLAUDE.md.
