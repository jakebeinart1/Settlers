#!/usr/bin/env python3
"""One-shot target experiment: four exports OR eight CPU retention samples.

Main runs each stage once under training_watchdog.py --seconds 300, using the
isolated upstream Python and repo/scripts:upstream/training on PYTHONPATH.
No retries, training or GPU. Native probe acceptance remains REQUIRED later
in Mac evaluate-bots.py; remote parity checks bytes and probe finiteness only.
"""

import argparse
import importlib
import json
import math
import os
import re
import struct
import sys
from fractions import Fraction
from pathlib import Path

import numpy as np
import torch

import catan_training_experiment as experiment

reconstruction = importlib.import_module("run-catan-reconstruction")
replay = reconstruction.replay
digest = replay.digest
ROOT = Path("/home/alex_ubuntu/empires-research/victory-target-20260906")
ARMS = (
    ("seed0-control7", 0, 7),
    ("seed0-target10", 0, 10),
    ("seed1-target10", 1, 10),
    ("seed1-control7", 1, 7),
)
UPDATES, STEPS, BUDGET = 800, 19_660_800, 300
EVAL_SEEDS, GAMES = (961201, 961202), 192
PARENT_SHA = "b2b65d569ef2e56bbca9e6f6ecfd41b4c0905842803e62c3aff2aeec7d96dace"
EXPORT_SHA = "ce74a024c0b1c9d52db6269f830c555935ccbfed42f21d9950fa7f9b569a7a7c"
TENSOR_KEYS = (
    "trunk.0.weight trunk.0.bias trunk.2.weight trunk.2.bias "
    "policy.weight policy.bias value.weight value.bias"
).split()


def read_json(path: Path) -> dict:
    return json.loads(
        path.read_text(),
        parse_float=reconstruction.finite_metric_number,
        parse_constant=reconstruction.finite_metric_number,
    )


def write_json(path: Path, value: object) -> None:
    with path.open("x") as handle:
        json.dump(value, handle, indent=2, sort_keys=True, allow_nan=False)
        handle.write("\n")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def check_config(config: dict, manifest: dict, seed: int, target: int) -> None:
    expected = {
        k.replace("-", "_"): v for k, v in reconstruction.TRAINING_FLAGS.items()
    }
    expected.update(
        seed=seed,
        victory_target=target,
        vp_delta=0,
        vp_delta_final=None,
        minutes=10,
        device="cuda",
        resume=manifest["parent"],
    )
    require(
        all(config.get(k) == v for k, v in expected.items()), "wrong training config"
    )
    require(manifest["experiment"]["snapshot_mode"] == "row", "wrong snapshot mode")


def training_accounting(directory: Path, run: Path, state: dict, parent: Path) -> dict:
    """Retain unequal batch/episode/Adam work; never compare states across targets."""
    matches = re.findall(
        r"^update (\d+) \| step ([\d,]+) \| .* \| batch ([\d,]+)$",
        (directory / "run.launcher.log").read_text(),
        re.MULTILINE,
    )
    batches = [tuple(int(v.replace(",", "")) for v in row) for row in matches]
    expected = [(i, i * 256 * 96) for i in range(1, UPDATES + 1)]
    require(
        [(i, step) for i, step, _ in batches] == expected, "missing/reordered batches"
    )
    rows = map(json.loads, (run / "metrics.jsonl").read_text().splitlines())
    games = [row for row in rows if row["t"] == "game"]
    before = torch.load(parent, map_location="cpu", weights_only=False)[
        "optimizer_state"
    ]["state"]
    after = state["optimizer_state"]["state"]
    require(set(before) == set(after), "Adam parameter inventory changed")
    counters = {}
    for key in before:
        start, end = float(before[key]["step"]), float(after[key]["step"])
        require(
            math.isfinite(start) and math.isfinite(end) and end >= start,
            "invalid Adam counter",
        )
        counters[str(key)] = dict(parent=start, final=end, delta=end - start)
    return dict(
        batch_sizes=[n for _, _, n in batches],
        completed_transitions=sum(n for _, _, n in batches),
        training_episodes=len(games),
        training_caps=sum(row["cap"] for row in games),
        adam_counters=counters,
    )


