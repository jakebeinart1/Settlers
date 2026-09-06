#!/usr/bin/env python3
"""Run one bounded, chair-rotated comparison with the existing native analyzer.

Usage: python3 scripts/evaluate-bots.py --config config/evaluation/neural-r2-smoke.json
       --output /tmp/empires-evaluation-unique-name

This first slice compares named policies in one frozen build, not arbitrary
checkpoints or opponent pools. Smoke results validate the pipeline, not strength.
The existing watchdog owns the deadline, process group and terminal receipt.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import shutil
import signal
import subprocess
import sys
from pathlib import Path
from typing import Optional, TextIO

import training_watchdog as watchdog

REPO = Path(__file__).resolve().parents[1]
PACKAGE = REPO / "Packages/CatanAI"
ANALYZER = REPO / "scripts/analyze-bot-evaluation.py"
CONFIG_KEYS = {
    "name",
    "purpose",
    "candidate",
    "baseline",
    "opponent",
    "players",
    "victory_points",
    "board",
    "first_seed",
    "seeds",
    "budget_seconds",
}
INTENTIONAL_FALLBACKS = {
    "player_trade_negotiation",
    "heuristic_trade_proposal",
    "unsupported_pre_roll_development_card",
}


def read_config(path: Path) -> dict:
    """Reject ambiguous configs before reserving output or launching a build."""
    config = json.loads(path.read_text(), object_pairs_hook=unique_object)
    if not isinstance(config, dict) or set(config) != CONFIG_KEYS:
        raise ValueError(f"config requires exactly these keys: {sorted(CONFIG_KEYS)}")
    validate_identifiers(config)
    validate_configuration(config)
    return config


def unique_object(pairs: list[tuple[str, object]]) -> dict:
    value = dict(pairs)
    if len(value) != len(pairs):
        raise ValueError("duplicate config keys are ambiguous")
    return value


def validate_identifiers(config: dict) -> None:
    for key in ("name", "candidate", "baseline", "opponent"):
        value = config[key]
        if (
            not isinstance(value, str)
            or not value
            or not all(
                char.isascii() and (char.isalnum() or char in "._-") for char in value
            )
        ):
            raise ValueError(f"{key} requires a nonempty ASCII identifier")


def validate_configuration(config: dict) -> None:
    for key in ("players", "victory_points", "first_seed", "seeds", "budget_seconds"):
        if type(config[key]) is not int:
            raise ValueError(f"{key} requires an integer, not a boolean or float")
    if config["players"] not in (3, 4) or config["victory_points"] not in (8, 10, 12):
        raise ValueError("supported players: 3/4; victory_points: 8/10/12")
    if (
        config["board"] not in ("standard", "randomized")
        or config["purpose"] != "smoke"
    ):
        raise ValueError(
            "board must be standard/randomized; this runner supports smoke"
        )
    if config["seeds"] < 2 or config["first_seed"] < 0:
        raise ValueError("at least two seeds and a nonnegative first_seed are required")
    if config["first_seed"] + config["seeds"] > 2**64:
        raise ValueError("seed range overflows UInt64")
    watchdog.Deadline(config["budget_seconds"], 0, 0)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: object) -> None:
    with path.open("x") as handle:
        json.dump(value, handle, indent=2, sort_keys=True, allow_nan=False)
        handle.write("\n")


def source_snapshot() -> dict[str, str]:
    paths = [Path(__file__), ANALYZER, REPO / "scripts/training_watchdog.py"]
    for package in (PACKAGE, REPO / "Packages/CatanEngine"):
        paths.append(package / "Package.swift")
        paths.extend(
            path for path in (package / "Sources").rglob("*") if path.is_file()
        )
    return {str(path.relative_to(REPO)): digest(path) for path in sorted(paths)}


def execute(command: list[str], output: Path, target: Optional[Path] = None) -> str:
    """Retain exact argv and stderr; only successful exit codes advance the run."""
    with (output / "commands.jsonl").open("a") as journal:
        journal.write(json.dumps(command) + "\n")
    print("Running:", command, flush=True)
    if target is None:
        return subprocess.check_output(command, cwd=REPO, text=True)
    with target.open("x") as stdout, target.with_suffix(".stderr.log").open(
        "x"
    ) as stderr:
        subprocess.run(command, cwd=REPO, stdout=stdout, stderr=stderr, check=True)
    return ""


def freeze_build(output: Path) -> Path:
    command = ["swift", "build", "--package-path", str(PACKAGE), "-c", "release"]
    execute([*command, "--product", "sim"], output, output / "build.log")
    binary_dir = Path(execute([*command, "--show-bin-path"], output).strip())
    frozen = output / "frozen"
    frozen.mkdir()
    shutil.copy2(binary_dir / "sim", frozen / "sim")
    shutil.copy2(ANALYZER, frozen / ANALYZER.name)
    bundles = [
        binary_dir / f"CatanAI_CatanAI.{suffix}" for suffix in ("bundle", "resources")
    ]
    present = [path for path in bundles if path.is_dir()]
    if len(present) != 1:
        raise ValueError("expected exactly one native CatanAI model resource bundle")
    shutil.copytree(present[0], frozen / present[0].name)
    source_model = PACKAGE / "Sources/CatanAI/Resources/UpstreamPolicy/final.ctnn"
    copied_model = frozen / present[0].name / "UpstreamPolicy/final.ctnn"
    if digest(source_model) != digest(copied_model):
        raise ValueError(
            "built model resource differs from source; rebuild before evaluating"
        )
    return frozen / "sim"


def run_arm(
    config: dict, arm: str, binary: Path, build_id: str, policies: dict, output: Path
) -> list[Path]:
    shards = []
    for seat in range(config["players"]):
        roster = [config["opponent"]] * config["players"]
        roster[seat] = config[arm]
        shard = output / f"{arm}-seat{seat}.jsonl"
        audit = output / f"{arm}-seat{seat}.audit.jsonl"
        command = [
            str(binary),
            "--jsonl",
            "--build-id",
            build_id,
            "--games",
            str(config["seeds"]),
            "--seed",
            str(config["first_seed"]),
            "--players",
            str(config["players"]),
            "--victory-points",
            str(config["victory_points"]),
            "--board",
            config["board"],
            "--seats",
            ",".join(roster),
            "--policy-audit-jsonl",
            str(audit),
        ]
        execute(command, output, shard)
        validate_shard(shard, config)
        validate_audit(audit, shard, policies["neural-r2"])
        shards.append(shard)
    return shards


def validate_shard(path: Path, config: dict) -> None:
    rows = [json.loads(line) for line in path.read_text().splitlines()]
    expected = list(range(config["first_seed"], config["first_seed"] + config["seeds"]))
    if [row["seed"] for row in rows] != expected:
        raise ValueError(f"{path.name}: missing, reordered or unexpected seeds")
    for row in rows:
        actual = (row["playerCount"], row["victoryPointTarget"], row["boardMode"])
        if actual != (config["players"], config["victory_points"], config["board"]):
            raise ValueError(f"{path.name}: game configuration differs from manifest")
        if row["winner"] is None:
            raise ValueError(f"{path.name}: incomplete smoke game; raw result retained")


def checked_counts(counts: dict, allowed: set[str]) -> int:
    if not isinstance(counts, dict) or set(counts) - allowed:
        raise ValueError(f"unexpected policy routes/fallbacks: {counts}")
    if any(type(value) is not int or value < 0 for value in counts.values()):
        raise ValueError("policy audit counters require nonnegative integers")
    return sum(counts.values())


def validate_audit(audit: Path, shard: Path, neural_id: str) -> None:
    """Count consulted responders too; legal heuristic fallback is not neural success."""
    games = [json.loads(line) for line in shard.read_text().splitlines()]
    records = [json.loads(line) for line in audit.read_text().splitlines()]
    if len(records) != len(games):
        raise ValueError("policy audit must account for every game")
    for record, game in zip(records, games):
        if record["schemaVersion"] != 1 or record["seed"] != game["seed"]:
            raise ValueError("policy audit schema/seed mismatch")
        if len(record["seats"]) != len(game["policies"]):
            raise ValueError("policy audit seat count mismatch")
        total = 0
        for seat, policy_id in zip(record["seats"], game["policies"]):
            total += validate_seat_audit(seat, policy_id, neural_id)
        if (
            type(record["evaluationCount"]) is not int
            or total != record["evaluationCount"]
            or total < game["moves"]
        ):
            raise ValueError("policy audit does not account for all evaluations")


def validate_seat_audit(seat: dict, policy_id: str, neural_id: str) -> int:
    neural = policy_id == neural_id
    if (
        seat["policyID"] != policy_id
        or type(seat["evaluations"]) is not int
        or seat["evaluations"] <= 0
    ):
        raise ValueError("policy audit identity/count mismatch")
    total = checked_counts(
        seat["sources"], {"neural", "heuristic"} if neural else {"policy"}
    )
    fallbacks = checked_counts(
        seat["fallbackReasons"], INTENTIONAL_FALLBACKS if neural else set()
    )
    if total != seat["evaluations"] or fallbacks != seat["sources"].get("heuristic", 0):
        raise ValueError("policy audit route/fallback totals disagree")
    if neural and seat["sources"].get("neural", 0) == 0:
        raise ValueError("neural seat never used the neural route")
    return total


def analyze(
    config: dict, policies: dict, build_id: str, arms: dict, output: Path
) -> None:
    command = [
        sys.executable,
        str(output / "frozen" / ANALYZER.name),
        "--name",
        config["name"],
    ]
    for arm in ("candidate", "baseline"):
        command.extend(
            [
                f"--{arm}-build-id",
                build_id,
                f"--{arm}-policy",
                policies[config[arm]],
                f"--{arm}-foil-policy",
                policies[config["opponent"]],
                f"--{arm}-files",
                *(str(path) for path in arms[arm]),
            ]
        )
    execute(command, output, output / "analysis.md")
    with (output / "report.md").open("x") as report:
        report.write("# Smoke verification — not a strength claim\n\n")
        report.write(
            "Development seeds; small sample. See manifest.json and run.watchdog.json.\n\n"
        )
        report.write((output / "analysis.md").read_text())
        append_route_report(report, arms)


def append_route_report(report: TextIO, arms: dict) -> None:
    report.write("\n## Decision routes (evaluated chair only)\n\n")
    report.write(
        "Selections include forced choices; these are not network inference-call counts.\n\n"
    )
    for arm, shards in arms.items():
        sources, reasons = {}, {}
        for seat, shard in enumerate(shards):
            for line in shard.with_suffix(".audit.jsonl").read_text().splitlines():
                record = json.loads(line)["seats"][seat]
                for field, counts in (
                    ("sources", sources),
                    ("fallbackReasons", reasons),
                ):
                    for key, count in record[field].items():
                        counts[key] = counts.get(key, 0) + count
        report.write(
            f"- {arm}: routes `{json.dumps(sources, sort_keys=True)}`; "
            f"intentional fallbacks `{json.dumps(reasons, sort_keys=True)}`.\n"
        )


def capture_inputs(config: dict, output: Path) -> dict:
    inputs = {
        "schema_version": 1,
        "config": config,
        "source_files": source_snapshot(),
        "source_commit": execute(["git", "rev-parse", "HEAD"], output).strip(),
        "source_status": execute(["git", "status", "--short"], output),
        "host": platform.platform(),
        "python": sys.version,
    }
    write_json(output / "inputs.json", inputs)
    return inputs


def record_manifest(inputs: dict, binary: Path, output: Path) -> dict:
    if source_snapshot() != inputs["source_files"]:
        raise ValueError(
            "source changed during build; discard comparison, retain evidence"
        )
    policies = json.loads(execute([str(binary), "--list-policies"], output))
    config = inputs["config"]
    for key in ("candidate", "baseline", "opponent"):
        if config[key] not in policies:
            raise ValueError(
                f"unknown {key} {config[key]!r}; available: {sorted(policies)}"
            )
    artifacts = {
        str(path.relative_to(output)): digest(path)
        for path in sorted(binary.parent.rglob("*"))
        if path.is_file()
    }
    # A model can change without relinking sim. Identify the complete artifact,
    # not just its executable, so the analyzer cannot conflate checkpoints.
    build_id = (
        "frozen-"
        + hashlib.sha256(json.dumps(artifacts, sort_keys=True).encode()).hexdigest()
    )
    manifest = {
        **inputs,
        "policy_ids": policies,
        "build_id": build_id,
        "artifacts": artifacts,
        "swift": execute(["swift", "--version"], output).strip(),
        "information_access": "reveal-all",
        "strength_claim": False,
    }
    write_json(output / "manifest.json", manifest)
    return manifest


def worker(output: Path) -> None:
    config = read_config(output / "config.json")
    inputs = capture_inputs(config, output)
    binary = freeze_build(output)
    manifest = record_manifest(inputs, binary, output)
    policies, build_id = manifest["policy_ids"], manifest["build_id"]
    arms = {
        arm: run_arm(config, arm, binary, build_id, policies, output)
        for arm in ("candidate", "baseline")
    }
    analyze(config, policies, build_id, arms, output)
    for name, expected in manifest["artifacts"].items():
        if digest(output / name) != expected:
            raise ValueError(f"frozen artifact changed during evaluation: {name}")
    write_json(
        output / "complete.json",
        {
            "games": 2 * config["players"] * config["seeds"],
            "strength_claim": False,
            "report": "report.md",
            "manifest_sha256": digest(output / "manifest.json"),
        },
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    options = parser.parse_args()
    output = options.output.resolve()
    if options.worker:
        worker(output)
        return 0
    if options.config is None:
        parser.error("--config is required")
    config = read_config(options.config)
    output.mkdir(parents=True, exist_ok=False)
    write_json(output / "config.json", config)
    print(
        f"Budget: {config['budget_seconds']}s. Live log: {output / 'run.launcher.log'}",
        flush=True,
    )
    signal.signal(signal.SIGTERM, watchdog.interrupted)
    command = [
        sys.executable,
        str(Path(__file__).resolve()),
        "--worker",
        "--output",
        str(output),
    ]
    code = watchdog.run(command, output / "run", config["budget_seconds"])
    print(f"{'PASS smoke' if code == 0 else 'FAILED'}: {output / 'run.watchdog.json'}")
    if code == 0:
        print(f"Report: {output / 'report.md'}")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
