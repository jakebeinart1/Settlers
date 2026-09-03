---
name: run-settlers
description: Build, install, launch and screenshot the Settlers ("Empires") iOS app on the simulator, and what blocks the real-iPhone path. Use whenever asked to run/rerun the app, "show me what it looks like", "screenshot the trade popup", "put it on my phone", "install it", or when the complaint is "my change didn't do anything", "it says it can't find that file", "the build works but the screen is wrong", or "why won't it install on my phone". The app is signed to JAKE's team (KDM65HE483) and Alex holds no identity for it, so the device path cannot sign today and the simulator is the only route that reaches a screen. Never claim a change works from a green build alone — take the screenshot and read it.
---

# Run Settlers (Empires)

**A green `xcodebuild` is a compile claim. "The change works" is a runtime claim.** Native
XCUITests exercise setup, settings, placement, and cold resume; an inspected screenshot
remains the evidence for visual layout. Neither substitutes for the other.

**Every path in this file is derived, not typed.** The previous version of this skill
hardcoded `/Users/jakeb/Documents/Catan Game` and a `DerivedData/Settlers-*` glob under
Jake's home. None of it ran on Alex's machine. Nothing below names a home directory: the
repo comes from `git rev-parse --show-toplevel`, the simulator is discovered, the `.app` is
read back out of `xcodebuild`, and the bundle id is read out of the built `Info.plist`.

## What has actually run

| Path | Status |
|---|---|
| **Simulator: build → install → launch → screenshot** | **RUN AND PROVEN 2026-08-29** on `iPhone 17 Pro` (`175016BD-5123-479A-AC91-4E852DF2FE06`, iOS 26.5), Debug. `BUILD SUCCEEDED`, installed, launched, four screenshots taken and read. The ladder below is that exact run. |
| **`xcodegen generate` after a new file** | **MEASURED 2026-08-29, both directions.** With an untracked `Settlers/QALaunchFlag.swift` on disk the build failed `error: cannot find 'QALaunchFlag' in scope` ×6 (exit 65); after `xcodegen generate`, exit 0, same source. |
| **QA launch arguments** | **RUN AND PROVEN 2026-08-29.** `-qaAutoStart -qaShowBuildPopup` and `-qaAutoStart -qaShowPauseMenu` both rendered their popup. `-qaShowEndGame` measured in both combinations (see the table). |
| **Native UI tests** | **RUN AND PROVEN 2026-09-02.** All five setup, settings, placement, and cold-resume flows passed from isolated state. The first clean run exposed and removed a hidden dependency on a previously saved player name. |
| **Real iPhone: build** | **NEVER SUCCEEDED.** Two separate blockers, both live as of 2026-08-29. See "The device path is blocked" below. |
| **Real iPhone: install / launch** | **NEVER RUN** on this machine — the build has never produced a signed `.app` to install. The `devicectl` retry advice below is **inherited from Jake's sessions and has not been reproduced by Alex.** |
| **Release configuration** | **RUN AND PROVEN.** Was red on `e95d1e5` (`#if DEBUG` methods called from unguarded sites) while every gate stayed green, because the gate built Debug only. Both are fixed: the call sites are guarded and `scripts/gate.sh` compiles Release on every run. |

## Hard preconditions: if one is missing, STOP and say which. Do not improvise.

- **`xcodegen` on PATH** (`/opt/homebrew/bin/xcodegen`, 2.46.0 here). The `.xcodeproj` is a
  build artifact. Editing `project.pbxproj` by hand is discarded on the next generate;
  version keys and build settings belong in `project.yml`.
- **A bootable iPhone simulator.** Discovered, never hardcoded — step 2 below.
- **For the device path only:** an unlocked, trusted iPhone reporting `available (paired)`
  from `devicectl`, *and* a codesigning identity for whichever team `project.yml` names.
  Neither holds today.

## The ladder

Run it top to bottom. Every step asserts its own exit code; nothing here parses output to
decide whether it passed.

