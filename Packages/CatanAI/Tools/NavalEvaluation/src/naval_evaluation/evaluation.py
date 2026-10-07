#!/usr/bin/env python3
"""Portable validation and execution around the exact preregistered naval study.

The original analyzer remains immutable. The canonical paired CI corrects only
floating-point zero-bound roundoff using integer counts and the same resamples.
This correction was specified before any held-out result interpretation.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import itertools
import json
import pathlib
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Any

from naval_evaluation.revisits import preserve
from naval_evaluation.statistics import paired_integers

FAMILIES = ("archipelago", "peninsula", "twinIslands")
POLICY_IDS = {
    "traditional": "naval-traditional-v1",
    "expert": "naval-expert-v1",
    "land-control": "naval-traditional-land-control-v1",
}
STAGES = (
    "matrix",
    "mixed-development",
    "land-development",
    "held-out",
    "uncontended-latency",
)
VERSIONS = {
    "schemaVersion": 3,
    "protocolVersion": 3,
    "mapVersion": 1,
    "rulesVersion": 1,
    "engineRulesVersion": 3,
    "actionLimit": 6000,
    "victoryPointTarget": 14,
}
FROZEN_HASHES = {
    "run_measurement.py": "e97b51d97b9c89aa3934dca596a251f5c4f9491fc2cd484fd0e0e35b2002597b",
    "analyze_measurement.py": "cb99704bc5250bb513470247e901f8c329eeeecf0815ecb78c1837fbab9b1672",
    "check_traditional_invariance.py": "187d0523a67b746b57f6301a1558a46dc64328c8a9e3657fc6bf96323c2e7e87",
}
ROOT = pathlib.Path(__file__).resolve().parents[2]
TIMING_PATTERN = re.compile(
    r"seed=(\d+) decisions=(\d+) p95=([\d.]+)ms p99=([\d.]+)ms "
    r"over50=(\d+) over150=(\d+)"
)


def read_json(path: pathlib.Path) -> Any:
    """Read an evidence record without inventing defaults for missing fields."""
    return json.loads(path.read_text())


def sha256(path: pathlib.Path) -> str:
    """Hash an immutable artifact or script."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_frozen_scripts() -> None:
    """Reject modification to any script frozen before confirmation."""
    for name, expected in FROZEN_HASHES.items():
        if sha256(ROOT / "frozen" / name) != expected:
            raise ValueError(f"frozen script changed: {name}")


def verify_evidence(directory: pathlib.Path) -> None:
    """Verify every retained evidence file against its committed byte digest."""
    expected = read_json(directory / "checksums.json")
    actual = {
        str(path.relative_to(directory))
        for path in directory.rglob("*")
        if path.is_file() and path.name != "checksums.json"
    }
    if set(expected) != actual:
        raise ValueError("missing or extra retained evidence files")
    for name, digest in expected.items():
        path = directory / name
        if not path.resolve().is_relative_to(directory.resolve()):
            raise ValueError("evidence path escapes its directory")
        if sha256(path) != digest:
            raise ValueError(f"retained evidence changed: {name}")


def artifact(binary: pathlib.Path) -> dict[str, Any]:
    """Require the executable to match its premeasurement Release manifest."""
    manifest = read_json(binary.parent / "provenance.json")
    if sha256(binary) != manifest["sha256"]:
        raise ValueError(f"artifact changed: {binary}")
    if manifest["configuration"] != "Release":
        raise ValueError("measurement requires a Release artifact")
    for key in ("schemaVersion", "protocolVersion", "mapVersion", "engineRulesVersion"):
        if manifest[key] != VERSIONS[key]:
            raise ValueError(f"artifact version mismatch: {key}")
    if manifest["navalRulesVersion"] != VERSIONS["rulesVersion"]:
        raise ValueError("artifact naval rules mismatch")
    return manifest


