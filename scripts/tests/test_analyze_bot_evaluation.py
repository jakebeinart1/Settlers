#!/usr/bin/env python3

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "analyze-bot-evaluation.py"
SPEC = importlib.util.spec_from_file_location("bot_evaluation", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def record(seat: int, seed: int = 10, build_id: str = "test-build") -> dict:
    policies = ["greedy"] * 4
    policies[seat] = "heuristic-balanced"
    return {
        "schemaVersion": 2,
        "buildID": build_id,
        "policies": policies,
        "seed": seed,
        "winner": seat,
        "moves": 100,
        "behavior": [{} for _ in range(4)],
    }


class EvaluationInputTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_shard(self, seat: int, rows: list[dict]) -> Path:
        path = self.root / f"balanced-seat{seat}.jsonl"
        path.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")
        return path

    def valid_paths(self) -> list[Path]:
        return [self.write_shard(seat, [record(seat)]) for seat in range(4)]

    def load(self, paths: list[Path]) -> list[tuple[int, dict]]:
        return MODULE.load(paths, "test-build", "heuristic-balanced", "greedy")

    def test_accepts_a_complete_paired_rotation(self) -> None:
        self.assertEqual(len(self.load(self.valid_paths())), 4)

    def test_rejects_a_duplicate_seed_within_a_shard(self) -> None:
        paths = self.valid_paths()
        paths[2] = self.write_shard(2, [record(2), record(2)])
        with self.assertRaisesRegex(SystemExit, "duplicate or invalid seed"):
            self.load(paths)

    def test_rejects_mismatched_seed_sets(self) -> None:
        paths = self.valid_paths()
        paths[3] = self.write_shard(3, [record(3, seed=11)])
        with self.assertRaisesRegex(SystemExit, "seed set differs"):
            self.load(paths)

    def test_rejects_wrong_build_provenance(self) -> None:
        paths = self.valid_paths()
        paths[1] = self.write_shard(1, [record(1, build_id="other")])
        with self.assertRaisesRegex(SystemExit, "expected schema 2/build"):
            self.load(paths)

    def test_rejects_wrong_policy_provenance(self) -> None:
        paths = self.valid_paths()
        row = record(0)
        row["policies"][0] = "heuristic-cautious"
        paths[0] = self.write_shard(0, [row])
        with self.assertRaisesRegex(SystemExit, "expected 'heuristic-balanced'"):
            self.load(paths)

    def test_clustered_interval_handles_uneven_timeouts(self) -> None:
        rows = {
            10: [(0, {"winner": 0}), (1, {"winner": None})],
            11: [(0, {"winner": 1}), (1, {"winner": 0})],
        }
        lower, upper = MODULE.clustered_win_interval(rows)
        observed = 2 / 3
        self.assertLessEqual(lower, observed)
        self.assertGreaterEqual(upper, observed)


if __name__ == "__main__":
    unittest.main()
