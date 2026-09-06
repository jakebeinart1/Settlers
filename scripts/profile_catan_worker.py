#!/usr/bin/env python3
"""Heavy profiling worker launched by the stdlib-only watchdog supervisor."""

import argparse
import cProfile
import importlib
import json
import os
import pstats
import shutil
import signal
import sys
import time
import uuid
from pathlib import Path

import catan_training_experiment as experiment

supervisor = importlib.import_module("profile-catan-training")
reconstruction = importlib.import_module("run-catan-reconstruction")
PROFILE_SCOPE = (
    "Cold trainer initialization, training, periodic/final evaluation and saves; "
    "wrapper imports/provenance and CUDA device preflight excluded. "
    "Trainer warmup retained, not separated. "
    "Host-call timings only: CUDA waits can be charged to cpu/item calls. "
    "Python transition bookkeeping and GAE share the trainer main frame."
)


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
    experiment_metadata = None
    if options.updates is not None:
        if (
            "--vp-delta-final" in command
            or command[command.index("--vp-delta") + 1] != "0"
        ):
            raise ValueError(
                "equal-update experiments require terminal reward without annealing"
            )
        command[3], experiment_metadata = experiment.entry(
            options.source, options.output, options.snapshot_mode, options.updates
        )
    write_json(
        options.output / "manifest.json",
        {
            "schema_version": 1,
            "upstream": reconstruction.replay.provenance(
                options.source, oracle, binding
            ),
            "wrapper_sha256": reconstruction.digest(Path(supervisor.__file__)),
            "worker_sha256": reconstruction.digest(Path(__file__)),
            "reconstruction_sha256": reconstruction.digest(
                Path(reconstruction.__file__)
            ),
            "parent": str(options.parent),
            "parent_sha256": options.parent_sha256,
            "command": command,
            "mode": options.mode,
            "run_name": name,
            **(
                {"experiment": experiment_metadata, "worker_pid": os.getpid()}
                if experiment_metadata is not None
                else {}
            ),
            "training_seconds": options.seconds,
            "watchdog_seconds": options.seconds + supervisor.FINISH_ALLOWANCE_SECONDS,
            "profile_scope": PROFILE_SCOPE,
            "gpu_lock": str(options.gpu_lock) if options.gpu_lock is not None else None,
            **device_metadata(options.device),
        },
    )
    return command


def save_profile(
    output: Path,
    profiler: cProfile.Profile,
    mode: str,
    elapsed: float,
    completed: bool,
    measure_memory: bool = False,
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
            **(
                {"peak_rss_bytes": experiment.peak_rss_bytes()}
                if measure_memory
                else {}
            ),
            "functions": functions,
        },
    )


def run_trainer(
    command: list[str],
    source: Path,
    output: Path,
    mode: str,
    measure_memory: bool = False,
) -> None:
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
        save_profile(output, profiler, mode, elapsed, completed, measure_memory)


def experiment_result(options: argparse.Namespace, run: Path, checkpoint: dict) -> dict:
    """Validate equal work before publishing experimental evidence, never a default."""
    if options.updates is None:
        return {}
    experiment.validate_work(checkpoint, options.updates)
    experiment.validate_metrics(run, options.updates)
    return {
        "checkpoint_content_digests": experiment.checkpoint_digests(
            run, options.updates
        ),
        "cuda_peak_allocated_bytes": (
            reconstruction.torch.cuda.max_memory_allocated()
            if options.device == "cuda"
            else None
        ),
        "cuda_peak_reserved_bytes": (
            reconstruction.torch.cuda.max_memory_reserved()
            if options.device == "cuda"
            else None
        ),
    }


def worker(options: argparse.Namespace) -> None:
    name = f"profile-{options.mode}-{uuid.uuid4().hex}"
    command = prepare_run(options, name)
    signal.signal(signal.SIGTERM, reconstruction.terminate_job)
    if options.device == "cuda" and options.updates is not None:
        reconstruction.torch.cuda.reset_peak_memory_stats()
    run_options = {"measure_memory": True} if options.updates is not None else {}
    run_trainer(command, options.source, options.output, options.mode, **run_options)
    runs = list((options.source / "training/runs").glob(f"*-{name}"))
    if len(runs) != 1:
        raise ValueError(f"expected one upstream run, found {len(runs)}")
    checkpoint = reconstruction.inspect_checkpoint(runs[0])
    measurements = experiment_result(options, runs[0], checkpoint)
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
            **measurements,
            "finite_checkpoint_and_metrics": True,
            "strength_claim": False,
        },
    )


if __name__ == "__main__":
    worker(supervisor.parse_options())
