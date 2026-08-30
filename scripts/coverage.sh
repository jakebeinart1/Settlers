#!/usr/bin/env bash
#
# Measure line coverage for one SPM package and fail if it is below a floor.
#
# Usage: scripts/coverage.sh <package-dir> <floor-percent>
#   e.g. scripts/coverage.sh Packages/CatanEngine 96
#
# WHY A FLOOR AND NOT A TARGET. A coverage number nobody enforces only ever
# drifts down, one "I'll add the test later" at a time. The floor is set just
# under today's real number so it starts green, and the rule is that it never
# goes down: lowering it takes a commit whose message says what was deleted and
# why. The script prints the ACTUAL number every run so a climb is visible and
# the floor can be raised deliberately.
#
# WHY THE HEADROOM. These suites are not perfectly deterministic - the bots
# still tie-break with `SystemRandomNumberGenerator` when a caller does not pass
# a seed - so the measured figure wobbles by well under a tenth of a point run
# to run. A one-point gap is roughly ten times that wobble, which keeps the gate
# from flapping without making it a rubber stamp.
#
# WHAT IS MEASURED. Only the package's own `Sources/`. Two exclusions, for
# different reasons:
#   - Test files, because including them inflates the number (test code is by
#     definition fully executed) and would let coverage "improve" by writing
#     more tests that assert nothing.
#   - Dependencies. A test binary links them too, so CatanAI's figure was being
#     computed over CatanEngine's sources as well - and those read 0% here
#     because they are covered by the engine's own suite, in a different
#     binary. This header claimed "only the package's own Sources" long before
#     the code did it; adding two well-tested engine files moved the AI number
#     from 91% to 75% and looked exactly like a 16-point regression in code
#     that had actually gained coverage.

set -euo pipefail

PACKAGE_DIR="${1:?usage: coverage.sh <package-dir> <floor-percent> [--reuse]}"
FLOOR="${2:?usage: coverage.sh <package-dir> <floor-percent> [--reuse]}"
# `--reuse` reads the profile an earlier `swift test --enable-code-coverage`
# already produced instead of running the suite again. The gate runs its test
# stage with coverage enabled, so re-running here would double the slowest part
# of the whole gate for no new information.
REUSE="${3:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT/$PACKAGE_DIR"

if [[ "$REUSE" != "--reuse" ]]; then
  swift test --enable-code-coverage > /dev/null 2>&1
fi

BIN_PATH="$(swift build --show-bin-path)"
PROFDATA="$BIN_PATH/codecov/default.profdata"
XCTEST_BUNDLE="$(find "$BIN_PATH" -maxdepth 1 -name '*.xctest' | head -1)"

# A missing artifact means the run did not happen, which must not read as a
# pass. This is the difference between "I checked and it was fine" and "I did
# not check" - they have to look different or the gate is lying.
if [[ ! -f "$PROFDATA" || -z "$XCTEST_BUNDLE" ]]; then
  echo "coverage: FAILED to produce coverage data for $PACKAGE_DIR" >&2
  exit 1
fi

BINARY="$XCTEST_BUNDLE/Contents/MacOS/$(basename "$XCTEST_BUNDLE" .xctest)"

# Restricted to THIS package's own sources, passed as a positional source
# filter. A test binary links its dependencies too, so without this the figure
# for CatanAI is computed over CatanEngine's files as well - and those sit at
# 0% here because they are covered by the *engine's* suite, in a different
# binary. That contamination is not academic: adding two well-tested engine
# files (ActionSpace, StateEncoding) dropped this number from 91% to 75% and
# read as a 16-point regression in code that had in fact gained coverage.
# cwd is the package directory by this point.
OWN_SOURCES="$PWD/Sources"

ACTUAL="$(
  xcrun llvm-cov export \
    -summary-only \
    -instr-profile "$PROFDATA" \
    -ignore-filename-regex='(Tests/|\.build/)' \
    "$BINARY" \
    "$OWN_SOURCES" \
  | python3 -c 'import json,sys; t=json.load(sys.stdin)["data"][0]["totals"]; print("%.2f" % t["lines"]["percent"])'
)"

printf 'coverage %-28s %6s%%  (floor %s%%)\n' "$PACKAGE_DIR" "$ACTUAL" "$FLOOR"

python3 - "$ACTUAL" "$FLOOR" <<'PY'
import sys
actual, floor = float(sys.argv[1]), float(sys.argv[2])
if actual < floor:
    print(f"  BELOW FLOOR by {floor - actual:.2f} points", file=sys.stderr)
    sys.exit(1)
if actual >= floor + 2:
    print(f"  note: {actual - floor:.2f} points of headroom - consider raising the floor")
PY
