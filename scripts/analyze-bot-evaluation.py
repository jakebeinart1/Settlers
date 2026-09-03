#!/usr/bin/env python3
"""Summarize seat-rotated Empires simulator JSONL without third-party packages.

Input filenames must end in ``-seat0.jsonl`` through ``-seat3.jsonl``. The
number identifies the evaluated policy's chair in that shard. Schema 5 records
carry their match configuration at the top level, allowing the analyzer to
require exactly three or four chair rotations for each configuration. This
prevents a common measurement error: counting every winner at a mixed table as
a win for the candidate.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import re
import statistics
from pathlib import Path
from typing import NamedTuple, Optional


SEAT_PATTERN = re.compile(r"-seat([0-3])\.jsonl$")
CURRENT_SCHEMA_VERSION = 5
CURRENT_CONFIGURATION_KEYS = (
    "playerCount",
    "victoryPointTarget",
    "boardMode",
)
LEGACY_CONFIGURATION = (4, 10, "randomized")
SUPPORTED_PLAYER_COUNTS = frozenset((3, 4))
SUPPORTED_VICTORY_POINT_TARGETS = frozenset((8, 10, 12))
SUPPORTED_BOARD_MODES = frozenset(("standard", "randomized"))
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
        description="Aggregate one arm or compare two paired bot-evaluation arms."
    )
    parser.add_argument("--name", required=True, help="label printed for the arm")
    parser.add_argument(
        "--candidate-build-id",
        "--build-id",
        dest="candidate_build_id",
        required=True,
        help="required candidate build provenance label",
    )
    parser.add_argument(
        "--schema-version",
        type=int,
        default=CURRENT_SCHEMA_VERSION,
        help="simulator schema expected in every row (default: current schema 5)",
    )
    parser.add_argument(
        "--candidate-policy", required=True, help="policy ID expected in the evaluated chair"
    )
    parser.add_argument(
        "--candidate-foil-policy",
        "--foil-policy",
        dest="candidate_foil_policy",
        required=True,
        help="policy ID expected in the candidate arm's other chairs",
    )
    parser.add_argument(
        "--baseline-build-id",
        help="build provenance expected in the paired baseline arm",
    )
    parser.add_argument(
        "--baseline-policy",
        help="policy ID in the evaluated chair of the paired baseline arm",
    )
    parser.add_argument(
        "--baseline-foil-policy",
        help="policy ID expected in the baseline arm's other chairs",
    )
    parser.add_argument(
        "--candidate-files",
        nargs="+",
        type=Path,
        help="candidate seat shards; required explicitly for paired analysis",
    )
    parser.add_argument(
        "--baseline-files",
        nargs="+",
        type=Path,
        help="baseline seat shards using the same configurations and rotations",
    )
    parser.add_argument(
        "files",
        nargs="*",
        type=Path,
        help="candidate shards for backward-compatible single-arm analysis",
    )
    options = parser.parse_args()
    if options.candidate_files is not None and options.files:
        parser.error("use either --candidate-files or positional candidate files, not both")
    if options.candidate_files is None:
        options.candidate_files = options.files
    if not options.candidate_files:
        parser.error("candidate seat shards are required")

    baseline_options = (
        options.baseline_build_id,
        options.baseline_policy,
        options.baseline_foil_policy,
        options.baseline_files,
    )
    if any(value is not None for value in baseline_options) and not all(
        value is not None for value in baseline_options
    ):
        parser.error(
            "--baseline-build-id, --baseline-policy, --baseline-foil-policy, "
            "and --baseline-files must be supplied together"
        )
    if options.baseline_files is not None and options.files:
        parser.error("paired analysis requires candidate shards under --candidate-files")
    return options


class RateDifference(NamedTuple):
    candidate_successes: int
    candidate_opportunities: int
    baseline_successes: int
    baseline_opportunities: int
    difference: float
    lower: float
    upper: float


class StrengthSummary(NamedTuple):
    games: int
    decisive: int
    wins: int
    win_rate: float
    decisive_rate: float
    median_moves: float


class WinRateDifference(NamedTuple):
    candidate: StrengthSummary
    baseline: StrengthSummary
    difference: float
    lower: float
    upper: float


class PairedBaseline(NamedTuple):
    rows: list[tuple[int, dict]]
    strength: WinRateDifference


class EvaluationConfiguration(NamedTuple):
    player_count: int
    victory_point_target: int
    board_mode: str


EvaluationKey = tuple[int, int, EvaluationConfiguration]
ClusterKey = tuple[int, EvaluationConfiguration]


def configuration_key(row: dict) -> EvaluationConfiguration:
    """Return configuration provenance, defaulting only truly legacy rows."""
    present = [key in row for key in CURRENT_CONFIGURATION_KEYS]
    if not any(present):
        return EvaluationConfiguration(*LEGACY_CONFIGURATION)
    missing = [
        key for key, is_present in zip(CURRENT_CONFIGURATION_KEYS, present)
        if not is_present
    ]
    if missing:
        raise ValueError(f"missing configuration field {missing[0]}")
    return validate_configuration(row)


def loaded_configuration_key(
    row: dict,
    schema_version: int,
) -> EvaluationConfiguration:
    """Validate schema-5 top-level provenance while admitting old archives."""
    missing = [key for key in CURRENT_CONFIGURATION_KEYS if key not in row]
    if schema_version >= CURRENT_SCHEMA_VERSION and missing:
        raise ValueError(f"missing configuration field {missing[0]}")
    return configuration_key(row)


def validate_configuration(row: dict) -> EvaluationConfiguration:
    """Reject labels that cannot describe a supported evaluation game."""
    player_count = row["playerCount"]
    victory_point_target = row["victoryPointTarget"]
    board_mode = row["boardMode"]
    if type(player_count) is not int or player_count not in SUPPORTED_PLAYER_COUNTS:
        raise ValueError("playerCount must be 3 or 4")
    if (
        type(victory_point_target) is not int
        or victory_point_target not in SUPPORTED_VICTORY_POINT_TARGETS
    ):
        raise ValueError("victoryPointTarget must be 8, 10 or 12")
    if not isinstance(board_mode, str) or board_mode not in SUPPORTED_BOARD_MODES:
        raise ValueError("boardMode must be standard or randomized")
    return EvaluationConfiguration(
        player_count,
        victory_point_target,
        board_mode,
    )


def evaluation_key(seat: int, row: dict) -> EvaluationKey:
    return (row["seed"], seat, configuration_key(row))


def mean_interval(values: list[float]) -> tuple[float, float]:
    mean = statistics.fmean(values)
    if len(values) < 2:
        return (mean, 0.0)
    margin = 1.959963984540054 * statistics.stdev(values) / math.sqrt(len(values))
    return (mean, margin)


def has_metric(rows: list[tuple[int, dict]], metric: str) -> bool:
    return all(metric in row["behavior"][seat] for seat, row in rows)


def clustered_win_interval(
    by_seed: dict[ClusterKey, list[tuple[int, dict]]],
) -> tuple[float, float]:
    """Bootstrap whole board-seed clusters and recompute the decisive rate."""
    generator = random.Random(0xE4_91_2A)
    clusters = list(by_seed.values())
    estimates: list[float] = []
    for _ in range(20_000):
        sampled = [generator.choice(clusters) for _ in clusters]
        decisive = [
            item
            for cluster in sampled
            for item in cluster
            if item[1].get("winner") is not None
        ]
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
    preserves the pairing and avoids treating the rotations on one generated
    board as independent observations.
    """
    candidate = {evaluation_key(seat, row): row for seat, row in candidate_rows}
    baseline = {evaluation_key(seat, row): row for seat, row in baseline_rows}
    if candidate.keys() != baseline.keys():
        raise ValueError("paired arms must contain the same seed/chair/config keys")

    def totals(rows: dict[EvaluationKey, dict], keys: list[EvaluationKey]) -> tuple[int, int]:
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
    clusters = sorted({(seed, configuration) for seed, _, configuration in keys})
    generator = random.Random(0x50_41_52)
    estimates: list[float] = []
    for _ in range(20_000):
        sampled_clusters = [generator.choice(clusters) for _ in clusters]
        sampled_keys = evaluation_keys_for_clusters(sampled_clusters)
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


