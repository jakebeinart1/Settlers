#!/usr/bin/env bash
#
# The dev-loop ladder: prove a change survives all the way to a running app.
#
# WHY THIS EXISTS ALONGSIDE gate.sh. `scripts/gate.sh` answers a COMPILE
# question - does everything build, lint, test and stay covered. It cannot
# answer the runtime one. This repo has `test: targets: []` in project.yml, so
# there is no UI test and nothing above the two SPM packages executes a single
# line of the app. An app that compiles can still fail to install, crash in
# `GameViewModel.init`, or paint a white screen, and every gate in gate.sh
# stays green while it does.
#
# THE LADDER, and the rule that each rung is only meaningful if the one below
# it passed - so this script stops at the first failure rather than collecting
# them the way gate.sh does:
#
#   1. project file regenerated  - a new .swift file is invisible until this runs
#   2. scripts/gate.sh           - the 9 compile/lint/test/coverage gates
#   3. build Debug + FRESH install - uninstall BEFORE install, always
#   4. launch, capture the PID
#   5. settle, diff the crash reports, `kill -0` the PID
#   6. screenshot  -- NOT AUTOMATED. A human or a model must read it.
#
# GATE 6 IS DELIBERATELY LEFT UNDONE. Everything above it can be green on a
# blank white screen: the process is alive, nothing crashed, the bundle
# installed. "It works" is a claim about pixels, and this script cannot make
# it. It prints `READ <path>` and stops.
#
# THE STANDING RULE ABOUT PIPES. Never `xcodebuild | tail`, `| head` or
# `| grep`: a shell pipeline returns the LAST command's exit status, so a
# failed build reads as whatever the filter thought. Measured in this repo - a
# failing `xcodebuild test` piped to `tail -25` reported EXIT=0. Below,
# xcodebuild writes to a log FILE and its own `$?` is the verdict. gate.sh does
# filter, and reads `${PIPESTATUS[0]}` to stay honest (gate.sh:169); if you add
# a pipe here, do the same.
#
# Usage:
#   scripts/verify.sh                          # the full ladder
#   scripts/verify.sh --skip-gate              # rungs 1, 3-6 only (records a SKIP)
#   scripts/verify.sh --launch-args "-qaAutoStart -qaShowBuildPopup"

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# How long the app is given to finish launching before it is judged. A cold
# launch here reaches the main menu in ~1s; 6s is deliberate slack so a slow
# first launch after an install is not misreported as a crash. Raise it to
# 12 if you pass -qaFastForwardToRollDice, which plays real bot turns and
# sleeps 600ms per turn (GameViewModel.swift).
SETTLE_SECONDS=6

# macOS writes simulator crash reports to the HOST's report directory, not
# into the simulator's container. Diffing it around the launch is the only
# automated evidence that the process did not die on its way to the screen.
CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"

# Derived data must live OUTSIDE the working tree. SwiftLint walks the
# filesystem rather than git, so a DerivedData/ inside the repo gets linted and
# fails `--strict` on Xcode's own generated sources - measured, and the reason
# .swiftlint.yml carries a DerivedData exclusion it should never have to use.
DERIVED="${TMPDIR:-/tmp}"
DERIVED="${DERIVED%/}/settlers-verify-derived"   # TMPDIR carries a trailing slash on macOS
BUILD_LOG="$DERIVED/xcodebuild.log"
SHOT="$DERIVED/verify.png"

SKIP_GATE=0
LAUNCH_ARGS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-gate)   SKIP_GATE=1; shift ;;
    --launch-args) LAUNCH_ARGS="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

RESULTS=()

# Prints a rung header. Kept separate from the verdict so a failure message
# from the tool itself sits directly under the name of the rung it broke.
announce() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

# Ends the run at the first broken rung. Everything above a failure is
# meaningless - there is no point screenshotting an app that did not install -
# so this exits rather than continuing with a recorded failure.
die() {
  RESULTS+=("FAIL  $1")
  printf '\n\033[1m─── ladder ───\033[0m\n'
  for line in "${RESULTS[@]}"; do printf '%s\n' "$line"; done
  printf '\n\033[31mverify: FAILED at %s\033[0m\n' "$1"
  exit 1
}

