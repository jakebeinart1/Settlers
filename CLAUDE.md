# Empires (repo: `Settlers`)

A native Swift/SwiftUI iOS Catan clone: a hex board, four seats, three heuristic bots, no
network and no backend. The rules and the AI live in two local SPM packages (`CatanEngine`
~2,000 lines, `CatanAI` ~1,800 lines); the app target (`Settlers/`, ~6,700 lines) is
presentation and persistence only.

**Ownership.** The repo is **Jake Beinart's** (`git@github.com:jakebeinart1/Settlers.git`,
private). Alex owns engineering and work goes back to Jake as **pull requests** - Alex has
`push` but **not `admin`** (`gh api repos/jakebeinart1/Settlers --jq .permissions` →
`admin: false`). Jake's own history is direct-to-`main`. Do not push to `main`.

## READ-FIRST - where truth lives (pointer map)

Every one of these is canonical for its question. Read the file, do not reason from this list.

| Question | Answer lives in |
|---|---|
| Build settings, deployment target, signing team, version keys | `project.yml` - **never** `Settlers.xcodeproj/project.pbxproj`, which is generated |
| What the quality gate checks, and why each gate is shaped that way | `scripts/gate.sh` (its header is the rationale, not decoration) |
| Coverage policy, the floors, the ratchet rule | `scripts/coverage.sh` |
| Why the pre-push hook drains stdin, and why an installer instead of `core.hooksPath` | `scripts/install-hooks.sh` |
| Why CI runs on Ubuntu and what it deliberately does not do | `.github/workflows/ci.yml` |
| Why each lint threshold sits where it does | `.swiftlint.yml` |
| Running / screenshotting the app, all 35 `-qa*` launch flags, UI-test reset arguments, what the device path blocks on | `.claude/skills/run-settlers/SKILL.md` - **the** reference; do not re-derive it |
| Legal moves and move application (the whole ruleset) | `Packages/CatanEngine/Sources/CatanEngine/RulesEngine.swift` |
| Save-file schema and its backward compatibility | `GameState.init(from:)`, `Models/GameState.swift:110` |
| Randomness contract | `Models/RandomSource.swift` (doc comment is the spec) |
| Why the board's viewport never moves, and what may not be changed about it | `GameView.belowBoard` + `BoardView.applicableFit` (both doc comments are the spec) |
| Why the board clips to its own bounds, and why not to its container's | `BoardView.body`'s `.clipped()` (the comment on it is the spec) |
| Bot decision entry point | `Packages/CatanAI/Sources/CatanAI/Bot.swift` |
| Bot loop, seat assignment, personality mix | `Settlers/ViewModels/GameViewModel.swift` |
| What is persisted, where, and why | `Settlers/Persistence/` - 7 stores, each with the rationale in its doc comment |
| Art assets: what is wired in, what is retired, how it was generated | `design-references/STATUS.md` |
| Feature design rationale (4 specs, Aug 2026) | `docs/superpowers/specs/` |
| Current product backlog | `TODO.md` |
| Coding standards, commit format, verification rules | `~/.claude/rules/*.md` (always-on) |

AI summaries belong in `docs/AI_summaries/` per the global rule. That directory does not
exist yet; create it rather than scattering summaries elsewhere.

## Build / run / test

Verified 2026-08-29 on Xcode 26.5, Swift 6.3.2, XcodeGen 2.46.0, SwiftLint 0.65.1,
gitleaks 8.30.1.

```bash
# Tests. Counts move; run them rather than trusting a number written here.
swift test --package-path Packages/CatanEngine     # ~5s warm
swift test --package-path Packages/CatanAI         # ~55-175s; this one dominates everything

# After ADDING OR REMOVING any .swift file under Settlers/ - before building:
xcodegen generate

# Build the app (Debug, simulator). Full ladder + screenshots: the run-settlers skill.
xcodebuild -project Settlers.xcodeproj -scheme Settlers \
  -destination 'platform=iOS Simulator,id=<SIM_UDID>' -configuration Debug build
```

**Forbidden, and why - each of these has produced a false green here:**

