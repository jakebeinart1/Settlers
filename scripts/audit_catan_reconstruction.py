"""Read-only terminal audit of a watched upstream reconstruction.

Run on the training host where checkpoint paths resolve. No Torch loading,
training, retries or strength verdict: the supervisor checks tensor finiteness;
this independently checks retained artifacts and outcome accounting.
"""

import argparse
import json
from pathlib import Path

from catan_policy_evidence import digest


def require(condition: bool, message: str) -> None:
    """Reject incomplete or inconsistent evidence instead of printing success."""
    if not condition:
        raise ValueError(message)


def read_json(path: Path) -> dict | list:
    return json.loads(path.read_text())


def read_rows(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines()]


def check_hash(path: Path, expected: str) -> None:
    require(digest(path) == expected, f"artifact hash mismatch: {path}")


def check_stages(stages: dict) -> dict:
    """Verify the exact parent, immutable final weights and metrics on disk."""
    require(set(stages) == {"fresh", "continuation"}, "missing training stage")
    fresh, continuation = stages["fresh"], stages["continuation"]
    require(not fresh["config"]["resume"], "fresh stage was not random initialization")
    require(
        continuation["config"]["resume"] == fresh["checkpoint"],
        "continuation did not resume the fresh final checkpoint",
    )
    result = {}
    for name, stage in stages.items():
        checkpoint = Path(stage["checkpoint"])
        check_hash(checkpoint, stage["checkpoint_sha256"])
        check_hash(checkpoint.parent.parent / "metrics.jsonl", stage["metrics_sha256"])
        require(stage["steps"] > 0 and stage["updates"] > 0, "empty training stage")
        result[name] = {
            key: stage[key] for key in ("steps", "updates", "checkpoint_sha256")
        }
        result[name]["minutes"] = stage["config"]["minutes"]
    return result


def count_outcomes(rows: list[dict], requested: int) -> dict:
    """Retain batch overshoot, and never count a capped episode as a win."""
    require(len(rows) >= requested, "evaluation has too few completed episodes")
    for ordinal, row in enumerate(rows):
        require(row["ordinal"] == ordinal, "non-contiguous outcome ordinals")
        require(type(row["capped"]) is bool, "invalid cap flag")
        require(
            type(row["winner"]) is int and row["winner"] in range(-1, 4),
            "invalid winner",
        )
        require(row["capped"] or row["winner"] >= 0, "unfinished uncapped episode")
    return {
        "games": len(rows),
        "wins": sum(row["winner"] == 0 and not row["capped"] for row in rows),
        "caps": sum(row["capped"] for row in rows),
    }


def check_evaluation(output: Path, manifest: dict, status: dict) -> list[dict]:
    """Require every predeclared cell, and recalculate its counts from raw rows."""
    protocol = manifest["protocol"]
    require(
        all(
            protocol[key] == value
            for key, value in {
                "lanes": 48,
                "requested_games": 192,
                "victory_target": 7,
                "visibility": "perfect",
                "policy_seat": 0,
                "opponent": "heuristic",
            }.items()
        ),
        "unexpected evaluation protocol",
    )
    records = read_json(output / "evaluation.json")
    require(records == status["evaluation"], "status/evaluation disagreement")
    seeds = manifest["evaluation_seeds"]
    require(len(set(seeds)) == len(seeds) and seeds, "invalid seed declaration")
    expected = {
        (model, seed) for model in ("original", "reconstructed") for seed in seeds
    }
    keys = [(row["model"], row["seed"]) for row in records]
    require(
        len(keys) == len(expected) and set(keys) == expected, "missing/duplicate cell"
    )
    hashes = {
        "original": manifest["checkpoint_sha256"],
        "reconstructed": status["stages"]["continuation"]["checkpoint_sha256"],
    }
    for record in records:
        require(record["checkpoint_sha256"] == hashes[record["model"]], "wrong model")
        path = output / f"{record['model']}-seed-{record['seed']}.jsonl"
        check_hash(path, record["outcomes_sha256"])
        counts = count_outcomes(
            read_rows(path), manifest["protocol"]["requested_games"]
        )
        require(
            all(record[key] == value for key, value in counts.items()), "wrong counts"
        )
    return records


def check_terminal(receipt: dict, status: dict) -> None:
    """A success from a different or overdue process does not certify this run."""
    require(
        receipt["state"] == "complete" and receipt["exit_code"] == 0,
        "watchdog not successful",
    )
    require(status["phase"] == "complete", "pipeline not complete")
    require(
        receipt["process_group"] == status["pid"], "receipt belongs to another pipeline"
    )
    require(
        receipt["started_epoch"]
        <= status["started"]
        <= status["finished"]
        <= receipt["deadline_epoch"],
        "pipeline outside recorded deadline",
    )


def check_native(output: Path, status: dict) -> None:
    """Match the actual export and native game to the supervisor's receipt."""
    check_hash(output / "final.ctnn", status["ctnn_sha256"])
    games = [
        row for row in read_rows(output / "native-metrics.jsonl") if row["t"] == "game"
    ]
    require(games == [status["native_game"]], "native metrics/status disagreement")
    game = games[0]
    require(
        type(game["winner"]) is int
        and game["winner"] in range(4)
        and game["cap"] is False
        and game["steps"] > 0,
        "native game did not finish",
    )


def audit(output: Path) -> dict:
    """Only a successfully terminated pipeline can produce an audited report."""
    receipt = read_json(output.with_name(output.name + ".watchdog.json"))
    status = read_json(output / "status.json")
    manifest = read_json(output / "manifest.json")
    check_terminal(receipt, status)
    stages = check_stages(status["stages"])
    check_native(output, status)
    records = check_evaluation(output, manifest, status)
    return report(output, stages, records)


def report(output: Path, stages: dict, records: list[dict]) -> dict:
    """Keep artifact integrity and playing strength as separate conclusions."""
    return {
        "artifact_audit": "passed",
        "auditor_sha256": digest(Path(__file__)),
        "manifest_sha256": digest(output / "manifest.json"),
        "status_sha256": digest(output / "status.json"),
        "training_reproduction_verdict": "not_assessed",
        "scope": "Fixed policy chair, perfect information, first to 7, three heuristic opponents. Not human play, Elo, search strength or an every-chair evaluation.",
        "stages": stages,
        "evaluation": records,
        "totals": {
            model: {
                key: sum(row[key] for row in records if row["model"] == model)
                for key in ("wins", "games", "caps")
            }
            for model in ("original", "reconstructed")
        },
        "limitations": "Single training seed; parallel outcomes have no per-game pairing IDs. Equal wall time on a GPU does not reproduce the historical sample budget. Native search game is a separate 10-point smoke check.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(audit(args.output.resolve()), indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
