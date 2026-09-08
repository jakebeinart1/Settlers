#!/usr/bin/env python3
"""Validate diagnostic traces and produce bounded, outcome-blind trade packets.

This is a first workflow trial, not a strategic judge. It checks the arithmetic
the Swift scorer emitted and samples complete decision records. Raw states stay
in the trace; the LLM view uses an explicit allowlist, never arbitrary JSON or
the eventual winner. Output directories must be new to preserve prior evidence.
Checks journal accounting, not native rules replay (not implemented here).
"""

import argparse
import hashlib
import json
import math
import random
import re
import shutil
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
MAX_LINE_BYTES = 8 * 1024 * 1024
MAX_PACKET_CHARS = 8000
SHIFTS = ("threatShift", "standingShift", "suspicionShift", "unlockShift")
HEURISTIC_IDS = {"heuristic-balanced", "heuristic-aggressive", "heuristic-cautious"}
ANCHOR_IDS = {"random", "greedy"}
SET_FIELDS = {"onBoardVertices", "onBoardEdges", "settlements", "cities", "roads", "pending"}
MAP_FIELDS = {"resources", "bank", "give", "get", "want", "amounts", "policyIDs",
              "devCardsBoughtThisTurn", "tradesAcceptedThisTurn", "declinedTradeOffersThisTurn"}


def semantic(value: Any, field: str = "") -> Any:
    """Normalize only native unordered collections, never decks or action order."""
    if isinstance(value, dict):
        return {key: semantic(item, "amounts" if field == "discard" else key)
                for key, item in value.items()}
    if not isinstance(value, list):
        return value
    items = [semantic(item) for item in value]
    if field in SET_FIELDS:
        return sorted(items, key=lambda item: json.dumps(item, sort_keys=True))
    if field in MAP_FIELDS and not (
        field == "policyIDs" and all(isinstance(item, str) for item in items)
    ):
        if len(items) % 2:
            raise ValueError(f"invalid native map: {field}")
        return sorted(zip(items[::2], items[1::2]),
                      key=lambda pair: json.dumps(pair[0], sort_keys=True))
    return items


def require_fields(value: dict, fields: tuple[str, ...]) -> None:
    if not isinstance(value, dict) or any(value.get(key) is None for key in fields):
        raise ValueError(f"missing required fields: {fields}")


def validate_checkpoint(payload: dict, count: int, rng: dict) -> dict:
    require_fields(payload, ("checkpoint",))
    checkpoint = payload["checkpoint"]
    require_fields(checkpoint, ("state", "policyEvaluationCount", "policyRNG"))
    if checkpoint["policyEvaluationCount"] != count or checkpoint["policyRNG"] != rng:
        raise ValueError("checkpoint count/RNG disagrees with returned evaluations")
    return semantic(checkpoint)


def start_identity(seed: int, payload: dict) -> tuple:
    require_fields(payload, ("buildID", "boardMode", "policyIDs", "initialState"))
    state = payload["initialState"]
    return (seed, len(state["players"]), state["victoryPointTarget"],
            payload["boardMode"], tuple(payload["policyIDs"]), payload["buildID"])


def scheduled_identities(path: Path) -> Counter:
    """Ordered seat IDs identify rotations; retain multiplicities, not just a set."""
    schedule = json.loads(path.read_text(), parse_constant=reject_constant,
                          object_pairs_hook=strict_object)
    digest = schedule["binarySHA256"]
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("invalid schedule binarySHA256")
    def policy_id(name):
        return name if name in ANCHOR_IDS else f"heuristic-{name}"
    return Counter((game["seed"], game["players"], schedule["victoryPointTarget"],
                    game["board"], tuple(policy_id(name) for name in game["seats"]),
                    "corpus-" + digest[:16]) for game in schedule["games"])


def reject_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON constant: {value}")


def strict_object(pairs: list) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def close(actual: float, expected: float) -> None:
    if not math.isfinite(actual) or not math.isclose(
        actual, expected, rel_tol=1e-10, abs_tol=1e-10
    ):
        raise ValueError(f"assessment mismatch: {actual} != {expected}")


def validate_assessment(assessment: dict) -> None:
    """Check emitted scalar accounting, not whether its valuation is wise."""
    close(assessment["netGain"], assessment["gainValue"] - assessment["costValue"])
    threshold = max(
        0, assessment["baseThreshold"] + sum(assessment[key] for key in SHIFTS)
    )
    close(assessment["threshold"], threshold)
    accepted = assessment["netGain"] > assessment["threshold"]
    if assessment["accepted"] is not accepted:
        raise ValueError("strict threshold decision does not match assessment")


def is_trade_response(move: dict) -> bool:
    return "respondToTrade" in move


