# Repeatable native AI evaluation

**Date:** 2026-09-06. Current priorities: [AI-PROGRAM.md](AI-PROGRAM.md).

## Product acceptance

One local command must evaluate the actual bundled neural policy without
hand-writing chair rotations, copying model IDs, or rebuilding the statistics.
This is deliberately a **smoke verifier**, not a difficulty calibration,
league manager or new training framework. Compatible external CTNN files use
the same adapter; a new architecture still requires its own reviewed build.

```bash
python3 scripts/evaluate-bots.py \
  --config config/evaluation/neural-r2-smoke.json \
  --output /tmp/empires-eval-unique-name
```

Use a new output directory each time. Configuration owns seeds, both evaluated
policies, identical opponents, rules cell and whole-run deadline. The native
`sim --list-policies` query supplies real IDs; `neural-r2` uses bundled r2 with
Balanced heuristic fallback and full information. It is not AlphaBot search.

Either `candidate` or `baseline` may instead be a descriptor with exactly
`checkpoint` (path relative to the configuration file, or absolute) and
`sha256` (64 lowercase hexadecimal characters). The opponent remains a named
built-in policy. Example: `{"checkpoint": "original.ctnn", "sha256": "<full digest>"}`.
The wrapper reads and verifies the bytes it copies into the run directory before
building. The native loader then validates CTNN dimensions, finite weights and
the embedded numerical probe. Model identity, adapter identity and full artifact
hash travel separately; a model name is not proof of its content.

The raw native CLI's `--neural-checkpoint-id` is explicitly caller-supplied
metadata. Use this wrapper for evidence: it supplies that ID only after verifying
the digest, freezes each arm's file, and rechecks all artifacts after evaluation.
Manifest schema 2 nests `policy_ids` by candidate/baseline because the same
`neural-checkpoint` seat name can resolve to different weights in each arm.

## Retained artifacts and pass criteria

- Copy the Release executable, model resource bundle and existing analyzer;
  hash the complete artifact, source inputs and configuration. Rebuilding later
  must not mutate either arm of a retained comparison.
- Play both arms over exactly the configured seeds and every chair. Validate
  complete shards/configuration before the existing schema-5 analyzer runs.
- Keep stderr, exact commands and raw JSONL on failures. Incomplete smoke games,
  changed artifacts, unknown policies, malformed config and command failures
  fail loudly; an existing output directory is never overwritten.
- Persist input/source hashes before building. Record selection routes and
  fallback reasons for every evaluated seat, including consulted responders;
  require exact agreement with the session's evaluation cursor. Unexpected
  neural fallbacks fail even if the game completes legally.
- Reuse `training_watchdog.py` for the independent process-group deadline.
  `run.watchdog.json` is the terminal verdict; `complete.json` also records a
  successful worker, never a strength-promotion decision. A failed guardian
  overrides a worker result. Active Mac process-identity inspection is limited;
  use the live foreground parent and fresh receipt, not a claim of Linux `/proc` support.
- `report.md` includes matched-arm results, completion and seed-cluster 95%
  intervals from the existing analyzer, prominently labeled development smoke.
- CLI tests must exercise real neural games across separate processes; runner
  tests repeat the entire three-player pipeline and compare all raw shards.

## Initial verification and warning

The first four-player run completed **32/32 games** in approximately 13 seconds
on this warm Mac build, including preparation and analysis. Its ten-minute
watchdog completed with exit 0. This is not a GPU or cold-build timing claim.
Raw evidence is retained at `/tmp/empires-neural-eval-smoke-20260906-r1`.

Four board seeds are too few to certify a model. Nevertheless the observed
native transfer result matters: **r2 6/16 versus Balanced 14/16**, each against
three Greedy opponents, with all four chairs rotated. The paired difference
was −50 percentage points (seed-cluster 95% bootstrap interval −87.5 to −12.5).
An interval based on only four clusters is unstable; do not promote this into
a broad strength claim. It motivates a prespecified larger native diagnostic
and a **hold on default-model promotion**, not tuning until these seeds pass.

The early run identified its build by executable hash; the final runner improves
that to a hash of executable **plus resources and analyzer**. Preserve the early
manifest as historical evidence rather than rewriting its identity.

### Audited follow-up and decision

A fixed 32-new-board diagnostic (seeds 960701–960732, four players, target 10,
randomized board, same Greedy opponents, every chair) completed **256/256 games**.
The first pass and its route-audited repeat agree: r2 **52/128 (40.6%)** versus
Balanced **112/128 (87.5%)**; paired difference **−46.9 points**, 95% seed-cluster
interval **−57.8 to −35.9**. There were **no unexpected fallbacks**. The evaluated
r2 seats used 17,811 neural routes and 3,445 intentional heuristic routes
(3,184 proposals, 261 pre-roll development-card choices). These are selection
counts, not neural inference-call counts.

**Decision:** retain r2 as an integrated research baseline, not a demonstrated
upgrade. Hold default promotion and TestFlight upload; investigate native
transfer/checkpoint/rule differences next. Do not retrain against these diagnostic
seeds until a desired number appears. This experiment did not test other targets,
three-player strength, human opponents, search, or universal Catan competence.

[Raw games, audits, configuration, source hashes, receipt and report](evidence/neural-evaluation-20260906/report.md)
are retained together. The frozen executable/resources remain at
`/tmp/empires-neural-transfer-audited-20260906/frozen`; model bytes already live
in the repo under their pinned provenance. The diagnostic preceded only the
registry's lint-required UTF-8 conversion spelling change; policy behavior was
not edited. The full quality gate checks the final source separately.

### Review and regression checks

