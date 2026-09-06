#!/usr/bin/env python3

import json
import resource
import signal
import subprocess
import tempfile
import unittest
from collections import Counter
from pathlib import Path
from typing import Optional


REPO_ROOT = Path(__file__).parents[2]
PACKAGE = REPO_ROOT / "Packages" / "CatanAI"
NEURAL_POLICY_ID = (
    "upstream-r2-hybrid-greedy-swift-compounds-trade-scheduler-"
    "fallback-heuristic-balanced"
)


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
            timeout=300,
        )
        result = subprocess.run(
            [
                "swift", "build", "--package-path", str(PACKAGE),
                "--configuration", "release", "--show-bin-path",
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )
        cls.simulator = Path(result.stdout.strip()) / "sim"

    def run_simulator(
        self, *arguments: str, file_size_limit: Optional[int] = None
    ) -> subprocess.CompletedProcess[str]:
        def limit_output_file_size() -> None:
            # Affect only this child: turn a full audit file into a checked
            # write error rather than killing the test runner or the process.
            assert file_size_limit is not None
            signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
            resource.setrlimit(resource.RLIMIT_FSIZE, (file_size_limit, file_size_limit))

        return subprocess.run(
            [str(self.simulator), *arguments],
            check=False,
            capture_output=True,
            text=True,
            timeout=120,
            preexec_fn=limit_output_file_size if file_size_limit is not None else None,
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
            (("--policy-audit-jsonl", ""), "--policy-audit-jsonl path cannot be empty"),
            (
                ("--policy-audit-jsonl", "one", "--policy-audit-jsonl", "two"),
                "--policy-audit-jsonl may be supplied only once",
            ),
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

    def test_policy_registry_is_standalone_and_deterministic(self) -> None:
        result = self.run_simulator("--list-policies")
        repeated = self.run_simulator("--list-policies")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(repeated.returncode, 0, repeated.stderr)
        self.assertEqual(result.stdout, repeated.stdout)
        self.assertEqual(result.stderr, "")
        registry = json.loads(result.stdout)
        self.assertEqual(registry, {
            "balanced": "heuristic-balanced",
            "aggressive": "heuristic-aggressive",
            "cautious": "heuristic-cautious",
            "greedy": "greedy",
            "random": "random",
            "neural-r2": NEURAL_POLICY_ID,
        })
        self.assertEqual(list(registry), sorted(registry))
        combined = self.run_simulator("--list-policies", "--jsonl")
        self.assertEqual(combined.returncode, 2)
        self.assertEqual(combined.stdout, "")
        self.assertIn("--list-policies must be used alone", combined.stderr)

    def test_neural_seats_complete_a_reproducible_game_with_real_policy_ids(self) -> None:
        arguments = (
            "--players", "3", "--victory-points", "8", "--board", "standard",
            "--seed", "101", "--games", "1", "--jsonl",
        )
        seats = "neural-r2,balanced,neural-r2"
        result = self.run_simulator(*arguments, "--seats", seats)
        repeated = self.run_simulator(*arguments, "--seats", seats)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(repeated.returncode, 0, repeated.stderr)
        self.assertEqual(result.stdout, repeated.stdout)
        record = json.loads(result.stdout)
        self.assertEqual(record["schemaVersion"], 5)
        self.assertEqual(record["policies"], [
            NEURAL_POLICY_ID, "heuristic-balanced", NEURAL_POLICY_ID,
        ])
        self.assertIn(record["winner"], range(3))
        self.assertGreaterEqual(record["vp"][record["winner"]], 8)
        self.assertGreater(record["moves"], 0)
        self.assertLess(record["moves"], 3_000)
        heuristic = self.run_simulator(*arguments, "--seats", "balanced,balanced,balanced")
        self.assertEqual(heuristic.returncode, 0, heuristic.stderr)
        self.assertEqual(set(record), set(json.loads(heuristic.stdout)))
        self.assertNotEqual(
            record["fingerprint"], json.loads(heuristic.stdout)["fingerprint"]
        )

    def test_unknown_policy_names_fail_before_game_output(self) -> None:
        result = self.run_simulator(
            "--players", "3", "--seats", "neural-r3,balanced,balanced", "--jsonl"
        )
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("unknown seat 'neural-r3'", result.stderr)

    def test_policy_audit_counts_all_neural_and_consulted_trade_routes(self) -> None:
        arguments = (
            "--players", "3", "--victory-points", "8", "--board", "standard",
            "--seats", "neural-r2,balanced,neural-r2",
            "--seed", "101", "--games", "2", "--jsonl", "--build-id", "audit-test",
        )
        with tempfile.TemporaryDirectory() as directory:
            audit_path = Path(directory) / "audit.jsonl"
            training_path = Path(directory) / "training.jsonl"
            result = self.run_simulator(
                *arguments, "--policy-audit-jsonl", str(audit_path),
                "--training-jsonl", str(training_path),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            audits = [json.loads(line) for line in audit_path.read_text().splitlines()]
            examples = [json.loads(line) for line in training_path.read_text().splitlines()]
        plain = self.run_simulator(*arguments)
        self.assertEqual(plain.returncode, 0, plain.stderr)
        self.assertEqual(result.stdout, plain.stdout)
        records = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual([audit["seed"] for audit in audits], [101, 102])
        for audit, record in zip(audits, records):
            decisions = [row for row in examples if row["seed"] == audit["seed"]]
            self.assert_audit_matches_decisions(audit, record, decisions)

    def assert_audit_matches_decisions(
        self, audit: dict, record: dict, decisions: list[dict]
    ) -> None:
        self.assertEqual(set(audit), {"schemaVersion", "seed", "evaluationCount", "seats"})
        self.assertEqual(audit["schemaVersion"], 1)
        self.assertEqual(audit["evaluationCount"], len(decisions))
        self.assertGreater(audit["evaluationCount"], record["moves"])
        self.assertEqual(
            sorted(row["decisionIndex"] for row in decisions), list(range(len(decisions)))
        )
        self.assertEqual([seat["policyID"] for seat in audit["seats"]], record["policies"])
        evaluated_seats = Counter(row["observerSeat"] for row in decisions)
        reasons: Counter[str] = Counter()
        for index, seat in enumerate(audit["seats"]):
            self.assertEqual(seat["evaluations"], evaluated_seats[index])
            self.assertEqual(sum(seat["sources"].values()), seat["evaluations"])
            if seat["policyID"] == NEURAL_POLICY_ID:
                self.assertGreater(seat["sources"].get("neural", 0), 0)
                self.assertEqual(set(seat["sources"]), {"neural", "heuristic"})
                self.assertEqual(
                    sum(seat["fallbackReasons"].values()), seat["sources"]["heuristic"]
                )
                reasons.update(seat["fallbackReasons"])
            else:
                self.assertEqual(seat["sources"], {"policy": seat["evaluations"]})
                self.assertEqual(seat["fallbackReasons"], {})
        self.assertGreater(reasons["player_trade_negotiation"], 0)
        self.assertGreater(reasons["heuristic_trade_proposal"], 0)
        self.assertLessEqual(set(reasons), {
            "player_trade_negotiation", "heuristic_trade_proposal",
            "unsupported_pre_roll_development_card",
        })

    def test_policy_audit_refuses_existing_paths_without_overwriting(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            audit_path = Path(directory) / "audit.jsonl"
            audit_path.write_text("existing evidence\n", encoding="utf-8")
            result = self.run_simulator("--policy-audit-jsonl", str(audit_path))
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, "")
            self.assertIn("existing paths are refused", result.stderr)
            self.assertEqual(audit_path.read_text(), "existing evidence\n")

    def test_policy_audit_retains_completed_rows_when_a_later_write_fails(self) -> None:
        arguments = ("--seed", "1", "--jsonl")
        with tempfile.TemporaryDirectory() as directory:
            first_path = Path(directory) / "first.jsonl"
            first = self.run_simulator(
                *arguments, "--policy-audit-jsonl", str(first_path)
            )
            self.assertEqual(first.returncode, 0, first.stderr)
            first_row = first_path.read_bytes()
            partial_path = Path(directory) / "partial.jsonl"
            failed = self.run_simulator(
                *arguments, "--games", "2", "--policy-audit-jsonl", str(partial_path),
                file_size_limit=len(first_row),
            )
            self.assertEqual(failed.returncode, 2, failed.stderr)
            self.assertIn("cannot write policy audit", failed.stderr)
            self.assertEqual(failed.stdout, first.stdout)
            self.assertEqual(partial_path.read_bytes(), first_row)

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
            self.assertEqual(example["actionCount"], 9_335)
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
        self.assertEqual(json.loads(implicit.stdout)["fingerprint"], "7964368a77394abc")


if __name__ == "__main__":
    unittest.main()