def parse_rows(path: Path):
    """Read bounded rows; a partial final row is failure, never silently dropped."""
    with path.open("rb") as stream:
        line_number = 0
        while line := stream.readline(MAX_LINE_BYTES + 1):
            line_number += 1
            if len(line) > MAX_LINE_BYTES or not line.endswith(b"\n"):
                raise ValueError(f"{path}:{line_number}: oversized/truncated row")
            row = json.loads(
                line, parse_constant=reject_constant, object_pairs_hook=strict_object
            )
            if row["schemaVersion"] != SCHEMA_VERSION:
                raise ValueError("unsupported trace version")
            yield line_number, row


def read_trace(path: Path, starts: list | None = None) -> tuple[list[dict], dict]:
    """Reconcile journal/RNG accounting, not legality of replayed state changes."""
    candidates = []
    counts: Counter = Counter()
    active_seed = None
    expected = 0
    pending = None
    commits = 0
    seen_seeds = set()
    for line, row in parse_rows(path):
        kind, seed, payload = row["type"], row["seed"], row["payload"]
        if kind == "start":
            if active_seed is not None or seed in seen_seeds:
                raise ValueError("duplicate or unterminated game")
            active_seed, expected, commits, pending = seed, 0, 0, None
            identity = start_identity(seed, payload)
            if starts is not None:
                starts.append(identity)
            roster = payload["policyIDs"]
            previous_rng = {"state": (seed * 31 + 7) & ((1 << 64) - 1)}
            last_checkpoint = None
            seen_seeds.add(seed)
            counts["games"] += 1
            continue
        if active_seed != seed:
            raise ValueError("row outside its game")
        if kind == "invocation":
            if pending is not None or payload["evaluationIndex"] != expected:
                raise ValueError("invocation gap or duplicate")
            require_fields(payload, ("policyID", "policyRNGBefore", "observation"))
            if payload["policyRNGBefore"] != previous_rng:
                raise ValueError("invocation RNG continuity broken")
            seat = payload["observation"]["seat"]["index"]
            if not 0 <= seat < len(roster) or payload["policyID"] != roster[seat]:
                raise ValueError("invocation policyID disagrees with roster")
            pending = payload
        elif kind == "evaluation":
            if pending is None or payload["evaluationIndex"] != expected:
                raise ValueError("return without matching invocation")
            require_fields(payload, ("policyID", "policyRNGBefore", "policyRNGAfter", "observation"))
            for field in ("policyID", "policyRNGBefore", "observation"):
                if semantic(payload[field]) != semantic(pending[field]):
                    raise ValueError(f"invocation/return mismatch: {field}")
            validate_evaluation(payload)
            candidate = compact_candidate(path, line, seed, payload)
            if candidate:
                candidates.append(candidate)
                counts["tradeResponseOpportunities"] += 1
                counts["tradeResponsesAccepted"] += int(candidate["accepted"])
                counts["tradeResponsesAcceptLegal"] += int(candidate["acceptLegal"])
                counts["tradeResponsesForcedReject"] += int(not candidate["acceptLegal"])
            counts["evaluations"] += 1
            expected += 1
            previous_rng = payload["policyRNGAfter"]
            pending = None
        elif kind == "commit":
            if pending is not None or payload["moveIndex"] != commits:
                raise ValueError("invalid commit order")
            require_fields(payload, ("actor", "move", "checkpoint"))
            last_checkpoint = validate_checkpoint(payload, expected, previous_rng)
            commits += 1
            counts["commits"] += 1
        elif kind == "end":
            if pending is not None or payload["evaluationCount"] != expected:
                raise ValueError("missing evaluations at game end")
            if payload["moves"] != commits:
                raise ValueError("missing committed moves")
            checkpoint = validate_checkpoint(payload, expected, previous_rng)
            if last_checkpoint is not None and checkpoint != last_checkpoint:
                raise ValueError("final checkpoint differs from last commit")
            counts[payload["reason"]] += 1
            active_seed = None
        else:
            raise ValueError(f"unknown or failed record: {kind}")
    if active_seed is not None or pending is not None:
        raise ValueError("trace ended without terminal accounting")
    if not seen_seeds:
        raise ValueError("empty trace")
    return candidates, dict(counts)