def strength_summary(rows: list[tuple[int, dict]]) -> StrengthSummary:
    """Return pooled strength and completion statistics for one arm."""
    decisive = [(seat, row) for seat, row in rows if row.get("winner") is not None]
    if not decisive:
        raise ValueError("evaluation arm has no decisive games")
    wins = sum(row["winner"] == seat for seat, row in decisive)
    return StrengthSummary(
        games=len(rows),
        decisive=len(decisive),
        wins=wins,
        win_rate=wins / len(decisive),
        decisive_rate=len(decisive) / len(rows),
        median_moves=statistics.median(row["moves"] for _, row in rows),
    )


def paired_win_rate_difference(
    candidate_rows: list[tuple[int, dict]],
    baseline_rows: list[tuple[int, dict]],
) -> WinRateDifference:
    """Compare pooled decisive-game win rates with paired seed resampling."""
    candidate = {evaluation_key(seat, row): row for seat, row in candidate_rows}
    baseline = {evaluation_key(seat, row): row for seat, row in baseline_rows}
    if candidate.keys() != baseline.keys():
        raise ValueError("paired arms must contain the same seed/chair/config keys")

    candidate_summary = strength_summary(candidate_rows)
    baseline_summary = strength_summary(baseline_rows)
    difference = candidate_summary.win_rate - baseline_summary.win_rate
    lower, upper = paired_win_interval(candidate, baseline)
    return WinRateDifference(
        candidate_summary,
        baseline_summary,
        difference,
        lower,
        upper,
    )


