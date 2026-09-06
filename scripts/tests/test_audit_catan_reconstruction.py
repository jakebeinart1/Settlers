"""Prove incomplete/corrupt evidence cannot become a completion success."""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from audit_catan_reconstruction import audit, count_outcomes
from catan_policy_evidence import digest

FIXTURE = (
    Path(__file__).resolve().parents[2]
    / "docs/AI_summaries/evidence/catan-reconstruction/gpu-watchdog-smoke"
)


class CompletionAuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name) / "run"
        self.output.mkdir()
        self.status = json.loads((FIXTURE / "status.json").read_text())
        self.manifest = json.loads((FIXTURE / "manifest.json").read_text())
        self.receipt = json.loads((FIXTURE / "watchdog-completed.json").read_text())
        for name, stage in self.status["stages"].items():
            checkpoint = self.output / name / "checkpoints/final.pt"
            checkpoint.parent.mkdir(parents=True)
            checkpoint.write_bytes(name.encode())
            metrics = checkpoint.parent.parent / "metrics.jsonl"
            metrics.write_text("{}\n")
            stage.update(
                checkpoint=str(checkpoint),
                checkpoint_sha256=digest(checkpoint),
                metrics_sha256=digest(metrics),
            )
        self.status["stages"]["continuation"]["config"]["resume"] = self.status[
            "stages"
        ]["fresh"]["checkpoint"]
        for record in self.status["evaluation"]:
            rows = [
                {
                    "ordinal": i,
                    "winner": 0 if i < record["wins"] else 1,
                    "capped": False,
                }
                for i in range(record["games"])
            ]
            path = self.output / f"{record['model']}-seed-{record['seed']}.jsonl"
            path.write_text("\n".join(json.dumps(row) for row in rows))
            record["outcomes_sha256"] = digest(path)
            if record["model"] == "reconstructed":
                record["checkpoint_sha256"] = self.status["stages"]["continuation"][
                    "checkpoint_sha256"
                ]
        exported = self.output / "final.ctnn"
        exported.write_bytes(b"test export")
        self.status["ctnn_sha256"] = digest(exported)
        (self.output / "native-metrics.jsonl").write_text(
            json.dumps(self.status["native_game"])
        )
        self.save()

    def save(self) -> None:
        for name, value in (
            ("status", self.status),
            ("manifest", self.manifest),
            ("evaluation", self.status["evaluation"]),
        ):
            (self.output / f"{name}.json").write_text(json.dumps(value))
        self.output.with_name("run.watchdog.json").write_text(json.dumps(self.receipt))

    def test_valid_smoke_remains_not_a_training_reproduction_claim(self) -> None:
        result = audit(self.output)
        self.assertEqual(result["artifact_audit"], "passed")
        self.assertEqual(result["training_reproduction_verdict"], "not_assessed")
        self.assertEqual(result["stages"]["fresh"]["minutes"], 0.5)
        self.assertEqual(
            result["totals"]["original"], {"wins": 504, "games": 768, "caps": 0}
        )

    def test_running_watchdog_is_not_completion(self) -> None:
        self.receipt["state"] = "running"
        self.save()
        with self.assertRaisesRegex(ValueError, "watchdog"):
            audit(self.output)

    def test_wrong_parent_is_rejected(self) -> None:
        self.status["stages"]["continuation"]["config"]["resume"] = "other.pt"
        self.save()
        with self.assertRaisesRegex(ValueError, "resume"):
            audit(self.output)

    def test_corrupt_checkpoint_is_rejected(self) -> None:
        Path(self.status["stages"]["fresh"]["checkpoint"]).write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            audit(self.output)

    def test_duplicate_or_missing_cell_is_rejected(self) -> None:
        self.status["evaluation"][-1] = self.status["evaluation"][0]
        self.save()
        with self.assertRaisesRegex(ValueError, "missing/duplicate"):
            audit(self.output)

    def test_summary_cannot_invent_wins(self) -> None:
        self.status["evaluation"][0]["wins"] += 1
        self.save()
        with self.assertRaisesRegex(ValueError, "wrong counts"):
            audit(self.output)

    def test_truncated_raw_file_is_rejected(self) -> None:
        (self.output / "original-seed-777.jsonl").write_text("{}")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            audit(self.output)

    def test_protocol_change_is_rejected(self) -> None:
        self.manifest["protocol"]["policy_seat"] = 1
        self.save()
        with self.assertRaisesRegex(ValueError, "protocol"):
            audit(self.output)

    def test_capped_native_game_is_rejected_even_with_matching_status(self) -> None:
        self.status["native_game"]["cap"] = True
        (self.output / "native-metrics.jsonl").write_text(
            json.dumps(self.status["native_game"])
        )
        self.save()
        with self.assertRaisesRegex(ValueError, "native game"):
            audit(self.output)

    def test_late_completion_is_rejected(self) -> None:
        self.status["finished"] = self.receipt["deadline_epoch"] + 1
        self.save()
        with self.assertRaisesRegex(ValueError, "deadline"):
            audit(self.output)

    def test_overshoot_kept_and_cap_never_a_win(self) -> None:
        rows = [{"ordinal": i, "winner": 0, "capped": i == 2} for i in range(3)]
        self.assertEqual(count_outcomes(rows, 2), {"games": 3, "wins": 2, "caps": 1})

    def test_failed_pipeline_and_wrong_receipt_rejected(self) -> None:
        for field, value in (("phase", "failed"), ("pid", -1)):
            with self.subTest(field=field):
                original = self.status[field]
                self.status[field] = value
                self.save()
                with self.assertRaises(ValueError):
                    audit(self.output)
                self.status[field] = original


if __name__ == "__main__":
    unittest.main()
