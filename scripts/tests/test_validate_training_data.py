#!/usr/bin/env python3

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "validate-training-data.py"
SPEC = importlib.util.spec_from_file_location("training_data", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def valid_record() -> dict:
    return {
        "schemaVersion": 2,
        "buildID": "test-build",
        "stateLayoutVersion": 3,
        "actionLayoutVersion": 2,
        "actionCount": 9_335,
        "seed": 7,
        "decisionIndex": 0,
        "observerSeat": 0,
        "winnerSeat": 0,
        "playerCount": 4,
        "victoryPointTarget": 10,
        "boardMode": "randomized",
        "policyID": "heuristic-balanced",
        "hiddenInformationPolicy": "revealAll",
        "features": [0.0] * 5_182,
        "legalActionIndices": [3, 12],
        "chosenActionIndex": 12,
        "outcome": 1,
    }


class TrainingDataValidationTests(unittest.TestCase):
    def test_accepts_the_complete_contract(self) -> None:
        self.assertEqual(MODULE.validate_row(valid_record(), "test-build", "revealAll", "row"), (7, 0))

    def test_rejects_a_stale_layout(self) -> None:
        record = valid_record()
        record["stateLayoutVersion"] = 2
        with self.assertRaisesRegex(ValueError, "stateLayoutVersion=3"):
            MODULE.validate_row(record, "test-build", "revealAll", "row")

    def test_rejects_a_negative_decision_index(self) -> None:
        record = valid_record()
        record["decisionIndex"] = -1
        with self.assertRaisesRegex(ValueError, "must be nonnegative"):
            MODULE.validate_row(record, "test-build", "revealAll", "row")

    def test_rejects_unsupported_evaluation_configuration(self) -> None:
        for field, value, message in (
            ("playerCount", 2, "invalid playerCount"),
            ("victoryPointTarget", 9, "invalid victoryPointTarget"),
            ("boardMode", "custom", "invalid boardMode"),
        ):
            with self.subTest(field=field):
                record = valid_record()
                record[field] = value
                with self.assertRaisesRegex(ValueError, message):
                    MODULE.validate_row(record, "test-build", "revealAll", "row")

    def test_rejects_a_chosen_action_outside_the_mask(self) -> None:
        record = valid_record()
        record["chosenActionIndex"] = 13
        with self.assertRaisesRegex(ValueError, "outside the legal mask"):
            MODULE.validate_row(record, "test-build", "revealAll", "row")

    def test_rejects_an_outcome_that_disagrees_with_the_winner(self) -> None:
        record = valid_record()
        record["winnerSeat"] = 1
        with self.assertRaisesRegex(ValueError, "outcome disagrees"):
            MODULE.validate_row(record, "test-build", "revealAll", "row")

    def test_rejects_unsorted_or_duplicate_legal_actions(self) -> None:
        record = valid_record()
        record["legalActionIndices"] = [12, 3, 3]
        with self.assertRaisesRegex(ValueError, "sorted and unique"):
            MODULE.validate_row(record, "test-build", "revealAll", "row")

    def test_rejects_nonfinite_or_out_of_range_features(self) -> None:
        for bad in (float("nan"), -0.1, 1.1):
            record = valid_record()
            record["features"][10] = bad
            with self.assertRaisesRegex(ValueError, "finite 0...1"):
                MODULE.validate_row(record, "test-build", "revealAll", "row")

    def test_rejects_duplicate_decisions_across_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            paths = []
            for name in ("first", "second"):
                path = Path(directory) / f"{name}.jsonl"
                path.write_text(json.dumps(valid_record()) + "\n", encoding="utf-8")
                paths.append(path)
            with self.assertRaisesRegex(ValueError, "duplicate decision"):
                MODULE.validate_files(paths, "test-build", "revealAll")

    def test_same_seed_in_different_configurations_is_not_a_duplicate_game(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            standard = valid_record()
            standard["boardMode"] = "standard"
            randomized = valid_record()
            path = Path(directory) / "matrix.jsonl"
            path.write_text(
                json.dumps(standard) + "\n" + json.dumps(randomized) + "\n",
                encoding="utf-8",
            )

            rows, seeds = MODULE.validate_files([path], "test-build", "revealAll")

        self.assertEqual(rows, 2)
        self.assertEqual(seeds, 1)

    def test_rejects_duplicate_or_extra_fields(self) -> None:
        record = valid_record()
        record["invented"] = True
        with self.assertRaisesRegex(ValueError, "schema fields differ"):
            MODULE.validate_row(record, "test-build", "revealAll", "row")
        with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
            MODULE.reject_duplicate_keys([("seed", 1), ("seed", 2)])


if __name__ == "__main__":
    unittest.main()
