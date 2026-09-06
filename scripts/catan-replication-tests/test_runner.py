"""Integration guards: run explicitly in the isolated upstream environment.

CATAN_UPSTREAM and CATAN_BINDING_SHA256 identify the verified build. These
tests intentionally live outside the Swift repository's dependency-free gate.
"""

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import catan_py

SCRIPT = Path(__file__).resolve().parents[1] / "reproduce-catan-policy.py"
SPEC = importlib.util.spec_from_file_location("reproduction_runner", SCRIPT)
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
SOURCE = Path(os.environ["CATAN_UPSTREAM"]).resolve()
BINDING_SHA256 = os.environ["CATAN_BINDING_SHA256"]


class RunnerGuardTests(unittest.TestCase):
    def test_verified_environment_is_accepted(self) -> None:
        model, binding = runner.check_inputs(SOURCE, BINDING_SHA256)
        self.assertEqual(runner.digest(model), runner.MODEL_SHA256)
        self.assertEqual(runner.digest(binding), BINDING_SHA256)

    def test_wrong_binding_is_rejected_before_any_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "must-not-exist"
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--source",
                    str(SOURCE),
                    "--binding-sha256",
                    "0" * 64,
                    "--output",
                    str(output),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("hash mismatch", result.stderr)
            self.assertFalse(output.exists())

    def test_wrong_revision_is_rejected(self) -> None:
        with (
            patch.object(runner, "git", return_value="wrong-commit"),
            self.assertRaisesRegex(ValueError, "pinned original revision"),
        ):
            runner.check_inputs(SOURCE, BINDING_SHA256)

    def test_modified_source_is_rejected(self) -> None:
        with (
            patch.object(runner, "git", side_effect=[runner.SOURCE_COMMIT, "diff"]),
            self.assertRaisesRegex(ValueError, "tracked source changed"),
        ):
            runner.check_inputs(SOURCE, BINDING_SHA256)

    def test_python_wrapper_cannot_replace_native_environment(self) -> None:
        with (
            patch.object(catan_py, "VecEnv", object()),
            self.assertRaisesRegex(ValueError, "wrapper replaced"),
        ):
            runner.check_inputs(SOURCE, BINDING_SHA256)

    def test_existing_output_is_not_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--source",
                    str(SOURCE),
                    "--binding-sha256",
                    BINDING_SHA256,
                    "--output",
                    directory,
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("FileExistsError", result.stderr)
            self.assertEqual(list(Path(directory).iterdir()), [])


if __name__ == "__main__":
    unittest.main()
