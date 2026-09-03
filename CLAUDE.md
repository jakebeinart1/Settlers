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
| Running / screenshotting the app, all nineteen `-qa*` launch flags, UI-test reset arguments, what the device path blocks on | `.claude/skills/run-settlers/SKILL.md` - **the** reference; do not re-derive it |
| Legal moves and move application (the whole ruleset) | `Packages/CatanEngine/Sources/CatanEngine/RulesEngine.swift` |
| Save-file schema and its backward compatibility | `GameState.init(from:)`, `Models/GameState.swift:110` |
| Randomness contract | `Models/RandomSource.swift` (doc comment is the spec) |
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

Gates, cheapest first: xcodegen drift · `swiftlint --strict` · both packages built with
`-warnings-as-errors` · CatanEngine tests · CatanAI tests · coverage floors (CatanEngine
**96.20%** vs floor 95, CatanAI **91.41%** vs floor 90) · gitleaks · **app build in Release**.

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

- **PR #1** (`fix/engine-determinism-and-rules`) and **PR #2** (`ci/gate-and-workflow`) are
  both **OPEN** and awaiting Jake. Nothing from this work is on `main`.
- **`-configuration Release` does not compile.** Verified 2026-08-29, exit 65. The QA hooks
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
  so a grep for any UI symbol returned two hits, one of them wrong. `TODO.md` item 1 still
  names `ClaudeDesignExport/` as the vehicle for the next design pass; that plan needs a fresh
  export from the current source, not the stale copy.

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
