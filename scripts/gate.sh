#!/usr/bin/env bash
#
# Run every gate and print ONE verdict per gate.
#
# WHY THIS IS THE GATE, and not GitHub Actions. Branch protection is out of
# reach on this repository twice over: `gh api
# repos/jakebeinart1/Settlers/branches/main/protection` answers 404 here
# because `permissions.admin` is false for this account, and on Alex's own
# private repos the same call answers 403 "Upgrade to GitHub Pro or make this
# repository public". So a CI check here can never *block* a merge -
# it is advisory by construction. A pre-push hook running this script is the
# only thing in the setup that can actually refuse. CI stays as a clean-room
# second opinion, which is a real but different job.
#
# THE RULES, inherited from BridgeRead's scripts/gate.sh, which earned each one:
#
#  1. Every gate reports PASS/FAIL from its own EXIT CODE. Nothing here parses a
#     tool's output to decide whether it passed. Reading `... | tail -3` from a
#     test runner is how a red suite gets reported green.
#  2. A gate that cannot run reports SKIP *in the summary*, never nothing.
#     "I did not check" and "I checked and it was fine" have to look different,
#     or the script is back to lying.
#  3. It does not stop at the first failure. Knowing three gates are red is
#     worth more than discovering them one push at a time.
#  4. Cheapest first, so the common failure is also the fastest.
#
# Usage:
#   scripts/gate.sh              # the full gate, ~70s warm
#   scripts/gate.sh --debug-app  # also compile the app in Debug
#   scripts/gate.sh --range A..B # scan only this commit range for secrets

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

WITH_DEBUG_APP=0
SECRET_RANGE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug-app) WITH_DEBUG_APP=1; shift ;;
    --range)    SECRET_RANGE="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

RESULTS=()
FAILED=0

# Runs one gate, records its verdict, and never aborts the script.
run_gate() {
  local name="$1"; shift
  local start; start=$SECONDS
  printf '\n\033[1m▸ %s\033[0m\n' "$name"
  if "$@"; then
    RESULTS+=("PASS  $name  ($((SECONDS - start))s)")
  else
    RESULTS+=("FAIL  $name  ($((SECONDS - start))s)")
    FAILED=1
  fi
}

# Records a gate that could not run. Deliberately distinct from PASS.
skip_gate() {
  RESULTS+=("SKIP  $1  -- $2")
}

# --- 1. Generated-project drift ------------------------------------------
# The .xcodeproj is generated from project.yml and both are committed. If they
# disagree, whoever builds next silently gets a different project than the one
# under review.
#
# The check RESTORES whatever it found, on every path. An earlier version
# regenerated in place, so a drifting tree was silently rewritten as a side
# effect of running the gate - the working tree would differ afterwards, and a
# `git checkout --` to undo the "fix" would take any legitimate edit to
# project.yml with it. A read-only check has to actually be read-only.
gate_xcodegen_drift() {
  if ! command -v xcodegen > /dev/null 2>&1; then return 200; fi

  local pbxproj="Settlers.xcodeproj/project.pbxproj"
  local snapshot; snapshot="$(mktemp)"
  cp "$pbxproj" "$snapshot"

  local before after status=0
  before="$(shasum -a 256 "$pbxproj" | cut -d' ' -f1)"
  if ! xcodegen generate --quiet > /dev/null 2>&1; then
    cp "$snapshot" "$pbxproj"; rm -f "$snapshot"
    echo "  xcodegen failed to generate from project.yml"
    return 1
  fi
  after="$(shasum -a 256 "$pbxproj" | cut -d' ' -f1)"

  if [[ "$before" != "$after" ]]; then
    echo "  project.pbxproj is stale relative to project.yml."
    echo "  Run 'xcodegen generate' and commit the result."
    status=1
  else
    echo "  project.pbxproj matches project.yml"
  fi

  cp "$snapshot" "$pbxproj"
  rm -f "$snapshot"
  return $status
}

# --- 2. Lint --------------------------------------------------------------
gate_swiftlint() {
  if ! command -v swiftlint > /dev/null 2>&1; then return 200; fi
  swiftlint lint --strict --quiet
}

# The bot evaluator is part of the evidence behind every future personality or
# strength claim. A malformed shard must fail loudly rather than producing a
# polished but invalid table.
gate_evaluation_tools() {
  python3 -m unittest discover -s scripts/tests -p 'test_*.py'
}

# --- 3. Compile the packages with warnings as errors ----------------------
gate_packages_build() {
  ( cd Packages/CatanEngine && swift build -Xswiftc -warnings-as-errors ) \
    && ( cd Packages/CatanAI && swift build -Xswiftc -warnings-as-errors )
}

# --- 4. The test suites ---------------------------------------------------
# Coverage is enabled here so the profile exists for the coverage gate below;
# collecting it during the run this gate already pays for is free, whereas
# re-running the suite to measure it doubled the slowest stage of the gate.
gate_engine_tests() { ( cd Packages/CatanEngine && swift test --enable-code-coverage ); }
gate_ai_tests()     { ( cd Packages/CatanAI && swift test --enable-code-coverage ); }

# A same-process determinism test is insufficient because Swift seeds hash
# iteration once per process. This executes the real exporter twice and checks
# the serialized artifact, including completeness validation.
gate_training_export() { ./scripts/verify-training-export.sh; }

