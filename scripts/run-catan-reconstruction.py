#!/usr/bin/env python3
"""Run a bounded fresh/continuation upstream reconstruction, then evaluate it.

Use the isolated upstream Python environment and put upstream/training on
PYTHONPATH. Launch under tmux on Linux; this program records status but does
not install a service, retry failures, tune weights, or call completion proof
of reproduced strength. All output directories are exclusive to one run.
"""

import argparse
import importlib
import json
import math
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import torch

from catan_training_config import (
    TRAINING_EVAL_EVERY,
    TRAINING_NUM_ENVS,
    TRAINING_ROLLOUT,
)

replay = importlib.import_module("reproduce-catan-policy")
digest = replay.digest

TRAINING_FLAGS = {
    "num-envs": TRAINING_NUM_ENVS,
    "rollout": TRAINING_ROLLOUT,
    "victory-target": 7,
    "visibility": "perfect",
    "lr": 0.00025,
    "epochs": 4,
    "minibatch": 4096,
    "hidden": 512,
    "seed": 0,
    "eval-every": TRAINING_EVAL_EVERY,
    "entropy-coef": 0.02,
    "train-seats": "policy,heuristic,policy,heuristic_v2",
}
# The historical seed is diagnostic, not a checkpoint-selection criterion.
EVALUATION_SEEDS = (777, 930011, 930043, 930071)
SEED_ENTRY = (
    "import numpy as np, runpy; np.random.seed(0); "
    "runpy.run_path('training/ppo.py', run_name='__main__')"
)
FINISH_ALLOWANCE_SECONDS = 600
EVALUATION_ENTRY = (
    "import importlib,sys; from pathlib import Path; "
    "m=importlib.import_module('run-catan-reconstruction'); "
    "m.evaluate_models(Path(sys.argv[1]),Path(sys.argv[2]),sys.argv[3],Path(sys.argv[4]))"
)


def save_status(output: Path, status: dict) -> None:
    """Replace status atomically so a disconnected reader never sees half JSON."""
    temporary = output / "status.tmp"
    temporary.write_text(json.dumps(status, indent=2, allow_nan=False) + "\n")
    temporary.replace(output / "status.json")


def command_for_stage(name: str, minutes: float, device: str, parent: str) -> list[str]:
    """Freeze known settings; use continuation settings for missing fresh flags.

    Parent is empty for genuine random initialization. NumPy seeding corrects
    an upstream omission outside its tracked source; wall-clock annealing and
    checkpoint semantics remain the upstream implementation's.
    """
    flags = dict(TRAINING_FLAGS, name=name, minutes=minutes, device=device)
    flags["vp-delta"] = 0 if parent else 0.05
    if parent:
        flags["resume"] = parent
    else:
        flags["vp-delta-final"] = 0
    arguments = [
        part for key, value in flags.items() for part in (f"--{key}", str(value))
    ]
    return [sys.executable, "-u", "-c", SEED_ENTRY, *arguments]


def run_logged(command: list[str], source: Path, log: Path, timeout: float) -> None:
    """Retain full output and propagate nonzero exits/timeouts to job status."""
    with log.open("x") as handle:
        subprocess.run(
            command,
            cwd=source,
            stdout=handle,
            stderr=subprocess.STDOUT,
            check=True,
            timeout=timeout,
            env=dict(
                os.environ,
                PYTHONPATH=os.pathsep.join(
                    (str(Path(__file__).resolve().parent), str(source / "training"))
                ),
            ),
        )


def finite_metric_number(raw: str) -> float:
    """Reject nonfinite JSON numbers, including nested metrics and overflow."""
    value = float(raw)
    if not math.isfinite(value):
        raise ValueError(f"non-finite metric: {raw}")
    return value


