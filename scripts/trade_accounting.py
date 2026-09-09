#!/usr/bin/env python3
"""Offline sensitivity of ONE fixed joint-target formula; never a playing policy.

Read native before/after inventories and the native scorer's target deficits.
Only changed resources need updating: other deficits stay fixed. No game rules,
build costs, weights or legal transitions are reimplemented here. Existing
thresholds remain unchanged for sensitivity, not because their scale is proven.
"""

import argparse
import json
import math
import shutil
from pathlib import Path

from enrich_corpus import digest
from review_corpus import close, reject_constant, resource_map, validate_assessment


FORMULA = "joint-target-reciprocal-v1"
COMPLETION_SCALE = 2.0  # One remaining card -> complete earns exactly target weight.
MAX_INPUT_BYTES = 8 * 1024 * 1024
MAX_CASES = 120
TARGET_NAMES = {"settlement", "city", "devCard", "road"}


def target_value(deficit: int, weight: float) -> float:
    """Fixed target potential, not a probability or value of a legal build."""
    if (
        type(deficit) is not int
        or deficit < 0
        or not math.isfinite(weight)
        or weight < 0
    ):
        raise ValueError("invalid target deficit/weight")
    return COMPLETION_SCALE * weight / (1 + deficit)


def target_inputs(score: dict, before: dict) -> dict:
    """Recover target totals consistently from all native per-resource entries."""
    targets = {}
    for component in score["resourceContributions"]:
        resource = component["resource"]
        names = set()
        for entry in component["targets"]:
            name = entry["targetName"]
            if name in names:
                raise ValueError("duplicate target")
            names.add(name)
            missing = entry["deficit"] + entry["otherDeficits"]
            item = targets.setdefault(
                name,
                {
                    "beforeMissing": missing,
                    "weight": entry["weight"],
                    "requirements": {},
                    "legacyNet": 0.0,
                },
            )
            if (item["beforeMissing"], item["weight"]) != (missing, entry["weight"]):
                raise ValueError("inconsistent native target totals")
            if entry["held"] != before[resource]:
                raise ValueError("scorer holding differs from native hand")
            required = item["requirements"].setdefault(resource, entry["required"])
            if required != entry["required"]:
                raise ValueError("inconsistent native target cost")
            sign = 1 if component["direction"] == "gain" else -1
            item["legacyNet"] += sign * component["quantity"] * entry["contribution"]
        if names != TARGET_NAMES:
            raise ValueError("incomplete native target inventory")
    return targets


def validate_exchange(score: dict, before: dict, after: dict) -> None:
    """Check emitted inventory arithmetic, not whether native rules allow the trade."""
    if set(before) != set(after) or any(
        type(n) is not int or n < 0 for n in (*before.values(), *after.values())
    ):
        raise ValueError("invalid native hands")
    received = resource_map(score["offer"]["give"])
    paid = resource_map(score["offer"]["want"])
    if not (received.keys() | paid.keys()) <= before.keys():
        raise ValueError("offer resource absent from native hand")
    if any(after[r] != before[r] + received.get(r, 0) - paid.get(r, 0) for r in before):
        raise ValueError("native exchange inventories disagree with offer")


def target_deltas(score: dict, before: dict, after: dict) -> list[dict]:
    validate_assessment(score)
    if not score.get("resourceContributions"):
        raise ValueError("native resource contributions required")
    validate_exchange(score, before, after)
    changed = {key for key in before if before[key] != after[key]}
    result = []
    for name, item in sorted(target_inputs(score, before).items()):
        requirements = item["requirements"]
        if not changed <= requirements.keys():
            raise ValueError("changed resource lacks native target metadata")
        missing = item["beforeMissing"] + sum(
            max(0, required - after[resource]) - max(0, required - before[resource])
            for resource, required in sorted(requirements.items())
        )
        delta = target_value(missing, item["weight"]) - target_value(
            item["beforeMissing"], item["weight"]
        )
        result.append(
            {
                "target": name,
                "beforeMissing": item["beforeMissing"],
                "afterMissing": missing,
                "weight": item["weight"],
                "legacyNet": item["legacyNet"],
                "experimentalNet": delta,
            }
        )
    close(sum(item["legacyNet"] for item in result), score["netGain"])
    return result


def compare(record: dict) -> dict:
    score = record.get("assessment")
    if score is None:
        return {"id": record["id"], "status": "unscored-no-candidate"}
    context = record["context"]
    if (
        not context["acceptInRecordedMask"]
        or context.get("nativeAcceptanceError")
        or not context.get("afterAcceptance")
    ):
        raise ValueError("candidate requires successful native acceptance")
    receiver = score["receiver"]["index"]
    before = next(seat for seat in context["before"] if seat["seat"] == receiver)
    after = next(
        seat for seat in context["afterAcceptance"] if seat["seat"] == receiver
    )
    terms = target_deltas(score, before["hand"], after["hand"])
    candidate = sum(term["experimentalNet"] for term in terms)
    return {
        "id": record["id"],
        "status": "scored",
        "formula": FORMULA,
        "legacyAccepted": score["accepted"],
        "legacyNet": score["netGain"],
        "experimentalNet": candidate,
        "unchangedThreshold": score["threshold"],
        "experimentalAccepted": candidate > score["threshold"],
        "targets": terms,
        "nativeOptionsBefore": before["mainTurnOptionsOnFrozenBoard"],
        "nativeOptionsAfter": after["mainTurnOptionsOnFrozenBoard"],
    }


def run(enriched: Path, output: Path) -> None:
    receipt_path = enriched / "receipt.json"
    receipt = json.loads(receipt_path.read_text(), parse_constant=reject_constant)
    native = enriched / "native-output.jsonl"
    if (
        receipt["status"] != "complete"
        or digest(native) != receipt["nativeOutputSHA256"]
    ):
        raise ValueError("complete, hash-matching native evidence required")
    if native.stat().st_size > MAX_INPUT_BYTES:
        raise ValueError("native evidence exceeds size budget")
    data = native.read_bytes()
    if not data.endswith(b"\n"):
        raise ValueError("truncated native evidence")
    records = [
        json.loads(line, parse_constant=reject_constant) for line in data.splitlines()
    ]
    if not 1 <= len(records) <= MAX_CASES or len(records) != receipt["cases"]:
        raise ValueError("native case count mismatch")
    if len({row["id"] for row in records}) != len(records):
        raise ValueError("duplicate case identity")
    results = [compare(record) for record in records]
    output.mkdir(parents=True, exist_ok=False)
    (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    for source in (
        Path(__file__),
        Path(__file__).with_name("enrich_corpus.py"),
        Path(__file__).with_name("review_corpus.py"),
    ):
        shutil.copy2(source, output / source.name)
    final = {
        "status": "complete",
        "formula": FORMULA,
        "cases": len(records),
        "sourceReceipt": str(receipt_path.resolve()),
        "receiptSHA256": digest(receipt_path),
        "nativeSHA256": digest(native),
        "scriptSHA256": digest(Path(__file__)),
        "resultsSHA256": digest(output / "results.json"),
        "strengthEvaluated": False,
    }
    (output / "receipt.json").write_text(json.dumps(final, indent=2) + "\n")
    print(json.dumps(final))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--enriched", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    run(arguments.enriched, arguments.output)