- **`swift test` reaches the two SPM packages ONLY.** It cannot see `GameViewModel`, the
  persistence stores, or anything else in the app target. App-target tests are a real
  bundle now - `SettlersTests` (`project.yml:80`), wired into the scheme's test action with
  coverage (`project.yml:92-104`) and run by `scripts/gate.sh:164` on every gate:
  `xcodebuild test -project Settlers.xcodeproj -scheme Settlers -destination '...'`.
  This previously read "`xcodebuild test -scheme Settlers` runs NOTHING", which was true
  when `test: targets: []` and is now false. Left uncorrected it tells the next reader that
  app-layer behaviour cannot be tested, which is exactly backwards.
- **`swift test` from the repo root fails** - there is no root `Package.swift`. Use
  `--package-path` (above) or `cd` into the package.
- **Never pipe `xcodebuild` (or any test runner) through `tail`/`head`/`grep`.** A shell
  pipeline returns the **last** command's status. Measured here: the failing
  `xcodebuild test` above, piped to `tail -25`, reported `EXIT=0`. If you must filter, read
  `${PIPESTATUS[0]}` - `scripts/gate.sh:159` does exactly that.
- **Never hand-edit `Settlers.xcodeproj/project.pbxproj`.** XcodeGen regenerates it from
  `project.yml` and the edit is silently discarded. Build settings, `DEVELOPMENT_TEAM`,
  `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` all belong in `project.yml`.
- **Never drive the simulator with desktop-coordinate click tools.** `cliclick`/AppleScript
  can hit whichever Mac window is frontmost. Native XCUITest is the supported interaction
  path; stable identifiers live in `AccessibilityID.swift`, and `-qa*` flags provide
  deterministic visual fixtures. See the run/play skills.

## The gate

Branch protection is **unavailable** on this repository and Alex is not an admin, so CI
**cannot block a merge**. The pre-push hook is the only thing in the setup that can refuse.

```bash
./scripts/install-hooks.sh          # ONCE PER CLONE. Writes .git/hooks/pre-push.
scripts/gate.sh                     # 10 gates. CatanAI and native UI tests dominate.
scripts/gate.sh --debug-app         # + also compile the app in Debug (Release always runs).
```

App/UI tests run on the dedicated `Empires QA` simulator selected by
`scripts/select-qa-simulator.py`. They erase that app container deliberately;
never replace this with "first available" or "first booted", which wiped the
manual-play simulator during an ordinary gate on 2026-09-03.

They also run **in parallel across cloned simulators** (`Clone N of Empires QA`,
created by xcodebuild - still not your manual-play device). Both bundles are
marked `parallelizable` in `project.yml`; the worker count is machine-specific
and lives in `gate.sh` (`GATE_TEST_WORKERS`, default 2). Measured on 8 cores /
16GB, same tree: 1151s serial, 731s at 2 workers, 681s at 3 - but 3 starved two
tests into failing. **A test that fails only at a higher worker count is a
suspect, not a verdict**: re-run it serially before believing it. `gate.sh`'s
`gate_app_tests` header names both of those and why each was starvation rather
than a bug.

Gates, cheapest first: xcodegen drift · `swiftlint --strict` · evaluation-tool tests · both
packages built with `-warnings-as-errors` · CatanEngine tests · CatanAI tests · training
export validation · coverage floors · gitleaks · app/UI tests · **app build in Release**.

Three properties it is built around, and that any change to it must preserve:

1. **Every verdict comes from an exit code.** Nothing parses tool output to decide pass/fail.
2. **A gate that cannot run prints `SKIP`, never nothing.** "I did not check" and "I checked
   and it was fine" must look different.
3. **It does not stop at the first failure.** Three red gates found at once beats three pushes.

`git push --no-verify` bypasses it. If you are reaching for that routinely, the gate is
wrong - fix the gate.

## Anti-false-green - lessons this repo has already paid for

Each of these produced a green signal over a broken thing. They are listed because the
mistake is cheap to repeat.

