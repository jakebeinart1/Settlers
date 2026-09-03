#!/usr/bin/env python3

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Optional


SCRIPT = Path(__file__).parents[1] / "analyze-bot-evaluation.py"
SPEC = importlib.util.spec_from_file_location("bot_evaluation", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def record(
    seat: int,
    seed: int = 10,
    build_id: str = "test-build",
    player_count: int = 4,
    schema_version: int = 5,
    victory_point_target: int = 10,
    board_mode: str = "randomized",
) -> dict:
    policies = ["greedy"] * player_count
    policies[seat] = "heuristic-balanced"
    result = {
        "schemaVersion": schema_version,
        "buildID": build_id,
        "policies": policies,
        "seed": seed,
        "winner": seat,
        "moves": 100,
        "behavior": [{} for _ in range(player_count)],
    }
    if schema_version == 5:
        result.update({
            "playerCount": player_count,
            "victoryPointTarget": victory_point_target,
            "boardMode": board_mode,
        })
    return result


def paired_record(
    seat: int,
    build_id: str,
    evaluated_policy: str,
    foil_policy: str,
    winner: Optional[int],
    moves: int,
    player_count: int = 4,
    schema_version: int = 5,
    victory_point_target: int = 10,
    board_mode: str = "randomized",
) -> dict:
    policies = [foil_policy] * player_count
    policies[seat] = evaluated_policy
    result = {
        "schemaVersion": schema_version,
        "buildID": build_id,
        "policies": policies,
        "seed": 10,
        "winner": winner,
        "moves": moves,
        "behavior": [{} for _ in range(player_count)],
    }
    if schema_version == 5:
        result.update({
            "playerCount": player_count,
            "victoryPointTarget": victory_point_target,
            "boardMode": board_mode,
        })
    return result


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

    def test_rejects_pooled_results_across_rules_configurations(self) -> None:
        paths: list[Path] = []
        for seat in range(4):
            rows = [record(seat, seed=11)]
            if seat < 3:
                rows.insert(0, record(
                    seat,
                    player_count=3,
                    victory_point_target=8,
                    board_mode="standard",
                ))
            paths.append(self.write_shard(seat, rows))

        with self.assertRaisesRegex(
            SystemExit,
            "analyze one rules configuration at a time",
        ):
            self.load(paths)

    def test_three_player_cluster_requires_exactly_three_rotations(self) -> None:
        paths = [
            self.write_shard(seat, [record(seat, player_count=3)])
            for seat in range(2)
        ]

        with self.assertRaisesRegex(SystemExit, r"needs rotations \[0, 1, 2\]"):
            self.load(paths)

    def test_evaluation_key_contains_every_configuration_dimension(self) -> None:
        original = record(0)
        original_key = MODULE.evaluation_key(0, original)
        variants = (
            {"playerCount": 3},
            {"victoryPointTarget": 12},
            {"boardMode": "standard"},
        )

        for changes in variants:
            with self.subTest(changes=changes):
                changed = dict(original)
                changed.update(changes)
                self.assertNotEqual(MODULE.evaluation_key(0, changed), original_key)

    def test_rejects_a_duplicate_seed_within_a_shard(self) -> None:
        paths = self.valid_paths()
        paths[2] = self.write_shard(2, [record(2), record(2)])
        with self.assertRaisesRegex(SystemExit, "duplicate or invalid seed"):
            self.load(paths)

    def test_rejects_mismatched_seed_sets(self) -> None:
        paths = self.valid_paths()
        paths[3] = self.write_shard(3, [record(3, seed=11)])
        with self.assertRaisesRegex(SystemExit, "seed/config key set differs"):
            self.load(paths)

    def test_rejects_wrong_build_provenance(self) -> None:
        paths = self.valid_paths()
        paths[1] = self.write_shard(1, [record(1, build_id="other")])
        with self.assertRaisesRegex(SystemExit, "expected schema 5/build"):
            self.load(paths)

    def test_rejects_wrong_policy_provenance(self) -> None:
        paths = self.valid_paths()
        row = record(0)
        row["policies"][0] = "heuristic-cautious"
        paths[0] = self.write_shard(0, [row])
        with self.assertRaisesRegex(SystemExit, "expected 'heuristic-balanced'"):
            self.load(paths)

    def test_rejects_current_schema_without_configuration_provenance(self) -> None:
        paths = self.valid_paths()
        for seat in range(4):
            row = record(seat)
            row.pop("playerCount")
            paths[seat] = self.write_shard(seat, [row])

        with self.assertRaisesRegex(SystemExit, "missing configuration field playerCount"):
            self.load(paths)

    def test_rejects_current_schema_with_incomplete_configuration(self) -> None:
        paths = self.valid_paths()
        for seat in range(4):
            row = record(seat)
            row.pop("boardMode")
            paths[seat] = self.write_shard(seat, [row])

        with self.assertRaisesRegex(SystemExit, "missing configuration field boardMode"):
            self.load(paths)

    def test_rejects_policy_and_behavior_widths_that_do_not_match_player_count(self) -> None:
        paths = self.valid_paths()
        wrong_policies = record(0)
        wrong_policies["policies"].append("greedy")
        paths[0] = self.write_shard(0, [wrong_policies])
        with self.assertRaisesRegex(SystemExit, "policy provenance width 5.*playerCount 4"):
            self.load(paths)

        paths = self.valid_paths()
        wrong_behavior = record(1)
        wrong_behavior["behavior"].pop()
        paths[1] = self.write_shard(1, [wrong_behavior])
        with self.assertRaisesRegex(SystemExit, "behavior width 3.*playerCount 4"):
            self.load(paths)

    def test_explicit_legacy_schema_three_and_four_use_four_seat_defaults(self) -> None:
        for schema_version in (3, 4):
            with self.subTest(schema_version=schema_version):
                paths = [
                    self.write_shard(
                        seat,
                        [record(seat, schema_version=schema_version)],
                    )
                    for seat in range(4)
                ]
                rows = MODULE.load(
                    paths,
                    "test-build",
                    "heuristic-balanced",
                    "greedy",
                    schema_version,
                )
                self.assertEqual(len(rows), 4)

    def test_clustered_interval_handles_uneven_timeouts(self) -> None:
        rows = {
            10: [(0, {"winner": 0}), (1, {"winner": None})],
            11: [(0, {"winner": 1}), (1, {"winner": 0})],
        }
        lower, upper = MODULE.clustered_win_interval(rows)
        observed = 2 / 3
        self.assertLessEqual(lower, observed)
        self.assertGreaterEqual(upper, observed)

    def test_metric_presence_supports_archived_schemas_without_new_fields(self) -> None:
        rows = [(0, {"behavior": [{"old": 1}]})]

        self.assertTrue(MODULE.has_metric(rows, "old"))
        self.assertFalse(MODULE.has_metric(rows, "new"))

    def test_paired_rate_difference_requires_the_same_seed_and_chair_keys(self) -> None:
        candidate = self.metric_rows(successes=3, opportunities=4)
        baseline = self.metric_rows(successes=1, opportunities=4)
        baseline[-1][1]["seed"] = 99

        with self.assertRaisesRegex(ValueError, "same seed/chair/config keys"):
            MODULE.paired_rate_difference(
                candidate, baseline, "chosen", "opportunities"
            )

    def test_paired_rate_difference_reports_pooled_rates_and_cluster_interval(self) -> None:
        candidate = self.metric_rows(successes=3, opportunities=4)
        baseline = self.metric_rows(successes=1, opportunities=4)

        result = MODULE.paired_rate_difference(
            candidate, baseline, "chosen", "opportunities"
        )

        self.assertEqual(result.candidate_successes, 12)
        self.assertEqual(result.candidate_opportunities, 16)
        self.assertEqual(result.baseline_successes, 4)
        self.assertEqual(result.baseline_opportunities, 16)
        self.assertAlmostEqual(result.difference, 0.5)
        self.assertAlmostEqual(result.lower, 0.5)
        self.assertAlmostEqual(result.upper, 0.5)

    def test_paired_rate_difference_refuses_an_arm_with_no_opportunities(self) -> None:
        candidate = self.metric_rows(successes=0, opportunities=0)
        baseline = self.metric_rows(successes=1, opportunities=4)

        with self.assertRaisesRegex(ValueError, "no opportunities"):
            MODULE.paired_rate_difference(
                candidate, baseline, "chosen", "opportunities"
            )

    @staticmethod
    def metric_rows(successes: int, opportunities: int) -> list[tuple[int, dict]]:
        rows: list[tuple[int, dict]] = []
        for seat in range(4):
            rows.append((seat, {
                "seed": 10,
                "behavior": [
                    {"chosen": successes, "opportunities": opportunities}
                    for _ in range(4)
                ],
            }))
        return rows


class PairedWinRateCLITests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_arm(
        self,
        name: str,
        build_id: str,
        evaluated_policy: str,
        foil_policy: str,
        winning_seats: set[int],
        moves: list[int],
        player_count: int = 4,
        schema_version: int = 5,
        victory_point_target: int = 10,
        board_mode: str = "randomized",
    ) -> list[Path]:
        paths: list[Path] = []
        for seat in range(player_count):
            winner = seat if seat in winning_seats else (seat + 1) % player_count
            row = paired_record(
                seat,
                build_id,
                evaluated_policy,
                foil_policy,
                winner,
                moves[seat],
                player_count,
                schema_version,
                victory_point_target,
                board_mode,
            )
            path = self.root / f"{name}-seat{seat}.jsonl"
            path.write_text(json.dumps(row) + "\n", encoding="utf-8")
            paths.append(path)
        return paths

    def run_paired(
        self,
        candidate_paths: list[Path],
        baseline_paths: list[Path],
        schema_version: Optional[int] = 5,
    ) -> subprocess.CompletedProcess[str]:
        command = [
            sys.executable,
            str(SCRIPT),
            "--name",
            "hard-v-standard",
        ]
        if schema_version is not None:
            command.extend(["--schema-version", str(schema_version)])
        command.extend([
            "--candidate-build-id",
            "candidate-build",
            "--candidate-policy",
            "candidate-v2",
            "--candidate-foil-policy",
            "candidate-anchor-v1",
            "--baseline-build-id",
            "baseline-build",
            "--baseline-policy",
            "baseline-v1",
            "--baseline-foil-policy",
            "baseline-anchor-v0",
            "--candidate-files",
            *(str(path) for path in candidate_paths),
            "--baseline-files",
            *(str(path) for path in baseline_paths),
        ])
        return subprocess.run(command, capture_output=True, text=True, check=False)

    def test_reports_paired_strength_across_independent_binaries(self) -> None:
        candidate = self.write_arm(
            "candidate",
            "candidate-build",
            "candidate-v2",
            "candidate-anchor-v1",
            {0, 1, 2},
            [80, 90, 100, 110],
        )
        baseline = self.write_arm(
            "baseline",
            "baseline-build",
            "baseline-v1",
            "baseline-anchor-v0",
            {0},
            [100, 110, 120, 130],
        )

        result = self.run_paired(candidate, baseline)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "| Candidate | `candidate-build` | `candidate-v2` | "
            "`candidate-anchor-v1` | 3/4 = 75.0% | 4/4 = 100.0% | 95 |",
            result.stdout,
        )
        self.assertIn(
            "| Baseline | `baseline-build` | `baseline-v1` | "
            "`baseline-anchor-v0` | 1/4 = 25.0% | 4/4 = 100.0% | 115 |",
            result.stdout,
        )
        self.assertIn(
            "- Paired win-rate difference: +50.0 percentage points",
            result.stdout,
        )
        self.assertIn(
            "- Seed-cluster bootstrap 95% CI: "
            "+50.0 to +50.0 percentage points",
            result.stdout,
        )

    def test_current_default_accepts_schema_five_evaluation_rows(self) -> None:
        candidate, baseline = self.valid_equal_arms()

        result = self.run_paired(candidate, baseline, schema_version=None)

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_explicit_schema_three_and_four_legacy_paired_analysis_still_works(self) -> None:
        for schema_version in (3, 4):
            with self.subTest(schema_version=schema_version):
                candidate = self.write_arm(
                    f"candidate-v{schema_version}",
                    "candidate-build",
                    "candidate-v2",
                    "candidate-anchor-v1",
                    {0, 1},
                    [80, 90, 100, 110],
                    schema_version=schema_version,
                )
                baseline = self.write_arm(
                    f"baseline-v{schema_version}",
                    "baseline-build",
                    "baseline-v1",
                    "baseline-anchor-v0",
                    {0},
                    [100, 110, 120, 130],
                    schema_version=schema_version,
                )

                result = self.run_paired(candidate, baseline, schema_version)

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("- Paired win-rate difference: +25.0", result.stdout)

    def test_reports_real_three_seat_paired_evaluation(self) -> None:
        candidate = self.write_arm(
            "candidate",
            "candidate-build",
            "candidate-v2",
            "candidate-anchor-v1",
            {0, 1},
            [80, 90, 100],
            player_count=3,
            victory_point_target=8,
            board_mode="standard",
        )
        baseline = self.write_arm(
            "baseline",
            "baseline-build",
            "baseline-v1",
            "baseline-anchor-v0",
            {0},
            [100, 110, 120],
            player_count=3,
            victory_point_target=8,
            board_mode="standard",
        )

        result = self.run_paired(candidate, baseline)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("- Games: 3 (1 seed/config cluster × 3 seat rotations)", result.stdout)
        self.assertIn(
            "| Candidate | `candidate-build` | `candidate-v2` | "
            "`candidate-anchor-v1` | 2/3 = 66.7% | 3/3 = 100.0% | 90 |",
            result.stdout,
        )
        self.assertIn(
            "| Baseline | `baseline-build` | `baseline-v1` | "
            "`baseline-anchor-v0` | 1/3 = 33.3% | 3/3 = 100.0% | 110 |",
            result.stdout,
        )
        self.assertIn(
            "- Paired win-rate difference: +33.3 percentage points",
            result.stdout,
        )
        self.assertIn(
            "- Seed-cluster bootstrap 95% CI: "
            "+33.3 to +33.3 percentage points",
            result.stdout,
        )

    def test_refuses_mismatched_configuration_keys(self) -> None:
        candidate = self.write_arm(
            "candidate",
            "candidate-build",
            "candidate-v2",
            "candidate-anchor-v1",
            {0, 1},
            [80, 90, 100, 110],
        )
        baseline = self.write_arm(
            "baseline",
            "baseline-build",
            "baseline-v1",
            "baseline-anchor-v0",
            {0, 1},
            [100, 110, 120, 130],
        )
        for path in baseline:
            changed = json.loads(path.read_text(encoding="utf-8"))
            changed["victoryPointTarget"] = 12
            path.write_text(json.dumps(changed) + "\n", encoding="utf-8")

        result = self.run_paired(candidate, baseline)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("same seed/chair/config keys", result.stderr)

    def test_refuses_three_seat_configuration_mismatch_before_output(self) -> None:
        candidate = self.write_arm(
            "candidate",
            "candidate-build",
            "candidate-v2",
            "candidate-anchor-v1",
            {0},
            [80, 90, 100],
            player_count=3,
            victory_point_target=8,
        )
        baseline = self.write_arm(
            "baseline",
            "baseline-build",
            "baseline-v1",
            "baseline-anchor-v0",
            {0},
            [100, 110, 120],
            player_count=3,
            victory_point_target=12,
        )

        result = self.run_paired(candidate, baseline)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("same seed/chair/config keys", result.stderr)

    def test_refuses_mismatched_seed_keys(self) -> None:
        candidate, baseline = self.valid_equal_arms()
        for path in baseline:
            changed = json.loads(path.read_text(encoding="utf-8"))
            changed["seed"] = 11
            path.write_text(json.dumps(changed) + "\n", encoding="utf-8")

        result = self.run_paired(candidate, baseline)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("same seed/chair/config keys", result.stderr)

    def test_reports_pooled_decisive_rates_when_one_arm_times_out(self) -> None:
        candidate = self.write_arm(
            "candidate",
            "candidate-build",
            "candidate-v2",
            "candidate-anchor-v1",
            {0, 1},
            [80, 90, 100, 3_000],
        )
        timed_out = json.loads(candidate[3].read_text(encoding="utf-8"))
        timed_out["winner"] = None
        candidate[3].write_text(json.dumps(timed_out) + "\n", encoding="utf-8")
        baseline = self.write_arm(
            "baseline",
            "baseline-build",
            "baseline-v1",
            "baseline-anchor-v0",
            {0},
            [100, 110, 120, 130],
        )

        result = self.run_paired(candidate, baseline)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("| 2/3 = 66.7% | 3/4 = 75.0% | 95 |", result.stdout)
        self.assertIn("| 1/4 = 25.0% | 4/4 = 100.0% | 115 |", result.stdout)
        self.assertIn(
            "- Paired win-rate difference: +41.7 percentage points",
            result.stdout,
        )

    def test_refuses_wrong_baseline_build_provenance(self) -> None:
        candidate, baseline = self.valid_equal_arms()
        changed = json.loads(baseline[1].read_text(encoding="utf-8"))
        changed["buildID"] = "candidate-build"
        baseline[1].write_text(json.dumps(changed) + "\n", encoding="utf-8")

        result = self.run_paired(candidate, baseline)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected schema 5/build 'baseline-build'", result.stderr)

    def test_refuses_wrong_baseline_evaluated_policy_provenance(self) -> None:
        candidate, baseline = self.valid_equal_arms()
        changed = json.loads(baseline[2].read_text(encoding="utf-8"))
        changed["policies"][2] = "candidate-v2"
        baseline[2].write_text(json.dumps(changed) + "\n", encoding="utf-8")

        result = self.run_paired(candidate, baseline)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected 'baseline-v1'", result.stderr)

    def test_refuses_wrong_baseline_foil_policy_provenance(self) -> None:
        candidate, baseline = self.valid_equal_arms()
        changed = json.loads(baseline[0].read_text(encoding="utf-8"))
        changed["policies"][1] = "candidate-anchor-v1"
        baseline[0].write_text(json.dumps(changed) + "\n", encoding="utf-8")

        result = self.run_paired(candidate, baseline)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected foil 'baseline-anchor-v0'", result.stderr)

    def test_bootstrap_resamples_whole_seed_clusters(self) -> None:
        candidate = self.write_arm(
            "candidate",
            "candidate-build",
            "candidate-v2",
            "candidate-anchor-v1",
            {0, 1, 2, 3},
            [80, 90, 100, 110],
        )
        baseline = self.write_arm(
            "baseline",
            "baseline-build",
            "baseline-v1",
            "baseline-anchor-v0",
            set(),
            [100, 110, 120, 130],
        )
        self.append_opposite_seed(candidate, baseline)

        result = self.run_paired(candidate, baseline)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "- Paired win-rate difference: +0.0 percentage points",
            result.stdout,
        )
        self.assertIn(
            "- Seed-cluster bootstrap 95% CI: "
            "-100.0 to +100.0 percentage points",
            result.stdout,
        )

    def append_opposite_seed(
        self,
        candidate_paths: list[Path],
        baseline_paths: list[Path],
    ) -> None:
        for seat in range(4):
            candidate = paired_record(
                seat,
                "candidate-build",
                "candidate-v2",
                "candidate-anchor-v1",
                (seat + 1) % 4,
                120 + seat * 10,
            )
            baseline = paired_record(
                seat,
                "baseline-build",
                "baseline-v1",
                "baseline-anchor-v0",
                seat,
                140 + seat * 10,
            )
            candidate["seed"] = 11
            baseline["seed"] = 11
            self.append_row(candidate_paths[seat], candidate)
            self.append_row(baseline_paths[seat], baseline)

    @staticmethod
    def append_row(path: Path, row: dict) -> None:
        contents = path.read_text(encoding="utf-8")
        path.write_text(contents + json.dumps(row) + "\n", encoding="utf-8")

    def valid_equal_arms(self) -> tuple[list[Path], list[Path]]:
        candidate = self.write_arm(
            "candidate",
            "candidate-build",
            "candidate-v2",
            "candidate-anchor-v1",
            {0, 1},
            [80, 90, 100, 110],
        )
        baseline = self.write_arm(
            "baseline",
            "baseline-build",
            "baseline-v1",
            "baseline-anchor-v0",
            {0, 1},
            [100, 110, 120, 130],
        )
        return candidate, baseline


if __name__ == "__main__":
    unittest.main()
