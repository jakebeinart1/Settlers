# Conquest Mode — Design

**Date:** 2026-09-23
**Status:** Rules agreed with Jake in conversation; awaiting spec review.
**Branch:** `feat/conquest-mode`

## Goal

A mode that is new, fun and tests the player: **territory**. Every hex starts
held by a neutral tribe. Players buy army cards, take hexes from the tribes and
from each other, and whoever holds a hex takes all of its production.

The test is economic nerve. Armies need all five resources and give no victory
points, so every card is a settlement or city not built. Hands are hidden, so
you never know what a rival can throw at you next turn.

Conquest is a **rule layer over a board**, not a board. It plays on Classic or
Vast. `GameMode` stays about board size and quantities; Conquest is a separate
switch beside it.

## Non-goals

- **No civilization powers, doubles re-rolls, tier-2 development cards or
  "own all three settlements" bonus.** All were discussed and deferred; each can
  be its own mode later.
- **No victory points for territory.** The production is the reward.
- **No troop movement.** Your hand is your army.
- **No out-of-turn play.** Every Conquest action happens on your own turn.
  There is no defender response window.
- **No plunder.** Beating a tribe gives the hex, nothing else.
- **No change to the training encodings.** `StateEncoding` and `ActionSpace`
  refuse a Conquest state, as they already refuse non-Classic modes.
- **Minimal visuals.** Enough UI to play and to test. The art pass is its own
  project, after the rules are proven.

## Rules

### Army cards

| | Classic board | Vast board |
|---|---|---|
| cost | **any 3 resource cards**, chosen by the buyer (revised 2026-09-24) | same |
| deck | 29 cards, strengths **1-4** (revised 2026-09-24, below) | 58 cards (each count doubled) |

Classic deck, by strength: `1×5, 2×5, 3×4, 4×4, 5×3, 6×3, 7×2, 8×2, 9×1`.
Mean strength ≈ 4.0. Weighted low so a 9 is an event, and finite so the table can
count cards: once the 9 is spent, everyone knows it is gone.

1. **Buying** draws the top card of the shuffled army deck. An empty deck cannot
   be bought from.
2. **Your hand is hidden.** Everyone sees how many army cards you hold, and how
   many remain in the deck; nobody sees strengths but you.
3. **A card cannot be played the turn it is bought**, as with development cards.
   No buy-and-strike out of nowhere.
4. **Army cards do not count toward the discard limit on a 7.**
5. **Starting card.** When setup ends, every player is dealt one army card,
   playable on their first turn.

### Garrisons

Every hex carries a garrison: an **owner** (a player, or the tribe) and a
**strength**, both visible to everyone.

- **Tribes.** At game start every producing hex is held by a tribe whose strength
  is its number's pip count: `2/12 → 1`, `3/11 → 2`, `4/10 → 3`, `5/9 → 4`,
  `6/8 → 5`. The desert has no garrison and cannot be occupied.
- **Unoccupied.** A hex whose garrison was beaten to exactly zero belongs to no
  one and has strength 0.

### Deploying (your turn, after rolling, any number of times)

Deploy one or more army cards from your hand to a hex **that one of your
settlements or cities touches**. The cards are spent; only the number remains.

- **Your own hex → reinforce.** Garrison strength rises by the cards' total.
- **Anyone else's hex, a tribe's, or unoccupied → attack.** The cards' total is
  subtracted from the garrison.
  - **Result below zero:** you take the hex. Your garrison is the overflow
    (attack 9 into a 5 leaves you holding it at 4).
  - **Exactly zero:** the hex becomes unoccupied.
  - **Above zero:** the defender keeps it, weakened.

There is no limit on how many hexes one player holds. Price is the brake.

### Production (the takeover)

When a hex's number is rolled:

| Hex state | Who collects |
|---|---|
| tribe-held or unoccupied | everyone, as normal |
| occupied by a player | **only the occupier's buildings**, plus **+1 bonus** of that resource |
| robber on it | nobody, no bonus |

The bonus is paid only if the bank can supply it, under the existing shortage rule.
Why a bonus as well as the block: blocking alone pays the occupier nothing, so a
card spent occupying was estimated (by hand, not simulated) to be a wash, while the two bystanders gained
for free. The +1 makes a card spent on a hex pay for itself.

### Revisions after first play (Jake, 2026-09-24)

- **Deck is strengths 1-4**: `1×7, 2×8, 3×8, 4×6` (mean ~2.45). Tribes keep their
  pip-count strengths (up to 5), so no single card takes a 6 or 8 and holding one
  takes several cards to break.
- **A card may be deployed the turn it is bought.** The same-turn rule below is
  withdrawn; a buy-and-strike can now come without warning.
- **The buyer chooses the 3 cards paid.**

The trained-Expert balance below was measured on the 1-9 deck with the same-turn
rule; it needs re-measuring on these rules.

### Price revision (2026-09-24)

