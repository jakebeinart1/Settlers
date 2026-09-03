#!/usr/bin/env python3
"""Train a dependency-free masked policy/value baseline on Empires JSONL."""

from __future__ import annotations

import argparse
import importlib.util
import json
import math
import hashlib
from collections import Counter
from pathlib import Path


VALIDATOR_PATH = Path(__file__).with_name("validate-training-data.py")
SPEC = importlib.util.spec_from_file_location("training_data_validator", VALIDATOR_PATH)
assert SPEC is not None and SPEC.loader is not None
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)

PHASE_COUNT = 7
TEST_FOLD_MODULUS = 5
VALUE_EPOCHS = 3
VALUE_LEARNING_RATE = 0.01


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-id", required=True)
    parser.add_argument("--information-policy", required=True, choices=VALIDATOR.INFORMATION_POLICIES)
    parser.add_argument("--model-output", type=Path, help="write the fitted versioned checkpoint")
    parser.add_argument("files", nargs="+", type=Path)
    return parser.parse_args()


def load_rows(paths: list[Path], build_id: str, information_policy: str) -> list[dict]:
    VALIDATOR.validate_files(paths, build_id, information_policy)
    rows: list[dict] = []
    for path in paths:
        with path.open(encoding="utf-8") as handle:
            rows.extend(json.loads(line) for line in handle)
    return rows


