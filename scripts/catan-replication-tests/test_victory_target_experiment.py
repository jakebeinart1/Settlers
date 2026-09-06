"""Target-mismatch experiment guards; no training, evaluation, or GPU launches."""

import importlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
import torch

import catan_training_experiment as experiment

supervisor = importlib.import_module("profile-catan-training")
profiler = importlib.import_module("profile_catan_worker")


class VictoryTargetExperimentTests(unittest.TestCase):
    def arguments(self, *extra: str) -> list[str]:
        return [
            "--source",
            "/tmp/unused-victory-source",
            "--output",
            "/tmp/unused-victory-output",
            "--parent",
            "/tmp/unused-victory-parent.pt",
            "--parent-sha256",
            "a" * 64,
            "--binding-sha256",
            "b" * 64,
            "--mode",
            "none",
            "--device",
            "cpu",
            *extra,
        ]

    def assert_rejected(self, *arguments: str) -> None:
        with patch("sys.stderr", new_callable=io.StringIO), self.assertRaises(
            SystemExit
        ) as rejected:
            supervisor.parse_options(self.arguments(*arguments))
        self.assertEqual(rejected.exception.code, 2)

    def test_default_and_short_experiment_limits_stay_unchanged(self) -> None:
        options = supervisor.parse_options(self.arguments())
        self.assertEqual(
            (options.seconds, options.updates, options.snapshot_mode), (60, None, "row")
        )
        self.assertEqual(
            (options.training_seed, options.victory_target, options.long_experiment),
            (None, None, False),
        )
        supervisor.parse_options(self.arguments("--updates", "100", "--seconds", "120"))
        for extra in (("--updates", "101"), ("--seconds", "121")):
            with self.subTest(arguments=extra):
                self.assert_rejected(*extra)

    def test_long_experiment_has_explicit_update_and_time_ceilings(self) -> None:
        for updates in (1, 800, 1000):
            options = supervisor.parse_options(
                self.arguments(
                    "--long-experiment", "--updates", str(updates), "--seconds", "600"
                )
            )
            self.assertEqual((options.updates, options.seconds), (updates, 600))
        for updates in ("0", "1001"):
            with self.subTest(updates=updates):
                self.assert_rejected("--long-experiment", "--updates", updates)
        for seconds in ("0", "-1", "nan", "inf", "600.01"):
            with self.subTest(seconds=seconds):
                self.assert_rejected(
                    "--long-experiment", "--updates", "800", "--seconds", seconds
                )

    def test_long_experiment_rejects_missing_updates_profiling_and_batch_storage(
        self,
    ) -> None:
        for extra in (
            (),
            ("--updates", "800", "--mode", "cprofile"),
            ("--updates", "800", "--snapshot-mode", "batch"),
        ):
            with self.subTest(arguments=extra):
                self.assert_rejected("--long-experiment", *extra)

    def test_training_variants_are_opt_in_and_seed_is_numpy_compatible(self) -> None:
        for seed in (0, 1, 4294967295):
            for target in (7, 10):
                options = supervisor.parse_options(
                    self.arguments(
                        "--updates",
                        "3",
                        "--training-seed",
                        str(seed),
                        "--victory-target",
                        str(target),
                    )
                )
                self.assertEqual(
                    (options.training_seed, options.victory_target), (seed, target)
                )
        for extra in (
            ("--training-seed", "0"),
            ("--victory-target", "7"),
            ("--updates", "3", "--training-seed", "-1"),
            ("--updates", "3", "--training-seed", "4294967296"),
            ("--updates", "3", "--victory-target", "8"),
            ("--updates", "3", "--victory-target", "10", "--snapshot-mode", "batch"),
        ):
            with self.subTest(arguments=extra):
                self.assert_rejected(*extra)

    def prepare(self, root: Path, *extra: str) -> tuple:
        root.mkdir(parents=True, exist_ok=True)
        parent = root / "parent.pt"
        parent.write_bytes(b"frozen parent")
        options = supervisor.parse_options(
            self.arguments(
                "--source",
                os.environ["CATAN_UPSTREAM"],
                "--output",
                str(root / "output"),
                "--parent",
                str(parent),
                "--parent-sha256",
                profiler.reconstruction.digest(parent),
                *extra,
            )
        )
        options.output.mkdir()
        with (
            patch.object(
                profiler.reconstruction.replay,
                "check_inputs",
                return_value=(root / "oracle", root / "binding"),
            ),
            patch.object(
                profiler.reconstruction.replay,
                "provenance",
                return_value={"fixture": True},
            ),
        ):
            command = profiler.prepare_run(options, "fixture")
        manifest = json.loads((options.output / "manifest.json").read_text())
        return options, command, manifest

    def test_default_command_and_manifest_remain_unmodified(self) -> None:
        defaults = dict(profiler.reconstruction.TRAINING_FLAGS)
        with tempfile.TemporaryDirectory() as directory:
            options, command, manifest = self.prepare(Path(directory))
            expected = profiler.reconstruction.command_for_stage(
                "fixture", 1.0, "cpu", str(options.parent)
            )
            self.assertEqual(command, expected)
            self.assertIn("np.random.seed(0)", command[3])
            self.assertNotIn("experiment", manifest)
            self.assertNotIn("worker_pid", manifest)
            self.assertFalse((options.output / "executed-ppo.py").exists())
            self.assertEqual(
                (manifest["training_seconds"], manifest["watchdog_seconds"]), (60, 180)
            )
        self.assertEqual(profiler.reconstruction.TRAINING_FLAGS, defaults)

    def test_long_transform_changes_only_update_cap_and_requires_opt_in(self) -> None:
        source = (Path(os.environ["CATAN_UPSTREAM"]) / "training/ppo.py").read_text()
        with self.assertRaises(ValueError):
            experiment.transform(source, "row", 800)
        generated = experiment.transform(source, "row", 800, long_experiment=True)
        self.assertEqual(
            generated,
            source.replace(
                "while time.time() < deadline:",
                "while update < 800 and time.time() < deadline:",
            ),
        )
        for mode, updates in (("row", 0), ("row", 1001), ("batch", 800)):
            with self.subTest(mode=mode, updates=updates), self.assertRaises(
                ValueError
            ):
                experiment.transform(source, mode, updates, long_experiment=True)

    def test_four_arms_share_parent_and_wire_numpy_and_upstream_cli_seeds(self) -> None:
        defaults = dict(profiler.reconstruction.TRAINING_FLAGS)
        source = (Path(os.environ["CATAN_UPSTREAM"]) / "training/ppo.py").read_text()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parent = root / "frozen-r2.pt"
            parent.write_bytes(b"same frozen r2 in all arms")
            parent_hash = profiler.reconstruction.digest(parent)
            for index, (seed, target) in enumerate(((0, 7), (0, 10), (1, 10), (1, 7))):
                with self.subTest(seed=seed, target=target):
                    options, command, manifest = self.prepare(
                        root / str(index),
                        "--long-experiment",
                        "--updates",
                        "800",
                        "--seconds",
                        "600",
                        "--training-seed",
                        str(seed),
                        "--victory-target",
                        str(target),
                        "--parent",
                        str(parent),
                        "--parent-sha256",
                        parent_hash,
                    )
                    flags = dict(zip(command[4::2], command[5::2]))
                    expected = profiler.reconstruction.command_for_stage(
                        "fixture", 10.0, "cpu", str(parent.resolve())
                    )
                    expected_flags = dict(zip(expected[4::2], expected[5::2]))
                    expected_flags.update(
                        {"--seed": str(seed), "--victory-target": str(target)}
                    )
                    self.assertEqual(flags, expected_flags)
                    self.assertEqual(flags["--vp-delta"], "0")
                    self.assertNotIn("--vp-delta-final", flags)
                    with patch.object(np.random, "seed") as numpy_seed, patch.object(
                        experiment, "execute"
                    ) as trainer:
                        exec(command[3], {})
                    numpy_seed.assert_called_once_with(seed)
                    trainer.assert_called_once()
                    with patch.object(sys, "argv", ["ppo.py", *command[4:]]):
                        args = profiler.reconstruction.replay.ppo.parse_args()
                    self.assertEqual((args.seed, args.victory_target), (seed, target))
                    self.assertEqual(
                        (
                            manifest["parent_sha256"],
                            manifest["training_seconds"],
                            manifest["watchdog_seconds"],
                        ),
                        (parent_hash, 600, 720),
                    )
                    metadata = manifest["experiment"]
                    self.assertEqual(
                        (
                            metadata["training_seed"],
                            metadata["victory_target"],
                            metadata["long_experiment"],
                        ),
                        (seed, target, True),
                    )
                    self.assertEqual(
                        (options.output / "executed-ppo.py").read_text(),
                        source.replace(
                            "while time.time() < deadline:",
                            "while update < 800 and time.time() < deadline:",
                        ),
                    )
            self.assertEqual(profiler.reconstruction.digest(parent), parent_hash)
        self.assertEqual(profiler.reconstruction.TRAINING_FLAGS, defaults)

    def test_long_supervisor_keeps_600_second_inner_and_720_second_outer_deadline(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory, patch.object(
            supervisor.watchdog, "run", return_value=0
        ) as run, patch.object(supervisor.signal, "signal"):
            result = supervisor.main(
                self.arguments(
                    "--output",
                    str(Path(directory) / "output"),
                    "--long-experiment",
                    "--updates",
                    "800",
                    "--seconds",
                    "600",
                )
            )
            self.assertEqual(result, 0)
            command, receipt, seconds = run.call_args.args
            self.assertEqual(seconds, 720)
            self.assertEqual(command[command.index("--seconds") + 1], "600")
            self.assertEqual(receipt.name, "run")

    def test_validate_work_requires_all_800_updates_and_19660800_decisions(
        self,
    ) -> None:
        experiment.validate_work({"updates": 800, "steps": 19660800}, 800)
        for checkpoint in (
            {"updates": 799, "steps": 19660800},
            {"updates": 800, "steps": 19636224},
            {"updates": 801, "steps": 19685376},
        ):
            with self.subTest(checkpoint=checkpoint), self.assertRaisesRegex(
                ValueError, "equal-update"
            ):
                experiment.validate_work(checkpoint, 800)

    def test_final_checkpoint_configuration_must_match_requested_seed_and_target(
        self,
    ) -> None:
        options = supervisor.parse_options(
            self.arguments(
                "--long-experiment",
                "--updates",
                "800",
                "--seconds",
                "600",
                "--training-seed",
                "1",
                "--victory-target",
                "10",
            )
        )
        valid = {
            "updates": 800,
            "steps": 19660800,
            "config": {"seed": 1, "victory_target": 10},
        }
        with tempfile.TemporaryDirectory() as directory, patch.object(
            experiment, "validate_metrics"
        ), patch.object(experiment, "checkpoint_digests", return_value={}):
            profiler.experiment_result(options, Path(directory), valid)
            for config in (
                {"seed": 0, "victory_target": 10},
                {"seed": 1, "victory_target": 7},
                {},
                {"seed": 1},
                {"victory_target": 10},
            ):
                with self.subTest(config=config), self.assertRaisesRegex(
                    ValueError, "training configuration"
                ):
                    profiler.experiment_result(
                        options, Path(directory), dict(valid, config=config)
                    )

    def test_short_cpu_preflight_options_wire_variants_without_long_budget(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            for target in (7, 10):
                options, command, manifest = self.prepare(
                    Path(directory) / str(target),
                    "--updates",
                    "1",
                    "--seconds",
                    "30",
                    "--training-seed",
                    "1",
                    "--victory-target",
                    str(target),
                )
                self.assertEqual(
                    (manifest["training_seconds"], manifest["watchdog_seconds"]),
                    (30, 150),
                )
                self.assertEqual(manifest["experiment"]["training_seed"], 1)
                self.assertEqual(manifest["experiment"]["victory_target"], target)
                self.assertFalse(manifest["experiment"]["long_experiment"])
                self.assertIn("np.random.seed(1)", command[3])
                self.assertEqual(command[command.index("--seed") + 1], "1")

    def test_supervisor_option_validation_imports_no_training_dependencies(
        self,
    ) -> None:
        code = (
            "import importlib,sys; m=importlib.import_module('profile-catan-training'); "
            "m.parse_options(sys.argv[1:]); "
            "assert not {'torch','numpy','catan_py'}.intersection(sys.modules)"
        )
        subprocess.run(
            [
                sys.executable,
                "-B",
                "-c",
                code,
                *self.arguments(
                    "--long-experiment",
                    "--updates",
                    "800",
                    "--seconds",
                    "600",
                    "--training-seed",
                    "1",
                    "--victory-target",
                    "10",
                ),
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )

    def test_800_iteration_evidence_has_50_checkpoints_and_102_evaluations(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)
            (run / "checkpoints").mkdir()
            rows = []
            for update in range(1, 801):
                step = update * 24576
                rows.append({"t": "train", "step": step})
                if update % 16 == 0:
                    rows.extend(
                        {"t": "eval", "step": step, "vs": opponent}
                        for opponent in ("random-3", "heuristic-v1-3")
                    )
                    torch.save(
                        {
                            "global_step": step,
                            "model_state": {"w": torch.tensor([0.0])},
                            "optimizer_state": {"state": {}},
                        },
                        run / "checkpoints" / f"step_{step:010d}.pt",
                    )
            rows.extend(
                {"t": "eval", "step": 19660800, "vs": opponent}
                for opponent in ("random-3", "heuristic-v1-3")
            )
            metrics = run / "metrics.jsonl"
            metrics.write_text("\n".join(json.dumps(row) for row in rows) + "\n")
            self.assertEqual(sum(row["t"] == "eval" for row in rows), 102)
            experiment.validate_metrics(run, 800)
            digests = experiment.checkpoint_digests(run, 800)
            self.assertEqual(len(digests), 50)
            self.assertIn("19660800", digests)
            metrics.write_text("\n".join(json.dumps(row) for row in rows[:-2]) + "\n")
            with self.assertRaisesRegex(ValueError, "evaluation sequence changed"):
                experiment.validate_metrics(run, 800)


if __name__ == "__main__":
    unittest.main()
