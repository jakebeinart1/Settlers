#!/usr/bin/env python3
"""Bound a training pipeline independently of the trainer and desktop watcher.

The receipt is the clock authority: UTC strings are derived from epoch seconds,
never from a local-time directory name. On Linux, CLOCK_BOOTTIME also includes
suspend time. The first exhausted wall/boot-time budget ends the owned process
group with TERM then KILL. No retries or checkpoint selection occur here.
"""

import argparse
import hashlib
import json
import math
import os
import signal
import subprocess
import time
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

MAX_SECONDS = 10800
POLL_SECONDS = 1
GRACE_SECONDS = 5
STALE_SECONDS = 30


def elapsed_clock() -> float:
    """Linux boot time counts suspend; macOS tests use monotonic elapsed time."""
    if hasattr(time, "CLOCK_BOOTTIME"):
        return time.clock_gettime(time.CLOCK_BOOTTIME)
    return time.monotonic()


def utc_timestamp(epoch: float) -> str:
    return datetime.fromtimestamp(epoch, timezone.utc).isoformat()


@dataclass(frozen=True)
class Deadline:
    seconds: float
    started_epoch: float
    started_elapsed: float

    def __post_init__(self) -> None:
        if not math.isfinite(self.seconds) or not 0 < self.seconds <= MAX_SECONDS:
            raise ValueError(f"budget must be finite and in (0, {MAX_SECONDS}]")

    def remaining(self, now_epoch: float, now_elapsed: float) -> float:
        return self.seconds - max(
            now_epoch - self.started_epoch, now_elapsed - self.started_elapsed
        )

    def record(self) -> dict:
        return {
            "budget_seconds": self.seconds,
            "started_epoch": self.started_epoch,
            "started_elapsed": self.started_elapsed,
            "started_utc": utc_timestamp(self.started_epoch),
            "deadline_epoch": self.started_epoch + self.seconds,
            "deadline_utc": utc_timestamp(self.started_epoch + self.seconds),
        }


def receipt_path(output: Path) -> Path:
    return output.with_name(output.name + ".watchdog.json")


def boot_identity() -> str:
    path = Path("/proc/sys/kernel/random/boot_id")
    return path.read_text().strip() if path.exists() else "unavailable"


def process_identity(pid: int) -> str | None:
    """Linux start ticks distinguish our process from a subsequently reused PID."""
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
    except FileNotFoundError:
        return None
    fields = stat.rsplit(")", 1)[1].split()
    return None if fields[0] == "Z" else fields[19]


@contextmanager
def cleanup_shield():
    """Repeated TERM/INT cannot interrupt the escalation already in progress."""
    previous = {
        sig: signal.signal(sig, signal.SIG_IGN)
        for sig in (signal.SIGTERM, signal.SIGINT)
    }
    try:
        yield
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def write_receipt(path: Path, state: dict) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(state, indent=2, allow_nan=False) + "\n")
    temporary.replace(path)


def terminate_group(process: subprocess.Popen, grace_seconds: float) -> None:
    """Kill descendants even if their parent already exited after TERM."""
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        process.wait(timeout=grace_seconds)
        return
    time.sleep(grace_seconds)
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass  # The owned group already exited, which is the desired result.
    process.wait(timeout=grace_seconds)


def monitor(
    process: subprocess.Popen, path: Path, state: dict, deadline: Deadline
) -> int:
    while True:
        remaining = deadline.remaining(time.time(), elapsed_clock())
        state.update(
            remaining_seconds=remaining,
            checked_epoch=time.time(),
            checked_utc=utc_timestamp(time.time()),
        )
        code = process.poll()
        if code is not None:
            state.update(state="complete" if code == 0 else "failed", exit_code=code)
            return code
        if remaining <= 0:
            state.update(state="timed_out", exit_code=124)
            return 124
        write_receipt(path, state)
        time.sleep(min(POLL_SECONDS, remaining))


def interrupted(signum: int, _frame: object) -> None:
    raise InterruptedError(f"watchdog received signal {signum}")


def run(
    command: list[str],
    output: Path,
    seconds: float,
    grace_seconds: float = GRACE_SECONDS,
) -> int:
    """Launch once, publish live receipts, and clean up only the owned group."""
    if not math.isfinite(grace_seconds) or not 0 < grace_seconds <= 30:
        raise ValueError("shutdown grace must be finite and in (0, 30]")
    deadline = Deadline(seconds, time.time(), elapsed_clock())
    path = receipt_path(output)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x"):
        pass  # Exclusive reservation prevents two launches using this run ID.
    state = dict(
        deadline.record(),
        state="starting",
        command=command,
        watchdog_pid=os.getpid(),
        watchdog_identity=process_identity(os.getpid()),
        boot_identity=boot_identity(),
        watchdog_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    )
    process = None
    try:
        with output.with_name(output.name + ".launcher.log").open("x") as log:
            process = subprocess.Popen(
                command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True
            )
            state.update(
                state="running",
                process_group=process.pid,
                process_identity=process_identity(process.pid),
            )
            return monitor(process, path, state, deadline)
    except BaseException as error:
        state.update(state="failed", error=repr(error))
        raise
    finally:
        try:
            if process is not None:
                with cleanup_shield():
                    terminate_group(process, grace_seconds)
        except BaseException as error:
            state.update(state="failed", cleanup_error=repr(error))
            raise
        finally:
            state["finished_utc"] = utc_timestamp(time.time())
            write_receipt(path, state)


def inspect(output: Path) -> dict:
    """Read receipts on the training host; never compare handwritten local dates."""
    state = json.loads(receipt_path(output).read_text())
    deadline = Deadline(
        state["budget_seconds"], state["started_epoch"], state["started_elapsed"]
    )
    state["remaining_seconds_now"] = deadline.remaining(time.time(), elapsed_clock())
    state["observed_utc"] = utc_timestamp(time.time())
    if state["state"] in ("running", "starting"):
        state["supervision"] = supervision_health(state)
        if state["supervision"] != "live":
            state["state"] = "supervision_lost"
    pipeline = output / "status.json"
    if pipeline.exists():
        state["pipeline"] = json.loads(pipeline.read_text())
    return state


def supervision_health(state: dict) -> str:
    if state["boot_identity"] == "unavailable":
        return "process_identity_unavailable"
    if state["boot_identity"] != boot_identity():
        return "host_rebooted"
    identity = process_identity(state["watchdog_pid"])
    if identity is None or identity != state["watchdog_identity"]:
        return "guardian_missing_or_replaced"
    if time.time() - state["checked_epoch"] > STALE_SECONDS:
        return "stale_receipt"
    return "live"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("run", "inspect"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seconds", type=float, default=MAX_SECONDS)
    args, command = parser.parse_known_args()
    if args.mode == "inspect":
        if command:
            parser.error("inspect does not accept a command")
        print(json.dumps(inspect(args.output.resolve()), indent=2))
        return
    if not command or command.pop(0) != "--" or not command:
        parser.error("run requires -- followed by the training command")
    signal.signal(signal.SIGTERM, interrupted)
    raise SystemExit(run(command, args.output.resolve(), args.seconds))


if __name__ == "__main__":
    main()