def load_arm(name: str, seed: int, target: int) -> tuple[dict, dict]:
    directory = ROOT / name
    result, manifest = read_json(directory / "result.json"), read_json(
        directory / "manifest.json"
    )
    receipt = read_json(directory / "run.watchdog.json")
    require(
        receipt["state"] == "complete"
        and receipt["exit_code"] == 0
        and result["finite_checkpoint_and_metrics"] is True,
        f"unsuccessful arm: {name}",
    )
    run = Path(result["upstream_run"])
    current = reconstruction.inspect_checkpoint(run)
    require(
        current == result["checkpoint"], "checkpoint/metrics changed after training"
    )
    require(Path(current["checkpoint"]).name == f"step_{STEPS:010d}.pt", "not final800")
    experiment.validate_work(
        current, UPDATES, training_seed=seed, victory_target=target
    )
    experiment.validate_metrics(run, UPDATES)
    check_config(current["config"], manifest, seed, target)
    parent = Path(manifest["parent"])
    require(
        manifest["parent_sha256"] == digest(parent) == PARENT_SHA, "wrong r2 parent"
    )
    require(
        manifest["upstream"]["trainer_sha256"] == experiment.PPO_SHA256,
        "wrong PPO source",
    )
    expected = {str(i * 256 * 96) for i in range(16, 801, 16)}
    inventory = result["checkpoint_content_digests"]
    require(set(inventory) == expected, "expected 50 saved checkpoint records")
    state = torch.load(current["checkpoint"], map_location="cpu", weights_only=False)
    keys = "obs_dim num_actions obs_version codec_version engine_commit".split()
    contract = tuple(state[k] for k in keys)
    require(
        contract == (1350, 299, 1, 1, replay.SOURCE_COMMIT), "wrong checkpoint contract"
    )
    for key in ("model_state", "optimizer_state"):
        require(
            experiment.state_digest(state[key]) == inventory[str(STEPS)][key],
            f"changed/nonfinite {key}",
        )
    names = "result.json manifest.json run.watchdog.json run.launcher.log".split()
    files = [directory / f for f in names]
    files += [Path(current["checkpoint"]), parent, run / "metrics.jsonl"]
    arm = dict(
        arm=name,
        training_seed=seed,
        training_target=target,
        **current,
        accounting=training_accounting(directory, run, state, parent),
        input_sha256={str(p): digest(p) for p in files},
    )
    return arm, state


def ctnn_parity(path: Path, state: dict) -> dict:
    blob = path.read_bytes()
    require(
        blob[:20] == struct.pack("<4s4I", b"CTNN", 1, 1350, 299, 512),
        "wrong CTNN header",
    )
    require(set(state["model_state"]) == set(TENSOR_KEYS), "unexpected tensors")
    cursor = 20
    for key in TENSOR_KEYS:
        tensor = state["model_state"][key]
        require(
            tensor.dtype == torch.float32 and bool(torch.isfinite(tensor).all()),
            f"invalid {key}",
        )
        expected = tensor.cpu().contiguous().numpy().astype("<f4").tobytes()
        require(
            blob[cursor : cursor + len(expected)] == expected,
            f"parameter mismatch: {key}",
        )
        cursor += len(expected)
    require(len(blob) == 4_438_528 == cursor + 4 * (1350 + 1 + 8), "wrong CTNN length")
    require(
        bool(np.isfinite(np.frombuffer(blob, dtype="<f4", offset=20)).all()),
        "nonfinite CTNN/probe",
    )
    return dict(
        ctnn=str(path),
        ctnn_sha256=digest(path),
        parameter_floats=(cursor - 20) // 4,
        all_parameter_bytes_exact=True,
        probe_floats_finite=True,
        native_probe="pending: Mac evaluate-bots.py must accept before games",
    )


def export_arm(args: argparse.Namespace, arm: dict, state: dict) -> dict:
    exported = args.output / f"{arm['arm']}.ctnn"
    require(not exported.exists(), "export already exists")
    command = [
        sys.executable,
        str(args.source / "training/export_net.py"),
        arm["checkpoint"],
        str(exported),
    ]
    reconstruction.run_logged(
        command, args.source, args.output / f"{arm['arm']}-export.log", BUDGET
    )
    return dict(arm=arm["arm"], command=command, **ctnn_parity(exported, state))


def retention_sample(arm: dict, network: object, seed: int, output: Path) -> dict:
    path = output / f"{arm['arm']}-eval-{seed}.jsonl"
    rows = replay.collect_outcomes(network, path, device="cpu", seed=seed, games=GAMES)
    require(len(rows) >= GAMES, "too few retention games")
    json.dumps(rows, allow_nan=False)
    valid = all(
        type(r["capped"]) is bool
        and r["winner"] in (-1, 0, 1, 2, 3)
        and (r["capped"] or r["winner"] in range(4))
        for r in rows
    )
    require(valid, "invalid outcome")
    return dict(
        arm=arm["arm"],
        training_seed=arm["training_seed"],
        training_target=arm["training_target"],
        evaluation_seed=seed,
        requested_games=GAMES,
        games=len(rows),
        wins=sum(r["winner"] == 0 and not r["capped"] for r in rows),
        caps=sum(r["capped"] for r in rows),
        outcomes_sha256=digest(path),
    )


