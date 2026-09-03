#!/usr/bin/env python3
"""Summarize seat-rotated Empires simulator JSONL without third-party packages.

Input filenames must end in ``-seat0.jsonl`` through ``-seat3.jsonl``. The
number identifies the evaluated policy's chair in that shard. This prevents a
common measurement error: counting every winner at a mixed table as a win for
the candidate.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import re
import statistics
from pathlib import Path
from typing import NamedTuple


SEAT_PATTERN = re.compile(r"-seat([0-3])\.jsonl$")
METRICS = (
    "roadsBuilt",
    "settlementsBuilt",
    "citiesBuilt",
    "developmentCardsBought",
    "knightsPlayed",
    "robberMoves",
    "bankTrades",
    "tradesProposed",
    "resolvedTradeAcceptances",
    "resolvedTradeRejections",
    "turnsEnded",
    "settlementCityOpportunities",
    "settlementsChosenInMixedBuildOpportunities",
    "citiesChosenInMixedBuildOpportunities",
    "cityBuildOpportunities",
    "citiesChosenWhenBuildable",
    "developmentCardBuildOpportunities",
    "developmentCardsChosenOverPermanentBuild",
    "tradeResponseOpportunities",
    "tradeResponsesAccepted",
    "proposalCardsGiven",
    "proposalCardsRequested",
    "playableKnightOpportunities",
    "knightsChosenWhenPlayable",
    "differentiatedRobberTargetOpportunities",
    "highestPublicVPRobberTargets",
    "tradeProposalOpportunities",
)

RATES = (
    (
        "city choice when city and settlement were legal",
        "citiesChosenInMixedBuildOpportunities",
        "settlementCityOpportunities",
    ),
    (
        "development-card choice when a permanent build was legal",
        "developmentCardsChosenOverPermanentBuild",
        "developmentCardBuildOpportunities",
    ),
    (
        "city chosen when buildable",
        "citiesChosenWhenBuildable",
        "cityBuildOpportunities",
    ),
    ("trade acceptance", "tradeResponsesAccepted", "tradeResponseOpportunities"),
    ("knight use when playable", "knightsChosenWhenPlayable", "playableKnightOpportunities"),
    (
        "highest-public-VP robber target when targets differed",
        "highestPublicVPRobberTargets",
        "differentiatedRobberTargetOpportunities",
    ),
    ("player-trade proposal", "tradesProposed", "tradeProposalOpportunities"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Aggregate one seat-rotated bot evaluation arm."
    )
    parser.add_argument("--name", required=True, help="label printed for the arm")
    parser.add_argument("--build-id", required=True, help="required build provenance label")
    parser.add_argument(
        "--schema-version",
        type=int,
        default=4,
        help="simulator schema expected in every row (default: current schema 4)",
    )
    parser.add_argument(
        "--candidate-policy", required=True, help="policy ID expected in the evaluated chair"
    )
    parser.add_argument("--foil-policy", required=True, help="policy ID expected in the other chairs")
    parser.add_argument(
        "--baseline-policy",
        help="policy ID in the evaluated chair of the paired baseline arm",
    )
    parser.add_argument(
        "--baseline-files",
        nargs=4,
        type=Path,
        metavar=("SEAT0", "SEAT1", "SEAT2", "SEAT3"),
        help="four baseline shards using the same seeds and chair rotations",
    )
    parser.add_argument("files", nargs="+", type=Path)
    options = parser.parse_args()
    if (options.baseline_policy is None) != (options.baseline_files is None):
        parser.error("--baseline-policy and --baseline-files must be supplied together")
    return options


class RateDifference(NamedTuple):
    candidate_successes: int
    candidate_opportunities: int
    baseline_successes: int
    baseline_opportunities: int
    difference: float
    lower: float
    upper: float


def mean_interval(values: list[float]) -> tuple[float, float]:
    mean = statistics.fmean(values)
    if len(values) < 2:
        return (mean, 0.0)
    margin = 1.959963984540054 * statistics.stdev(values) / math.sqrt(len(values))
    return (mean, margin)


def has_metric(rows: list[tuple[int, dict]], metric: str) -> bool:
    return all(metric in row["behavior"][seat] for seat, row in rows)


def clustered_win_interval(by_seed: dict[int, list[tuple[int, dict]]]) -> tuple[float, float]:
    """Bootstrap whole board-seed clusters and recompute the decisive rate."""
    generator = random.Random(0xE4_91_2A)
    clusters = list(by_seed.values())
    estimates: list[float] = []
    for _ in range(20_000):
        sampled = [generator.choice(clusters) for _ in clusters]
        decisive = [item for cluster in sampled for item in cluster if item[1].get("winner") is not None]
        if decisive:
            estimates.append(statistics.fmean(row["winner"] == seat for seat, row in decisive))
    estimates.sort()
    return (
        estimates[int(0.025 * len(estimates))],
        estimates[int(0.975 * len(estimates))],
    )


def paired_rate_difference(
    candidate_rows: list[tuple[int, dict]],
    baseline_rows: list[tuple[int, dict]],
    numerator: str,
    denominator: str,
) -> RateDifference:
    """Compare rates on identical board seeds and chair rotations.

    Whole seeds, including every chair rotation, are resampled together. This
    preserves the pairing and avoids treating four games on one generated
    board as four independent observations.
    """
    candidate = {(row["seed"], seat): row for seat, row in candidate_rows}
    baseline = {(row["seed"], seat): row for seat, row in baseline_rows}
    if candidate.keys() != baseline.keys():
        raise ValueError("paired arms must contain the same seed/chair pairs")

    def totals(rows: dict[tuple[int, int], dict], keys: list[tuple[int, int]]) -> tuple[int, int]:
        successes = sum(rows[key]["behavior"][key[1]][numerator] for key in keys)
        opportunities = sum(rows[key]["behavior"][key[1]][denominator] for key in keys)
        return successes, opportunities

    keys = sorted(candidate)
    candidate_successes, candidate_opportunities = totals(candidate, keys)
    baseline_successes, baseline_opportunities = totals(baseline, keys)
    if candidate_opportunities == 0 or baseline_opportunities == 0:
        raise ValueError(f"no opportunities for paired metric {numerator}/{denominator}")

    difference = (
        candidate_successes / candidate_opportunities
        - baseline_successes / baseline_opportunities
    )
    seeds = sorted({seed for seed, _ in keys})
    generator = random.Random(0x50_41_52)
    estimates: list[float] = []
    for _ in range(20_000):
        sampled_seeds = [generator.choice(seeds) for _ in seeds]
        sampled_keys = [(seed, seat) for seed in sampled_seeds for seat in range(4)]
        cand_successes, cand_opportunities = totals(candidate, sampled_keys)
        base_successes, base_opportunities = totals(baseline, sampled_keys)
        if cand_opportunities and base_opportunities:
            estimates.append(
                cand_successes / cand_opportunities
                - base_successes / base_opportunities
            )
    if not estimates:
        raise ValueError(f"no bootstrap samples had opportunities for {numerator}/{denominator}")
    estimates.sort()
    return RateDifference(
        candidate_successes=candidate_successes,
        candidate_opportunities=candidate_opportunities,
        baseline_successes=baseline_successes,
        baseline_opportunities=baseline_opportunities,
        difference=difference,
        lower=estimates[int(0.025 * len(estimates))],
        upper=estimates[int(0.975 * len(estimates))],
    )


def load(
    files: list[Path],
    build_id: str,
    candidate_policy: str,
    foil_policy: str,
    schema_version: int = 3,
) -> list[tuple[int, dict]]:
    rows: list[tuple[int, dict]] = []
    seen_seats: set[int] = set()
    seeds_by_seat: dict[int, set[int]] = {}
    for path in files:
        match = SEAT_PATTERN.search(path.name)
        if match is None:
            raise SystemExit(f"{path}: filename must end in -seat0.jsonl .. -seat3.jsonl")
        seat = int(match.group(1))
        if seat in seen_seats:
            raise SystemExit(f"candidate seat {seat} appears in more than one shard")
        seen_seats.add(seat)
        shard_seeds: set[int] = set()
        with path.open(encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, 1):
                try:
                    row = json.loads(line)
                    row["behavior"][seat]
                except (json.JSONDecodeError, KeyError, IndexError, TypeError) as error:
                    raise SystemExit(f"{path}:{line_number}: invalid simulator record: {error}")
                if row.get("schemaVersion") != schema_version or row.get("buildID") != build_id:
                    raise SystemExit(
                        f"{path}:{line_number}: expected schema {schema_version}/build {build_id!r}, "
                        f"got {row.get('schemaVersion')!r}/{row.get('buildID')!r}"
                    )
                policies = row.get("policies")
                if not isinstance(policies, list) or len(policies) != 4:
                    raise SystemExit(f"{path}:{line_number}: missing four-seat policy provenance")
                if policies[seat] != candidate_policy:
                    raise SystemExit(
                        f"{path}:{line_number}: seat {seat} is {policies[seat]!r}, "
                        f"expected {candidate_policy!r}"
                    )
                wrong_foils = [
                    index
                    for index, policy in enumerate(policies)
                    if index != seat and policy != foil_policy
                ]
                if wrong_foils:
                    raise SystemExit(
                        f"{path}:{line_number}: expected foil {foil_policy!r} outside seat {seat}; "
                        f"wrong seats {wrong_foils}"
                    )
                seed = row.get("seed")
                if not isinstance(seed, int) or seed in shard_seeds:
                    raise SystemExit(f"{path}:{line_number}: duplicate or invalid seed {seed!r}")
                shard_seeds.add(seed)
                rows.append((seat, row))
        seeds_by_seat[seat] = shard_seeds
    if seen_seats != {0, 1, 2, 3}:
        raise SystemExit(f"evaluation needs all four seat rotations; found {sorted(seen_seats)}")
    expected_seeds = seeds_by_seat[0]
    for seat, seeds in seeds_by_seat.items():
        if seeds != expected_seeds:
            raise SystemExit(
                f"seat {seat} seed set differs from seat 0 "
                f"(missing {sorted(expected_seeds - seeds)}, extra {sorted(seeds - expected_seeds)})"
            )
    return rows


def main() -> None:
    options = parse_args()
    rows = load(
        options.files,
        options.build_id,
        options.candidate_policy,
        options.foil_policy,
        options.schema_version,
    )
    decisive_rows = [(seat, row) for seat, row in rows if row.get("winner") is not None]
    if not decisive_rows:
        raise SystemExit("evaluation has no decisive games")
    wins = sum(row["winner"] == seat for seat, row in decisive_rows)
    by_seed: dict[int, list[tuple[int, dict]]] = {}
    for seat, row in rows:
        by_seed.setdefault(row["seed"], []).append((seat, row))
    lower, upper = clustered_win_interval(by_seed)
    print(f"# {options.name}")
    print()
    print(f"- Games: {len(rows)} ({len(rows) // 4} seeds × 4 seat rotations)")
    print(f"- Decisive: {len(decisive_rows)}/{len(rows)}")
    print(
        f"- Wins: {wins}/{len(decisive_rows)} = {wins / len(decisive_rows):.1%} "
        f"(seed-cluster bootstrap 95% CI {lower:.1%}–{upper:.1%})"
    )
    print(f"- Median moves: {statistics.median(row['moves'] for _, row in rows):g}")
    print()
    print("| Behavior per game | Mean | 95% CI margin |")
    print("| --- | ---: | ---: |")
    for metric in METRICS:
        if not has_metric(rows, metric):
            print(f"| `{metric}` | not recorded | not recorded |")
            continue
        seed_means = [
            statistics.fmean(row["behavior"][seat][metric] for seat, row in seed_rows)
            for seed_rows in by_seed.values()
        ]
        mean, margin = mean_interval(seed_means)
        print(f"| `{metric}` | {mean:.3f} | ±{margin:.3f} |")
    print()
    print("| Opportunity-normalized behavior | Rate | Opportunities |")
    print("| --- | ---: | ---: |")
    for label, numerator, denominator in RATES:
        if not has_metric(rows, numerator) or not has_metric(rows, denominator):
            print(f"| {label} | not recorded | not recorded |")
            continue
        successes = sum(row["behavior"][seat][numerator] for seat, row in rows)
        opportunities = sum(row["behavior"][seat][denominator] for seat, row in rows)
        rate = f"{successes / opportunities:.1%}" if opportunities else "not observed"
        print(f"| {label} | {rate} | {opportunities} |")

    if options.baseline_files is not None:
        baseline_rows = load(
            options.baseline_files,
            options.build_id,
            options.baseline_policy,
            options.foil_policy,
            options.schema_version,
        )
        print()
        print(f"## Paired differences from `{options.baseline_policy}`")
        print()
        print("| Opportunity-normalized behavior | Difference | Seed-cluster 95% CI | Candidate / baseline opportunities |")
        print("| --- | ---: | ---: | ---: |")
        for label, numerator, denominator in RATES:
            required = (numerator, denominator)
            if not all(has_metric(arm, metric) for arm in (rows, baseline_rows) for metric in required):
                print(f"| {label} | not recorded | not recorded | not recorded |")
                continue
            try:
                result = paired_rate_difference(rows, baseline_rows, numerator, denominator)
            except ValueError as error:
                if "no opportunities" not in str(error):
                    raise SystemExit(str(error)) from error
                print(f"| {label} | not observed | not observed | 0 |")
                continue
            print(
                f"| {label} | {result.difference:+.1%} | "
                f"{result.lower:+.1%} to {result.upper:+.1%} | "
                f"{result.candidate_opportunities} / {result.baseline_opportunities} |"
            )


if __name__ == "__main__":
    main()