```bash
set -euo pipefail

# 1) ANCHOR EVERY PATH TO THE REPO, not to a home directory. This is the whole
#    reason the previous version of this skill was dead on arrival: it hardcoded
#    another developer's checkout. `--show-toplevel` works from any subdirectory
#    and is correct on any machine that has cloned this repo.
REPO="$(git rev-parse --show-toplevel)"

# 2) DISCOVER A SIMULATOR. Prefer one that is already Booted (booting costs ~15s
#    and a warm simulator is also less likely to wedge), else take the first
#    available iPhone. Never paste a UDID into a script: they differ per machine
#    and change when Xcode installs a new runtime.
SIM="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = [d for runtime in json.load(sys.stdin)["devices"].values()
             for d in runtime if "iPhone" in d["name"]]
booted = [d for d in devices if d["state"] == "Booted"]
print((booted or devices)[0]["udid"])')"
xcrun simctl boot "$SIM" 2>/dev/null || true   # already-booted is not an error
open -a Simulator                              # so the screenshot has something to photograph

# 3) REGENERATE THE PROJECT IF THE FILE LIST CHANGED. `project.yml` globs
#    `sources: [Settlers]`, but the .xcodeproj holds a frozen file list, so a new
#    .swift file on disk is invisible to the compiler until this runs. The error
#    it produces names the SYMBOL, not the file - "cannot find 'X' in scope" while
#    X is plainly on disk with correct imports - which sends people hunting an
#    import bug that does not exist. Cheap and idempotent: just always run it.
xcodegen generate --spec "$REPO/project.yml" --project "$REPO"

# 4) BUILD, WITH DERIVED DATA OUTSIDE THE REPO. The path is explicit so step 5
#    can find the .app without globbing a hash under ~/Library. It must live
#    OUTSIDE the working tree: SwiftLint walks the filesystem rather than git, so
#    a DerivedData/ inside the repo makes `scripts/gate.sh` fail on Xcode's own
#    generated sources (measured - see the trap below).
#    Log to a FILE and assert the exit code. Never `xcodebuild | grep`: a pipeline
#    returns the LAST command's status, so a failed build reads as whatever grep
#    thought. (gate.sh does this correctly with PIPESTATUS; match it.)
DD="${TMPDIR:-/tmp}/settlers-derived"
xcodebuild -project "$REPO/Settlers.xcodeproj" -scheme Settlers \
  -destination "platform=iOS Simulator,id=$SIM" \
  -configuration Debug -derivedDataPath "$DD" build > "$DD.log" 2>&1
grep -q "BUILD SUCCEEDED" "$DD.log"   # belt and braces; `set -e` already caught exit != 0

# 5) READ THE ARTIFACT'S OWN IDENTITY BACK. Do not assume either value. The
#    product path comes from xcodebuild's own settings and the bundle id from the
#    built Info.plist, so both stay right if project.yml is ever retargeted.
#    (Today: com.jakebeinart.settlers, display name "Empires".)
APP="$DD/Build/Products/Debug-iphonesimulator/Settlers.app"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")"

# 6) UNINSTALL BEFORE INSTALLING, when you want a REPRODUCIBLE screen. The app
#    resumes a persisted save - `GameViewModel.init()` calls `GameStore.shared.load()`
#    - so `-qaAutoStart` lands on whatever game that simulator was last left in.
#    Measured: three launches with identical flags gave three different boards
#    (different civilizations, different dice, one mid-robber-move). Uninstalling
#    wipes the container, so the next launch is a fresh setup-phase board every
#    time. Skip this step only when you deliberately want the existing save.
xcrun simctl uninstall "$SIM" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"

# 7) LAUNCH STRAIGHT INTO THE SCREEN YOU WANT, using the -qa flags (table below).
#    Terminate first: launching an already-running app returns its existing PID
#    and re-runs NONE of the flag handling, so you screenshot the previous state
#    and conclude your change did nothing.
xcrun simctl terminate "$SIM" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$SIM" "$BUNDLE_ID" -qaAutoStart -qaShowBuildPopup

# 8) SCREENSHOT, THEN READ IT WITH THE Read TOOL. This is the only gate that
#    proves anything visual. ~3-4s is enough for a normal launch; allow 10-12s
#    when -qaFastForwardToRollDice is in the flags (it plays real bot turns and
#    they sleep 600ms each - GameViewModel.swift:495).
sleep 4
xcrun simctl io "$SIM" screenshot "$DD/verify.png"
echo "now READ $DD/verify.png"
```