The original price, one of each resource, was measured dead: a trained Expert that plays
only to win bought 0.1 army cards a game. Any one card was the opposite failure: a seat
refusing armies won 6.5% (null 25%), a single meta. **Any three cards** leaves refusing
armies viable (24.8%) while the table buys ~11 cards and makes ~4.5 takeovers a game, and
seats win at similar rates across 0, 1-3 and 4-7 cards bought - several routes, not one.
The engine chooses which three: biggest pile first. Evidence:
`docs/AI_summaries/2026-09-23-conquest-expert-price.md`.

## What we expect to happen (hypotheses, to measure)

- Turns 1–5 are a race against tribes: the dealt card takes a 2, 3, 11 or 12; a
  6 or 8 needs saving or combining.
- Covering all five resources in setup becomes a real opening, competing with
  "best numbers". Ports, especially 2:1, gain value.
- Player-versus-player fights start when someone takes a shared 6 or 8.
- **Risk:** the first player to hold a shared 6 or 8 snowballs. Brakes if it
  does, in order of preference: raise the price, flatten the deck, add upkeep.

## Architecture

### State

- `GameState.variant: GameVariant` — `.standard` or `.conquest`, `String`-raw,
  decoded with default `.standard`. Kept apart from `mode` for the same reason
  `mode` is a tag: a save cannot carry an incoherent combination, and Conquest
  crosses every board.
- `GameState.garrisons: [HexCoordinate: Garrison]`, where
  `Garrison { owner: PlayerID?; strength: Int }` (`nil` owner = tribe). Empty for
  `.standard`.
- `GameState.armyDeck: [Int]` and `Player.armyCards: [Int]`, plus a
  `armyCardsBoughtThisTurn` record mirroring `devCardsBoughtThisTurn`.
- **Every new field decodes with a default**, `schemaVersion` goes to 5, and a
  `SaveCompatibilityTests` case covers a version-4 save.

### Quantities

The deck composition goes on `Ruleset` as `armyDeck: [Int: Int]`, with a Classic
default, so Vast's doubled deck is data, not a branch.

### Moves

Two new `GameMove` cases:

- `.buyArmyCard`
- `.deployArmy(to: HexCoordinate, strengths: [Int])` — reinforce or attack is
  decided by who owns the hex, so the engine has one move and the UI has one
  gesture.

`legalMoves` cannot list every subset of a hand (it grows as 2ⁿ). It lists, per
eligible hex, a bounded set of candidates: each single card, and the smallest
subset that takes the hex. `apply` validates **any** subset the hand actually
holds, so the UI is not limited to the enumerated candidates.

### Determinism

- The army deck is shuffled with `state.rng`, and **only when `variant ==
  .conquest`**. A standard game must draw exactly the same random sequence as
  today; `SeededGameFingerprintTests` must pass unchanged.
- Garrison walks go through sorted coordinates, never dictionary order.

### Hidden information

A bot must not read a rival's `armyCards`. The rival's hand **count** and the
spent cards are public; `PublicLedger` gains army-card entries so the bot
estimates what is left from what has been seen, as a human would.

### Bots (`CatanAI`)

Three decisions, heuristic, no training:

1. **Buy?** Weigh an army card against the best build, by the production it would
   swing.
2. **Where to deploy?** Value a hex as (occupier's gain + rivals' loss) × pips,
   and prefer a hex the bot can take outright over chipping one.
3. **How much?** Send the smallest set that wins; reinforce a held hex when a
   rival's visible hand could plausibly break it.

Expert's fitted weights are Classic-only. Conquest bots start from Balanced
heuristics and are measured, not tuned, in this project.

### App

- New Game: a **Conquest** toggle beside the board choice.
- Board: the owner's colour rings the hex's number token (Jake, 2026-09-23: "a simple
  approach"); tribes get no ring. Strength sits beside the token.
- Hand: army card count and strengths in the player panel; count only for bots.
- Deploy: tap a hex, pick cards, confirm — using the existing confirmable
  board-action pattern (`2026-09-04-confirmable-board-actions.md`).

## Testing

- **Engine:** one test per rule above: tribe strengths from pips, desert
  un-occupiable, adjacency required, overflow capture, exact-zero unoccupied,
  reinforce, same-turn play refused, discard exemption, starting card dealt,
  takeover production, robber blocks bonus, bonus under bank shortage.
- **Determinism:** fingerprint tests unchanged for standard games; a seeded
  Conquest game replays identically across processes.
- **Saves:** version-4 save loads as `.standard`.
- **Balance, via `sim-harness`:** seeded bot games on both boards reporting
  (a) win rate of the first player to hold a shared 6 or 8, (b) army cards bought
  per game, (c) round of first player-versus-player attack. The snowball risk is
  confirmed or cleared by (a).
- **UI:** one XCUITest that buys, deploys and sees the badge change.

## Open questions for tuning (not blockers)

- The deck composition and the 1-of-each price are first guesses.
- Whether Vast needs more than a doubled deck: it has 3.2× Classic's hexes.
