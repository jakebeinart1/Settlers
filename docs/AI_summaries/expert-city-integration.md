# Expert city-production integration — October 4, 2026

## Scope and acceptance

Promote only the independently confirmed city-production feature into Jake's
current `EvaluationPolicy` Expert, not into Classic/Balanced. The unchanged
addition to each seat's standing is `0.7 * min(oreProduction/3, grainProduction/2)`.
It rewards an economy that can repeatedly pay for cities rather than valuing
surplus ore or wheat independently. Existing weights, trade logic, hand
discipline, legal moves and personality/dialogue are unchanged.

- New four-seat Classic/10-VP/Standard Expert matches without Ghost chairs
  select the versioned city-production policy, on fixed and randomized boards.
- Classic difficulty, Conquest, Vast, legacy table sizes/targets, hot-seat and
  Ghost tables retain the previous policy. No unsupported global rollout.
- Persist the realized Expert revision alongside difficulty in `MatchSetup`.
  An absent revision decodes as legacy. Unknown revisions fail recovery without
  rewriting the original save. Resume and Restart keep the stored revision.
- Checkpoints carry the distinct policy ID; recorded replay stays move-based.
  Ghost fitting and inference retain the unchanged default Expert evaluator.
- Keep the existing Expert leaderboard identity. This is a revision of Expert,
  not a new tier; evidence remains version-specific, not a human Elo claim.
- Match the frozen candidate's trajectories after accounting for the deliberately
  new policy ID. Run regression, package, app/UI, Release and full pre-push gates,
  inspect runtime output, review standards and scope, then PR/merge.

## Existing evidence (not new integration measurements)

Baseline `54bcd51d40baa1dec394c02e8ce89629f573d20b`; research AI
`35ba23806c4a41d410c19678b18071f3ae5df23f`. B-001 screened ten hypotheses
and independently confirmed only city production: randomized Classic/Standard
relative Elo +24.9, whole-seed-family 95% interval [12.4,36.9], 4,096 reciprocal
primary games and 2,048 secondary games plus four controls. Fixed
Classic/Standard subsequently passed compatibility (+160.6 [133.0,186.1]).
Conquest randomized missed its secondary guard; Vast samples were incomplete.
Those configurations are not being promoted. No claims of human-level skill.

Research ledger and full protocols:
`/Users/alex/.codex/worktrees/expert-strategy-trial-20261003/Settlers/docs/AI_summaries/expert-improvement/STRATEGY-EXPERIMENTS.md`.
Immutable raw evidence, binary hashes, manifests and receipts:
`/Users/alex/Library/Application Support/EmpiresResearch/expert-improvement/experiments/B-001/`
and sibling `C-001/`. This product branch deliberately excludes the nine
rejected/inconclusive hypotheses and broad research infrastructure.

## Work and verification status

Checkout: `/Users/alex/.codex/worktrees/expert-city-integration/Settlers`.
Branch: `codex/expert-city-integration`, based on the baseline above.
Primary checkout and other agents' opening research are untouched.

Implemented the isolated, versioned feature and its app selection/persistence
path. The coefficient is frozen in `ExpertRevision`, deliberately not exposed
as an editable `BotWeights` knob: changing it would silently reinterpret saved
revision IDs without the experiment needed to justify a different brain.

Integration evidence is stored at
`/Users/alex/Library/Application Support/EmpiresResearch/expert-improvement/deliveries/expert-city-20261004/`:

- `parity-result.json` and raw trajectories: 88 paired comparisons / 184
  executions matched the frozen candidate after normalizing only explicit
  policy IDs. Both board layouts, every chair, reciprocal legacy/current
  lineups, Balanced secondary tables and separate-process repeats completed.
- Six package revision tests passed; focused app/archive tests and a native
  Expert New Game → cold resume → confirmed setup-placement UI flow passed
  (11 tests / 19 parameterized executions, no failures or skips). The app-owned
  match reached game over through production checkpoint/result/export paths.
- `ui-attachments/21452E2C-FD42-4BAE-BE15-1592D60255C6.png` was opened and
  inspected: painted board, visible ports and the confirmation dock. This is
  a Debug UI-test capture, not proof of signed-device runtime.
- Independent standards/spec reviews found two issues: active revision metadata
  could pin editable New Game drafts, and the match test could leave completion
  work alive during fixture teardown. The draft copy now resets only its
  revision; the regression failed four assertions before the fix. The match
  test bounds unrelated Ghost extraction and retains/awaits completion before
  any throwing post-game checks. Full-suite testing will recheck the final
  lifecycle correction.

Build 16 is reserved in `project.yml`. Full pre-push gate, GitHub CI/PR/merge,
fresh Release runtime and signed TestFlight delivery are still pending. Local
signing is gitignored and Jake's committed defaults are unchanged. No research
branch, rejected hypothesis, CloudKit schema change or new difficulty is included.
