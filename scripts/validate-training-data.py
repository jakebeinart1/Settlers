#!/usr/bin/env python3
"""Fail fast when Empires training JSONL violates its versioned data contract."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


SCHEMA_VERSION = 2
STATE_LAYOUT_VERSION = 3
ACTION_LAYOUT_VERSION = 1
FEATURE_COUNT = 5_182
ACTION_COUNT = 9_295
INFORMATION_POLICIES = ("revealAll", "publicCountsOnly")
PLAYER_COUNTS = (3, 4)
VICTORY_POINT_TARGETS = (8, 10, 12)
BOARD_MODES = ("standard", "randomized")
REQUIRED_FIELDS = {
    "schemaVersion", "buildID", "stateLayoutVersion", "actionLayoutVersion",
    "actionCount", "seed", "decisionIndex", "observerSeat", "winnerSeat", "playerCount",
    "victoryPointTarget", "boardMode",
    "policyID", "hiddenInformationPolicy", "features", "legalActionIndices",
    "chosenActionIndex", "outcome",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-id", required=True, help="required producer provenance")
    parser.add_argument("--information-policy", required=True, choices=INFORMATION_POLICIES)
    parser.add_argument("files", nargs="+", type=Path)
    return parser.parse_args()


def require_integer(row: dict, key: str, location: str) -> int:
    value = row.get(key)
    if type(value) is not int:
        raise ValueError(f"{location}: {key} must be an integer")
    return value


def validate_row(
    row: dict,
    build_id: str,
    information_policy: str,
    location: str,
) -> tuple[int, int]:
    if set(row) != REQUIRED_FIELDS:
        missing = sorted(REQUIRED_FIELDS - set(row))
        extra = sorted(set(row) - REQUIRED_FIELDS)
        raise ValueError(f"{location}: schema fields differ; missing={missing}, extra={extra}")
    expected = {
        "schemaVersion": SCHEMA_VERSION,
        "stateLayoutVersion": STATE_LAYOUT_VERSION,
        "actionLayoutVersion": ACTION_LAYOUT_VERSION,
        "actionCount": ACTION_COUNT,
        "buildID": build_id,
        "hiddenInformationPolicy": information_policy,
    }
    for key, value in expected.items():
        if row.get(key) != value:
            raise ValueError(f"{location}: expected {key}={value!r}, got {row.get(key)!r}")

    seed = require_integer(row, "seed", location)
    decision = require_integer(row, "decisionIndex", location)
    if seed < 0 or decision < 0:
        raise ValueError(f"{location}: seed and decisionIndex must be nonnegative")
    player_count = require_integer(row, "playerCount", location)
    if player_count not in PLAYER_COUNTS:
        raise ValueError(f"{location}: invalid playerCount {player_count}")
    victory_target = require_integer(row, "victoryPointTarget", location)
    if victory_target not in VICTORY_POINT_TARGETS:
        raise ValueError(f"{location}: invalid victoryPointTarget {victory_target}")
    board_mode = row.get("boardMode")
    if board_mode not in BOARD_MODES:
        raise ValueError(f"{location}: invalid boardMode {board_mode!r}")
    observer = require_integer(row, "observerSeat", location)
    winner = require_integer(row, "winnerSeat", location)
    if observer not in range(player_count):
        raise ValueError(f"{location}: invalid observer {observer} for {player_count} players")
    if winner not in range(player_count):
        raise ValueError(f"{location}: invalid winner {winner} for {player_count} players")
    if not isinstance(row.get("policyID"), str) or not row["policyID"]:
        raise ValueError(f"{location}: policyID must be nonempty")

    validate_features(row.get("features"), location)
    legal = validate_legal_actions(row.get("legalActionIndices"), location)
    chosen = require_integer(row, "chosenActionIndex", location)
    if chosen not in legal:
        raise ValueError(f"{location}: chosen action {chosen} is outside the legal mask")
    if type(row.get("outcome")) not in (int, float) or row["outcome"] not in (-1, 1):
        raise ValueError(f"{location}: outcome must be -1 or 1")
    expected_outcome = 1 if observer == winner else -1
    if row["outcome"] != expected_outcome:
        raise ValueError(f"{location}: outcome disagrees with observer and winner seats")
    return seed, decision


def validate_features(features: object, location: str) -> None:
    if not isinstance(features, list) or len(features) != FEATURE_COUNT:
        length = len(features) if isinstance(features, list) else "not-a-list"
        raise ValueError(f"{location}: expected {FEATURE_COUNT} features, got {length}")
    for index, value in enumerate(features):
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError(f"{location}: feature {index} is not numeric")
        if not math.isfinite(value) or not 0 <= value <= 1:
            raise ValueError(f"{location}: feature {index}={value!r} escapes finite 0...1")


def validate_legal_actions(legal: object, location: str) -> set[int]:
    if not isinstance(legal, list) or not legal:
        raise ValueError(f"{location}: legalActionIndices must be a nonempty list")
    if any(type(index) is not int or index not in range(ACTION_COUNT) for index in legal):
        raise ValueError(f"{location}: legal action outside 0..<{ACTION_COUNT}")
    if legal != sorted(set(legal)):
        raise ValueError(f"{location}: legal actions must be sorted and unique")
    return set(legal)


def reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key {key!r}")
        result[key] = value
    return result


def game_key(row: dict) -> tuple[int, int, int, str]:
    """Identify one trajectory without conflating equal seeds across arms."""
    return (
        row["seed"],
        row["playerCount"],
        row["victoryPointTarget"],
        row["boardMode"],
    )


def validate_files(paths: list[Path], build_id: str, information_policy: str) -> tuple[int, int]:
    decisions_by_game: dict[tuple[int, int, int, str], set[int]] = {}
    rows = 0
    for path in paths:
        with path.open(encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, start=1):
                location = f"{path}:{line_number}"
                try:
                    row = json.loads(line, object_pairs_hook=reject_duplicate_keys)
                except (json.JSONDecodeError, ValueError) as error:
                    raise ValueError(f"{location}: invalid JSON: {error}") from error
                if not isinstance(row, dict):
                    raise ValueError(f"{location}: record must be an object")
                seed, decision = validate_row(row, build_id, information_policy, location)
                key = game_key(row)
                if decision in decisions_by_game.setdefault(key, set()):
                    raise ValueError(f"{location}: duplicate decision {decision} for game {key}")
                decisions_by_game[key].add(decision)
                rows += 1
    if rows == 0:
        raise ValueError("dataset contains no records")
    for key, decisions in decisions_by_game.items():
        if decisions != set(range(len(decisions))):
            raise ValueError(f"game {key}: decision indices are not contiguous from zero")
    return rows, len({key[0] for key in decisions_by_game})


def main() -> None:
    options = parse_args()
    try:
        rows, seeds = validate_files(options.files, options.build_id, options.information_policy)
    except ValueError as error:
        raise SystemExit(f"training-data: {error}") from error
    print(f"training-data: valid {rows} examples across {seeds} seeds")


if __name__ == "__main__":
    main()
