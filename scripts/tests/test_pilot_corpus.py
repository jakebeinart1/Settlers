"""The small development schedule is a fixed contract, not a strength sample."""

import importlib.util
import unittest
from collections import Counter, defaultdict
from pathlib import Path


SPEC = importlib.util.spec_from_file_location("pilot_corpus", Path(__file__).parents[1] / "pilot_corpus.py")
assert SPEC and SPEC.loader
PILOT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PILOT)


class PilotCorpusTests(unittest.TestCase):
    def test_declared_size_cells_and_independent_families(self):
        games = PILOT.schedule()
        self.assertEqual(len(games), 24)
        self.assertEqual(len({game["family"] for game in games}), 14)
        counts = Counter(game["roster"] for game in games)
        self.assertEqual(counts, {"mixed": 14, "balanced": 10})
        cells = {(g["players"], g["board"], g["roster"]) for g in games}
        self.assertEqual(len(cells), 8)

    def test_mixed_families_rotate_every_chair_balanced_never_repeats(self):
        families = defaultdict(list)
        for game in PILOT.schedule():
            families[game["family"]].append(game)
        for games in families.values():
            first = games[0]
            if first["roster"] == "balanced":
                self.assertEqual(len(games), 1)
            else:
                self.assertEqual({g["rotation"] for g in games}, set(range(first["players"])))
                self.assertEqual(len({tuple(g["seats"]) for g in games}), first["players"])


if __name__ == "__main__":
    unittest.main()
