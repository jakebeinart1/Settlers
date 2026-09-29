#!/usr/bin/env python3
"""Every Expert and Classic that ever shipped, at one table: schedule, run, analyse.

Why this exists (2026-09-28): Jake did not believe that Expert with and without
the hand-size rule could be equally strong, and asked for every version of
Expert and Classic that ever lived to play every other, often enough to trust
the answer. `arena` plays the games; this script decides which games, runs them
in parallel shards, and reads the results.

Subcommands
  probe    four copies of each built version, a few seeds each, to find which
           commits actually changed how a bot plays (same moves on every probe
           seed = the same variant) and which cannot play today's rules
  roster   collapse the probe into one representative per distinct variant
  schedule every pair of roster entries, 1 vs 3 in both directions, the
           candidate in each of the four chairs, on shared seeds
  run      play a schedule in N detached-friendly shards (resumable)
  analyse  head-to-head table with 95% intervals, a rating for every variant
           fitted over all games, and hand-size behaviour per variant

Standard library only, like the other scripts here.
"""

from __future__ import annotations

import argparse
import itertools
import json
import math
import os
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

PROBE_SEEDS = range(8_100_000, 8_100_006)
LOCAL_VARIANTS = ["local:expert", "local:expert-holder", "local:classic",
                  "local:classic-aggressive", "local:classic-cautious"]


def git(*args: str) -> str:
    here = Path(__file__).resolve().parent
    return subprocess.run(["git", "-C", str(here), *args], check=True, capture_output=True,
                          text=True).stdout.strip()


def built_versions(seats_dir: Path) -> list[tuple[str, set[str]]]:
    versions = []
    for binary in sorted(seats_dir.glob("seat-*")):
        if binary.suffix == ".flags":
            continue
        flags_file = binary.with_name(binary.name + ".flags")
        flags = set(flags_file.read_text().split()) if flags_file.exists() else set()
        versions.append((binary.name.removeprefix("seat-"), flags))
    return versions


def policies_for(flags: set[str]) -> list[str]:
    return ["classic", "expert"] if "-DEXPERT" in flags else ["classic"]


def write_jsonl(path: Path, rows) -> int:
    count = 0
    with path.open("w") as handle:
        for row in rows:
            handle.write(json.dumps(row) + "\n")
            count += 1
    return count


def read_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


# MARK: probe and roster

def cmd_probe(args) -> None:
    games = []
    for version, flags in built_versions(args.seats_dir):
        for policy in policies_for(flags):
            seat = f"{version}:{policy}"
            games += [{"match": f"probe {seat}", "seed": seed, "seats": [seat] * 4} for seed in PROBE_SEEDS]
    for seat in LOCAL_VARIANTS:
        games += [{"match": f"probe {seat}", "seed": seed, "seats": [seat] * 4} for seed in PROBE_SEEDS]
    print(f"{write_jsonl(args.out, games)} probe games -> {args.out}")


def commit_order() -> dict[str, int]:
    shas = git("log", "--first-parent", "--format=%h", "origin/main").split()
    return {sha[:7]: index for index, sha in enumerate(reversed(shas))}


def cmd_roster(args) -> None:
    """One entry per distinct behaviour, named by the first commit that played it."""
    by_seat: dict[str, dict] = defaultdict(lambda: {"prints": {}, "fallbacks": 0, "decisions": 0, "unfinished": 0})
    for game in read_jsonl(args.results):
        seat = game["seats"][0]
        entry = by_seat[seat]
        entry["prints"][game["seed"]] = game["fingerprint"]
        entry["fallbacks"] += sum(r["fallbacks"] + r["decodeErrors"] for r in game["results"])
        entry["decisions"] += sum(r["decisions"] for r in game["results"])
        entry["unfinished"] += game.get("winner") is None
    order = commit_order()
    groups: dict[tuple, list[str]] = defaultdict(list)
    for seat, entry in by_seat.items():
        if len(entry["prints"]) != len(PROBE_SEEDS):
            print(f"  incomplete probe: {seat}", file=sys.stderr)
            continue
        policy = seat.split(":", 1)[1].replace("classic-balanced", "classic")
        family = "expert" if policy.startswith("expert") else "classic"
        groups[(family, tuple(entry["prints"][s] for s in PROBE_SEEDS))].append(seat)
    roster = []
    for (family, _), seats in groups.items():
        seats.sort(key=lambda seat: age_key(seat, order))
        first = seats[0]
        local = [seat for seat in seats if seat.startswith("local:")]
        # Play the in-process copy when today's code is in the group: same
        # moves (the probe just showed it), no pipe.
        representative = local[0] if local else first
        stats = by_seat[representative]
        rate = stats["fallbacks"] / max(stats["decisions"], 1)
        roster.append({"family": family, "seat": representative, "label": describe(first, family, seats),
                       "sameAs": [s for s in seats if s != representative],
                       "fallbackRate": round(rate, 5), "unfinishedProbes": stats["unfinished"]})
    roster.sort(key=lambda row: (row["family"], age_key(row["seat"], order)))
    args.out.write_text(json.dumps(roster, indent=1) + "\n")
    for row in roster:
        flag = "  EXCLUDE?" if row["fallbackRate"] > args.max_fallback or row["unfinishedProbes"] else ""
        print(f"{row['family']:8} {row['seat']:28} +{len(row['sameAs']):2} identical  "
              f"fallback {row['fallbackRate']:.4f} unfinished {row['unfinishedProbes']}{flag}")


