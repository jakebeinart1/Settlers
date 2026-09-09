"""Integrity/redaction boundaries for the small native-enrichment workflow."""

import copy
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from test_review_corpus import assessment, payload


SCRIPTS = Path(__file__).parents[1]
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("enrich_corpus", SCRIPTS / "enrich_corpus.py")
assert SPEC and SPEC.loader
ENRICH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ENRICH)


class EnrichCorpusTests(unittest.TestCase):
    def test_selected_source_hash_and_identity_are_enforced(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "trace.jsonl"
            row = {"type": "evaluation", "seed": 100, "payload": payload()}
            path.write_text(json.dumps(row) + "\n")
            manifest = {"sources": [{"path": str(path), "sha256": ENRICH.digest(path)}],
                        "packets": [{"source": str(path), "line": 1, "seed": 100,
                                     "evaluationIndex": 0, "id": "case-001"}]}
            selected = ENRICH.selected_rows(manifest)
            self.assertEqual(selected[0]["id"], "case-001")
            manifest["packets"][0]["evaluationIndex"] = 99
            with self.assertRaisesRegex(ValueError, "identity"):
                ENRICH.selected_rows(manifest)
            path.write_text("changed\n")
            with self.assertRaisesRegex(ValueError, "hash"):
                ENRICH.selected_rows(manifest)

    def test_blind_enrichment_never_includes_recorded_choice_or_scores(self):
        original = {"id": "case-001", **payload()}
        context = {"before": [], "afterAcceptance": [], "secret": "SECRET-FUTURE"}
        result = {"id": "case-001", "context": context,
                  "assessment": {"resourceContributions": ["REVEALED-SCORE"]}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            ENRICH.publish_packets([original], path, [result])
            blind = (path / "case-001-blind.md").read_text()
            explained = (path / "case-001-explained.md").read_text()
            self.assertNotIn("SECRET", blind)
            self.assertNotIn("REVEALED-SCORE", blind)
            self.assertNotIn("Selected:", blind)
            self.assertIn("REVEALED-SCORE", explained)
            self.assertIn("Selected:", explained)

    def test_contribution_math_and_quantities_are_checked(self):
        data = assessment()
        data["resourceContributions"] = []
        for direction, resource, value in (("gain", "ore", 3), ("cost", "brick", 1)):
            data["resourceContributions"].append({
                "direction": direction, "resource": resource, "quantity": 1,
                "unitValue": value, "totalValue": value,
                "targets": [{"required": 1, "held": 0, "deficit": 1,
                             "otherDeficits": 0, "weight": value, "contribution": value}]})
        ENRICH.validate_assessment(data)
        for field in ("quantity", "unitValue", "totalValue"):
            broken = copy.deepcopy(data)
            broken["resourceContributions"][0][field] += 1
            with self.assertRaises(ValueError):
                ENRICH.validate_assessment(broken)
        broken = copy.deepcopy(data)
        broken["resourceContributions"][0]["targets"][0]["otherDeficits"] = 1
        with self.assertRaises(ValueError):
            ENRICH.validate_assessment(broken)


class EnrichPublicationTests(unittest.TestCase):
    """Exercise real selection, validation, files and receipts; mock only native execution."""

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        self.review = root / "review"
        self.review.mkdir()
        self.output = root / "enriched"
        self.binary = root / "fake-native"
        self.binary.write_bytes(b"frozen mock binary; never execute\n")
        self.original = self.consistent_payload()
        trace = root / "trace.jsonl"
        trace.write_text(json.dumps({"type": "evaluation", "seed": 100,
                                     "payload": self.original}) + "\n")
        manifest = {"validation": {"scheduleMembership": True},
                    "sources": [{"path": str(trace), "sha256": ENRICH.digest(trace)}],
                    "packets": [{"source": str(trace), "line": 1, "seed": 100,
                                 "evaluationIndex": 0, "id": "case-001"}]}
        (self.review / "manifest.json").write_text(json.dumps(manifest))

    @staticmethod
    def consistent_payload():
        original = payload()
        state = original["observation"]["state"]
        state["phase"] = {"mainTurn": {"playerIndex": 1}}
        for seat in (1, 2):
            state["players"].append({"id": {"index": seat},
                                     "resources": ["ore", 1] if seat == 1 else [],
                                     "settlements": [], "cities": [], "roads": []})
        original["observation"]["legalMoves"].append(
            {"respondToTrade": {"offerID": "offer", "accept": False}})
        score = original["tradeAssessments"][0]
        score["resourceContributions"] = []
        for direction, resource, held, required, value in (
            ("gain", "ore", 0, 1, 3), ("cost", "brick", 1, 2, 1)
        ):
            score["resourceContributions"].append({
                "direction": direction, "resource": resource, "quantity": 1,
                "unitValue": value, "totalValue": value,
                "targets": [{"targetName": "mock-target", "required": required,
                             "held": held, "deficit": 1, "otherDeficits": 0,
                             "weight": value, "contribution": value}]})
        return original

    @staticmethod
    def native_result(original):
        """Synthetic facts obey the fixture's exchange, not a second native-rule implementation."""
        before = []
        for player in original["observation"]["state"]["players"]:
            hand = dict(zip(player["resources"][::2], player["resources"][1::2]))
            before.append({"seat": player["id"]["index"],
                           "mainTurnNow": player["id"]["index"] == 1,
                           "publicVP": 0, "totalVP": 0, "hand": hand,
                           "bankRates": {"ore": 4, "brick": 4},
                           "expectedCardsPerRoll": {"ore": 0, "brick": 0},
                           "mainTurnOptionsOnFrozenBoard": {
                               "roads": 0, "settlements": 0, "cities": 0,
                               "developmentCard": False, "bankExchanges": 0}})
        after = copy.deepcopy(before)
        after[0]["hand"] = {"brick": 0, "ore": 1}
        after[1]["hand"] = {"brick": 1, "ore": 0}
        return {"schemaVersion": 1, "id": original["id"],
                "context": {"acceptInRecordedMask": True, "before": before,
                            "afterAcceptance": after, "nativeAcceptanceError": None},
                "assessment": copy.deepcopy(original["tradeAssessments"][0])}

    def run_native(self, command, *, stdout, stderr, check, timeout):
        self.assertEqual(command, [str(self.output / "trade-review"),
                                   str(self.output / "private-input.jsonl")])
        self.assertTrue(check)
        self.assertEqual(timeout, ENRICH.PROCESS_TIMEOUT_SECONDS)
        selected = json.loads(Path(command[1]).read_text())
        self.assertEqual(selected, {"id": "case-001", **self.original})
        stdout.write(json.dumps(self.native_result(selected)) + "\n")
        return subprocess.CompletedProcess(command, 0)

    def test_successful_enrichment_publishes_packets_and_verifiable_receipt(self):
        printed = io.StringIO()
        with patch.object(ENRICH.subprocess, "run", side_effect=self.run_native) as native, \
                patch("sys.stdout", printed):
            ENRICH.enrich(self.review, self.binary, self.output)
        native.assert_called_once()
        receipt = json.loads((self.output / "receipt.json").read_text())
        self.assertEqual(json.loads(printed.getvalue()), receipt)
        self.assertEqual((receipt["status"], receipt["cases"]), ("complete", 1))
        self.assertEqual(receipt["sourceManifest"], str((self.review / "manifest.json").resolve()))
        for key, path in (("sourceManifestSHA256", self.review / "manifest.json"),
                          ("binarySHA256", self.output / "trade-review"),
                          ("inputSHA256", self.output / "private-input.jsonl"),
                          ("enricherSHA256", self.output / "enricher.py"),
                          ("reviewRendererSHA256", SCRIPTS / "review_corpus.py")):
            self.assertEqual(receipt[key], ENRICH.digest(path))
        self.assertEqual((self.output / "trade-review").read_bytes(), self.binary.read_bytes())
        blind = (self.output / "case-001-blind.md").read_text()
        explained = (self.output / "case-001-explained.md").read_text()
        self.assertIn("Hand after accepting: brick=0, ore=1.", blind)
        self.assertIn("P1: acts now=True", blind)
        for marker in ("Selected:", "Threshold=", "mock-target", "SECRET-"):
            self.assertNotIn(marker, blind)
        self.assertIn("Selected: accept.", explained)
        self.assertIn("mock-target", explained)
        self.assertNotIn("SECRET-", explained)

    def test_subprocess_failure_retains_partial_output_without_success_receipt(self):
        def fail_native(command, **kwargs):
            self.run_native(command, **kwargs)
            kwargs["stdout"].write('{"id":')
            kwargs["stderr"].write("native failed after partial output\n")
            raise subprocess.CalledProcessError(1, command)

        printed = io.StringIO()
        with patch.object(ENRICH.subprocess, "run", side_effect=fail_native), \
                patch("sys.stdout", printed):
            with self.assertRaises(subprocess.CalledProcessError):
                ENRICH.enrich(self.review, self.binary, self.output)
        self.assertTrue((self.output / "native-output.jsonl").read_text().endswith('{"id":'))
        self.assertIn("native failed", (self.output / "native-stderr.log").read_text())
        self.assertFalse((self.output / "receipt.json").exists())
        self.assertEqual(list(self.output.glob("case-*.md")), [])
        self.assertEqual(printed.getvalue(), "")

    def test_packet_budget_failure_does_not_publish_success_receipt(self):
        printed = io.StringIO()
        with patch.object(ENRICH.subprocess, "run", side_effect=self.run_native) as native, \
                patch.object(ENRICH, "MAX_PACKET_CHARACTERS", 1), \
                patch("sys.stdout", printed):
            with self.assertRaisesRegex(ValueError, "exceeds packet budget"):
                ENRICH.enrich(self.review, self.binary, self.output)
        native.assert_called_once()
        result = json.loads((self.output / "native-output.jsonl").read_text())
        self.assertEqual(result["id"], "case-001")
        self.assertFalse((self.output / "receipt.json").exists())
        self.assertEqual(list(self.output.glob("case-*.md")), [])
        self.assertEqual(printed.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