## The `-qa*` launch arguments — all nineteen

Jake's version of this skill said there were three. There are nineteen. Each is a plain
`ProcessInfo` argument check that is never set in normal use, so none can affect a real
player. Find them all with:

```bash
grep -rnoE '"\-qa[A-Za-z]+"' --include="*.swift" "$REPO/Settlers" | sort -u
```

| Flag | Consumed in | Screen it reaches |
|---|---|---|
| `-qaAutoStart` | `ContentView.swift` | Skips `MainMenuView`, lands on the board. **Prerequisite for every GameView flag below.** |
| `-qaShowEndGame` | `ContentView.swift` | `EndGameView` ("YOU WIN!") via a forced human win. |
| `-qaShowSettings` | `MainMenuView.swift` | `SettingsView` over the main menu. **The one flag that must NOT be combined with `-qaAutoStart`.** |
| `-qaShowPauseMenu` | `GameView.swift` | The "Game Menu" pause sheet. |
| `-qaShowTradePopup` | `GameView.swift` | `TradePopupView`. |
| `-qaShowBuildPopup` | `GameView.swift` | The "Build" popup (Road / Settlement / City / Dev Card). |
| `-qaShowMonopolyPopup` | `GameView.swift` | The Monopoly resource picker in `DevCardPopupView` (Year of Plenty shares the layout). |
| `-qaShowPendingTradeConfirmation` | `GameView.swift` | The trade popup's "a bot will accept" banner, seeded directly. |
| `-qaShowRobberTargeting` | `GameView.swift` | The "tap a tile" robber targeting panel. |
| `-qaShowRobberVictimPicker` | `GameView.swift` | One step further: the "Steal from:" victim picker. |
| `-qaShowIncomingOffer` | `GameView.swift` | `IncomingTradeCardView`, seeded with a fake always-fulfillable offer. |
| `-qaFastForwardToRollDice` | `GameView.swift` | Plays the human's own setup placements, then rolls, so the `.rollDice` action row is reachable. **Applies real moves** (writes the save and the game log) and **needs 10-12s**, not 4. |
| `-qaShowNewGame` | `MainMenuView.swift` / `NewGameSetupView.swift` | `NewGameSetupView` over the main menu, on a startable two-human/two-AI fixture (green ready plaque, Start enabled). **Must NOT be combined with `-qaAutoStart`.** |
| `-qaShowNewGameInvalid` | `NewGameSetupView.swift` | Same screen, seat 2's name whitespace-only — the amber problem plaque and a disabled Start. |
| `-qaShowNewGameOverwrite` | `NewGameSetupView.swift` | Same screen with the "Replace your saved game?" confirmation already raised. Pair with a real save (run `-qaAutoStart -qaFastForwardToRollDice` first) to also get the amber saved-game plaque behind it. |
| `-qaShowNewGameCivilizationPicker` | `NewGameSetupView.swift` | Same screen with seat 2's civilization grid open — the only way to see a taken civilization greyed out. |
| `-qaNewGameThreeSeats` | `NewGameSetupView.swift` | **Modifier**, combines with any of the four above: shrinks the fixture to a three-player table. |
| `-qaTwoHumans` | `ContentView.swift` | Turns the loaded game into a two-human hot-seat game (seats 0 and 1, nobody at the device) so `HandoffCoverView` is photographable. **Needs `-qaAutoStart`.** |
| `-qaScrollNewGameToBottom` | `NewGameSetupView.swift` | **Legacy modifier** retained for fixture compatibility. The compact screen now fits without requiring this scroll position. |

**`-qaAutoStart` is load-bearing for ten of these.** `GameView` only renders once
`hasStartedThisSession` is true, so every flag read inside `GameView.swift` is inert on its
own — and so is `-qaTwoHumans`, which `ContentView` reads in the same branch. Measured on 2026-08-29: `-qaShowEndGame` alone left the app sitting on the main menu;
`-qaAutoStart -qaShowEndGame` rendered the win screen. If a flag "does nothing", check this
before suspecting the flag.

