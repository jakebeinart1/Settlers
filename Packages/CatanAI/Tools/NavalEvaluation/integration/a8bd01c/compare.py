#!/usr/bin/env python3
"""Compare the declared matrix without relabeling historical source artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "src"))

from naval_evaluation.evaluation import validate_rows  # noqa: E402


def identity(row: dict) -> tuple:
    """Identify a matrix trajectory independently of its source label."""
    return tuple(
        row[key]
        for key in (
            "family",
            "fogEnabled",
            "resourceChoiceEnabled",
            "playerCount",
            "seed",
            "arm",
            "focalChair",
        )
    )


def indexed(rows: list[dict]) -> dict:
    """Reject duplicate trajectories instead of silently overwriting them."""
    result = {identity(row): row for row in rows}
    if len(result) != len(rows):
        raise ValueError("duplicate trajectory identity")
    return result


def semantic(row: dict) -> dict:
    """Exclude only the deliberate new build label, preserving every other field."""
    return {key: value for key, value in row.items() if key != "buildID"}


def digest(row: dict) -> str:
    """Pin the entire compared row in a stable, readable comparison receipt."""
    data = json.dumps(semantic(row), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(data.encode()).hexdigest()


def compare_results(historical: list[dict], integrated: list[dict]) -> dict:
    """Require symmetric keys and equality of all result fields, including moves."""
    old, new = indexed(historical), indexed(integrated)
    if old.keys() != new.keys():
        raise ValueError("historical and integrated trajectory keys differ")
    records = []
    for key in sorted(old):
        before, after = semantic(old[key]), semantic(new[key])
        changed = sorted(
            field
            for field in before.keys() | after.keys()
            if field not in before
            or field not in after
            or before[field] != after[field]
        )
        records.append(
            {
                "identity": list(key),
                "historicalFingerprint": old[key]["fingerprint"],
                "integratedFingerprint": new[key]["fingerprint"],
                "historicalResultSHA256": digest(old[key]),
                "integratedResultSHA256": digest(new[key]),
                "changedFields": changed,
                "equal": not changed,
            }
        )
    return {
        "excludedFields": ["buildID"],
        "comparedGames": len(records),
        "matchedGames": sum(record["equal"] for record in records),
        "allEqual": all(record["equal"] for record in records),
        "records": records,
    }


def main() -> int:
    """Validate both complete plans and their actual binary bytes before comparing."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("historical", type=pathlib.Path)
    parser.add_argument("integrated", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()
    historical = validate_rows(args.historical, "matrix", verify_binaries=True)
    integrated = validate_rows(args.integrated, "matrix", verify_binaries=True)
    report = compare_results(historical, integrated)
    report["historicalDirectory"] = str(args.historical.resolve())
    report["integratedDirectory"] = str(args.integrated.resolve())
    report["binaryVerification"] = "actual SHA-256 and Release manifest"
    report["performanceInterpretation"] = "CPU-contended diagnostic timing only"
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key != "records"}))
    return 0 if report["allEqual"] and report["comparedGames"] == 48 else 1


if __name__ == "__main__":
    raise SystemExit(main())
