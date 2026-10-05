# H6/H10 strategy mechanism evidence — October 4, 2026

Status: **focused mechanism suite executed successfully; no strategy change**.
This is a mechanism handoff, not a strategy fix, strength estimate, or replay
of the reported screenshots.

Checkout: `/Users/alex/.codex/worktrees/expert-city-integration/Settlers`.
Observed HEAD: `7a77640ea9ed6e7a1d087bdc686d412800721c0a`, branch
`codex/human-review-20261004`. Production AI/engine sources had no working-tree
diff at the initial audit. At final checking, concurrent edits appeared in
`Ghost/DecisionExtractor.swift` and `Ghost/DecisionRecord.swift`; they belong
to the parent/other owner and were not touched or reviewed by this task.
The parent also owns unrelated app changes in this checkout.
This task writes only this note and
[`HumanReviewStrategyDiagnosticsTests.swift`](../../Packages/CatanAI/Tests/CatanAITests/HumanReviewStrategyDiagnosticsTests.swift).
No formula, coefficient, candidate-generation, revision, harness, experiment,
or default was changed. Other Expert worktrees and artifacts were read only.

## Source-proved

### Confirm the brain before interpreting a robber or road

[`BotDifficulty.policy`](../../Settlers/Models/BotDifficulty.swift) selects
`HeuristicPolicy` for Classic difficulty and `EvaluationPolicy` for Expert.
Classic **mode** does not imply Classic **difficulty**. Expert has no strategic
personality axis. The diagnostic policy always explicitly selects a revision:

| Revision | Policy ID | Additional standing feature |
| --- | --- | --- |
| `legacy` | `evaluation-v1` | None |
| `cityProductionV1` | `evaluation-city-production-v1` | `0.7 * min(oreProduction / 3, grainProduction / 2)` |

[`MatchSetup.newMatchExpertRevision`](../../Settlers/Persistence/MatchSetup.swift)
selects the city revision for fresh Expert, Classic-mode, standard-variant,
10-VP, four-seat, one-human, no-Ghost matches. Other configurations and absent
saved revision metadata use legacy. Resume uses the persisted revision.
[`ExpertRevision.swift`](../../Packages/CatanAI/Sources/CatanAI/Evaluation/ExpertRevision.swift)
and the match checkpoint are the identity authorities. The complaint's actual
difficulty, revision, pre-move state, and ledger have **not** been recovered;
the screenshots cannot establish them. Both production revisions are covered
by the new fixture diagnostics.

### H6: city production and self collateral already reach the decision

[`ProductionModel.rate`](../../Packages/CatanAI/Sources/CatanAI/Planner/ProductionModel.swift)
counts settlements once, cities twice, and excludes the robber's tile.
[`PositionEvaluator.standing`](../../Packages/CatanAI/Sources/CatanAI/Evaluation/PositionEvaluator.swift)
uses that rate for every seat, including the robber mover. Expert evaluates
ordinary robber candidates by applying the engine move, folding masked ledger
events, and evaluating the resulting position. The engine enumerates every
other tile and every eligible victim; there is no Expert-only preference for
a two-token tile in that enumeration.

Arithmetic confirmed by engine-applied fixture tests:

| Controlled tile | Production suppressed per roll |
| --- | ---: |
| One settlement on a two | `1 * 1/36 = 0.0277778` |
| Two cities on an eight | `4 * 5/36 = 0.5555556` |
| Mover's own city on that eight | `2 * 5/36 = 0.2777778` self loss |

The first two differ by a factor of 20. Multiplying by Classic's existing
production weight, `0.4601`, gives `0.0127806` versus `0.2556111` in a seat's
direct production component. Those are **not candidate score differences**:
variety, city-recipe bottleneck, hands, sites, and the rival comparison also
matter. The city revision earns no extra grain credit when ore is already the
city bottleneck. Port ownership receives flat port-count credit; placing the
robber does not remove access to the port. Sustainable production conversion
through that port is not a separate robber feature in this evaluator.

The objective is own standing minus `weights.rival` times the **maximum rival
standing**, recomputed after each move. Standing includes public points and
economy, not just public VP rank. Blocking a rival below that maximum may give
no rival-side benefit if the maximum remains unchanged. Conversely, blocking
the strongest rival can switch which rival is the maximum and limit the gain.
This is a structural explanation worth testing, not proof of why the reported
robber moved to a two. Own hidden VP counts; rival hidden VP faces do not.

Steals are a separate confound: `EvaluationPolicy` explicitly documents that
it applies the real seeded steal when pricing a candidate, allowing the drawn
resource to influence its score. The fixtures separate empty hands from
single-card victim hands. Single-card hands remove draw ambiguity but do not
test mixed-hand information leakage or fix it.

### H10: geometric legality exists; economic/race justification is separate

