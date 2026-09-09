"""Synthetic subprocesses only: no native games, builds or policy tuning."""

import copy
import json
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from collections import Counter
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
import screen_trade_policy as SCREEN


def rows(shard, build="test"):
    return [
        {
            "schemaVersion": 5,
            "buildID": build,
            "seed": seed,
            "playerCount": shard["players"],
            "victoryPointTarget": 10,
            "boardMode": "randomized",
            "policies": shard["policies"],
            "winner": seed % shard["players"],
            "moves": 100,
            "vp": [10] * shard["players"],
            "fingerprint": "0123456789abcdef",
            "behavior": [{} for _ in range(shard["players"])],
        }
        for seed in range(shard["firstSeed"], shard["firstSeed"] + shard["games"])
    ]


def write_rows(path, values):
    path.write_text("".join(json.dumps(row) + "\n" for row in values))


class ScreenTradePolicyTests(unittest.TestCase):
    def test_locked_schedule_and_pairs(self):
        shards = SCREEN.schedule(SCREEN.CANDIDATE_ID)
        self.assertEqual(len(shards), 28)
        self.assertEqual(
            Counter(
                {
                    arm: sum(s["games"] for s in shards if s["arm"] == arm)
                    for arm in ("candidate", "baseline")
                }
            ),
            {"candidate": 224, "baseline": 224},
        )
        families = []
        for cell, first in enumerate((880000, 880100, 880200, 880300)):
            selected = [s for s in shards if s["firstSeed"] == first]
            players = 3 if cell < 2 else 4
            self.assertEqual(
                {(s["arm"], s["chair"]) for s in selected},
                {
                    (arm, chair)
                    for arm in ("candidate", "baseline")
                    for chair in range(players)
                },
            )
            families.extend(range(first, first + 16))
            for shard in selected:
                self.assertEqual(
                    shard["policies"][shard["chair"]],
                    SCREEN.CANDIDATE_ID
                    if shard["arm"] == "candidate"
                    else SCREEN.BASELINE_ID,
                )
        self.assertEqual(len(set(families)), 64)

    def test_strict_native_output_contract(self):
        shard = SCREEN.schedule(SCREEN.CANDIDATE_ID)[0]
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "candidate-seat0.jsonl"
            good = rows(shard)
            write_rows(path, good)
            SCREEN.validate_shard(path, shard, "test")
            edits = {
                "seed": 1,
                "schemaVersion": True,
                "buildID": "other",
                "playerCount": 4,
                "victoryPointTarget": 8,
                "boardMode": "standard",
                "policies": [],
                "winner": None,
                "moves": 0,
                "behavior": [],
                "vp": [],
                "fingerprint": "invalid",
            }
            for key, value in edits.items():
                with self.subTest(key=key):
                    bad = copy.deepcopy(good)
                    bad[0][key] = value
                    write_rows(path, bad)
                    with self.assertRaises(ValueError):
                        SCREEN.validate_shard(path, shard, "test")
            for bad in (good[:-1], good + [good[0]], list(reversed(good))):
                write_rows(path, bad)
                with self.assertRaises(ValueError):
                    SCREEN.validate_shard(path, shard, "test")
            path.write_text(json.dumps(good[0]))
            with self.assertRaisesRegex(ValueError, "truncated"):
                SCREEN.validate_shard(path, shard, "test")

    def test_two_workers_no_failure_replacements(self):
        active = peak = launched = 0
        lock = threading.Lock()

        def fake(*args):
            nonlocal active, peak, launched
            with lock:
                launched += 1
                active += 1
                peak = max(peak, active)
            time.sleep(0.02)
            with lock:
                active -= 1
            raise ValueError("failed seed")

        with tempfile.TemporaryDirectory() as temp, patch.object(
            SCREEN, "run_shard", side_effect=fake
        ):
            with (Path(temp) / "progress").open("w") as progress:
                with self.assertRaisesRegex(ValueError, "failed seed"):
                    SCREEN.play(
                        SCREEN.schedule(SCREEN.CANDIDATE_ID),
                        dict(candidate=Path("a"), baseline=Path("b")),
                        dict(candidate="a", baseline="b"),
                        Path(temp),
                        progress,
                    )
        self.assertEqual(peak, 2)
        self.assertEqual(launched, 2)

    def test_subprocess_timeout_retains_raw_and_command(self):
        shard = SCREEN.schedule(SCREEN.CANDIDATE_ID)[0]
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            (output / shard["stratum"]).mkdir()
            with patch.object(
                SCREEN.subprocess,
                "run",
                side_effect=subprocess.TimeoutExpired("sim", 120),
            ) as run:
                with self.assertRaises(subprocess.TimeoutExpired):
                    SCREEN.run_shard(output, shard, Path("sim"), "test")
            self.assertEqual(run.call_args.kwargs["timeout"], 120)
            self.assertTrue(run.call_args.kwargs["check"])
            path = SCREEN.shard_path(output, shard)
            self.assertTrue(path.exists())
            self.assertTrue(path.with_suffix(".command.json").exists())

    def test_synthetic_full_pipeline_and_exclusive_output(self):
        # A tiny executable writes native-shaped records; it never loads Empires.
        program = (
            f"#!{sys.executable}\n"
            + """import json,sys
a=sys.argv[1:]
get=lambda key:a[a.index(key)+1]
n=int(get('--players')); names=get('--seats').split(',')
ids=['experimental-joint-balanced-v1' if s=='joint-balanced' else 'heuristic-'+s for s in names]
for seed in range(int(get('--seed')),int(get('--seed'))+int(get('--games'))):
 print(json.dumps(dict(schemaVersion=5,buildID=get('--build-id'),seed=seed,playerCount=n,
 victoryPointTarget=10,boardMode='randomized',policies=ids,winner=seed%n,moves=100,
 vp=[10]*n,fingerprint='0123456789abcdef',behavior=[{} for _ in range(n)])))
"""
        )
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            binary = root / "fake-sim"
            binary.write_text(program)
            binary.chmod(0o755)
            (root / "source.tar.gz").write_bytes(b"synthetic source archive")
            output = root / "result"
            with patch.object(SCREEN, "BASELINE_SHA256", SCREEN.digest(binary)):
                SCREEN.run(binary, binary, SCREEN.CANDIDATE_ID, output)
            receipt = json.loads((output / "receipt.json").read_text())
            self.assertEqual(receipt["status"], "complete")
            self.assertEqual(receipt["games"], 448)
            self.assertEqual(receipt["parityGames"], 28)
            self.assertEqual(receipt["adoption"], "inconclusive-no-ship")
            self.assertFalse(receipt["strengthEstablished"])
            for name, expected in receipt["artifactsSHA256"].items():
                self.assertEqual(SCREEN.digest(output / name), expected)
            events = [
                json.loads(line)
                for line in (output / "progress.jsonl").read_text().splitlines()
            ]
            barrier = next(
                i
                for i, event in enumerate(events)
                if event["status"] == "parity-passed"
            )
            self.assertTrue(
                all(
                    "joint-balanced" not in e.get("shard", {}).get("seats", [])
                    for e in events[:barrier]
                )
            )
            self.assertTrue((output / "source/scripts/screen_trade_policy.py").exists())
            self.assertTrue((output / "source" / SCREEN.ANALYZER).exists())
            with self.assertRaises(FileExistsError):
                SCREEN.run(binary, binary, SCREEN.CANDIDATE_ID, output)


if __name__ == "__main__":
    unittest.main()
