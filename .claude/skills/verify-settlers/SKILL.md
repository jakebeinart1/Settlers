---
name: verify-settlers
description: The dev-loop verification ladder for the Settlers ("Empires") iOS app - regenerate the project, run scripts/gate.sh, install FRESH on the simulator, launch, prove the process survived, and hand over a screenshot. Use before saying a change works, before opening a PR to Jake, and whenever the report is "it builds", "tests pass, ship it", "is this ready?", or the complaint is "my change didn't do anything", "it compiled but the screen is wrong", "it worked yesterday", or "did you actually check?". `scripts/gate.sh` compiles the app in RELEASE and its Debug build is opt-in (`--debug-app`), while every `-qa*` launch flag is wrapped in `#if DEBUG` - so a green gate has never once built the binary you are about to screenshot. Never pipe `xcodebuild` through `tail`, `head` or `grep`: a shell pipeline returns the LAST command's exit status, so a failed build reads as success.
---

# Verify Settlers

**"It builds" is a compile claim. "It works" is a runtime claim, and no compiler
emits one.** This repo has no UI test - `xcodebuild test -scheme Settlers` was
literally empty until this week - so above the two SPM packages nothing executes
a line of the app until a person launches it. An app that compiles, lints,
passes 178 tests and clears both coverage floors can still fail to install,
crash inside `GameViewModel.init()`, or paint a blank screen, and every gate in
`scripts/gate.sh` stays green while it does.

**The last rung is deliberately not automated.** Rungs 1-5 can all be green on a
white screen: the bundle installed, the process is alive, no crash report
landed. That is the exact failure this ladder cannot see, which is why it ends
by printing `READ <path>` and stopping instead of exiting green with a verdict
it has no right to give.

## What has actually run