def paired_win_interval(
    candidate: dict[EvaluationKey, dict],
    baseline: dict[EvaluationKey, dict],
) -> tuple[float, float]:
    """Bootstrap matched board seeds while retaining all chair rotations."""
    clusters = sorted({(seed, configuration) for seed, _, configuration in candidate})
    generator = random.Random(0x57_49_4E)
    estimates: list[float] = []
    for _ in range(20_000):
        sampled = [generator.choice(clusters) for _ in clusters]
        candidate_rate = sampled_win_rate(candidate, sampled)
        baseline_rate = sampled_win_rate(baseline, sampled)
        if candidate_rate is not None and baseline_rate is not None:
            estimates.append(candidate_rate - baseline_rate)
    if not estimates:
        raise ValueError("no bootstrap sample contained decisive games in both arms")
    estimates.sort()
    return (
        estimates[int(0.025 * len(estimates))],
        estimates[int(0.975 * len(estimates))],
    )


def sampled_win_rate(
    rows: dict[EvaluationKey, dict],
    sampled_clusters: list[ClusterKey],
) -> Optional[float]:
    sampled = [
        (seat, rows[(seed, seat, configuration)])
        for seed, configuration in sampled_clusters
        for seat in range(configuration.player_count)
        if rows[(seed, seat, configuration)].get("winner") is not None
    ]
    if not sampled:
        return None
    return statistics.fmean(row["winner"] == seat for seat, row in sampled)


def evaluation_keys_for_clusters(
    clusters: list[ClusterKey],
) -> list[EvaluationKey]:
    return [
        (seed, seat, configuration)
        for seed, configuration in clusters
        for seat in range(configuration.player_count)
    ]


def print_paired_strength(
    result: WinRateDifference,
    options: argparse.Namespace,
) -> None:
    """Render the provenance and required strength statistics together."""
    print("## Paired strength")
    print()
    print("| Arm | Build ID | Evaluated policy | Opponent policy | "
          "Pooled win rate | Decisive rate | Median moves |")
    print("| --- | --- | --- | --- | ---: | ---: | ---: |")
    print(strength_row(
        "Candidate", options.candidate_build_id, options.candidate_policy,
        options.candidate_foil_policy, result.candidate,
    ))
    print(strength_row(
        "Baseline", options.baseline_build_id, options.baseline_policy,
        options.baseline_foil_policy, result.baseline,
    ))
    print()
    print(
        "- Paired win-rate difference: "
        f"{result.difference * 100:+.1f} percentage points"
    )
    print(
        "- Seed-cluster bootstrap 95% CI: "
        f"{result.lower * 100:+.1f} to {result.upper * 100:+.1f} "
        "percentage points"
    )


