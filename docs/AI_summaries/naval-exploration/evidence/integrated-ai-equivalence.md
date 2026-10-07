# Integrated naval AI trajectory equivalence

The separately rebuilt integrated Release artifact matched all 48 declared
development results from the frozen `d863991` study. Every result field,
including the ordered-move fingerprint, winner, action count, policy IDs,
configuration and per-seat behavior telemetry, matched after excluding only the
deliberately changed `buildID`. All 48 games completed, with zero checkpoint,
process or behavioral rejections.

This bridge uses source `a8bd01c69702e1a862d92fc923e4a78e9ca9708f`, tree
`1f208b12b7bfdb6212848a09ef6a13341cb6d954`. Its Release executable SHA-256 is
`72bba5d36295fa489dfe7117e0e5f50f6d18eba44f86be8c37934c3dfba69bc8`.
The binary and manifest are preserved outside Git at
`/Users/alex/.codex/artifacts/naval-ai/integrated-a8bd01c/`.
The [manifest](../../../../Packages/CatanAI/Tools/NavalEvaluation/integration/a8bd01c/data/provenance.json)
records the exact external-scratch build command. Building the Release
`naval-sim` product completed successfully in 25.62 seconds with two build jobs;
the [build log](../../../../Packages/CatanAI/Tools/NavalEvaluation/integration/a8bd01c/data/build.log)
is retained.

The integrated CatanAI source subtree and the historical policy/harness subtree
are both `ee0e65f380959b5ca88af092374419b6a10151dd`. Neither the policy nor its
harness was changed. The engine source delta from study source
`81bb29c5a6c4acc35ff268976aef4c58c71b0a03` is the terminal-session fix in
`be5ddeb7ff26ebf28800be44953a082fc85eb1a4`: automated trade replies stop after
victory, and a queued reply must belong to the current main-turn proposer.
[Source checks](../../../../Packages/CatanAI/Tools/NavalEvaluation/integration/a8bd01c/data/source-checks.json)
and the [complete engine source patch](../../../../Packages/CatanAI/Tools/NavalEvaluation/integration/a8bd01c/data/engine-source-diff.json)
pin this boundary. App presentation and human trade-confirmation fixes need
their native test evidence separately.

The comparison was declared before running the rebuilt artifact. It repeats the
existing development matrix: archipelago, peninsula and twin islands; both fog
settings; both flexible-resource settings; three and four seats; all-Traditional
and all-Expert rosters. Each of the 12 cells uses seed `700000 + 100 × cell`,
giving 24 games per table size and 48 total. This uses development seeds only.
The [declared plan](../../../../Packages/CatanAI/Tools/NavalEvaluation/integration/a8bd01c/data/equivalence-plan.json),
[commands and subprocess receipts](../../../../Packages/CatanAI/Tools/NavalEvaluation/integration/a8bd01c/data/matrix/),
and [full comparison](../../../../Packages/CatanAI/Tools/NavalEvaluation/integration/a8bd01c/data/equivalence.json)
are retained. Both input datasets passed strict plan validation and verification
against the actual executable bytes and Release manifests before comparison.
Each trajectory still validates and JSON-round-trips its checkpoint after every
committed action. The comparator also pins a SHA-256 of each complete result
record after removing `buildID`.

The preserved data packet contains 109 checksummed files. It can be verified with
`naval_eval.py verify-evidence` against
`Packages/CatanAI/Tools/NavalEvaluation/integration/a8bd01c/data`.

Seven comparator regressions passed, covering changed fingerprints, changed
action counts, nested telemetry mutations, added null fields, missing or
duplicate trajectories, and the allowed build-label change. The complete Python
tool suite passed 46 tests in 6.60 seconds; Black and isort checks passed. The
comparison script can be rerun from the repository root:

```sh
python3 Packages/CatanAI/Tools/NavalEvaluation/integration/a8bd01c/compare.py \
  Packages/CatanAI/Tools/NavalEvaluation/evidence/matrix \
  Packages/CatanAI/Tools/NavalEvaluation/integration/a8bd01c/data/matrix \
  /tmp/naval-integrated-comparison.json
```

This is a bounded source-integration check. The 1,464-game held-out study,
confidence intervals and uncontended host latency remain attached to their
original frozen artifact and engine, as documented in [the AI study](ai-study.md).
The 48 bridge games ran concurrently with the repository gate. Their retained
timings are CPU-contended diagnostics and provide no new performance verdict.
Phone latency remains unmeasured; this bridge does not certify the app or UI gate.
