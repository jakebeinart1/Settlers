#!/usr/bin/env python3
"""One-shot diagnostic dispatch; no training, retries, or strength sampling."""

import argparse
import importlib.util
import json
import signal
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path("/private/tmp/empires-policy-decision-trace-20260906")
OUTPUT = Path("/tmp/empires-cap-replays-20260906")
CUTOFF = datetime(2026, 9, 6, 22, 0, tzinfo=timezone.utc)
sys.path.insert(0, str(REPO / "scripts"))
import training_watchdog as watchdog

SPEC = importlib.util.spec_from_file_location(
    "evaluation", REPO / "scripts/evaluate-bots.py"
)
evaluation = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(evaluation)

CASES = (
    (
        "candidate",
        961131,
        1,
        "4b504877db53efef",
        [6, 9, 5, 5],
        "/tmp/empires-target-native-seed0-20260906/candidate-seat1.audit.jsonl",
        "b5e4ecef685a7ebefe32969c07be4dbf18b5a3ba05aab5b857cf1902535f206e",
        "seed0-target10.ctnn",
    ),
    (
        "baseline",
        961105,
        3,
        "88e4e5bcbee25ab1",
        [8, 5, 4, 9],
        "/tmp/empires-target-native-seed1-20260906/baseline-seat3.audit.jsonl",
        "ebf6524fc0e242965e5be3381d448a97dd0a70e9fe43a8f80a52e56f6d709863",
        "seed1-control7.ctnn",
    ),
)
EXPORTS = Path(
    "/Users/alex/Library/Application Support/EmpiresResearch/experiments/victory-target-20260906/exports"
)


def artifacts() -> dict[str, str]:
    return {
        str(path.relative_to(OUTPUT)): evaluation.digest(path)
        for path in sorted((OUTPUT / "frozen").rglob("*"))
        if path.is_file()
    }


def prepare() -> None:
    OUTPUT.mkdir()
    config = {
        case[0]: {"checkpoint": str(EXPORTS / case[7]), "sha256": case[6]}
        for case in CASES
    }
    before = evaluation.source_snapshot()
    evaluation.freeze_build(config, OUTPUT)
    if evaluation.source_snapshot() != before:
        raise ValueError("source changed while freezing diagnostic executable")
    evaluation.write_json(
        OUTPUT / "manifest.json",
        {
            "schema_version": 1,
            "source_files": before,
            "artifacts": artifacts(),
            "launcher_sha256": evaluation.digest(Path(__file__)),
            "cases": CASES,
            "launch_cutoff_utc": CUTOFF.isoformat(),
            "budget_seconds_per_case": 90,
            "strength_claim": False,
        },
    )


def run_case(case: tuple) -> None:
    arm, seed, chair, fingerprint, points, original_audit, sha, _ = case
    prefix = OUTPUT / arm
    roster = ["greedy"] * 4
    roster[chair] = "neural-checkpoint"
    command = [
        str(OUTPUT / "frozen/sim"),
        "--games",
        "1",
        "--seed",
        str(seed),
        "--players",
        "4",
        "--victory-points",
        "10",
        "--board",
        "randomized",
        "--seats",
        ",".join(roster),
        "--jsonl",
        "--build-id",
        "cap-diagnostic-" + evaluation.digest(OUTPUT / "frozen/sim"),
        "--neural-checkpoint",
        str(OUTPUT / f"frozen/{arm}.ctnn"),
        "--neural-checkpoint-id",
        "sha256-" + sha,
        "--policy-audit-jsonl",
        str(OUTPUT / f"{arm}.audit.jsonl"),
        "--decision-trace-jsonl",
        str(OUTPUT / f"{arm}.trace.jsonl"),
    ]
    if datetime.now(timezone.utc) >= CUTOFF:
        raise ValueError("launch cutoff reached; no extension")
    code = watchdog.run(command, prefix, 90)
    if code != 0:
        raise ValueError(f"{arm} diagnostic failed with exit {code}; no retry")
    lines = prefix.with_suffix(".launcher.log").read_text().splitlines()
    results = [json.loads(line) for line in lines if line.startswith("{")]
    if len(results) != 1:
        raise ValueError("expected exactly one game result")
    result = results[0]
    if result["fingerprint"] != fingerprint:
        raise ValueError("diagnostic fingerprint differs from original")
    if (
        result["vp"] != points
        or result["moves"] != 3000
        or result["winner"] is not None
    ):
        raise ValueError("diagnostic outcome differs from original")
    original = [
        json.loads(line)
        for line in Path(original_audit).read_text().splitlines()
        if json.loads(line)["seed"] == seed
    ]
    current = [
        json.loads(line)
        for line in (OUTPUT / f"{arm}.audit.jsonl").read_text().splitlines()
    ]
    if len(original) != 1 or current != original:
        raise ValueError("diagnostic policy audit differs from original")
    evaluation.write_json(
        OUTPUT / f"{arm}.verified.json",
        {
            "fingerprint_matches": True,
            "outcome_matches": True,
            "full_policy_audit_matches": True,
            "result": result,
        },
    )


def run() -> None:
    manifest = json.loads((OUTPUT / "manifest.json").read_text())
    if artifacts() != manifest["artifacts"]:
        raise ValueError("frozen artifact changed")
    if evaluation.digest(Path(__file__)) != manifest["launcher_sha256"]:
        raise ValueError("launcher changed after freeze")
    with (OUTPUT / "dispatch-started.json").open("x") as handle:
        json.dump({"started_utc": datetime.now(timezone.utc).isoformat()}, handle)
    for case in CASES:
        run_case(case)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("prepare", "run"))
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, watchdog.interrupted)
    {"prepare": prepare, "run": run}[args.stage]()