def validate_evaluation(payload: dict) -> None:
    observation = payload["observation"]
    if semantic(payload["chosenMove"]) not in semantic(observation["legalMoves"]):
        raise ValueError("chosen move outside actual action mask")
    policy = payload["policyID"]
    if policy not in HEURISTIC_IDS | ANCHOR_IDS:
        raise ValueError("unsupported policy assessment contract")
    if policy in ANCHOR_IDS and payload["tradeAssessments"]:
        raise ValueError("nonheuristic policy emitted heuristic assessments")
    for assessment in payload["tradeAssessments"]:
        if assessment["receiver"] != observation["seat"]:
            raise ValueError("assessment receiver disagrees with observation")
        if semantic(assessment["offer"]) not in semantic(observation["state"]["pendingTradeOffers"]):
            raise ValueError("assessment offer disagrees with observation")
        validate_assessment(assessment)
    if observation["legalMoves"] and all(
        is_trade_response(move) for move in observation["legalMoves"]
    ):
        response = payload["chosenMove"]["respondToTrade"]
        matching = [a for a in payload["tradeAssessments"]
                    if a["offer"]["id"] == response["offerID"]]
        accept_legal = any(move["respondToTrade"]["accept"] for move in observation["legalMoves"])
        if policy in HEURISTIC_IDS and accept_legal and not matching:
            raise ValueError("missing optional heuristic response assessment")
        if not accept_legal and payload["tradeAssessments"]:
            raise ValueError("reject-only response unexpectedly emitted assessments")
        if matching and matching[-1]["accepted"] != response["accept"]:
            raise ValueError("scoped response disagrees with its actual assessment")


def resource_map(value: Any) -> dict:
    """Swift encodes enum-keyed dictionaries as alternating key/value arrays."""
    if isinstance(value, dict):
        return value
    if not isinstance(value, list) or len(value) % 2:
        raise ValueError("invalid resource map")
    return strict_object(list(zip(value[::2], value[1::2])))


def compact_candidate(path: Path, line: int, seed: int, payload: dict) -> Any:
    observation = payload["observation"]
    if not all(is_trade_response(move) for move in observation["legalMoves"]):
        return None
    response = payload["chosenMove"]["respondToTrade"]
    assessments = payload["tradeAssessments"]
    relevant = [a for a in assessments if a["offer"]["id"] == response["offerID"]]
    state = observation["state"]
    players = [{"seat": p["id"]["index"], "resources": resource_map(p["resources"]),
                "settlements": len(p["settlements"]), "cities": len(p["cities"]),
                "roads": len(p["roads"])} for p in state["players"]]
    return {
        "source": str(path.resolve()), "line": line, "seed": seed,
        "evaluationIndex": payload["evaluationIndex"],
        "receiver": observation["seat"]["index"], "players": players,
        "target": state["victoryPointTarget"],
        "offers": [offer for offer in state["pendingTradeOffers"] if offer["id"] == response["offerID"]],
        "context": [line for line in payload.get("observationText", "").splitlines()
                    if line.startswith(("OBS v", "KEY ", "BANK ")) or re.match(r"^P\d+ ", line)],
        "accepted": response["accept"], "assessments": relevant,
        "acceptLegal": any(m["respondToTrade"]["accept"] for m in observation["legalMoves"]),
    }


def choose_packets(candidates: list[dict], seed: int, count: int) -> list[dict]:
    """Sample seed families, then games, then decisions; rotations stay together."""
    groups: dict = defaultdict(list)
    for candidate in candidates:
        groups[(candidate["source"], candidate["seed"])].append(candidate)
    rng = random.Random(seed)
    families: dict = defaultdict(list)
    for key in sorted(groups):
        families[key[1]].append(key)
    keys = sorted(families)
    rng.shuffle(keys)
    return [rng.choice(groups[rng.choice(families[key])]) for key in keys[:count]]


def packet_text(candidate: dict, reveal: bool) -> str:
    """Explicit allowlist; no raw state/RNG/deck/seed/outcome reaches this view."""
    lines = ["# Trade decision review", "",
             "Information: this native policy receives every player's exact resource hand and development-card identities. "
             "This is reveal-all research, not a hidden-information claim.",
             "Resource names: grain = wheat; lumber = wood; wool = sheep. Missing hand resources are zero.",
             "This packet is incomplete for spatial/production judgments; request context before concluding.",
             f"Receiver: P{candidate['receiver']}; victory target: {candidate['target']}.",
             f"Accept is legal: {candidate['acceptLegal']}. Reject is available.",
             "", "## Players"]
    lines.extend(f"- P{p['seat']}: hand={json.dumps(p['resources'], sort_keys=True)}; "
                 f"settlements={p['settlements']}, cities={p['cities']}, roads={p['roads']}"
                 for p in candidate["players"])
    if candidate["context"]:
        lines.extend(["", "## Native current-position facts", "```text",
                      *candidate["context"], "```",
                      "Native abbreviations: br=brick, lu=lumber, or=ore, gr=grain, wo=wool. "
                      "Position indices require a separate board graph; do not infer adjacency."])
    lines.extend(["", "## Offer being evaluated (give/want are from the proposer's perspective)"])
    for offer in candidate["offers"]:
        lines.append(f"- P{offer['from']['index']} gives {json.dumps(resource_map(offer['give']), sort_keys=True)}; "
                     f"asks for {json.dumps(resource_map(offer['want']), sort_keys=True)}.")
    if reveal:
        lines.extend(["", "## Actual decision and scorer accounting",
                      f"Selected: {'accept' if candidate['accepted'] else 'reject'}."])
        for assessment in candidate["assessments"]:
            lines.append(f"- Gain={assessment['gainValue']:.6g}; cost={assessment['costValue']:.6g}; "
                         f"net={assessment['netGain']:.6g}.")
            lines.append(f"- Threshold={assessment['threshold']:.6g}: base={assessment['baseThreshold']:.6g}, "
                         + ", ".join(f"{key}={assessment[key]:.6g}" for key in SHIFTS))
        lines.append("Acceptance requires net > threshold, not equality. unlockShift means newly affordable "
                     "settlement/city resource cost, NOT verified legal placement or an immediate win.")
        if not candidate["assessments"]:
            lines.append("No score was emitted: investigate masking/early exit; do not invent an explanation.")
    lines.extend(["", "## Review questions", "What evidence is missing? Could either action be reasonable?",
                  "Separate arithmetic/implementation evidence from strategic hypotheses.",
                  "State a counterexample to any suggested rule and a test that could refute it."])
    result = "\n".join(lines) + "\n"
    if len(result) > MAX_PACKET_CHARS:
        raise ValueError("packet exceeds context budget; do not silently truncate")
    return result