def retention_comparisons(samples: list[dict]) -> list[dict]:
    comparisons = []
    for seed in (0, 1):
        totals = {}
        for target in (7, 10):
            rows = [
                r
                for r in samples
                if r["training_seed"] == seed and r["training_target"] == target
            ]
            require(
                sorted(r["evaluation_seed"] for r in rows) == list(EVAL_SEEDS),
                "missing/duplicate eval seed",
            )
            totals[target] = {
                k: sum(r[k] for r in rows) for k in ("wins", "games", "caps")
            }
        control, treatment = totals[7], totals[10]
        loss = Fraction(control["wins"], control["games"]) - Fraction(
            treatment["wins"], treatment["games"]
        )
        passed = loss <= Fraction(1, 20) and control["caps"] == treatment["caps"] == 0
        comparisons.append(
            dict(
                training_seed=seed,
                control7=control,
                treatment10=treatment,
                loss=float(loss),
                retention_gate_passed=passed,
            )
        )
    return comparisons


def provenance(args: argparse.Namespace) -> dict:
    _, binding = replay.check_inputs(args.source, args.binding_sha256)
    require(
        digest(args.source / "training/export_net.py") == EXPORT_SHA, "exporter changed"
    )
    require(
        (replay.VICTORY_TARGET, replay.LANES) == (7, 48), "retention contract changed"
    )
    files = [
        Path(__file__),
        Path(replay.__file__),
        Path(experiment.__file__),
        Path(reconstruction.__file__),
        args.source / "training/ppo.py",
        args.source / "training/export_net.py",
        binding,
        ROOT / "frozen-protocol.md",
    ]
    return dict(
        protocol_commit="0ba5ab0",
        stage=args.stage,
        budget_seconds=BUDGET,
        command=sys.argv,
        source_commit=replay.SOURCE_COMMIT,
        source=str(args.source),
        files_sha256={str(p): digest(p) for p in files},
        python=sys.version,
        torch=torch.__version__,
        numpy=np.__version__,
        device="cpu",
        torch_threads=replay.TORCH_THREADS,
        retention_protocol=dict(
            evaluation_seeds=EVAL_SEEDS,
            requested_games=GAMES,
            victory_target=7,
            lanes=48,
            visibility="perfect",
            policy_seat=0,
            opponents=["heuristic"] * 3,
            caps_are_nonwins=True,
            retain_overshoot=True,
            arrival_pairing=False,
            loss_margin=0.05,
        ),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("export", "retention"))
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--binding-sha256", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.source, args.output = args.source.resolve(), args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    torch.set_num_threads(replay.TORCH_THREADS)
    os.environ.update(
        OMP_NUM_THREADS=str(replay.TORCH_THREADS),
        MKL_NUM_THREADS=str(replay.TORCH_THREADS),
    )
    metadata = provenance(args)
    loaded = [load_arm(*arm) for arm in ARMS]
    require(
        len({arm["checkpoint"] for arm, _ in loaded}) == 4,
        "four separate checkpoints required",
    )
    write_json(
        args.output / "manifest.json", dict(**metadata, arms=[arm for arm, _ in loaded])
    )
    results = []
    for arm, state in loaded:
        if args.stage == "export":
            results.append(export_arm(args, arm, state))
        else:
            network = replay.make_policy(Path(arm["checkpoint"])).to("cpu")
            for seed in EVAL_SEEDS:
                sample = retention_sample(arm, network, seed, args.output)
                write_json(
                    args.output / f"{arm['arm']}-eval-{seed}-summary.json", sample
                )
                results.append(sample)
    require(provenance(args) == metadata, "stage provenance changed")
    for arm, _ in loaded:
        require(
            all(digest(Path(p)) == sha for p, sha in arm["input_sha256"].items()),
            "training inputs changed",
        )
    comparisons = retention_comparisons(results) if args.stage == "retention" else []
    passed = all(row["retention_gate_passed"] for row in comparisons)
    write_json(
        args.output / "result.json",
        dict(
            stage=args.stage,
            complete=True,
            results=results,
            comparisons=comparisons,
            gate_passed=passed,
            strength_claim=False,
            statistical_equivalence_claim=False,
        ),
    )
    if not passed:
        raise SystemExit(
            "Retention gate failed (caps or >5pp loss); raw outcomes retained"
        )


if __name__ == "__main__":
    main()