@dataclass(frozen=True)
class Job:
    """One complete seed range, cell, table, arm, and occupied focal chair."""

    cell: int
    family: str
    fog: bool
    wild: bool
    players: int
    arm: str
    chair: int
    seats: tuple[str, ...]
    seed: int
    games: int

    @property
    def name(self) -> str:
        return f"{self.cell}-{self.players}-{self.arm}-{self.chair}"

    def command(self, binary: pathlib.Path, source: str) -> list[str]:
        return [
            str(binary),
            "--games",
            str(self.games),
            "--seed",
            str(self.seed),
            "--players",
            str(self.players),
            "--family",
            self.family,
            "--fog",
            "on" if self.fog else "off",
            "--wild",
            "on" if self.wild else "off",
            "--seats",
            ",".join(self.seats),
            "--build-id",
            source,
            "--arm",
            self.arm,
            "--focal-chair",
            str(self.chair),
        ]


def plan(stage: str) -> list[Job]:
    """Expand the locked cell order, development seeds, and paired chair plan."""
    if stage not in STAGES:
        raise ValueError(f"unknown stage: {stage}")
    if stage == "uncontended-latency":
        return [job for job in plan("matrix") if job.arm == "expert"]
    jobs = []
    cells = itertools.product(FAMILIES, (True, False), (True, False))
    for cell, (family, fog, wild) in enumerate(cells):
        for players in (3, 4):
            if stage == "matrix":
                entries = [
                    (tier, 0, (tier,) * players) for tier in ("traditional", "expert")
                ]
                seed, games = 700000 + cell * 100, 1
            else:
                arms = (
                    ("candidate", "control")
                    if stage == "held-out"
                    else ("expert" if stage == "mixed-development" else "land-control",)
                )
                entries = []
                for arm in arms:
                    for chair in range(players):
                        focal = "expert" if arm == "candidate" else arm
                        seats = tuple(
                            focal if s == chair and arm != "control" else "traditional"
                            for s in range(players)
                        )
                        entries.append((arm, chair, seats))
                if stage == "held-out":
                    seed, games = 800000 + cell * 1000, 11 if players == 3 else 7
                else:
                    offset = 1 if stage == "mixed-development" else 3
                    seed, games = 700000 + cell * 100 + offset, 1
            for arm, chair, seats in entries:
                jobs.append(
                    Job(
                        cell, family, fog, wild, players, arm, chair, seats, seed, games
                    )
                )
    return jobs


def validate_process_records(
    directory: pathlib.Path, jobs: list[Job]
) -> dict[str, dict]:
    """Require every declared subprocess exactly once and a successful exit."""
    names = {job.name for job in jobs}
    if {path.stem for path in directory.glob("*.jsonl")} != names:
        raise ValueError("missing or extra measurement shards")
    records = read_json(directory / "jobs.json")
    if {record["name"] for record in records} != names or len(records) != len(jobs):
        raise ValueError("missing or duplicated subprocess records")
    if any(record["returncode"] != 0 for record in records):
        raise ValueError("failed simulation process")
    return {record["name"]: record for record in records}


def comparison_identity(directory: pathlib.Path) -> dict[str, Any]:
    """Require unambiguous source and binary identity before joining arms."""
    comparison = read_json(directory / "comparison.json")
    for key in ("candidateSource", "anchorSource", "engineOriginalCommit"):
        if not re.fullmatch(r"[0-9a-f]{40}", comparison[key]):
            raise ValueError(f"invalid source identity: {key}")
    for key in ("candidateSHA256", "anchorSHA256"):
        if not re.fullmatch(r"[0-9a-f]{64}", comparison[key]):
            raise ValueError(f"invalid artifact identity: {key}")
    return comparison


def rejection_count(rows: list[dict[str, Any]]) -> int:
    """Count real failures without conflating productive sailing revisits."""
    keys = ("forcedEnds", "idleSailingCycles", "tradeCycles", "duplicateProposals")
    return sum(
        bool(row["winner"] is None or any(row[key] for key in keys)) for row in rows
    )