**Debug only, as of 2026-08-29.** All nineteen reads are consolidated into
`Settlers/QALaunchFlag.swift`, whose `isSet` is wrapped in `#if DEBUG` — so in a Release
build the flags are inert whatever you pass. If that file exists, do not try to screenshot a
Release build with them.

## Trap: a new .swift file without `xcodegen generate` (measured 2026-08-29)

The symptom is `error: cannot find 'QALaunchFlag' in scope`, six times, while the file is
right there on disk with correct imports. Nothing in the message mentions the project file.
`xcodegen generate` fixed it with zero source changes — same tree, exit 65 before, exit 0
after. Editing an existing file's contents does not need this; adding, renaming or deleting
one always does.

## Trap: derived data inside the repo turns the lint gate red (measured 2026-08-29)

Building with `-derivedDataPath DerivedData` (inside the working tree) made
`scripts/gate.sh` fail its SwiftLint gate on a file nobody wrote:

```
DerivedData/Build/Intermediates.noindex/.../GeneratedAssetSymbols.swift:125:1:
  error: Trailing Newline Violation (trailing_newline)
```

SwiftLint walks the filesystem, not git, so `.gitignore` does not protect it. Deleting the
directory made `swiftlint --strict` clean again immediately. **Build outside the tree**
(the ladder uses `$TMPDIR`).

Worth knowing if you ever do want an in-repo build directory: the two ignore lists do not
line up. `.gitignore` ignores `DerivedData/` but `.swiftlint.yml` does not exclude it;
`.swiftlint.yml` excludes `.ci-derived` but `.gitignore` does not ignore it. Neither name is
safe on both counts without editing one of the two files.

## Trap: Release does not compile, and no gate in this repo can see it

Measured on 2026-08-29 against commit `e95d1e5`, with `scripts/gate.sh` otherwise green:

```
ContentView.swift:87:27: error: value of type 'GameViewModel' has no dynamic member 'qaForceHumanWin'
GameView.swift:353:27:   error: value of type 'GameViewModel' has no member 'qaSeedPendingTradeConfirmation'
```

The cause is a guard mismatch, and it is worth understanding rather than pattern-matching:
`GameViewModel.swift:313` wraps `qaForceHumanWin()` and `qaSeedPendingTradeConfirmation()` in
`#if DEBUG`, but the two call sites are guarded only by `QALaunchFlag.<case>.isSet`. That is a
**runtime** check, not a compile-time one — the compiler still has to resolve the call, and in
Release the methods do not exist. The call sites need `#if DEBUG` too.

This is exactly the failure class the Debug-only gate cannot catch, which is why it is
recorded here and not left to be rediscovered. Build Release explicitly before believing
anything about a shippable binary.

## The device path is blocked, by two independent things

Discover the phone — do not trust `xctrace list devices`, which reports a different state
than the tool that actually installs:

```bash
xcrun devicectl list devices
```

On 2026-08-29 that printed Alex's iPhone (`7EC639FF-685F-53D0-A11E-42473B94A724`,
iPhone 17 Pro Max) as **`connected (no DDI)`** — not `available (paired)`. "No DDI" is the
developer disk image not being mounted, and it is what surfaces later as **"The developer
disk image could not be mounted on this device."** The fix is physical and is Alex's to do,
not something to work around: **unlock the phone and tap Trust**, then re-run the list and
confirm it says `available (paired)` before building.

**Signing fails regardless, and it fails first.** Building for that device today:

```
error: No profiles for 'com.jakebeinart.settlers' were found: Xcode couldn't find any
iOS App Development provisioning profiles matching 'com.jakebeinart.settlers'.
```

`project.yml` sets `DEVELOPMENT_TEAM: KDM65HE483` — **Jake's** team. Alex's is
`HXB9F28LHR`, and he holds no identity for Jake's:

```bash
security find-identity -v -p codesigning
# 2026-08-29: one "Apple Development: Created via API (R7AQ2QHN3X)", OU = HXB9F28LHR,
# plus two iPhone Distribution certs, also HXB9F28LHR. Nothing for KDM65HE483.
```

So the device path needs `DEVELOPMENT_TEAM` changed to `HXB9F28LHR` **in `project.yml`**
(never in the pbxproj — it is regenerated) plus `-allowProvisioningUpdates` to mint a
profile and register the phone. That is a real change to a file that goes back to Jake in a
PR, so **ask before making it**; do not quietly retarget the team to get a build through.