def strength_row(
    label: str,
    build_id: str,
    policy: str,
    foil_policy: str,
    summary: StrengthSummary,
) -> str:
    return (
        f"| {label} | `{build_id}` | `{policy}` | `{foil_policy}` | "
        f"{summary.wins}/{summary.decisive} = {summary.win_rate:.1%} | "
        f"{summary.decisive}/{summary.games} = {summary.decisive_rate:.1%} | "
        f"{summary.median_moves:g} |"
    )


def load(
    files: list[Path],
    build_id: str,
    candidate_policy: str,
    foil_policy: str,
    schema_version: int = CURRENT_SCHEMA_VERSION,
) -> list[tuple[int, dict]]:
    rows: list[tuple[int, dict]] = []
    seen_seats: set[int] = set()
    seen_evaluations: set[EvaluationKey] = set()
    seats_by_cluster: dict[ClusterKey, set[int]] = {}
    for path in files:
        match = SEAT_PATTERN.search(path.name)
        if match is None:
            raise SystemExit(f"{path}: filename must end in -seat0.jsonl .. -seat3.jsonl")
        seat = int(match.group(1))
        if seat in seen_seats:
            raise SystemExit(f"seat {seat} appears in more than one shard")
        seen_seats.add(seat)
        row_count = 0
        with path.open(encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, 1):
                try:
                    row = json.loads(line)
                except json.JSONDecodeError as error:
                    raise SystemExit(f"{path}:{line_number}: invalid simulator record: {error}")
                if not isinstance(row, dict):
                    raise SystemExit(f"{path}:{line_number}: simulator record must be an object")
                if row.get("schemaVersion") != schema_version or row.get("buildID") != build_id:
                    raise SystemExit(
                        f"{path}:{line_number}: expected schema {schema_version}/build "
                        f"{build_id!r}, "
                        f"got {row.get('schemaVersion')!r}/{row.get('buildID')!r}"
                    )
                try:
                    configuration = loaded_configuration_key(row, schema_version)
                except (KeyError, TypeError, ValueError) as error:
                    raise SystemExit(
                        f"{path}:{line_number}: invalid evaluation configuration: {error}"
                    ) from error
                if seat >= configuration.player_count:
                    raise SystemExit(
                        f"{path}:{line_number}: seat {seat} is outside playerCount "
                        f"{configuration.player_count}"
                    )
                policies = row.get("policies")
                if not isinstance(policies, list):
                    raise SystemExit(f"{path}:{line_number}: policies must be an array")
                if len(policies) != configuration.player_count:
                    raise SystemExit(
                        f"{path}:{line_number}: policy provenance width {len(policies)} "
                        f"does not match playerCount {configuration.player_count}"
                    )
                behavior = row.get("behavior")
                if not isinstance(behavior, list):
                    raise SystemExit(f"{path}:{line_number}: behavior must be an array")
                if len(behavior) != configuration.player_count:
                    raise SystemExit(
                        f"{path}:{line_number}: behavior width {len(behavior)} "
                        f"does not match playerCount {configuration.player_count}"
                    )
                if not all(isinstance(metrics, dict) for metrics in behavior):
                    raise SystemExit(
                        f"{path}:{line_number}: every behavior entry must be an object"
                    )
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
                        f"{path}:{line_number}: expected foil {foil_policy!r} "
                        f"outside seat {seat}; "
                        f"wrong seats {wrong_foils}"
                    )
                seed = row.get("seed")
                evaluation = (seed, seat, configuration)
                if type(seed) is not int or seed < 0 or evaluation in seen_evaluations:
                    raise SystemExit(f"{path}:{line_number}: duplicate or invalid seed {seed!r}")
                winner = row.get("winner")
                if winner is not None and (
                    type(winner) is not int
                    or winner not in range(configuration.player_count)
                ):
                    raise SystemExit(f"{path}:{line_number}: invalid winner {winner!r}")
                moves = row.get("moves")
                if type(moves) is not int or moves < 0:
                    raise SystemExit(f"{path}:{line_number}: invalid moves {moves!r}")
                seen_evaluations.add(evaluation)
                cluster = (seed, configuration)
                seats_by_cluster.setdefault(cluster, set()).add(seat)
                rows.append((seat, row))
                row_count += 1
        if row_count == 0:
            raise SystemExit(f"{path}: shard is empty")
    if not rows:
        raise SystemExit("evaluation has no records")
    configurations = {configuration for _, configuration in seats_by_cluster}
    if len(configurations) != 1:
        raise SystemExit(
            "analyze one rules configuration at a time; "
            f"found {len(configurations)} configurations"
        )
    for (seed, configuration), seats in seats_by_cluster.items():
        expected = set(range(configuration.player_count))
        if seats != expected:
            raise SystemExit(
                "seat seed/config key set differs: "
                f"seed {seed}, playerCount {configuration.player_count}, "
                f"victoryPointTarget {configuration.victory_point_target}, "
                f"boardMode {configuration.board_mode!r} needs rotations "
                f"{sorted(expected)}; found {sorted(seats)}"
            )
    return rows