def dataset_digest(paths: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in paths:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    return digest.hexdigest()


def split_by_seed(rows: list[dict]) -> tuple[list[dict], list[dict]]:
    seeds = sorted({row["seed"] for row in rows})
    if len(seeds) < TEST_FOLD_MODULUS:
        raise ValueError(f"baseline needs at least {TEST_FOLD_MODULUS} whole-game seeds")
    test_seeds = set(seeds[::TEST_FOLD_MODULUS])
    train = [row for row in rows if row["seed"] not in test_seeds]
    test = [row for row in rows if row["seed"] in test_seeds]
    return train, test


def phase_index(features: list[float]) -> int:
    phase = features[:PHASE_COUNT]
    if phase.count(1) != 1 or any(value not in (0, 1) for value in phase):
        raise ValueError("phase prefix is not one-hot")
    return phase.index(1)


def train_policy(rows: list[dict]) -> Counter[tuple[int, int]]:
    return Counter((phase_index(row["features"]), row["chosenActionIndex"]) for row in rows)


def predict_action(row: dict, counts: Counter[tuple[int, int]]) -> int:
    phase = phase_index(row["features"])
    return max(row["legalActionIndices"], key=lambda action: (counts[(phase, action)], -action))


def policy_metrics(rows: list[dict], counts: Counter[tuple[int, int]]) -> dict[str, float | int]:
    decisions = [row for row in rows if len(row["legalActionIndices"]) > 1]
    if not decisions:
        raise ValueError("test fold has no non-forced policy decisions")
    correct = sum(predict_action(row, counts) == row["chosenActionIndex"] for row in decisions)
    random_expected = sum(1 / len(row["legalActionIndices"]) for row in decisions)
    return {
        "evaluatedDecisions": len(decisions),
        "top1Accuracy": correct / len(decisions),
        "uniformLegalExpectedAccuracy": random_expected / len(decisions),
        "illegalSelections": 0,
    }


def nonzero_features(row: dict) -> list[tuple[int, float]]:
    return [(index, value) for index, value in enumerate(row["features"]) if value]


def train_value(rows: list[dict]) -> tuple[list[float], float]:
    weights = [0.0] * VALIDATOR.FEATURE_COUNT
    bias = 0.0
    ordered = sorted(rows, key=lambda row: (row["seed"], row["decisionIndex"]))
    for _ in range(VALUE_EPOCHS):
        for row in ordered:
            sparse = nonzero_features(row)
            prediction = bias + sum(weights[index] * value for index, value in sparse)
            error = max(-1.0, min(1.0, prediction)) - row["outcome"]
            bias -= VALUE_LEARNING_RATE * error
            for index, value in sparse:
                weights[index] -= VALUE_LEARNING_RATE * error * value
    return weights, bias


def value_metrics(rows: list[dict], weights: list[float], bias: float, train_mean: float) -> dict[str, float]:
    predictions = []
    for row in rows:
        prediction = bias + sum(weights[index] * value for index, value in nonzero_features(row))
        predictions.append(max(-1.0, min(1.0, prediction)))
    mae = sum(abs(prediction - row["outcome"]) for prediction, row in zip(predictions, rows)) / len(rows)
    constant_mae = sum(abs(train_mean - row["outcome"]) for row in rows) / len(rows)
    sign_accuracy = sum((prediction >= 0) == (row["outcome"] > 0) for prediction, row in zip(predictions, rows)) / len(rows)
    majority_sign_accuracy = sum((train_mean >= 0) == (row["outcome"] > 0) for row in rows) / len(rows)
    return {
        "meanAbsoluteError": mae,
        "constantMeanMAE": constant_mae,
        "signAccuracy": sign_accuracy,
        "majoritySignAccuracy": majority_sign_accuracy,
    }


def train_and_evaluate(rows: list[dict]) -> tuple[dict, dict]:
    train, test = split_by_seed(rows)
    policy = train_policy(train)
    weights, bias = train_value(train)
    train_mean = sum(row["outcome"] for row in train) / len(train)
    metrics = {
        "schemaVersion": 1,
        "stateLayoutVersion": VALIDATOR.STATE_LAYOUT_VERSION,
        "actionLayoutVersion": VALIDATOR.ACTION_LAYOUT_VERSION,
        "trainSeeds": len({row["seed"] for row in train}),
        "testSeeds": len({row["seed"] for row in test}),
        "trainExamples": len(train),
        "testExamples": len(test),
        "policy": policy_metrics(test, policy),
        "value": value_metrics(test, weights, bias, train_mean),
        "valueWeightL2": math.sqrt(sum(weight * weight for weight in weights)),
    }
    checkpoint = {
        "schemaVersion": 1,
        "stateLayoutVersion": VALIDATOR.STATE_LAYOUT_VERSION,
        "actionLayoutVersion": VALIDATOR.ACTION_LAYOUT_VERSION,
        "featureCount": VALIDATOR.FEATURE_COUNT,
        "actionCount": VALIDATOR.ACTION_COUNT,
        "trainingSeeds": sorted({row["seed"] for row in train}),
        "teacherPolicyIDs": sorted({row["policyID"] for row in train}),
        "teacherPolicyCounts": dict(sorted(Counter(row["policyID"] for row in train).items())),
        "hiddenInformationPolicy": rows[0]["hiddenInformationPolicy"],
        "hyperparameters": {
            "testFoldModulus": TEST_FOLD_MODULUS,
            "valueEpochs": VALUE_EPOCHS,
            "valueLearningRate": VALUE_LEARNING_RATE,
        },
        "policyCounts": [
            [phase, action, count]
            for (phase, action), count in sorted(policy.items())
        ],
        "valueBias": bias,
        "valueWeights": weights,
    }
    return metrics, checkpoint


def checkpoint_bytes(checkpoint: dict, build_id: str, data_digest: str) -> bytes:
    complete = {**checkpoint, "buildID": build_id, "datasetSHA256": data_digest}
    return (json.dumps(complete, separators=(",", ":"), sort_keys=True) + "\n").encode()


def write_checkpoint(path: Path, checkpoint: dict, build_id: str, data_digest: str) -> None:
    if path.exists():
        raise ValueError(f"refusing to overwrite existing checkpoint at {path}")
    path.write_bytes(checkpoint_bytes(checkpoint, build_id, data_digest))


def load_checkpoint(path: Path, build_id: str, information_policy: str) -> dict:
    checkpoint = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=VALIDATOR.reject_duplicate_keys)
    expected = {
        "schemaVersion": 1,
        "stateLayoutVersion": VALIDATOR.STATE_LAYOUT_VERSION,
        "actionLayoutVersion": VALIDATOR.ACTION_LAYOUT_VERSION,
        "featureCount": VALIDATOR.FEATURE_COUNT,
        "actionCount": VALIDATOR.ACTION_COUNT,
        "buildID": build_id,
        "hiddenInformationPolicy": information_policy,
    }
    for key, value in expected.items():
        if checkpoint.get(key) != value:
            raise ValueError(f"checkpoint expected {key}={value!r}, got {checkpoint.get(key)!r}")
    if len(checkpoint.get("valueWeights", [])) != VALIDATOR.FEATURE_COUNT:
        raise ValueError("checkpoint has the wrong value-weight width")
    if not isinstance(checkpoint.get("datasetSHA256"), str) or len(checkpoint["datasetSHA256"]) != 64:
        raise ValueError("checkpoint has no SHA-256 dataset provenance")
    return checkpoint


def checkpoint_predictions(row: dict, checkpoint: dict) -> tuple[int, float]:
    counts = Counter({(phase, action): count for phase, action, count in checkpoint["policyCounts"]})
    action = predict_action(row, counts)
    value = checkpoint["valueBias"] + sum(
        checkpoint["valueWeights"][index] * feature
        for index, feature in nonzero_features(row)
    )
    return action, max(-1.0, min(1.0, value))


def main() -> None:
    options = parse_args()
    try:
        rows = load_rows(options.files, options.build_id, options.information_policy)
        metrics, checkpoint = train_and_evaluate(rows)
        if options.model_output is not None:
            write_checkpoint(options.model_output, checkpoint, options.build_id, dataset_digest(options.files))
    except ValueError as error:
        raise SystemExit(f"policy-baseline: {error}") from error
    print(json.dumps(metrics, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
