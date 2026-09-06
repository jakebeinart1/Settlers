# Frozen upstream policy

`final.ctnn` is Alex's existing completed `gpu-baseline-20260906-r2` export,
copied without conversion, quantization, retraining, or checkpoint selection.

- Source: https://github.com/Eli6th/catan-rl
- Source commit: `021279c56834b6203480e5292e1de7246e47bd68`
- CTNN SHA-256: `a3c957a8765ccbb3c9afd1a8ebee45b7cbaff134c40ce0456e5024560b3ef94e`
- Parent checkpoint SHA-256: `b2b65d569ef2e56bbca9e6f6ecfd41b4c0905842803e62c3aff2aeec7d96dace`
- Byte count: 4,438,528
- CTNN version: 1; observation version: 1; action codec version: 1.
- Dimensions: 1,350 inputs, two 512-wide ReLU layers, 299 raw logits,
  one linear value output (clamped to [-1, 1] by Rust inference).
- CTNN v1 records dimensions but **does not encode** observation/codec
  versions, visibility or game configuration; these remain adapter contracts.
- Training/evaluation provenance: four seats, perfect information, 7-VP target;
  see `docs/AI_summaries/evidence/catan-reconstruction/gpu-baseline-20260906-r2/`.

The upstream repository declares MIT and ships its code and original weights
in the same tree; no separate weight-specific license was found at the pinned
commit. `UpstreamNetwork.swift` adapts its `net.rs`
arithmetic; the fixture generator compiles that original module as its oracle.
Retain the accompanying unmodified `LICENSE.txt` in source and distributed
resource bundles. The r2 weights were trained locally using that upstream stack;
they are not the author's published `catan-512.ctnn`. No branding, artwork,
third-party runtimes, or training dependencies are included here.

The embedded CTNN check compares only a raw value and logits 0–7 with absolute
error < 0.001. It is a numerical compatibility check, **not a checksum**.
The import and fixture generator verify the full SHA-256 above; the portable
runtime checks structure, finiteness and the embedded numerical probe.

All integer fields and IEEE-754 binary32 words are little-endian. The header is
ASCII `CTNN` followed by four UInt32s: version 1, input count 1350, action count
299, hidden width 512. Tensors on disk are row-major `[output][input]`:

| Tensor | Byte offset | Float count |
| --- | ---: | ---: |
| First-layer weights | 20 | 691,200 |
| First-layer bias | 2,764,820 | 512 |
| Second-layer weights | 2,766,868 | 262,144 |
| Second-layer bias | 3,815,444 | 512 |
| Policy weights | 3,817,492 | 153,088 |
| Policy bias | 4,429,844 | 299 |
| Value weights | 4,431,040 | 512 |
| Value bias | 4,433,088 | 1 |
| Embedded observation | 4,433,092 | 1,350 |
| Embedded raw value | 4,438,492 | 1 |
| Embedded logits 0–7 | 4,438,496 | 8 |

Only the trunk matrices are transposed at load, to `[input][output]`. Each
trunk sum starts at its bias, adds inputs in ascending index order (skipping
both signs of zero), then applies ReLU. Each head starts 16 float32 sums at
zero, adds successive products to lane `index % 16`, sums lanes left-to-right,
then adds its bias. Hidden width 512 has no tail. No fused multiply-add, Double
accumulation, tanh, softmax, input normalization or legal mask is introduced.
Prediction clamps only the value; the embedded check uses the unclamped value.

The Foundation-only implementation stores approximately 4.23 MiB of immutable
float weights and biases; Swift array copies share storage until mutation.
Prediction allocates its own two 512-float hidden buffers and 299-float output,
without copying model weights. Loading transiently retains decoded and
transposed arrays; it is intended to happen once, outside the turn loop.

To regenerate full-output fixtures, run `scripts/generate-upstream-network-fixtures.py`
with `--source` pointing to that pinned checkout, `--model` to this `final.ctnn`,
`--rustc` to an installed compiler and `--output` to
`Packages/CatanAI/Tests/CatanAITests/Fixtures/UpstreamNetwork/rust-parity.json`.
It runs the original Rust module twice in separate processes and records all
input/output float32 bits, compiler/flags and source hash. Synthetic frozen
vectors test numerical inference; they do not prove observation translation,
gameplay correctness or strength.
