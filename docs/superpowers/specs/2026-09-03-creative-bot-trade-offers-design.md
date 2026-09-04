# Creative bot trade offers — design

Implements TODO.md section 4 ("Creative bot trade offers"). Decisions below were
made with Jake over three rounds of clarifying questions; each is recorded with
the reasoning so a future reader doesn't have to re-derive it.

## Problem

`TradeHeuristics.proposeTrades` (`Packages/CatanAI/Sources/CatanAI/TradeHeuristics.swift`)
composes exactly one trade offer per turn, toward the nearest-blocked build
target, and only if it's favorable to the proposer (`resourceValue(ask) >
resourceValue(give)`). Two gaps, both from `TODO.md`:

1. **No retry.** Once declined, the offer is gone (`Trading.respond` removes it
   from `pendingTradeOffers` on reject same as accept) and nothing regenerates
   a different one — `proposeTrades` returns the *same* offer every subsequent
   call (guarded against only for the identical-and-still-pending case), so a
   declined trade just means the bot gives up on trading this turn.
2. **Never self-unfavorable, even to unlock its own best move.** A bot sitting
   on 3 ore and missing exactly one resource for a settlement won't offer the
   3 ore for it unless that ask is independently worth more than the ore —
   i.e. never, since giving up a genuine surplus for a single pivotal card is
   by definition not "worth more to me" in isolation.

## Decisions

**Retry count:** up to 3 total proposals per player per turn (1 initial + 2
retries), gated by a new `RulesEngine.maxTradeProposalsPerTurn` constant. Not
personality-scaled — kept simple; revisit if evaluation shows a style-axis
reason to.

**Retry variety:** each retry must be a genuinely different offer (different
give resource and/or quantity), not a resubmission of what was just declined.
Tracked via a new `GameState.declinedTradeOffersThisTurn: [PlayerID:
[TradeOffer]]` field (mirrors `tradesAcceptedThisTurn`'s shape and turn-reset
lifecycle) so `proposeTrades` stays a pure function of state.

**Generosity scope:** only for the two highest-value targets — settlement and
city (matches the scope `enablesImmediateBuild` already uses elsewhere in this
file) — and only when that target is the nearest-blocked one (the bot's
"current best move" proxy the file already computes via
`nearestBlockedTarget`). A generous road/dev-card trade isn't worth the
complexity.

**Generosity bound — the load-bearing decision.** Jake's framing: a bot should
never give up a worse ratio than the bank/port would already give it for free
— "you'd never go 4 different cards for 1 of the same kind, because you could
just trade the bank for that; but you'd go further than the normal 1-2 card
range if it's genuinely better than what the bank offers you and it unlocks
real value." Concretely: the generous give-quantity is capped at
`Trading.bestRate(for: give, player: me, state: state) - 1` — always at least
one card better than the player's own best available bank/port rate for that
resource. With no port that's 3 (bank rate 4); with a 3:1 port, 2; with a 2:1
port, 1 (no room to be "generous" at all — the port already is). This is
strictly the *quantity* dimension; give/want stay single-resource-pair (no
multi-resource bundles) — matches the file's existing architecture and
`RulesEngine.tradeProposals`'s enumeration shape. Multi-resource bundling is
explicitly out of scope for this pass.

This keeps the new ceiling at a fixed constant (3, the no-port case) rather
than "uncapped" — genuinely unbounded quantity can't be decoded by
`ActionSpace.move(at:)`, which reconstructs a move from a bare index with no
access to a player's live resource holdings; encoding "give however many I
hold" would require threading live resources through every `ActionSpace`
call site, which is a materially larger, separate change. A fixed ceiling of
3 fits the existing fixed-size encoding with a small, symmetric-in-spirit
widening of the give dimension only (want stays at the existing 2).

**Scope — human and bot-to-bot both.** `proposeTrades` doesn't distinguish
trade partner type today and shouldn't start; the retry/generosity logic
applies uniformly.

## What does NOT change

- `TradeHeuristics.evaluate` (accept/reject an *incoming* offer) — unaffected;
  this work is entirely about what a bot *proposes*.
- Bank/port trades (`bestBankTrade`) — unaffected; the whole point of the
  generosity bound is comparing against this, not changing it.
- `maxEnumeratedTradeQuantity` (want-side quantity bound, currently 2) — stays
  2. Only the give side gets the wider `maxGenerousGiveQuantity` (3) range.

## Cross-cutting surface (why this touches more than one file)

- `GameState` gains a field → schema version bump, `SaveCompatibilityTests`
  case, `init(from:)` default.
- `RulesEngine.tradeProposals` must enumerate the wider give range or
  `Bot.swift`'s `matchLegal` (strict containment against `legal`) silently
  drops any offer `TradeHeuristics` composes above the old cap.
- `ActionSpace`'s `.proposeTrade` segment size/encode/decode must widen with
  it, or `mask(for:)` traps via `preconditionFailure` the first time a bot
  proposes a give-quantity-3 offer during self-play/training.
- `GameSession`'s `proposedTradeThisTurn` (session-local, checkpointed) — the
  single-shot "already proposed, don't ask again" gate — is replaced by
  reading `state.declinedTradeOffersThisTurn[seat].count` against
  `maxTradeProposalsPerTurn` directly off persisted state, which also removes
  session-local trade-turn bookkeeping from `GameSession.Checkpoint`
  entirely (one less thing to keep in sync across resume, in the same spirit
  as keeping `RandomSource` in `GameState` rather than threading it through
  `apply`).

See `docs/superpowers/plans/2026-09-03-creative-bot-trade-offers.md` for the
task breakdown.
