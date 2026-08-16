# Bot threat assessment & leader-aware strategy

Date: 2026-08-16
Status: Approved for implementation

## Background

`Packages/CatanAI` (`Bot.swift`, `BuildPlanner`, `TradeHeuristics`,
`RobberHeuristics`, `DevCardHeuristics`, `PlacementHeuristics`) already
scores candidate moves with personality-weighted heuristics. This is
TODO.md's open "Bot strength" item.

Today only `RobberHeuristics` reasons about opponents relative to each
other, and it does so crudely: "leader" = whoever has the most victory
points among opponents, given a flat 3x disruption weight. Trading,
building, and dev-card play don't consider opponents' relative standing
at all.

Research into existing Catan bots ([JSettlers][jsettlers], the long-running
Java reference AI, and [Catanatron][catanatron], a modern Python
alpha-beta bot) confirms the standard approach: a single reusable
per-player evaluation function (weighted sum of VP, production,
development, road position) that every decision consults, rather than
each subsystem inventing its own notion of "who's ahead." We adopt that
pattern here, scoped to this codebase's existing heuristic architecture
(no search/lookahead - see Non-goals).

[jsettlers]: https://github.com/jonzia/Catan
[catanatron]: https://github.com/bcollazo/catanatron

## Goals

- Replace the binary "leader" concept with a **threat score for every
  opponent**, so bots can react proportionally (a close three-way race
  doesn't get skewed onto whoever's nominally 1 VP ahead; a dominant
  player draws sharply more attention than a slight one).
- Threat reflects not just current VP but **how dangerous a player is
  about to become** - production strength, hidden dev cards, and
  proximity to grabbing Largest Army / Longest Road (each worth a
  sudden +2 VP swing).
- Extend leader-aware play from robber-only to **robber, building
  (settlements + roads), trading, and dev cards (Monopoly)**.
- Keep every move legality-checked through the existing
  `RulesEngine.legalMoves` / `matchLegal` contract - heuristics only
  ever suggest, `Bot.swift` still validates.

## Non-goals

- No minimax/alpha-beta search or multi-turn lookahead (Catanatron's
  strongest mode). The current architecture scores each legal move
  once, in isolation; this project stays within that model and only
  changes *how* moves are scored. A search-based rewrite is a
  substantially larger project and not needed to address the specific
  weaknesses being targeted here.
- No change to `TradeOffer` to support player-directed trades (it has
  no `to` field - offers are open to all players). Leader-awareness on
  the trade side is therefore accept/reject-only (see below), not
  "offer worse deals to the leader."
- No UI/debug surface for threat scores. Internal to `CatanAI`.

## Design

### 1. `ThreatAssessment` (new file)

```swift
public enum ThreatAssessment {
    /// Threat score for every player except `excluding`, highest first.
    public static func scores(excluding player: PlayerID, in state: GameState) -> [(player: PlayerID, score: Double)]

    /// `scores`'s weight for `target` relative to the average opponent -
    /// 1.0 means "exactly as threatening as the average opponent."
    /// Consumers multiply their existing effect by this instead of a
    /// flat leader/non-leader constant. Returns 1.0 for every opponent
    /// when all scores are 0 (e.g. pre-placement) to avoid a divide-by-zero
    /// cliff at the start of the game.
    public static func relativeWeight(for target: PlayerID, excluding player: PlayerID, in state: GameState) -> Double
}
```

`score(for:in:)` (private, backs `scores`):

```
score = 10.0 * victoryPoints(for: player)
      + productionStrength(player)      // sum of PlacementHeuristics.score(vertex:)
                                         // across settlements, x2 per vertex for cities
      + 1.5 * player.devCards.count     // hidden threat - unplayed knights/VP/etc.
      + milestoneSwingBonus(player)
```

`milestoneSwingBonus` catches "about to become dangerous":
- **Largest Army**: if `player` doesn't already hold it, has exactly 2
  played knights, and the current holder (if any) has <= 2 played
  knights, add `2.5` - one more knight would take/claim the +2 VP
  bonus.
- **Longest Road**: if `player` doesn't already hold it, and
  `LongestRoad.length(for: player, in: state)` is `>= max(4, holderLength)`
  (one more segment would tie-or-beat the minimum-5 threshold and the
  current holder), add `2.5`.
- Both can apply at once (a player can be one move from either bonus
  simultaneously).

`relativeWeight` divides each opponent's score by the mean opponent
score (excluding `player`), clamped to `[0.4, 3.0]` so a single
early-game outlier (e.g. first settlement placed) doesn't produce an
extreme swing, and floors to `1.0` uniformly when the mean is `0`.

