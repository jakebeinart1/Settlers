# H6/H10: robber and road strategy handoff

Audit base: `38f7885ddfd30deefdfa9b1b3bde7756804f8570` (shipped Build 16).
Parent: `/Users/alex/.codex/worktrees/expert-city-integration/Settlers`.
This note supplements [the human-review ledger](2026-10-04-human-review.md).

## Status and ownership

**Proved** below means directly established by source, or explicitly attributed
to a completed frozen experiment. **Unrun** means a proposed counterexample,
not an observed decision or a verified fixture. No new road/robber experiments,
builds, package tests, gate or simulator tests were run for this audit. Screens
`/Users/alex/Downloads/IMG_1703.PNG`, `IMG_1705.PNG` and `IMG_1699.PNG` supplied
review context only: they do not identify the policy/revision, reconstruct a
whole game, establish intent behind a road, or prove a robber choice was wrong.

The separate Expert owner continues experiments in other worktrees. Main owns
stall reproduction, production integration and verification. No strategic
formula, Expert revision, RNG/rules, or other agent's files were changed here.
The H4 implementation is app-owned interruption policy, not a strength claim.

## H6: existing robber terms and actual gaps

Source evidence in the parent (line anchors describe the audited source):

- `Packages/CatanAI/Sources/CatanAI/Planner/ProductionModel.swift:93-111`:
  production includes token probability, city yield two versus settlement one,
  and zero yield beneath the robber. A city on eight loses `2 * 5/36 = 10/36`
  expected cards per roll; the same city on two loses `2 * 1/36 = 2/36`.
  **Proved:** Expert does not simply omit token weights or city production.
- `Packages/CatanAI/Sources/CatanAI/Evaluation/PositionEvaluator.swift:48-61`:
  evaluate own standing minus weighted maximum rival standing. `:74-85` includes
  economy/hand/bonus terms; `:167-168` uses public VP for rivals and actual VP for
  self. **Proved:** public points and own blocked production already affect the
  evaluation, but the highest-public-VP opponent need not be its strongest rival.
- `Packages/CatanAI/Sources/CatanAI/Evaluation/EvaluationPolicy.swift:308-321`
  applies the candidate using the real engine, then folds masked events into the
  ledger and reconciles the observer's hand.
  `Packages/CatanEngine/Sources/CatanEngine/Robber.swift:55-64`
  builds the real victim hand and samples a card with the copied engine RNG.
  **Proved:** projected steals use a particular true-hand/RNG outcome, not an
  expectation over the public belief. The full-state observation limitation is
  explicitly documented in `Packages/CatanEngine/Sources/CatanEngine/GameSession.swift:5-20`. Whether it
  changes a reported choice is **unrun**; do not label a screenshot proof of it.
- `Packages/CatanAI/Sources/CatanAI/RobberHeuristics.swift:66-104`: Classic uses
  city/settlement counts and threat, excludes own-adjacent tiles when alternatives
  exist, then chooses a threat-ranked victim. Its disruption term does not weight
  the token. **Proved:** a Classic diagnosis cannot be attributed to Expert without
  checking the realized opponent profile and saved Expert revision.

### Prioritized counterexamples (all unrun)

1. **R1 — single-outcome steal sensitivity.** Construct two robber positions
   with identical board, public points, hand sizes, legal tile/victim candidates
   and supplied public ledger. Permute only hidden victim resource identities;
   separately vary the copied engine RNG. Compare actual selected move and each
   candidate score. Keep at least one card in every eligible victim's hand so
   candidate legality cannot explain a difference. Quantify the production-only
   part, resulting stolen card, build unlocked, hand delta and rival maximum.
   This can locate an information/projection root cause without changing weights.
