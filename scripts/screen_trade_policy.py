#!/usr/bin/env python3
"""448-game screen or one Stage 4 confirmation stratum, under the existing watchdog.

Supply --players, --opponent, --first-seed and --seeds together for confirmation.
Two chairs run at once, in chunks of at most 16 seeds, with 120s per subprocess.
Timeouts/crashes/caps retain raw evidence but never certify a complete screen.
The native simulator owns play; the existing analyzer owns clustered inference.
--source-root accepts an earlier frozen source snapshot; runner sources are
archived separately so today's tooling never overwrites yesterday's candidate.
"""

import argparse
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from pathlib import Path
from threading import Event

from pilot_corpus import ROOT, digest, freeze
from review_corpus import reject_constant, strict_object

SEEDS = 16
MAX_SEEDS = 64
UINT64_MAX = (1 << 64) - 1
WORKERS = 2
SHARD_TIMEOUT = 120
TOTAL_GAMES = 448
ANALYZER = Path("scripts/analyze-bot-evaluation.py")
BASELINE_ID = "heuristic-balanced"
BASELINE_SHA256 = "f0a362eccbbd515fb65c4fd9f52f4a4fdb14cf876b1855113c6625e984ca905b"
CANDIDATE_ID = "experimental-joint-balanced-v1"
CANDIDATE_SHA256 = "de9b5dd775fb0fbd7476a1a88a7321400bc6a14ad7ce4bac27bf46a34bd11083"
PRACTICAL_TARGET = 0.05
CONFIRMATION_PURPOSE = "stage4-confirmation"


def configurations(players=None, opponent=None, first_seed=None, seeds=None):
    """Validate an all-or-none stratum before creating any output or subprocess."""
    values = (players, opponent, first_seed, seeds)
    if all(value is None for value in values):
        return [
            (p, o, 880000 + cell * 100, SEEDS)
            for cell, (p, o) in enumerate(
                (p, o) for p in (3, 4) for o in ("balanced", "aggressive")
            )
        ]
    if any(value is None for value in values):
        raise ValueError(
            "--players, --opponent, --first-seed and --seeds are required together"
        )
    if type(players) is not int or players not in (3, 4):
        raise ValueError("--players must be 3 or 4")
    if opponent not in ("balanced", "aggressive"):
        raise ValueError("--opponent must be balanced or aggressive")
    if type(seeds) is not int or not 1 <= seeds <= MAX_SEEDS:
        raise ValueError("--seeds must be an integer in 1..64")
    if type(first_seed) is not int or not 0 <= first_seed <= UINT64_MAX - seeds + 1:
        raise ValueError("--first-seed must be nonnegative and the range UInt64-safe")
    return [(players, opponent, first_seed, seeds)]


def schedule(candidate_id, players=None, opponent=None, first_seed=None, seeds=None):
    """Disjoint strata, paired seeds within arms, every evaluated chair once."""
    shards = []
    for players, opponent, first_seed, seeds in configurations(
        players, opponent, first_seed, seeds
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
                        "firstSeed": first_seed,
                        "games": seeds,
                        "seats": seats,
                        "policies": policies,
                    }
                )
    return shards