| Path | Status |
|---|---|
| **`scripts/verify.sh` full, all six rungs** | **RUN AND PROVEN 2026-08-29, exit 0**, on `iPhone 17 Pro` (`175016BD-5123-479A-AC91-4E852DF2FE06`), against `4b99aff`. Gate green in 130s (`swiftlint --strict` 0s, packages W=E 10s, CatanEngine tests 11s, CatanAI tests 86s, coverage CatanEngine **95.50%** / CatanAI **91.52%**, gitleaks 1s, app build Release 21s); then Debug built, uninstalled, installed, launched as pid 11383, alive after 6s, no crash report, screenshot taken **and read** - the Empires main menu with "Randomized Board" / "Randomize Seat" and "New Game". |
| **`scripts/verify.sh --skip-gate`** | **RUN AND PROVEN 2026-08-29, exit 0.** Same ladder minus rung 2, ~90s instead of ~4min. The summary line reads `SKIP`, loudly. |
| **The crash-report diff (rung 5) firing on a real crash** | **NEVER SEEN RED.** The `Settlers[-.]` filter and the `comm -13` diff are correct by construction and were exercised on a clean run, but no crash has been produced to prove they catch one. Treat a green rung 5 as "nothing appeared", not as "a crash would have been caught". |
| **`kill -0 $PID` (rung 5)** | **RUN AND PROVEN 2026-08-29.** Simulator processes are ordinary host processes owned by this user, so the signal-0 liveness test is valid from the host shell. pid 84107 answered. |
| **Release configuration** | **BUILT BY THE GATE ON EVERY RUN** since `gate.sh` made it mandatory. It is the one thing the ladder does NOT rebuild - rung 3 is Debug on purpose (see rung 3's note). |
| **Any interaction at all** | **NEVER RUN, AND CANNOT BE.** `simctl` has no touch injection. A dead button, an untappable tile, a drag that does nothing - all six rungs pass. |

## Hard preconditions: if one is missing, STOP and say which

- **`xcodegen` on PATH** (2.46.0 here). The `.xcodeproj` is a build artifact
  generated from `project.yml`; hand edits to `project.pbxproj` are discarded.
- **A bootable iPhone simulator.** Discovered, never hardcoded - UDIDs differ
  per machine and change when Xcode installs a runtime.
- **A tree that is yours.** `gate.sh` lints and tests the WHOLE repo. If another
  agent or another branch has an in-progress file in it, rung 2 fails on their
  work and tells you nothing about yours. Check `git status` first.

## The ladder

`scripts/verify.sh` implements rungs 1-5 and stops at 6. Run that rather than
retyping this; the block below is here so the WHY is readable without opening
the script, and so the pieces can be run by hand when you are changing them.

```bash
set -euo pipefail   # -e, so a rung that fails stops the ladder rather than
                    # letting the next one report on a stale artifact

# 1) REGENERATE THE PROJECT. `project.yml` globs `sources: [Settlers]`, but the
#    .xcodeproj holds a FROZEN file list, so a new .swift file on disk is
#    invisible to the compiler until this runs. The error it produces names the
#    SYMBOL and never the file - "cannot find 'X' in scope" while X is plainly
#    on disk with correct imports - which sends people hunting an import bug
#    that does not exist. It is idempotent, so do not try to detect whether the
#    file list moved: just always run it.
#    NOTE this regenerates IN PLACE, unlike gate.sh's drift gate, which
#    snapshots and restores because a read-only check has to actually be
#    read-only. Here we need a correct project handed to the compiler, so if
#    the pbxproj changes, that is a file you now have to commit.
REPO="$(git rev-parse --show-toplevel)"
xcodegen generate --quiet

# 2) THE COMPILE/LINT/TEST GATE. Eight gates, ~94s warm: xcodegen drift,
#    swiftlint --strict, both packages with -warnings-as-errors, both suites,
#    both coverage floors, gitleaks, and the app in RELEASE. Run it BEFORE the
#    simulator work, not after: it is the cheap half of the ladder and the
#    common failure, and there is no point installing an app whose package
#    tests are red.
"$REPO/scripts/gate.sh"

# 3) BUILD DEBUG, OUTSIDE THE TREE, AND ASSERT THE EXIT CODE.
#    Debug and not Release, for two reasons that are easy to get backwards:
#    gate.sh already compiled Release in step 2 so a second one proves nothing
#    new, and every `-qa*` launch flag is wrapped in `#if DEBUG` and is inert
#    in a Release binary. Debug and Release are different programs the moment a
#    `#if` enters the codebase - that is not a slogan here, it is how the app
#    stopped compiling for release for a whole afternoon while every gate
#    stayed green.
#    DerivedData must live OUTSIDE the working tree: SwiftLint walks the
#    filesystem rather than git, so an in-repo DerivedData/ gets linted and
#    fails --strict on Xcode's own generated sources.
#    Log to a FILE. Never `xcodebuild | tail` - see the trap below.
DD="${TMPDIR:-/tmp}/settlers-verify-derived"; mkdir -p "$DD"
SIM="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = [d for runtime in json.load(sys.stdin)["devices"].values()
             for d in runtime if "iPhone" in d["name"]]
booted = [d for d in devices if d["state"] == "Booted"]
print((booted or devices)[0]["udid"])')"
xcrun simctl boot "$SIM" 2>/dev/null || true   # already-booted exits non-zero
open -a Simulator                              # so there is a window to photograph
xcodebuild -project "$REPO/Settlers.xcodeproj" -scheme Settlers \
  -destination "platform=iOS Simulator,id=$SIM" \
  -configuration Debug -derivedDataPath "$DD" build > "$DD/xcodebuild.log" 2>&1
# $? is xcodebuild's own, because nothing was piped.

# 4) UNINSTALL FIRST, THEN INSTALL. The order is the whole point. A stale
#    install masks exactly the two failures this ladder exists for: a changed
#    bundle id installs ALONGSIDE the old app, so you launch and photograph
#    yesterday's binary and conclude your change did nothing; and a renamed or
#    deleted asset keeps resolving out of the previous container, so a broken
#    asset reference looks fine until a clean device gets it.
#    Wiping the container also removes the persisted save that
#    `GameViewModel.init()` restores, so the launch below starts from a known
#    state rather than whatever game this simulator was last left in.
#    Read the identity back out of the ARTIFACT - never assume the bundle id -
#    so both stay right if project.yml is ever retargeted.
APP="$DD/Build/Products/Debug-iphonesimulator/Settlers.app"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")"
xcrun simctl uninstall "$SIM" "$BUNDLE_ID" 2>/dev/null || true   # nothing to remove is fine
xcrun simctl install "$SIM" "$APP"