pass() { RESULTS+=("PASS  $1"); }
skip() { RESULTS+=("SKIP  $1  -- $2"); }

# --- 1. Regenerate the project -------------------------------------------
# project.yml globs `sources: [Settlers]`, but the .xcodeproj holds a FROZEN
# file list. A .swift file added on disk and not generated in fails with
# "cannot find 'X' in scope" - naming the symbol, never the file - which sends
# people hunting an import bug that does not exist. Idempotent, so it is run
# unconditionally rather than trying to detect whether the file list moved.
#
# This regenerates in place, unlike gate.sh's drift gate which snapshots and
# restores. That is intentional: gate.sh is a read-only check, this is the
# script that has to hand a correct project to the compiler.
announce "1. xcodegen generate"
command -v xcodegen > /dev/null 2>&1 || die "1. xcodegen generate (xcodegen not on PATH)"
BEFORE_PBX="$(shasum -a 256 Settlers.xcodeproj/project.pbxproj | cut -d' ' -f1)"
xcodegen generate --quiet || die "1. xcodegen generate"
AFTER_PBX="$(shasum -a 256 Settlers.xcodeproj/project.pbxproj | cut -d' ' -f1)"
if [[ "$BEFORE_PBX" != "$AFTER_PBX" ]]; then
  echo "  project.pbxproj was STALE and has been regenerated - commit it."
else
  echo "  project.pbxproj already matched project.yml"
fi
pass "1. xcodegen generate"

# --- 2. The compile/lint/test gate ---------------------------------------
if [[ $SKIP_GATE -eq 1 ]]; then
  announce "2. scripts/gate.sh"
  echo "  skipped by --skip-gate"
  skip "2. scripts/gate.sh" "--skip-gate was passed; NOTHING was linted or tested"
else
  announce "2. scripts/gate.sh"
  ./scripts/gate.sh || die "2. scripts/gate.sh"
  pass "2. scripts/gate.sh"
fi

# --- 3. Build Debug and install FRESH ------------------------------------
# Debug, not Release, for two reasons: the -qa* launch flags are wrapped in
# `#if DEBUG` and are inert in a Release build, and gate.sh already compiled
# Release above so a second Release build proves nothing new.
announce "3. build Debug + fresh install"
mkdir -p "$DERIVED"

# UI tests and this fresh-install ladder erase app data. Always use the named
# Empires QA simulator (created when absent), never a developer's play device.
SIM="$(python3 scripts/select-qa-simulator.py)"
[[ -n "$SIM" ]] || die "3. build Debug + fresh install (no iPhone simulator available)"
echo "  simulator $SIM"
xcrun simctl boot "$SIM" 2> /dev/null   # already-booted exits non-zero; not an error
open -a Simulator                       # so the screenshot photographs a real window

xcodebuild -project Settlers.xcodeproj -scheme Settlers \
  -destination "platform=iOS Simulator,id=$SIM" \
  -configuration Debug -derivedDataPath "$DERIVED" build > "$BUILD_LOG" 2>&1
BUILD_STATUS=$?
if [[ $BUILD_STATUS -ne 0 ]]; then
  grep -E "error:" "$BUILD_LOG" | sort -u | head -20
  echo "  full log: $BUILD_LOG"
  die "3. build Debug + fresh install (xcodebuild exit $BUILD_STATUS)"
fi

# Read the artifact's own identity back rather than assuming either value, so
# both stay correct if project.yml is ever retargeted.
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Settlers.app"
[[ -d "$APP" ]] || die "3. build Debug + fresh install (no .app at $APP)"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")" \
  || die "3. build Debug + fresh install (no CFBundleIdentifier in Info.plist)"
echo "  $BUNDLE_ID"

# UNINSTALL FIRST. A stale install masks exactly the failures this ladder is
# for: a changed bundle id installs alongside the old app and you launch and
# photograph the OLD one, and a renamed or deleted asset keeps resolving out of
# the previous container. Wiping the container also removes the persisted save
# that `GameViewModel.init()` restores, so the launch below starts from a known
# state instead of whatever game this simulator was last left in.
xcrun simctl uninstall "$SIM" "$BUNDLE_ID" 2> /dev/null
xcrun simctl install "$SIM" "$APP" || die "3. build Debug + fresh install (install failed)"
pass "3. build Debug + fresh install"