[`BoardIndex`](../../Packages/CatanAI/Sources/CatanAI/Evaluation/BoardIndex.swift)
already rejects occupied/adjacent building sites and exhausted settlement
supply. Approaches use additional-road distance, cap it by remaining road
pieces, exclude opponent roads, and do not seed or traverse opponent buildings.
The evaluator sees at most four additional roads and discounts site production
by `0.5^distance`. These are geometric options, not a funded acquisition plan:
the term does not include settlement cost, hand affordability, resource-specific
funding, rival timing, or the possibility of a later city returning a settlement
piece. An exhausted settlement supply therefore removes expansion credit even
when a later upgrade could reopen it.

[`Building.canBuildRoad`](../../Packages/CatanEngine/Sources/CatanEngine/Building.swift)
can legally let a road end at an opponent building. It forbids extending
through that building. A legal road thus need not be a settlement route.
[`LongestRoad`](../../Packages/CatanEngine/Sources/CatanEngine/LongestRoad.swift)
uses continuous trail length, cuts at opposing buildings, and preserves a
holder on a tie. It does not confuse total road inventory with chain length.

The evaluator independently adds `longestChainLength * roadLength`, regardless
of settlement options, bonus holder, rival length, or attainable contest.
Classic weights credit **0.0888 per additional chain edge** before any actual
bonus. A rival holding a 15-edge chain cannot be beaten with Classic's 15-road
supply: tying it retains their award. Building an extra own chain edge can
still receive the 0.0888 component. This proves an incentive exists, **not**
that the full policy chooses the road or that removing it improves play.

[`HandDiscipline`](../../Packages/CatanAI/Sources/CatanAI/Evaluation/HandDiscipline.swift)
and `EvaluationPolicy.best` can independently force spending: only when the
unrestricted best move is End Turn, the hand exceeds the discard threshold,
and a scored spending candidate exists, choose the best spending candidate.
There is no requirement that it beat passing. Under that condition the policy
can accept a negative score margin to obey the product rule. The rule is
Jake's explicit requirement, not an authorization to disable it. The on/off
controls in this suite are diagnostic policy instances only.

## Measured fixture evidence

The parent executed the focused suite on October 4 at 23:01 EDT. It passed
with the Ghost provenance suite: 14 test declarations across two suites,
including every parameterized diagnostic case, in 0.325 seconds after build.
Receipt: `/tmp/empires-human-review-strategy-focused.log` (exit 0).

- Both Expert revisions selected the grain-eight city tile when blocking it
  caused no self collateral, with and without the controlled one-card steal.
  With the mover's own city on that eight, both selected the two instead.
  This demonstrates a real self-harm trade-off, not a missing city multiplier;
  it does not reconstruct Alex's reported position.
- The independent engine-road oracle agreed on barriers, legal detours,
  distance-rule sites, exhausted/returned settlement supply, and road supply.
- Both revisions built the affordable reachable settlement in its fixture.
- Both revisions chose a road despite no available settlement sites and an
  unbeatable rival's 15-edge road. The chosen connection added two chain edges;
  its existing linear road credit was 0.1776. It beat passing by 0.017675 with
  seven cards and 0.081825 with eight. Disabling hand discipline did not alter
  those choices: the position score itself preferred the road in this fixture.
  This prioritizes unjustified chain credit for the separate Expert owner;
  it does not establish a replacement formula or measured strength gain.

The frozen suite has 11 test declarations, intended to yield 16 parameterized
test cases (the two revisions run inside each relevant case). It uses complete
Classic board geometry and on-board edges; no invented corridor edges or
screenshot coordinates. A terrain-face swap preserves resource/token bags and
red-token spacing to create an eight-grain tile touching an existing port.
Fixtures assemble partial positions, with setup phases explicitly staged and
resource endowments transferred from the bank. Placements and subsequent
purchases go through the engine. These are spatial/legal mechanism fixtures,
not claims that a full four-player game generated the positions naturally.

| Fixture/check | Intended evidence after execution |
| --- | --- |
| Two cities on eight versus settlement on two | Exact production suppression; port access unchanged |
| Own city on shared eight | Own probability × city-yield loss reduces own standing |
| Robber choices, collateral on/off, steals on/off | Both revisions' actual choice over the complete legal mask; target candidate scores and per-seat standings/rates |
| Public army holder; hidden VP/private leader contrast | Public versus private leader information remains separate; rival hidden faces/deck order cannot change evaluation with the same ledger |
| Three-edge spatial route | Additional-road distance falls 2 → 1 → current legal site |
| Rival settlement/city on a route | Opponent through-point blocked; real detour remains available |
| Rival road on a route | Occupied edge cannot become an own shortcut |
| Five settlements, then one city upgrade | Exhausted supply hides sites; returned piece restores actual routes |
| Fourteen/fifteen own roads | Approaches respect one/zero remaining road pieces |
| Affordable reachable settlement | Actual Expert choice converts a real site into a public point |
| Five settlements plus rival 15-edge holder, own hand 7/8 | Legal choice and score margins with discipline off/on; no attainable road award and no settlement sites |

