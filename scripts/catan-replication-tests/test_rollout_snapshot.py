"""Exercise the executed snapshot patch, not a separate implementation of it."""

import hashlib
import importlib
import json
import os
import sys
import tempfile
import textwrap
import unittest
from collections import defaultdict
from contextlib import ExitStack
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import numpy as np
import torch

import catan_training_experiment as experiment

supervisor = importlib.import_module("profile-catan-training")
profiler = importlib.import_module("profile_catan_worker")


class RolloutSnapshotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.original = (
            Path(os.environ["CATAN_UPSTREAM"]) / "training/ppo.py"
        ).read_text()

    def transformed(self, mode: str) -> str:
        return experiment.transform(self.original, mode, 3)

    def open_records(self, mode: str, state: dict) -> None:
        source = self.transformed(mode)
        snippet = source.split("                # Open a transition per row", 1)[1]
        snippet = "                # Open a transition per row" + snippet
        snippet = snippet.split("                obs, masks, seats, rewards", 1)[0]
        exec(textwrap.dedent(snippet), state)

    def state(self) -> dict:
        return {
            "args": SimpleNamespace(num_envs=2),
            "pending": {},
            "chains": defaultdict(list),
            "seats": np.array([0, 2]),
            "obs": np.arange(8, dtype=np.float32).reshape(2, 4),
            "masks": np.array([[True, False], [False, True]]),
            "acts_np": np.array([0, 1]),
            "logps_np": np.array([0.1, 0.2]),
            "values_np": np.array([0.3, 0.4]),
        }

    def test_pinned_patch_changes_only_limit_and_snapshot_storage(self) -> None:
        self.assertEqual(
            hashlib.sha256(self.original.encode()).hexdigest(), experiment.PPO_SHA256
        )
        control = self.transformed("row")
        self.assertEqual(
            control,
            self.original.replace(
                "while time.time() < deadline:",
                "while update < 3 and time.time() < deadline:",
            ),
        )
        candidate = self.transformed("batch")
        self.assertIn('"obs": snapshot_obs[i], "mask": snapshot_masks[i]', candidate)
        self.assertIn(
            "snapshot_obs, snapshot_masks = obs.copy(), masks.copy()", candidate
        )
        compile(candidate, "experiment.py", "exec")

    def test_unknown_source_and_invalid_limits_fail_closed(self) -> None:
        with self.assertRaisesRegex(ValueError, "SHA"):
            experiment.transform(self.original + "\n", "batch", 3)
        for mode, updates in (("other", 3), ("batch", 0), ("row", -1), ("row", 101)):
            with (
                self.subTest(mode=mode, updates=updates),
                self.assertRaises(ValueError),
            ):
                experiment.transform(self.original, mode, updates)

    def test_pending_snapshots_survive_source_overwrite_and_next_update(self) -> None:
        for mode in ("row", "batch"):
            with self.subTest(mode=mode):
                state = self.state()
                expected_obs, expected_mask = state["obs"].copy(), state["masks"].copy()
                self.open_records(mode, state)
                first = state["pending"][(0, 0)]
                state["obs"].fill(-10)
                state["masks"].fill(False)
                state["pending"][(0, 0)]["reward_set"] = True
                self.open_records(mode, state)
                self.assertIs(state["chains"][(0, 0)][0], first)
                np.testing.assert_array_equal(first["obs"], expected_obs[0])
                np.testing.assert_array_equal(first["mask"], expected_mask[0])
                self.assertEqual(first["next_value"], state["values_np"][0])
                self.assertFalse(np.shares_memory(first["obs"], state["obs"]))

    def test_hash_covers_tensor_shape_dtype_and_all_optimizer_fields(self) -> None:
        original = {
            "model": torch.arange(4),
            "optimizer": {"state": {0: {"step": 1.0}}, "lr": 0.1},
        }
        reordered = {
            "optimizer": original["optimizer"],
            "model": original["model"].clone(),
        }
        baseline = experiment.state_digest(original)
        self.assertEqual(baseline, experiment.state_digest(reordered))
        for changed in (
            dict(original, model=original["model"].reshape(2, 2)),
            dict(original, model=original["model"].float()),
            dict(original, optimizer={"state": {0: {"step": 2.0}}, "lr": 0.1}),
            dict(original, optimizer={"state": {0: {"step": 1.0}}, "lr": 0.2}),
        ):
            self.assertNotEqual(baseline, experiment.state_digest(changed))

    def test_equal_work_validation_rejects_early_normal_exit(self) -> None:
        valid = {"updates": 3, "steps": 3 * 256 * 96, "config": {}}
        experiment.validate_work(valid, 3)
        for changed in (dict(valid, updates=2), dict(valid, steps=1)):
            with self.assertRaisesRegex(ValueError, "equal-update"):
                experiment.validate_work(changed, 3)

    def save_test_checkpoint(
        self, run: Path, filename_update: int, recorded_update: int
    ) -> None:
        checkpoints = run / "checkpoints"
        checkpoints.mkdir(exist_ok=True)
        checkpoint = {
            "global_step": recorded_update * 256 * 96,
            "model_state": {"weight": torch.tensor([1.0])},
            "optimizer_state": {"state": {}, "lr": 0.1},
        }
        torch.save(
            checkpoint, checkpoints / f"step_{filename_update * 256 * 96:010d}.pt"
        )

    def test_checkpoint_inventory_requires_periodic_and_final_steps(self) -> None:
        cases = (
            (3, (), False),
            (17, (16,), False),
            (17, (17,), False),
            (17, (3, 16, 17), False),
            (3, (3,), True),
            (16, (16,), True),
            (17, (16, 17), True),
        )
        for updates, saved_updates, valid in cases:
            with (
                self.subTest(updates=updates, saved=saved_updates),
                tempfile.TemporaryDirectory() as directory,
            ):
                run = Path(directory)
                for saved_update in saved_updates:
                    self.save_test_checkpoint(run, saved_update, saved_update)
                if not valid:
                    with self.assertRaisesRegex(ValueError, "checkpoint inventory"):
                        experiment.checkpoint_digests(run, updates)
                    continue
                result = experiment.checkpoint_digests(run, updates)
                self.assertEqual(
                    set(result), {str(index * 256 * 96) for index in saved_updates}
                )
                for digests in result.values():
                    self.assertEqual(
                        digests,
                        {
                            "model_state": experiment.state_digest(
                                {"weight": torch.tensor([1.0])}
                            ),
                            "optimizer_state": experiment.state_digest(
                                {"state": {}, "lr": 0.1}
                            ),
                        },
                    )

    def test_checkpoint_inventory_rejects_duplicate_and_misnamed_steps(self) -> None:
        for entries in (((16, 16), (17, 16)), ((16, 17),)):
            with (
                self.subTest(entries=entries),
                tempfile.TemporaryDirectory() as directory,
            ):
                run = Path(directory)
                for filename_update, recorded_update in entries:
                    self.save_test_checkpoint(run, filename_update, recorded_update)
                with self.assertRaisesRegex(ValueError, "duplicate or misnamed"):
                    experiment.checkpoint_digests(run, 17)

    def test_memory_guard_still_signals_when_abort_receipt_write_fails(self) -> None:
        with (
            patch.object(experiment.threading, "Event") as event,
            patch.object(experiment.threading, "Thread") as thread,
            patch.object(
                experiment,
                "peak_rss_bytes",
                return_value=experiment.RSS_ABORT_BYTES + 1,
            ),
            patch.object(
                Path, "write_text", autospec=True, side_effect=OSError("disk full")
            ) as write,
            patch.object(experiment.os, "kill") as kill,
        ):
            event.return_value.wait.return_value = False
            with experiment.memory_guard(Path("/tmp/unused-memory-guard-test")):
                # Invoke the real monitor synchronously so its failure is observable.
                monitor = thread.call_args.kwargs["target"]
                with self.assertRaisesRegex(OSError, "disk full"):
                    monitor()
                write.assert_called_once()
                kill.assert_called_once_with(os.getpid(), experiment.signal.SIGTERM)
            event.return_value.set.assert_called_once()
            thread.return_value.join.assert_called_once_with(
                timeout=experiment.MEMORY_THREAD_JOIN_SECONDS
            )

    def test_default_modes_omit_experiment_metrics_and_cuda_memory_calls(self) -> None:
        for mode in ("control", "cprofile"):
            with (
                self.subTest(mode=mode),
                tempfile.TemporaryDirectory() as directory,
                ExitStack() as stack,
            ):
                source = Path(directory)
                output = source / "output"
                output.mkdir()
                run = source / "training/runs" / f"fixture-profile-{mode}-fixed"
                run.mkdir(parents=True)
                for filename in ("metrics.jsonl", "config.json"):
                    (run / filename).write_text("{}\n")
                options = SimpleNamespace(
                    source=source,
                    output=output,
                    mode=mode,
                    device="cuda",
                    updates=None,
                    seconds=1,
                    gpu_lock=None,
                    parent=source / "parent.pt",
                    parent_sha256="0" * 64,
                    binding_sha256="0" * 64,
                    snapshot_mode="row",
                )
                for owner, name, value in (
                    (profiler.uuid, "uuid4", SimpleNamespace(hex="fixed")),
                    (profiler, "check_parent", None),
                    (profiler.reconstruction.replay, "check_inputs", (None, None)),
                    (profiler.reconstruction.replay, "provenance", {}),
                    (profiler.reconstruction, "digest", "0" * 64),
                    (
                        profiler.reconstruction,
                        "command_for_stage",
                        [sys.executable, "-u", "-c", "pass"],
                    ),
                    (profiler.reconstruction, "inspect_checkpoint", {"updates": 1}),
                    (profiler, "device_metadata", {"device": "cuda"}),
                    (profiler.signal, "signal", None),
                ):
                    stack.enter_context(patch.object(owner, name, return_value=value))
                for owner, names in (
                    (
                        experiment,
                        (
                            "entry",
                            "validate_work",
                            "validate_metrics",
                            "checkpoint_digests",
                            "peak_rss_bytes",
                        ),
                    ),
                    (
                        torch.cuda,
                        (
                            "reset_peak_memory_stats",
                            "max_memory_allocated",
                            "max_memory_reserved",
                        ),
                    ),
                ):
                    for name in names:
                        stack.enter_context(
                            patch.object(
                                owner,
                                name,
                                side_effect=AssertionError(
                                    f"unexpected default-mode call: {name}"
                                ),
                            )
                        )
                profiler.worker(options)
                manifest = json.loads((output / "manifest.json").read_text())
                profile = json.loads((output / "profile.json").read_text())
                result = json.loads((output / "result.json").read_text())
                self.assertNotIn("experiment", manifest)
                self.assertNotIn("worker_pid", manifest)
                self.assertNotIn("peak_rss_bytes", profile)
                self.assertTrue(profile["trainer_returned_normally"])
                self.assertEqual(
                    set(result),
                    {
                        "schema_version",
                        "upstream_run",
                        "checkpoint",
                        "finite_checkpoint_and_metrics",
                        "strength_claim",
                    },
                )

    def rollout_state(self) -> dict:
        state = self.state()
        state.update(np=np, torch=torch, device=torch.device("cpu"), global_step=0)
        constants = self.transformed("row").split("GAMMA =", 1)[1]
        exec("GAMMA =" + constants.split("def parse_args", 1)[0], state)
        return state

    def step_records(
        self,
        mode: str,
        state: dict,
        next_seats: tuple,
        rewards: tuple,
        dones: tuple = (False, False),
        terminals: tuple = ((0, 0, 0, 0), (0, 0, 0, 0)),
    ) -> None:
        """Execute the real open/step/reward code against overwritten input buffers."""
        decision = state["global_step"] // state["args"].num_envs
        state["acts_np"] = np.array([2 * decision, 2 * decision + 1])
        state["values_np"] = np.array([decision + 0.25, decision + 0.5])
        state["logps_np"] = np.array([-decision - 0.25, -decision - 0.5])

        def step(actions: np.ndarray) -> tuple:
            np.testing.assert_array_equal(actions, state["acts_np"])
            # Stronger than today's Rust contract: a missing snapshot is observable.
            state["obs"].fill(-1000)
            state["masks"].fill(False)
            obs = np.arange(8, dtype=np.float32).reshape(2, 4) + 10 * (decision + 1)
            masks = np.array([[True, False], [False, True]])
            return (
                obs,
                masks,
                np.array(next_seats),
                np.array(rewards),
                np.array(dones),
                np.array(terminals),
            )

        state["env"] = SimpleNamespace(step=step)
        anchor = "                # Open a transition per row"
        snippet = anchor + self.transformed(mode).split(anchor, 1)[1]
        snippet = snippet.split("                for turns, winner, vps, cap", 1)[0]
        exec(textwrap.dedent(snippet), state)

    def flush_batch(self, mode: str, state: dict) -> None:
        """Keep the actual empty-batch continue and CPU tensor assembly intact."""
        anchor = "        # ------------------------------------------- GAE per chain + flush"
        snippet = anchor + self.transformed(mode).split(anchor, 1)[1]
        snippet = snippet.split(
            "        # --------------------------------------------------- PPO update",
            1,
        )[0]
        wrapped = "for _snippet_update in range(1):\n"
        exec(wrapped + textwrap.indent(textwrap.dedent(snippet), "    "), state)

    def assert_same_batch(self, control: dict, candidate: dict) -> None:
        self.assertEqual(control["n"], candidate["n"])
        self.assertEqual(list(control["batch"]), list(candidate["batch"]))
        for name, rows in control["batch"].items():
            with self.subTest(batch_field=name):
                expected, actual = np.array(rows), np.array(candidate["batch"][name])
                self.assertEqual(expected.shape, actual.shape)
                self.assertEqual(expected.dtype, actual.dtype)
                self.assertEqual(expected.tobytes(), actual.tobytes())
        if control["n"]:
            for name in (
                "b_obs",
                "b_mask",
                "b_act",
                "b_logp",
                "b_val",
                "b_adv",
                "b_ret",
            ):
                with self.subTest(tensor=name):
                    self.assertEqual(control[name].dtype, candidate[name].dtype)
                    self.assertTrue(torch.equal(control[name], candidate[name]))

    def test_terminal_flushes_all_pending_seats_before_auto_reset(self) -> None:
        states = {}
        for mode in ("row", "batch"):
            with self.subTest(mode=mode):
                state = states[mode] = self.rollout_state()
                for next_seats in ((1, 3), (2, 0), (3, 1)):
                    self.step_records(mode, state, next_seats, (0, 0))
                old = {seat: state["pending"][(0, seat)] for seat in range(3)}
                self.step_records(
                    mode,
                    state,
                    (0, 2),
                    (999, 0.5),
                    (True, False),
                    ((1, -2, 3, -4), (99, 99, 99, 99)),
                )
                self.assertEqual(
                    set(state["pending"]), {(1, seat) for seat in range(4)}
                )
                for seat, reward in enumerate((1, -2, 3, -4)):
                    record = state["chains"][(0, seat)][0]
                    if seat in old:
                        self.assertIs(record, old[seat])
                    self.assertTrue(record["done"])
                    self.assertTrue(record["reward_set"])
                    self.assertEqual(record["reward"], reward)
                    self.assertEqual(record["next_value"], 0.0)
                    np.testing.assert_array_equal(
                        record["obs"], np.arange(4) + 10 * seat
                    )
                self.assertEqual(state["pending"][(1, 2)]["reward"], 0.5)
                self.assertTrue(
                    all(not rec["done"] for rec in state["pending"].values())
                )
                self.flush_batch(mode, state)
                self.assertEqual(state["batch"]["action"], [0, 2, 4, 6])
                self.assertEqual(state["batch"]["ret"], [1, -2, 3, -4])
        self.assert_same_batch(states["row"], states["batch"])

    def test_pending_crosses_updates_with_exact_repeated_seat_gae_order(self) -> None:
        states = {mode: self.rollout_state() for mode in ("row", "batch")}
        delayed = {}
        for mode, state in states.items():
            self.step_records(mode, state, (0, 1), (0.5, 0))
            delayed[mode] = state["pending"][(1, 2)]
            self.step_records(mode, state, (0, 1), (0.75, 1.25))
            self.step_records(mode, state, (0, 1), (1, 1.5))
            self.flush_batch(mode, state)
            self.assertEqual(state["batch"]["action"], [2, 0, 3])
            self.assertIs(state["pending"][(1, 2)], delayed[mode])
            self.assertNotIn("reward_set", delayed[mode])
            self.assertTrue(all(not chain for chain in state["chains"].values()))
        self.assert_same_batch(states["row"], states["batch"])

        for mode, state in states.items():
            self.step_records(mode, state, (0, 1), (1.25, 1.75))
            self.step_records(mode, state, (0, 2), (1.5, 2))
            self.flush_batch(mode, state)
            self.assertEqual(state["batch"]["action"], [6, 4, 7, 5])
            self.assertIs(state["pending"][(1, 2)], delayed[mode])
            self.assertTrue(delayed[mode]["reward_set"])
            self.assertEqual(delayed[mode]["reward"], 2)
            self.assertEqual(delayed[mode]["value"], 0.5)
            self.assertEqual(delayed[mode]["logp"], -0.5)
            np.testing.assert_array_equal(delayed[mode]["obs"], np.arange(4, 8))
        self.assert_same_batch(states["row"], states["batch"])

        for mode, state in states.items():
            self.step_records(
                mode,
                state,
                (0, 2),
                (999, 3),
                (True, False),
                ((100, 200, 300, 400), (0, 0, 0, 0)),
            )
            self.assertIs(state["chains"][(1, 2)][0], delayed[mode])
            self.step_records(
                mode,
                state,
                (0, 2),
                (999, 999),
                (True, True),
                ((-5, 6, 7, 8), (5, 6, 7, 8)),
            )
            self.assertEqual(state["pending"], {})
            self.flush_batch(mode, state)
            self.assertEqual(state["batch"]["action"], [12, 10, 8, 9, 13, 11, 1])
            np.testing.assert_allclose(
                state["batch"]["ret"],
                [-5, 100, 96.7625, 6, 7, 9.975, 11.75125],
                rtol=0,
                atol=1e-12,
            )
        self.assert_same_batch(states["row"], states["batch"])

    def test_empty_updates_keep_pending_until_the_seat_returns(self) -> None:
        states = {}
        for mode in ("row", "batch"):
            state = states[mode] = self.rollout_state()
            self.step_records(mode, state, (1, 3), (0, 0))
            pending = dict(state["pending"])
            self.flush_batch(mode, state)
            self.assertEqual(state["n"], 0)
            self.assertNotIn("b_obs", state)
            self.step_records(mode, state, (0, 2), (0.25, 0.5))
            self.flush_batch(mode, state)
            self.assertEqual(state["n"], 0)
            for key, record in pending.items():
                self.assertIs(state["pending"][key], record)
                self.assertTrue(record["reward_set"])
            self.step_records(mode, state, (1, 3), (0.75, 1))
            self.flush_batch(mode, state)
            self.assertEqual(state["batch"]["action"], [0, 1])
            np.testing.assert_array_equal(
                state["batch"]["obs"], np.arange(8).reshape(2, 4)
            )
        self.assert_same_batch(states["row"], states["batch"])


if __name__ == "__main__":
    unittest.main()