# --- 4. Launch and capture the PID ---------------------------------------
# The PID is the whole point of this rung. Without it, rung 5 can only say
# "no crash report appeared", which is also true of an app that never started.
announce "4. launch"
CRASH_BEFORE="$(ls -1 "$CRASH_DIR" 2> /dev/null | sort)"
xcrun simctl terminate "$SIM" "$BUNDLE_ID" 2> /dev/null   # a running app returns its OLD pid and re-reads no flags

# shellcheck disable=SC2086 -- LAUNCH_ARGS is a deliberate word-split list of -qa flags
LAUNCH_OUT="$(xcrun simctl launch "$SIM" "$BUNDLE_ID" $LAUNCH_ARGS 2>&1)" \
  || { echo "  $LAUNCH_OUT"; die "4. launch"; }
PID="${LAUNCH_OUT##*: }"
[[ "$PID" =~ ^[0-9]+$ ]] || die "4. launch (could not read a pid from '$LAUNCH_OUT')"
echo "  pid $PID${LAUNCH_ARGS:+  args:$LAUNCH_ARGS}"
pass "4. launch (pid $PID)"

# --- 5. Settle, then prove it is still alive -----------------------------
# Two independent checks, because either alone is weak. A new crash report
# names the failure but can lag; `kill -0` is instant but silent about why.
announce "5. survive ${SETTLE_SECONDS}s"
sleep "$SETTLE_SECONDS"

# Simulator processes are ordinary host processes owned by this user, so
# `kill -0` (signal nothing, just check deliverability) is a valid liveness
# test from here.
kill -0 "$PID" 2> /dev/null || die "5. survive ${SETTLE_SECONDS}s (pid $PID is gone)"

CRASH_AFTER="$(ls -1 "$CRASH_DIR" 2> /dev/null | sort)"
NEW_REPORTS="$(comm -13 <(printf '%s\n' "$CRASH_BEFORE") <(printf '%s\n' "$CRASH_AFTER"))"
# Only reports naming THIS executable are a verdict on this app; the directory
# is shared with every other process on the machine, and unrelated reports
# landing mid-run must not fail the ladder or it becomes noise nobody reads.
OUR_REPORTS="$(printf '%s\n' "$NEW_REPORTS" | grep -E '^Settlers[-.]' || true)"
if [[ -n "$OUR_REPORTS" ]]; then
  printf '%s\n' "$OUR_REPORTS" | sed "s|^|  $CRASH_DIR/|"
  die "5. survive ${SETTLE_SECONDS}s (new crash report)"
fi
if [[ -n "${NEW_REPORTS//[[:space:]]/}" ]]; then
  echo "  (unrelated new reports, not a verdict on this app:)"
  printf '%s\n' "$NEW_REPORTS" | sed 's|^|    |'
fi
echo "  pid $PID alive, no Settlers crash report"
pass "5. survive ${SETTLE_SECONDS}s"

# --- 6. The screenshot: handed over, not judged --------------------------
announce "6. screenshot (NOT automated)"
xcrun simctl io "$SIM" screenshot "$SHOT" > /dev/null 2>&1 || die "6. screenshot"
skip "6. read the screenshot" "no automated check exists; a human or model must open it"

printf '\n\033[1m─── ladder ───\033[0m\n'
for line in "${RESULTS[@]}"; do
  case "$line" in
    PASS*) printf '\033[32m%s\033[0m\n' "$line" ;;
    FAIL*) printf '\033[31m%s\033[0m\n' "$line" ;;
    *)     printf '\033[33m%s\033[0m\n' "$line" ;;
  esac
done

printf '\n\033[1mREAD %s\033[0m\n' "$SHOT"
printf 'Rungs 1-5 are green: it compiles, it installs, it launches, it is alive.\n'
printf 'None of that is evidence about what is on the screen. Open the file above.\n'
