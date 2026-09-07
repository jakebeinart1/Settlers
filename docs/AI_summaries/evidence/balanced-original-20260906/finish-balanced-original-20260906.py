#!/usr/bin/env python3
"""Time-only repair for the fixed comparison; reuse the existing evaluator.

The first watchdog is never changed. Only its timed-out original-model arm may
be repeated, against byte-identical artifacts, with complete prefix agreement.
Run this once through the existing 600-second watchdog, never directly.
"""

import argparse
import datetime
import importlib.util
import json
import os
import shutil
import sys
from pathlib import Path

REPO = Path("/private/tmp/empires-policy-decision-trace-20260906")
sys.path.insert(0, str(REPO / "scripts"))
SPEC = importlib.util.spec_from_file_location(
    "evaluation", REPO / "scripts/evaluate-bots.py"
)
EVALUATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EVALUATION)
LAUNCH_CUTOFF = datetime.datetime(2026, 9, 7, tzinfo=datetime.timezone.utc)


def verify_artifacts(root: Path, manifest: dict) -> None:
    for name, digest in manifest["artifacts"].items():
        if EVALUATION.digest(root / name) != digest:
            raise ValueError(f"frozen artifact changed: {name}")
    if EVALUATION.source_snapshot() != manifest["source_files"]:
        raise ValueError("evaluator or policy source changed")


def validate_original(root: Path) -> dict:
    receipt = json.loads((root / "run.watchdog.json").read_text())
    if receipt.get("state") not in {"timed_out", "failed"} or receipt.get("exit_code") != 124:
        raise ValueError(
            "repair requires a terminal timeout, never a cap/audit failure"
        )
    if "finished_utc" not in receipt:
        raise ValueError("wait for watchdog cleanup to finish")
    try:
        os.killpg(receipt["process_group"], 0)
    except ProcessLookupError:
        pass
    else:
        raise ValueError("original owned process group is still present")
    manifest = json.loads((root / "manifest.json").read_text())
    expected = EVALUATION.read_config(
        REPO / "config/evaluation/balanced-vs-original-balanced.json"
    )
    if manifest["config"] != expected:
        raise ValueError("only the predeclared Balanced-opponent group can be repaired")
    verify_artifacts(root, manifest)
    for seat in range(manifest["config"]["players"]):
        EVALUATION.validate_shard(
            root / f"candidate-seat{seat}.jsonl", manifest["config"]
        )
        EVALUATION.validate_audit(
            root / f"candidate-seat{seat}.audit.jsonl",
            root / f"candidate-seat{seat}.jsonl",
            set(),
        )
    for path in root.glob("baseline-seat[0-3].jsonl"):
        if any(
            json.loads(line)["winner"] is None for line in path.read_text().splitlines()
        ):
            raise ValueError("a capped game does not qualify for time-only repair")
    return manifest


def copy_inputs(original: Path, output: Path, manifest: dict) -> list[Path]:
    output.mkdir(parents=True, exist_ok=False)
    shutil.copytree(original / "frozen", output / "frozen")
    candidates = []
    for seat in range(manifest["config"]["players"]):
        for suffix in ("jsonl", "audit.jsonl"):
            name = f"candidate-seat{seat}.{suffix}"
            shutil.copy2(original / name, output / name)
        candidates.append(output / f"candidate-seat{seat}.jsonl")
    EVALUATION.write_json(output / "manifest.json", manifest)
    EVALUATION.write_json(
        output / "repair.json",
        {
            "original": str(original),
            "original_manifest_sha256": EVALUATION.digest(original / "manifest.json"),
            "original_watchdog_sha256": EVALUATION.digest(
                original / "run.watchdog.json"
            ),
            "repair_source_sha256": EVALUATION.digest(Path(__file__)),
            "reason": "time-only completion of the unchanged fixed game set; no control rerun",
        },
    )
    verify_artifacts(output, manifest)
    return candidates


def verify_prefixes(original: Path, output: Path) -> int:
    repeated = 0
    for path in sorted(original.glob("baseline-seat[0-3]*.jsonl")):
        previous = path.read_bytes().splitlines(keepends=True)
        current = (output / path.name).read_bytes().splitlines(keepends=True)
        if current[: len(previous)] != previous:
            raise ValueError(f"repeated prefix changed: {path.name}")
        if not path.name.endswith(".audit.jsonl"):
            repeated += len(previous)
    return repeated


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    options = parser.parse_args()
    if datetime.datetime.now(datetime.timezone.utc) >= LAUNCH_CUTOFF:
        raise ValueError("time-only repair launch window is closed")
    original, output = options.original.resolve(), options.output.resolve()
    manifest = validate_original(original)
    candidates = copy_inputs(original, output, manifest)
    config, policies = manifest["config"], manifest["policy_ids"]
    baselines = EVALUATION.run_arm(
        config,
        "baseline",
        output / "frozen/sim",
        manifest["build_id"],
        policies["baseline"],
        output,
    )
    repeated = verify_prefixes(original, output)
    EVALUATION.analyze(
        config,
        policies,
        manifest["build_id"],
        {"candidate": candidates, "baseline": baselines},
        output,
    )
    verify_artifacts(output, manifest)
    EVALUATION.write_json(
        output / "complete.json",
        {
            "games": 2 * config["players"] * config["seeds"],
            "repeated_prefix_games": repeated,
            "strength_claim": False,
            "original_attempt_stays_failed": True,
        },
    )


if __name__ == "__main__":
    main()