# 5) LAUNCH AND CAPTURE THE PID. The pid is what makes the next rung mean
#    anything: without it, "no crash report appeared" is also true of an app
#    that never started. Terminate first - launching an already-running app
#    returns its EXISTING pid and re-runs none of the flag handling, so you
#    photograph the previous state.
CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"
BEFORE="$(ls -1 "$CRASH_DIR" | sort)"
xcrun simctl terminate "$SIM" "$BUNDLE_ID" 2>/dev/null || true
PID="$(xcrun simctl launch "$SIM" "$BUNDLE_ID")"; PID="${PID##*: }"

# 6) SETTLE, THEN PROVE IT SURVIVED, TWO INDEPENDENT WAYS. Either alone is
#    weak: a new crash report names the failure but can lag behind the process
#    dying, while `kill -0` is instant and says nothing about why. macOS writes
#    SIMULATOR crash reports to the HOST's report directory, so the diff is
#    taken there - and it must be filtered to this executable, because that
#    directory is shared with every other process on the machine and unrelated
#    reports landing mid-run would turn the rung into noise nobody reads.
#    6s is deliberate slack; a cold launch reaches the menu in about 1s. Use
#    12s if you pass -qaFastForwardToRollDice, which plays real bot turns and
#    sleeps 600ms each.
sleep 6
kill -0 "$PID"
CRASHED="$(comm -13 <(printf '%s\n' "$BEFORE") <(ls -1 "$CRASH_DIR" | sort) \
           | grep -E '^Settlers[-.]' || true)"   # `|| true`: no match is the GOOD case
[[ -z "$CRASHED" ]]

# 7) SCREENSHOT, AND HAND IT OVER. This rung has no assertion in it, on
#    purpose. Everything above is green on a blank white screen.
xcrun simctl io "$SIM" screenshot "$DD/verify.png"
echo "READ $DD/verify.png"
```

## Trap: the pipeline that reports a failed build as a success

**Measured in this repo.** A failing `xcodebuild test -scheme Settlers` piped
into `tail -25` reported `EXIT=0`. The mechanism is not subtle and applies to
every runner, not just xcodebuild: a shell pipeline's exit status is the exit
status of the **last** command in it, and `tail` succeeded at tailing. So

```bash
xcodebuild ... | tail -25          # exit status of tail. Always 0.
xcodebuild ... | grep -E "error:"  # exit status of grep. 1 when the build was CLEAN.
```

Two correct shapes, both in use here:

- **Redirect to a file and read `$?`** - `scripts/verify.sh` rung 3.
- **Pipe, then read `${PIPESTATUS[0]}`** - `scripts/gate.sh:169` filters
  xcodebuild's output for readability and still returns xcodebuild's own
  status. Copy that line if you need to filter.

`grep` is the nastier of the two, because it inverts: a perfectly clean build
produces no `error:` lines, grep matches nothing, and the gate goes red on a
green build. People then "fix" it by loosening the pattern until it matches
something, at which point the gate cannot go red at all.

## Trap: running this while someone else is editing the tree

**Measured 2026-08-29.** A full `scripts/verify.sh` failed at rung 2 with

```
SettlersTests/PersistenceTests.swift:85:74: error: Force Cast Violation (force_cast)
```

on a file this session had not touched, written by a concurrent agent minutes
earlier. `gate.sh` is a whole-repo check by design - that is what makes it a
merge gate - so it does not care whose work is in the tree. Two consequences:

- **Read `git status` before believing rung 2's verdict.** A red gate over
  somebody else's untracked file is not a statement about your change.
- **`--skip-gate` exists for exactly this**, and it records `SKIP`, never
  silence, in the ladder summary. "I did not check" and "I checked and it was
  fine" have to look different or the script is back to lying. Never report a
  `--skip-gate` run as a verified change.

(The same run also blocked on `Another instance of SwiftPM is already running
using .../CatanAI/.build` while the other agent held the lock. That is SwiftPM
waiting correctly, not a hang - it resolves on its own.)

## Trap: Release-only breakage, and why rung 2 now catches it

The app once stopped compiling for `-configuration Release` entirely while
every gate was green: `qaForceHumanWin()` and `qaSeedPendingTradeConfirmation()`
were moved behind `#if DEBUG` in `GameViewModel.swift`, but their call sites in
`ContentView.swift` and `GameView.swift` were guarded only by
`QALaunchFlag.<case>.isSet` - a **runtime** check. The compiler still has to
resolve the call, and in Release the methods do not exist.

