#!/usr/bin/env python3
"""Exercise Ghost's real JSONL importer, not a second copy of its decoder."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Optional


REPO_ROOT = Path(__file__).parents[2]
PACKAGE = REPO_ROOT / "Packages" / "CatanAI"
OFFER_ID = "00000000-0000-0000-0000-000000000001"
NEXT_OFFER_ID = "00000000-0000-0000-0000-000000000002"


def offer(identifier: str) -> dict[str, object]:
    # Resource-keyed dictionaries use Swift Codable's alternating key/value array.
    return {
        "id": identifier,
        "from": {"index": 1},
        "give": ["ore", 1],
        "want": ["lumber", 1],
    }


def start_line() -> dict[str, object]:
    players = [
        {
            "id": {"index": index},
            "resources": resources,
            "devCards": [],
            "playedKnights": 0,
            "settlements": [],
            "cities": [],
            "roads": [],
        }
        for index, resources in enumerate(
            (["lumber", 3, "brick", 2], ["ore", 2, "wool", 2], [])
        )
    ]
    return {
        "kind": "start",
        "roster": {"humanSeats": [{"index": 0}]},
        "initialState": {
            # Trade-only position: no placements or production are exercised.
            "board": {
                "tiles": [],
                "ports": [],
                "onBoardVertices": [],
                "onBoardEdges": [],
                "robberTile": {"q": 0, "r": 0},
            },
            "players": players,
            "phase": {"mainTurn": {"playerIndex": 1}},
            "rng": {"state": 33},
            "bank": ["lumber", 16, "brick", 17, "ore", 17, "wool", 17, "grain", 19],
            "pendingTradeOffers": [offer(OFFER_ID)],
        },
    }


def response_line(
    identifier: str, origin: Optional[bool], accept: bool = False
) -> dict[str, object]:
    line: dict[str, object] = {
        "kind": "move",
        "player": {"index": 0},
        "move": {"respondToTrade": {"offerID": identifier, "accept": accept}},
    }
    if origin is not None:
        line["isHumanDecision"] = origin
    return line


class GhostImporterProvenanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        subprocess.run(
            [
                "swift", "build", "--package-path", str(PACKAGE),
                "--jobs", "2", "--configuration", "release", "--product", "ghost",
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=600,
        )
        result = subprocess.run(
            [
                "swift", "build", "--package-path", str(PACKAGE),
                "--jobs", "2", "--configuration", "release", "--show-bin-path",
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=120,
        )
        cls.ghost = Path(result.stdout.strip()) / "ghost"

    def extract(
        self, events: list[dict[str, object]]
    ) -> tuple[subprocess.CompletedProcess[str], list[dict[str, object]]]:
        with tempfile.TemporaryDirectory(prefix="ghost-import-provenance-") as folder:
            directory = Path(folder)
            archive = directory / "trace.jsonl"
            output = directory / "decisions.jsonl"
            archive.write_text(
                "".join(json.dumps(line) + "\n" for line in [start_line(), *events]),
                encoding="utf-8",
            )
            result = subprocess.run(
                [str(self.ghost), "extract", "--out", str(output), str(archive)],
                check=False,
                cwd=directory,
                capture_output=True,
                text=True,
                timeout=120,
            )
            records = (
                [json.loads(line) for line in output.read_text().splitlines()]
                if output.exists() else []
            )
        return result, records

    def test_false_is_not_learned_and_explicit_or_legacy_true_is_learned(self) -> None:
        for origin, expected_count in ((False, 0), (True, 1), (None, 1)):
            with self.subTest(is_human_decision=origin):
                result, records = self.extract([response_line(OFFER_ID, origin)])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(len(records), expected_count, result.stdout)
                if records:
                    self.assertEqual(records[0]["facet"], "tradeResponse")
                    candidates = records[0]["candidates"]
                    self.assertEqual(
                        candidates[records[0]["chosen"]]["move"],
                        response_line(OFFER_ID, origin)["move"],
                    )

    def test_mixed_origins_keep_later_human_decisions(self) -> None:
        proposal = {
            "kind": "move",
            "player": {"index": 1},
            "move": {"proposeTrade": {"_0": offer(NEXT_OFFER_ID)}},
        }
        result, records = self.extract([
            response_line(OFFER_ID, False),
            proposal,
            response_line(NEXT_OFFER_ID, True, accept=True),
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(records), 1, result.stdout)
        record = records[0]
        self.assertEqual(record["facet"], "tradeResponse")
        self.assertEqual(
            record["candidates"][record["chosen"]]["move"],
            response_line(NEXT_OFFER_ID, True, accept=True)["move"],
        )

    def test_non_training_moves_are_applied_not_dropped_from_replay(self) -> None:
        result, records = self.extract([
            response_line(OFFER_ID, False), response_line(OFFER_ID, False),
        ])
        # The first rejection removes the offer. Repeating it must diverge at
        # event 1, even though neither move should contribute training records.
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("divergedAt", result.stderr)
        self.assertIn("index: 1", result.stderr)
        self.assertIn("invalidTradeTarget", result.stderr)
        self.assertEqual(records, [])


if __name__ == "__main__":
    unittest.main()
