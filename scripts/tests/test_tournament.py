"""Tests for scripts/tournament/tournament.py: the schedule, the dedupe, the ratings.

These are the parts whose mistakes would not crash - a skipped chair, two
different bots merged as one, a rating that favours whoever played most - and
would instead produce a confident wrong answer to Jake's question.
"""

import importlib.util
import json
import random
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tournament" / "tournament.py"
spec = importlib.util.spec_from_file_location("tournament", SCRIPT)
tournament = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tournament)


def game(seats, winner, match="x", seed=1):
    results = [{"seat": s, "vp": 10 if i == winner else 5, "turnsEnded": 10, "turnsEndedOverSeven": 0,
                "turnsEndedOverFifteen": 0, "handAtEndTurnTotal": 50, "maxHand": 9, "cardsDiscarded": 0,
                "decisions": 100, "fallbacks": 0, "decodeErrors": 0, "tradesBlocked": 0}
               for i, s in enumerate(seats)]
    return {"match": match, "seed": seed, "seats": seats, "winner": winner, "moves": 400,
            "fingerprint": "f", "results": results}


class ScheduleTests(unittest.TestCase):
    def test_every_pair_both_directions_every_chair(self):
        with tempfile.TemporaryDirectory() as tmp:
            roster = Path(tmp) / "roster.json"
            roster.write_text(json.dumps([{"seat": s} for s in ("a:x", "b:x", "c:x")]))
            out = Path(tmp) / "schedule.jsonl"
            tournament.cmd_schedule(Namespace(roster=roster, seeds=5, first_seed=100, out=out, pairs="all"))
            games = tournament.read_jsonl(out)
        # 3 pairs x 2 directions x 4 chairs x 5 seeds
        self.assertEqual(len(games), 3 * 2 * 4 * 5)
        for hero, field in (("a:x", "b:x"), ("b:x", "a:x")):
            cell = [g for g in games if g["match"] == f"{hero} vs {field}"]
            chairs = sorted(g["seats"].index(hero) for g in cell)
            self.assertEqual(chairs, sorted(list(range(4)) * 5))
            self.assertTrue(all(g["seats"].count(field) == 3 for g in cell))

    def test_excluded_variants_are_not_scheduled(self):
        with tempfile.TemporaryDirectory() as tmp:
            roster = Path(tmp) / "roster.json"
            roster.write_text(json.dumps([{"seat": "a:x"}, {"seat": "b:x"}, {"seat": "c:x", "excluded": True}]))
            out = Path(tmp) / "schedule.jsonl"
            tournament.cmd_schedule(Namespace(roster=roster, seeds=1, first_seed=1, out=out, pairs="all"))
            self.assertFalse(any("c:x" in g["seats"] for g in tournament.read_jsonl(out)))


class RosterTests(unittest.TestCase):
    def setUp(self):
        self.real_git = tournament.git
        tournament.git = lambda *args: "a\nb\nc" if args[0] == "log" and "--first-parent" in args else "09-14"

    def tearDown(self):
        tournament.git = self.real_git

    def roster(self, prints_by_seat):
        with tempfile.TemporaryDirectory() as tmp:
            results = Path(tmp) / "probe.jsonl"
            rows = []
            for seat, prints in prints_by_seat.items():
                for seed, printed in zip(tournament.PROBE_SEEDS, prints):
                    row = game([seat] * 4, 0, match=f"probe {seat}", seed=seed)
                    row["fingerprint"] = printed
                    rows.append(row)
            tournament.write_jsonl(results, rows)
            out = Path(tmp) / "roster.json"
            tournament.cmd_roster(Namespace(results=results, out=out, max_fallback=0.005))
            return json.loads(out.read_text())

    def test_identical_play_collapses_and_prefers_the_in_process_copy(self):
        same = ["p"] * len(tournament.PROBE_SEEDS)
        roster = self.roster({"a:expert": same, "local:expert": same,
                              "b:expert": ["q"] * len(tournament.PROBE_SEEDS)})
        seats = sorted(row["seat"] for row in roster)
        self.assertEqual(seats, ["b:expert", "local:expert"])
        merged = next(row for row in roster if row["seat"] == "local:expert")
        self.assertEqual(merged["sameAs"], ["a:expert"])

    def test_one_differing_seed_keeps_two_variants(self):
        base = ["p"] * len(tournament.PROBE_SEEDS)
        changed = base[:-1] + ["z"]
        self.assertEqual(len(self.roster({"a:classic": base, "b:classic": changed})), 2)

    def test_expert_and_classic_never_merge(self):
        same = ["p"] * len(tournament.PROBE_SEEDS)
        self.assertEqual(len(self.roster({"a:expert": same, "a:classic": same})), 2)


class RatingTests(unittest.TestCase):
    def test_recovers_the_order_of_known_strengths(self):
        rng = random.Random(7)
        truth = {"weak": 0.5, "mid": 1.0, "strong": 2.0}
        names = list(truth)
        games = []
        for _ in range(3000):
            seats = [rng.choice(names) for _ in range(4)]
            if len(set(seats)) == 1:
                continue
            weights = [truth[s] for s in seats]
            games.append(game(seats, rng.choices(range(4), weights)[0]))
        ratings = tournament.fit_ratings(games)
        self.assertLess(ratings["weak"], ratings["mid"])
        self.assertLess(ratings["mid"], ratings["strong"])
        # log(2) apart in strength is ~120 Elo-scale points
        self.assertAlmostEqual(ratings["strong"] - ratings["mid"], 120, delta=40)

    def test_equal_players_rate_equal(self):
        rng = random.Random(3)
        games = [game(["a", "b", "b", "b"], rng.randrange(4)) for _ in range(4000)]
        ratings = tournament.fit_ratings(games)
        self.assertAlmostEqual(ratings["a"], ratings["b"], delta=25)

    def test_wilson_interval_contains_the_rate(self):
        low, high = tournament.wilson(250, 1000)
        self.assertLess(low, 0.25)
        self.assertGreater(high, 0.25)
        self.assertAlmostEqual(high - low, 0.054, delta=0.004)


if __name__ == "__main__":
    unittest.main()
