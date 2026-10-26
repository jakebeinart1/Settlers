#!/usr/bin/env python3
"""Download every ranked ladder game from CloudKit to this Mac.

Every rated game a phone finishes is uploaded as a `Match` record: the opening
position and every move (`Settlers/Sync/SharedMatch.swift`). Phones replay a
downloaded game for its result and drop the moves, so this is how the Mac gets
everyone's games for `ghost fidelity` and ghost training (Jake, 2026-10-24:
"that data is very valuable").

It reads the public database with a CloudKit server-to-server key, which only
the container's owner (Alex) can create: `docs/cloudkit-server-key.md`.

Usage:
  scripts/cloudkit-games.py fetch [--out DIR] [--environment production]
  scripts/cloudkit-games.py players [--out DIR]     # who is in DIR: finished games and restarts
  scripts/cloudkit-games.py restarts [--out DIR]    # each restart: when, who, how far in

Key: `$EMPIRES_CLOUDKIT_KEY_ID` and `$EMPIRES_CLOUDKIT_KEY` (a PEM path), or
`~/.config/empires/cloudkit/key-id` and `~/.config/empires/cloudkit/key.pem`.
Never commit either.

Each game is written once, as `<match>.json`:
  {"owner": "<uploader's user id>", "ownerName": "Kbeast", "modified": ..., "game": <SharedMatch>}
The person seat in `game.seats` is the uploader's decisions; `ghost` reads these files.
"""

import argparse
import base64
import datetime
import hashlib
import json
import os
import subprocess
import sys
import urllib.request
from collections import Counter
from pathlib import Path

CONTAINER = "iCloud.com.alexchandler.empires"
API = "https://api.apple-cloudkit.com"
CONFIG = Path.home() / ".config" / "empires" / "cloudkit"
DEFAULT_OUT = Path.home() / "Library" / "Caches" / "empires-cloud-games"
PAGE = 200


def key_paths():
    key_id = os.environ.get("EMPIRES_CLOUDKIT_KEY_ID")
    if key_id is None and (CONFIG / "key-id").exists():
        key_id = (CONFIG / "key-id").read_text().strip()
    pem = Path(os.environ.get("EMPIRES_CLOUDKIT_KEY", CONFIG / "key.pem"))
    if not key_id or not pem.exists():
        sys.exit(f"No CloudKit server key: set EMPIRES_CLOUDKIT_KEY_ID/EMPIRES_CLOUDKIT_KEY or fill {CONFIG}. "
                 "Alex creates it: docs/cloudkit-server-key.md")
    return key_id, pem


def signed_message(date: str, body: bytes, subpath: str) -> bytes:
    """What CloudKit's server-to-server auth signs: date, body hash, path."""
    digest = base64.b64encode(hashlib.sha256(body).digest()).decode()
    return f"{date}:{digest}:{subpath}".encode()


def sign(message: bytes, pem: Path) -> str:
    """ECDSA P-256 over SHA-256, DER, base64 - via openssl, so no pip installs."""
    result = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(pem)], input=message,
                            capture_output=True, check=True)
    return base64.b64encode(result.stdout).decode()


def subpath(environment: str, operation: str) -> str:
    return f"/database/1/{CONTAINER}/{environment}/public/{operation}"


def request(environment: str, operation: str, payload: dict, key_id: str, pem: Path) -> dict:
    path = subpath(environment, operation)
    body = json.dumps(payload).encode()
    date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    req = urllib.request.Request(API + path, data=body, method="POST", headers={
        "Content-Type": "application/json",
        "X-Apple-CloudKit-Request-KeyID": key_id,
        "X-Apple-CloudKit-Request-ISO8601Date": date,
        "X-Apple-CloudKit-Request-SignatureV1": sign(signed_message(date, body, path), pem),
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        sys.exit(f"CloudKit {operation} failed: HTTP {error.code} {error.read().decode(errors='replace')}")


def match_records(environment, key_id, pem):
    """Every Match record, page by page."""
    query = {"query": {"recordType": "Match"}, "resultsLimit": PAGE}
    while True:
        page = request(environment, "records/query", query, key_id, pem)
        yield from page.get("records", [])
        marker = page.get("continuationMarker")
        if not marker:
            return
        query["continuationMarker"] = marker


def asset_url(record: dict) -> str:
    """The payload asset's download URL, with CloudKit's `${f}` filename slot filled."""
    return record["fields"]["payload"]["value"]["downloadURL"].replace("${f}", "payload.json")


def owner(record: dict) -> str:
    return record.get("created", {}).get("userRecordName", "")


def names(user_ids, environment, key_id, pem) -> dict:
    """Each uploader's ladder name, from their `account-<id>` Player record."""
    if not user_ids:
        return {}
    lookup = {"records": [{"recordName": f"account-{user}"} for user in sorted(user_ids)]}
    found = request(environment, "records/lookup", lookup, key_id, pem).get("records", [])
    result = {}
    for record in found:
        name = record.get("fields", {}).get("name", {}).get("value")
        user = record.get("recordName", "").removeprefix("account-")
        # Only the account itself can name it (LiveSync's rule).
        if name and owner(record) == user:
            result[user] = name
    return result


def kept(record: dict, payload: dict, owner_names: dict) -> dict:
    user = owner(record)
    return {"owner": user, "ownerName": owner_names.get(user), "modified": record.get("modified", {}).get("timestamp"),
            "game": payload}


def fetch(args):
    key_id, pem = key_paths()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    records = list(match_records(args.environment, key_id, pem))
    owner_names = names({owner(r) for r in records}, args.environment, key_id, pem)
    new = 0
    for record in records:
        file = out / f"{record['recordName']}.json"
        if file.exists():
            continue
        with urllib.request.urlopen(asset_url(record), timeout=60) as response:
            payload = json.load(response)
        file.write_text(json.dumps(kept(record, payload, owner_names)))
        new += 1
    print(f"{len(records)} ranked games and restarts on CloudKit, {new} new -> {out}")
    players(args)


def players(args):
    """Finished games and restarts per player. A restart is a rated game left
    unfinished for a new one (`SharedMatch.abandoned`); Elo rates it as a loss."""
    finished, restarts = Counter(), Counter()
    for file in Path(args.out).glob("*.json"):
        game = json.loads(file.read_text())
        who = (game.get("ownerName") or "?", game["owner"])
        (restarts if game["game"].get("abandoned") else finished)[who] += 1
    for who in sorted(set(finished) | set(restarts), key=lambda w: (-finished[w], w)):
        print(f"{finished[who]:4d} games {restarts[who]:4d} restarts  {who[0]:16s} {who[1]}")


def restarts(args):
    """Each restart: when, by whom, and how far the game had gone."""
    rows = []
    for file in Path(args.out).glob("*.json"):
        game = json.loads(file.read_text())
        if not game["game"].get("abandoned"):
            continue
        moves = game["game"].get("moves", [])
        rolls = sum(1 for m in moves if "rollDice" in m["move"])
        when = datetime.datetime(2001, 1, 1) + datetime.timedelta(seconds=game["game"]["date"])
        rows.append((when, game.get("ownerName") or "?", len(moves), rolls, file.stem))
    for when, name, moves, rolls, match in sorted(rows):
        print(f"{when:%Y-%m-%d %H:%M}  {name:16s} {moves:4d} moves {rolls:3d} rolls  {match}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", choices=["fetch", "players", "restarts"])
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--environment", default="production", choices=["production", "development"])
    args = parser.parse_args(argv)
    {"fetch": fetch, "players": players, "restarts": restarts}[args.command](args)


if __name__ == "__main__":
    main()
