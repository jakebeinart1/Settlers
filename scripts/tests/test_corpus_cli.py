#!/usr/bin/env python3
"""Real-process diagnostic export checks; SIM_BINARY can select a parent build.

Native Codable sets and non-string-keyed dictionaries have unordered wire
arrays. Normalize only those named collections, never decks, masks, moves or
record order. This deliberately asserts semantic, not raw-byte, trace parity.
"""

import json
import os
import re
import subprocess
import tempfile
import unittest
from itertools import zip_longest
from pathlib import Path
from typing import Any, Iterator


REPO_ROOT = Path(__file__).parents[2]
PACKAGE = REPO_ROOT / "Packages" / "CatanAI"
SET_FIELDS = {"onBoardVertices", "onBoardEdges", "settlements", "cities", "roads", "pending"}
MAP_FIELDS = {
    "resources", "bank", "give", "get", "want", "amounts", "policyIDs",
    "devCardsBoughtThisTurn", "tradesAcceptedThisTurn", "declinedTradeOffersThisTurn",
}


def semantic(value: Any, field: str = "") -> Any:
    """Keep ordered arrays intact while normalizing Swift collection encodings."""
    if isinstance(value, dict):
        if field == "discard":
            return {key: semantic(item, "amounts") for key, item in value.items()}
        return {key: semantic(item, key) for key, item in value.items()}
    if not isinstance(value, list):
        return value
    items = [semantic(item) for item in value]
    if field in SET_FIELDS:
        return sorted(items, key=lambda item: json.dumps(item, sort_keys=True))
    # Start.policyIDs is an ordered roster; checkpoint.policyIDs is a map
    # encoded as alternating PlayerID/value pairs, not a roster of strings.
    if field in MAP_FIELDS and not (
        field == "policyIDs" and all(isinstance(item, str) for item in items)
    ):
        assert len(items) % 2 == 0, (field, items)
        pairs = list(zip(items[::2], items[1::2]))
        return sorted(pairs, key=lambda pair: json.dumps(pair[0], sort_keys=True))
    return items


def records(path: Path) -> Iterator[dict[str, Any]]:
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            yield json.loads(line)


class CorpusCLITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if os.environ.get("SIM_BINARY"):
            cls.simulator = Path(os.environ["SIM_BINARY"])
        else:
            build = ["swift", "build", "--package-path", str(PACKAGE), "-c", "release"]
            subprocess.run(build + ["--product", "sim"], check=True, capture_output=True)
            result = subprocess.run(
                build + ["--show-bin-path"], check=True, capture_output=True, text=True
            )
            cls.simulator = Path(result.stdout.strip()) / "sim"
        cls.directory = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.directory.cleanup)
        cls.first = Path(cls.directory.name) / "first.jsonl"
        cls.second = Path(cls.directory.name) / "second.jsonl"
        cls.shared = ("--seed", "1", "--jsonl", "--build-id", "corpus-cli-test")
        cls.plain = cls.run_simulator(*cls.shared)
        cls.traced = cls.run_simulator(*cls.shared, "--decision-jsonl", str(cls.first))
        cls.repeated = cls.run_simulator(*cls.shared, "--decision-jsonl", str(cls.second))
        for result in (cls.plain, cls.traced, cls.repeated):
            if result.returncode != 0:
                raise AssertionError(result.stderr)

    @classmethod
    def run_simulator(cls, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(cls.simulator), *arguments], check=False,
            capture_output=True, text=True, timeout=180,
        )

    def test_plain_stdout_and_existing_fingerprint_are_unchanged(self) -> None:
        self.assertEqual(self.plain.stdout, self.traced.stdout)
        self.assertEqual(self.traced.stdout, self.repeated.stdout)
        source = PACKAGE / "Tests/CatanAITests/SeededGameFingerprintTests.swift"
        match = re.search(r'\b1: "([0-9a-f]{16})"', source.read_text(encoding="utf-8"))
        self.assertIsNotNone(match)
        self.assertEqual(json.loads(self.traced.stdout)["fingerprint"], match.group(1))

    def test_separate_process_traces_match_semantically_including_rng(self) -> None:
        for index, pair in enumerate(zip_longest(records(self.first), records(self.second))):
            self.assertEqual(semantic(pair[0]), semantic(pair[1]), f"record {index}")

    def assert_assessment(self, assessment: dict[str, Any]) -> None:
        self.assertAlmostEqual(
            assessment["netGain"], assessment["gainValue"] - assessment["costValue"]
        )
        threshold = sum(assessment[key] for key in (
            "baseThreshold", "threatShift", "standingShift", "suspicionShift", "unlockShift"
        ))
        self.assertAlmostEqual(assessment["threshold"], max(0, threshold))
        self.assertEqual(assessment["accepted"], assessment["netGain"] > assessment["threshold"])

    def test_invocation_pairing_masks_assessments_counts_and_actual_order(self) -> None:
        evaluations = commits = assessment_count = responder_batches = 0
        pending = None
        previous_rng = {"state": 1 * 31 + 7}
        evaluations_since_commit = 0
        last_checkpoint = None
        for record in records(self.first):
            self.assertEqual(set(record), {"schemaVersion", "type", "seed", "payload"})
            self.assertEqual((record["schemaVersion"], record["seed"]), (1, 1))
            payload = record["payload"]
            kind = record["type"]
            if kind == "start":
                self.assertEqual(payload["buildID"], "corpus-cli-test")
                self.assertEqual(payload["policyIDs"], json.loads(self.plain.stdout)["policies"])
                self.assertEqual(payload["boardMode"], "randomized")
                self.assertIn("weights", payload)
            elif kind == "invocation":
                self.assertIsNone(pending)
                self.assertEqual(payload["evaluationIndex"], evaluations)
                self.assertEqual(payload["policyRNGBefore"], previous_rng)
                pending = payload
            elif kind == "evaluation":
                self.assertIsNotNone(pending)
                self.assertEqual(payload["evaluationIndex"], evaluations)
                for key in ("evaluationIndex", "policyID", "observation", "policyRNGBefore"):
                    self.assertEqual(semantic(payload[key]), semantic(pending[key]))
                observation = payload["observation"]
                self.assertIn(semantic(payload["chosenMove"]), semantic(observation["legalMoves"]))
                self.assertTrue(payload["observationText"].startswith("OBS v"))
                mask = observation["legalMoves"]
                if all("respondToTrade" in move for move in mask) and not any(
                    move["respondToTrade"]["accept"] for move in mask
                ):
                    self.assertEqual(payload["tradeAssessments"], [])
                for assessment in payload["tradeAssessments"]:
                    self.assert_assessment(assessment)
                    self.assertEqual(assessment["receiver"], observation["seat"])
                    assessment_count += 1
                previous_rng = payload["policyRNGAfter"]
                evaluations += 1
                evaluations_since_commit += 1
                pending = None
            elif kind == "commit":
                self.assertIsNone(pending)
                self.assertEqual(payload["moveIndex"], commits)
                last_checkpoint = payload["checkpoint"]
                self.assertEqual(last_checkpoint["policyEvaluationCount"], evaluations)
                self.assertEqual(last_checkpoint["policyRNG"], previous_rng)
                if "proposeTrade" in payload["move"]:
                    # Responders run inside commit, hence their evaluations
                    # must already exist when the proposal commit is emitted.
                    self.assertGreater(evaluations_since_commit, 1)
                    responder_batches += 1
                commits += 1
                evaluations_since_commit = 0
            elif kind == "end":
                self.assertIsNone(pending)
                self.assertEqual(payload["reason"], "gameOver")
                self.assertEqual(payload["moves"], commits)
                self.assertEqual(payload["evaluationCount"], evaluations)
                self.assertEqual(semantic(payload["checkpoint"]), semantic(last_checkpoint))
                self.assertEqual(payload["winner"], json.loads(self.plain.stdout)["winner"])
            else:
                self.fail(f"unexpected record type {kind}")
        self.assertGreater(assessment_count, 0)
        self.assertGreater(responder_batches, 0)
        self.assertEqual(kind, "end")
        self.assertEqual(commits, json.loads(self.plain.stdout)["moves"])

    def test_existing_path_is_preserved(self) -> None:
        path = Path(self.directory.name) / "existing.jsonl"
        sentinel = b"existing diagnostic data\n"
        path.write_bytes(sentinel)
        result = self.run_simulator(*self.shared, "--decision-jsonl", str(path))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("overwrite", result.stderr)
        self.assertEqual(path.read_bytes(), sentinel)

    def test_byte_cap_fails_with_retained_prefix_and_footer(self) -> None:
        # Stop after the first invocation but before its return; the footer
        # must expose the unmatched call, not renumber a partial trace.
        with self.first.open("rb") as stream:
            start = stream.readline()
            invocation = stream.readline()
        cap = len(start) + len(invocation) + 512
        path = Path(self.directory.name) / "capped.jsonl"
        result = self.run_simulator(
            *self.shared, "--decision-jsonl", str(path), "--trace-max-bytes", str(cap)
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("byte cap", result.stderr)
        self.assertLessEqual(path.stat().st_size, cap)
        trace = list(records(path))
        self.assertEqual([item["type"] for item in trace], ["start", "invocation", "failure"])
        self.assertEqual(trace[-1]["payload"]["invocationCount"], 1)
        self.assertEqual(trace[-1]["payload"]["evaluationCount"], 0)
        self.assertEqual(result.stdout, "")

    def test_flags_fail_loudly_before_creating_output(self) -> None:
        path = Path(self.directory.name) / "invalid.jsonl"
        cases = (
            ("--decision-jsonl", str(path)),
            ("--decision-jsonl", ""),
            ("--decision-jsonl",),
            ("--trace-max-bytes", "0"),
            ("--trace-max-bytes", "-1"),
            ("--trace-max-bytes", "1.5"),
            ("--trace-max-bytes", str(2**64)),
            ("--trace-max-bytes", "1024"),
            ("--decision-jsnol", str(path)),
            ("--build-id", "--jsonl", "--decision-jsonl", str(path)),
            ("--build-id", "x", "--decision-jsonl", str(path), "--decision-jsonl", str(path)),
            ("--build-id", "x", "--trace-max-bytes", "5", "--trace-max-bytes", "6"),
        )
        for arguments in cases:
            with self.subTest(arguments=arguments):
                result = self.run_simulator(*arguments)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertTrue(result.stderr)
                self.assertFalse(path.exists())

    def test_text_stdout_is_unchanged(self) -> None:
        path = Path(self.directory.name) / "text.jsonl"
        arguments = ("--seed", "1", "--build-id", "corpus-cli-test")
        plain = self.run_simulator(*arguments)
        traced = self.run_simulator(*arguments, "--decision-jsonl", str(path))
        self.assertEqual(plain.returncode, 0, plain.stderr)
        self.assertEqual(traced.returncode, 0, traced.stderr)
        self.assertEqual(plain.stdout, traced.stdout)

    def test_multiple_seeds_have_independent_start_end_and_indices(self) -> None:
        path = Path(self.directory.name) / "multi.jsonl"
        result = self.run_simulator(*self.shared, "--games", "2", "--decision-jsonl", str(path))
        self.assertEqual(result.returncode, 0, result.stderr)
        starts = []
        ends = []
        evaluation_index = 0
        for record in records(path):
            if record["type"] == "start":
                starts.append(record["seed"])
                evaluation_index = 0
            elif record["type"] == "evaluation":
                self.assertEqual(record["payload"]["evaluationIndex"], evaluation_index)
                evaluation_index += 1
            elif record["type"] == "end":
                ends.append(record["seed"])
                self.assertEqual(record["payload"]["evaluationCount"], evaluation_index)
        self.assertEqual(starts, [1, 2])
        self.assertEqual(ends, starts)


if __name__ == "__main__":
    unittest.main()
