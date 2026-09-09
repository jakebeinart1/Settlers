"""Falsify the offline formula independently of reviewer preferences or wins."""

import itertools
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1]))
import trade_accounting as ACCOUNTING


# Synthetic independent oracle, not a second runtime implementation of Catan.
RESOURCES = ("brick", "lumber", "ore", "grain", "wool")
TARGETS = {
    "settlement": ({"brick": 1, "lumber": 1, "grain": 1, "wool": 1}, 3.0),
    "city": ({"ore": 3, "grain": 2}, 2.5),
    "devCard": ({"ore": 1, "grain": 1, "wool": 1}, 1.5),
    "road": ({"brick": 1, "lumber": 1}, 1.0),
}


def hand(**values):
    return {resource: values.get(resource, 0) for resource in RESOURCES}


def fixture(before, after):
    score = {
        "offer": {"give": [], "want": []},
        "resourceContributions": [],
        "gainValue": 0.0,
        "costValue": 0.0,
        "baseThreshold": 0.4,
        "threatShift": 0.0,
        "standingShift": 0.0,
        "suspicionShift": 0.0,
        "unlockShift": 0.0,
        "threshold": 0.4,
        "receiver": {"index": 0},
    }
    for resource in RESOURCES:
        change = after[resource] - before[resource]
        if change == 0:
            continue
        direction = "gain" if change > 0 else "cost"
        score["offer"]["give" if change > 0 else "want"] += [resource, abs(change)]
        entries = []
        for name, (cost, weight) in TARGETS.items():
            deficit = max(0, cost.get(resource, 0) - before[resource])
            other = sum(
                max(0, amount - before[key])
                for key, amount in cost.items()
                if key != resource
            )
            entries.append(
                {
                    "targetName": name,
                    "weight": weight,
                    "held": before[resource],
                    "required": cost.get(resource, 0),
                    "deficit": deficit,
                    "otherDeficits": other,
                    "contribution": weight / (1 + other) if deficit else 0.0,
                }
            )
        unit = sum(entry["contribution"] for entry in entries)
        score["resourceContributions"].append(
            {
                "resource": resource,
                "quantity": abs(change),
                "direction": direction,
                "targets": entries,
                "unitValue": unit,
                "totalValue": unit * abs(change),
            }
        )
        score["gainValue" if change > 0 else "costValue"] += unit * abs(change)
    score["netGain"] = score["gainValue"] - score["costValue"]
    score["accepted"] = score["netGain"] > score["threshold"]
    return score


def value(inventory):
    return sum(
        ACCOUNTING.target_value(
            sum(max(0, n - inventory[r]) for r, n in cost.items()), weight
        )
        for cost, weight in TARGETS.values()
    )