def inspect_checkpoint(run: Path) -> dict:
    """Validate the final model/optimizer and metrics before allowing continuation."""
    checkpoint = (run / "checkpoints/latest.pt").resolve(strict=True)
    state = torch.load(checkpoint, map_location="cpu", weights_only=False)
    tensors = list(state["model_state"].values())
    for optimizer_state in state["optimizer_state"]["state"].values():
        tensors.extend(
            value for value in optimizer_state.values() if torch.is_tensor(value)
        )
    if not all(torch.isfinite(value).all().item() for value in tensors):
        raise ValueError("non-finite model or optimizer tensor")
    updates = 0
    with (run / "metrics.jsonl").open() as handle:
        for line in handle:
            row = json.loads(
                line,
                parse_float=finite_metric_number,
                parse_constant=finite_metric_number,
            )
            if row["t"] == "train":
                updates += 1
    if not updates or state["global_step"] <= 0:
        raise ValueError("training completed without any recorded updates")
    return {
        "checkpoint": str(checkpoint),
        "checkpoint_sha256": digest(checkpoint),
        "steps": state["global_step"],
        "updates": updates,
        "config": state["config"],
        "metrics_sha256": digest(run / "metrics.jsonl"),
    }


def train_stage(
    source: Path,
    output: Path,
    device: str,
    stage: str,
    minutes: float,
    parent: str,
    status: dict,
) -> dict:
    """Execute one unique upstream run, selecting its final—not best-scoring—model."""
    name = f"{output.name}-{stage}"
    run_root = source / "training/runs"
    pattern = f"*-{name}"
    if list(run_root.glob(pattern)):
        raise FileExistsError(f"upstream run name already used: {name}")
    command = command_for_stage(name, minutes, device, parent)
    status.update(phase=stage, active_command=command, phase_started=time.time())
    save_status(output, status)
    start = time.monotonic()
    run_logged(
        command,
        source,
        output / f"{stage}.log",
        minutes * 60 + FINISH_ALLOWANCE_SECONDS,
    )
    runs = list(run_root.glob(pattern))
    if len(runs) != 1:
        raise ValueError(f"expected one completed upstream run; found {runs}")
    result = inspect_checkpoint(runs[0])
    result["elapsed_seconds"] = time.monotonic() - start
    status["stages"][stage] = result
    save_status(output, status)
    return result


def evaluate_models(
    source: Path, output: Path, device: str, checkpoint: Path
) -> list[dict]:
    """Compare final and original policies on predeclared seeds, retaining every row.

    These are fixed-chair upstream-contract diagnostics. Multiple training seeds
    and a separate assessment are still needed for a training-reproduction verdict.
    """
    torch.set_num_threads(replay.TORCH_THREADS)
    results = []
    for name, model in (
        ("original", source / "models/catan-512-best.pt"),
        ("reconstructed", checkpoint),
    ):
        network = replay.make_policy(model).to(device)
        for seed in EVALUATION_SEEDS:
            path = output / f"{name}-seed-{seed}.jsonl"
            rows = replay.collect_outcomes(network, path, device=device, seed=seed)
            results.append(
                {
                    "model": name,
                    "checkpoint_sha256": digest(model),
                    "seed": seed,
                    "games": len(rows),
                    "wins": sum(row["winner"] == 0 for row in rows),
                    "caps": sum(row["capped"] for row in rows),
                    "outcomes_sha256": digest(path),
                }
            )
    (output / "evaluation.json").write_text(json.dumps(results, indent=2) + "\n")
    return results


def completed_native_game(metrics: Path) -> dict:
    """A zero simulator exit can still mean a capped or abandoned game."""
    rows = [json.loads(line) for line in metrics.read_text().splitlines()]
    games = [row for row in rows if row["t"] == "game"]
    if len(games) != 1:
        raise ValueError("expected exactly one native game")
    game = games[0]
    if game["winner"] not in range(4) or game["cap"] or game["steps"] <= 0:
        raise ValueError("native game did not finish with a winner")
    return game