- **XcodeGen discards `project.pbxproj` edits.** A build setting typed into the pbxproj
  survives until the next `xcodegen generate` - which the drift gate runs on every push.
  Worse in the file-list direction: a new `.swift` file on disk that has not been generated
  in fails with `cannot find 'X' in scope`, naming the *symbol*, not the file, which sends
  people hunting an import bug that does not exist.
- **An empty `test: targets:` makes "tests passed" a message about nothing.** That was
  literally true here - the app scheme once had `targets: []`, so `xcodebuild test` reported
  success having run zero tests. It is fixed (`project.yml:92-104`), and the lesson is kept
  because the failure is silent: a test action with no targets does not error, it passes.
  If the app suite's count ever drops toward zero, check the scheme before the tests.
- **"Seat 0 is the human" was copied into several places and is not fully dead.** Jake's
  `8710045` ("Randomize Seat") fixed the copies in `CatanTheme.playerLabel`,
  `GameViewModel.drawAssignment`, `GameViewModel.personality(for:)`, `ContentView`'s bot-loop
  kickoff, and `BotHUDRow`/`HumanPlayerPanel`/`EndGameView`. A fourth copy survived in
  `RulesEngine.playerLabel(_:)` - in another module, which is why it was missed twice - and
  wrote `state.log` lines calling a bot "You" in three games out of four. It now numbers seats
  ("Player 1"..."Player 4") and leaves naming to the UI, because the engine has no notion of a
  human seat and should not acquire one to answer a presentation question. **If you find
  yourself adding a fifth copy, that is the signal to pass the seat instead.**
- **The board's size must never be a layout *remainder*, and a remembered fit is not a fix
  for that.** `GameView` gave `boardArea` `maxHeight: .infinity` in a column whose other rows
  came and went, so the board's own container measured **362.67, 382.67 or 503.67 points on
  the same device in the same game** depending on which panels were up - the board re-zoomed
  and re-centered on a placement, on an incoming trade offer, and on a seven. The fix applied
  first was to lock `BoardView`'s fit to the *tallest container it had been given*, and that
  is the part worth remembering: **it looked like it worked and made the bug worse.** It
  replaced a frame-dependent board size with a *history*-dependent one, so a game that rolled
  a seven kept a board 39% too big for every later screen - drawn ~70pt below its container
  and clipped, which is what cut the outer port badges off - while a game that never rolled
  one kept a correct board. Two identical games, two board sizes, and no test could see it
  because each game was internally consistent.
  **No rule that observes the container can fix this**: tallest-seen is history-dependent,
  shortest-seen shrinks the board mid-game, first-seen locks to the untrustworthy first
  frame. The container has to stop varying. It does now: everything below the board lives in
  a fixed `GameView.belowBoardReserve`-point frame, so panels inside it come and go without
  reaching the board, and `BoardView`'s fit is a pure function again with **no stored fit at
  all**. `BoardViewportInvarianceTests` launches every phase fixture and compares the board's
  own frame; removing the reserve fails it immediately (measured: 382.67 vs 362.67).
  **If the board ever moves again, the container moved - fix the layout, never re-introduce a
  remembered fit.**
- **A fixed reserve stops the BOARD moving; it does not stop rows moving INSIDE the reserve.**
  The 20pt info-banner row at the top of `belowBoard` was still conditional - omitted whenever
  a board decision was up, on the reasoning that the command dock could have the room. It could
  not: `BoardDecisionDockView` is pinned to the same `BottomRowMetrics.height` as the action row
  it replaces. So the row was deleted for nothing, and the player nameplate and the whole command
  row under it jumped **exactly 20 points** up the screen the moment a settlement placement, a
  knight, or a rolled seven began, then dropped back when it ended. Same bug one level in: **a row
  whose height depends on the phase moves every row after it.** Reserve the row and make only its
  *content* conditional. `BelowBoardInvarianceTests` measures `game.command-row` across six phase
  fixtures and fails on a 1pt difference (measured with the row conditional again: 752.0 vs 732.0).
