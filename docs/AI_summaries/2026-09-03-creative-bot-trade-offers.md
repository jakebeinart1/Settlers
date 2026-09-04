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

## Final whole-branch review fix pass (2026-09-03/04)

A final review of the whole branch (all 8 tasks individually approved) found
one critical and four important issues the per-task reviews above didn't
reach, because none of them crossed package boundaries into the app target
or paired the two new heuristic passes against each other end to end. All
five are fixed; full detail, every command run, and exact output is in
`.superpowers/sdd/2026-09-03-creative-bot-trade-offers/final-review-fix-report.md`.

- **C1 (critical) — save/replay validation would have blocked existing
  in-progress saves.** `MatchCheckpointStore.validateHistory()` replays a
  match's recorded moves through the CURRENT `RulesEngine.apply` and
  compares full-state equality against the persisted snapshot. For any save
  whose history contains a `.respondToTrade(_, false)` recorded before this
  branch shipped, replay under the new rules legitimately populates
  `declinedTradeOffersThisTurn` for the current turn while the old
  snapshot - written by code that never touched that field - has it empty,
  so `replay == state` would fail and the whole document would be marked
  blocked. This is the exact incident class `CLAUDE.md` already documents
  (`tradesAcceptedThisTurn` deleting every in-progress save), reached this
  time through the app-target replay validator that no package-level test
  can see. Fixed with a narrow, `validateHistory()`-only comparison,
  `GameState.matchesForReplayValidationExcludingDeclinedTradeHistory(_:)`
  (`Settlers/Persistence/MatchCheckpointStore.swift`) - checks every field
  `GameState.==` checks except this one, with a regression test in
  `SettlersTests/MatchCheckpointStoreTests.swift`
  (`validateHistoryToleratesADeclinedTradeSnapshotFromBeforeTheFieldExisted`)
  that builds exactly this shape (a real decline in the move history, a
  hand-blanked snapshot) and confirms `validateHistory()` no longer throws.
  `GameState`'s own `Equatable` is untouched - other code (determinism
  tests) may depend on its current strictness.

- **I1 (important) — the generous-unlock pass could escalate to a WORSE
  offer than the ordinary one.** With a 2:1 port, the old
  `giveCount = min(ceiling, max(1, held - 1))` produced 1 (ceiling
  `bestRate - 1 = 1`), while the ordinary pass had already offered 2 of the
  same resource - a guaranteed-worse re-ask that would only burn one of the
  3 per-turn attempts. `generousUnlockOffer` now computes the ordinary
  pass's own give quantity for the same resource
  (`ordinaryGiveCount(for:me:weights:)`, factored out of `ordinaryOffer` so
  both sides share it) and refuses to escalate - returns `nil`, no offer -
  unless the generous quantity genuinely exceeds it.
  `generousUnlockCeilingCollapsesWithAGoodPort` (already existed) now
  asserts the corrected behavior: the second call returns empty rather than
  the old, wrong `[.ore: 1]`.

- **I2 (important) — the per-turn retry cap only counts declines, not
  proposals.** `RulesEngine.maxTradeProposalsPerTurn`'s doc comment claimed
  it gated total proposals; the actual gate
  (`GameSession.decideNextDetailed()`) reads
  `declinedTradeOffersThisTurn[seat].count`, which `Trading.respond` only
  increments on the reject branch - a seat whose offers keep getting
  *accepted* can propose more than 3 times a turn, bounded only by
  `GameSession.maxActionsPerTurn` (25). **Chosen fix: leave the behavior as
  is, fix the doc comment.** A bot that keeps successfully trading isn't the
  same failure mode as one that keeps getting turned down - the constant
  exists to stop the latter (a policy retrying a declined offer forever,
  crowding out `.endTurn`), and it still does. Switching to a
  total-attempts counter was rejected as the higher-risk option for a
  same-day fix pass: it would require either repurposing
  `declinedTradeOffersThisTurn` or adding a second counter, and
  re-verifying every existing test built around decline-only semantics
  (Tasks 5 and 6), for a behavior change nobody had asked for. The doc
  comment on `RulesEngine.maxTradeProposalsPerTurn` now says exactly what
  it gates and why the accepted-trade gap is judged acceptable rather than
  an oversight.