def write_report(paths: list[Path], output: Path, seed: int, count: int,
                 expected_games: int, cohort: str = "all", schedule: Path | None = None) -> None:
    if len({path.resolve() for path in paths}) != len(paths):
        raise ValueError("duplicate trace paths")
    expected_starts = scheduled_identities(schedule) if schedule is not None else None
    starts = []
    candidates = []
    counts: Counter = Counter()
    sources = []
    for path in paths:
        rows, metrics = read_trace(path, starts)
        candidates.extend(rows)
        counts.update(metrics)
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        sources.append({"path": str(path.resolve()), "sha256": digest})
    if counts["games"] != expected_games:
        raise ValueError(f"expected {expected_games} games, received {counts['games']}; incomplete input manifest")
    if expected_starts is not None and Counter(starts) != expected_starts:
        raise ValueError("trace starts do not match schedule membership/cells/rosters/build")
    eligible = [row for row in candidates if cohort == "all"
                or row["acceptLegal"] == (cohort == "optional")]
    selected = choose_packets(eligible, seed, count)
    output.mkdir(parents=True, exist_ok=False)
    manifest = {"schemaVersion": 1, "samplingSeed": seed, "counts": dict(counts),
                "cohort": cohort, "eligibleDecisionCount": len(eligible),
                "sources": sources, "packets": [],
                "selection": "uniform seed families, then uniform games, then uniform scoped trade decision"}
    manifest["validation"] = {"journalAccounting": True, "nativeRulesReplay": False,
                              "scheduleMembership": schedule is not None}
    if schedule is not None:
        manifest["schedule"] = {"path": str(schedule.resolve()),
                                "sha256": hashlib.sha256(schedule.read_bytes()).hexdigest()}
    with Path(__file__).open("rb") as stream:
        manifest["rendererSHA256"] = hashlib.file_digest(stream, "sha256").hexdigest()
    shutil.copy2(Path(__file__), output / "renderer.py")
    for index, candidate in enumerate(selected):
        packet_id = f"case-{index + 1:03d}"
        for name, reveal in (("blind", False), ("explained", True)):
            text = f"Sampling cohort: {cohort}. Filtered cohorts do not estimate overall frequency.\n\n"
            text += packet_text(candidate, reveal)
            (output / f"{packet_id}-{name}.md").write_text(text)
        manifest["packets"].append({"id": packet_id, "source": candidate["source"],
                                    "line": candidate["line"], "seed": candidate["seed"],
                                    "evaluationIndex": candidate["evaluationIndex"]})
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"counts": dict(counts), "packets": len(selected), "output": str(output)}))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("traces", nargs="+", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sampling-seed", type=int, required=True)
    parser.add_argument("--count", type=int, default=12)
    parser.add_argument("--expected-games", type=int, required=True)
    parser.add_argument("--schedule", type=Path, help="Pilot schedule.json for exact start membership")
    parser.add_argument("--cohort", choices=("all", "optional", "forced"), default="all")
    args = parser.parse_args()
    if not 1 <= args.count <= 120:
        parser.error("count must be between 1 and 120")
    if args.expected_games < 1:
        parser.error("expected-games must be positive")
    write_report(args.traces, args.output, args.sampling_seed, args.count,
                 args.expected_games, args.cohort, args.schedule)


if __name__ == "__main__":
    main()