It survived because the gate built Debug only. `gate.sh` now builds **Release
on every run** and Debug is the opt-in (`--debug-app`), which is the reverse of
what most people assume when they read the flag list. The lesson generalizes
past that one bug: **Debug and Release are different programs the moment a
`#if` enters the codebase**, so a screenshot from a Debug build says nothing
about the shippable one.

## Trap: derived data inside the repo turns the lint gate red

Building with `-derivedDataPath DerivedData` (inside the working tree) made
`swiftlint --strict` fail on a file nobody wrote:

```
DerivedData/Build/Intermediates.noindex/.../GeneratedAssetSymbols.swift:125:1:
  error: Trailing Newline Violation (trailing_newline)
```

SwiftLint walks the filesystem, not git, so `.gitignore` does not protect it.
`.swiftlint.yml` now carries a `DerivedData` exclusion, but the ladder still
builds into `$TMPDIR` and you should too - relying on an exclusion list to
protect you from your own build directory is one edit away from breaking.

## Honest limits (do not overpromise)

- **Rung 6 is not automated and must not be reported as passed.** The script
  prints `READ <path>`. If nobody opened that file, the change is unverified,
  and a summary that says "verified" is a false claim about work that was not
  done.
- **No interaction is tested, ever.** `simctl` has no touch injection, SwiftUI
  is one opaque canvas to the accessibility APIs, and synthetic clicks are
  banned here because they land on whatever Mac window is frontmost - including
  Alex's real applications. A dead button passes all six rungs.
- **The app-target test bundle is brand new and does not change this.** As of
  2026-08-29 `SettlersTests` is being added on this branch (`project.yml`
  gains `type: bundle.unit-test` and the scheme's `test: targets:` stops being
  empty). Those are unit tests over `GameViewModel` and the persistence stores.
  They are a real improvement and they still never render a pixel.
- **One screenshot, one screen.** The ladder photographs the launch screen.
  Everything reachable only by tapping is out of scope; use the `-qa*` flags
  and the **run-settlers** skill to seed a specific screen, and note that most
  of those flags seed state directly, so they prove a view LAYS OUT, never that
  the game logic which would normally produce that state works.
- **Simulator is not a device.** Nothing here says anything about touch
  latency, thermals, memory pressure, or safe-area behaviour on real hardware,
  and the device path has never produced an installed build on this machine
  (signing is to Jake's team - see **run-settlers**).
- **Rung 5 has never gone red.** It has been proven to pass on a healthy app,
  not proven to catch a sick one.

## Related

- **`.claude/skills/run-settlers/SKILL.md`** - the twelve `-qa*` launch flags,
  what each screen needs, and why the real-iPhone path is blocked. Use it when
  you need a SPECIFIC screen; use this skill when you need to know a change is
  safe to hand over.
- **`.claude/skills/sim-harness/SKILL.md`** - the headless equivalent for the
  bots. Thousands of games with no simulator, no UI and no screenshot.
- **`scripts/gate.sh`** - rung 2. Its header is the rationale for every gate
  and for the three properties any change to it must preserve.
- **`scripts/verify.sh`** - this ladder, rungs 1-5, ending in `READ <path>`.
- **`CLAUDE.md`** - "Anti-false-green", the list of green signals this repo has
  already been burned by.