2. **R2 — eight versus two, then own collateral.** Start with equal buildings,
   resource type and victim/steal opportunity, no own adjacency, and identical
   old-robber relief. Use a city on eight versus a city on two; verify the blocked
   rates above before checking the move. Next add an own settlement/city on the
   eight target. Trace production newly blocked AND production restored at the
   old robber location. Quantify net own loss, each rival loss and full score;
   do not turn "eight always wins" into a rule when collateral differs.
3. **R3 — public leader versus maximum-standing rival.** Place equivalent
   production targets beside a public-VP leader and a lower-VP, richer opponent.
   Record each opponent's standing before/after and which one controls the
   maximum. Vary public VP through an engine-valid fixture while keeping the
   compared targets fixed. Test score behavior near a maximum-rival switch.
   **Hypothesis:** blocking a non-max rival may have little/no immediate rival
   subtraction benefit; choosing the nominal leader is not inherently correct.
4. **R4 — tier/candidate provenance.** Run the same explicit fixture through
   the realized Classic policy and saved Expert revision. List engine-legal
   tile/victim pairs, excluded pairs, actual pick and tie handling. Establish
   whether token-insensitive Classic, a missing candidate, a tie, or the Expert
   projection explains the complaint before considering a strategy intervention.

H6 product acceptance: legal tile/victim choice, no omitted city/token/own-loss
accounting, explainable leader/steal tradeoffs, and no future revision silently
changing a saved old Expert. Any claim to eliminate hidden-hand sensitivity
needs a public-ledger invariance test; the existing full-state contract is not
itself proof that this invariant currently holds.

## H10: existing road filters and independent incentives

- `Packages/CatanAI/Sources/CatanAI/Evaluation/BoardIndex.swift:86-107` filters
  approached destinations by distance rule, occupancy, remaining settlement
  pieces and road pieces. `:110-139` does bounded, sorted traversal, excluding
  opposing roads/buildings. **Proved:** simply adding a distance-rule filter
  repeats existing behavior. It is not yet proved that a particular chosen road
  had a destination at all, or that every path witness satisfies the engine.
- `Packages/CatanAI/Sources/CatanAI/Evaluation/PositionEvaluator.swift:194-210`
  considers approached settlement production within four roads, discounted per
  road. `:315-322` independently credits engine Longest Road length linearly.
  **Proved:** raw length credit does not require an attainable award or a legal
  settlement destination. Award VP is a different term.
- `Packages/CatanAI/Sources/CatanAI/Evaluation/HandDiscipline.swift:28-37`
  marks road building as spending above the discard threshold;
  `EvaluationPolicy.swift:165-175` can replace an otherwise selected end turn
  with the best spending move. **Proved mechanism, unrun complaint attribution:**
  discarding avoidance can select a road with poor strategic purpose.

### Prioritized counterexamples (all unrun)

1. **D1 — impossible award plus no settlement benefit.** Construct an
   engine-legal network with a legal own road extending length four to five,
   no reached/approached legal settlement sites, and a rival length-15 holder
   that cannot be cut from this network. At the Classic 15-road piece limit,
   tying the holder cannot win the award. Supply eight cards: two each brick,
   lumber, grain and wool; no useful ports, point purchase or remaining proposal
   attempts. Confirm these assertions with engine legality/Longest Road, not
   hand-drawn adjacency. **Constructability is not yet proved.** Compare end
   turn versus each legal road, then seven-card and achievable-award controls.
   Quantify raw-length benefit, all hand/discard/economy deltas, actual move,
   HandDiscipline override and cards spent on roads with no productive endpoint.
2. **D2 — distance-blocked apparent destination.** Pick an attractive empty
   vertex adjacent to an occupied vertex. Assert it is absent from approached
   sites before AND after each legal road. Add an independently legal productive
   destination as a control. Trace site IDs/distances and actual road choice.
   If the blocked target never appears, diagnose D1/incentive terms; do not call
   its destination filter broken from the road's direction alone.
