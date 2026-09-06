#!/usr/bin/env python3
"""Profile one unmodified upstream continuation, never promote its checkpoint.

Run in the isolated upstream environment with scripts and upstream/training on
PYTHONPATH. Each invocation owns an outer watchdog and a unique upstream run.
Use --mode none as the unprofiled control; cProfile measures host-call time,
including cold trainer initialization and periodic/final evaluation, not CUDA
kernel durations or separately timed rollout/GAE/update phases.
"""

import argparse
import cProfile
import importlib
import json
import math
import os
import pstats
import shutil
import signal
import sys
import time
import uuid
from pathlib import Path
from typing import Optional

import training_watchdog as watchdog

reconstruction = importlib.import_module("run-catan-reconstruction")
MAX_TRAINING_SECONDS = 120
FINISH_ALLOWANCE_SECONDS = 120
PROFILE_SCOPE = (
    "Cold trainer initialization, training, periodic/final evaluation and saves; "
    "wrapper imports/provenance and CUDA device preflight excluded. "
    "Trainer warmup retained, not separated. "
    "Host-call timings only: CUDA waits can be charged to cpu/item calls. "
    "Python transition bookkeeping and GAE share the trainer main frame."
)


def sha256_argument(value: str) -> str:
    if len(value) != 64 or set(value) - set("0123456789abcdef"):
        raise argparse.ArgumentTypeError("expected 64 lowercase SHA-256 hex digits")
    return value


