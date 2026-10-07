#!/usr/bin/env python3
"""Run the portable naval evaluator directly from a checkout."""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / "src"))

from naval_evaluation.evaluation import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main())