3. **D3 — reachable-site path witness.** For each reported approached vertex,
   construct the claimed free-edge path and apply its roads through the engine
   on a copied state, then attempt the settlement. Vary opponent blocking,
   distance occupancy, one remaining road, exhausted settlements and narrow
   coastal networks. A witness failure isolates a topology/filter bug; zero
   witnesses plus positive road score isolates an incentive instead. Do not
   conflate geometry with being able to afford road plus settlement now.
4. **D4 — opportunity cost and completion.** On valid D1/D2 positions compare
   spending on a road versus preserving a settlement/city recipe. Quantify later
   point purchases, purposeless roads, end turns above seven, refused proposals,
   turn length and action-cap hits. A road veto that only shifts behavior to
   endless trades or harms attainable expansion is a symptom patch, not success.

H10 product acceptance: excluded distance-rule destinations stay excluded,
claimed paths have engine-valid witnesses within piece supply, and impossible
award investment has an explicit diagnostic explanation. Preserve valuable
multi-road expansion and attainable contests. A broad "all roads without an
immediate settlement are bad" rule is not an acceptable consequence.

## Frozen negative trials: avoid repeating them

Historical evidence is in another worktree, not produced by this audit:

- [B-001 results](/Users/alex/.codex/worktrees/expert-strategy-trial-20261003/Settlers/docs/AI_summaries/expert-improvement/B-001-RESULTS.md:26):
  funded approach **−16.3 Elo, 95% interval [−38.0,+5.4]**; road race
  **−10.0 [−33.5,+11.8]**, with secondary regressions. These rejected their
  intended +20 improvement; they do not prove every targeted alternative fails.
- [Frozen expansion definition](/Users/alex/.codex/worktrees/expert-strategy-trial-20261003/Settlers/docs/AI_summaries/expert-improvement/BATCH-EXPANSION.md):
  funded approach already replaced geometric discount with a complete
  road-plus-settlement public production/bank-conversion clock. It ignored
  current hand, bank timing, integer batches and intervening production changes.
  Reviving "include the whole cost" with the same clock is not a new hypothesis.
- [Frozen race definition](/Users/alex/.codex/worktrees/expert-strategy-trial-20261003/Settlers/docs/AI_summaries/expert-improvement/BATCH-RACES.md):
  road race already replaced raw length with bounded contest credit, strict
  rival+one target, physical-piece ceiling, remaining supply and an available
  legal edge. It was not an exact multi-road route proof. Repeating its attainable
  contest adjustment would repeat a failed arm, even if D1 passes.
- Frozen source/tool commit: `35ba23806c4a41d410c19678b18071f3ae5df23f`.
  Artifacts and source receipts:
  `/Users/alex/Library/Application Support/EmpiresResearch/expert-improvement/experiments/B-001/`.
- [C-001 results](/Users/alex/.codex/worktrees/expert-strategy-trial-20261003/Settlers/docs/AI_summaries/expert-improvement/C-001-RESULTS.md:17):
  compatibility of the unchanged city-production candidate, **not a road trial**.
  Randomized Classic/Conquest missed the secondary guard (−3.91pp against
  Balanced); Vast cells were incomplete or timed out, including baseline in
  Vast/Conquest. They are not evidence for a global road/robber replacement.

## Next narrow seam and experiment gates

Proposed disjoint files in the Expert owner's worktree, subject to its existing
reservations: `Packages/CatanAI/Tests/CatanAITests/RobberDecisionDiagnosticsTests.swift`
and `RoadDecisionDiagnosticsTests.swift`. First build small engine-valid
fixtures and a test-only trace of the EXISTING evaluator/filter path. No new
formula is proposed here. Candidate behavior changes, if justified, remain
versioned experiments in that owner's worktree, not integration edits here.

Trace: profile/revision/weights identity, actor/phase, legal candidates, actual
filter rejection reasons, public ledger, per-seat before/after standing,
strongest-rival identity, blocked/restored production, engine road lengths,
approached-site witnesses, total candidate score, tie handling, HandDiscipline
override and actual selected move. `Ghost/CandidateScoring.swift:11-20` explicitly
includes offers Expert would never choose; its highest score is not proof of
the actual policy pick. Use the actual decision path plus these diagnostics.

