#!/usr/bin/env python3

import base64
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).parents[1] / "cloudkit-games.py"
SPEC = importlib.util.spec_from_file_location("cloudkit_games", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def match_record(name="M1", user="_kyle", url="https://cvws.icloud-content.com/x/${f}"):
    return {"recordName": name, "created": {"userRecordName": user}, "modified": {"timestamp": 1},
            "fields": {"payload": {"value": {"downloadURL": url}}}}


class SigningTests(unittest.TestCase):
    def test_the_signed_message_is_date_body_hash_and_path(self):
        body = b'{"query":{}}'
        message = MODULE.signed_message("2026-10-24T20:00:00Z", body, "/database/1/c/production/public/records/query")
        digest = base64.b64encode(hashlib.sha256(body).digest()).decode()
        self.assertEqual(message.decode(), f"2026-10-24T20:00:00Z:{digest}:/database/1/c/production/public/records/query")

    def test_a_signature_verifies_against_the_public_key(self):
        with tempfile.TemporaryDirectory() as directory:
            pem, public = Path(directory) / "key.pem", Path(directory) / "public.pem"
            subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(pem)], check=True)
            subprocess.run(["openssl", "ec", "-in", str(pem), "-pubout", "-out", str(public)], check=True,
                           capture_output=True)
            message = b"date:hash:/path"
            signature = Path(directory) / "signature.der"
            signature.write_bytes(base64.b64decode(MODULE.sign(message, pem)))
            verified = subprocess.run(["openssl", "dgst", "-sha256", "-verify", str(public), "-signature", str(signature)],
                                      input=message, capture_output=True)
            self.assertEqual(verified.returncode, 0, verified.stdout + verified.stderr)

    def test_the_path_names_the_ladder_container(self):
        self.assertEqual(MODULE.subpath("production", "records/query"),
                         "/database/1/iCloud.com.alexchandler.empires/production/public/records/query")


class RecordTests(unittest.TestCase):
    def test_the_asset_filename_slot_is_filled(self):
        self.assertEqual(MODULE.asset_url(match_record()), "https://cvws.icloud-content.com/x/payload.json")

    def test_pages_follow_the_continuation_marker(self):
        pages = [{"records": [match_record("A")], "continuationMarker": "next"}, {"records": [match_record("B")]}]
        sent = []
        def fake(environment, operation, payload, key_id, pem):
            sent.append(dict(payload))
            return pages[len(sent) - 1]
        with mock.patch.object(MODULE, "request", fake):
            names = [r["recordName"] for r in MODULE.match_records("production", "id", Path("k"))]
        self.assertEqual(names, ["A", "B"])
        self.assertEqual(sent[1]["continuationMarker"], "next")

    def test_a_name_counts_only_when_its_own_account_set_it(self):
        found = {"records": [
            {"recordName": "account-_kyle", "created": {"userRecordName": "_kyle"}, "fields": {"name": {"value": "Kbeast"}}},
            {"recordName": "account-_jake", "created": {"userRecordName": "_mallory"}, "fields": {"name": {"value": "Fake"}}},
        ]}
        with mock.patch.object(MODULE, "request", lambda *args: found):
            self.assertEqual(MODULE.names({"_kyle", "_jake"}, "production", "id", Path("k")), {"_kyle": "Kbeast"})

    def test_a_kept_game_carries_its_uploader(self):
        kept = MODULE.kept(match_record(), {"version": 1}, {"_kyle": "Kbeast"})
        self.assertEqual((kept["owner"], kept["ownerName"], kept["game"]), ("_kyle", "Kbeast", {"version": 1}))


class CommandTests(unittest.TestCase):
    def test_players_counts_games_per_uploader(self):
        with tempfile.TemporaryDirectory() as directory:
            for index, (user, name) in enumerate([("_kyle", "Kbeast"), ("_kyle", "Kbeast"), ("_jake", "Bein")]):
                (Path(directory) / f"{index}.json").write_text(json.dumps({"owner": user, "ownerName": name, "game": {}}))
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                MODULE.main(["players", "--out", directory])
        lines = output.getvalue().splitlines()
        self.assertTrue(lines[0].split()[:2] == ["2", "Kbeast"], lines)

    def test_no_key_says_where_it_comes_from(self):
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(MODULE, "CONFIG", Path(directory)), \
                mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(SystemExit) as exit:
                MODULE.key_paths()
        self.assertIn("docs/cloudkit-server-key.md", str(exit.exception))


if __name__ == "__main__":
    unittest.main()
