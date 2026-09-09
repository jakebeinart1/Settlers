#!/usr/bin/env python3
"""Fixed 448-game exploratory screen; launch under the archived 600s watchdog.

Two whole-chair shards run at once, with 120s per subprocess and no retries.
Timeouts/crashes/caps retain raw evidence but never certify a complete screen.
The native simulator owns play; the existing analyzer owns clustered inference.
"""

import argparse
import importlib.util
import json
import re
import shutil
import subprocess
import time
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from pathlib import Path

from pilot_corpus import ROOT, digest, freeze
from review_corpus import reject_constant, strict_object


SEEDS = 16
WORKERS = 2
SHARD_TIMEOUT = 120
TOTAL_GAMES = 448
ANALYZER = Path("scripts/analyze-bot-evaluation.py")
BASELINE_ID = "heuristic-balanced"
BASELINE_SHA256 = "f0a362eccbbd515fb65c4fd9f52f4a4fdb14cf876b1855113c6625e984ca905b"
CANDIDATE_ID = "experimental-joint-balanced-v1"
PRACTICAL_TARGET = 0.05


def schedule(candidate_id):
    """Disjoint strata, paired seeds within arms, every evaluated chair once."""
    shards = []
    for cell, (players, opponent) in enumerate(
        (p, o) for p in (3, 4) for o in ("balanced", "aggressive")
    ):
        for chair in range(players):
            for arm in ("candidate", "baseline"):
                seats = [opponent] * players
                policies = [f"heuristic-{opponent}"] * players
                seats[chair] = "joint-balanced" if arm == "candidate" else "balanced"
                policies[chair] = candidate_id if arm == "candidate" else BASELINE_ID
                shards.append(
                    {
                        "stratum": f"p{players}-{opponent}",
                        "arm": arm,
                        "chair": chair,
                        "players": players,
                        "opponent": opponent,
                        "firstSeed": 880000 + cell * 100,
                        "games": SEEDS,
                        "seats": seats,
                        "policies": policies,
                    }
                )
    return shards


