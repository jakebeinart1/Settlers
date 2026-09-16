#!/usr/bin/env python3

import json
import subprocess
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
        # Seed 1's trajectory, pinned a second time on this side of the fence:
        # the Swift `SeededGameFingerprintTests` proves the game is
        # reproducible, and this proves the CLI's defaults still select the
        # configuration those traces were recorded under. Re-record BOTH
        # together - this value drifting alone means the defaults moved, which
        # is the whole point of the check. Last changed 2026-09-08, when bots
        # stopped scoring opponents on hidden victory-point cards.
        self.assertEqual(json.loads(implicit.stdout)["fingerprint"], "3994f514fb48cde2")

    def test_joint_trade_candidate_is_explicit_and_cross_process_reproducible(self) -> None:
        for players in (3, 4):
            arguments = (
                "--players", str(players), "--victory-points", "10",
                "--board", "randomized", "--seed", "879900", "--games", "1",
                "--seats", ",".join(["joint-balanced"] + ["balanced"] * (players - 1)),
                "--build-id", "candidate-cli-test", "--jsonl",
            )
            first = self.run_simulator(*arguments)
            second = self.run_simulator(*arguments)
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(first.stdout, second.stdout)
            record = json.loads(first.stdout)
            self.assertEqual(record["policies"][0], "experimental-joint-balanced-v1")
            self.assertIn(record["winner"], range(players))


if __name__ == "__main__":
    unittest.main()