**Inherited from Jake, not reproduced here:** `xcrun devicectl device install app` fails
intermittently on the *first* attempt with `CoreDeviceError 4000` ("The device disconnected
immediately after connecting") or `CoreDeviceError 3002` ("Could not get service
com.apple.remote.installcoordination_proxy"), on a genuinely available device. A plain retry
~5s later has always worked. Retry once before treating it as a connectivity problem.

## Never drive the simulator with desktop-coordinate clicks

No `osascript ... click at {x, y}`, no `cliclick`. Three reasons, and the third is the one
that matters:

1. The Simulator window's screen coordinates do not map cleanly onto the device's logical
   points, so the tap lands somewhere you did not aim.
2. SwiftUI renders as one opaque canvas to the accessibility APIs — there is no element tree
   to click into by name, so there is nothing to target reliably.
3. A click can land on **whatever Mac window happens to be frontmost**, which means it can
   interact with Alex's real desktop applications.

`simctl` has no touch injection. Use native XCUITest for repeatable interaction and the
`-qa*` flags for deterministic visual fixtures.

## UI-test launch isolation

The UI-test target uses two Debug-only process arguments with deliberately different
semantics:

- `-ui-testing-reset` clears preferences, the active save, civilization assignment, stats,
  and game logs before `ContentView` is created. Every independent UI test starts with it.
- `-ui-testing` marks a UI-test launch without clearing anything. The cold-resume test uses
  it on its second process launch so the save from the first launch remains present.

Never put reset behavior behind `-ui-testing` itself: doing so makes a true cold-resume test
impossible. Reset support is compiled out of Release builds.

## Before saying a change works

```bash
"$REPO/scripts/gate.sh"              # 10 gates, including app and native UI tests
"$REPO/scripts/gate.sh --debug-app"  # Release included; also compile the screenshot binary
```

The gate is the merge gate here, because branch protection is unavailable on this repository
(403, "Upgrade to GitHub Pro or make this repository public") and CI therefore cannot block
anything — `scripts/install-hooks.sh` installs the pre-push hook that can. A screenshot
proving the pixels and a green gate proving the rules are two different claims; a visual
change needs both.

## Honest limits (do not overpromise)

- **The launch ladder photographs one screen.** Native XCUITests separately exercise a
  focused set of interactions; untested gameplay still requires play-settlers or a person.
- **`xcodebuild test -scheme Settlers` runs app and UI targets.** Read the Swift Testing and
  XCTest summaries; do not mistake one runner's zero line for an empty full suite.
- **This ladder builds Debug** (the `-qa*` flags are `#if DEBUG`), so a Release-only
  break was invisible to every gate in this repo until Release compilation became mandatory in `scripts/gate.sh`
  (see the trap above). A green gate is not evidence the app compiles for release.
- **Simulator ≠ device.** Nothing here says anything about touch latency, thermals, memory
  pressure, or safe-area behaviour on real hardware.
- **The device path has never produced an installed build on this machine.** Do not say "it's
  on your phone" from anything in this file.
- **A screenshot proves what was on screen, not that the state was reached legitimately.**
  Most `-qa*` flags seed state directly (a forced win, a fake trade offer, a bogus
  confirmation banner). They prove the view *lays out*, never that the game logic that would
  normally produce that state works. That belongs to the engine tests.

## Related

- **`scripts/gate.sh`** — the 10-gate merge gate (xcodegen drift, SwiftLint, packages with
  warnings-as-errors, both suites, coverage floors, gitleaks, app/UI tests, Release build,
  and optional Debug build). Each gate
  reports from its own exit code and a gate that cannot run reports SKIP, never silence.
- **`scripts/install-hooks.sh`** — installs the pre-push hook, the only thing in the setup
  that can actually refuse a push.
- **`project.yml`** — the source of truth for the target. Bundle id, team, warnings-as-errors,
  Info.plist keys. The `.xcodeproj` is generated from it.
- **`design-references/STATUS.md`** — the asset/UI conventions a screenshot should be judged
  against.