def write_json(path, value):
    with path.open("x") as stream:
        json.dump(value, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")


def freeze_inputs(binary, baseline, output):
    """Reuse pilot freezing; supplement its snapshot with the runner/analyzer."""
    binary_hash, baseline_hash = digest(binary), digest(baseline)
    if baseline_hash != BASELINE_SHA256:
        raise ValueError("baseline binary differs from locked hash")
    candidate, provenance = freeze(binary, output)
    control = output / "baseline-sim"
    shutil.copy2(baseline, control)
    archive = baseline.with_name("source.tar.gz")
    shutil.copy2(archive, output / "baseline-source.tar.gz")
    if digest(archive) != digest(output / "baseline-source.tar.gz"):
        raise ValueError("baseline source archive changed while freezing")
    if digest(candidate) != binary_hash or digest(control) != baseline_hash:
        raise ValueError("binary changed while freezing")
    extras = [
        Path(__file__).resolve(),
        ROOT / ANALYZER,
        ROOT / "scripts/tests/test_screen_trade_policy.py",
    ]
    for package in ("CatanAI", "CatanEngine"):
        extras.extend(
            p for p in (ROOT / f"Packages/{package}/Sources").rglob("*") if p.is_file()
        )
    for source in extras:
        relative = str(source.relative_to(ROOT))
        if relative not in provenance["sourceSHA256"]:
            target = output / "source" / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            provenance["sourceSHA256"][relative] = digest(target)
    for relative, expected in provenance["sourceSHA256"].items():
        if digest(ROOT / relative) != expected:
            raise ValueError("source changed while freezing")
    provenance.update(
        baselineBinarySHA256=baseline_hash,
        baselinePath=str(baseline),
        baselineSourceCommit="ec058ab",
        baselineSourceCommitOrigin="parent lock",
        baselineSourceArchiveSHA256=digest(output / "baseline-source.tar.gz"),
    )
    return {"candidate": candidate, "baseline": control}, provenance


def command_for(shard, binary, build_id):
    return [
        str(binary),
        "--jsonl",
        "--build-id",
        build_id,
        "--games",
        str(shard["games"]),
        "--seed",
        str(shard["firstSeed"]),
        "--players",
        str(shard["players"]),
        "--victory-points",
        "10",
        "--board",
        "randomized",
        "--seats",
        ",".join(shard["seats"]),
    ]


def validate_shard(path, shard, build_id):
    data = path.read_bytes()
    if not data.endswith(b"\n"):
        raise ValueError("truncated shard")
    rows = [
        json.loads(
            line, parse_constant=reject_constant, object_pairs_hook=strict_object
        )
        for line in data.splitlines()
    ]
    expected = list(range(shard["firstSeed"], shard["firstSeed"] + shard["games"]))
    if [row["seed"] for row in rows] != expected:
        raise ValueError("missing, duplicate, reordered or unexpected seeds")
    for row in rows:
        labels = (
            row["schemaVersion"],
            row["buildID"],
            row["playerCount"],
            row["victoryPointTarget"],
            row["boardMode"],
            row["policies"],
        )
        if labels != (
            5,
            build_id,
            shard["players"],
            10,
            "randomized",
            shard["policies"],
        ):
            raise ValueError("schema/config/build/policy mismatch")
        if any(
            type(row[key]) is not int
            for key in (
                "seed",
                "schemaVersion",
                "playerCount",
                "victoryPointTarget",
                "moves",
            )
        ):
            raise ValueError("native counters must be integers")
        if type(row["winner"]) is not int or not 0 <= row["winner"] < shard["players"]:
            raise ValueError("incomplete or invalid winner; retain raw evidence")
        if row["moves"] <= 0 or len(row["behavior"]) != shard["players"]:
            raise ValueError("invalid move/behavior count")
        if not all(isinstance(item, dict) for item in row["behavior"]):
            raise ValueError("invalid behavior entries")
        if (
            len(row["vp"]) != shard["players"]
            or any(type(v) is not int or v < 0 for v in row["vp"])
            or not isinstance(row["fingerprint"], str)
            or not re.fullmatch(r"[0-9a-f]{16}", row["fingerprint"])
        ):
            raise ValueError("invalid VP/fingerprint output")


def shard_path(output, shard):
    return output / shard["stratum"] / f"{shard['arm']}-seat{shard['chair']}.jsonl"


def run_shard(output, shard, binary, build_id):
    path = shard_path(output, shard)
    command = command_for(shard, binary, build_id)
    write_json(path.with_suffix(".command.json"), command)
    started = time.monotonic()
    with path.open("xb") as stdout, path.with_suffix(".stderr.log").open(
        "xb"
    ) as stderr:
        subprocess.run(
            command, stdout=stdout, stderr=stderr, check=True, timeout=SHARD_TIMEOUT
        )
    validate_shard(path, shard, build_id)
    return {
        "rawSHA256": digest(path),
        "stderrSHA256": digest(path.with_suffix(".stderr.log")),
        "elapsedSeconds": time.monotonic() - started,
        "games": shard["games"],
    }


def play(shards, binaries, build_ids, output, progress):
    """Keep only two futures in flight; after a failure launch no replacements."""
    remaining = iter(shards)
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        pending = {}

        def submit():
            shard = next(remaining, None)
            if shard is not None:
                progress.write(json.dumps({"status": "started", "shard": shard}) + "\n")
                future = pool.submit(
                    run_shard,
                    output,
                    shard,
                    binaries[shard["arm"]],
                    build_ids[shard["arm"]],
                )
                pending[future] = shard

        for _ in range(WORKERS):
            submit()
        while pending:
            done, _ = wait(pending, return_when=FIRST_COMPLETED)
            for future in done:
                shard = pending.pop(future)
                try:
                    result = future.result()
                except Exception as error:
                    progress.write(
                        json.dumps(
                            {"status": "failed", "shard": shard, "error": repr(error)}
                        )
                        + "\n"
                    )
                    raise
                progress.write(
                    json.dumps({"status": "complete", "shard": shard, **result}) + "\n"
                )
            for _ in done:
                submit()


def analyze(shards, build_ids, output):
    """Use the frozen current analyzer, separately for each opponent/table cell."""
    spec = importlib.util.spec_from_file_location(
        "screen_analyzer", output / "source" / ANALYZER
    )
    analyzer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(analyzer)
    results = []
    for stratum in dict.fromkeys(shard["stratum"] for shard in shards):
        cell = [s for s in shards if s["stratum"] == stratum]
        arms = {}
        for arm in ("candidate", "baseline"):
            selected = [s for s in cell if s["arm"] == arm]
            arms[arm] = analyzer.load(
                [shard_path(output, s) for s in selected],
                build_ids[arm],
                selected[0]["policies"][selected[0]["chair"]],
                f"heuristic-{cell[0]['opponent']}",
            )
        comparison = analyzer.paired_win_rate_difference(
            arms["candidate"], arms["baseline"]
        )
        result = {
            "stratum": stratum,
            "seedFamilies": SEEDS,
            "candidate": comparison.candidate._asdict(),
            "baseline": comparison.baseline._asdict(),
            "difference": comparison.difference,
            "lower95": comparison.lower,
            "upper95": comparison.upper,
            "practicalTarget": PRACTICAL_TARGET,
            "purpose": "development-screen",
            "strengthEstablished": False,
            "adoption": "reject" if comparison.upper < 0 else "inconclusive-no-ship",
        }
        write_json(output / stratum / "analysis.json", result)
        results.append(result)
    return (
        "reject"
        if any(r["adoption"] == "reject" for r in results)
        else "inconclusive-no-ship"
    )


def qualify(shards, binaries, build_ids, output, progress):
    """One seed per unchanged baseline roster/chair, on both frozen binaries."""
    directory = output / "parity"
    probes = []
    for shard in shards:
        if shard["arm"] == "baseline":
            (directory / shard["stratum"]).mkdir(parents=True, exist_ok=True)
            probes.extend(
                {**shard, "games": 1, "arm": arm} for arm in ("candidate", "baseline")
            )
    play(probes, binaries, build_ids, directory, progress)
    for probe in probes:
        if probe["arm"] != "candidate":
            continue
        current = json.loads(shard_path(directory, probe).read_text())
        original = json.loads(
            shard_path(directory, {**probe, "arm": "baseline"}).read_text()
        )
        current.pop("buildID")
        original.pop("buildID")
        if current != original:
            raise ValueError(
                f"unchanged-roster fingerprint/result parity failed: {probe}"
            )
    progress.write(json.dumps({"status": "parity-passed", "games": len(probes)}) + "\n")


def artifact_hashes(output):
    return {
        str(p.relative_to(output)): digest(p)
        for p in sorted(output.rglob("*"))
        if p.is_file()
    }


def run(binary, baseline, candidate_id, output):
    output = output.resolve()
    if not candidate_id or candidate_id in (BASELINE_ID, "heuristic-aggressive"):
        raise ValueError("candidate requires a distinct emitted native policy ID")
    output.mkdir(parents=True, exist_ok=False)
    status = {
        "status": "failed",
        "purpose": "development-screen",
        "strengthEstablished": False,
    }
    try:
        shards = schedule(candidate_id)
        for name in {s["stratum"] for s in shards}:
            (output / name).mkdir()
        binaries, provenance = freeze_inputs(
            binary.resolve(), baseline.resolve(), output
        )
        build_ids = {arm: "screen-" + digest(path) for arm, path in binaries.items()}
        write_json(
            output / "manifest.json",
            {
                "shards": shards,
                "games": TOTAL_GAMES,
                "buildIDs": build_ids,
                "board": "randomized",
                "victoryPoints": 10,
                "workers": WORKERS,
                "shardTimeoutSeconds": SHARD_TIMEOUT,
                "externalWatchdogSeconds": 600,
                "parityGames": len(shards),
                "practicalTarget": PRACTICAL_TARGET,
                "purpose": "development-screen",
                "strengthEstablished": False,
                **provenance,
            },
        )
        pinned = artifact_hashes(output)
        with (output / "progress.jsonl").open("x", buffering=1) as progress:
            qualify(shards, binaries, build_ids, output, progress)
            play(shards, binaries, build_ids, output, progress)
        adoption = analyze(shards, build_ids, output)
        if any(digest(output / name) != expected for name, expected in pinned.items()):
            raise ValueError("frozen evidence changed during screen")
        status.update(
            status="complete",
            games=TOTAL_GAMES,
            gamesPerArm=TOTAL_GAMES // 2,
            parityGames=len(shards),
            adoption=adoption,
        )
    except Exception as error:
        status["error"] = repr(error)
        raise
    finally:
        write_json(
            output / "receipt.json",
            {**status, "artifactsSHA256": artifact_hashes(output)},
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--baseline-binary", type=Path, required=True)
    parser.add_argument("--candidate-policy-id", default=CANDIDATE_ID)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    run(args.binary, args.baseline_binary, args.candidate_policy_id, args.output)


if __name__ == "__main__":
    main()
