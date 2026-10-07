---
name: run-settlers
description: Build, install, launch and screenshot Settlers ("Empires") on a simulator or Alex's paired iPhone. Use for run/rerun, visual checks, phone installs, stale-build complaints, and signing/device failures. Jake's committed signing defaults stay intact; Alex's device path uses the gitignored local override. A green build is not runtime evidence — inspect the screen or exercise the requested flow.
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
| **Real iPhone: build** | **RUN AND PROVEN 2026-09-05.** Debug Build 4 signed for Alex's team through `Signing.local.xcconfig` and built for his paired iPhone. |
| **Real iPhone: install / launch** | **RUN AND PROVEN 2026-09-05.** Build 4 installed in place, launched with `devicectl`, and read back as version 1.0 build 4. |
| **Release configuration** | **RUN AND PROVEN.** Was red on `e95d1e5` (`#if DEBUG` methods called from unguarded sites) while every gate stayed green, because the gate built Debug only. Both are fixed: the call sites are guarded and `scripts/gate.sh` compiles Release on every run. |

## Hard preconditions: if one is missing, STOP and say which. Do not improvise.

- **`xcodegen` on PATH** (`/opt/homebrew/bin/xcodegen`, 2.46.0 here). The `.xcodeproj` is a
  build artifact. Editing `project.pbxproj` by hand is discarded on the next generate;
  version keys and build settings belong in `project.yml`.
- **A bootable iPhone simulator.** Discovered, never hardcoded — step 2 below.
- **For the device path only:** an unlocked, trusted iPhone reporting `available (paired)`
  from `devicectl`, *and* a codesigning identity for whichever team `project.yml` names.
  Alex's gitignored signing override supplies his team without changing Jake's defaults.

## Simulator lifecycle

Before selecting, creating, booting, resetting, or testing on a simulator, read the
whole host inventory and disk use, including devices belonging to other projects:

```bash
xcrun simctl list devices -j
df -h "$HOME/Library/Developer/CoreSimulator"
du -sh "$HOME/Library/Developer/CoreSimulator/Devices"
```

Record the total and booted counts, relevant UDIDs, runtime, ownership evidence,
last known use, and current task/test/user review. A device name or installed app
alone does not prove exclusive ownership. Reuse an existing compatible, idle
task-owned device; keep its UDID across builds. Create only when none can serve
the task, and record the new device and its eventual cleanup in task evidence.

`select-qa-simulator.py` can create a device and its override validates the name
`Empires QA`, not task ownership. Duplicate names exist. Confirm an idle dedicated
QA device, export its exact `SETTLERS_QA_SIMULATOR_ID`, and keep it set for the
selector, gate, verification script, and push hook. Never substitute a user's
manual-play device for a reset or fresh install. Serialize native builds/tests
across agents and worktrees; use `-parallel-testing-enabled NO
-parallel-testing-worker-count 1` for direct tests and `GATE_TEST_WORKERS=1` for
the gate so repeated runs do not allocate parallel worker clones.

When finished, shut down idle devices this task booted unless ongoing work or
user review still needs them, and record/read back their state. Shutdown releases
memory; deleting a device releases storage and loses its data. Delete only a
known disposable task-owned device after archiving needed saves/recordings and
confirming no other task or user relies on it. If ownership or use is uncertain,
keep it. Never use `shutdown all`, `delete unavailable`, or blanket erase/delete;
never stop or delete another project's device. Recheck inventory and ownership
immediately before individual cleanup.

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

# 2) Use the dedicated QA simulator because this recipe uninstalls the app.
#    For a user's manual-play device, install in place and omit uninstall/reset
#    flags so their saved game survives. Never run this destructive recipe there.
: "${SETTLERS_QA_SIMULATOR_ID:?Inventory and pin a confirmed idle QA device first}"
SIM="$(python3 "$REPO/scripts/select-qa-simulator.py")"
# Boot only if the fresh inventory reports Shutdown; preserve real boot errors.
# An already Booted device needs no boot command.
xcrun simctl bootstatus "$SIM" -b
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

