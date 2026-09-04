#!/usr/bin/env python3

import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "train-policy-baseline.py"
SPEC = importlib.util.spec_from_file_location("policy_baseline", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def row(seed: int, phase: int, chosen: int, outcome: int = 1) -> dict:
    features = [0.0] * 5_182
    features[phase] = 1.0
    return {
        "seed": seed,
        "decisionIndex": 0,
        "features": features,
        "legalActionIndices": [3, 8],
        "chosenActionIndex": chosen,
        "outcome": outcome,
        "policyID": "teacher",
        "hiddenInformationPolicy": "revealAll",
    }


class PolicyValueBaselineTests(unittest.TestCase):
    def test_split_keeps_every_game_in_exactly_one_fold(self) -> None:
        rows = [row(seed, 0, 3) for seed in range(10) for _ in range(2)]
        train, test = MODULE.split_by_seed(rows)
        train_seeds = {item["seed"] for item in train}
        test_seeds = {item["seed"] for item in test}
        self.assertFalse(train_seeds & test_seeds)
        self.assertEqual(train_seeds | test_seeds, set(range(10)))

    def test_masked_policy_never_selects_an_illegal_popular_action(self) -> None:
        counts = MODULE.train_policy([row(1, 0, 8), row(2, 0, 8)])
        test = row(3, 0, 3)
        test["legalActionIndices"] = [3]
        self.assertEqual(MODULE.predict_action(test, counts), 3)

    def test_phase_conditioning_changes_the_learned_preference(self) -> None:
        counts = MODULE.train_policy([row(1, 0, 3), row(2, 1, 8)])
        self.assertEqual(MODULE.predict_action(row(3, 0, 8), counts), 3)
        self.assertEqual(MODULE.predict_action(row(4, 1, 3), counts), 8)

    def test_value_baseline_fits_a_separable_signal(self) -> None:
        rows = []
        for seed in range(10):
            positive = row(seed, 0, 3, outcome=1)
            negative = row(seed, 0, 3, outcome=-1)
            positive["features"][20] = 1.0
            negative["features"][21] = 1.0
            rows.extend([positive, negative])
        weights, bias = MODULE.train_value(rows)
        metrics = MODULE.value_metrics(rows, weights, bias, train_mean=0)
        self.assertGreater(metrics["signAccuracy"], 0.9)

    def test_checkpoint_records_layouts_and_training_seeds(self) -> None:
        rows = [row(seed, seed % 2, 3 if seed % 2 else 8) for seed in range(10)]
        _, checkpoint = MODULE.train_and_evaluate(rows)
        self.assertEqual(checkpoint["stateLayoutVersion"], 3)
        self.assertEqual(checkpoint["actionLayoutVersion"], 2)
        self.assertEqual(checkpoint["featureCount"], 5_182)
        self.assertEqual(checkpoint["trainingSeeds"], [1, 2, 3, 4, 6, 7, 8, 9])

    def test_checkpoint_round_trip_preserves_predictions_and_bytes(self) -> None:
        rows = [row(seed, seed % 2, 3 if seed % 2 else 8) for seed in range(10)]
        _, checkpoint = MODULE.train_and_evaluate(rows)
        first = MODULE.checkpoint_bytes(checkpoint, "build", "a" * 64)
        second = MODULE.checkpoint_bytes(checkpoint, "build", "a" * 64)
        self.assertEqual(first, second)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "model.json"
            path.write_bytes(first)
            loaded = MODULE.load_checkpoint(path, "build", "revealAll")
        self.assertEqual(
            MODULE.checkpoint_predictions(rows[0], checkpoint),
            MODULE.checkpoint_predictions(rows[0], loaded),
        )


if __name__ == "__main__":
    unittest.main()