# --- 5. Coverage floors ---------------------------------------------------
# Floors sit ~1 point under the measured figure. See scripts/coverage.sh for
# the ratchet policy: the floor never goes down without a commit message
# saying what was deleted and why, and rises when headroom exceeds 2 points.
# Measured 2026-08-31: engine 95.88%, AI 96.71%. The AI figure moved from a
# stated 92.04% not because coverage changed but because coverage.sh was
# measuring CatanAI over CatanEngine's sources as well; see that script.
#
# Both floors are always measured. They used to be chained with `&&`, so a
# failing engine floor meant the AI floor was never evaluated and nothing said
# so - the summary showed one failure where there might have been two, which is
# the "a check that could not run must not look like a check that passed" rule
# turned on the gate itself.
gate_coverage() {
  local status=0
  ./scripts/coverage.sh Packages/CatanEngine 95 --reuse || status=1
  ./scripts/coverage.sh Packages/CatanAI 95 --reuse || status=1
  return $status
}

# --- 6. Secrets -----------------------------------------------------------
gate_secrets() {
  if ! command -v gitleaks > /dev/null 2>&1; then return 200; fi
  if [[ -n "$SECRET_RANGE" ]]; then
    gitleaks detect --no-banner --redact --log-opts="$SECRET_RANGE"
  else
    gitleaks detect --no-banner --redact
  fi
}

# --- 7. The app target's own tests ----------------------------------------
# `xcodebuild test -scheme Settlers` used to answer "Scheme Settlers is not
# currently configured for the test action" - the scheme's test target list was
# literally empty, so 6,700 lines of app code had no tests and any gate built on
# that command would have been a false green. The scheme is wired now.
gate_app_tests() {
  local sim; sim="$(first_iphone_simulator)"
  if [[ -z "$sim" ]]; then return 200; fi
  xcodebuild test -project Settlers.xcodeproj -scheme Settlers \
    -destination "platform=iOS Simulator,id=$sim" 2>&1 \
    | grep -E "error:|✘|Test run with|TEST SUCCEEDED|TEST FAILED" | sort -u
  return "${PIPESTATUS[0]}"
}

# --- 8. The app target ----------------------------------------------------
first_iphone_simulator() {
  xcrun simctl list devices available -j 2>/dev/null \
    | python3 -c 'import json,sys
d=json.load(sys.stdin)["devices"]
for runtime, devices in d.items():
    for dev in devices:
        if "iPhone" in dev["name"]:
            print(dev["udid"]); raise SystemExit' 2>/dev/null
}

# Compiled in RELEASE, and not optional.
#
# This gate started out Debug-only and opt-in, and that combination let a real
# break through within hours: two `qa*` methods were put behind `#if DEBUG`
# while their call sites were not, so the app stopped compiling for release
# entirely - and every gate stayed green over it, because nothing here ever
# built the configuration that would ship. Debug and Release are different
# programs the moment a `#if` enters the codebase.
gate_app_build() {
  local sim; sim="$(first_iphone_simulator)"
  if [[ -z "$sim" ]]; then return 200; fi
  xcodebuild -project Settlers.xcodeproj -scheme Settlers \
    -destination "platform=iOS Simulator,id=$sim" \
    -configuration "${1:-Release}" build 2>&1 \
    | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | sort -u
  # Read xcodebuild's own status, not grep's - a pipeline returns the LAST
  # command's exit code, so `xcodebuild | grep` reports whether grep matched.
  return "${PIPESTATUS[0]}"
}

# --- run ------------------------------------------------------------------
maybe() {
  local name="$1"; shift
  local start=$SECONDS
  printf '\n\033[1m▸ %s\033[0m\n' "$name"
  "$@"
  local status=$?
  if [[ $status -eq 200 ]]; then
    RESULTS+=("SKIP  $name  -- required tool not installed")
  elif [[ $status -eq 0 ]]; then
    RESULTS+=("PASS  $name  ($((SECONDS - start))s)")
  else
    RESULTS+=("FAIL  $name  ($((SECONDS - start))s)")
    FAILED=1
  fi
}

maybe "xcodegen drift"          gate_xcodegen_drift
maybe "swiftlint --strict"      gate_swiftlint
maybe "evaluation tooling"     gate_evaluation_tools
maybe "packages build (W=E)"    gate_packages_build
maybe "CatanEngine tests"       gate_engine_tests
maybe "CatanAI tests"           gate_ai_tests
maybe "training export"         gate_training_export
maybe "coverage floors"         gate_coverage
maybe "gitleaks"                gate_secrets
maybe "app tests"               gate_app_tests
maybe "app build (Release)"     gate_app_build Release
if [[ $WITH_DEBUG_APP -eq 1 ]]; then
  maybe "app build (Debug)"     gate_app_build Debug
else
  skip_gate "app build (Debug)" "not requested; pass --debug-app"
fi

printf '\n\033[1m─── summary ───\033[0m\n'
for line in "${RESULTS[@]}"; do
  case "$line" in
    PASS*) printf '\033[32m%s\033[0m\n' "$line" ;;
    FAIL*) printf '\033[31m%s\033[0m\n' "$line" ;;
    *)     printf '\033[33m%s\033[0m\n' "$line" ;;
  esac
done

if [[ $FAILED -ne 0 ]]; then
  printf '\n\033[31mgate: FAILED\033[0m\n'
  exit 1
fi
printf '\n\033[32mgate: passed\033[0m\n'
