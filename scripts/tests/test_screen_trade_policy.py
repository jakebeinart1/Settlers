"""Synthetic subprocesses only: no native games, builds or policy tuning."""

import copy
import io
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


def synthetic_native(command, *, stdout, stderr, check, timeout):
    """Exercise real serialization/analysis without launching the native candidate."""

    def option(name):
        return command[command.index(name) + 1]

    seats = option("--seats").split(",")
    shard = {
        "players": int(option("--players")),
        "firstSeed": int(option("--seed")),
        "games": int(option("--games")),
        "policies": [
            SCREEN.CANDIDATE_ID if seat == "joint-balanced" else f"heuristic-{seat}"
            for seat in seats
        ],
    }
    stdout.write(
        "".join(
            json.dumps(row) + "\n" for row in rows(shard, option("--build-id"))
        ).encode()
    )
    stderr.write(b"synthetic diagnostics\n")


class ScreenTradePolicyTests(unittest.TestCase):
    def test_configured_strata_full_rotation_and_1792_game_total(self):
        total = 0
        for players in (3, 4):
            for opponent in ("balanced", "aggressive"):
                shards = SCREEN.schedule(
                    SCREEN.CANDIDATE_ID, players, opponent, 990000, 64
                )
                self.assertEqual(len(shards), players * 2)
                self.assertEqual(
                    {s["stratum"] for s in shards}, {f"p{players}-{opponent}"}
                )
                for arm in ("candidate", "baseline"):
                    selected = [s for s in shards if s["arm"] == arm]
                    self.assertEqual(
                        [s["chair"] for s in selected], list(range(players))
                    )
                    self.assertTrue(
                        all(
                            s["games"] == 64 and s["firstSeed"] == 990000
                            for s in selected
                        )
                    )
                total += sum(s["games"] for s in shards)
        self.assertEqual(total, 1792)

    def test_configuration_all_or_none_and_invalid_values(self):
        good = dict(players=3, opponent="balanced", first_seed=0, seeds=64)
        keys = list(good)
        for mask in range(1, 15):
            partial = {
                key: good[key] for index, key in enumerate(keys) if mask & (1 << index)
            }
            with self.subTest(partial=partial), self.assertRaisesRegex(
                ValueError, "together"
            ):
                SCREEN.schedule(SCREEN.CANDIDATE_ID, **partial)
        for key, values in {
            "players": (2, 5, True, 3.0),
            "opponent": ("cautious", "", 1),
            "first_seed": (-1, 1.5, True, 2**64, 2**64 - 63),
            "seeds": (0, -1, 65, True, 1.5),
        }.items():
            for value in values:
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    SCREEN.schedule(SCREEN.CANDIDATE_ID, **{**good, key: value})
        for first, count in ((0, 1), (2**64 - 1, 1), (2**64 - 64, 64)):
            shard = SCREEN.schedule(SCREEN.CANDIDATE_ID, 3, "balanced", first, count)[0]
            self.assertEqual(shard["firstSeed"] + shard["games"] - 1, first + count - 1)

    def test_cli_validation_before_run(self):
        required = ["--binary", "sim", "--baseline-binary", "base", "--output", "out"]
        valid = [
            "--players",
            "4",
            "--opponent",
            "aggressive",
            "--first-seed",
            "0",
            "--seeds",
            "64",
            "--source-root",
            "prior/source",
        ]
        locks = [
            "--candidate-sha256",
            "a" * 64,
            "--baseline-sha256",
            "b" * 64,
            "--baseline-source-commit",
            "4737471",
        ]
        args = SCREEN.parse_args(required + valid + locks)
        self.assertEqual(
            (args.players, args.opponent, args.first_seed, args.seeds),
            (4, "aggressive", 0, 64),
        )
        self.assertEqual(args.source_root, Path("prior/source"))
        self.assertIsNone(SCREEN.parse_args(required).players)
        for invalid in (
            ["--players", "3"],
            valid[:1] + ["5"] + valid[2:],
            valid[:3] + ["cautious"] + valid[4:],
            valid[:5] + ["-1"] + valid[6:],
            valid[:7] + ["65"] + valid[8:],
            valid[:5] + [str(2**64 - 63)] + valid[6:],
        ):
            with self.subTest(invalid=invalid), patch("sys.stderr", new=io.StringIO()):
                with self.assertRaises(SystemExit) as error:
                    SCREEN.parse_args(required + invalid)
                self.assertEqual(error.exception.code, 2)

    def test_chunks_preserve_exact_seed_series_and_timeout(self):
        for count, expected in (
            (1, [1]),
            (16, [16]),
            (17, [16, 1]),
            (63, [16, 16, 16, 15]),
            (64, [16, 16, 16, 16]),
        ):
            with self.subTest(seeds=count), tempfile.TemporaryDirectory() as temp:
                shard = SCREEN.schedule(
                    SCREEN.CANDIDATE_ID, 4, "aggressive", 900000, count
                )[0]
                output = Path(temp)
                (output / shard["stratum"]).mkdir()
                with patch.object(
                    SCREEN.subprocess, "run", side_effect=synthetic_native
                ) as run:
                    result = SCREEN.run_shard(output, shard, Path("sim"), "test")
                self.assertEqual(run.call_count, len(expected))
                commands = [call.args[0] for call in run.call_args_list]
                self.assertEqual(
                    [int(c[c.index("--games") + 1]) for c in commands], expected
                )
                self.assertEqual(
                    [int(c[c.index("--seed") + 1]) for c in commands],
                    [900000 + i * 16 for i in range(len(expected))],
                )
                self.assertTrue(
                    all(
                        call.kwargs["timeout"] == 120 and call.kwargs["check"]
                        for call in run.call_args_list
                    )
                )
                combined = SCREEN.shard_path(output, shard)
                SCREEN.validate_shard(combined, shard, "test")
                self.assertEqual(result["games"], count)
                actual = [
                    json.loads(line)["seed"]
                    for line in combined.read_text().splitlines()
                ]
                self.assertEqual(actual, list(range(900000, 900000 + count)))
                self.assertEqual(len(list(combined.parent.glob("*-seat*.jsonl"))), 1)
                with self.assertRaises(FileExistsError):
                    SCREEN.run_shard(output, shard, Path("sim"), "test")

    def test_later_chunk_failure_keeps_evidence_and_launches_no_more_chunks(self):
        shard = SCREEN.schedule(SCREEN.CANDIDATE_ID, 3, "balanced", 900000, 64)[0]
        calls = 0

        def fail_second(command, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 2:
                kwargs["stdout"].write(b"partial")
                raise subprocess.TimeoutExpired(command, 120)
            synthetic_native(command, **kwargs)

        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            (output / shard["stratum"]).mkdir()
            progress = io.StringIO()
            with patch.object(SCREEN.subprocess, "run", side_effect=fail_second):
                with self.assertRaises(subprocess.TimeoutExpired):
                    SCREEN.play(
                        [shard],
                        {"candidate": Path("sim")},
                        {"candidate": "test"},
                        output,
                        progress,
                    )
            self.assertEqual(calls, 2)
            self.assertEqual(
                json.loads(progress.getvalue().splitlines()[-1])["status"], "failed"
            )
            directory = (
                SCREEN.shard_path(output, shard).parent / "chunks" / "candidate-seat0"
            )
            self.assertTrue((directory / "chunk-000.receipt.json").exists())
            self.assertEqual((directory / "chunk-001.jsonl").read_bytes(), b"partial")
            self.assertTrue((directory / "chunk-001.command.json").exists())
            self.assertFalse((directory / "chunk-002.jsonl").exists())
            self.assertFalse((output / shard["stratum"] / "analysis.json").exists())

    def test_confirmation_pipeline_archives_frozen_source_and_current_runner(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            binary = root / "sim"
            binary.write_bytes(b"synthetic locked executable; never launched")
            (root / "source.tar.gz").write_bytes(b"synthetic baseline archive")
            source = root / "prior" / "source"
            (source / "scripts").mkdir(parents=True)
            (source / "scripts/screen_trade_policy.py").write_text("old runner\n")
            (source / "candidate.swift").write_text(
                "prior candidate, not live bindings\n"
            )
            output = root / "result"
            with patch.object(
                SCREEN.subprocess, "run", side_effect=synthetic_native
            ) as run:
                SCREEN.run(
                    binary,
                    binary,
                    SCREEN.CANDIDATE_ID,
                    output,
                    players=4,
                    opponent="aggressive",
                    first_seed=900000,
                    seeds=64,
                    source_root=source,
                    candidate_sha256=SCREEN.digest(binary),
                    baseline_sha256=SCREEN.digest(binary),
                    baseline_source_commit="4737471",
                )
            self.assertEqual(run.call_count, 40)  # 8 parity + 8 chairs × 4 chunks.
            manifest = json.loads((output / "manifest.json").read_text())
            receipt = json.loads((output / "receipt.json").read_text())
            analysis = json.loads((output / "p4-aggressive/analysis.json").read_text())
            self.assertEqual(
                manifest["configuration"],
                dict(players=4, opponent="aggressive", firstSeed=900000, seeds=64),
            )
            self.assertEqual(manifest["subprocesses"], 32)
            self.assertEqual(manifest["baselineSourceCommit"], "4737471")
            self.assertEqual(
                manifest["binaryLocks"],
                dict(candidate=SCREEN.digest(binary), baseline=SCREEN.digest(binary)),
            )
            self.assertEqual(receipt["games"], 512)
            self.assertEqual(receipt["gamesPerArm"], 256)
            self.assertEqual(receipt["parityGames"], 8)
            self.assertEqual(receipt["status"], "complete")
            for record in (manifest, receipt, analysis):
                self.assertEqual(record["purpose"], "stage4-confirmation")
                self.assertFalse(record["strengthEstablished"])
            self.assertEqual(receipt["adoption"], "parent-decision-required")
            self.assertEqual(analysis["adoption"], "parent-decision-required")
            self.assertEqual(analysis["seedFamilies"], 64)
            self.assertEqual(analysis["candidate"]["games"], 256)
            self.assertEqual(analysis["baseline"]["games"], 256)
            self.assertEqual(
                (analysis["difference"], analysis["lower95"], analysis["upper95"]),
                (0, 0, 0),
            )
            self.assertEqual(
                (output / "source/scripts/screen_trade_policy.py").read_text(),
                "old runner\n",
            )
            self.assertEqual(
                SCREEN.digest(output / "runner-source/scripts/screen_trade_policy.py"),
                SCREEN.digest(Path(SCREEN.__file__)),
            )
            self.assertEqual(manifest["candidateSource"]["root"], str(source.resolve()))
            self.assertIn(
                "not independently verified",
                manifest["candidateSource"]["relationship"],
            )
            for name, expected in receipt["artifactsSHA256"].items():
                self.assertEqual(SCREEN.digest(output / name), expected)

    def test_confirmation_rejects_unpinned_candidate_before_launch(self):
        with tempfile.TemporaryDirectory() as temp:
            binary = Path(temp) / "sim"
            binary.write_bytes(b"wrong candidate")
            output = Path(temp) / "out"
            with patch.object(SCREEN.subprocess, "run") as run:
                with self.assertRaisesRegex(ValueError, "locked Stage 4 hash"):
                    SCREEN.run(
                        binary,
                        binary,
                        SCREEN.CANDIDATE_ID,
                        output,
                        players=3,
                        opponent="balanced",
                        first_seed=900000,
                        seeds=64,
                        candidate_sha256=SCREEN.CANDIDATE_SHA256,
                        baseline_sha256=SCREEN.BASELINE_SHA256,
                        baseline_source_commit="4737471",
                    )
            run.assert_not_called()
            self.assertFalse(output.exists())

    def test_explicit_locks_and_commit_validation(self):
        required = ["--binary", "sim", "--baseline-binary", "base", "--output", "out"]
        args = SCREEN.parse_args(
            required
            + [
                "--candidate-sha256",
                "A" * 64,
                "--baseline-sha256",
                "b" * 64,
                "--baseline-source-commit",
                "4737471",
            ]
        )
        self.assertEqual(args.candidate_sha256, "a" * 64)
        self.assertEqual(args.baseline_sha256, "b" * 64)
        self.assertEqual(args.baseline_source_commit, "4737471")
        defaults = SCREEN.parse_args(required)
        self.assertEqual(defaults.candidate_sha256, SCREEN.CANDIDATE_SHA256)
        self.assertEqual(defaults.baseline_sha256, SCREEN.BASELINE_SHA256)
        self.assertEqual(defaults.baseline_source_commit, "ec058ab")
        for flag, value in (
            ("--candidate-sha256", "a" * 63),
            ("--baseline-sha256", "g" * 64),
            ("--baseline-source-commit", "main"),
            ("--baseline-source-commit", "abc123"),
            ("--baseline-source-commit", "a" * 41),
        ):
            with self.subTest(flag=flag), patch("sys.stderr", new=io.StringIO()):
                with self.assertRaises(SystemExit) as error:
                    SCREEN.parse_args(required + [flag, value])
                self.assertEqual(error.exception.code, 2)

    def test_confirmation_requires_every_explicit_lock(self):
        required = [
            "--binary",
            "sim",
            "--baseline-binary",
            "base",
            "--output",
            "out",
            "--players",
            "3",
            "--opponent",
            "balanced",
            "--first-seed",
            "0",
            "--seeds",
            "64",
        ]
        locks = [
            ("--candidate-sha256", "a" * 64),
            ("--baseline-sha256", "b" * 64),
            ("--baseline-source-commit", "4737471"),
        ]
        for mask in range(7):
            supplied = [
                value
                for index, pair in enumerate(locks)
                if mask & (1 << index)
                for value in pair
            ]
            with self.subTest(mask=mask), patch("sys.stderr", new=io.StringIO()):
                with self.assertRaises(SystemExit) as error:
                    SCREEN.parse_args(required + supplied)
                self.assertEqual(error.exception.code, 2)
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(ValueError, "confirmation requires explicit"):
                SCREEN.run(
                    Path("missing"),
                    Path("missing"),
                    SCREEN.CANDIDATE_ID,
                    Path(temp) / "out",
                    players=3,
                    opponent="balanced",
                    first_seed=0,
                    seeds=64,
                )

    def test_two_chair_failure_cancels_peer_before_its_next_chunk(self):
        cancellation = threading.Event()
        both_started = threading.Barrier(2)

        def fail_candidate(command, **kwargs):
            both_started.wait(timeout=2)
            if "joint-balanced" in command[command.index("--seats") + 1]:
                raise ValueError("invalid candidate chunk")
            self.assertTrue(cancellation.wait(timeout=2))
            synthetic_native(command, **kwargs)

        shards = SCREEN.schedule(SCREEN.CANDIDATE_ID, 3, "balanced", 900000, 64)
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            (output / shards[0]["stratum"]).mkdir()
            progress = io.StringIO()
            with patch.object(SCREEN, "Event", return_value=cancellation), patch.object(
                SCREEN.subprocess, "run", side_effect=fail_candidate
            ) as run:
                with self.assertRaises((ValueError, RuntimeError)):
                    SCREEN.play(
                        shards,
                        dict(candidate=Path("sim"), baseline=Path("base")),
                        dict(candidate="test", baseline="test"),
                        output,
                        progress,
                    )
            self.assertTrue(cancellation.is_set())
            self.assertEqual(run.call_count, 2)
            events = [json.loads(line) for line in progress.getvalue().splitlines()]
            self.assertEqual(sum(event["status"] == "started" for event in events), 2)
            self.assertEqual(events[-1]["status"], "failed")
            peer = output / shards[0]["stratum"] / "chunks/baseline-seat0"
            self.assertTrue((peer / "chunk-000.receipt.json").exists())
            self.assertFalse((peer / "chunk-001.command.json").exists())

    def test_current_repo_source_root_and_explicit_freeze_locks(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            binary = root / "sim"
            binary.write_bytes(b"fresh candidate")
            baseline = root / "baseline"
            baseline.write_bytes(b"fresh baseline")
            (root / "source.tar.gz").write_bytes(b"baseline source archive")
            locks = dict(
                candidate_sha256=SCREEN.digest(binary),
                baseline_sha256=SCREEN.digest(baseline),
                baseline_source_commit="4737471",
            )
            output = root / "result"
            output.mkdir()
            frozen, provenance = SCREEN.freeze_inputs(
                binary, baseline, output, SCREEN.ROOT, **locks
            )
            self.assertEqual(
                SCREEN.digest(frozen["candidate"]), locks["candidate_sha256"]
            )
            self.assertEqual(
                SCREEN.digest(frozen["baseline"]), locks["baseline_sha256"]
            )
            self.assertEqual(provenance["baselineSourceCommit"], "4737471")
            self.assertFalse((output / "source/.git").exists())
            self.assertFalse((output / "source/Packages/CatanAI/.build").exists())
            for name, expected in provenance["sourceSHA256"].items():
                self.assertEqual(SCREEN.digest(SCREEN.ROOT / name), expected)
            for arm in ("candidate", "baseline"):
                with self.subTest(arm=arm), self.assertRaisesRegex(
                    ValueError, "locked hash"
                ):
                    SCREEN.freeze_inputs(
                        binary,
                        baseline,
                        root / "rejected",
                        SCREEN.ROOT,
                        **{**locks, arm + "_sha256": "0" * 64},
                    )
            self.assertFalse((root / "rejected").exists())

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
                    (
                        SCREEN.CANDIDATE_ID
                        if shard["arm"] == "candidate"
                        else SCREEN.BASELINE_ID
                    ),
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
        program = f"#!{sys.executable}\n" + """import json,sys
a=sys.argv[1:]
get=lambda key:a[a.index(key)+1]
n=int(get('--players')); names=get('--seats').split(',')
ids=['experimental-joint-balanced-v1' if s=='joint-balanced' else 'heuristic-'+s for s in names]
for seed in range(int(get('--seed')),int(get('--seed'))+int(get('--games'))):
 print(json.dumps(dict(schemaVersion=5,buildID=get('--build-id'),seed=seed,playerCount=n,
 victoryPointTarget=10,boardMode='randomized',policies=ids,winner=seed%n,moves=100,
 vp=[10]*n,fingerprint='0123456789abcdef',behavior=[{} for _ in range(n)])))
"""
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            binary = root / "fake-sim"
            binary.write_text(program)
            binary.chmod(0o755)
            (root / "source.tar.gz").write_bytes(b"synthetic source archive")
            output = root / "result"
            with patch.object(
                SCREEN, "BASELINE_SHA256", SCREEN.digest(binary)
            ), patch.object(SCREEN, "CANDIDATE_SHA256", SCREEN.digest(binary)):
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
