"""Opt-in, hash-pinned experiments; never edit the frozen upstream checkout."""

import contextlib
import hashlib
import json
import os
import resource
import signal
import sys
import threading
from pathlib import Path
from typing import Iterator

PPO_SHA256 = "720ecfa3971314b0feeed6cd11283ecbeea158b7d70d4deab1b73b0948bb7f42"
MAX_UPDATES = 100
RSS_ABORT_BYTES = 8 * 1024**3
MEMORY_POLL_SECONDS = 0.25
MEMORY_THREAD_JOIN_SECONDS = 1


def transform(source: str, mode: str, updates: int) -> str:
    """Keep ordering/GAE intact; fail closed when upstream or patch anchors drift."""
    if hashlib.sha256(source.encode()).hexdigest() != PPO_SHA256:
        raise ValueError("experimental trainer source SHA-256 mismatch")
    if mode not in ("row", "batch") or not 0 < updates <= MAX_UPDATES:
        raise ValueError("unsupported snapshot mode or update limit")
    patches = [
        (
            "while time.time() < deadline:",
            f"while update < {updates} and time.time() < deadline:",
        )
    ]
    if mode == "batch":
        patches.extend(
            [
                (
                    "                for i in range(args.num_envs):\n                    key = (i, int(seats[i]))\n                    rec = {",
                    "                snapshot_obs, snapshot_masks = obs.copy(), masks.copy()\n                for i in range(args.num_envs):\n                    key = (i, int(seats[i]))\n                    rec = {",
                ),
                (
                    '"obs": obs[i].copy(), "mask": masks[i].copy(),',
                    '"obs": snapshot_obs[i], "mask": snapshot_masks[i],',
                ),
            ]
        )
    for before, after in patches:
        if source.count(before) != 1:
            raise ValueError("experimental trainer patch anchor is not unique")
        source = source.replace(before, after)
    return source


def entry(source: Path, output: Path, mode: str, updates: int) -> tuple[str, dict]:
    original = source / "training/ppo.py"
    generated = transform(original.read_text(), mode, updates)
    artifact = output / "executed-ppo.py"
    with artifact.open("x") as handle:
        handle.write(generated)
    metadata = {
        "snapshot_mode": mode,
        "updates": updates,
        "original_ppo_sha256": PPO_SHA256,
        "executed_ppo_sha256": hashlib.sha256(generated.encode()).hexdigest(),
        "helper_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    }
    command = (
        "import numpy as np; from pathlib import Path; "
        "from catan_training_experiment import execute; np.random.seed(0); "
        f"execute(Path({str(artifact)!r}), Path({str(original)!r}), "
        f"{metadata['executed_ppo_sha256']!r})"
    )
    return command, metadata


def peak_rss_bytes() -> int:
    # macOS reports bytes; Linux reports KiB. Rust/Rayon work in this process.
    value = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return int(value if sys.platform == "darwin" else value * 1024)


@contextlib.contextmanager
def memory_guard(output: Path) -> Iterator[None]:
    """Sampled stop, not a hard allocation barrier; watchdog still owns time."""
    stopped = threading.Event()

    def monitor() -> None:
        while not stopped.wait(MEMORY_POLL_SECONDS):
            peak = peak_rss_bytes()
            if peak > RSS_ABORT_BYTES:
                try:
                    (output / "memory-abort.json").write_text(
                        json.dumps({"peak_rss_bytes": peak})
                    )
                finally:
                    # A full disk must not disable the memory stop.
                    os.kill(os.getpid(), signal.SIGTERM)
                return

    thread = threading.Thread(target=monitor, daemon=True)
    thread.start()
    try:
        yield
    finally:
        stopped.set()
        thread.join(timeout=MEMORY_THREAD_JOIN_SECONDS)


def execute(artifact: Path, original: Path, expected_sha: str) -> None:
    source = artifact.read_bytes()
    if hashlib.sha256(source).hexdigest() != expected_sha:
        raise ValueError("executed trainer artifact SHA-256 mismatch")
    namespace = {"__file__": str(original), "__name__": "__main__"}
    with memory_guard(artifact.parent):
        exec(compile(source, str(artifact), "exec"), namespace, namespace)


def state_digest(value: object) -> str:
    """Hash actual model/Adam contents, not run metadata or pickle serialization."""
    import torch

    digest = hashlib.sha256()

    def visit(item: object) -> None:
        if torch.is_tensor(item):
            tensor = item.detach().cpu().contiguous()
            visit(("tensor", str(tensor.dtype), list(tensor.shape)))
            digest.update(tensor.reshape(-1).view(torch.uint8).numpy().tobytes())
        elif isinstance(item, dict):
            digest.update(b"dict:")
            for key in sorted(item, key=lambda key: (type(key).__name__, repr(key))):
                visit(key)
                visit(item[key])
            digest.update(b"end:")
        elif isinstance(item, (list, tuple)):
            digest.update(type(item).__name__.encode() + b":")
            for child in item:
                visit(child)
            digest.update(b"end:")
        else:
            raw = json.dumps(item, allow_nan=False).encode()
            digest.update(
                type(item).__name__.encode() + str(len(raw)).encode() + b":" + raw
            )

    visit(value)
    return digest.hexdigest()


def validate_work(checkpoint: dict, updates: int) -> None:
    if checkpoint["updates"] != updates or checkpoint["steps"] != updates * 256 * 96:
        raise ValueError(
            "equal-update experiment stopped before completing requested work"
        )


def validate_metrics(run: Path, updates: int) -> None:
    rows = [
        json.loads(line) for line in (run / "metrics.jsonl").read_text().splitlines()
    ]
    expected_steps = [index * 256 * 96 for index in range(1, updates + 1)]
    if [row["step"] for row in rows if row["t"] == "train"] != expected_steps:
        raise ValueError("equal-update training steps differ from requested work")
    eval_steps = [index * 256 * 96 for index in range(16, updates + 1, 16)]
    expected_evals = [
        (step, label)
        for step in [*eval_steps, expected_steps[-1]]
        for label in ("random-3", "heuristic-v1-3")
    ]
    actual = [(row["step"], row["vs"]) for row in rows if row["t"] == "eval"]
    if actual != expected_evals:
        raise ValueError("periodic/final evaluation sequence changed")


def checkpoint_digests(run: Path, updates: int) -> dict:
    import torch

    result = {}
    for path in sorted((run / "checkpoints").glob("step_*.pt")):
        checkpoint = torch.load(path, map_location="cpu", weights_only=False)
        step = checkpoint["global_step"]
        if str(step) in result or path.name != f"step_{step:010d}.pt":
            raise ValueError("duplicate or misnamed checkpoint step")
        result[str(step)] = {
            name: state_digest(checkpoint[name])
            for name in ("model_state", "optimizer_state")
        }
    expected = {
        str(index * 256 * 96) for index in (*range(16, updates + 1, 16), updates)
    }
    if set(result) != expected:
        raise ValueError("experiment checkpoint inventory differs from expected steps")
    return result
