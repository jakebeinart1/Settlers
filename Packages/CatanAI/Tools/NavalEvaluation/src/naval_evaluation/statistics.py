"""Exact numerator arithmetic for the preregistered paired cluster bootstrap.

Each rotation contributes an integer candidate-win minus control-win. Summing
those integers before dividing once prevents a true zero CI bound becoming a
positive floating-point epsilon. Sampling, strata, seeds, and quantiles are fixed.
"""

import collections
import random
from typing import Any


def integer_bootstrap(strata: dict[tuple, list[int]], players: int) -> dict[str, Any]:
    """Use the original 20,000 seeded stratified resamples with exact counts."""
    expected = 11 if players == 3 else 7
    if len(strata) != 12 or any(len(values) != expected for values in strata.values()):
        raise ValueError("incomplete bootstrap strata")
    denominator = players * 12 * expected
    rng = random.Random(20261004)
    bootstrap = sorted(
        sum(sum(rng.choice(values) for _ in values) for values in strata.values())
        for _ in range(20000)
    )
    difference = sum(sum(values) for values in strata.values()) / denominator
    interval = [bootstrap[499] / denominator, bootstrap[19499] / denominator]
    return dict(
        difference=difference,
        difference95CI=interval,
        substantiveGatePassed=difference >= 0.10 and interval[0] > 0,
    )


def paired_integers(rows: list[dict[str, Any]], players: int) -> dict[str, Any]:
    """Build the same sorted seed clusters as the frozen floating analyzer."""
    groups = collections.defaultdict(list)
    for row in rows:
        if row["playerCount"] != players:
            continue
        key = (
            row["family"],
            row["fogEnabled"],
            row["resourceChoiceEnabled"],
            row["seed"],
        )
        if row["winner"] is None:
            raise ValueError("incomplete paired arm")
        win = int(row["winner"] == row["focalChair"])
        groups[key].append(win if row["arm"] == "candidate" else -win)
    strata = collections.defaultdict(list)
    for key, values in sorted(groups.items()):
        strata[key[:3]].append(sum(values))
    return integer_bootstrap(strata, players)