Verification order for the other owner (all prospective, none run here):

1. Mechanism fixtures R1/R2 and D1/D2, then engine path witnesses D3. Reject
   invalid constructions rather than treating a fabricated state as a legal game.
2. Same fixture/seed across separate processes; stable ordering, bounded runtime
   and hidden-information perturbation tests. Pin old-revision move behavior;
   do not rewrite old expectations to make a new strategy pass.
3. Freeze candidate and anchor source/binaries/hashes. Preregister effect size,
   seeds, chairs, opponents, cells, caps/timeouts, completion and regression gates.
   Held-out paired seeds, every occupied chair, separate three/four-seat strata
   and all-Greedy/identical-policy controls; never pool table sizes/configurations.
4. Report intervals and completion receipts plus behavior measures. Keep a
   second opponent and trade-refusing tables. B-001's historical retention gate
   was ≥20 Elo point gain, primary interval above zero, all games complete and
   neither secondary point loss >3pp. A new experiment must lock its own gate
   before results, not tune until it passes those historical numbers.
5. Incomplete/cancelled/timed-out cells remain unscored; no post-hoc timeout
   increase or margin-at-cap winner. Mechanism improvement alone is not a
   strength claim; positive self-play alone is not human UX acceptance.

## H4 module/load contract for main

`Settlers/Models/HumanTradeOfferPolicy.swift` and its tests are the only owned
production code here. Main owns checkpoint/view-model/view wiring. Bank
suppression compares exact one-resource quantity at the HUMAN's export rate
and available stock of the SAME received resource; equal price is suppressed.
Rejection classes and interruption budgets remain separate from Expert strength.

Load uses the throwing contextual validator, after checkpoint history/roster
validation, before runtime decision methods:

```swift
try policy.validate(for: match.state, expectedHuman: realizedHuman,
                    committedMoves: match.moves.map(\.move),
                    initialOffers: match.initialState.pendingTradeOffers)
```

The no-argument validator is structural only, not a substitute for that call.
Negative counts, invalid limits/seat, incoherent counters, duplicate/reordered
occurrences, invented IDs/future indices, wrong-turn occurrences and damaged
refusal ratios throw rather than invoking runtime preconditions. Older untouched
accounting is legitimate; future counters are not. Exposure/tap origin cannot be
reconstructed from engine moves, so valid saved presentation counts are retained.

`Context.proposalSequence` is a zero-based committed proposal index; `-1` alone
denotes an inherited initial-state offer, whose ID must match `initialOffers`.
The sentinel is not index zero, cannot be used after turn zero, and must not
legitimize an unknown unlogged offer. This preserves migrated/QA pending offers
without inventing proposal history. Distinct inherited IDs can share the sentinel;
an actual later identical proposal remains a separate occurrence.

`isPresented(offer:context:)` is a pure query on the durably published policy,
not on an unpublished reservation copy. Policy-managed UI requires durable
presentation accounting. Suppression must apply/commit its real
`.respondToTrade(..., accept: false)` before clearing an offer or advancing.
On write failure retain live offer/session/policy and show the persistence
blocker. `.notIncoming` is delegated to existing legacy negotiation/presentation;
it is NOT a hide-only suppression result. Expiry is not an explicit preference.

`SettlersTests/HumanTradeOfferIntegrationTests.swift` exercises real pending
proposal cold resume, durable/idempotent reservation, bank suppression response,
explicit versus expiry cross-resource/bot rejection, beforeReplace failures,
old JSON missing metadata, legacy `.notIncoming`, and inherited initial offers.
Damaged-policy cold-load cases verify rejection without replacing original bytes.
All test declarations are **unrun by this agent**; lint is not compilation or
runtime proof. Main owns serial app-target compilation/tests and UI verification.
