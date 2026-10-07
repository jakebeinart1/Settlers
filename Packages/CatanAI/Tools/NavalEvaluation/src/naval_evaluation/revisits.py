"""Inspect every preserved successful trajectory containing a raw ship revisit."""

import hashlib
import json
import pathlib
import shutil
from typing import Any


def trace_fingerprint(lines: list[str]) -> str:
    """Reproduce naval-sim's FNV-1a over canonical moves, excluding newlines."""
    value = 0xCBF29CE484222325
    for line in lines:
        for byte in line.encode("utf-8"):
            value = ((value ^ byte) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return f"{value:016x}"


def artifact_name(row: dict[str, Any]) -> str:
    """Match the frozen harness's diagnostic filename exactly."""
    fog = "true" if row["fogEnabled"] else "false"
    wild = "true" if row["resourceChoiceEnabled"] else "false"
    return (
        f'{row["seed"]}-{row["playerCount"]}-{row["focalChair"]}-'
        f'{row["arm"]}-{row["family"]}-{fog}-{wild}'
    )


def inspect(row: dict[str, Any], directory: pathlib.Path) -> dict[str, Any]:
    """Reject missing/truncated/mismatched endpoint, trace, or rejection evidence."""
    name = artifact_name(row)
    reason = (directory / f"{name}.failure").read_text()
    expected = (
        f'build={row["buildID"]}\nCompletion/revisit evidence: '
        f'winner=Optional({row["winner"]}), forced=0, '
        f'raw sailing={row["sailingCycles"]}, idle sailing=0, trading=0\n'
    )
    if reason != expected:
        raise ValueError(f"unexpected revisit verdict: {name}")
    trace = (directory / f"{name}.txt").read_text().splitlines()
    if len(trace) != row["moves"] or trace_fingerprint(trace) != row["fingerprint"]:
        raise ValueError(f"truncated or divergent revisit trace: {name}")
    checkpoint = json.loads((directory / f"{name}.json").read_text())
    if checkpoint["state"]["phase"] != {
        "gameOver": {"winner": {"index": row["winner"]}}
    }:
        raise ValueError(f"revisit checkpoint winner mismatch: {name}")
    digests = {
        f"{name}.{suffix}": hashlib.sha256(
            (directory / f"{name}.{suffix}").read_bytes()
        ).hexdigest()
        for suffix in ("failure", "txt", "json")
    }
    return dict(
        name=name,
        rawRevisits=row["sailingCycles"],
        idleRevisits=0,
        winner=row["winner"],
        fingerprint=row["fingerprint"],
        sha256=digests,
    )


def preserve(
    rows: list[dict[str, Any]], source: pathlib.Path, destination: pathlib.Path
) -> dict[str, Any]:
    """Keep indexed full traces/checkpoints outside Git without discarding cases."""
    records = [inspect(row, source) for row in rows if row["sailingCycles"]]
    destination.mkdir(parents=True, exist_ok=True)
    for record in records:
        for filename, digest in record["sha256"].items():
            target = destination / filename
            if (
                target.exists()
                and hashlib.sha256(target.read_bytes()).hexdigest() != digest
            ):
                raise ValueError(f"previous diagnostic artifact differs: {filename}")
            shutil.copy2(source / filename, target)
    return dict(
        artifactDirectory=str(destination),
        gamesInspected=len(records),
        rawRevisits=sum(record["rawRevisits"] for record in records),
        idleRevisits=0,
        records=records,
    )