def finish_pipeline(
    source: Path,
    output: Path,
    device: str,
    checkpoint: Path,
    simulator: Path,
    status: dict,
) -> None:
    """Export, check native loading/game completion, and retain frozen evaluations."""
    status["phase"] = "export-and-evaluate"
    save_status(output, status)
    exported = output / "final.ctnn"
    run_logged(
        [sys.executable, "training/export_net.py", str(checkpoint), str(exported)],
        source,
        output / "export.log",
        FINISH_ALLOWANCE_SECONDS,
    )
    run_logged(
        [
            str(simulator),
            "--games",
            "1",
            "--players",
            "A,H,H,H",
            "--seed",
            "0",
            "--net",
            str(exported),
            "--alpha-config",
            "8,96,300",
            "--record-replays",
            str(output / "rust-replay"),
            "--metrics",
            str(output / "native-metrics.jsonl"),
        ],
        source,
        output / "rust-inference.log",
        FINISH_ALLOWANCE_SECONDS,
    )
    status["ctnn_sha256"] = digest(exported)
    status["native_game"] = completed_native_game(output / "native-metrics.jsonl")
    run_logged(
        [
            sys.executable,
            "-u",
            "-c",
            EVALUATION_ENTRY,
            str(source),
            str(output),
            device,
            str(checkpoint),
        ],
        source,
        output / "evaluation.log",
        FINISH_ALLOWANCE_SECONDS,
    )
    status["evaluation"] = json.loads((output / "evaluation.json").read_text())
    status.update(
        phase="complete",
        finished=time.time(),
        training_reproduction_verdict="not_assessed",
    )
    save_status(output, status)


def positive_minutes(value: str) -> float:
    """Bound this reproduction command to at most an hour per training stage."""
    minutes = float(value)
    if not math.isfinite(minutes) or not 0 < minutes <= 60:
        raise argparse.ArgumentTypeError("minutes must be finite and in (0, 60]")
    return minutes


def terminate_job(signum: int, _frame: object) -> None:
    """Turn a supervisor termination into a recorded failure and child cleanup."""
    raise InterruptedError(f"received signal {signum}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--binding-sha256", required=True)
    parser.add_argument("--device", choices=("cpu", "cuda"), default="cuda")
    parser.add_argument("--fresh-minutes", type=positive_minutes, default=50.0)
    parser.add_argument("--continuation-minutes", type=positive_minutes, default=60.0)
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    oracle, binding = replay.check_inputs(source, args.binding_sha256)
    simulator = source / "rust/target/release/catan-sim"
    if not simulator.is_file():
        raise FileNotFoundError(f"build the pinned simulator first: {simulator}")
    torch.set_num_threads(replay.TORCH_THREADS)
    metadata = replay.provenance(source, oracle, binding)
    metadata.update(
        device=args.device,
        cuda_runtime=torch.version.cuda,
        supervisor_sha256=digest(Path(__file__)),
        simulator_sha256=digest(simulator),
        evaluation_seeds=EVALUATION_SEEDS,
    )
    if args.device == "cuda":
        metadata["gpu"] = torch.cuda.get_device_name(0)
    output.mkdir(parents=True, exist_ok=False)
    (output / "manifest.json").write_text(json.dumps(metadata, indent=2) + "\n")
    execute(args, source, output, simulator)


def execute(
    args: argparse.Namespace, source: Path, output: Path, simulator: Path
) -> None:
    """Make interrupted/failed work distinguishable from a successfully finished job."""
    status = {"pid": os.getpid(), "started": time.time(), "stages": {}}
    signal.signal(signal.SIGTERM, terminate_job)
    try:
        first = train_stage(
            source, output, args.device, "fresh", args.fresh_minutes, "", status
        )
        second = train_stage(
            source,
            output,
            args.device,
            "continuation",
            args.continuation_minutes,
            first["checkpoint"],
            status,
        )
        finish_pipeline(
            source, output, args.device, Path(second["checkpoint"]), simulator, status
        )
    except BaseException as error:
        status.update(phase="failed", error=repr(error), finished=time.time())
        save_status(output, status)
        raise


if __name__ == "__main__":
    main()
