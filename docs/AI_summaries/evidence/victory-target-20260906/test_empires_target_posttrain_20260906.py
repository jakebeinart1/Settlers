"""Fixture-only checks: never call an exporter, native sim, or live VecEnv."""

import argparse
import copy
import importlib.util
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import torch

spec = importlib.util.spec_from_file_location(
    "posttrain", "/tmp/empires-target-posttrain-20260906.py"
)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def model_state():
    shapes = (
        (512, 1350),
        (512,),
        (512, 512),
        (512,),
        (299, 512),
        (299,),
        (1, 512),
        (1,),
    )
    return {key: torch.zeros(shape) for key, shape in zip(runner.TENSOR_KEYS, shapes)}


def export_bytes(state):
    return (
        struct.pack("<4s4I", b"CTNN", 1, 1350, 299, 512)
        + b"".join(
            state["model_state"][key].numpy().astype("<f4").tobytes()
            for key in runner.TENSOR_KEYS
        )
        + bytes(4 * (1350 + 1 + 8))
    )


def arm_fixture(root, name="seed0-control7", seed=0, target=7):
    directory = root / name
    directory.mkdir()
    checkpoints = directory / "run/checkpoints"
    checkpoints.mkdir(parents=True)
    parent = root / "parent.pt"
    if not parent.exists():
        torch.save(
            {"optimizer_state": {"state": {0: {"step": torch.tensor(2.0)}}}}, parent
        )
    config = {
        key.replace("-", "_"): value
        for key, value in runner.reconstruction.TRAINING_FLAGS.items()
    }
    config.update(
        seed=seed,
        victory_target=target,
        vp_delta=0,
        vp_delta_final=None,
        minutes=10,
        device="cuda",
        resume=str(parent),
    )
    state = dict(
        model_state=model_state(),
        optimizer_state={"state": {0: {"step": torch.tensor(5.0)}}},
        global_step=runner.STEPS,
        config=config,
        obs_dim=1350,
        num_actions=299,
        obs_version=1,
        codec_version=1,
        engine_commit=runner.replay.SOURCE_COMMIT,
    )
    path = checkpoints / f"step_{runner.STEPS:010d}.pt"
    torch.save(state, path)
    (checkpoints / "latest.pt").symlink_to(path.name)
    rows = []
    for index in range(1, 801):
        rows.append({"t": "train", "step": index * 256 * 96})
        if index % 16 == 0:
            rows.extend(
                {"t": "eval", "step": index * 256 * 96, "vs": label}
                for label in ("random-3", "heuristic-v1-3")
            )
    rows.extend(
        {"t": "eval", "step": runner.STEPS, "vs": label}
        for label in ("random-3", "heuristic-v1-3")
    )
    rows.extend((dict(t="game", cap=False), dict(t="game", cap=True)))
    (checkpoints.parent / "metrics.jsonl").write_text(
        "\n".join(json.dumps(row) for row in rows)
    )
    (directory / "run.launcher.log").write_text(
        "\n".join(
            f"update {i} | step {i * 256 * 96:,} | 42 sps | ent 1 | ev 0 | clip 0 | batch {i + 20000:,}"
            for i in range(1, 801)
        )
    )
    evidence = dict(
        checkpoint=str(path.resolve()),
        checkpoint_sha256=runner.digest(path),
        steps=runner.STEPS,
        updates=800,
        config=config,
        metrics_sha256=runner.digest(checkpoints.parent / "metrics.jsonl"),
    )
    inventory = {str(index * 256 * 96): {} for index in range(16, 801, 16)}
    inventory[str(runner.STEPS)] = {
        key: runner.experiment.state_digest(state[key])
        for key in ("model_state", "optimizer_state")
    }
    manifest = dict(
        parent=str(parent),
        parent_sha256=runner.digest(parent),
        mode="none",
        training_seconds=600,
        watchdog_seconds=720,
        experiment=dict(
            training_seed=seed,
            victory_target=target,
            updates=800,
            snapshot_mode="row",
            long_experiment=True,
        ),
        upstream=dict(
            source_commit=runner.replay.SOURCE_COMMIT,
            trainer_sha256=runner.experiment.PPO_SHA256,
        ),
    )
    result = dict(
        checkpoint=evidence,
        upstream_run=str(checkpoints.parent),
        finite_checkpoint_and_metrics=True,
        checkpoint_content_digests=inventory,
    )
    for filename, value in (
        ("manifest.json", manifest),
        ("result.json", result),
        ("config.json", config),
    ):
        runner.write_json(directory / filename, value)
    runner.write_json(
        directory / "run.watchdog.json", dict(state="complete", exit_code=0)
    )
    return state, manifest, result


