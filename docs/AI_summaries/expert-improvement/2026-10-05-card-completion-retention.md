# Retained Expert card readiness — October 5, 2026

## Decision and evidence

Alex explicitly retained B-002's card-timing change and replaced the fixed
+20-Elo cutoff with improvement supported by a confidence interval at **90%
or higher wholly above zero**. Future levels/samples are declared before new
games run. The shared rule is `.claude/skills/bot-strength/SKILL.md`.

Held-out confirmation: **+18.10 relative Elo, 95% [+9.73, +26.02]** against
Build 16's city-production Expert. All **6,148** games finished: 4,096 primary
(512 seed families, four chairs, reciprocal 1-v-3 / 3-v-1), 1,024 in each
secondary pool and four controls. Balanced-pool focal gain: +3.125 pp
[+0.781, +5.273]; trade-refusing Balanced: +5.078 pp [+2.734, +7.617].
This is a population-relative improvement, not human-level play or a difficulty
ladder. The 95% interval already satisfies the new at-least-90% rule.

Frozen B-002 source: `49548b84188876169bbb6f7041c3b767eaa811e8`; baseline
`38f7885ddfd30deefdfa9b1b3bde7756804f8570`. Original plan and sealed results
retain their +20 rule and `positiveGate=false`; the owner's changed retention
policy is recorded here, not by editing historical evidence. No fallback arm,
combination, extra sample or coefficient tuning was used.

Raw evidence:
`/Users/alex/Library/Application Support/EmpiresResearch/expert-improvement/experiments/B-002/confirmation/`.
Complete result SHA-256:
`d26f3aff17a0a4f42a6b8ecf745d598993c47b5740762f756a225683ad7aa653`.
The eight-arm screen and rejected ideas remain in the isolated research
checkout `/Users/alex/.codex/worktrees/expert-batch2-20261004/Settlers`.

## Exact retained behavior

Keep B-001 city production unchanged. For a legal Year of Plenty or Road
Building play in the observer's main turn, add **Q(after) − Q(before)** to its
ordinary score. Q is the best printed point gain from a directly affordable,
legal city/settlement, or the existing gap to terminal standing for a purchase
that wins. An already open purchase gets no additional credit; an actual
terminal card play keeps its ordinary score. No partial recipe, bank conversion,
future stolen card, opponent holding or new tuning coefficient is included.

The nonretained own-seven discard correction and seven other trial wrappers
are excluded. Diagnostics and actual decisions share `EvaluationPolicy.score`.
Legacy Expert, city-production-only Expert, Classic and Ghost callers keep
their prior paths. Legal masks, trade caps, rules and randomness remain intact.

## Product acceptance criteria

1. New `ExpertRevision.pointCompletingCardsV1` has distinct policy identity
   `evaluation-point-completing-cards-v1`; both revised brains include the
   existing frozen city-production value.
2. Fresh four-seat, single-human, no-Ghost Expert games on **Classic / Standard /
   10 VP / randomized boards** select the new revision. Fixed boards retain
   city production. Other settings retain their existing legacy selection.
3. Existing legacy/city/card saves and restarts preserve the recorded brain,
   seat identities, rules and RNG trajectory. Unsupported revisions or domains
   remain blocked without rewriting bytes. Old archives replay with their
   exact policy IDs.
4. A regression observed failing before the bonus must now select Plenty's
   city-completing pair and permit the native city purchase. Free roads count
   only if they open an affordable legal settlement; exhausted supply,
   pre-roll, discards and hidden-opponent permutations earn no accidental bonus.
5. Production simulator reproduces frozen research trajectories, winner,
   move count, points and behavior after only ID/build-label normalization.
   Current-city baseline remains unchanged. Separate processes are mandatory.
6. Strict lint, Release warnings-as-errors, targeted package/app tests,
   two-axis review, complete gate, native gameplay and inspected Release
   screenshots precede PR/CI and merge. No reduction in gate or coverage floors.
7. Deliver a uniquely numbered, signed Empires build through the established
   TestFlight path; preserve Jake's signing defaults. Verify actual tester
   availability, not merely upload success. Other agents and QA runs serialize.

## Integration status

Narrow source and save wiring implemented on `codex/expert-card-completion-20261005`
in `/Users/alex/.codex/worktrees/expert-city-integration/Settlers`, based on main
`793dfea180ac457be857e2bdea2665e9c5fcdca4` (includes PR #55's UI fixes).
The focused Plenty regression failed before implementation and passes afterward;
12 package tests passed. Shared skill validation and strict SwiftLint passed.
Production parity passed: 72 research/product pairs (144 games), every trajectory,
winner, move count, points and behavior matched after policy-ID normalization
only. The city-only baseline also matched. Artifact: `parity-receipt.json` in
`/Users/alex/Library/Application Support/EmpiresResearch/expert-improvement/deliveries/expert-cards-20261005/`.
Hosted app/save/archive suites passed: 14 test functions, including parameterized
old/new revision and unsupported-domain cases. The post-review rerun passed too.

## Standards

The independent reviewer found one minor duplicated restore/restart assertion
sequence. Both scenarios now use a common helper with byte equality, complete
session/RNG, human identity, roster, recorded brain, board setting, distinct
restart ID and subsequent cold restoration checks. The reviewer confirmed it
resolved, with no remaining concrete issue. No functional finding was reported.

## Spec

The independent reviewer found no actionable issue: exact retained formula,
scope, old brains, Ghost exclusion, archive identities and the confidence-only
rule match the acceptance criteria. Reviews were read-only, not test evidence.

Apple read-only preflight passed; latest uploaded build was 19, VALID. Reserve
Build 20 in `project.yml`, regenerate, and verify the emitted artifact's number.
Remaining: full pre-push gate, PR/CI, merge, native Release verification and
TestFlight availability. Not yet merged or shipped.
