"""Exercise hook installation and gate selection in a real linked worktree."""

import subprocess
import tempfile
import unittest
from pathlib import Path


INSTALLER = Path(__file__).parents[1] / "install-hooks.sh"


class WorktreeHookTests(unittest.TestCase):
    def test_linked_worktree_runs_its_own_gate(self) -> None:
        with tempfile.TemporaryDirectory(prefix="empires-hook-test-") as temporary:
            root = Path(temporary) / "main"
            linked = Path(temporary) / "linked"
            root.mkdir()
            self.git(root, "init", "--quiet")
            self.git(root, "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                     "commit", "--allow-empty", "--quiet", "-m", "fixture")
            self.git(root, "worktree", "add", "--quiet", "--detach", str(linked))
            for checkout, status in [(root, 19), (linked, 0)]:
                scripts = checkout / "scripts"
                scripts.mkdir()
                (scripts / "install-hooks.sh").write_bytes(INSTALLER.read_bytes())
                gate = scripts / "gate.sh"
                gate.write_text(f"#!/bin/sh\nexit {status}\n")
                gate.chmod(0o755)
            subprocess.run(["bash", str(linked / "scripts/install-hooks.sh")],
                           cwd=linked, check=True, capture_output=True)
            hook = root / ".git/hooks/pre-push"
            result = subprocess.run([str(hook)], cwd=linked, input="", text=True,
                                    capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def git(self, directory: Path, *arguments: str) -> None:
        subprocess.run(["git", "-C", str(directory), *arguments],
                       check=True, capture_output=True)
