"""Offline integrity checks on the two closed cap replays; never launches games."""

import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path("/tmp/empires-cap-replays-20260906")
CASES = (
    (
        "candidate",
        961131,
        "/tmp/empires-target-native-seed0-20260906/candidate-seat1.jsonl",
    ),
    (
        "baseline",
        961105,
        "/tmp/empires-target-native-seed1-20260906/baseline-seat3.jsonl",
    ),
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def validate(arm: str, seed: int, original_path: str) -> dict:
    original = [
        json.loads(line)
        for line in Path(original_path).read_text().splitlines()
        if json.loads(line)["seed"] == seed
    ]
    require(len(original) == 1, "ambiguous original game")
    current = json.loads((ROOT / f"{arm}.verified.json").read_text())["result"]
    previous = original[0]
    current.pop("buildID")
    previous.pop("buildID")
    require(current == previous, "game JSON differs beyond build identity")
    counts = Counter()
    evaluations = {}
    committed = set()
    terminal = None
    trace = ROOT / f"{arm}.trace.jsonl"
    with trace.open() as stream:
        for sequence, line in enumerate(stream):
            row = json.loads(line)
            require(
                row["schemaVersion"] == 1 and row["sequence"] == sequence,
                "row sequence/schema",
            )
            require(row["seed"] == seed, "mixed seed")
            require(terminal is None, "rows after terminal")
            kind, payload = row["type"], row["payload"]
            counts[kind] += 1
            if kind == "evaluation":
                index = payload["evaluationIndex"]
                require(index == len(evaluations), "evaluation order")
                evaluations[index] = (
                    payload["seat"],
                    payload["move"],
                    payload["policyTrace"],
                )
            elif kind == "commit":
                index = payload["policyTrace"]["evaluationIndex"]
                require(index not in committed, "evaluation committed twice")
                require(
                    evaluations[index]
                    == (payload["actor"], payload["move"], payload["policyTrace"]),
                    "commit mismatch",
                )
                require(row["moveIndex"] == len(committed), "commit order")
                committed.add(index)
            elif kind == "end":
                terminal = row
            else:
                require(kind == "start" and sequence == 0, "unexpected row")
    require(counts["start"] == 1 and counts["end"] == 1, "missing boundary")
    end = terminal["payload"]
    require(
        end["reason"] == "moveCap" and end["fingerprint"] == current["fingerprint"],
        "terminal mismatch",
    )
    require(end["evaluationCount"] == len(evaluations), "missing evaluations")
    require(
        terminal["moveIndex"] == counts["commit"] == current["moves"], "missing commits"
    )
    require(end["victoryPoints"] == current["vp"], "terminal score mismatch")
    return {
        "rows": sum(counts.values()),
        "row_counts": dict(counts),
        "all_commit_links_match": True,
        "all_game_fields_except_build_id_match": True,
        "sha256": hashlib.sha256(trace.read_bytes()).hexdigest(),
    }


if __name__ == "__main__":
    result = {arm: validate(arm, seed, source) for arm, seed, source in CASES}
    with (ROOT / "trace-integrity.json").open("x") as output:
        json.dump(result, output, indent=2, sort_keys=True)
    print(json.dumps(result, indent=2))