class PosttrainTests(unittest.TestCase):
    def test_provenance_records_durable_protocol_hash_without_latest_doc_gate(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            protocol = root / "frozen-protocol.md"
            protocol.write_text("fixture frozen protocol")
            binding = root / "fixture.so"
            binding.write_bytes(b"fixture binding")
            args = argparse.Namespace(
                source=Path(runner.replay.ppo.__file__).resolve().parents[1],
                binding_sha256=runner.digest(binding),
                stage="export",
            )
            with mock.patch.object(runner, "ROOT", root), mock.patch.object(
                runner.replay, "check_inputs", return_value=(Path("/oracle"), binding)
            ):
                metadata = runner.provenance(args)
                self.assertEqual(metadata["protocol_commit"], "0ba5ab0")
                self.assertEqual(
                    metadata["files_sha256"][str(protocol)], runner.digest(protocol)
                )
                self.assertEqual(
                    metadata["retention_protocol"]["evaluation_seeds"], (961201, 961202)
                )
                self.assertNotIn("777", json.dumps(metadata["retention_protocol"]))
                protocol.write_text(
                    "different fixture: provenance, not a fixed hash gate"
                )
                self.assertNotEqual(runner.provenance(args), metadata)

    def test_accounting_rejects_missing_batch_and_preserves_unequal_work(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state, manifest, _ = arm_fixture(root)
            directory = root / "seed0-control7"
            parent = Path(manifest["parent"])
            original = runner.training_accounting(
                directory, directory / "run", state, parent
            )
            state["optimizer_state"]["state"][0]["step"] += 11
            changed = runner.training_accounting(
                directory, directory / "run", state, parent
            )
            self.assertEqual(changed["adam_counters"]["0"]["delta"], 14)
            self.assertEqual(original["batch_sizes"], changed["batch_sizes"])
            log = directory / "run.launcher.log"
            log.write_text("\n".join(log.read_text().splitlines()[:-1]))
            with self.assertRaisesRegex(ValueError, "missing/reordered batches"):
                runner.training_accounting(directory, directory / "run", state, parent)

    def test_successful_final_arm_and_fail_closed_mutations(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state, manifest, result = arm_fixture(root)
            with mock.patch.object(runner, "ROOT", root), mock.patch.object(
                runner, "PARENT_SHA", manifest["parent_sha256"]
            ):
                arm, loaded = runner.load_arm("seed0-control7", 0, 7)
                self.assertEqual(loaded["global_step"], 19_660_800)
                self.assertEqual(arm["training_seed"], 0)
                self.assertEqual(
                    arm["accounting"]["batch_sizes"], list(range(20001, 20801))
                )
                self.assertEqual(
                    arm["accounting"]["adam_counters"]["0"],
                    dict(parent=2.0, final=5.0, delta=3.0),
                )
                self.assertEqual(
                    (
                        arm["accounting"]["training_episodes"],
                        arm["accounting"]["training_caps"],
                    ),
                    (2, 1),
                )
                path = root / "seed0-control7/result.json"
                for field, value in (
                    ("updates", 799),
                    ("steps", 1),
                    ("checkpoint_sha256", "wrong"),
                ):
                    mutated = copy.deepcopy(result)
                    mutated["checkpoint"][field] = value
                    path.write_text(json.dumps(mutated))
                    with self.subTest(field=field), self.assertRaises(ValueError):
                        runner.load_arm("seed0-control7", 0, 7)
                path.write_text(json.dumps(result))
                receipt = root / "seed0-control7/run.watchdog.json"
                receipt.write_text(json.dumps(dict(state="failed", exit_code=1)))
                with self.assertRaises(ValueError):
                    runner.load_arm("seed0-control7", 0, 7)

    def test_configuration_and_nonfinite_state_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            state, manifest, result = arm_fixture(Path(tmp))
            for key, value in (
                ("seed", 1),
                ("victory_target", 10),
                ("vp_delta", 0.05),
                ("vp_delta_final", 0),
                ("minibatch", 2048),
            ):
                mutated = dict(state["config"], **{key: value})
                with self.subTest(key=key), self.assertRaises(ValueError):
                    runner.check_config(mutated, manifest, 0, 7)
            directory = Path(tmp) / "seed0-control7"
            for key in ("model_state", "optimizer_state"):
                mutated = copy.deepcopy(state)
                if key == "model_state":
                    mutated[key]["value.bias"][0] = float("nan")
                else:
                    mutated[key]["state"][0]["step"] = torch.tensor(float("inf"))
                torch.save(mutated, Path(result["checkpoint"]["checkpoint"]))
                with self.subTest(key=key), self.assertRaises(ValueError):
                    runner.reconstruction.inspect_checkpoint(directory / "run")

    def test_ctnn_exact_parameters_and_corrupt_probe_rejected(self):
        state = {"model_state": model_state()}
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "fixture.ctnn"
            original = export_bytes(state)
            path.write_bytes(original)
            self.assertTrue(
                runner.ctnn_parity(path, state)["all_parameter_bytes_exact"]
            )
            for offset, value in ((20, 1.0), (len(original) - 4, float("nan"))):
                mutated = bytearray(original)
                struct.pack_into("<f", mutated, offset, value)
                path.write_bytes(mutated)
                with self.subTest(offset=offset), self.assertRaises(ValueError):
                    runner.ctnn_parity(path, state)
            path.write_bytes(original + b"extra")
            with self.assertRaises(ValueError):
                runner.ctnn_parity(path, state)

    def test_export_uses_unchanged_exporter_and_leaves_native_probe_pending(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            state = {"model_state": model_state()}
            args = argparse.Namespace(output=output, source=Path("/upstream"))
            arm = {"arm": "seed0-control7", "checkpoint": "/final800.pt"}

            def fake_export(command, source, log, timeout):
                self.assertEqual(
                    command,
                    [
                        sys.executable,
                        "/upstream/training/export_net.py",
                        "/final800.pt",
                        str(output / "seed0-control7.ctnn"),
                    ],
                )
                self.assertEqual(timeout, 300)
                Path(command[-1]).write_bytes(export_bytes(state))

            with mock.patch.object(
                runner.reconstruction, "run_logged", side_effect=fake_export
            ) as exporter:
                result = runner.export_arm(args, arm, state)
                self.assertTrue(result["probe_floats_finite"])
                self.assertTrue(result["native_probe"].startswith("pending:"))
                self.assertEqual(exporter.call_count, 1)
                with self.assertRaises(ValueError):
                    runner.export_arm(args, arm, state)

    def test_retention_preserves_overshoot_explicit_seeds_and_caps_as_nonwins(self):
        with tempfile.TemporaryDirectory() as tmp:
            rows = [dict(winner=0, capped=False, ordinal=index) for index in range(197)]
            rows[0]["capped"] = True
            arm = dict(arm="seed1-target10", training_seed=1, training_target=10)
            network = object()

            def fake_collect(net, path, **kwargs):
                self.assertIs(net, network)
                self.assertEqual(kwargs, dict(device="cpu", seed=961202, games=192))
                path.write_text("\n".join(json.dumps(row) for row in rows))
                return rows

            with mock.patch.object(
                runner.replay, "collect_outcomes", side_effect=fake_collect
            ):
                sample = runner.retention_sample(arm, network, 961202, Path(tmp))
            self.assertEqual(
                (
                    sample["evaluation_seed"],
                    sample["games"],
                    sample["wins"],
                    sample["caps"],
                ),
                (961202, 197, 196, 1),
            )

    def test_pooled_actual_counts_exact_margin_caps_and_inventory(self):
        samples = [
            dict(
                training_seed=seed,
                training_target=target,
                evaluation_seed=evaluation,
                wins=100 if target == 7 else 90,
                games=200,
                caps=0,
            )
            for seed in (0, 1)
            for target in (7, 10)
            for evaluation in runner.EVAL_SEEDS
        ]
        self.assertTrue(
            all(
                row["retention_gate_passed"]
                for row in runner.retention_comparisons(samples)
            )
        )
        samples[2]["wins"] -= 1
        self.assertFalse(
            runner.retention_comparisons(samples)[0]["retention_gate_passed"]
        )
        samples[2]["wins"] += 1
        samples[0]["caps"] = 1
        self.assertFalse(
            runner.retention_comparisons(samples)[0]["retention_gate_passed"]
        )
        samples[0]["caps"] = 0
        samples[0]["games"] = 220
        comparison = runner.retention_comparisons(samples)[0]
        self.assertAlmostEqual(comparison["loss"], 200 / 420 - 180 / 400)
        for broken in (samples[:-1], samples + [samples[0]]):
            with self.assertRaises(ValueError):
                runner.retention_comparisons(broken)

    def test_both_stages_refuse_existing_output_before_any_execution(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = [
                "runner",
                "retention",
                "--source",
                tmp,
                "--output",
                tmp,
                "--binding-sha256",
                "fixture",
            ]
            with mock.patch.object(sys, "argv", base), mock.patch.object(
                runner.replay, "collect_outcomes"
            ) as collect:
                with self.assertRaises(FileExistsError):
                    runner.main()
                collect.assert_not_called()
            base[1] = "export"
            with mock.patch.object(sys, "argv", base), self.assertRaises(
                FileExistsError
            ):
                runner.main()

    def test_retention_main_four_models_eight_fixed_calls_with_failed_cap_gate(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "retention"
            loaded = [
                (
                    dict(
                        arm=name,
                        training_seed=seed,
                        training_target=target,
                        checkpoint=f"/{name}.pt",
                        checkpoint_sha256="fixture",
                        parent="/parent.pt",
                        input_sha256={},
                    ),
                    {},
                )
                for name, seed, target in runner.ARMS
            ]
            samples = []

            def fake_sample(arm, network, seed, directory):
                row = dict(
                    arm,
                    evaluation_seed=seed,
                    games=192,
                    wins=96,
                    caps=int(seed == 961201),
                )
                samples.append((arm["arm"], seed))
                return row

            argv = [
                "runner",
                "retention",
                "--source",
                tmp,
                "--output",
                str(output),
                "--binding-sha256",
                "fixture",
            ]
            with mock.patch.object(sys, "argv", argv), mock.patch.object(
                runner, "load_arm", side_effect=loaded
            ), mock.patch.object(
                runner, "provenance", return_value={}
            ), mock.patch.object(
                runner, "digest", return_value="fixture"
            ), mock.patch.object(
                runner, "PARENT_SHA", "fixture"
            ), mock.patch.object(
                runner.replay, "make_policy"
            ) as make, mock.patch.object(
                runner, "retention_sample", side_effect=fake_sample
            ):
                with self.assertRaisesRegex(SystemExit, "Retention gate failed"):
                    runner.main()
                self.assertEqual(make.call_count, 4)
            self.assertEqual(
                samples,
                [(arm[0], seed) for arm in runner.ARMS for seed in runner.EVAL_SEEDS],
            )
            result = runner.read_json(output / "result.json")
            self.assertTrue(result["complete"])
            self.assertFalse(result["gate_passed"])
            self.assertEqual(len(result["results"]), 8)


if __name__ == "__main__":
    torch.set_num_threads(1)
    unittest.main(verbosity=2)