Approach comparisons use an **independent bounded engine oracle**: enumerate
actual legal road purchases up to two moves, ask `Building.canBuildSettlement`
at each resulting position, record minimum purchase count, and remove sites
already legal at distance zero. It does not duplicate BoardIndex's BFS.
Current sites are compared against the engine over all on-board vertices.

Trace lines start `H6H10`. They include policy ID, selected move/score,
per-seat public points/standing/resource production/public bank rates, selected
and inspected candidates, card delta, chain-length delta, existing linear road
credit, and resulting site/approach counts. Road cases compare scores with End
Turn and print whether discipline actually changed a passing choice. Candidate
scores use the existing API; bank-trade scores can include purchase-unlock
credit, so the printed chain component is not a decomposition of their full
score. A robber case has no End Turn, so `deltaVsEnd` there uses the selected
score as its reference. The diagnostics require legal application and finite
scores; they do **not** require a two-target choice, a wasted road, or a negative
spending margin to remain forever. A later improvement may change those traces
without breaking the regression contracts.

## Frozen B-001 context — prior evidence, not rerun here

Read the separate trial's `B-001-PLAN.md`, `B-001-RESULTS.md`,
`BATCH-EXPANSION.md`, and `BATCH-RACES.md` under:
`/Users/alex/.codex/worktrees/expert-strategy-trial-20261003/Settlers/docs/AI_summaries/expert-improvement/`.
The race definition was also checked directly with `git show` at frozen
research commit `35ba23806c4a41d410c19678b18071f3ae5df23f`.

The prior report rejected funded approach and road race as meeting the locked
meaningful-improvement requirement; road race also failed secondary opponent
guards. Those results are about the exact tested replacements, not every
funding/race idea and not proof that the current choices are ideal. Productive
ports was inconclusive. Only city production was retained and then integrated
as its explicit revision. This task does not revive those flags, retune their
constants, reproduce population outcomes, or make a new stronger/Elo claim.

## Prioritized counterpart for the other Expert owner

1. **Attribute H6 on a captured decision before changing robber weights.**
   Recover difficulty/revision, phase, prior robber tile, complete mask, public
   buildings/bonuses/ports, own hand, and observer ledger. Compare the selected
   two with the eight's legal target/victim pairs using the existing APIs.
   Identify whose standing is maximal before/after, self production released
   from the old tile, collateral on the new tile, and the steal. Validate the
   maximum-rival blind spot on positions with equal theft/self effects and a
   third public leader; these controlled fixtures alone cannot establish it as
   the screenshot's cause. Avoid adding a missing-city multiplier: it exists.

2. **Classify H10 as voluntary length credit or forced spend-down.** Run the
   paired hand-7/8 traces and record selected road/bank/passing margins, actual
   length increase, real sites, returned-piece possibilities, and bonus upper
   bound. A negative road chosen only with discipline on calls for evaluating
   the spending alternatives under Jake's rule. A road already best with the
   rule off points toward position valuation. Neither result by itself selects
   a replacement formula. Preserve invariant tests when traces improve.

3. **Use legality-oracle discrepancies as bugs; investigate funding/race only
   after they pass.** If BoardIndex diverges from engine-applied routes, repair
   the concrete discrepancy in the appropriate owner task. If it agrees, the
   complaint is about investment value or future opportunities, not missing
   distance-rule filtering. Do not assume `currentLength + remainingPieces`
   proves a contest impossible: one connecting road can join two components.
   The fixture's rival-15 versus total-supply-15 bound avoids that mistake.

4. **New economic/race changes need new evidence and a new revision.** Existing
   B-001 funded-approach/road-race replacements did not earn promotion. A new
   hypothesis should explain how it differs, preserve terminal wins and privacy,
   and cover scarcity, barriers, fragmented networks, holder ties, and beneficial
   city upgrades. Any later strength comparison belongs to the other Expert
   owner's frozen, held-out, rotated evaluation, not this diagnostic suite.

## Commands and remaining verification limits

The diagnostic subagent performed no builds. The parent then granted one
compiler slot and executed:

```sh
swift test --package-path Packages/CatanAI --jobs 2 \
  --filter 'HumanReviewStrategyDiagnosticsTests|GhostTrainingProvenanceTests'
```

After a successful build, an optional second process can replay this same
suite without compiling again; do not claim cross-process agreement from two
iterations inside one test process. This repeat is also **NOT RUN**:

```sh
swift test --package-path Packages/CatanAI --skip-build \
  --filter HumanReviewStrategyDiagnosticsTests
```

If the parent uses the full gate, this file is discovered by the existing
CatanAI test target; no package/project changes are required. Keep its ordinary
SwiftPM scratch path unless the parent deliberately chooses isolation. Do not
start another package process while the slot is occupied.

Strict SwiftLint and `git diff --check` passed. The focused command establishes
compile compatibility, spatial fixture/oracle assertions, actual policy choices
and rule-on/off margins. A separate-process repeat, rated simulations, and
attribution to the historical screenshot remain unperformed. No stronger-bot
claim or strategy promotion is licensed by these mechanism checks.
