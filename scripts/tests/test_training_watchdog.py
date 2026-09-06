"""Exercise real bounded subprocesses and machine-generated UTC deadlines."""

import importlib
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
watchdog = importlib.import_module("training_watchdog")


class TrainingWatchdogTests(unittest.TestCase):
    def test_deadline_comes_from_epoch_not_local_run_directory(self):
        deadline = watchdog.Deadline(10800, 1788661944.1607244, 100)
        self.assertEqual(
            deadline.record()["started_utc"], "2026-09-06T02:32:24.160724+00:00"
        )
        self.assertEqual(
            deadline.record()["deadline_utc"], "2026-09-06T05:32:24.160724+00:00"
        )
        self.assertGreater(deadline.remaining(1788664552.8, 2708.7), 0)

    def test_either_clock_can_expire_budget(self):
        deadline = watchdog.Deadline(10, 1000, 100)
        self.assertLessEqual(deadline.remaining(1011, 101), 0)
        self.assertLessEqual(deadline.remaining(900, 111), 0)
        self.assertEqual(deadline.remaining(1005, 105), 5)

    def test_budgets_reject_unbounded_values(self):
        for seconds in (0, -1, float("nan"), float("inf"), 10801):
            with self.subTest(seconds=seconds), self.assertRaises(ValueError):
                watchdog.Deadline(seconds, 1000, 100)

    def test_success_and_failure_are_distinct(self):
        for code in (0, 7):
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "job"
                result = watchdog.run(
                    [sys.executable, "-c", f"raise SystemExit({code})"], output, 5
                )
                state = json.loads(watchdog.receipt_path(output).read_text())
                self.assertEqual(result, code)
                self.assertEqual(state["state"], "complete" if code == 0 else "failed")
                self.assertEqual(state["exit_code"], code)

    def test_existing_receipt_cannot_launch_duplicate(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "job"
            watchdog.receipt_path(output).write_text("existing")
            with self.assertRaises(FileExistsError):
                watchdog.run([sys.executable, "-c", "pass"], output, 1)

    def test_cleanup_failure_cannot_record_completion(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "job"
            with (
                patch.object(
                    watchdog,
                    "terminate_group",
                    side_effect=RuntimeError("cleanup failed"),
                ),
                self.assertRaises(RuntimeError),
            ):
                watchdog.run([sys.executable, "-c", "pass"], output, 5)
            state = json.loads(watchdog.receipt_path(output).read_text())
            self.assertEqual(state["state"], "failed")
            self.assertIn("cleanup failed", state["cleanup_error"])

    @unittest.skipUnless(os.name == "posix", "process-group contract is POSIX")
    def test_timeout_kills_child_even_when_parent_exits_on_term(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "job"
            marker = Path(directory) / "escaped.txt"
            ready = Path(directory) / "ready.txt"
            child = (
                "import signal,time,pathlib; signal.signal(signal.SIGTERM,signal.SIG_IGN); "
                f"pathlib.Path({str(ready)!r}).write_text('ready'); "
                f"time.sleep(1.5); pathlib.Path({str(marker)!r}).write_text('escaped')"
            )
            parent = f"import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',{child!r}]); time.sleep(10)"
            result = watchdog.run(
                [sys.executable, "-c", parent], output, 0.3, grace_seconds=0.1
            )
            self.assertEqual(result, 124)
            self.assertTrue(
                ready.exists(), "test never armed the SIGTERM-ignore handler"
            )
            self.assertEqual(
                json.loads(watchdog.receipt_path(output).read_text())["state"],
                "timed_out",
            )
            time.sleep(1.6)
            self.assertFalse(marker.exists(), "descendant survived the job deadline")

    def test_dead_guardian_is_not_reported_running(self):
        state = {
            "boot_identity": "boot",
            "watchdog_pid": 123,
            "watchdog_identity": "456",
            "checked_epoch": time.time(),
        }
        with (
            patch.object(watchdog, "boot_identity", return_value="boot"),
            patch.object(watchdog, "process_identity", return_value=None),
        ):
            self.assertEqual(
                watchdog.supervision_health(state), "guardian_missing_or_replaced"
            )
        with patch.object(watchdog, "boot_identity", return_value="new-boot"):
            self.assertEqual(watchdog.supervision_health(state), "host_rebooted")

    def test_repeated_term_cannot_skip_forced_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "job"
            ready = Path(directory) / "ready"
            ticks = Path(directory) / "ticks"
            child = (
                "import signal,time,pathlib; signal.signal(signal.SIGTERM,signal.SIG_IGN); "
                f"pathlib.Path({str(ready)!r}).write_text('ready'); "
                f"[(pathlib.Path({str(ticks)!r}).write_text(str(i)),time.sleep(0.05)) for i in range(300)]"
            )
            command = [
                sys.executable,
                str(Path(watchdog.__file__)),
                "run",
                "--output",
                str(output),
                "--seconds",
                "15",
                "--",
                sys.executable,
                "-c",
                child,
            ]
            with subprocess.Popen(
                command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            ) as guardian:
                limit = time.monotonic() + 3
                while (
                    not ready.exists()
                    and guardian.poll() is None
                    and time.monotonic() < limit
                ):
                    time.sleep(0.02)
                self.assertTrue(ready.exists(), "child did not become ready")
                guardian.send_signal(signal.SIGTERM)
                time.sleep(0.2)
                guardian.send_signal(signal.SIGTERM)
                self.assertNotEqual(guardian.wait(timeout=7), 0)
            before = ticks.read_text()
            time.sleep(0.2)
            self.assertEqual(
                ticks.read_text(), before, "child escaped interrupted cleanup"
            )
            self.assertEqual(
                json.loads(watchdog.receipt_path(output).read_text())["state"], "failed"
            )


if __name__ == "__main__":
    unittest.main()
