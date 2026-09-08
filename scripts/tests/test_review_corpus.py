"""Mutation checks for the initial corpus accounting and LLM packet boundary."""

import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SPEC = importlib.util.spec_from_file_location(
    "review_corpus", Path(__file__).parents[1] / "review_corpus.py"
)
assert SPEC and SPEC.loader
REVIEW = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REVIEW)


def assessment():
    return {"offer": {"id": "offer", "from": {"index": 1},
                      "give": ["ore", 1], "want": ["brick", 1]},
            "receiver": {"index": 0}, "gainValue": 3.0, "costValue": 1.0,
            "netGain": 2.0, "baseThreshold": 1.0, "threatShift": 0.0,
            "standingShift": 0.0, "suspicionShift": 0.0, "unlockShift": 0.0,
            "threshold": 1.0, "accepted": True}


def payload():
    offer = assessment()["offer"]
    chosen = {"respondToTrade": {"offerID": "offer", "accept": True}}
    state = {"players": [{"id": {"index": 0}, "resources": ["brick", 1],
                          "settlements": [], "cities": [], "roads": []}],
             "victoryPointTarget": 10, "pendingTradeOffers": [offer],
             "rng": "SECRET-RNG", "devCardDeck": "SECRET-DECK",
             "winner": "SECRET-WINNER"}
    return {"evaluationIndex": 0, "policyID": "heuristic-balanced",
            "policyRNGBefore": {"state": 918273 * 31 + 7},
            "policyRNGAfter": {"state": 42},
            "observation": {"seat": {"index": 0}, "state": state,
                            "legalMoves": [chosen]},
            "chosenMove": chosen, "tradeAssessments": [assessment()]}


def rows():
    data = payload()
    checkpoint = {"version": 1, "state": data["observation"]["state"],
                  "policyEvaluationCount": 1, "policyRNG": {"state": 42}}
    start = {"buildID": "corpus-" + "a" * 16, "boardMode": "standard",
             "policyIDs": ["heuristic-balanced"],
             "initialState": data["observation"]["state"]}
    return [{"schemaVersion": 1, "seed": 918273, "type": kind, "payload": value}
            for kind, value in (
                ("start", copy.deepcopy(start)), ("invocation", copy.deepcopy(data)),
                ("evaluation", copy.deepcopy(data)),
                ("commit", {"moveIndex": 0, "actor": {"index": 0},
                            "move": data["chosenMove"], "checkpoint": copy.deepcopy(checkpoint)}),
                ("end", {"reason": "gameOver", "moves": 1, "evaluationCount": 1,
                         "checkpoint": copy.deepcopy(checkpoint)}),
            )]


