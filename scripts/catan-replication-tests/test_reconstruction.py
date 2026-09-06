"""Bounded orchestration tests, run inside the isolated upstream environment."""

import argparse
import importlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

supervisor = importlib.import_module("run-catan-reconstruction")


class ReconstructionTests(unittest.TestCase):
    def test_fresh_stage_never_resumes_a_published_or_smoke_model(self) -> None:
        command = supervisor.command_for_stage("fresh", 50, "cuda", "")
        self.assertNotIn("--resume", command)
        self.assertEqual(command[command.index("--vp-delta") + 1], "0.05")
        self.assertEqual(command[command.index("--vp-delta-final") + 1], "0")
        self.assertEqual(command[command.index("--device") + 1], "cuda")
        self.assertIn("np.random.seed(0)", command[3])

    def test_continuation_uses_exact_parent_and_removes_shaping(self) -> None:
        command = supervisor.command_for_stage("second", 60, "cuda", "/run/final.pt")
        self.assertEqual(command[command.index("--resume") + 1], "/run/final.pt")
        self.assertEqual(command[command.index("--vp-delta") + 1], "0")
        self.assertNotIn("--vp-delta-final", command)
        self.assertNotIn("resume", supervisor.TRAINING_FLAGS)

    def test_budgets_are_finite_positive_and_bounded(self) -> None:
        for invalid in ("0", "-1", "nan", "inf", "61"):
            with (
                self.subTest(invalid=invalid),
                self.assertRaises(argparse.ArgumentTypeError),
            ):
                supervisor.positive_minutes(invalid)
        self.assertEqual(supervisor.positive_minutes("50"), 50)

    def test_failure_is_recorded_and_propagated(self) -> None:
        args = argparse.Namespace(
            device="cuda", fresh_minutes=50, continuation_minutes=60
        )
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            with (
                patch.object(
                    supervisor, "train_stage", side_effect=RuntimeError("broken")
                ),
                patch.object(supervisor.signal, "signal"),
                self.assertRaisesRegex(RuntimeError, "broken"),
            ):
                supervisor.execute(args, output, output, output / "sim")
            status = json.loads((output / "status.json").read_text())
            self.assertEqual(status["phase"], "failed")
            self.assertIn("broken", status["error"])
            self.assertNotIn("training_reproduction_verdict", status)

    def test_logged_command_failure_is_not_success(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(subprocess.CalledProcessError):
                supervisor.run_logged(
                    [sys.executable, "-c", "raise SystemExit(9)"],
                    root,
                    root / "failure.log",
                    5,
                )

    def test_logged_command_timeout_propagates(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(subprocess.TimeoutExpired):
                supervisor.run_logged(
                    [sys.executable, "-c", "import time; time.sleep(5)"],
                    root,
                    root / "timeout.log",
                    0.05,
                )

    def test_signal_handler_does_not_silently_finish(self) -> None:
        with self.assertRaises(InterruptedError):
            supervisor.terminate_job(15, None)

    def test_native_game_must_reach_a_winner(self) -> None:
        valid = {"t": "game", "winner": 2, "cap": False, "steps": 400}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "metrics.jsonl"
            path.write_text(json.dumps(valid) + "\n")
            self.assertEqual(supervisor.completed_native_game(path), valid)
            for rows in (
                [],
                [valid, valid],
                [dict(valid, winner=-1)],
                [dict(valid, cap=True)],
                [dict(valid, steps=0)],
            ):
                with self.subTest(rows=rows), self.assertRaises(ValueError):
                    path.write_text("\n".join(json.dumps(row) for row in rows))
                    supervisor.completed_native_game(path)


if __name__ == "__main__":
    unittest.main()