### 2. Robber (`RobberHeuristics`) - refactor

- Add a `personality: BotPersonality` parameter to `chooseRobberTarget`
  (update the two call sites in `Bot.swift` and `DevCardHeuristics`).
- Replace the flat `weight = (other.id == leader?.id) ? 3 : 1` in
  `disruption(_:)` with
  `weight = 1 + ThreatAssessment.relativeWeight(for: other.id, excluding: player, in: state) * personality.aggressiveness * 2`,
  so disruption naturally scales with both relative threat and how
  aggressive this bot is.
- Victim selection (`occupants.first(where: leader?.id)` fallback) uses
  `scores(excluding:in:)` sorted order restricted to `occupants` instead
  of a single `leader`.

### 3. Building (`BuildPlanner`) - denial bonus

New helper, `denialBonus(vertex:board:state:player:)`:
- A vertex is in an opponent's "frontier" if it's adjacent (via
  `board.adjacentVertices`) to an edge that opponent could legally road
  into from their existing road network, mirroring the `bestReachable`
  computation `.buildRoad` scoring already does for the bot's own
  spots.
- For every opponent whose frontier contains the candidate vertex, add
  `PlacementHeuristics.score(vertex:) * 0.4 * relativeWeight(for: opponent, ...)`.
  Denying a strong player's good spot is worth close to half of what
  taking it yourself for production is worth; denying a weak player's
  frontier barely moves the score.
- Added to `.buildSettlement`'s existing score.

Roads get the same treatment plus a longest-road-specific term:
- Existing `claimsLongestRoad` bonus (2.5) is kept, but scaled up
  slightly (`* (1 + relativeWeight(for: currentHolder))`) when building
  this edge would take the bonus *away* from a currently-threatening
  holder, not just grant it fresh.
- Add a `blocksLongestRoad` bonus: if this edge occupies a vertex/edge
  that sits on the *only* extension of a high-threat opponent's current
  longest path (i.e. removing this edge from their reachable frontier
  would cap their `LongestRoad.length`), add a bonus scaled by that
  opponent's `relativeWeight`.

### 4. Trading (`TradeHeuristics`) - accept-side caution

`evaluate(offer:receiver:state:personality:)` raises its threshold using
the proposer's relative threat:

```swift
let proposerWeight = ThreatAssessment.relativeWeight(for: offer.from, excluding: receiver, in: state)
let threshold = max(0, 0.5 - personality.tradeWillingness) * proposerWeight
```

A trade from a far-above-average-threat player needs a proportionally
better deal to accept (since accepting hands them resources); a trade
from a below-average player keeps roughly today's bar.
`proposeTrades`/`bestBankTrade` are unchanged (see Non-goals).

### 5. Dev cards (`DevCardHeuristics`) - Monopoly targeting

`opponentTotal(_:state:player:)` becomes threat-weighted:

```swift
state.players.filter { $0.id != player }.reduce(0.0) { partial, opponent in
    partial + Double(opponent.resources[resource] ?? 0) * ThreatAssessment.relativeWeight(for: opponent.id, excluding: player, in: state)
}
```
(return type changes `Int` -> `Double`; the `>= 3` affordability gate
in `choosePlay` compares against `3.0`.) Picks the resource that hurts
the highest-threat holders most, not just whoever holds the most in
raw total.

## Testing

- `ThreatAssessmentTests.swift`: score formula components in isolation
  (VP weight, production weight, dev card count, each milestone-swing
  condition individually and combined), `relativeWeight`'s clamping and
  zero-mean fallback.
- Extend `RobberHeuristicsTests`, `BuildPlannerTests`,
  `TradeHeuristicsTests`, `DevCardHeuristicsTests` with cases asserting
  the new leader-aware behavior (e.g. robber prefers the higher-threat
  of two occupied tiles; Monopoly picks the resource the higher-threat
  opponent holds).
- `FullBotGameSimulationTests` / `BotLegalityTests` must keep passing
  unmodified - they're the safety net that every suggested move stays
  inside `RulesEngine.legalMoves`.

## Personality interaction

`aggressiveness` already scales the robber's leader-reaction; this
carries it into the new relative-weight multiplier there and is *not*
separately re-introduced into building/trading/dev-card weighting for
this pass, to avoid over-parameterizing before there's evidence the
simpler version needs it (YAGNI). Can be revisited once
`FullBotGameSimulationTests`-style play testing shows a personality
isn't differentiating enough.
