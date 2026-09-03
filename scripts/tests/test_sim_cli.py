#!/usr/bin/env python3

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).parents[2]
PACKAGE = REPO_ROOT / "Packages" / "CatanAI"


class SimulatorConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        subprocess.run(
            [
                "swift", "build", "--package-path", str(PACKAGE),
                "--configuration", "release", "--product", "sim",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        result = subprocess.run(
            [
                "swift", "build", "--package-path", str(PACKAGE),
                "--configuration", "release", "--show-bin-path",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.simulator = Path(result.stdout.strip()) / "sim"

    def run_simulator(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(self.simulator), *arguments],
            check=False,
            capture_output=True,
            text=True,
            timeout=120,
        )

    def test_three_player_standard_eight_point_game_reports_its_configuration(self) -> None:
        result = self.run_simulator(
            "--players", "3",
            "--victory-points", "8",
            "--board", "standard",
            "--seats", "balanced,aggressive,cautious",
            "--build-id", "integration-test",
            "--seed", "701",
            "--games", "1",
            "--jsonl",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(len(lines), 1)
        record = json.loads(lines[0])
        self.assertEqual(set(record), {
            "schemaVersion", "buildID", "playerCount", "victoryPointTarget",
            "boardMode", "policies", "seed", "moves", "winner", "vp",
            "fingerprint", "behavior",
        })
        self.assertEqual(record["schemaVersion"], 5)
        self.assertEqual(record["buildID"], "integration-test")
        self.assertEqual(record["playerCount"], 3)
        self.assertEqual(record["victoryPointTarget"], 8)
        self.assertEqual(record["boardMode"], "standard")
        self.assertEqual(len(record["policies"]), 3)
        self.assertEqual(len(record["vp"]), 3)
        self.assertEqual(len(record["behavior"]), 3)
        self.assertIn(record["winner"], range(3))
        self.assertGreaterEqual(record["vp"][record["winner"]], 8)

    def test_difficulty_and_personality_are_independent_seat_names(self) -> None:
        result = self.run_simulator(
            "--players", "3",
            "--victory-points", "8",
            "--board", "randomized",
            "--seats", "easy-balanced,standard-aggressive,easy-cautious",
            "--build-id", "difficulty-integration",
            "--seed", "703",
            "--games", "1",
            "--jsonl",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads(result.stdout)
        self.assertEqual(record["policies"], [
            "easy-balanced", "standard-aggressive", "easy-cautious",
        ])
        self.assertIn(record["winner"], range(3))

    def test_configuration_flags_reject_unsupported_duplicate_and_wrapping_values(self) -> None:
        cases = (
            (("--players", "2"), "--players must be 3 or 4"),
            (("--victory-points", "9"), "--victory-points must be 8, 10 or 12"),
            (("--board", "custom"), "--board must be standard or randomized"),
            (("--players", "3", "--players", "4"), "--players may be supplied only once"),
            (
                ("--seed", str(2**64 - 1), "--games", "2"),
                "seed range overflows UInt64",
            ),
        )

        for arguments, message in cases:
            with self.subTest(arguments=arguments):
                result = self.run_simulator(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertIn(message, result.stderr)

    def test_three_player_training_examples_carry_the_same_configuration(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            training_path = Path(directory) / "training.jsonl"
            result = self.run_simulator(
                "--players", "3",
                "--victory-points", "12",
                "--board", "randomized",
                "--seats", "balanced,aggressive,cautious",
                "--build-id", "training-config-test",
                "--training-information", "public-counts",
                "--training-jsonl", str(training_path),
                "--seed", "702",
                "--games", "1",
                "--jsonl",
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            examples = [
                json.loads(line)
                for line in training_path.read_text(encoding="utf-8").splitlines()
            ]
            validation = subprocess.run(
                [
                    "python3", str(REPO_ROOT / "scripts" / "validate-training-data.py"),
                    "--build-id", "training-config-test",
                    "--information-policy", "publicCountsOnly",
                    str(training_path),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(validation.returncode, 0, validation.stderr)
        self.assertGreater(len(examples), 0)
        for example in examples:
            self.assertEqual(example["schemaVersion"], 2)
            self.assertEqual(example["playerCount"], 3)
            self.assertEqual(example["victoryPointTarget"], 12)
            self.assertEqual(example["boardMode"], "randomized")
            self.assertEqual(example["actionCount"], 9_295)
            self.assertIn(example["observerSeat"], range(3))
            self.assertIn(example["winnerSeat"], range(3))
            self.assertLess(example["chosenActionIndex"], example["actionCount"])

    def test_every_supported_configuration_runs_to_a_decisive_game(self) -> None:
        fingerprints: dict[tuple[int, int, str], str] = {}
        for players in (3, 4):
            for target in (8, 10, 12):
                seed = 720 + players * 10 + target
                for board_mode in ("standard", "randomized"):
                    with self.subTest(
                        players=players,
                        victory_points=target,
                        board=board_mode,
                    ):
                        result = self.run_simulator(
                            "--players", str(players),
                            "--victory-points", str(target),
                            "--board", board_mode,
                            "--build-id", "configuration-matrix",
                            "--seed", str(seed),
                            "--games", "1",
                            "--jsonl",
                        )
                        self.assertEqual(result.returncode, 0, result.stderr)
                        record = json.loads(result.stdout)
                        self.assertEqual(record["schemaVersion"], 5)
                        self.assertEqual(record["playerCount"], players)
                        self.assertEqual(record["victoryPointTarget"], target)
                        self.assertEqual(record["boardMode"], board_mode)
                        self.assertEqual(len(record["policies"]), players)
                        self.assertEqual(len(record["vp"]), players)
                        self.assertEqual(len(record["behavior"]), players)
                        self.assertIn(record["winner"], range(players))
                        self.assertGreaterEqual(record["vp"][record["winner"]], target)
                        self.assertLess(record["moves"], 3_000)
                        fingerprints[(players, target, board_mode)] = record["fingerprint"]

        for players in (3, 4):
            for target in (8, 10, 12):
                self.assertNotEqual(
                    fingerprints[(players, target, "standard")],
                    fingerprints[(players, target, "randomized")],
                )

    def test_default_run_matches_the_explicit_historical_configuration(self) -> None:
        shared = ("--seed", "1", "--games", "1", "--jsonl")
        implicit = self.run_simulator(*shared)
        explicit = self.run_simulator(
            *shared,
            "--players", "4",
            "--victory-points", "10",
            "--board", "randomized",
        )

        self.assertEqual(implicit.returncode, 0, implicit.stderr)
        self.assertEqual(explicit.returncode, 0, explicit.stderr)
        self.assertEqual(implicit.stdout, explicit.stdout)
        self.assertEqual(json.loads(implicit.stdout)["fingerprint"], "d7fdc2d2721c1585")


if __name__ == "__main__":
    unittest.main()
