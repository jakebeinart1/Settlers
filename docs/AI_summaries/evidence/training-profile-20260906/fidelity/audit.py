"""Read-only diagnostic: compare retained exports and CPU/Rust predictions.

Uses the pinned upstream exporter and existing Rust-oracle wrapper; does not
train, rewrite retained models, or infer playing strength from unmasked logits.
Run with the isolated upstream Python and both repo/scripts and upstream/training
on PYTHONPATH. Paths are this diagnostic's explicit inputs, not portable defaults.
"""

import importlib
import json
import struct
from pathlib import Path

import torch

from catan_policy_evidence import digest

oracle = importlib.import_module("generate-upstream-network-fixtures")
replay = importlib.import_module("reproduce-catan-policy")
ROOT = Path("/tmp/empires-export-fidelity-H0pWLD")
SOURCE = Path("/Users/alex/Library/Application Support/EmpiresResearch/catan-rl/original-v1")
REPO = Path("/Users/alex/Documents/Personal Projects/Settlers")
BACKUP = Path("/Users/alex/Library/Application Support/EmpiresResearch/checkpoints/gpu-baseline-20260906-r2")
TENSOR_END = 4_433_092


def compare(name: str, checkpoint: Path, exported: Path) -> dict:
    old, new = exported.read_bytes(), (ROOT / f"{name}.ctnn").read_bytes()
    assert len(old) == len(new) == oracle.MODEL_BYTES
    assert old[:TENSOR_END] == new[:TENSOR_END], "header or tensor bytes changed"
    old_probe = struct.unpack_from("<1359f", old, TENSOR_END)
    new_probe = struct.unpack_from("<1359f", new, TENSOR_END)
    assert old_probe[:1350] == new_probe[:1350]
    fixture = REPO / "Packages/CatanAI/Tests/CatanAITests/Fixtures/upstream-observations.jsonl"
    positions = [json.loads(row) for row in fixture.read_text().splitlines()]
    cases = oracle.frozen_inputs(old) + [
        (f"game-{i}", row["features"]) for i, row in enumerate(positions)
    ]
    rust_bits = oracle.rust_predictions(SOURCE, exported, "rustc", cases)
    assert rust_bits == oracle.rust_predictions(SOURCE, exported, "rustc", cases)
    rust = torch.tensor([
        struct.unpack("<300f", struct.pack("<300I", *row)) for row in rust_bits
    ])
    with torch.no_grad():
        logits, value = replay.make_policy(checkpoint)(
            torch.tensor([features for _, features in cases]),
            torch.ones(len(cases), 299, dtype=torch.bool),
        )
    assert torch.isfinite(logits).all() and torch.isfinite(value).all()
    logit_delta = float((logits - rust[:, :299]).abs().max())
    value_delta = float((value.clamp(-1, 1) - rust[:, 299]).abs().max())
    assert logit_delta < 0.001 and value_delta < 0.001
    return {
        "model": name, "checkpoint_sha256": digest(checkpoint),
        "export_sha256": digest(exported), "reexport_sha256": digest(ROOT / f"{name}.ctnn"),
        "header_and_all_parameter_bytes_identical": True,
        "parameter_float_count": (TENSOR_END - 20) // 4,
        "probe_input_identical": True,
        "probe_prediction_max_abs_delta": max(abs(a-b) for a, b in zip(old_probe[1350:], new_probe[1350:])),
        "samples": len(cases), "real_upstream_positions": len(positions),
        "observation_fixture_sha256": digest(fixture),
        "rust_separate_process_bit_parity": True,
        "cpu_rust_logit_max_abs_delta": logit_delta,
        "cpu_rust_clamped_value_max_abs_delta": value_delta,
        "unmasked_top1_disagreements": int((logits.argmax(1) != rust[:, :299].argmax(1)).sum()),
        "limits": "Top-1 uses all 299 outputs, not legal-action masks. Numerical audit, not gameplay or exhaustive parity.",
    }


torch.set_num_threads(4)
oracle.verified_source(SOURCE)
report = {
    "source_commit": oracle.SOURCE_COMMIT,
    "exporter_sha256": digest(SOURCE / "training/export_net.py"),
    "trainer_sha256": digest(SOURCE / "training/ppo.py"),
    "auditor_sha256": digest(Path(__file__)), "torch": torch.__version__,
    "models": [
        compare("original", SOURCE / "models/catan-512-best.pt", SOURCE / "models/catan-512.ctnn"),
        compare("r2", BACKUP / "step_0148807680.pt", REPO / "Packages/CatanAI/Sources/CatanAI/Resources/UpstreamPolicy/final.ctnn"),
    ],
}
with (ROOT / "audit.json").open("x") as handle:
    json.dump(report, handle, indent=2, allow_nan=False)
print(json.dumps(report, indent=2))