class TradeAccountingTests(unittest.TestCase):
    def test_sole_surplus_and_destroyed_completion_worked_examples(self):
        cases = [
            (hand(ore=1, grain=1), hand(grain=1, wool=1), 0, 0.25),
            (hand(ore=2, grain=1), hand(ore=1, grain=1, wool=1), 1.5, 19 / 12),
            (
                hand(ore=1, grain=1, wool=1),
                hand(lumber=1, grain=1, wool=1),
                -1.5,
                -5 / 12,
            ),
        ]
        for before, after, expected_dev, expected_total in cases:
            terms = ACCOUNTING.target_deltas(fixture(before, after), before, after)
            self.assertAlmostEqual(
                next(t["experimentalNet"] for t in terms if t["target"] == "devCard"),
                expected_dev,
            )
            self.assertAlmostEqual(
                sum(t["experimentalNet"] for t in terms), expected_total
            )

    def test_3125_hands_reverse_swaps_match_direct_independent_potential(self):
        # Quantities 0..4 cover below/at/above every single-target requirement.
        comparisons = 0
        for counts in itertools.product(range(5), repeat=5):
            before = dict(zip(RESOURCES, counts))
            for sold, bought in itertools.permutations(RESOURCES, 2):
                if not before[sold]:
                    continue
                after = {**before, sold: before[sold] - 1, bought: before[bought] + 1}
                actual = sum(
                    t["experimentalNet"]
                    for t in ACCOUNTING.target_deltas(
                        fixture(before, after), before, after
                    )
                )
                reverse = sum(
                    t["experimentalNet"]
                    for t in ACCOUNTING.target_deltas(
                        fixture(after, before), after, before
                    )
                )
                self.assertAlmostEqual(actual, value(after) - value(before))
                self.assertAlmostEqual(actual, -reverse)
                comparisons += 1
        self.assertEqual(comparisons, 50000)

    def test_addition_monotonicity_bundle_order_and_cycles(self):
        for counts in itertools.product(range(3), repeat=5):
            start = dict(zip(RESOURCES, counts))
            initial = value(start)
            self.assertEqual(value(start) - initial, 0)
            for first, second in itertools.product(RESOURCES, repeat=2):
                middle = {**start, first: start[first] + 1}
                finish = {**middle, second: middle[second] + 1}
                alternate = {**start, second: start[second] + 1}
                reverse_finish = {**alternate, first: alternate[first] + 1}
                self.assertGreaterEqual(value(middle), initial)
                self.assertEqual(finish, reverse_finish)
                direct = sum(
                    t["experimentalNet"]
                    for t in ACCOUNTING.target_deltas(
                        fixture(start, finish), start, finish
                    )
                )
                self.assertAlmostEqual(direct, value(finish) - initial)
                self.assertAlmostEqual(
                    (value(middle) - initial) + (value(finish) - value(middle)), direct
                )
                self.assertAlmostEqual(direct + initial - value(finish), 0)

    def test_surplus_is_explicitly_saturated_not_invented_inventory_value(self):
        before = hand(ore=1, grain=1)
        one, many = hand(ore=1, grain=1, wool=1), hand(ore=1, grain=1, wool=3)
        self.assertEqual(value(one), value(many))
        self.assertGreater(
            fixture(before, many)["netGain"], fixture(before, one)["netGain"]
        )

    def test_native_metadata_inconsistency_is_rejected(self):
        before, after = hand(ore=1, grain=1), hand(grain=1, wool=1)
        for field in ("held", "otherDeficits", "weight"):
            score = fixture(before, after)
            score["resourceContributions"][0]["targets"][0][field] += 1
            with self.assertRaises(ValueError):
                ACCOUNTING.target_deltas(score, before, after)
        score = fixture(before, after)
        after["brick"] += 1
        with self.assertRaisesRegex(ValueError, "exchange inventories"):
            ACCOUNTING.target_deltas(score, before, after)

    def test_receiving_resource_cannot_silently_become_losing_it(self):
        before, after = hand(brick=3, grain=1), hand(brick=2, grain=2)
        score = fixture(before, after)
        after["grain"] = 0
        with self.assertRaisesRegex(ValueError, "exchange inventories"):
            ACCOUNTING.target_deltas(score, before, after)

    def test_invalid_target_values_fail(self):
        for deficit, weight in (
            (-1, 1),
            (1.5, 1),
            (True, 1),
            (1, -1),
            (1, float("nan")),
        ):
            with self.assertRaises(ValueError):
                ACCOUNTING.target_value(deficit, weight)

    def test_no_scored_or_legal_acceptance_means_no_fabricated_candidate(self):
        self.assertEqual(
            ACCOUNTING.compare({"id": "forced"})["status"], "unscored-no-candidate"
        )
        with self.assertRaisesRegex(ValueError, "successful native"):
            ACCOUNTING.compare(
                {
                    "id": "bad",
                    "assessment": {"receiver": {"index": 0}},
                    "context": {"acceptInRecordedMask": False},
                }
            )

    def test_real_cli_receipt_hash_failure_and_overwrite_protection(self):
        before, after = hand(ore=1, grain=1), hand(grain=1, wool=1)
        facts = lambda inventory: {
            "seat": 0,
            "hand": inventory,
            "mainTurnOptionsOnFrozenBoard": {},
        }
        record = {
            "id": "test",
            "assessment": fixture(before, after),
            "context": {
                "acceptInRecordedMask": True,
                "before": [facts(before)],
                "afterAcceptance": [facts(after)],
            },
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            native = root / "native-output.jsonl"
            native.write_text(json.dumps(record) + "\n")
            receipt = {
                "status": "complete",
                "cases": 1,
                "nativeOutputSHA256": ACCOUNTING.digest(native),
            }
            (root / "receipt.json").write_text(json.dumps(receipt))
            command = [
                sys.executable,
                ACCOUNTING.__file__,
                "--enriched",
                str(root),
                "--output",
                str(root / "result"),
            ]
            success = subprocess.run(
                command, capture_output=True, text=True, timeout=10
            )
            self.assertEqual(success.returncode, 0, success.stderr)
            final = json.loads((root / "result/receipt.json").read_text())
            self.assertFalse(final["strengthEvaluated"])
            existing = subprocess.run(
                command, capture_output=True, text=True, timeout=10
            )
            self.assertNotEqual(existing.returncode, 0)
            native.write_text("changed\n")
            command[-1] = str(root / "bad")
            failed = subprocess.run(command, capture_output=True, text=True, timeout=10)
            self.assertNotEqual(failed.returncode, 0)
            self.assertFalse((root / "bad").exists())


if __name__ == "__main__":
    unittest.main()
