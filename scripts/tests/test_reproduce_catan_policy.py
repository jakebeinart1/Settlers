"""Evidence accounting must remain testable without installing an RL stack."""

import copy
import importlib.util
import tempfile
import unittest
from pathlib import Path

RUNNER = Path(__file__).resolve().parents[1] / "catan_policy_evidence.py"
SPEC = importlib.util.spec_from_file_location("reproduce_catan_policy", RUNNER)
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class ReproductionEvidenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.rows = [
            {
                "ordinal": 0,
                "batch": 8,
                "turns": 70,
                "winner": 0,
                "victory_points": [7, 4, 2, 3],
                "capped": False,
            },
            {
                "ordinal": 1,
                "batch": 8,
                "turns": 51,
                "winner": 1,
                "victory_points": [3, 7, 4, 2],
                "capped": False,
            },
        ]

    def test_parallel_arrival_order_is_not_a_game_change(self) -> None:
        reversed_rows = copy.deepcopy(self.rows[::-1])
        for ordinal, row in enumerate(reversed_rows):
            row["ordinal"] = ordinal
        self.assertEqual(
            runner.outcome_digest(self.rows), runner.outcome_digest(reversed_rows)
        )

    def test_every_reported_game_field_affects_fingerprint(self) -> None:
        changes = {
            "batch": 9,
            "turns": 71,
            "winner": 2,
            "victory_points": [7, 5, 2, 3],
            "capped": True,
        }
        for key, value in changes.items():
            with self.subTest(key=key):
                changed = copy.deepcopy(self.rows)
                changed[0][key] = value
                self.assertNotEqual(
                    runner.outcome_digest(self.rows), runner.outcome_digest(changed)
                )

    def test_duplicate_games_are_not_deduplicated(self) -> None:
        self.assertNotEqual(
            runner.outcome_digest(self.rows),
            runner.outcome_digest(self.rows + [self.rows[0]]),
        )

    def test_gate_rejects_wrong_count_score_and_caps(self) -> None:
        rows = [
            dict(self.rows[0], ordinal=i, winner=0 if i < 126 else 1)
            for i in range(192)
        ]
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "games.jsonl"
            artifact.touch()
            good = runner.summarize(rows, artifact)
            self.assertTrue(good["artifact_gate_passed"])
            self.assertFalse(good["training_reproduced"])
            self.assertIsNone(good["local_outcome_replay_matched"])
            matched = runner.summarize(rows, artifact, runner.outcome_digest(rows))
            self.assertTrue(matched["artifact_gate_passed"])
            wrong_digest = runner.summarize(rows, artifact, "0" * 64)
            self.assertTrue(wrong_digest["artifact_score_matched"])
            self.assertFalse(wrong_digest["artifact_gate_passed"])
            bad_score = copy.deepcopy(rows)
            bad_score[0]["winner"] = 1
            capped = copy.deepcopy(rows)
            capped[0]["capped"] = True
            for bad in ([], rows[:-1], rows + [rows[-1]], bad_score, capped):
                with self.subTest(length=len(bad)):
                    self.assertFalse(
                        runner.summarize(bad, artifact)["artifact_gate_passed"]
                    )


if __name__ == "__main__":
    unittest.main()