- **Half the board clipped and half did not, and the resting fit hid it.** Tiles, ports and the
  robber are drawn into a `Canvas`, which clips to its own frame for free. Settlements, cities and
  roads are ordinary SwiftUI views placed with `.position(...)` and `Path.fill`, which are **not**
  bounded by the frame they sit in. At the fitted camera nothing reaches an edge, so the two look
  identical; the moment a player pinched in, the hexes stopped dead at the board's top edge while
  pieces kept going, floating over the bot HUD cards and the painted sky above them.
  `GameView.boardArea` already clipped, and that is precisely why it did not help - that container
  is taller than `BoardView` by `topChipInset` (the room reserved for the dice and bank chips), and
  that band is exactly what the pieces escaped into. The clip belongs on `BoardView` itself, whose
  frame is the viewport a player perceives. Verified by screenshot, before and after, at the same
  zoom and pan on the same fixture.
- **An accessibility identifier on a CONTAINER can delete its children's containers.** Adding
  `.accessibilityElement(children: .contain)` + an identifier to `GameView.bottomPanel` - purely
  to give a test a frame to measure - made that row an accessibility ancestor of
  `BoardDecisionDockView`, and `app.otherElements["board-decision.dock"]` stopped resolving.
  **Eleven** board-decision UI tests failed, every one of them reporting nothing but a bare
  `XCTAssertTrue failed` from a `waitForExistence` with no message, which points at the board and
  not at the row two levels above it. The fix is to measure from a SIBLING leaf
  (`GameView.commandRowFrameMarker`, a Debug-only empty `.background` element), never from an
  ancestor. If a batch of unrelated element lookups fails at once, suspect a new container above
  them before you suspect any of them.
- **SwiftPM will serve a stale module after a public API change**, producing a runtime crash
  that a clean rebuild fixes and that no rebuild-in-place reproduces. If behaviour contradicts
  the source you are reading, `rm -rf Packages/<Pkg>/.build` (or `swift package clean`) and
  re-run **before** debugging the logic.
- **A `where` clause binds only to the pattern it directly follows.** `GameView.swift:428`
  now repeats it on both patterns; the single-clause spelling left `.setupForward` matching
  *every* seat, driving a human move on a bot's setup turn, and a `try?` swallowed the
  resulting error so the hook looked like it worked. `SWIFT_TREAT_WARNINGS_AS_ERRORS` on the
  app target is what surfaced it - do not turn that off.
- **SwiftLint walks the filesystem, not git.** A gitignored `DerivedData/` inside the repo is
  therefore linted. Measured 2026-08-29: two `trailing_newline` errors on Xcode's own
  `GeneratedAssetSymbols.swift` turned the whole gate red on files nobody wrote.
  `.swiftlint.yml` excludes `.build` and `.ci-derived` but **not** `DerivedData`. Build with
  `-derivedDataPath` pointing **outside** the working tree.
- **A green build is a compile claim; "it works" is a runtime claim.** Native XCUITests cover
  critical setup/settings/resume paths, but visual changes still need an inspected screenshot
  and gameplay claims still need the play-settlers workflow.

## Determinism invariants (easy to break silently, expensive to notice)

The engine is reproducible: the same seed replays a game move-for-move **across separate
processes**, and a recorded `GameLogStore` trajectory replays exactly. It previously diverged
at move 17 of 590.

**Read that "across processes" carefully - it is the whole difficulty.** `761822f` fixed the
RNG and was verified by playing a seed twice *inside one process*, which passed while the
property was still false: Swift seeds `Set`/`Dictionary` iteration order once per process, so
two runs in one process agree with each other and disagree with tomorrow's. Four further
places let that ordering reach a decision, all found afterwards - a `Double` summed over a
filtered `Set` (floating-point addition is not associative, so a "tie" broke differently), a
best-vertex pick by strict `>` over a `Set`, a dictionary flat-map, and a `.first` on a `Set`.

`SeededGameFingerprintTests.swift` is the guard that actually holds: it pins the exact move
sequence of five seeded games, and because every test process gets a fresh hash seed, a
regression fails it rather than merely flaking. `DeterminismTests.swift` and
`SaveCompatibilityTests.swift` cover replay and save compatibility. A change that breaks one
of these may still pass every other gate.