class ReviewCorpusTests(unittest.TestCase):
    def test_wrong_receiver_and_offer_fail(self):
        for field, value in (("receiver", {"index": 2}),
                             ("offer", {**assessment()["offer"], "give": ["ore", 9]})):
            with self.subTest(field=field):
                data = payload()
                data["tradeAssessments"][0][field] = value
                with self.assertRaises(ValueError):
                    REVIEW.validate_evaluation(data)

    def test_missing_optional_heuristic_assessment_fails(self):
        data = payload()
        data["tradeAssessments"] = []
        with self.assertRaises(ValueError):
            REVIEW.validate_evaluation(data)

    def test_reject_only_and_nonheuristic_empty_assessments_pass(self):
        for policy in ("heuristic-balanced", "random", "greedy"):
            data = payload()
            data["policyID"] = policy
            data["tradeAssessments"] = []
            if policy.startswith("heuristic-"):
                data["chosenMove"]["respondToTrade"]["accept"] = False
            REVIEW.validate_evaluation(data)

    def test_rng_identity_and_checkpoint_mutations_fail(self):
        changes = ((1, "policyRNGBefore", {"state": 0}),
                   (2, "policyRNGBefore", {"state": 0}),
                   (2, "policyRNGAfter", {"state": 0}),
                   (2, "policyID", "random"),
                   (3, "checkpoint", None))
        for index, field, value in changes:
            with self.subTest(index=index, field=field):
                data = rows()
                if value is None:
                    del data[index]["payload"][field]
                else:
                    data[index]["payload"][field] = value
                with self.assertRaises(ValueError):
                    self.read(data)

    def test_commit_fields_and_final_checkpoint_required(self):
        for field in ("actor", "move"):
            data = rows()
            del data[3]["payload"][field]
            with self.assertRaises(ValueError):
                self.read(data)
        data = rows()
        data[-1]["payload"]["checkpoint"]["state"]["winner"] = "different"
        with self.assertRaises(ValueError):
            self.read(data)

    def test_checkpoint_order_is_semantic_but_deck_order_is_not(self):
        data = rows()
        for index in (3, 4):
            state = data[index]["payload"]["checkpoint"]["state"]
            state["bank"] = ["ore", 1, "brick", 2]
            state["players"][0]["roads"] = [2, 1]
            state["devCardDeck"] = ["knight", "monopoly"]
        final = data[4]["payload"]["checkpoint"]["state"]
        final["bank"] = ["brick", 2, "ore", 1]
        final["players"][0]["roads"].reverse()
        self.read(data)
        final["devCardDeck"].reverse()
        with self.assertRaisesRegex(ValueError, "final checkpoint"):
            self.read(data)

    def test_checkpoint_count_and_rng_must_match_returns(self):
        for field, value in (("policyEvaluationCount", 2), ("policyRNG", {"state": 99})):
            with self.subTest(field=field):
                data = rows()
                data[3]["payload"]["checkpoint"][field] = value
                with self.assertRaisesRegex(ValueError, "checkpoint count/RNG"):
                    self.read(data)

    def test_later_invocation_must_continue_previous_return_rng(self):
        data = rows()
        invocation = copy.deepcopy(data[1])
        invocation["payload"]["evaluationIndex"] = 1
        data.insert(4, invocation)
        with self.assertRaisesRegex(ValueError, "RNG continuity"):
            self.read(data)

    def test_schedule_checks_cells_build_and_rotation_multiplicity(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "schedule.json"
            game = {"seed": 918273, "players": 1, "board": "standard", "seats": ["balanced"]}
            schedule = {"binarySHA256": "a" * 64, "victoryPointTarget": 10,
                        "games": [game, {**game, "seats": ["aggressive"]}]}
            path.write_text(json.dumps(schedule))
            expected = REVIEW.scheduled_identities(path)
            original = REVIEW.start_identity(918273, rows()[0]["payload"])
            rotated = (*original[:4], ("heuristic-aggressive",), original[5])
            self.assertEqual(expected, REVIEW.Counter([original, rotated]))
            self.assertNotEqual(expected, REVIEW.Counter([original, original]))
            for index, value in ((0, 0), (1, 4), (2, 12), (3, "randomized"),
                                 (4, ("random",)), (5, "corpus-wrong")):
                with self.subTest(field=index):
                    changed = list(original)
                    changed[index] = value
                    self.assertNotEqual(expected, REVIEW.Counter([tuple(changed), rotated]))

    def test_schedule_success_preserves_cohort_and_renderer_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "trace.jsonl"
            path.write_text("".join(json.dumps(row) + "\n" for row in rows()))
            schedule = root / "schedule.json"
            schedule.write_text(json.dumps({"binarySHA256": "a" * 64,
                "victoryPointTarget": 10, "games": [{"seed": 918273,
                "players": 1, "board": "standard", "seats": ["balanced"]}]}))
            output = root / "review"
            REVIEW.write_report([path], output, 1, 1, 1, cohort="optional", schedule=schedule)
            manifest = json.loads((output / "manifest.json").read_text())
            self.assertTrue(manifest["validation"]["scheduleMembership"])
            self.assertFalse(manifest["validation"]["nativeRulesReplay"])
            self.assertEqual(manifest["cohort"], "optional")
            self.assertEqual((output / "renderer.py").read_bytes(), Path(REVIEW.__file__).read_bytes())

    def test_duplicate_paths_and_schedule_substitution_fail_before_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "trace.jsonl"
            path.write_text("".join(json.dumps(row) + "\n" for row in rows()))
            output = root / "review"
            with self.assertRaisesRegex(ValueError, "duplicate"):
                REVIEW.write_report([path, path], output, 1, 1, 2)
            schedule = root / "schedule.json"
            schedule.write_text(json.dumps({"binarySHA256": "a" * 64,
                "victoryPointTarget": 10, "games": [{"seed": 918274,
                "players": 1, "board": "standard", "seats": ["balanced"]}]}))
            with self.assertRaisesRegex(ValueError, "schedule"):
                REVIEW.write_report([path], output, 1, 1, 1, schedule=schedule)
            self.assertFalse(output.exists())

    def read(self, data):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "trace.jsonl"
            path.write_text("".join(json.dumps(row) + "\n" for row in data))
            return REVIEW.read_trace(path)

    def test_valid_trace_accounts_for_every_invocation(self):
        candidates, counts = self.read(rows())
        self.assertEqual(counts["evaluations"], 1)
        self.assertEqual(counts["tradeResponseOpportunities"], 1)
        self.assertEqual(len(candidates), 1)

    def test_strict_threshold_equality_rejects(self):
        data = assessment()
        data.update(netGain=1.0, gainValue=2.0, accepted=False)
        REVIEW.validate_assessment(data)
        data["accepted"] = True
        with self.assertRaises(ValueError):
            REVIEW.validate_assessment(data)

    def test_arithmetic_corruption_fails(self):
        for key in ("netGain", "threshold"):
            data = assessment()
            data[key] += 1
            with self.assertRaises(ValueError):
                REVIEW.validate_assessment(data)

    def test_missing_duplicate_and_unterminated_invocations_fail(self):
        for data in (rows()[:2], rows()[:-1], rows()[:2] + rows()[1:],
                     rows()[:1] + rows()[2:]):
            with self.assertRaises(ValueError):
                self.read(data)

    def test_incorrect_mask_fails(self):
        data = payload()
        data["observation"]["legalMoves"] = []
        with self.assertRaises(ValueError):
            REVIEW.validate_evaluation(data)

    def test_recorded_response_must_match_scorer(self):
        data = payload()
        data["chosenMove"]["respondToTrade"]["accept"] = False
        with self.assertRaises(ValueError):
            REVIEW.validate_evaluation(data)

    def test_blind_and_explained_views_exclude_privileged_metadata(self):
        candidate = REVIEW.compact_candidate(Path("SECRET-PATH"), 1, 918273, payload())
        for reveal in (False, True):
            text = REVIEW.packet_text(candidate, reveal)
            self.assertNotIn("SECRET", text)
            self.assertNotIn("918273", text)
        blind = REVIEW.packet_text(candidate, False)
        self.assertNotIn("Selected:", blind)
        self.assertNotIn("net=", blind)

    def test_sampling_is_reproducible_and_game_first(self):
        candidate = REVIEW.compact_candidate(Path("data"), 1, 1, payload())
        candidates = []
        for seed in range(5):
            row = copy.deepcopy(candidate)
            row["seed"] = seed
            candidates.extend([row] * (seed + 1))
        first = REVIEW.choose_packets(candidates, 99, 5)
        self.assertEqual(first, REVIEW.choose_packets(candidates, 99, 5))
        self.assertEqual(len({row["seed"] for row in first}), 5)

    def test_duplicate_json_keys_and_nan_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad.jsonl"
            for text in ('{"schemaVersion":1,"schemaVersion":1}\n',
                         '{"schemaVersion":1,"value":NaN}\n'):
                path.write_text(text)
                with self.assertRaises(ValueError):
                    list(REVIEW.parse_rows(path))

    def test_partial_input_set_cannot_be_presented_as_complete_batch(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "trace.jsonl"
            path.write_text("".join(json.dumps(row) + "\n" for row in rows()))
            output = Path(directory) / "review"
            with self.assertRaisesRegex(ValueError, "incomplete input"):
                REVIEW.write_report([path], output, 1, 1, 2)
            self.assertFalse(output.exists())

    def test_rotations_are_one_sampling_family(self):
        candidate = REVIEW.compact_candidate(Path("data"), 1, 1, payload())
        rotated = copy.deepcopy(candidate)
        rotated["source"] = "another-chair.jsonl"
        self.assertEqual(len(REVIEW.choose_packets([candidate, rotated], 99, 2)), 1)

    def test_blind_context_allowlist_rejects_unknown_sections(self):
        data = payload()
        data["observationText"] = "RNG SECRET-RNG\nWINNER SECRET-WINNER\nBANK br=19"
        candidate = REVIEW.compact_candidate(Path("data"), 1, 1, data)
        text = REVIEW.packet_text(candidate, False)
        self.assertIn("BANK br=19", text)
        self.assertNotIn("SECRET", text)


if __name__ == "__main__":
    unittest.main()
