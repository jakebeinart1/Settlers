# Reproducing the naval AI study

This tool package preserves the exact scripts frozen before confirmation, plus a
portable validator. Python 3.9+ runs the tool with standard-library dependencies.
Its tests use pytest. Production engine and policy sources are not modified here.

The policy artifact is source `d8639917f68563b6fd2ca0d38c5fc28d3fc80a18`; its
Traditional opponent is the independently preserved source
`a316139bb2daa22d7224c19953f4a2e32c699c2f`. Both use engine source
`81bb29c5a6c4acc35ff268976aef4c58c71b0a03`. Release manifests and binary SHA-256
values are in `evidence/{candidate,anchor}-provenance.json`. Original binaries are
preserved locally at `/Users/alex/.codex/artifacts/naval-ai/d863991/{candidate,anchor}/naval-sim`.
A newly rebuilt binary is a new artifact; it must receive its own manifest and
must not be relabeled as the historical binary.

From the repository root:

```sh
pytest -q Packages/CatanAI/Tools/NavalEvaluation
python3 Packages/CatanAI/Tools/NavalEvaluation/naval_eval.py verify-evidence \
  Packages/CatanAI/Tools/NavalEvaluation/evidence
python3 Packages/CatanAI/Tools/NavalEvaluation/naval_eval.py analyze \
  Packages/CatanAI/Tools/NavalEvaluation/evidence/held-out --require-strength
```

`analyze` validates the entire declared plan before computing statistics. It
requires every seed/chair/cell/table/arm, subprocess exit status, exact policy and
source labels, command records, cross-chair control fingerprints, and one timing
record covering every committed action per game. Missing or extra control-only
rows fail. Executable bytes and manifests are verified by default; `--offline`
explicitly marks analysis as recorded provenance only when historical binary
paths are unavailable. Null winners are preserved and cannot receive VP-margin credit.
`--require-strength` returns a failing exit code unless the declared functional
and separate three-/four-player strength criteria pass. It is not a phone or UI
acceptance check.

To rerun the same plan into a new directory with preserved binaries:

```sh
python3 Packages/CatanAI/Tools/NavalEvaluation/naval_eval.py run \
  --candidate /Users/alex/.codex/artifacts/naval-ai/d863991/candidate/naval-sim \
  --anchor /Users/alex/.codex/artifacts/naval-ai/d863991/anchor/naval-sim \
  --stage held-out --output /tmp/naval-confirmation-reproduction --workers 1
```

The output must be new or empty. Worker count is explicit, from one to eight.
`uncontended-latency` repeats the 24 all-Expert development configurations and
requires one worker. `matrix`, `mixed-development`, and `land-development` reproduce the previously
declared development probes; none of these authorize tuning against the held-out
range. Full protocol rationale is in
[EvaluationProtocol.swift](../../Sources/naval-sim/EvaluationProtocol.swift),
with its frozen source hash and arithmetic revision in `protocol.json`.

The byte-identical originals in `frozen/` remain unchanged, including their
historical `/tmp` paths. The canonical analyzer corrects floating-point zero-bound
roundoff: it sums integer candidate-minus-control win counts, then divides once.
It keeps the same 12 strata, seed `20261004`, 20,000 draws, and quantile indices
499/19499. The revision was specified from an independent exact-zero counterexample
before interpreting confirmation results. All other numerical report fields must
match the frozen analyzer; paired values may differ only by floating-point roundoff.

Raw JSONL, timings, subprocess records, commands, manifests, deterministic repeat
captures, and reports are retained under `evidence/`. The accompanying `checksums.json`
pins their bytes. Findings and limitations belong in
[the AI study report](../../../../docs/AI_summaries/naval-exploration/evidence/ai-study.md).
