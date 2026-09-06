"""One frozen four-arm experiment; no retries or reusable training scheduler."""

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path("/home/alex_ubuntu/empires-research")
TOOLS = ROOT / "victory-target-tools-20260906"
OUTPUT = ROOT / "victory-target-20260906"
SOURCE = ROOT / "original-v1"
PYTHON = SOURCE / ".venv/bin/python"
PARENT = (
    SOURCE
    / "training/runs/20260906-0030-gpu-baseline-20260906-r2-continuation/checkpoints/step_0148807680.pt"
)
PARENT_SHA = "b2b65d569ef2e56bbca9e6f6ecfd41b4c0905842803e62c3aff2aeec7d96dace"
BINDING_SHA = "1cedb54260dfa407135981e1fdbf35608a1b739a5168164424f02010701c0198"
CUTOFF = dt.datetime(2026, 9, 6, 21, 30, tzinfo=dt.timezone.utc)
ARMS = [
    ("seed0-control7", 0, 7),
    ("seed0-target10", 0, 10),
    ("seed1-target10", 1, 10),
    ("seed1-control7", 1, 7),
]


def verify_tools():
    for name, expected in json.loads((TOOLS / "tool-sha256.json").read_text()).items():
        if hashlib.sha256((TOOLS / name).read_bytes()).hexdigest() != expected:
            raise ValueError(f"frozen tool changed: {name}")


def main():
    # Exclusive receipt prevents accidentally dispatching this sequence twice.
    with (OUTPUT / "sequence-started.json").open("x") as handle:
        json.dump(
            {
                "started": dt.datetime.now(dt.timezone.utc).isoformat(),
                "arms": ARMS,
                "inner_seconds": 600,
                "outer_seconds": 720,
            },
            handle,
        )
    environment = dict(os.environ, PYTHONPATH=f'{TOOLS}:{SOURCE / "training"}')
    for name, seed, target in ARMS:
        verify_tools()
        if dt.datetime.now(dt.timezone.utc) >= CUTOFF:
            raise RuntimeError("predeclared launch cutoff reached")
        device = subprocess.check_output(
            [
                "/usr/lib/wsl/lib/nvidia-smi",
                "--query-compute-apps=pid,used_memory",
                "--format=csv,noheader",
            ],
            text=True,
            timeout=10,
        )
        if device.strip():
            raise RuntimeError(
                f"GPU already has a compute workload; leave it alone: {device}"
            )
        output = OUTPUT / name
        if output.exists():
            raise RuntimeError(f"arm already exists; no retry: {name}")
        command = [
            str(PYTHON),
            str(TOOLS / "profile-catan-training.py"),
            "--source",
            str(SOURCE),
            "--output",
            str(output),
            "--parent",
            str(PARENT),
            "--parent-sha256",
            PARENT_SHA,
            "--binding-sha256",
            BINDING_SHA,
            "--device",
            "cuda",
            "--gpu-lock",
            "/home/alex_ubuntu/gc-data/.gpu.exclusive.lock",
            "--mode",
            "none",
            "--seconds",
            "600",
            "--updates",
            "800",
            "--snapshot-mode",
            "row",
            "--long-experiment",
            "--training-seed",
            str(seed),
            "--victory-target",
            str(target),
        ]
        print(
            json.dumps(
                {
                    "starting": name,
                    "utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                    "command": command,
                }
            ),
            flush=True,
        )
        subprocess.run(command, env=environment, check=True)
        receipt = json.loads((output / "run.watchdog.json").read_text())
        result = json.loads((output / "result.json").read_text())
        checkpoint = result["checkpoint"]
        if (
            receipt["state"] != "complete"
            or receipt["exit_code"] != 0
            or checkpoint["updates"] != 800
            or checkpoint["steps"] != 19660800
            or checkpoint["config"]["seed"] != seed
            or checkpoint["config"]["victory_target"] != target
            or not result["finite_checkpoint_and_metrics"]
        ):
            raise ValueError(f"arm did not satisfy completed-work checks: {name}")
        print(
            json.dumps(
                {"completed": name, "utc": dt.datetime.now(dt.timezone.utc).isoformat()}
            ),
            flush=True,
        )
    with (OUTPUT / "sequence-complete.json").open("x") as handle:
        json.dump(
            {"completed": dt.datetime.now(dt.timezone.utc).isoformat(), "arms": ARMS},
            handle,
        )


if __name__ == "__main__":
    main()