def validate_row(row: dict[str, Any], job: Job, source: str) -> None:
    """Pin settings, policy identities, versions, and occupied seat telemetry."""
    expected = dict(
        VERSIONS,
        family=job.family,
        fogEnabled=job.fog,
        resourceChoiceEnabled=job.wild,
        playerCount=job.players,
        arm=job.arm,
        focalChair=job.chair,
        buildID=source,
        policies=[POLICY_IDS[seat] for seat in job.seats],
    )
    if any(row.get(key) != value for key, value in expected.items()):
        raise ValueError(f"row configuration or source mismatch: {job.name}")
    if row["winner"] is not None and row["winner"] not in range(job.players):
        raise ValueError(f"invalid winner: {job.name}")
    if len(row["behavior"]) != job.players:
        raise ValueError(f"missing seat behavior: {job.name}")
    if not 0 < row["moves"] <= VERSIONS["actionLimit"]:
        raise ValueError(f"action count exceeds declared budget: {job.name}")


def validate_executables(
    commands: list, comparison: dict, verify_binaries: bool
) -> None:
    """Pin one executable per source and optionally verify actual artifact bytes."""
    hashes = {
        comparison["candidateSource"]: comparison["candidateSHA256"],
        comparison["anchorSource"]: comparison["anchorSHA256"],
    }
    paths = {}
    for _, command in commands:
        source = command[command.index("--build-id") + 1]
        if source not in hashes:
            raise ValueError("unknown command artifact source")
        if source in paths and paths[source] != command[0]:
            raise ValueError("command executable differs within a frozen source")
        paths[source] = command[0]
    if verify_binaries:
        for source, binary in paths.items():
            manifest = artifact(pathlib.Path(binary))
            if (
                manifest["sourceCommit"] != source
                or manifest["sha256"] != hashes[source]
                or manifest["engineOriginalCommit"]
                != comparison["engineOriginalCommit"]
            ):
                raise ValueError(
                    "command artifact does not match comparison provenance"
                )


def validate_timing(directory: pathlib.Path, job: Job, rows: list[dict]) -> None:
    """Require each game's policy timing and every committed decision."""
    timings = TIMING_PATTERN.findall((directory / f"{job.name}.timing").read_text())
    if [int(timing[0]) for timing in timings] != list(
        range(job.seed, job.seed + job.games)
    ):
        raise ValueError(f"missing or mislabeled policy timing: {job.name}")
    if any(
        int(timing[1]) != row["moves"] or row["moves"] <= 0
        for timing, row in zip(timings, rows)
    ):
        raise ValueError(f"incomplete policy timing: {job.name}")
    if any(
        not 0 <= int(timing[5]) <= int(timing[4]) <= int(timing[1])
        for timing in timings
    ):
        raise ValueError(f"invalid latency counts: {job.name}")


def validate_shard(
    directory: pathlib.Path, job: Job, source: str, record: dict
) -> list[dict]:
    """Require the exact preregistered ordered seed range in each shard."""
    rows = [
        json.loads(line)
        for line in (directory / f"{job.name}.jsonl").read_text().splitlines()
        if line
    ]
    if len(rows) != job.games or record["games"] != job.games:
        raise ValueError(f"missing simulation rows: {job.name}")
    if [row["seed"] for row in rows] != list(range(job.seed, job.seed + job.games)):
        raise ValueError(f"seed range or order mismatch: {job.name}")
    for row in rows:
        validate_row(row, job, source)
    if record["rejects"] != rejection_count(rows):
        raise ValueError(f"subprocess rejection metadata mismatch: {job.name}")
    validate_timing(directory, job, rows)
    return rows


