#!/usr/bin/env python3
"""Frozen 24-game instrumentation trial, not a strength or prevalence study.

Run under the existing bounded watchdog. Each game also has a 60-second stop;
every traced game is compared with a separate untraced process. Never replace
failed seeds. Partial evidence and the predeclared schedule remain on disk.
"""

import argparse
import hashlib
import json
import shutil
import subprocess
import time
from pathlib import Path


GAME_TIMEOUT_SECONDS = 60
GAME_TRACE_BYTES = 256 * 1024 * 1024
BATCH_TRACE_BYTES = 2 * 1024 * 1024 * 1024
ROOT = Path(__file__).resolve().parents[1]


def schedule():
    games = []
    family = 870100
    for players in (3, 4):
        for board in ("standard", "randomized"):
            roster = ["balanced", "aggressive", "cautious", "balanced"][:players]
            for chair in range(players):
                games.append({"seed": family, "family": family, "players": players,
                              "board": board, "roster": "mixed", "rotation": chair,
                              "seats": roster[chair:] + roster[:chair]})
            family += 1
            for _ in range(3 if players == 3 else 2):
                games.append({"seed": family, "family": family, "players": players,
                              "board": board, "roster": "balanced", "rotation": 0,
                              "seats": ["balanced"] * players})
                family += 1
    return games


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def freeze(binary, output):
    """Snapshot the executable and its source; do not label a dirty tree HEAD."""
    frozen = output / "sim"
    shutil.copy2(binary, frozen)
    paths = list((ROOT / "Packages/CatanAI/Sources").rglob("*.swift"))
    paths += list((ROOT / "Packages/CatanEngine/Sources").rglob("*.swift"))
    paths += [ROOT / "Packages/CatanAI/Package.swift", ROOT / "Packages/CatanEngine/Package.swift",
              Path(__file__).resolve(), ROOT / "scripts/review_corpus.py"]
    hashes = {}
    for path in sorted(paths):
        relative = path.relative_to(ROOT)
        target = output / "source" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        hashes[str(relative)] = digest(target)
    return frozen, {"binarySHA256": digest(frozen), "sourceSHA256": hashes}


def run_one(binary, output, game, index, build_id, remaining):
    prefix = output / f"game-{index:03d}"
    args = [str(binary), "--games", "1", "--seed", str(game["seed"]),
            "--players", str(game["players"]), "--board", game["board"],
            "--seats", ",".join(game["seats"]), "--victory-points", "10",
            "--build-id", build_id, "--jsonl"]
    started = time.monotonic()
    for traced in (False, True):
        suffix = "traced" if traced else "plain"
        command = args + (["--decision-jsonl", str(prefix.with_suffix(".trace.jsonl")),
                           "--trace-max-bytes", str(min(remaining, GAME_TRACE_BYTES))]
                          if traced else [])
        with prefix.with_suffix(f".{suffix}.jsonl").open("xb") as stdout, \
                prefix.with_suffix(f".{suffix}.stderr").open("xb") as stderr:
            subprocess.run(command, stdout=stdout, stderr=stderr, check=True,
                           timeout=GAME_TIMEOUT_SECONDS)
    plain = prefix.with_suffix(".plain.jsonl").read_bytes()
    traced = prefix.with_suffix(".traced.jsonl").read_bytes()
    if plain != traced:
        raise ValueError(f"trace changed game {index}; preserve both results")
    result = json.loads(traced)
    return {"index": index, "elapsedSeconds": time.monotonic() - started,
            "traceBytes": prefix.with_suffix(".trace.jsonl").stat().st_size,
            "fingerprint": result["fingerprint"], "winner": result["winner"],
            "moves": result["moves"], "plainTraceParity": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    binary, provenance = freeze(args.binary.resolve(), args.output)
    games = schedule()
    manifest = {"purpose": "instrumentation development only", "games": games,
                "victoryPointTarget": 10, "perProcessTimeoutSeconds": GAME_TIMEOUT_SECONDS,
                "batchTraceByteCap": BATCH_TRACE_BYTES, **provenance}
    (args.output / "schedule.json").write_text(json.dumps(manifest, indent=2) + "\n")
    build_id = "corpus-" + provenance["binarySHA256"][:16]
    total_bytes = 0
    with (args.output / "progress.jsonl").open("x", buffering=1) as progress:
        for index, game in enumerate(games):
            try:
                if total_bytes >= BATCH_TRACE_BYTES:
                    raise ValueError("batch trace byte cap reached")
                result = run_one(binary, args.output, game, index, build_id,
                                 BATCH_TRACE_BYTES - total_bytes)
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                progress.write(json.dumps({"index": index, "status": "failed", "error": str(error)}) + "\n")
                raise
            total_bytes += result["traceBytes"]
            progress.write(json.dumps({"status": "complete", **result}) + "\n")
            print(f"game {index + 1}/{len(games)}: parity passed, {result['moves']} moves", flush=True)
    (args.output / "complete.json").write_text(json.dumps(
        {"games": len(games), "traceBytes": total_bytes, "plainTraceParity": True}) + "\n")


if __name__ == "__main__":
    main()
