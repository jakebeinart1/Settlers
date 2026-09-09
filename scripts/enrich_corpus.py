#!/usr/bin/env python3
"""Enrich already selected decisions without replaying/collecting games.

The full corpus must first pass review_corpus with exact schedule validation.
Verify source hashes, parse only selected rows, and use the native offline tool
for game facts. Private input snapshots never go into the blind LLM packets.
"""

import argparse
import hashlib
import json
import shutil
import subprocess
import time
from collections import defaultdict
from pathlib import Path

from review_corpus import (
    compact_candidate, packet_text, validate_assessment, validate_evaluation,
)


PROCESS_TIMEOUT_SECONDS = 60
MAX_PACKET_CHARACTERS = 12000


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def selected_rows(manifest: dict) -> list[dict]:
    hashes = {source["path"]: source["sha256"] for source in manifest["sources"]}
    groups: dict = defaultdict(dict)
    for packet in manifest["packets"]:
        groups[packet["source"]][packet["line"]] = packet
    rows = {}
    for source, wanted in groups.items():
        path = Path(source)
        if digest(path) != hashes[source]:
            raise ValueError("source hash changed after validation")
        # Skip unselected rows as bytes: don't decode every repeated board.
        with path.open("rb") as stream:
            for number, raw in enumerate(stream, 1):
                if number not in wanted:
                    continue
                row = json.loads(raw)
                packet = wanted[number]
                if row["type"] != "evaluation" or row["seed"] != packet["seed"] \
                        or row["payload"]["evaluationIndex"] != packet["evaluationIndex"]:
                    raise ValueError("selected row identity mismatch")
                validate_evaluation(row["payload"])
                rows[packet["id"]] = {"id": packet["id"], **row["payload"]}
                if number == max(wanted):
                    break
    if len(rows) != len(manifest["packets"]):
        raise ValueError("missing or duplicate selected rows")
    return [rows[packet["id"]] for packet in manifest["packets"]]


def resource_text(values: dict) -> str:
    return ", ".join(f"{key}={value:.3g}" for key, value in sorted(values.items()))


def context_text(context: dict) -> str:
    lines = ["## Native before/after evidence", "",
             "Acceptance tested on a COPY using native rules. No future dice or deck order used.",
             "Options below assume that seat's main turn on this frozen board; off-turn seats cannot build now.",
             "Counts include affordability, placement and piece limits, not usefulness or multi-step plans.",
             "Production = expected cards per next roll with current bank/robber; excludes seven losses."]
    after = context.get("afterAcceptance")
    for index, before in enumerate(context["before"]):
        lines.append(f"\nP{before['seat']}: acts now={before['mainTurnNow']}; "
                     f"VP public/total={before['publicVP']}/{before['totalVP']}.")
        lines.append(f"Hand before: {resource_text(before['hand'])}.")
        if after is not None:
            lines.append(f"Hand after accepting: {resource_text(after[index]['hand'])}.")
        lines.append(f"Production/roll: {resource_text(before['expectedCardsPerRoll'])}.")
        lines.append(f"Bank rates: {resource_text(before['bankRates'])}.")
        lines.append(f"Own-main-turn options before: {json.dumps(before['mainTurnOptionsOnFrozenBoard'], sort_keys=True)}")
        if after is not None:
            lines.append(f"Own-main-turn options after: {json.dumps(after[index]['mainTurnOptionsOnFrozenBoard'], sort_keys=True)}")
    if context.get("nativeAcceptanceError"):
        lines.append(f"Native acceptance error: {context['nativeAcceptanceError']}; no fabricated after-state.")
    return "\n".join(lines) + "\n"


def publish_packets(inputs: list[dict], output: Path, results: list[dict]) -> None:
    for original, result in zip(inputs, results, strict=True):
        case_id = result["id"]
        native = context_text(result["context"])
        candidate = compact_candidate(Path("private-input.jsonl"), 0, 0, original)
        if candidate is None:
            raise ValueError("only scoped trade responses can be enriched")
        for suffix in ("blind", "explained"):
            # Regenerate the allowlisted view from verified native input, not
            # a Markdown file that might have been edited after selection.
            base = packet_text(candidate, reveal=suffix == "explained")
            base = base.replace(
                "This packet is incomplete for spatial/production judgments; request context before concluding.",
                "Production and immediate build options are supplied below. Spatial rankings and future play remain unknown.")
            text = base + "\n" + native
            if suffix == "explained" and result.get("assessment"):
                text += "\n## Resource-score inputs (offline recomputation; original scalars numerically matched)\n"
                text += "Scalar tolerance: 1e-12 relative/absolute; accept/reject must match exactly.\n"
                text += json.dumps(result["assessment"].get("resourceContributions"), sort_keys=True) + "\n"
                text += "Loss values use the ORIGINAL hand, not the depleted hand. Contributions explain the scorer, not optimal play.\n"
            if len(text) > MAX_PACKET_CHARACTERS:
                raise ValueError(f"{case_id} exceeds packet budget; no silent truncation")
            (output / f"{case_id}-{suffix}.md").write_text(text)


def enrich(review: Path, binary: Path, output: Path) -> None:
    started = time.monotonic()
    manifest = json.loads((review / "manifest.json").read_text())
    if not manifest.get("validation", {}).get("scheduleMembership"):
        raise ValueError("exact-schedule validated review required")
    if not 1 <= len(manifest["packets"]) <= 120:
        raise ValueError("expected 1–120 selected cases")
    inputs = selected_rows(manifest)
    output.mkdir(parents=True, exist_ok=False)
    snapshot = output / "private-input.jsonl"
    snapshot.write_text("".join(json.dumps(row) + "\n" for row in inputs))
    frozen = output / "trade-review"
    shutil.copy2(binary, frozen)
    with (output / "native-output.jsonl").open("x") as stdout, \
            (output / "native-stderr.log").open("x") as stderr:
        subprocess.run([str(frozen), str(snapshot)], stdout=stdout, stderr=stderr,
                       check=True, timeout=PROCESS_TIMEOUT_SECONDS)
    results = [json.loads(row) for row in (output / "native-output.jsonl").read_text().splitlines()]
    if [row["id"] for row in results] != [row["id"] for row in inputs]:
        raise ValueError("native result identities differ from selected cases")
    for result in results:
        if result.get("assessment"):
            validate_assessment(result["assessment"])
    publish_packets(inputs, output, results)
    shutil.copy2(Path(__file__), output / "enricher.py")
    shutil.copy2(Path(__file__).with_name("review_corpus.py"), output / "review_corpus.py")
    receipt = {"schemaVersion": 1, "status": "complete", "cases": len(results),
               "sourceManifest": str((review / "manifest.json").resolve()),
               "sourceManifestSHA256": digest(review / "manifest.json"),
               "binarySHA256": digest(frozen), "inputSHA256": digest(snapshot),
               "nativeOutputSHA256": digest(output / "native-output.jsonl"),
               "enricherSHA256": digest(Path(__file__)),
               "reviewRendererSHA256": digest(Path(__file__).with_name("review_corpus.py")),
               "elapsedSeconds": time.monotonic() - started}
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review", type=Path, required=True)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    enrich(args.review, args.binary, args.output)


if __name__ == "__main__":
    main()