**Standards:** fixed the sample-config-dependent fixture and removed its
tautological completion assertion. Extracted input/manifest responsibilities;
the existing watchdog/analyzer still own supervision/statistics.

**Spec:** fixed missing fallback audits and loss of hashes on early failures;
added cursor/seat/route completeness checks. No remaining blocking findings in
the independent read-only follow-up review.

Eleven native CLI tests and seven wrapper tests pass. Tests include real
three-player evaluation twice in separate processes, identical raw games/audits,
intentional file-write failure, unknown policies, timeout/fail-closed cleanup,
preserved inputs, invalid counters, unexpected fallbacks, and overwrite refusal.
On this Mac, one timeout's cleanup recorded `PermissionError` and correctly
remained FAILED (never PASS); follow-up process inspection found no residual
owned group. This limitation is not represented as successful process cleanup.
The final fast Release neural regression also passes: 35 tests, including
15 supported app-configuration full games and the Rust parity checks.

## Remaining scope

Separate builds for incompatible architectures; richer frozen opponents; measured
inference/fallback/latency counters; screened/confirmation experiment configs.
Implement only what the next experiment needs. Historical source-faithful
reconstruction and native transfer are separate measurements.

## Checkpoint-transfer investigation (predeclared 2026-09-06)

**Question:** does the original published checkpoint outperform r2 through the
same native adapter? This isolates checkpoint choice, not the cause of any gap
between the upstream and native games.

- Candidate: published CTNN `21f3b380786a53998172896caac44191dea3d44efd11d3bf8c92150d8b18c8a5`.
- Baseline: bundled r2, hash pinned in its existing provenance record.
- Identical engine, adapter, Balanced fallback, three Greedy opponents, four
  players, target 10, randomized board and all four chair rotations.
- First require identical-weight loaded/bundled equivalence, including routes,
  then an eight-game-per-arm smoke on two development boards (960790–960791).
- Diagnostic: fixed development seeds 960801–960832, 128 games per arm, 600-second
  watchdog budget, actively supervised until terminal. A 10-point difference is
  worth further checkpoint investigation; this run cannot authorize promotion.
  Retain every result, cap and failure; no adaptive extension or seed tuning.
- If both are weak, investigate transfer before more training. If original is
  clearly better, audit reconstruction/export first. Neither outcome proves an
  adapter bug or justifies altering native rules to improve a benchmark.

**Source audit:** both retained reactive evaluation and Swift use masked argmax,
so omitted AlphaBot search does not explain a reactive-to-reactive discrepancy.
Actual r2 training occupied seats 0 and 2; calibration used seat 0. Native ports,
the no-adjacent-6/8 board generator and victory target differ from training.
Existing oracle fixtures use upstream port placement and omit real encoded
Road Building/victim subdecisions. These are coverage/distribution questions,
not verified explanations of the strength gap. No neural weights were changed.

### Result and decision

The 16-game smoke passed, then the prespecified diagnostic completed **256/256**
games in 69.6 seconds, watchdog exit 0, zero unexpected fallbacks. Original:
**74/128 = 57.8%** (seed-cluster 95% CI 46.9–68.8); r2: **46/128 = 35.9%**.
Paired difference: **+21.9 points**, 95% interval **+10.2 to +32.8**. Per-chair
wins were original `[21,21,15,17]`, r2 `[13,13,11,9]` (32 games per chair).
The direction therefore was not confined to a chair absent from training.

**Decision: investigate checkpoint generalization; no promotion.** The difference
exceeds the predeclared 10-point investigative threshold, reversing the ranking
seen in the upstream seven-point calibration. This is evidence against treating
that calibration as transferred strength, not proof of a reconstruction bug or
superiority to our native Balanced policy. Balanced was not an evaluated arm on
these new seeds. Keep r2 and the original frozen; neither is an expert-play claim.
Check export/training-contract fidelity and the missing real compound observation
fixtures before changing weights. Profile the actual training pipeline before
committing the next GPU budget; additional training is not an automatic remedy.

[Complete raw comparison](evidence/checkpoint-transfer-20260906/report.md)
includes both checkpoint/build identities, exact commands, all games and route
audits, initial inputs and the terminal receipt. The frozen executable/resources
remain at `/tmp/empires-original-vs-r2-native-20260906/frozen`. The full published
model stays in the pinned upstream checkout rather than being duplicated in the app.

Verification of the loader extension: 15 CLI tests and 12 wrapper tests passed.
Identical weights produce identical games/audits through bundled and external
paths; two external descriptors work together; a valid zero network changes
actual move fingerprints. That deliberately weak fixture first hit the move cap
against Greedy; the test now uses Balanced opponents and an eight-point target.
The completion gate was kept unchanged. Invalid/mutated checkpoint hashes fail
before loading, and malformed models fail before result files are created.
Independent standards/spec review found no remaining issue after the pre-load
hash recheck and guarded failure diagnostics; the scoped simplifier pass found
no further useful reduction. This CLI-only slice changes no app policy or UI.

Final bounded verification passed: **105 evaluation-tool tests**, **35 Release
neural tests** (including 15 full supported-configuration games), warnings-as-errors
Release compilation and strict SwiftLint. Receipt: `verification.watchdog.json`
beside the retained comparison; log: `verification.log`. Hosted app/UI tests and
the full iOS release gate were not rerun for this CLI-only extension; the prior
full gate/CI evidence belongs to PR #41, not this local unmerged change.
The verbatim test-compilation log retains two pre-existing unused-`try?` warnings
in `DiscardRaceRegressionTests.swift`; the production warnings-as-errors build
passed separately. No claim of warning-free compilation of the entire test bundle.
