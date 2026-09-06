"""Profiling orchestration guards; isolated Torch environment, no GPU launches."""

import argparse
import fcntl
import importlib
import json
import os
import pstats
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

supervisor = importlib.import_module("profile-catan-training")
profiler = importlib.import_module("profile_catan_worker")


class ProfileTrainingTests(unittest.TestCase):
    def arguments(self, root: Path) -> list[str]:
        return [
            "--source",
            str(root),
            "--output",
            str(root / "output"),
            "--parent",
            str(root / "parent.pt"),
            "--parent-sha256",
            "a" * 64,
            "--binding-sha256",
            "b" * 64,
            "--mode",
            "cprofile",
            "--device",
            "cpu",
        ]

    def test_arguments_require_hashes_and_bound_inner_budget(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = self.arguments(Path(directory).resolve())
            self.assertEqual(supervisor.parse_options(arguments).seconds, 60)
            for value in ("0", "-1", "nan", "inf", "121"):
                with self.subTest(value=value), self.assertRaises(SystemExit):
                    supervisor.parse_options([*arguments, "--seconds", value])
            self.assertEqual(
                supervisor.parse_options([*arguments, "--seconds", "120"]).seconds, 120
            )
        for value in ("", "a" * 63, "A" * 64, "g" * 64):
            with (
                self.subTest(value=value),
                self.assertRaises(argparse.ArgumentTypeError),
            ):
                supervisor.sha256_argument(value)

    def test_cuda_requires_explicit_lock_but_cpu_does_not(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            arguments = self.arguments(root)
            self.assertIsNone(supervisor.parse_options(arguments).gpu_lock)
            with self.assertRaises(SystemExit):
                supervisor.parse_options([*arguments, "--device", "cuda"])
            options = supervisor.parse_options(
                [*arguments, "--device", "cuda", "--gpu-lock", str(root / "gpu.lock")]
            )
            self.assertEqual(options.gpu_lock, root / "gpu.lock")

    def test_prepare_reuses_continuation_flags_and_retains_provenance(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            options = supervisor.parse_options(
                [
                    *self.arguments(root),
                    "--device",
                    "cuda",
                    "--gpu-lock",
                    str(root / "gpu.lock"),
                ]
            )
            options.output.mkdir()
            options.parent.write_bytes(b"trusted parent")
            options.parent_sha256 = profiler.reconstruction.digest(options.parent)
            with (
                patch.object(
                    profiler.reconstruction.replay,
                    "check_inputs",
                    return_value=(root / "oracle", root / "binding"),
                ) as check,
                patch.object(
                    profiler.reconstruction.replay,
                    "provenance",
                    return_value={"verified": True},
                ) as provenance,
                patch.object(
                    profiler.reconstruction,
                    "command_for_stage",
                    wraps=profiler.reconstruction.command_for_stage,
                ) as command_for_stage,
                patch.object(
                    profiler.reconstruction.torch.cuda,
                    "is_available",
                    return_value=True,
                ),
                patch.object(
                    profiler.reconstruction.torch.cuda,
                    "get_device_name",
                    return_value="Test GPU",
                ),
            ):
                command = profiler.prepare_run(options, "unique-profile")
            check.assert_called_once_with(root, "b" * 64)
            provenance.assert_called_once_with(root, root / "oracle", root / "binding")
            command_for_stage.assert_called_once_with(
                "unique-profile", 1, "cuda", str(options.parent)
            )
            self.assertEqual(
                command[command.index("--resume") + 1], str(options.parent)
            )
            self.assertNotIn("--vp-delta-final", command)
            manifest = json.loads((options.output / "manifest.json").read_text())
            self.assertEqual(manifest["command"], command)
            self.assertEqual(manifest["parent_sha256"], options.parent_sha256)
            self.assertEqual(manifest["watchdog_seconds"], 180)
            self.assertEqual(manifest["device"], "cuda")
            self.assertEqual(manifest["gpu"], "Test GPU")
            self.assertEqual(manifest["gpu_lock"], str(root / "gpu.lock"))

    def test_cuda_unavailable_fails_without_cpu_fallback(self) -> None:
        with (
            patch.object(
                profiler.reconstruction.torch.cuda, "is_available", return_value=False
            ),
            patch.object(profiler.reconstruction.torch.cuda, "get_device_name") as name,
            self.assertRaisesRegex(ValueError, "no CPU fallback"),
        ):
            profiler.device_metadata("cuda")
        name.assert_not_called()
        self.assertIsNone(profiler.device_metadata("cpu")["gpu"])

    def test_wrong_parent_fails_before_provenance_or_training(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            options = supervisor.parse_options(self.arguments(root))
            options.parent.write_bytes(b"wrong bytes")
            with (
                patch.object(profiler.reconstruction.replay, "check_inputs") as check,
                self.assertRaisesRegex(ValueError, "parent checkpoint SHA-256"),
            ):
                profiler.prepare_run(options, "not-launched")
            check.assert_not_called()
            self.assertFalse(options.output.exists())

    def test_modes_execute_identical_entry_once_and_restore_process_context(
        self,
    ) -> None:
        previous_argv, previous_directory = sys.argv, Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            for mode in ("cprofile", "none"):
                output = root / mode
                output.mkdir()
                entry = "import sys; from pathlib import Path; Path('seen.json').write_text(str(sys.argv))"
                command = [sys.executable, "-u", "-c", entry, "--seed", "0"]
                profiler.run_trainer(command, output, output, mode)
                self.assertEqual(
                    (output / "seen.json").read_text(), "['-c', '--seed', '0']"
                )
                result = json.loads((output / "profile.json").read_text())
                self.assertTrue(result["trainer_returned_normally"])
                self.assertGreater(result["elapsed_seconds"], 0)
                self.assertEqual(bool(result["functions"]), mode == "cprofile")
                self.assertEqual(
                    (output / "profile.pstats").exists(), mode == "cprofile"
                )
                if mode == "cprofile":
                    self.assertGreater(
                        pstats.Stats(str(output / "profile.pstats")).total_calls, 0
                    )
        self.assertIs(sys.argv, previous_argv)
        self.assertEqual(Path.cwd(), previous_directory)

    def test_partial_profile_survives_failure_and_termination_without_success(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            for index, exception in enumerate(
                ("RuntimeError('broken')", "InterruptedError('TERM')")
            ):
                output = root / str(index)
                output.mkdir()
                command = [sys.executable, "-u", "-c", f"raise {exception}"]
                with self.assertRaises((RuntimeError, InterruptedError)):
                    profiler.run_trainer(command, root, output, "cprofile")
                result = json.loads((output / "profile.json").read_text())
                self.assertFalse(result["trainer_returned_normally"])
                self.assertTrue((output / "profile.pstats").exists())
                self.assertFalse((output / "result.json").exists())

    def test_supervisor_always_uses_watchdog_and_refuses_existing_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            with (
                patch.object(supervisor.watchdog, "run", return_value=124) as run,
                patch.object(profiler.signal, "signal"),
            ):
                self.assertEqual(supervisor.main(self.arguments(root)), 124)
                command, output, seconds = run.call_args.args
                self.assertEqual(
                    command[3],
                    str(Path(supervisor.__file__).with_name("profile_catan_worker.py")),
                )
                self.assertNotIn("--worker", command)
                self.assertEqual(output, root / "output/run")
                self.assertEqual(seconds, 180)
                with self.assertRaises(FileExistsError):
                    supervisor.main(self.arguments(root))
                self.assertEqual(run.call_count, 1)

    def test_worker_validates_checkpoint_and_preserves_parent_before_success(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            options = supervisor.parse_options(self.arguments(root))
            options.device = "cpu"
            options.output.mkdir()
            run = root / "training/runs/date-profile-cprofile-fixed"
            run.mkdir(parents=True)
            (run / "metrics.jsonl").write_text('{"t":"train","step":10}\n')
            (run / "config.json").write_text('{"device":"cpu"}\n')
            with (
                patch.object(profiler.uuid, "uuid4") as unique,
                patch.object(profiler, "prepare_run", return_value=["entry"]),
                patch.object(profiler, "run_trainer") as execute,
                patch.object(profiler.signal, "signal"),
                patch.object(profiler, "check_parent") as parent,
                patch.object(profiler.reconstruction.replay, "check_inputs"),
                patch.object(
                    profiler.reconstruction,
                    "inspect_checkpoint",
                    return_value={"steps": 10},
                ) as inspect,
            ):
                unique.return_value.hex = "fixed"
                profiler.worker(options)
            inspect.assert_called_once_with(run)
            parent.assert_called_once_with(options)
            execute.assert_called_once_with(["entry"], root, options.output, "cprofile")
            result = json.loads((options.output / "result.json").read_text())
            self.assertTrue(result["finite_checkpoint_and_metrics"])
            self.assertFalse(result["strength_claim"])
            for filename in ("metrics.jsonl", "config.json"):
                self.assertEqual(
                    (options.output / filename).read_bytes(),
                    (run / filename).read_bytes(),
                )
            self.assertFalse(any(options.output.glob("*.pt")))

    def test_cuda_wraps_worker_with_nonblocking_lock_inside_watchdog(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            arguments = [
                *self.arguments(root),
                "--device",
                "cuda",
                "--gpu-lock",
                str(root / "gpu.lock"),
            ]
            with (
                patch.object(supervisor.watchdog, "run", return_value=1) as run,
                patch.object(supervisor.signal, "signal"),
            ):
                self.assertEqual(supervisor.main(arguments), 1)
            command, output, seconds = run.call_args.args
            self.assertEqual(
                command[:3], ["flock", "--nonblock", str(root / "gpu.lock")]
            )
            self.assertEqual(command[3:6], [sys.executable, "-B", "-u"])
            self.assertEqual(command[6], str(Path(profiler.__file__)))
            self.assertEqual(output, root / "output/run")
            self.assertEqual(seconds, 180)

    def test_missing_flock_has_failed_receipt_without_starting_worker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            result = subprocess.run(
                [
                    sys.executable,
                    "-B",
                    supervisor.__file__,
                    *self.arguments(root),
                    "--device",
                    "cuda",
                    "--gpu-lock",
                    str(root / "gpu.lock"),
                ],
                env=dict(os.environ, PATH=""),
                capture_output=True,
                text=True,
                check=False,
                timeout=15,
            )
            self.assertNotEqual(result.returncode, 0, result.stderr)
            receipt = json.loads((root / "output/run.watchdog.json").read_text())
            self.assertEqual(receipt["state"], "failed")
            self.assertEqual(receipt["budget_seconds"], 180)
            self.assertIn("FileNotFoundError", receipt["error"])
            self.assertEqual(receipt["command"][0], "flock")
            self.assertNotIn("process_group", receipt)
            self.assertFalse((root / "output/manifest.json").exists())
            self.assertFalse((root / "output/result.json").exists())

    @unittest.skipUnless(
        sys.platform.startswith("linux") and shutil.which("flock"),
        "requires Linux flock",
    )
    def test_real_lock_refuses_competitor_then_stays_held_across_worker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            lock, marker = root / "gpu.lock", root / "worker-ran"
            (root / "profile_catan_worker.py").write_text(
                "import fcntl\nfrom pathlib import Path\n"
                f"with Path({str(lock)!r}).open('a') as lock:\n"
                "    try:\n        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)\n"
                "    except BlockingIOError:\n"
                f"        Path({str(marker)!r}).write_text('lock held')\n"
                "    else:\n        raise AssertionError('worker ran without lock')\n"
            )
            arguments = [
                *self.arguments(root),
                "--device",
                "cuda",
                "--gpu-lock",
                str(lock),
                "--seconds",
                "1",
            ]
            with (
                patch.object(supervisor, "__file__", str(root / "supervisor.py")),
                patch.object(supervisor, "FINISH_ALLOWANCE_SECONDS", 0),
                patch.object(supervisor.signal, "signal"),
            ):
                with lock.open("a") as competing:
                    fcntl.flock(competing, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    code = supervisor.main(arguments)
                    self.assertNotEqual(code, 0)
                    receipt = json.loads(
                        (root / "output/run.watchdog.json").read_text()
                    )
                    self.assertEqual(receipt["state"], "failed")
                    self.assertFalse(marker.exists())
                self.assertEqual(
                    supervisor.main([*arguments, "--output", str(root / "released")]), 0
                )
            receipt = json.loads((root / "released/run.watchdog.json").read_text())
            self.assertEqual(receipt["state"], "complete")
            self.assertEqual(marker.read_text(), "lock held")
            with lock.open("a") as released:
                fcntl.flock(released, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_nonfinite_checkpoint_cannot_write_success(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            options = supervisor.parse_options(self.arguments(root))
            options.output.mkdir()
            (root / "training/runs/date-profile-cprofile-fixed").mkdir(parents=True)
            with (
                patch.object(profiler.uuid, "uuid4") as unique,
                patch.object(profiler, "prepare_run", return_value=["entry"]),
                patch.object(profiler, "run_trainer"),
                patch.object(profiler.signal, "signal"),
                patch.object(
                    profiler.reconstruction,
                    "inspect_checkpoint",
                    side_effect=ValueError("non-finite"),
                ),
                self.assertRaisesRegex(ValueError, "non-finite"),
            ):
                unique.return_value.hex = "fixed"
                profiler.worker(options)
            self.assertFalse((options.output / "result.json").exists())

    def test_normal_trainer_return_without_artifacts_is_not_success(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            options = supervisor.parse_options(self.arguments(root))
            options.output.mkdir()
            with (
                patch.object(
                    profiler,
                    "prepare_run",
                    return_value=[sys.executable, "-u", "-c", "pass"],
                ),
                patch.object(profiler.signal, "signal"),
                self.assertRaisesRegex(ValueError, "expected one upstream run"),
            ):
                profiler.worker(options)
            self.assertTrue(
                json.loads((options.output / "profile.json").read_text())[
                    "trainer_returned_normally"
                ]
            )
            self.assertFalse((options.output / "result.json").exists())

    def test_changed_parent_or_source_blocks_result_after_normal_return(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            for changed in ("parent", "source"):
                options = supervisor.parse_options(self.arguments(root))
                options.output = root / changed
                options.output.mkdir()
                options.parent.write_bytes(b"parent")
                options.parent_sha256 = profiler.reconstruction.digest(options.parent)
                (root / "training/runs/date-profile-cprofile-fixed").mkdir(
                    parents=True, exist_ok=True
                )
                if changed == "parent":
                    options.parent.write_bytes(b"modified")
                with (
                    patch.object(profiler.uuid, "uuid4") as unique,
                    patch.object(profiler, "prepare_run", return_value=["entry"]),
                    patch.object(profiler, "run_trainer"),
                    patch.object(profiler.signal, "signal"),
                    patch.object(
                        profiler.reconstruction, "inspect_checkpoint", return_value={}
                    ),
                    patch.object(
                        profiler.reconstruction.replay,
                        "check_inputs",
                        side_effect=(
                            ValueError("source changed")
                            if changed == "source"
                            else None
                        ),
                    ) as source_check,
                    self.assertRaisesRegex(
                        ValueError,
                        (
                            "parent checkpoint SHA-256 mismatch"
                            if changed == "parent"
                            else "source changed"
                        ),
                    ),
                ):
                    unique.return_value.hex = "fixed"
                    profiler.worker(options)
                if changed == "parent":
                    source_check.assert_not_called()
                else:
                    source_check.assert_called_once_with(root, "b" * 64)
                self.assertFalse((options.output / "result.json").exists())

    def test_real_cli_bad_parent_is_supervised_and_never_starts_trainer(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root / "parent.pt").write_bytes(b"not the pinned parent")
            result = subprocess.run(
                [
                    sys.executable,
                    "-B",
                    supervisor.__file__,
                    *self.arguments(root),
                    "--device",
                    "cpu",
                ],
                capture_output=True,
                text=True,
                check=False,
                timeout=20,
            )
            self.assertNotEqual(result.returncode, 0, result.stderr)
            receipt = json.loads((root / "output/run.watchdog.json").read_text())
            self.assertEqual(receipt["state"], "failed")
            self.assertEqual(receipt["budget_seconds"], 180)
            self.assertIn(
                "parent checkpoint SHA-256 mismatch",
                (root / "output/run.launcher.log").read_text(),
            )
            self.assertFalse((root / "output/profile.json").exists())
            self.assertFalse((root / "output/result.json").exists())

    def test_real_cli_dependency_import_failure_has_failed_receipt(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root / "torch.py").write_text(
                "raise ImportError('controlled Torch failure')\n"
            )
            result = subprocess.run(
                [sys.executable, "-B", supervisor.__file__, *self.arguments(root)],
                env=dict(os.environ, PYTHONPATH=str(root)),
                capture_output=True,
                text=True,
                check=False,
                timeout=15,
            )
            self.assertNotEqual(result.returncode, 0, result.stderr)
            receipt = json.loads((root / "output/run.watchdog.json").read_text())
            self.assertEqual(receipt["state"], "failed")
            self.assertEqual(receipt["budget_seconds"], 180)
            self.assertIn(
                "controlled Torch failure",
                (root / "output/run.launcher.log").read_text(),
            )
            self.assertFalse((root / "output/profile.json").exists())
            self.assertFalse((root / "output/result.json").exists())

    def test_import_hang_is_bounded_and_leaves_no_worker_process_group(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            pid_path = root / "import.pid"
            (root / "torch.py").write_text(
                "import os, signal, time\nfrom pathlib import Path\n"
                "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
                f"Path({str(pid_path)!r}).write_text(str(os.getpid()))\n"
                "time.sleep(60)\n"
            )
            entry = (
                "import importlib\nfrom unittest.mock import patch\n"
                "supervisor = importlib.import_module('profile-catan-training')\n"
                "with patch.object(supervisor, 'FINISH_ALLOWANCE_SECONDS', 0):\n"
                "    raise SystemExit(supervisor.main())\n"
            )
            result = subprocess.run(
                [
                    sys.executable,
                    "-B",
                    "-c",
                    entry,
                    *self.arguments(root),
                    "--seconds",
                    "1",
                ],
                env=dict(
                    os.environ,
                    PYTHONPATH=os.pathsep.join(
                        (str(root), str(Path(supervisor.__file__).parent))
                    ),
                ),
                capture_output=True,
                text=True,
                check=False,
                timeout=15,
            )
            self.assertEqual(result.returncode, 124, result.stderr)
            receipt = json.loads((root / "output/run.watchdog.json").read_text())
            self.assertEqual(receipt["state"], "timed_out")
            self.assertEqual(receipt["budget_seconds"], 1)
            self.assertEqual(receipt["process_group"], int(pid_path.read_text()))
            with self.assertRaises(ProcessLookupError):
                os.killpg(receipt["process_group"], 0)
            self.assertFalse((root / "output/profile.json").exists())
            self.assertFalse((root / "output/result.json").exists())


if __name__ == "__main__":
    unittest.main()