def load_paired_baseline(
    options: argparse.Namespace,
    candidate_rows: list[tuple[int, dict]],
) -> Optional[PairedBaseline]:
    """Load and validate the complete paired arm before rendering output."""
    if options.baseline_files is None:
        return None
    baseline_rows = load(
        options.baseline_files,
        options.baseline_build_id,
        options.baseline_policy,
        options.baseline_foil_policy,
        options.schema_version,
    )
    try:
        strength = paired_win_rate_difference(candidate_rows, baseline_rows)
    except ValueError as error:
        raise SystemExit(str(error)) from error
    return PairedBaseline(baseline_rows, strength)


def game_count_description(
    rows: list[tuple[int, dict]],
    clusters: dict[ClusterKey, list[tuple[int, dict]]],
) -> str:
    cluster_count = len(clusters)
    cluster_noun = "cluster" if cluster_count == 1 else "clusters"
    rotations = sorted({configuration.player_count for _, configuration in clusters})
    if len(rotations) == 1:
        return (
            f"{len(rows)} ({cluster_count} seed/config {cluster_noun} "
            f"× {rotations[0]} seat rotations)"
        )
    rotation_list = "/".join(str(rotation) for rotation in rotations)
    return (
        f"{len(rows)} ({cluster_count} seed/config {cluster_noun}; "
        f"{rotation_list} seat rotations by configuration)"
    )


def main() -> None:
    options = parse_args()
    rows = load(
        options.candidate_files,
        options.candidate_build_id,
        options.candidate_policy,
        options.candidate_foil_policy,
        options.schema_version,
    )
    paired_baseline = load_paired_baseline(options, rows)
    decisive_rows = [(seat, row) for seat, row in rows if row.get("winner") is not None]
    if not decisive_rows:
        raise SystemExit("evaluation has no decisive games")
    wins = sum(row["winner"] == seat for seat, row in decisive_rows)
    by_seed: dict[ClusterKey, list[tuple[int, dict]]] = {}
    for seat, row in rows:
        by_seed.setdefault((row["seed"], configuration_key(row)), []).append((seat, row))
    lower, upper = clustered_win_interval(by_seed)
    print(f"# {options.name}")
    print()
    print(f"- Games: {game_count_description(rows, by_seed)}")
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

    if paired_baseline is not None:
        baseline_rows = paired_baseline.rows
        print()
        print_paired_strength(paired_baseline.strength, options)
        print()
        print(f"## Paired differences from `{options.baseline_policy}`")
        print()
        print(
            "| Opportunity-normalized behavior | Difference | Seed-cluster 95% CI | "
            "Candidate / baseline opportunities |"
        )
        print("| --- | ---: | ---: | ---: |")
        for label, numerator, denominator in RATES:
            required = (numerator, denominator)
            if not all(
                has_metric(arm, metric)
                for arm in (rows, baseline_rows)
                for metric in required
            ):
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