- **I3 (important) — `.claude/skills/sim-harness/SKILL.md` pinned stale
  fingerprints.** Updated to the values currently pinned in
  `SeededGameFingerprintTests.swift`, and actually re-verified against a
  fresh Release build of the `sim` harness (not just copied) - which is how
  the next finding was caught.

- **I4 (important) — TODO.md's flagship example (3 ore for 1 lumber) was
  unreachable.** `generousUnlockOffer` reserved one card
  (`held - 1`) the way the ordinary pass does, but the give resource here is
  by construction one the target doesn't need at all - there's no reason to
  hold a reserve of it. With exactly 3 ore held, the old ceiling collapsed
  to 2, identical to the ordinary offer, so the escalation never fired.
  Changed the reserve to `held` (offer everything). New test
  `generousUnlockOffersAllThreeOreWhenThatsAllThatsHeld` proves the TODO's
  literal example now works. Fixing I1 and I4 together surfaced a real
  interaction: with the reserve widened, a *still-pending* (not yet
  declined) ordinary offer could get "escalated" past by the generous pass
  before anyone had even responded to it, breaking a pre-existing
  regression test (`proposeTradesSkipsWhenIdenticalOfferAlreadyPending`).
  Fixed by adding a third guard: `generousUnlockOffer` requires
  `declined` to be non-empty - it only ever fires after an actual decline,
  never merely because an identical ordinary offer is still awaiting a
  response.

- **I5 (important) — nothing proved a generous offer is ever accepted.**
  New test `aGenerousUnlockOfferIsAcceptedByAPlausibleReceiver` pairs a real
  generous-unlock offer (via `proposeTrades`, after a decline) with
  `TradeHeuristics.evaluate` from a plausible receiver holding a genuine,
  independent need for what's offered. **Finding: accepted.** The
  `acceptUnlockShift` penalty (0.6, applied because a generous-unlock offer
  is by construction an immediate-build-unlock for the proposer) narrows
  which deals clear the bar; it does not block this class of offer
  outright. Verified for both a receiver with a strong independent use for
  the resource and a more neutral one - both accepted the 3-ore-for-1-lumber
  offer. A full `bot-strength` measurement was explicitly out of scope for
  this fix pass.

- **Consequence of I1/I4: one fingerprint re-recorded, not four.**
  `TradeHeuristics.swift`'s corrections are genuine bot-behavior changes,
  and one of the five seeds pinned in `SeededGameFingerprintTests.swift`
  (1234) has a trajectory that passes through a generous-unlock trade. Its
  fingerprint moved from `db3186c153860fc4` to `c07d57fded64e7ae`, confirmed
  identical across three separate processes (two `sim`-harness runs plus
  the test's own process) before being re-pinned; the other four seeds
  (1, 7, 42, 99) are unaffected and unchanged. `sim-harness/SKILL.md`'s
  cross-check line was updated to match.

- **Minor:** `SaveCompatibilityTests.swift`'s comment claiming "the two
  this change introduces" was corrected to name the one field this branch
  actually added (`declinedTradeOffersThisTurn`).

### Fix-pass verification

- `swift test --package-path Packages/CatanEngine` - full suite, PASS.
- `swift test --package-path Packages/CatanAI` - full suite (including the
  re-recorded `SeededGameFingerprintTests`), PASS.
- `SettlersTests/MatchCheckpointStoreTests` (full suite, including the new
  C1 regression test), run via `xcodebuild test -only-testing:` against the
  QA simulator - PASS (10/10 tests).
- `scripts/gate.sh` was **not** re-run for this fix pass, per scope.
