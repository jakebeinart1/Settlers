# Creative bot trade offers

Closes both boxes of `TODO.md` section 4. Full design rationale:
`docs/superpowers/specs/2026-09-03-creative-bot-trade-offers-design.md`. Task
breakdown: `docs/superpowers/plans/2026-09-03-creative-bot-trade-offers.md`.
Ledger of what actually happened while executing it (preflight scan, every
task's review outcome, both cross-cutting findings this plan surfaced and
fixed): `.superpowers/sdd/2026-09-03-creative-bot-trade-offers/progress.md`.

## What changed

**1. Retry after decline.** `TradeHeuristics.proposeTrades`
(`Packages/CatanAI/Sources/CatanAI/TradeHeuristics.swift`) used to compose
exactly one offer per turn and give up for good once it was declined. It now
retries with a genuinely different offer (different give resource and/or
quantity) up to `RulesEngine.maxTradeProposalsPerTurn` (3: one initial
proposal plus two retries) total proposals per player per turn. A new
`GameState.declinedTradeOffersThisTurn: [PlayerID: [TradeOffer]]` field
(mirrors `tradesAcceptedThisTurn`'s shape and turn-reset lifecycle) tracks
what's already been tried, so `proposeTrades` stays a pure function of state
rather than depending on session-local memory. This also let
`GameSession.Checkpoint` drop its own single-shot `proposedTradeThisTurn`
gate entirely — one less piece of session-local state to keep in sync across
resume, in the same spirit as keeping `RandomSource` inside `GameState`
rather than threading it through `apply`.

The retry count is not personality-scaled; that was a deliberate
simplification, left for a future pass if evaluation ever shows a style-axis
reason to vary it.

**2. Generous unlock trades.** A bot sitting on 3 ore and missing exactly one
resource for a settlement — its best available move — previously wouldn't
offer those 3 ore for the 1 it needed unless that was already favorable in
isolation (i.e. never, by construction: giving up a genuine surplus for one
pivotal card is not "worth more to me" standing alone). The heuristic now
escalates give-quantity for that specific target after its ordinary
candidates have all been proposed and declined this turn, scoped to
**settlement and city only** (the two targets `enablesImmediateBuild`
already privileges elsewhere in this file), and **bounded by the bank/port
rate**: the generous give-quantity is capped at
`Trading.bestRate(for: give, player: me, state: state) - 1` — always at
least one card better than the bank/port would already give the bot for
free. With no port that ceiling is 3 (bank rate 4); with a 3:1 port, 2; with
a 2:1 port, 1 (no room to be "generous" at all — the port already is).

This is a two-*pass* design, not a one-*branch* toggle: pass 1 walks
ranked, value-filtered give candidates at the ordinary 1-2 quantity
(today's behavior, generalized across a list); pass 2 (settlement/city
only) escalates *quantity* — not favorability, which pass 1's candidates
already cleared — and is reached only once every pass-1 candidate for this
target has already been proposed-and-declined this turn. The generous offer
is therefore an escalation after an ordinary decline, not a bot's first
move — both logically necessary (an unconditional favorability branch turned
out to be unreachable on a fresh call, see below) and closer to the intent
behind it: reach further only once the ordinary asks haven't worked.

Enabling this required widening `RulesEngine.tradeProposals`'s enumerated
give-quantity range (new `RulesEngine.maxGenerousGiveQuantity` constant, 3)
and `ActionSpace`'s `.proposeTrade` encode/decode range to match — otherwise
`Bot.swift`'s legality check would silently drop any offer above the old
cap, or `ActionSpace.mask(for:)` would trap on the first give-quantity-3
proposal during self-play. `ActionSpace.layoutVersion` moved 1 → 2 and its
pinned size assertion moved from 9,295 to 9,335 to reflect the wider
encoding.

## Two cross-cutting findings this plan surfaced (and fixed) along the way

This did not execute as a clean linear sequence of eight independent tasks.
Two real problems only became visible once later tasks ran suites earlier
tasks hadn't touched:

- **A load-bearing design bug caught before implementation.** The
  originally-drafted algorithm gated the generous path behind a
  `requireFavorable: Bool` toggle on the same candidate-selection branch as
  the ordinary path. Hand-tracing it against `Building.settlementCost` and
  `resourceValue` showed the "favorable" branch trivially wins for any
  genuinely-surplus give resource, so the generous branch could never be
  reached on a fresh call — contradicting the test this same plan specified,
  which expected an immediate `.ore: 3` offer. Caught during the plan's
  preflight scan, before Task 6 was ever dispatched, and redesigned as the
  two-pass structure described above.
- **Two pre-existing tests went stale mid-plan, and neither CatanEngine nor
  any earlier task's suite would have caught it.** Only `CatanEngine`'s
  tests ran during Tasks 1-5 (widened enumeration + the new propose-trade
  gate); nobody ran the full `CatanAI` package suite until Task 6, where two
  failures turned up: `SeededGameFingerprintTests.seededSelfPlayReproducesExactly`
  (all 5 pinned seeds) and `PolicyTests.aRejectedOfferIsNotRepeatedInTheSameTurn`.
  Bisecting by hand (`git checkout` to the end of Task 5) confirmed both
  already failed *before* Task 6 touched anything — real consequences of
  Tasks 3 and 5 changing the legal-move space, not a Task 6 regression, and
  not a determinism bug: `seededSelfPlayReproducesExactly` was re-run twice
  in separate processes at both the old and new commit, and each commit's
  fingerprint was internally consistent across processes (the file's own
  documented cross-process protocol). The five fingerprints were
  re-recorded to their new, confirmed-deterministic values, and the
  `PolicyTests` case — which had literally encoded the *old* one-proposal-
  per-turn behavior this plan explicitly replaces — was rewritten to assert
  retry-then-eventually-end-turn instead. A third stale literal
  (`TrainingExampleTests.swift`'s hardcoded `actionCount == 9_295`) turned up
  the same way and was fixed the same mechanical way.
- A plan-mandated review finding (`TradeHeuristics.proposeTrades` landing at
  75 lines against this repo's ~30-line guideline) was fixed with a
  behavior-preserving extraction into two private helpers rather than
  accepted as a known violation.

## Verification

Both package suites (`CatanEngine`, `CatanAI`) pass in full as of the final
commit, and the two determinism guards (`DeterminismTests`,
`SeededGameFingerprintTests`) were re-run explicitly and pass unchanged.

`scripts/gate.sh` was also run in full — its raw top-line verdict on that
one run was **`gate: FAILED`**, not a clean pass, with two `FAIL` stages:

- **`evaluation tooling`** — `python3 -m unittest discover -s scripts/tests`
  failed 2 of 58 tests (then a further 1 on re-check), all on stale
  Python/`sim`-binary mirrors of the `ActionSpace` layout bump this plan
  made on the Swift side (`layoutVersion` 1→2, size 9,295→9,335): a pinned
  fingerprint literal, a hardcoded `actionCount`, and `validate-training-data.py`'s
  own `ACTION_LAYOUT_VERSION`/`ACTION_COUNT` constants. This task's own
  commits `f202941` and `09b7901` are the fix — root-caused and applied
  during this same verification task, then reverified at 58/58 passing.
- **`app tests`** — `SettlersUITests.GameplayBoundaryFlowTests.testIncomingOfferSurvivesAppRelaunch`
  failed inside the full 180-test run. Re-run in isolation on the same
  simulator, it passed cleanly in 24s; the fixture code it exercises
  (`Settlers/Testing/GameViewModel+QATrade.swift`) is untouched by every
  task in this plan. Ruled a pre-existing simulator-load flake, not a
  regression — the full 180-test app-tests stage was deliberately not
  re-run at full scale afterward, an explicit cost/benefit call given its
  ~62-minute runtime.

Every other gate stage passed (`xcodegen drift`, `packages build`,
`CatanEngine`/`CatanAI` tests, `training export`, `coverage floors`,
`app build (Release)`); `swiftlint --strict` and `gitleaks` reported `SKIP`
(tool not installed in this environment), and `app build (Debug)` reported
`SKIP` (not requested). See
`.superpowers/sdd/2026-09-03-creative-bot-trade-offers/task-8-report.md`
for the full stage-by-stage breakdown, exact commands, and output.