def validate_pairing(rows: list[dict[str, Any]]) -> None:
    """Require symmetric arms and identical control trajectories across chairs."""
    arms = {arm: set() for arm in ("candidate", "control")}
    controls = {}
    for row in rows:
        key = (
            row["family"],
            row["fogEnabled"],
            row["resourceChoiceEnabled"],
            row["playerCount"],
            row["seed"],
        )
        arms[row["arm"]].add(key + (row["focalChair"],))
        if row["arm"] == "control":
            fingerprint = row["fingerprint"]
            if key in controls and controls[key] != fingerprint:
                raise ValueError("control trajectories differ across chairs")
            controls[key] = fingerprint
    if arms["candidate"] != arms["control"]:
        raise ValueError("candidate and control keys differ")


def validate_rows(
    directory: pathlib.Path, stage: str, verify_binaries: bool = False
) -> list[dict[str, Any]]:
    """Reject missing/mislabeled evidence; keep null winners as null."""
    jobs = plan(stage)
    records = validate_process_records(directory, jobs)
    comparison = comparison_identity(directory)
    command_records = read_json(directory / "commands.json")
    if {record[0] for record in command_records} != {job.name for job in jobs} or len(
        command_records
    ) != len(jobs):
        raise ValueError("missing or duplicated command records")
    commands = dict(command_records)
    rows = []
    for job in jobs:
        source_key = (
            "anchorSource"
            if stage == "held-out" and job.arm == "control"
            else "candidateSource"
        )
        source = comparison[source_key]
        command = commands[job.name]
        if command != job.command(pathlib.Path(command[0]), source):
            raise ValueError(f"command configuration or source mismatch: {job.name}")
        rows.extend(validate_shard(directory, job, source, records[job.name]))
    if stage == "held-out":
        validate_pairing(rows)
    validate_executables(command_records, comparison, verify_binaries)
    return rows


def analyze(
    directory: pathlib.Path, stage: str, verify_binaries: bool = True
) -> dict[str, Any]:
    """Validate all shards, then invoke the byte-identical frozen CI calculation."""
    verify_frozen_scripts()
    rows = validate_rows(directory, stage, verify_binaries)
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "frozen" / "analyze_measurement.py"),
            str(directory),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    report = read_json(directory / "analysis.json")
    report["artifactVerification"] = (
        "binary SHA256 and manifest"
        if verify_binaries
        else "offline recorded provenance only"
    )
    if stage == "held-out":
        (directory / "analysis-frozen-original.json").write_bytes(
            (directory / "analysis.json").read_bytes()
        )
        for players in (3, 4):
            report["byTable"][str(players)]["paired"].update(
                paired_integers(rows, players)
            )
        report["analysisArithmetic"] = "integer paired counts; one final division"
        report["frozenAnalyzerSHA256"] = FROZEN_HASHES["analyze_measurement.py"]
    (directory / "analysis.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n"
    )
    return report


