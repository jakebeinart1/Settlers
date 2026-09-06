# Repeatable native AI evaluation — first slice

**Date:** 2026-09-06. Current priorities: [AI-PROGRAM.md](AI-PROGRAM.md).

## Product acceptance

One local command must evaluate the actual bundled neural policy without
hand-writing chair rotations, copying model IDs, or rebuilding the statistics.
This slice is deliberately a **smoke verifier**, not a difficulty calibration,
arbitrary checkpoint loader, league manager or new training framework.

```bash
python3 scripts/evaluate-bots.py \
  --config config/evaluation/neural-r2-smoke.json \
  --output /tmp/empires-eval-unique-name
```

Use a new output directory each time. Configuration owns seeds, both evaluated
policies, identical opponents, rules cell and whole-run deadline. The native
`sim --list-policies` query supplies real IDs; `neural-r2` uses bundled r2 with
Balanced heuristic fallback and full information. It is not AlphaBot search.

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

Compatible arbitrary checkpoint selection and immutable model IDs; separate
builds for incompatible architectures; richer frozen opponents; measured
inference/fallback/latency counters; screened/confirmation experiment configs.
Implement only what the next experiment needs. Historical source-faithful
reconstruction and native transfer are separate measurements.