def describe(first: str, family: str, seats: list[str]) -> str:
    """'Expert 1f2c8f0 09-14' - the commit that first played this way."""
    version, policy = first.split(":", 1)
    name = {"expert": "Expert", "expert-holder": "Expert holder", "classic": "Classic",
            "classic-aggressive": "Classic aggressive", "classic-cautious": "Classic cautious"}[policy]
    if version == "local":
        return f"{name} (today)"
    date = git("log", "-1", "--format=%ad", "--date=format:%m-%d", version)
    if "local:expert-holder" in seats:
        return f"{name} {version} {date} = today's minus hand rule"
    today = any(seat in ("local:expert", "local:classic") for seat in seats)
    return f"{name} {version} {date}" + (" = today" if today else "")


def age_key(seat: str, order: dict[str, int]) -> int:
    version = seat.split(":")[0]
    return 10**9 if version == "local" else order.get(version, -1)


# MARK: schedule and run

def cmd_schedule(args) -> None:
    roster = [row for row in json.loads(args.roster.read_text()) if not row.get("excluded")]
    seats = [row["seat"] for row in roster]
    family = {row["seat"]: row.get("family") for row in roster}
    seeds = range(args.first_seed, args.first_seed + args.seeds)
    games = []
    pairs = [(a, b) for a, b in itertools.combinations(seats, 2)
             if args.pairs == "all" or {family[a], family[b]} == set(args.pairs.split("-"))
             or (args.pairs in family.values() and family[a] == family[b] == args.pairs)]
    for a, b in pairs:
        for hero, field in ((a, b), (b, a)):
            for chair in range(4):
                table = [field] * 4
                table[chair] = hero
                games += [{"match": f"{hero} vs {field}", "seed": seed, "seats": table} for seed in seeds]
    print(f"{len(seats)} variants, {len(pairs)} pairs, "
          f"{write_jsonl(args.out, games)} games -> {args.out}")


def cmd_run(args) -> None:
    args.results_dir.mkdir(parents=True, exist_ok=True)
    workers = []
    for shard in range(args.workers):
        out = args.results_dir / f"shard-{shard}.jsonl"
        command = [str(args.arena), "--schedule", str(args.schedule), "--seats-dir", str(args.seats_dir),
                   "--shard", f"{shard}/{args.workers}", "--done", str(out)]
        workers.append(subprocess.Popen(command, stdout=out.open("a"),
                                        stderr=(args.results_dir / f"shard-{shard}.err").open("a")))
    failed = [w.args for w in workers if w.wait() != 0]
    if failed:
        sys.exit(f"{len(failed)} shard(s) failed; re-run to resume: {failed[0]}")


# MARK: analysis

def wilson(wins: float, n: int) -> tuple[float, float]:
    if n == 0:
        return (0.0, 1.0)
    z, p = 1.96, wins / n
    centre = (p + z * z / (2 * n)) / (1 + z * z / n)
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / (1 + z * z / n)
    return (centre - half, centre + half)


def fit_ratings(games: list[dict], iterations: int = 2000) -> dict[str, float]:
    """Winner-only Plackett-Luce: P(seat i wins) = exp(r_i) / sum exp(r_j).

    Minorise-maximise (Hunter 2004) with a weak prior so an unbeaten variant
    stays finite. Reported on an Elo-like scale: 400 * log10(e) * r, centred so
    the mean variant is 1500.
    """
    names = sorted({seat for game in games for seat in game["seats"]})
    strength = {name: 1.0 for name in names}
    wins = defaultdict(float)
    for game in games:
        wins[game["seats"][game.get("winner")]] += 1
    for _ in range(iterations):
        denominators = defaultdict(float)
        for game in games:
            total = sum(strength[s] for s in game["seats"])
            for seat in game["seats"]:
                denominators[seat] += 1 / total
        updated = {n: (wins[n] + 1) / (denominators[n] + 2 / (strength[n] + 1)) for n in names}
        scale = math.exp(sum(math.log(v) for v in updated.values()) / len(updated))
        change = max(abs(math.log(updated[n] / scale / strength[n])) for n in names)
        strength = {n: updated[n] / scale for n in names}
        if change < 1e-9:
            break
    elo = 400 / math.log(10)
    return {n: 1500 + elo * math.log(strength[n]) for n in names}


