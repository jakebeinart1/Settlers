"""Dependency-free accounting for the historical Catan policy calibration.

The RL runner imports this module; the regular repository tests exercise it
without adding PyTorch or the external Rust engine to Empires' dependencies.
"""

import hashlib
import json
from pathlib import Path

GAMES = 192
EXPECTED_WINS = 126


def digest(path: Path) -> str:
    """Hash exact inputs and outputs so subsequent runs can be compared."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def outcome_digest(rows: list[dict]) -> str:
    """Compare reported outcomes despite parallel delivery within one batch.

    Only arrival ordinal is removed. Batch, duplicate multiplicity, winner,
    points, turn count and cap status remain. This is not a move-trace hash:
    v1's episode API does not expose the trajectory or lane identity.
    """
    canonical = sorted(
        json.dumps(
            {key: value for key, value in row.items() if key != "ordinal"},
            sort_keys=True,
        )
        for row in rows
    )
    return hashlib.sha256("\n".join(canonical).encode()).hexdigest()


def summarize(rows: list[dict], outcomes: Path, expected_outcomes: str = "") -> dict:
    """Keep the artifact score gate distinct from a training-reproduction claim."""
    wins = sum(row["winner"] == 0 for row in rows)
    caps = sum(row["capped"] for row in rows)
    fingerprint = outcome_digest(rows)
    score_matched = wins == EXPECTED_WINS and len(rows) == GAMES and caps == 0
    replay_matched = fingerprint == expected_outcomes if expected_outcomes else None
    return {
        "wins": wins,
        "games": len(rows),
        "caps": caps,
        "win_rate": wins / len(rows) if rows else None,
        "games_sha256": digest(outcomes),
        "outcome_multiset_sha256": fingerprint,
        "artifact_score_matched": score_matched,
        "local_outcome_replay_matched": replay_matched,
        "artifact_gate_passed": score_matched and replay_matched is not False,
        "training_reproduced": False,
    }