def parse_options(arguments: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--parent", type=Path, required=True)
    parser.add_argument("--parent-sha256", type=sha256_argument, required=True)
    parser.add_argument("--binding-sha256", type=sha256_argument, required=True)
    parser.add_argument("--mode", choices=("none", "cprofile"), required=True)
    parser.add_argument("--seconds", type=float, default=60)
    parser.add_argument("--device", choices=("cpu", "cuda"), default="cuda")
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    options = parser.parse_args(arguments)
    if (
        not math.isfinite(options.seconds)
        or not 0 < options.seconds <= MAX_TRAINING_SECONDS
    ):
        parser.error(f"--seconds must be finite and in (0, {MAX_TRAINING_SECONDS}]")
    for name in ("source", "output", "parent"):
        setattr(options, name, getattr(options, name).resolve())
    return options


def write_json(path: Path, value: object) -> None:
    with path.open("x") as handle:
        json.dump(value, handle, indent=2, sort_keys=True, allow_nan=False)
        handle.write("\n")


def check_parent(options: argparse.Namespace) -> None:
    if reconstruction.digest(options.parent) != options.parent_sha256:
        raise ValueError("parent checkpoint SHA-256 mismatch")


def device_metadata(device: str) -> dict:
    gpu = None
    if device == "cuda":
        if not reconstruction.torch.cuda.is_available():
            raise ValueError("CUDA requested but unavailable; no CPU fallback")
        gpu = reconstruction.torch.cuda.get_device_name(0)
    return {
        "device": device,
        "gpu": gpu,
        "cuda_runtime": reconstruction.torch.version.cuda,
    }


def prepare_run(options: argparse.Namespace, name: str) -> list[str]:
    """Reuse frozen flags and provenance; verify the parent before trainer entry."""
    check_parent(options)
    oracle, binding = reconstruction.replay.check_inputs(
        options.source, options.binding_sha256
    )
    command = reconstruction.command_for_stage(
        name, options.seconds / 60, options.device, str(options.parent)
    )
    write_json(
        options.output / "manifest.json",
        {
            "schema_version": 1,
            "upstream": reconstruction.replay.provenance(
                options.source, oracle, binding
            ),
            "wrapper_sha256": reconstruction.digest(Path(__file__)),
            "reconstruction_sha256": reconstruction.digest(
                Path(reconstruction.__file__)
            ),
            "parent": str(options.parent),
            "parent_sha256": options.parent_sha256,
            "command": command,
            "mode": options.mode,
            "run_name": name,
            "training_seconds": options.seconds,
            "watchdog_seconds": options.seconds + FINISH_ALLOWANCE_SECONDS,
            "profile_scope": PROFILE_SCOPE,
            **device_metadata(options.device),
        },
    )
    return command


def save_profile(
    output: Path, profiler: cProfile.Profile, mode: str, elapsed: float, completed: bool
) -> None:
    functions = []
    if mode == "cprofile":
        profiler.dump_stats(str(output / "profile.pstats"))
        for (file, line, name), (primitive, calls, own, cumulative, _) in sorted(
            pstats.Stats(profiler).stats.items()
        ):
            functions.append(
                {
                    "file": file,
                    "line": line,
                    "function": name,
                    "primitive_calls": primitive,
                    "calls": calls,
                    "self_seconds": own,
                    "cumulative_seconds": cumulative,
                }
            )
    write_json(
        output / "profile.json",
        {
            "schema_version": 1,
            "mode": mode,
            "scope": PROFILE_SCOPE,
            "trainer_returned_normally": completed,
            "elapsed_seconds": elapsed,
            "functions": functions,
        },
    )


def run_trainer(command: list[str], source: Path, output: Path, mode: str) -> None:
    """Execute the existing seeded entry verbatim; retain partial profiles on TERM.

    Restoring argv/cwd also makes this seam testable without launching training.
    No profiler callbacks, synchronizations, or trainer functions are replaced.
    """
    if command[:3] != [sys.executable, "-u", "-c"]:
        raise ValueError("unexpected reconstruction entry-point contract")
    previous_argv, previous_directory = sys.argv, Path.cwd()
    profiler, namespace, completed = cProfile.Profile(), {}, False
    started = time.perf_counter()
    try:
        os.chdir(source)
        sys.argv = ["-c", *command[4:]]
        if mode == "cprofile":
            profiler.runctx(command[3], namespace, namespace)
        else:
            exec(command[3], namespace, namespace)
        completed = True
    finally:
        elapsed = time.perf_counter() - started
        sys.argv = previous_argv
        os.chdir(previous_directory)
        save_profile(output, profiler, mode, elapsed, completed)


def worker(options: argparse.Namespace) -> None:
    name = f"profile-{options.mode}-{uuid.uuid4().hex}"
    command = prepare_run(options, name)
    signal.signal(signal.SIGTERM, reconstruction.terminate_job)
    run_trainer(command, options.source, options.output, options.mode)
    runs = list((options.source / "training/runs").glob(f"*-{name}"))
    if len(runs) != 1:
        raise ValueError(f"expected one upstream run, found {len(runs)}")
    checkpoint = reconstruction.inspect_checkpoint(runs[0])
    check_parent(options)
    reconstruction.replay.check_inputs(options.source, options.binding_sha256)
    for filename in ("metrics.jsonl", "config.json"):
        with (options.output / filename).open("xb") as target:
            with (runs[0] / filename).open("rb") as source:
                shutil.copyfileobj(source, target)
    write_json(
        options.output / "result.json",
        {
            "schema_version": 1,
            "upstream_run": str(runs[0]),
            "checkpoint": checkpoint,
            "finite_checkpoint_and_metrics": True,
            "strength_claim": False,
        },
    )


def main(arguments: Optional[list[str]] = None) -> int:
    arguments = sys.argv[1:] if arguments is None else arguments
    options = parse_options(arguments)
    if options.worker:
        worker(options)
        return 0
    options.output.mkdir(parents=True, exist_ok=False)
    command = [
        sys.executable,
        "-B",
        "-u",
        str(Path(__file__).resolve()),
        *arguments,
        "--worker",
    ]
    signal.signal(signal.SIGTERM, watchdog.interrupted)
    return watchdog.run(
        command, options.output / "run", options.seconds + FINISH_ALLOWANCE_SECONDS
    )


if __name__ == "__main__":
    raise SystemExit(main())