1. **All randomness goes through `state.rng`.** `GameState` owns a `RandomSource`
   (SplitMix64, `Codable`). Any new `Int.random`, `.randomElement()`, `.shuffled()` or
   `SystemRandomNumberGenerator` inside `CatanEngine` is a bug - pass `using: &state.rng`.
   Keeping the generator in state (rather than threading an `inout` through `apply`) is what
   makes a *resumed save* continue its sequence instead of restarting it.
2. **New enumeration must be order-stable.** `Set` and `Dictionary` iteration order is seeded
   per process in Swift, so it differs between launches. `RulesEngine.legalMoves` `.sorted()`s
   its edge/vertex/settlement walks and drives resource enumeration off `Resource.allCases`
   rather than `player.resources`. Do the same in anything new.
3. **`legalMoves` must stay a pure function of the state.** Enumerated `.proposeTrade`
   candidates take a content-derived id via `TradeOffer.enumerated` (FNV-1a over proposer +
   sorted give/want). A fresh `UUID()` per call made two calls over identical state return
   unequal offers. Offers the *player* creates in the UI keep the random default - those are
   genuinely distinct proposals.
4. **Every new `GameState` field must decode with a default.** `init(from:)` is hand-written
   (`Models/GameState.swift:110`) precisely because the synthesized one uses `decode`, not
   `decodeIfPresent`, for non-optionals - `GameStore.load()` swallows the throw with `try?`
   and the app silently starts a new game. **Adding one field once deleted every player's
   in-progress save** (`tradesAcceptedThisTurn`). Only `board`, `players` and `phase` may
   throw. Bump `schemaVersion` and add a `SaveCompatibilityTests` case.

Corollary: **`CatanEngine` and `CatanAI` import only `Foundation`** (plus `CatanEngine` from
`CatanAI`) and have zero external dependencies. That is what lets CI test them on Linux at 1x
billing. Importing UIKit/SwiftUI/Darwin into either package breaks CI, not just taste.

## Commits, branches, PRs

- **Conventional commits**: `type(scope): description` - `feat` `fix` `docs` `style`
  `refactor` `test` `chore`. Per `~/.claude/rules/gitflow.md`.
- **Jake's own style is sentence-case, imperative, no type prefix, committed straight to
  `main`** ("Add bot trade messages, painted-chrome UI overhaul, trade heuristic tuning").
  That conflicts with the global gitflow rule. **Alex's commits follow the global rule**; do
  not retroactively rewrite Jake's, and do not adopt his style for new work.
- Branch per unit of work (`fix/`, `feat/`, `ci/`, `build/`), PR into `main`, never push to
  `main` directly. The current stack is `feat/stage-0-cleanup` on top of
  `ci/gate-and-workflow` on top of `fix/engine-determinism-and-rules`.
- Commit bodies here are long and explain *why*, with measured numbers. Match that; the
  existing bodies (`761822f`, `1f3618d`) are the template.

## Known-open

- **There is nothing open.** `gh pr list --state open` returns empty as of 2026-09-09.
  This entry previously said PR #1 (`fix/engine-determinism-and-rules`) and PR #2
  (`ci/gate-and-workflow`) were "**OPEN** and awaiting Jake" with "nothing from this work on
  `main`" - both merged on 2026-08-29 and the line stayed wrong for eleven days, telling
  every reader the determinism and gate work was unlanded when it had been `main` for over a
  week. **Check the PR list rather than trusting this bullet.**
- **`main` moved twice on 2026-09-09.** Alex's PR #47 (`codex/heuristic-corpus-plan-...`,
  merge `1d11da4`) closed the heuristic trial: ~6,400 lines of trade-diagnostics research -
  new `CatanAI` trade tests, four corpus tools under `scripts/` with their own Python
  suites, and the `docs/AI_summaries/` write-ups. Rome's art rebuild (`67b8bb6`) went on top
  of it. Anything written against an earlier tree - `design-references/STATUS.md` included -
  predates both.