def write_json(path, value):
    with path.open("x") as stream:
        json.dump(value, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")


def freeze_candidate(binary, output, source_root):
    """Keep a supplied archive intact; source bytes alone do not prove a build."""
    if source_root is None or source_root.resolve() == ROOT:
        candidate, provenance = freeze(binary, output)
        source_root = ROOT
        extras = [
            ROOT / ANALYZER,
            Path(__file__).resolve(),
            ROOT / "scripts/tests/test_screen_trade_policy.py",
        ]
        for package in ("CatanAI", "CatanEngine"):
            extras.extend(
                p
                for p in (ROOT / f"Packages/{package}/Sources").rglob("*")
                if p.is_file()
            )
        for source in extras:
            target = output / "source" / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    else:
        source_root = source_root.resolve()
        candidate = output / "sim"
        shutil.copy2(binary, candidate)
        shutil.copytree(source_root, output / "source")
        provenance = {"binarySHA256": digest(candidate)}
    provenance["sourceSHA256"] = artifact_hashes(output / "source")
    for relative, expected in provenance["sourceSHA256"].items():
        if digest(source_root / relative) != expected:
            raise ValueError("source changed while freezing")
    provenance["candidateSource"] = {
        "root": str(source_root),
        "binaryPath": str(binary),
        "binarySHA256": digest(candidate),
        "relationship": "supplied snapshot; compile correspondence not independently verified",
    }
    return candidate, provenance


def freeze_inputs(
    binary,
    baseline,
    output,
    source_root=None,
    *,
    candidate_sha256=None,
    baseline_sha256=None,
    baseline_source_commit="ec058ab",
):
    """Freeze executable/source separately from the current runner and analyzer."""
    candidate_sha256, baseline_sha256, baseline_source_commit = validate_locks(
        candidate_sha256, baseline_sha256, baseline_source_commit
    )
    binary_hash, baseline_hash = digest(binary), digest(baseline)
    if baseline_hash != baseline_sha256:
        raise ValueError("baseline binary differs from locked hash")
    if binary_hash != candidate_sha256:
        raise ValueError("candidate binary differs from locked hash")
    candidate, provenance = freeze_candidate(binary, output, source_root)
    control = output / "baseline-sim"
    shutil.copy2(baseline, control)
    archive = baseline.with_name("source.tar.gz")
    shutil.copy2(archive, output / "baseline-source.tar.gz")
    if digest(archive) != digest(output / "baseline-source.tar.gz"):
        raise ValueError("baseline source archive changed while freezing")
    if digest(candidate) != binary_hash or digest(control) != baseline_hash:
        raise ValueError("binary changed while freezing")
    runner_paths = [
        ANALYZER,
        Path("scripts/screen_trade_policy.py"),
        Path("scripts/tests/test_screen_trade_policy.py"),
        Path("scripts/pilot_corpus.py"),
        Path("scripts/review_corpus.py"),
    ]
    for relative in runner_paths:
        target = output / "runner-source" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        expected = digest(ROOT / relative)
        shutil.copy2(ROOT / relative, target)
        if digest(target) != expected or digest(ROOT / relative) != expected:
            raise ValueError("runner source changed while freezing")
    provenance.update(
        runnerSourceSHA256=artifact_hashes(output / "runner-source"),
        baselineBinarySHA256=baseline_hash,
        baselinePath=str(baseline),
        baselineSourceCommit=baseline_source_commit,
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


def check_cancelled(cancellation):
    """A failed chair stops fresh work; an already running chunk remains bounded."""
    if cancellation is not None and cancellation.is_set():
        raise RuntimeError("screen cancelled after another worker failed")


def run_chunk(path, shard, binary, build_id, cancellation=None):
    """Retain the original subprocess timeout, strict validation and raw evidence."""
    check_cancelled(cancellation)
    command = command_for(shard, binary, build_id)
    write_json(path.with_suffix(".command.json"), command)
    started = time.monotonic()
    with path.open("xb") as stdout, path.with_suffix(".stderr.log").open(
        "xb"
    ) as stderr:
        check_cancelled(cancellation)
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


def chunks(shard):
    """Partition a chair's consecutive seed family without overlapping boundaries."""
    return [
        {
            **shard,
            "firstSeed": shard["firstSeed"] + offset,
            "games": min(SEEDS, shard["games"] - offset),
        }
        for offset in range(0, shard["games"], SEEDS)
    ]


def run_shard(output, shard, binary, build_id, cancellation=None):
    """Signal peer workers at the failure site, before the coordinator sees it."""
    try:
        check_cancelled(cancellation)
        return run_chair(output, shard, binary, build_id, cancellation)
    except Exception:
        if cancellation is not None:
            cancellation.set()
        raise


def run_chair(output, shard, binary, build_id, cancellation):
    """Analyze only one exclusive full-chair file, never its retained chunk files."""
    path = shard_path(output, shard)
    parts = chunks(shard)
    if len(parts) == 1:
        return run_chunk(path, shard, binary, build_id, cancellation)
    directory = path.parent / "chunks" / path.stem
    directory.mkdir(parents=True, exist_ok=False)
    write_json(
        path.with_suffix(".command.json"),
        [command_for(part, binary, build_id) for part in parts],
    )
    started = time.monotonic()
    with path.open("xb") as combined, path.with_suffix(".stderr.log").open(
        "xb"
    ) as stderr:
        for index, part in enumerate(parts):
            check_cancelled(cancellation)
            chunk_path = directory / f"chunk-{index:03d}.jsonl"
            result = run_chunk(chunk_path, part, binary, build_id, cancellation)
            write_json(chunk_path.with_suffix(".receipt.json"), result)
            with chunk_path.open("rb") as stream:
                shutil.copyfileobj(stream, combined)
            with chunk_path.with_suffix(".stderr.log").open("rb") as stream:
                shutil.copyfileobj(stream, stderr)
    validate_shard(path, shard, build_id)
    return {
        "rawSHA256": digest(path),
        "stderrSHA256": digest(path.with_suffix(".stderr.log")),
        "elapsedSeconds": time.monotonic() - started,
        "games": shard["games"],
        "chunks": len(parts),
    }


def play(shards, binaries, build_ids, output, progress):
    """Keep only two futures in flight; after a failure launch no replacements."""
    remaining = iter(shards)
    cancellation = Event()
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        pending = {}

        def submit():
            if cancellation.is_set():
                return
            shard = next(remaining, None)
            if shard is not None:
                progress.write(json.dumps({"status": "started", "shard": shard}) + "\n")
                future = pool.submit(
                    run_shard,
                    output,
                    shard,
                    binaries[shard["arm"]],
                    build_ids[shard["arm"]],
                    cancellation,
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
                    cancellation.set()
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


def analyze(shards, build_ids, output, purpose="development-screen"):
    """Use the frozen current analyzer, separately for each opponent/table cell."""
    spec = importlib.util.spec_from_file_location(
        "screen_analyzer", output / "runner-source" / ANALYZER
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
        adoption = "reject" if comparison.upper < 0 else "inconclusive-no-ship"
        if purpose == CONFIRMATION_PURPOSE:
            adoption = "parent-decision-required"
        result = {
            "stratum": stratum,
            "seedFamilies": cell[0]["games"],
            "firstSeed": cell[0]["firstSeed"],
            "candidate": comparison.candidate._asdict(),
            "baseline": comparison.baseline._asdict(),
            "difference": comparison.difference,
            "lower95": comparison.lower,
            "upper95": comparison.upper,
            "practicalTarget": PRACTICAL_TARGET,
            "purpose": purpose,
            "strengthEstablished": False,
            "adoption": adoption,
        }
        write_json(output / stratum / "analysis.json", result)
        results.append(result)
    if purpose == CONFIRMATION_PURPOSE:
        return "parent-decision-required"
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


def run(
    binary,
    baseline,
    candidate_id,
    output,
    *,
    players=None,
    opponent=None,
    first_seed=None,
    seeds=None,
    source_root=None,
    candidate_sha256=None,
    baseline_sha256=None,
    baseline_source_commit=None,
):
    output = output.resolve()
    if output.exists():
        raise FileExistsError(output)
    shards = schedule(candidate_id, players, opponent, first_seed, seeds)
    purpose = CONFIRMATION_PURPOSE if players is not None else "development-screen"
    require_confirmation_locks(
        players, candidate_sha256, baseline_sha256, baseline_source_commit
    )
    candidate_sha256, baseline_sha256, baseline_source_commit = validate_locks(
        candidate_sha256, baseline_sha256, baseline_source_commit
    )
    if digest(binary) != candidate_sha256:
        raise ValueError("candidate binary differs from locked Stage 4 hash")
    games = sum(shard["games"] for shard in shards)
    if not candidate_id or candidate_id in (BASELINE_ID, "heuristic-aggressive"):
        raise ValueError("candidate requires a distinct emitted native policy ID")
    output.mkdir(parents=True, exist_ok=False)
    status = {
        "status": "failed",
        "purpose": purpose,
        "strengthEstablished": False,
    }
    try:
        for name in {s["stratum"] for s in shards}:
            (output / name).mkdir()
        binaries, provenance = freeze_inputs(
            binary.resolve(),
            baseline.resolve(),
            output,
            source_root,
            candidate_sha256=candidate_sha256,
            baseline_sha256=baseline_sha256,
            baseline_source_commit=baseline_source_commit,
        )
        build_ids = {arm: "screen-" + digest(path) for arm, path in binaries.items()}
        write_json(
            output / "manifest.json",
            {
                "shards": shards,
                "games": games,
                "configuration": {
                    "players": players,
                    "opponent": opponent,
                    "firstSeed": first_seed,
                    "seeds": seeds,
                },
                "binaryLocks": {
                    "candidate": candidate_sha256,
                    "baseline": baseline_sha256,
                },
                "invocation": sys.argv,
                "chunkSeeds": SEEDS,
                "subprocesses": sum(len(chunks(s)) for s in shards),
                "buildIDs": build_ids,
                "board": "randomized",
                "victoryPoints": 10,
                "workers": WORKERS,
                "shardTimeoutSeconds": SHARD_TIMEOUT,
                "externalWatchdogSeconds": 600,
                "parityGames": len(shards),
                "practicalTarget": PRACTICAL_TARGET,
                "purpose": purpose,
                "strengthEstablished": False,
                **provenance,
            },
        )
        pinned = artifact_hashes(output)
        with (output / "progress.jsonl").open("x", buffering=1) as progress:
            qualify(shards, binaries, build_ids, output, progress)
            play(shards, binaries, build_ids, output, progress)
        adoption = analyze(shards, build_ids, output, purpose)
        if any(digest(output / name) != expected for name, expected in pinned.items()):
            raise ValueError("frozen evidence changed during screen")
        status.update(
            status="complete",
            games=games,
            gamesPerArm=games // 2,
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


def validate_locks(candidate_sha256, baseline_sha256, baseline_source_commit):
    """Accept explicit frozen-build locks without inventing their source revision."""
    candidate = CANDIDATE_SHA256 if candidate_sha256 is None else candidate_sha256
    baseline = BASELINE_SHA256 if baseline_sha256 is None else baseline_sha256
    if baseline_source_commit is None:
        baseline_source_commit = "ec058ab"
    for name, value in (("candidate", candidate), ("baseline", baseline)):
        if not isinstance(value, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", value):
            raise ValueError(f"--{name}-sha256 must be exactly 64 hexadecimal digits")
    if not isinstance(baseline_source_commit, str) or not re.fullmatch(
        r"[0-9a-fA-F]{7,40}", baseline_source_commit
    ):
        raise ValueError(
            "--baseline-source-commit must be a 7..40 digit hexadecimal commit"
        )
    return candidate.lower(), baseline.lower(), baseline_source_commit.lower()


def require_confirmation_locks(players, candidate, baseline, commit):
    """Historical lock defaults are for development, never implicit confirmation."""
    if players is not None and any(
        value is None for value in (candidate, baseline, commit)
    ):
        raise ValueError(
            "confirmation requires explicit --candidate-sha256, "
            "--baseline-sha256 and --baseline-source-commit"
        )


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--baseline-binary", type=Path, required=True)
    parser.add_argument("--candidate-policy-id", default=CANDIDATE_ID)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--players", type=int, choices=(3, 4))
    parser.add_argument("--opponent", choices=("balanced", "aggressive"))
    parser.add_argument("--first-seed", type=int)
    parser.add_argument("--seeds", type=int)
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--candidate-sha256")
    parser.add_argument("--baseline-sha256")
    parser.add_argument("--baseline-source-commit")
    args = parser.parse_args(argv)
    try:
        configurations(args.players, args.opponent, args.first_seed, args.seeds)
        require_confirmation_locks(
            args.players,
            args.candidate_sha256,
            args.baseline_sha256,
            args.baseline_source_commit,
        )
        args.candidate_sha256, args.baseline_sha256, args.baseline_source_commit = (
            validate_locks(
                args.candidate_sha256, args.baseline_sha256, args.baseline_source_commit
            )
        )
    except ValueError as error:
        parser.error(str(error))
    return args


def main():
    args = parse_args()
    run(
        args.binary,
        args.baseline_binary,
        args.candidate_policy_id,
        args.output,
        players=args.players,
        opponent=args.opponent,
        first_seed=args.first_seed,
        seeds=args.seeds,
        source_root=args.source_root,
        candidate_sha256=args.candidate_sha256,
        baseline_sha256=args.baseline_sha256,
        baseline_source_commit=args.baseline_source_commit,
    )


if __name__ == "__main__":
    main()