After reading the screenshot, apply [Simulator lifecycle](#simulator-lifecycle)
to devices this workflow used.

## The `-qa*` launch arguments

Each is a plain
`ProcessInfo` argument check that is never set in normal use, so none can affect a real
player. Find them all with:

```bash
grep -rnoE '"\-qa[A-Za-z]+"' --include="*.swift" "$REPO/Settlers" | sort -u
```

| Flag | Consumed in | Screen it reaches |
|---|---|---|
| `-qaAutoStart` | `ContentView.swift` | Skips `MainMenuView`, lands on the board. **Prerequisite for every GameView flag below.** |
| `-qaShowEndGame` | `ContentView.swift` | `EndGameView` ("YOU WIN!") via a forced human win. |
| `-qaPlayToEnd` | `ContentView.swift` | Plays every seat without presentation delays through the real app session, persistence, statistics, and game log until `EndGameView` renders. Needs `-qaAutoStart`. |
| `-qaShowPauseMenu` | `GameView.swift` | The "Game Menu" pause sheet. |
| `-qaShowTradePopup` | `GameView.swift` | `TradePopupView`. |
| `-qaBankTradePosition` | `GameView.swift` | Conserved seven-grain hand with a grain port; tap Trade → Bank to exercise six grain for three ore. |
| `-qaProductionPosition` | `GameView.swift` | Pre-roll city/settlement fixture. Tap Roll Dice to produce two ore and one grain through the real commit and receipt path. |
| `-qaLongestRoadPosition` | `GameView.swift` | Tied five-road paths with a rival holding the bonus. Tap Confirm on the human's staged sixth road to verify the Longest Road transfer and both signed VP changes. |
| `-qaShowBuildPopup` | `GameView.swift` | The "Build" popup (Road / Settlement / City / Dev Card). |
| `-qaPaidBuildPosition` | `GameView.swift` | Installs a real main-turn position where Road, Settlement, and City are all legal; use this to tap through the Build popup rather than seeding its result. |
| `-qaShowPaidRoadDecision` | `GameView.swift` | Starts a real paid-road proposal with no road or resources committed yet. |
| `-qaShowPaidSettlementDecision` | `GameView.swift` | Starts a real paid-settlement proposal with no settlement or resources committed yet. |
| `-qaShowPaidCityDecision` | `GameView.swift` | Starts a real paid-city proposal with no city or resources committed yet. |
| `-qaRecordingWarningAfterCity` | `GameView.swift` | Modifier for `-qaShowPaidCityDecision`: Confirm a legal city upgrade to raise the real recording-warning alert through the existing export-warning state. Only the warning is injected; the city, +1 VP notice, queue and timer use the production commit path. No archive write is forced to fail. |
| `-qaShowMonopolyPopup` | `GameView.swift` | The Monopoly resource picker in `DevCardPopupView` (Year of Plenty shares the layout). |
| `-qaShowDevCardHand` | `GameView.swift` | A mixed private hand containing every card type, including ready, new, and passive states. |
| `-qaDevCardPurchase` | `GameView.swift` | Backward-compatible shorthand for `-qaDevCardPurchase=monopoly`. |
| `-qaDevCardPurchase=<type>` | `GameView.swift` | A legal Build position with `knight`, `roadBuilding`, `yearOfPlenty`, `monopoly`, or `victoryPoint` on top. An older matching card makes active types playable after the tapped purchase, while the new copy remains visibly marked New. |
| `-qaShowDevCardReveal` | `GameView.swift` | A real committed Year of Plenty purchase waiting on its durable private acknowledgement. |
| `-qaShowWinningDevCardReveal` | `GameView.swift` | A real Victory Point purchase that wins the game; the private reveal must appear before standings. |
| `-qaShowPendingTradeConfirmation` | `GameView.swift` | The trade popup's "a bot will accept" banner, seeded directly. |
| `-qaShowRobberTargeting` | `GameView.swift` | Starts a real cancellable Knight proposal before a destination is selected. |
| `-qaShowRobberVictimPicker` | `GameView.swift` | Stages the mandatory robber fixture's three-victim destination; no victim is selected and nothing is committed. |
| `-qaShowRoadBuildingDecision` | `GameView.swift` | Starts a real Road Building proposal; both roads and the card remain uncommitted until Confirm. |
| `-qaShowMandatoryRobberDecision` | `GameView.swift` | Starts the mandatory rolled-seven robber proposal with three eligible victims for maximum-width layout QA. |
| `-qaShowDiscard` | `GameView.swift` | A real conserved eight-card hand in a mandatory four-card discard, for expanded/minimized inspection and submission. **Needs `-qaAutoStart`.** |
| `-qaShowIncomingOffer` | `GameView.swift` | `IncomingTradeCardView`, backed by a real pending engine offer and conserved deterministic hands. |
| `-qaQueuedBotOffers` | `GameViewModel+QATrade.swift` | Modifier for `-qaShowIncomingOffer`: two affordable offers during a bot turn, for receipt/timer hold and resume checks. |
| `-qaBotTradeAfterPause` | `GameViewModel+QATradeTapSafety.swift`, `GameView.swift` | Conserved bot main-turn baseline with no pending offer. The next deterministic QA policy choice proposes through the real session/history/checkpoint after production pacing. Pair with `-qaShowPauseMenu` to select Slow and the offer timer first; supports `-qaNavalMode`, `-qaThreePlayerTable` and `-qaBundleOffer`. Cold resume restores the production policy with its unchanged ID. |
| `-qaTradeCompetitionWinner=human` or `-qaTradeCompetitionWinner=rival` | `Testing/GameViewModel+QATradeTapSafety.swift` | Debug-only modifier for `-qaBotTradeAfterPause` (and its `-qaAutoStart` prerequisite). Bank-conserved hands fund a real four-Brick-for-one-Grain offer, the human and one actual seated Traditional/Expert rival. A bounded search of 64 starting policy seeds selects the requested recipient while the rival chooses acceptance through its real policy. Only the proposer's existing one-proposal QA selector is substituted; neither acceptance nor the exchange result is injected. The subsequent proposal/Accept use normal session/checkpoint/history paths. Omitting this modifier preserves the older Skip fixture. Invalid values, missing rival or an exhausted search fail explicitly. This selected starting cursor proves a requested outcome path, not ordinary recipient frequencies, match economics or AI strength; native verification remains separately required. |
| `-qaBundleOffer` | `GameViewModel+QATrade.swift` | **Modifier** for `-qaShowIncomingOffer`: widens it to the widest bundle the engine permits (four give types against one want type). The single-resource fixture cannot show what a composed Expert offer does to the card's fixed-height row — measured 2026-09-16, it silently dropped every count on the wider side. |
| `-qaFastForwardToRollDice` | `GameView.swift` | Plays the human's setup placements and first roll, resolving a possible seven until the main-turn controls are enabled. **Applies real moves** (writes the save and game log); wait on the target control's readiness rather than a fixed delay. |
| `-qaSeedGameHistory` | `SettlersApp.swift` | Writes one deterministic finished recording (40 moves, played by "first legal move") into the archive before the menu appears, so Game History and the replay have something real to open. Seeded AFTER `-ui-testing-reset`, which clears the archive. |
| `-qaShowHowToPlay` | `MainMenuView.swift` | `HowToPlayView` over the main menu, on its Walkthrough tab. |
| `-qaShowGameHistory` | `MainMenuView.swift` | `GameHistoryView` over the main menu. Pair with `-qaSeedGameHistory`, or it correctly shows its empty state. **Must NOT be combined with `-qaAutoStart`.** |
| `-qaShowReplay` | `MainMenuView.swift` / `GameHistoryView.swift` | Opens the newest recording's `GameReplayView` directly - board, score strip and transport controls, no tap needed. Pair with `-qaSeedGameHistory`. |
| `-qaShowNewGame` | `MainMenuView.swift` / `NewGameSetupView.swift` | `NewGameSetupView` over the main menu, on a startable two-human/two-AI fixture (green ready plaque, Start enabled). **Must NOT be combined with `-qaAutoStart`.** |
| `-qaSeedLeaderboard` | `LeaderboardView.swift` | Records three rated games (Jake vs Jake's bundled ghost + two Classic seats) before the leaderboard loads, so the ghost page shows a record and a spider graph on a fresh install. Open the leaderboard from the main menu. |
| `-qaAskLadderName` | `LadderNamePrompt` | Shows the first-launch leaderboard name prompt even with simulator CloudKit disabled; Join saves the name used to prefill New Game. |
| `-qaShowNewGameInvalid` | `NewGameSetupView.swift` | Same screen, seat 2's name whitespace-only — the amber problem plaque and a disabled Start. |
| `-qaShowNewGameOverwrite` | `NewGameSetupView.swift` | Same screen with the "Replace your saved game?" confirmation already raised. Pair with a real save (run `-qaAutoStart -qaFastForwardToRollDice` first) to also get the amber saved-game plaque behind it. |
| `-qaShowNewGameCivilizationPicker` | `NewGameSetupView.swift` | Same screen with seat 2's civilization grid open — the only way to see a taken civilization greyed out. |
| `-qaNewGameThreeSeats` | `NewGameSetupView.swift` | **Modifier**, combines with any of the four above: shrinks the fixture to a three-player table. |
| `-qaThreePlayerTable` | `GameViewModel+QABoardDecision.swift` | **Modifier** for robber decision fixtures: builds a supported three-player game. |
| `-qaHumanSeatTwo` | `GameViewModel+QABoardDecision.swift` | **Modifier** for robber decision fixtures: assigns the acting human to nonzero seat 2. |
| `-qaScrollNewGameToBottom` | `NewGameSetupView.swift` | **Legacy modifier** retained for fixture compatibility. The compact screen now fits without requiring this scroll position. |

**`-qaAutoStart` is load-bearing for every in-game fixture above.** `GameView` only renders once
`hasStartedThisSession` is true, so every flag read inside `GameView.swift` is inert on its
own. Measured on 2026-08-29: `-qaShowEndGame` alone left the app sitting on the main menu;
`-qaAutoStart -qaShowEndGame` rendered the win screen. If a flag "does nothing", check this
before suspecting the flag.

**Debug only.** Boolean flags normally use `Settlers/QALaunchFlag.swift`'s
`isSet`; parameterized values use `QALaunchOption`. Their reads are wrapped in
`#if DEBUG`, so Release ignores them. The naval production-highlight probe below
is a deliberately local Debug-only raw argument in `GameView+QA.swift`. Its
helper and markers are also compiled out of Release. Build Debug for these fixtures.

### Voyages launch arguments and fixture bounds

Read `QALaunchFlag.swift`, `Testing/GameViewModel+QANaval.swift`,
`Testing/NavalQAFixture.swift` and `Testing/GameView+QA.swift` when changing this
branch. The table covers every actual `-qaNaval*` flag and value. At the October 5
checkpoint, adjacent/stacked fixtures from `2201653` are integrated as `5b00914`,
and the highlight probe from `4dce712` as `f602187` (pixel wait `a19ac5d`). Regular
World/fog native checks and largest-text Nearby/global Fleet choice pass on both
regular and SE devices. Frozen source `971a615` passes the complete gate; the
exact gated Debug binary also passes purchase/sailing/capture/cold-resume and
actual system Reduce Motion journeys. The final source-bound receipts live in
`docs/AI_summaries/naval-exploration/evidence/`. An older installed binary cannot
exercise the additions; build/install integrated Debug source first. The table
describes source behavior; a launch fixture alone is not a runtime pass.

| Flag/value | Consumed in | Behavior |
|---|---|---|
| `-qaNavalMode` | `ContentView.swift`, `NewGameSetupView.swift`, `GameViewModel+QANaval.swift` | With `-qaAutoStart` and no saved match, starts fresh Standard Voyages: four seats, human seat 0, no seat shuffle, 14 points. With `-qaShowNewGame`, prefills Voyages in the setup fixture instead. |
| `-qaNavalBuildScarcity` | `GameViewModel+QANaval.swift`, `NavalQAFixture.swift` | Real setup/coastal voyage baseline, with the bank-conserved hand 0 brick, 1 lumber, 0 ore, 0 grain and 10 wool. Exercises unavailable construction, shortages and disabled physical taps. |
| `-qaNavalCivilization=<rawValue>` | `GameViewModel+QANaval.swift` | Explicitly retains the chosen current-controller roster when replacing a rare baseline. All eight fleet styles can be bought and inspected; ordinary fixtures keep their original deterministic assignment. |
| `-qaNavalMixedShipsPosition` | `NavalQAFixture.swift` | Two real purchases by different owners, followed by legal sea steps, produce an actual mixed-owner stack. As with harvest fixtures, QA only refreshes travel steps between sailing rounds. |
| `-qaNavalExpert` | `GameViewModel+QANaval.swift`, `NewGameSetupView.swift` | Naval QA modifier selecting Expert and the naval revision; default is Traditional. It does not turn the complete-match driver's external human chair into Expert. |
| `-qaNavalNoFog` | `GameViewModel+QANaval.swift`, `NewGameSetupView.swift` | Naval QA modifier disabling fog. Omission leaves fog on. |
| `-qaNavalNoResourceChoice` | Same setup handlers | Naval QA modifier disabling flexible production. Omission leaves it on. Harvest fixtures require flexible production enabled. |
| `-qaNavalSeed=<UInt64>` | `QALaunchOption`, `GameViewModel.makeInitialState` | Seed for an ordinary fresh naval game, including one started from the setup screen. Omission chooses a fresh random seed; invalid values fail. Rare-state `NavalQAFixture` positions below use fixed seed 7501 regardless of this value. |
| `-qaNavalFamily=archipelago`, `-qaNavalFamily=peninsula`, or `-qaNavalFamily=twinIslands` | `QALaunchOption`, both naval setup handlers | Selects the exact raw family spelling. Omission leaves Surprise me; unknown values fail. Applies to normal naval QA setup and rare-state fixture options. |
| `-qaNavalVoyagePosition` | `GameViewModel+QANaval.swift`, `NavalQAFixture` | Completed setup, human main turn, no pre-purchased human ship and conserved extra cards sufficient for a real purchase. Use Build → Ship, preview/cancel/confirm, then select and sail through normal controls. |
| `-qaNavalAdjacentShipsPosition` | Same fixture handlers, `2201653` | Two owned ships purchased through rules, then one actual step by ship ID 1 makes them occupy adjacent sea hexes. World zoom exercises overlapping minimum hit regions and explicit identity choice. |
| `-qaNavalStackedShipsPosition` | Same fixture handlers, `2201653` | Three owned hulls purchased; ship ID 1 takes one step. Two remain stacked at launch with the third adjacent, covering same-cell plus neighbor ambiguity. It is not three ships all at one coordinate. |
| `-qaNavalCapturePosition` | `GameViewModel+QANaval.swift`, `NavalQAFixture` | A rival purchases one eligible hull, then a rigged real roll of 11 reaches the human's durable capture phase. Capture or Skip uses normal confirmation/persistence; no transfer is pre-committed. |
| `-qaNavalResourcePosition` | Same fixture handlers | An actual ship, discovery and first colony reach a flexible-production tile; a rigged real matching roll opens one settlement harvest unit. Requires resource choice on. |
| `-qaNavalCityResourcePosition` | Same fixture handlers | Upgrades that colony through a real city move, then opens two separately chosen harvest units for the same human. Requires resource choice on; useful for cold resume between units. |
| `-qaNavalProductionHighlights` | `Testing/GameView+QA.swift`, `4dce712` | Shows Debug control `qa.production.show` (“Show held production rings”). A native tap injects known and hidden same-number coordinates directly into the renderer; six perimeter probes per tile expose actual coordinates/numbers to automation. Requires a fogged naval world with suitable known/hidden production; do not pair with `-qaNavalNoFog` or a fully charted world. |

**Fresh game versus fixture.** `-qaAutoStart` resumes an existing save; naval start
flags do not replace it. Use the ladder's task-owned clean QA container, or the
first native test launch's `-ui-testing-reset`, for a new baseline. Cold resume
uses `-ui-testing` without reset so the committed state/mandatory obligation survives.
Choose one position flag. Source precedence is stacked → adjacent → city harvest
→ settlement harvest → capture → voyage. Current presentation uses natural
owner/ship wording; stored IDs and automation IDs remain zero-based.

Rare fixtures finish snake setup through legal moves, transfer supplemental cards
from bank to hand, and install a replacement replay baseline. Each begins with
extra 3 lumber, 2 wool, 2 ore, 1 grain and 1 brick in the human hand, in addition
to ordinary setup grants. Capture and nearby-hull preparation transfer additional
ship costs; city preparation transfers its upgrade cost. Counts are conserved,
but the resources were granted for QA rather than earned through ordinary turns.
Fixture construction also sets phases and rigs roll RNG; harvest travel refreshes
steps between fixture-only rounds. These shortcuts do not run in normal gameplay.
Subsequent tapped purchase, movement, capture and resource choice use real rules,
session, save and history transactions. Layout fixtures do not establish expedition
pace or full-match economics.

The production-highlight probe changes only ephemeral presentation: it commits no
roll, production, discovery or save. Its hidden-coordinate/number labels are
intentional Debug instrumentation, not evidence of ordinary VoiceOver concealment.
The native counterexample compares a changed known perimeter with unchanged hidden
fog; hosted producer tests separately cover real roll visibility and robber blocking.

Use `$SIM` from the ladder with the task-owned QA UUID. For concurrent work, set
`SETTLERS_QA_SIMULATOR_ID` to that task's assigned simulator before selecting it;
never reset a different chat's device. After installing a Debug artifact and
terminating its prior process, an ordinary reproducible opening is:

```bash
xcrun simctl launch "$SIM" "$BUNDLE_ID" -qaAutoStart -qaNavalMode \
  -qaNavalSeed=7501 -qaNavalExpert
```

For a purchase/sailing baseline add `-qaNavalVoyagePosition`; for overlap or held
highlight checks add the specific fixture/probe from the table only after its
source is integrated into the installed build. Use native XCUITest for the taps.
`-qaAutoStart -qaNavalMode -qaNavalSeed=7501 -qaNavalExpert -qaPlayToEnd` drives
actual app session/persistence to victory, with a 10,000-move cap and yielding
between committed moves. It supplies the external human chair with balanced
`HeuristicPolicy` and acknowledges durable card receipts; configured bot chairs
retain their selected tier. This is an automated complete match, not unscripted
human play or all-Expert strength measurement. `-qaShowEndGame` instead forces a
win for layout and cannot substitute for that complete-match route.

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

## Real-iPhone path

Discover the phone — do not trust `xctrace list devices`, which reports a different state
than the tool that actually installs:

```bash
xcrun devicectl list devices
```

Proceed only when Alex's iPhone is `available (paired)`. `connected (no DDI)` means the
phone must be unlocked/trusted so Xcode can mount its developer disk image.

Jake's team and bundle id remain the defaults in `Settlers/Signing.xcconfig`. Alex's
`Settlers/Signing.local.xcconfig` overrides them with team `HXB9F28LHR` and bundle id
`com.alexchandler.empires`; it is gitignored and never reaches Jake. The local file must
exist before Alex's device build — changing `project.yml` or Jake's defaults is not part of
this path.

The Xcode destination identifier and the CoreDevice identifier are different. Read the
former from `xcodebuild -showdestinations` and the latter from `devicectl list devices`, then
build and install in place so a manual-play save survives:

```bash
REPO="$(git rev-parse --show-toplevel)"
DEVICE_DERIVED="$(mktemp -d /tmp/empires-device.XXXXXX)"
xcodebuild -project "$REPO/Settlers.xcodeproj" -scheme Settlers \
  -configuration Debug -destination "id=<XCODE-DESTINATION-ID>" \
  -derivedDataPath "$DEVICE_DERIVED" -allowProvisioningUpdates build

APP="$DEVICE_DERIVED/Build/Products/Debug-iphoneos/Settlers.app"
plutil -extract CFBundleVersion raw "$APP/Info.plist"
xcrun devicectl device install app --device <COREDEVICE-ID> "$APP"
xcrun devicectl device process launch --device <COREDEVICE-ID> com.alexchandler.empires
xcrun devicectl device info apps --device <COREDEVICE-ID> \
  --bundle-id com.alexchandler.empires --columns '*'
```

The 2026-09-05 run produced `BUILD SUCCEEDED`, installed Build 4, launched it, and read Build
4 back from the phone. A transient `CoreDeviceError 3002`/`4000` merits one install retry;
repeated failure means re-check pairing, unlock state, and the DDI rather than changing
signing.

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
GATE_TEST_WORKERS=1 "$REPO/scripts/gate.sh"              # app and native UI tests
GATE_TEST_WORKERS=1 "$REPO/scripts/gate.sh --debug-app"  # also build the screenshot binary
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
- **Simulator ≠ device.** A successful install says nothing about touch latency, thermals,
  memory pressure, or every safe-area state on hardware; manual play remains the check.
- **Read the installed app back before saying it is on the phone.** The version/build row from
  `devicectl device info apps` is the completion criterion, not a successful compile.
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
