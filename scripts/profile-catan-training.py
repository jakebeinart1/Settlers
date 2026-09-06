#!/usr/bin/env python3
"""Profile one unmodified upstream continuation, never promote its checkpoint.

Run in the isolated upstream environment with scripts and upstream/training on
PYTHONPATH. Each invocation owns an outer watchdog and a unique upstream run.
Use --mode none as the unprofiled control; cProfile measures host-call time,
including cold trainer initialization and periodic/final evaluation, not CUDA
kernel durations or separately timed rollout/GAE/update phases.
"""

import argparse
import math
import signal
import sys
from pathlib import Path
from typing import Optional

import training_watchdog as watchdog

MAX_TRAINING_SECONDS = 120
FINISH_ALLOWANCE_SECONDS = 120


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
    parser.add_argument(
        "--gpu-lock", type=Path, help="Shared advisory lock; required for CUDA"
    )
    options = parser.parse_args(arguments)
    if options.device == "cuda" and options.gpu_lock is None:
        parser.error("--gpu-lock is required for --device cuda")
    if (
        not math.isfinite(options.seconds)
        or not 0 < options.seconds <= MAX_TRAINING_SECONDS
    ):
        parser.error(f"--seconds must be finite and in (0, {MAX_TRAINING_SECONDS}]")
    for name in ("source", "output", "parent"):
        setattr(options, name, getattr(options, name).resolve())
    if options.gpu_lock is not None:
        options.gpu_lock = options.gpu_lock.resolve()
    return options


def main(arguments: Optional[list[str]] = None) -> int:
    arguments = sys.argv[1:] if arguments is None else arguments
    options = parse_options(arguments)
    options.output.mkdir(parents=True, exist_ok=False)
    command = [
        sys.executable,
        "-B",
        "-u",
        str(Path(__file__).resolve().with_name("profile_catan_worker.py")),
        *arguments,
    ]
    if options.device == "cuda":
        # Launch even lock acquisition under the watchdog so refusal is retained.
        command = ["flock", "--nonblock", str(options.gpu_lock), *command]
    signal.signal(signal.SIGTERM, watchdog.interrupted)
    return watchdog.run(
        command, options.output / "run", options.seconds + FINISH_ALLOWANCE_SECONDS
    )


if __name__ == "__main__":
    raise SystemExit(main())
