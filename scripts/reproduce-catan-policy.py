#!/usr/bin/env python3
"""Replay the original upstream policy gate and retain every scored outcome.

Run inside the isolated upstream v1 environment, with its training directory on
PYTHONPATH. This deliberately preserves the author's 48-lane, completion-order
sampling and batch overshoot. It is a historical calibration, not a fair new
strength tournament. No upstream trainer or game rules are changed.

Evaluation loop adapted from Eli Olcott's catan-rl/training/ppo.py at
021279c56834b6203480e5292e1de7246e47bd68, Copyright (c) 2026 Eli Olcott.
MIT license: scripts/licenses/catan-rl-MIT.txt.
"""

from __future__ import annotations

import argparse
import json
import platform
import subprocess
import sys
from pathlib import Path

import catan_py
import numpy as np
import ppo
import torch
from catan_policy_evidence import GAMES, digest, summarize

SOURCE_COMMIT = "021279c56834b6203480e5292e1de7246e47bd68"
MODEL_SHA256 = "c4258f235c673efe6968b0aa4de66a1411f01012fa14fe71f548dfff681525a3"
LANES = 48
SEED = 777
VICTORY_TARGET = 7
TORCH_THREADS = 4


def git(source: Path, *args: str) -> str:
    """Read upstream provenance, propagating errors rather than guessing it."""
    return subprocess.check_output(["git", "-C", str(source), *args], text=True).strip()


def check_inputs(source: Path, binding_sha256: str) -> tuple[Path, Path]:
    """Reject a wrong model, imported trainer, engine contract, or binary."""
    model = source / "models/catan-512-best.pt"
    binding = Path(catan_py.catan_py.__file__).resolve()
    if catan_py.VecEnv is not catan_py.catan_py.VecEnv:
        raise ValueError("Python wrapper replaced the verified native VecEnv")
    if git(source, "rev-parse", "HEAD") != SOURCE_COMMIT:
        raise ValueError("upstream checkout is not the pinned original revision")
    if Path(ppo.__file__).resolve() != source / "training/ppo.py":
        raise ValueError("PYTHONPATH imported a different upstream trainer")
    changes = git(
        source, "diff", "HEAD", "--", ".", ":(exclude)rust/catan-py/Cargo.lock"
    )
    if changes:
        raise ValueError("upstream tracked source changed beyond the binding lock")
    if digest(model) != MODEL_SHA256 or digest(binding) != binding_sha256:
        raise ValueError("model or installed engine binary hash mismatch")
    contract = (
        catan_py.OBS_VERSION,
        catan_py.OBS_DIM,
        catan_py.CODEC_VERSION,
        catan_py.NUM_ACTIONS,
    )
    if contract != (1, 1350, 1, 299):
        raise ValueError(f"wrong engine contract: {contract}")
    return model, binding


def make_policy(model: Path) -> ppo.PolicyValueNet:
    """Load only the hash-checked historical artifact using its own network."""
    checkpoint = torch.load(model, map_location="cpu", weights_only=False)
    net = ppo.PolicyValueNet(
        checkpoint["obs_dim"],
        checkpoint["num_actions"],
        checkpoint["config"]["hidden"],
    )
    net.load_state_dict(checkpoint["model_state"])
    net.eval()
    return net


def collect_outcomes(net: ppo.PolicyValueNet, path: Path) -> list[dict]:
    """Mirror ppo.evaluate_vs, recording every completion including overshoot.

    The v1 API exposes no lane or per-game seed in these stats. We retain the
    batch/ordinal and VP/turn/winner data it does expose, without inventing IDs.
    """
    env = catan_py.VecEnv(
        LANES,
        victory_target=VICTORY_TARGET,
        visibility="perfect",
        seed=SEED,
        seats=["policy", "heuristic", "heuristic", "heuristic"],
    )
    observations, masks, _ = env.observe()
    rows: list[dict] = []
    batch = 0
    with torch.no_grad(), path.open("x", encoding="utf-8") as handle:
        while len(rows) < GAMES:
            logits, _ = net(torch.as_tensor(observations), torch.as_tensor(masks))
            actions = logits.argmax(dim=1).numpy().astype(np.uint32)
            observations, masks, _, _, _, _ = env.step(actions)
            batch += 1
            for turns, winner, points, cap in env.take_episode_stats():
                row = {
                    "ordinal": len(rows),
                    "batch": batch,
                    "turns": turns,
                    "winner": winner,
                    "victory_points": points,
                    "capped": cap,
                }
                handle.write(json.dumps(row, sort_keys=True) + "\n")
                rows.append(row)
    return rows


def provenance(source: Path, model: Path, binding: Path) -> dict:
    """Keep exact source, native binary, dependency, and machine identities."""
    return {
        "source_commit": SOURCE_COMMIT,
        "checkpoint_sha256": digest(model),
        "binding_sha256": digest(binding),
        "binding_path": str(binding),
        "runner_sha256": digest(Path(__file__)),
        "evidence_helper_sha256": digest(
            Path(__file__).with_name("catan_policy_evidence.py")
        ),
        "trainer_sha256": digest(source / "training/ppo.py"),
        "binding_lock_diff": git(
            source, "diff", "HEAD", "--", "rust/catan-py/Cargo.lock"
        ),
        "python": sys.version,
        "python_executable": sys.executable,
        "platform": platform.platform(),
        "machine": platform.machine(),
        "torch": torch.__version__,
        "numpy": np.__version__,
        "dependencies": subprocess.check_output(
            [sys.executable, "-m", "pip", "freeze", "--all"], text=True
        ).splitlines(),
        "protocol": {
            "seed": SEED,
            "lanes": LANES,
            "requested_games": GAMES,
            "victory_target": VICTORY_TARGET,
            "visibility": "perfect",
            "policy_seat": 0,
            "opponent": "heuristic",
            "torch_threads": TORCH_THREADS,
            "sampling": "upstream completion order; retain batch overshoot",
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--binding-sha256", required=True)
    parser.add_argument(
        "--expected-outcomes", default="", help="Optional prior local outcome digest"
    )
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    source = args.source.resolve()
    model, binding = check_inputs(source, args.binding_sha256)
    torch.set_num_threads(TORCH_THREADS)
    metadata = provenance(source, model, binding)
    metadata["expected_local_outcomes_sha256"] = args.expected_outcomes
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / "manifest.json").write_text(json.dumps(metadata, indent=2) + "\n")
    outcomes = args.output / "games.jsonl"
    rows = collect_outcomes(make_policy(model), outcomes)
    summary = summarize(rows, outcomes, args.expected_outcomes)
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    if not summary["artifact_gate_passed"]:
        raise SystemExit("Historical artifact gate differed; raw results retained")


if __name__ == "__main__":
    main()
