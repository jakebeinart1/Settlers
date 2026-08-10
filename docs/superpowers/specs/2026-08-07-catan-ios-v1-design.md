# Settlers of Catan — iOS Single-Player (1v3 Bots) — v1 Design

**Date:** 2026-08-07
**Status:** Approved

## Goal

Build a native iOS Settlers of Catan game, single-player only, where the human plays against 3 AI-controlled opponents ("bots") in a standard 4-player game. Visual style and feel inspired by colonist.io: clean, modern, flat, legible. The bots should play *well* — smart, rule-aware, believable opponents — not naive random-move AI.

## Non-Goals (v1)

- No expansions (Seafarers, Cities & Knights, etc.) — base game only.
- No online multiplayer, accounts, or cloud sync.
- No MCTS/simulation-based AI — heuristic bots only for v1 (architecture should not preclude adding a stronger AI tier later).
- No physical device deployment / TestFlight — iOS Simulator only for now (no paid Apple Developer account yet).

## Architecture

Three-layer Swift package structure inside one Xcode project:

1. **`CatanEngine`** (Swift Package, zero UI dependencies)
   - Board model: hex tiles, vertices (settlement/city spots), edges (roads), ports, robber.
   - Board generation: standard fixed layout, plus a randomized/shuffled-but-balanced layout mode.
   - `GameState`: players, resources, dev cards, buildings, roads, current phase/turn, dice, bank.
   - Turn/phase state machine: setup phase (initial placements), main phase (roll → produce → build/trade → end), robber-on-7 interrupts, dev card play windows.
   - Rules engine: legal-move generation for every action type (build road/settlement/city, buy/play dev card, propose/accept/reject trade, move robber, discard on 7, bank/port trade), longest road calculation, largest army, win condition (10 VP).
   - Deterministic given a random seed — enables reproducible tests and reproducible bot evaluation.
   - `Codable` conformance on `GameState` for persistence.

2. **`CatanAI`** (Swift Package, depends on `CatanEngine` only)
   - Bot decision-making built entirely on `CatanEngine`'s public legal-move API — bots do not get privileged access to hidden engine internals beyond what the rules allow (no cheating by seeing opponents' hidden dev cards, etc., except where Catan rules allow probabilistic inference).
   - Heuristic scoring functions per decision type:
     - Placement value (pip count / production diversity / port access / blocking) for initial settlements and city upgrades.
     - Build priority (road vs settlement vs city vs dev card) based on current resource mix, VP progress, and game phase.
     - Robber placement (maximize opponent disruption, avoid self-harm).
     - Trade evaluation (accept/reject/counter incoming offers; decide when to propose trades) based on resource marginal value to the bot's current build plan.
     - Dev card play timing (knight for robber control / largest army race, road building, monopoly, year of plenty).
   - 3 distinct weight profiles ("personalities") so the 3 bots don't play identically.
   - Bots act through the exact same engine move-submission API a human action does — no special-cased "bot path."

3. **`CatanApp`** (SwiftUI iOS app target, depends on `CatanEngine` + `CatanAI`)
   - `GameViewModel` (`@Observable`): owns the single source-of-truth `GameState`, applies moves from either human taps or bot decisions, drives auto-save.
   - Views:
     - Main menu / new game setup (toggle randomized board on/off, start game).
     - Game screen: hex board (SwiftUI `Canvas` for tile/road/settlement geometry, overlaid interactive SwiftUI views for tap targets and animations), player resource/VP HUD for all 4 players, build menu, trade sheet (bank/port + propose-to-bot), dev card hand/play panel, dice roll display, turn indicator, game log/event feed.
     - Robber/discard modal flows.
     - End-game screen (winner, final stats).
   - Bots take turns automatically with a short "thinking" delay and visibly animated actions (not instant), so games feel legible and paced like a real match.
   - Visual style: flat-shaded hexes, crisp vector resource/piece icons, bright saturated per-resource colors, minimal chrome — colonist.io-like.

## Data Flow

```
User tap / Bot decision
        │
        ▼
GameViewModel.apply(move:)
        │
        ▼
CatanEngine validates + mutates GameState
        │
        ▼
GameViewModel publishes updated state → SwiftUI re-renders
        │
        ▼
Auto-save GameState (Codable → JSON on disk)
```

Bots run their decision logic (`CatanAI`) against a read-only snapshot of `GameState` + the engine's legal-move generator, then submit the chosen move through the same `apply(move:)` path as the human.

## Persistence

`GameState` is `Codable`. After every state-changing action, the view model serializes it to JSON and writes to the app's Application Support directory. On app launch, if a saved game exists, resume it; otherwise show the main menu. No cloud sync in v1.

## Testing

- `CatanEngine`: unit tests (Swift Testing) covering rules correctness — longest road recalculation on road removal/branching, dev card purchase/play timing, robber-on-7 discard thresholds, win condition, trade legality, board generation validity.
- `CatanAI`: unit tests asserting bots make legal moves in all reachable states, plus scenario tests asserting sane behavior (e.g., a bot one settlement from winning prioritizes that path).
- No UI tests planned for v1 (manual verification via Simulator).

## Repo / Workflow

- Git repo initialized locally, remote `origin` set to `https://github.com/jakebeinart1/Settlers.git`, default branch `main`.
- Commit and push to `main` after every major change, per user's standing instruction.

## Open Items for Later (explicitly out of scope now)

- MCTS/stronger AI tier.
- Expansions.
- Real-device / TestFlight distribution.
- Multiplayer/online.
- Full hand-drawn/vector resource icon set (the "crisp vector resource icons... colonist.io-like" constraint). Task 16 added SF Symbol stand-ins (`CatanTheme.symbolName(for:)`) to the trade sheet's give/want pickers so resources are no longer text-only there, but tiles are still flat-color fills with no per-resource icon, and a true custom vector icon set (matching colonist.io's actual art) was judged out of proportion for a v1 polish pass.
- Bot auto-reject of pending trade offers can pre-empt a human (or another bot). `Bot.decideMainTurn`'s lowest-priority fallback (`Bot.swift`, added in Task 16) has a bot actively reject any pending trade offer it doesn't want once it has nothing better to do that turn. `Trading.respond` removes a rejected offer from `state.pendingTradeOffers` for *everyone*, not just the rejecting bot - so if bot A proposes an offer and bot B (the next player to act) doesn't want it, bot B's reject can clear the offer before the human, or bot C, ever gets a chance to see and accept it on their own upcoming turn. This is a deliberate tradeoff, not a bug: without it, an offer nobody wants but nobody explicitly rejects sits in `state.pendingTradeOffers` forever (surviving every `endTurn`), which is what caused the Task 16 bot trade-loop hang (see the report's bug #2). A more sophisticated fix - e.g. only auto-rejecting after some grace period, or only when it's clear no other player will get a turn to act on the offer soon - would be a reasonable follow-up if this ever proves annoying in practice.