def execute(
    candidate: pathlib.Path,
    anchor: pathlib.Path,
    stage: str,
    output: pathlib.Path,
    workers: int,
) -> None:
    """Run a portable copy of the preregistered plan without overwriting evidence."""
    if stage == "uncontended-latency" and workers != 1:
        raise ValueError("uncontended latency requires one worker")
    verify_frozen_scripts()
    candidate_manifest, anchor_manifest = artifact(candidate), artifact(anchor)
    if (
        candidate_manifest["engineOriginalCommit"]
        != anchor_manifest["engineOriginalCommit"]
    ):
        raise ValueError("candidate and anchor engines differ")
    if output.exists() and any(output.iterdir()):
        raise ValueError("output must be new or empty")
    output.mkdir(parents=True, exist_ok=True)
    comparison = {
        "candidateSource": candidate_manifest["sourceCommit"],
        "candidateSHA256": candidate_manifest["sha256"],
        "anchorSource": anchor_manifest["sourceCommit"],
        "anchorSHA256": anchor_manifest["sha256"],
        "engineOriginalCommit": candidate_manifest["engineOriginalCommit"],
    }
    (output / "comparison.json").write_text(json.dumps(comparison, indent=2) + "\n")
    commands = []
    for job in plan(stage):
        control = stage == "held-out" and job.arm == "control"
        binary, manifest = (
            (anchor, anchor_manifest) if control else (candidate, candidate_manifest)
        )
        commands.append((job.name, job.command(binary, manifest["sourceCommit"])))
    (output / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")

    def run(command: tuple[str, list[str]]) -> dict[str, Any]:
        name, args = command
        started = time.monotonic()
        with (output / f"{name}.jsonl").open("w") as stdout, (
            output / f"{name}.timing"
        ).open("w") as stderr:
            result = subprocess.run(args, stdout=stdout, stderr=stderr, check=False)
        rows = [
            json.loads(line)
            for line in (output / f"{name}.jsonl").read_text().splitlines()
            if line
        ]
        rejects = sum(
            bool(
                row["winner"] is None
                or any(
                    row[key]
                    for key in (
                        "forcedEnds",
                        "idleSailingCycles",
                        "tradeCycles",
                        "duplicateProposals",
                    )
                )
            )
            for row in rows
        )
        return dict(
            name=name,
            returncode=result.returncode,
            games=len(rows),
            rejects=rejects,
            seconds=round(time.monotonic() - started, 3),
        )

    records = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        for record in pool.map(run, commands):
            records.append(record)
            (output / "jobs.json").write_text(json.dumps(records, indent=2) + "\n")
            print(json.dumps(record), flush=True)
    analyze(output, stage)


def argument_parser() -> argparse.ArgumentParser:
    """Define portable reproduction and evidence inspection commands."""
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    analyzer = subparsers.add_parser("analyze")
    analyzer.add_argument("directory", type=pathlib.Path)
    analyzer.add_argument("--stage", choices=STAGES, default="held-out")
    analyzer.add_argument("--require-strength", action="store_true")
    analyzer.add_argument(
        "--offline",
        action="store_true",
        help="Use recorded provenance when historical binaries are unavailable.",
    )
    runner = subparsers.add_parser("run")
    runner.add_argument("--candidate", type=pathlib.Path, required=True)
    runner.add_argument("--anchor", type=pathlib.Path, required=True)
    runner.add_argument("--stage", choices=STAGES, required=True)
    runner.add_argument("--output", type=pathlib.Path, required=True)
    runner.add_argument("--workers", type=int, choices=range(1, 9), default=1)
    verifier = subparsers.add_parser("verify-evidence")
    verifier.add_argument("directory", type=pathlib.Path)
    inspector = subparsers.add_parser("inspect-revisits")
    inspector.add_argument("directory", type=pathlib.Path)
    inspector.add_argument("source", type=pathlib.Path)
    inspector.add_argument("destination", type=pathlib.Path)
    return parser


def main() -> int:
    """Expose reproduction commands without implicitly rebuilding or tuning AI."""
    arguments = argument_parser().parse_args()
    if arguments.command == "verify-evidence":
        verify_frozen_scripts()
        verify_evidence(arguments.directory)
        print("All retained evidence and frozen script hashes match.")
        return 0
    if arguments.command == "inspect-revisits":
        rows = validate_rows(arguments.directory, "held-out")
        report = preserve(rows, arguments.source, arguments.destination)
        (arguments.directory / "revisit-inspection.json").write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n"
        )
        print(
            json.dumps(
                {key: value for key, value in report.items() if key != "records"}
            )
        )
        return 0
    if arguments.command == "run":
        execute(
            arguments.candidate,
            arguments.anchor,
            arguments.stage,
            arguments.output,
            arguments.workers,
        )
        return 0
    report = analyze(
        arguments.directory, arguments.stage, verify_binaries=not arguments.offline
    )
    print(
        json.dumps(
            {key: value for key, value in report.items() if key != "byTable"}, indent=2
        )
    )
    if arguments.require_strength:
        passed = report["functionalGatePassed"] and all(
            report["byTable"][str(players)]
            .get("paired", {})
            .get("substantiveGatePassed", False)
            for players in (3, 4)
        )
        return 0 if passed else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
