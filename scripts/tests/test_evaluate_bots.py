"""Public config/CLI checks for the repeatable evaluation entry point."""

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location(
    "evaluate_bots", SCRIPTS / "evaluate-bots.py"
)
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
DEFAULT = SCRIPTS.parent / "config/evaluation/neural-r2-smoke.json"


class EvaluationRunnerTests(unittest.TestCase):
    def test_real_pipeline_repeats_across_processes_with_complete_artifacts(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = json.loads(DEFAULT.read_text()) | {
                "players": 3,
                "seeds": 2,
                "budget_seconds": 180,
            }
            configuration = root / "small.json"
            configuration.write_text(json.dumps(config))
            outputs = [root / "first", root / "second"]
            for output in outputs:
                result = subprocess.run(
                    [
                        sys.executable,
                        str(SCRIPTS / "evaluate-bots.py"),
                        "--config",
                        str(configuration),
                        "--output",
                        str(output),
                    ],
                    capture_output=True,
                    text=True,
                    timeout=200,
                    check=False,
                )
                log = output / "run.launcher.log"
                self.assertEqual(
                    result.returncode,
                    0,
                    result.stderr + (log.read_text() if log.exists() else ""),
                )
                receipt = json.loads((output / "run.watchdog.json").read_text())
                self.assertEqual(receipt["state"], "complete")
                self.assertEqual(receipt["exit_code"], 0)
                complete = json.loads((output / "complete.json").read_text())
                self.assertEqual(complete["games"], 12)
                self.assertFalse(complete["strength_claim"])
                manifest = json.loads((output / "manifest.json").read_text())
                self.assertTrue(
                    any(name.endswith("final.ctnn") for name in manifest["artifacts"])
                )
                for name, digest in manifest["artifacts"].items():
                    self.assertEqual(runner.digest(output / name), digest)
                self.assertIn(
                    "not a strength claim", (output / "report.md").read_text()
                )
            shards = [
                outputs[0] / f"{arm}-seat{seat}{suffix}"
                for arm in ("candidate", "baseline")
                for seat in range(3)
                for suffix in (".jsonl", ".audit.jsonl")
            ]
            self.assertEqual(len(shards), 12)
            for first in shards:
                self.assertEqual(
                    first.read_bytes(), (outputs[1] / first.name).read_bytes()
                )

    def test_config_rejects_ambiguous_or_unbounded_inputs(self) -> None:
        invalid = (
            {"seeds": True},
            {"seeds": 1},
            {"first_seed": -1},
            {"first_seed": 2**64 - 1},
            {"budget_seconds": 0},
            {"budget_seconds": 10801},
            {"budget_seconds": float("inf")},
            {"players": 2},
            {"victory_points": 9},
            {"purpose": "promotion"},
            {"board": "custom"},
            {"candidate": "bad/name"},
            {"typo": "value"},
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.json"
            for change in invalid:
                with self.subTest(change=change):
                    path.write_text(
                        json.dumps(json.loads(DEFAULT.read_text()) | change)
                    )
                    with self.assertRaises(ValueError):
                        runner.read_config(path)
            path.write_text(DEFAULT.read_text())
            self.assertEqual(runner.read_config(path)["candidate"], "neural-r2")
            path.write_text('{"budget_seconds": 1, "budget_seconds": 600}')
            with self.assertRaisesRegex(ValueError, "duplicate"):
                runner.read_config(path)

    def test_existing_output_is_never_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "saved-evidence"
            marker.write_text("preserve me")
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPTS / "evaluate-bots.py"),
                    "--config",
                    str(DEFAULT),
                    "--output",
                    directory,
                ],
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(marker.read_text(), "preserve me")
            self.assertEqual(
                sorted(path.name for path in Path(directory).iterdir()),
                ["saved-evidence"],
            )

    def test_wrong_seeds_configuration_and_capped_games_fail_loudly(self) -> None:
        config = runner.read_config(DEFAULT)
        rows = [
            {
                "seed": config["first_seed"] + index,
                "playerCount": config["players"],
                "victoryPointTarget": config["victory_points"],
                "boardMode": config["board"],
                "winner": 0,
            }
            for index in range(config["seeds"])
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "candidate-seat0.jsonl"
            cases = [
                rows[:-1],
                [rows[0]] * len(rows),
                [row | {"playerCount": 7 - config["players"]} for row in rows],
                [row | {"winner": None} for row in rows],
            ]
            for changed in cases:
                path.write_text("\n".join(json.dumps(row) for row in changed))
                with self.assertRaises(ValueError):
                    runner.validate_shard(path, config)
                self.assertTrue(path.exists(), "failed evidence must be retained")
            path.write_text("\n".join(json.dumps(row) for row in rows))
            runner.validate_shard(path, config)

    def test_command_failure_retains_raw_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            shard = output / "failed.jsonl"
            with self.assertRaises(subprocess.CalledProcessError):
                runner.execute(
                    [sys.executable, "-c", "print('partial'); raise SystemExit(7)"],
                    output,
                    shard,
                )
            self.assertEqual(shard.read_text(), "partial\n")
            self.assertTrue((output / "commands.jsonl").exists())

    def test_unexpected_fallbacks_and_missing_audits_fail(self) -> None:
        neural_id = "neural-test"
        valid = {
            "policyID": neural_id,
            "evaluations": 3,
            "sources": {"neural": 2, "heuristic": 1},
            "fallbackReasons": {"player_trade_negotiation": 1},
        }
        invalid = (
            valid | {"fallbackReasons": {"observation_encoding_failure": 1}},
            valid | {"fallbackReasons": {}},
            valid | {"sources": {"untraced": 3}},
            valid | {"sources": {"heuristic": 3}},
            valid | {"evaluations": True},
            valid | {"policyID": "wrong-model"},
        )
        self.assertEqual(runner.validate_seat_audit(valid, neural_id, neural_id), 3)
        for seat in invalid:
            with self.subTest(seat=seat), self.assertRaises(ValueError):
                runner.validate_seat_audit(seat, neural_id, neural_id)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "game.jsonl").write_text(json.dumps({"seed": 1}))
            (root / "audit.jsonl").write_text("")
            with self.assertRaises(ValueError):
                runner.validate_audit(
                    root / "audit.jsonl", root / "game.jsonl", neural_id
                )

    def test_pipeline_failures_retain_inputs_without_success_receipt(self) -> None:
        cases = (
            ({"candidate": "not-a-policy", "budget_seconds": 180}, "failed"),
            ({"seeds": 1000, "budget_seconds": 1}, "timed_out"),
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for changes, expected_state in cases:
                output = root / expected_state
                config = root / f"{expected_state}.json"
                config.write_text(json.dumps(json.loads(DEFAULT.read_text()) | changes))
                result = subprocess.run(
                    [
                        sys.executable,
                        str(SCRIPTS / "evaluate-bots.py"),
                        "--config",
                        str(config),
                        "--output",
                        str(output),
                    ],
                    capture_output=True,
                    text=True,
                    timeout=200,
                    check=False,
                )
                self.assertNotEqual(result.returncode, 0, result.stdout)
                receipt = json.loads((output / "run.watchdog.json").read_text())
                if expected_state == "timed_out":
                    self.assertEqual(receipt["exit_code"], 124, receipt)
                    self.assertIn(receipt["state"], ("timed_out", "failed"), receipt)
                    if receipt["state"] == "failed":
                        # A denied cleanup is deliberately more severe than a
                        # clean timeout. The watchdog must never hide it as PASS.
                        self.assertIn("cleanup_error", receipt)
                else:
                    self.assertEqual(receipt["state"], expected_state, receipt)
                self.assertTrue((output / "inputs.json").exists())
                inputs = json.loads((output / "inputs.json").read_text())
                self.assertIn(
                    "Packages/CatanAI/Sources/sim/main.swift", inputs["source_files"]
                )
                self.assertFalse((output / "complete.json").exists())


if __name__ == "__main__":
    unittest.main()