- **RESOLVED, kept for the lesson: `-configuration Release` once did not compile.**
  Verified 2026-08-29, exit 65. The QA hooks
  `qaForceHumanWin` and `qaSeedPendingTradeConfirmation` were moved behind `#if DEBUG` in
  `GameViewModel.swift:313`, but their call sites - `ContentView.swift:87` and
  `GameView.swift:353` - were not guarded. **Every gate is green while this is broken**:
  the gate built Debug only, so a Release-only break was invisible to the whole setup. Both
  are fixed: the call sites are guarded, and **`gate.sh` now compiles Release on every run**
  (Debug is the opt-in one, `--debug-app`). Debug and Release are different programs the
  moment a `#if` enters the codebase.
- **The coverage gate flaked once.** On one `gate.sh` run the CatanAI test stage finished
  green but left no merged `default.profdata`, so `coverage.sh --reuse` reported
  `FAILED to produce coverage data`. Not reproducible in three subsequent attempts. Note that
  it failed *loudly* - that is the designed behaviour, not a bug in the gate. Recovery: re-run
  `scripts/coverage.sh Packages/CatanAI 90` **without** `--reuse`.
- **`ClaudeDesignExport/` and `BuildingsDesignExport/` have been deleted** - 3,934 lines
  compiled by nothing (`project.yml` builds only `Settlers/`) and drifted from the real views,
  so a grep for any UI symbol returned two hits, one of them wrong. This entry used to add
  that "`TODO.md` item 1 still names `ClaudeDesignExport/` as the vehicle for the next design
  pass"; `TODO.md` no longer mentions it anywhere (checked 2026-09-09), so that warning is
  retired too.
- **One app test is an unexplained flake.**
  `CheckpointExportTests.retryReplacesATruncatedArchiveWithoutDuplicatingMoves` asserts byte
  equality across two exports of one checkpoint. Measured 2026-09-09 on one tree: **failed**
  under the gate at 2 workers and again in a serial full-suite run, then **passed** in a
  second serial full-suite run, in isolation, and in the gate run that landed `67b8bb6`.
  Clean `HEAD` passed a full suite too. So it is not tied to a change, and it does not
  reproduce in isolation - only under full-suite conditions. **The cause was not found.** A
  `Set<PlayerID>` encoded as an unordered JSON array in `GameLogStore.SeatRoster.encode` was
  the obvious suspect and is probably *not* it (two identically-built Sets share an iteration
  order within one process). Worth solving before it fails a run that matters.

## Settled dead ends - do not re-litigate

- **Branch protection.** Unavailable: private repo on a plan without it, and Alex is not an
  admin (`gh api .../branches/main/protection` returns 404 for a non-admin; a write attempt
  answers 403 "Upgrade to GitHub Pro or make this repository public"). The pre-push hook is
  the gate. Do not describe CI as blocking anything.
- **Per-push macOS GitHub runners.** Billed at a 10x minute multiplier. Alex exhausted his
  Actions allowance on 2026-07-27 across two other repos, after which every workflow failed in
  ~2s having run zero steps. Package tests run on `ubuntu-latest` in `swift:6.1`; the XcodeGen
  drift job is macOS and `workflow_dispatch`-only. Verified working, run `33273621617`.
- **Installing on Alex's iPhone.** `project.yml` signs to Jake's team `KDM65HE483`; Alex holds
  identities only for `HXB9F28LHR` and none for Jake's. Retargeting `DEVELOPMENT_TEAM` is a
  real change to a file that goes back to Jake - **ask first**, never quietly. The simulator
  is the only route to a screen today.
- **Threading an `inout RandomNumberGenerator` through `RulesEngine.apply`.** Rejected: it
  changes every call site in three modules and still leaves save/resume non-deterministic,
  because the generator's position would not survive being written to disk. The generator
  lives in `GameState` instead.
- **Adding an Xcode test target.** The tests are SPM tests and run on Linux for 1x billing.
  Keep them there.

House style still applies (`~/.claude/rules/`): fail-fast over defensive conditionals,
functions under ~30 lines, named constants over magic numbers, docs that state the *why*, no
claiming "done" without a run you actually watched, and `echo -e '\a'` on every pause or
finish.