def label(seat: str, labels: dict[str, str]) -> str:
    return labels.get(seat, seat)


def cmd_analyse(args) -> None:
    games = [g for path in args.results for g in read_jsonl(path) if not g["match"].startswith("probe")]
    labels = {}
    if args.roster:
        for row in json.loads(args.roster.read_text()):
            labels[row["seat"]] = row.get("label", row["seat"])
    decisive = [g for g in games if g["winner"] is not None]
    print(f"{len(games)} games, {len(decisive)} decisive ({len(decisive) / max(len(games), 1):.1%})\n")

    pairs: dict[tuple[str, str], list[int]] = defaultdict(lambda: [0, 0, 0])
    for game in games:
        hero, field = game["match"].split(" vs ")
        cell = pairs[(hero, field)]
        cell[1] += 1
        if game.get("winner") is None:
            cell[2] += 1
        elif game["seats"][game.get("winner")] == hero:
            cell[0] += 1

    ratings = fit_ratings(decisive) if decisive else {}
    print("Ratings (winner-only Plackett-Luce over every decisive game; mean variant = 1500)")
    for seat, rating in sorted(ratings.items(), key=lambda kv: -kv[1]):
        print(f"  {rating:7.0f}  {label(seat, labels)}")

    print("\nHead to head: one hero vs three copies of the field, hero rotated through all four chairs."
          " Null = 25%.")
    for (hero, field), (won, played, unfinished) in sorted(pairs.items(), key=lambda kv: kv[0]):
        low, high = wilson(won, played - unfinished)
        rate = won / max(played - unfinished, 1)
        print(f"  {label(hero, labels):34} vs 3x {label(field, labels):34} {rate:6.1%}  "
              f"[{low:.1%}, {high:.1%}]  n={played - unfinished}" + (f" unfinished={unfinished}" if unfinished else ""))

    print("\nHand size at the end of own turns, per variant (all its seats, all games)")
    hands = defaultdict(lambda: defaultdict(int))
    for game in games:
        for result in game["results"]:
            h = hands[result["seat"]]
            for key in ("turnsEnded", "turnsEndedOverSeven", "turnsEndedOverFifteen", "handAtEndTurnTotal",
                        "cardsDiscarded", "fallbacks", "decodeErrors", "decisions"):
                h[key] += result[key]
            h["games"] += 1
            h["maxHand"] = max(h["maxHand"], result["maxHand"])
    print(f"  {'variant':34} {'avg hand':>8} {'>7 ends':>8} {'>15 ends':>8} {'discarded/g':>11} "
          f"{'max':>4} {'fallback':>8}")
    for seat, h in sorted(hands.items(), key=lambda kv: label(kv[0], labels)):
        ends = max(h["turnsEnded"], 1)
        print(f"  {label(seat, labels):34} {h['handAtEndTurnTotal'] / ends:8.2f} "
              f"{h['turnsEndedOverSeven'] / ends:8.2%} {h['turnsEndedOverFifteen'] / ends:8.3%} "
              f"{h['cardsDiscarded'] / h['games']:11.2f} {h['maxHand']:4d} "
              f"{(h['fallbacks'] + h['decodeErrors']) / max(h['decisions'], 1):8.4%}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    probe = sub.add_parser("probe")
    probe.add_argument("--seats-dir", type=Path, required=True)
    probe.add_argument("--out", type=Path, required=True)
    probe.set_defaults(run=cmd_probe)

    roster = sub.add_parser("roster")
    roster.add_argument("--results", type=Path, required=True)
    roster.add_argument("--out", type=Path, required=True)
    roster.add_argument("--max-fallback", type=float, default=0.005)
    roster.set_defaults(run=cmd_roster)

    schedule = sub.add_parser("schedule")
    schedule.add_argument("--roster", type=Path, required=True)
    schedule.add_argument("--seeds", type=int, required=True)
    schedule.add_argument("--first-seed", type=int, default=9_000_000)
    schedule.add_argument("--out", type=Path, required=True)
    schedule.add_argument("--pairs", default="all",
                          help="all, or a family (expert: expert vs expert), or two joined by '-' "
                               "(expert-classic: every expert vs every classic)")
    schedule.set_defaults(run=cmd_schedule)

    run = sub.add_parser("run")
    run.add_argument("--arena", type=Path, required=True)
    run.add_argument("--schedule", type=Path, required=True)
    run.add_argument("--seats-dir", type=Path, required=True)
    run.add_argument("--results-dir", type=Path, required=True)
    run.add_argument("--workers", type=int, default=6)
    run.set_defaults(run=cmd_run)

    analyse = sub.add_parser("analyse")
    analyse.add_argument("results", type=Path, nargs="+")
    analyse.add_argument("--roster", type=Path)
    analyse.set_defaults(run=cmd_analyse)

    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
