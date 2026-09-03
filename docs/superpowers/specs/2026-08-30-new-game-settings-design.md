# Empires — New Game Settings Stage

**Spec version:** 1.2 · **Date:** 2026-08-30 · **Status:** implemented with amendments
**Repo:** `Settlers` (app "Empires"), branch off `main`, PR to Jake.

> **Verification note on the source material.** Two claims carried into this stage from prior work are **wrong** and have been corrected here from source:
> 1. **`project.yml` no longer sets `test: targets: []`.** It declares a real `SettlersTests` bundle (`project.yml:76-90`) and wires it into the scheme's test action with coverage (`project.yml:92-104`), and `scripts/gate.sh:164` runs `xcodebuild test -scheme Settlers` on every gate. **App-layer unit tests are available and are the primary verification tool for this stage.** `CLAUDE.md`'s "xcodebuild test -scheme Settlers runs NOTHING" section is stale and must be corrected as part of this work.
> 2. **`GameViewModel.humanPlayer` has 35 references across 6 files**, not ~60 across 9: `ContentView.swift`, `GameViewModel.swift`, `Theme/Civilization.swift` (a doc comment only), `Views/TradePopupView.swift`, `Views/GameView.swift`, `Views/DiscardPopupView.swift`. `PlayerHUDView`, `EndGameView` and `GameLogStore` take a seat as a parameter and never read the global.
>
> A third correction matters for scope: **bot chips already hide hands.** `PlayerChip.body` renders `state.publicVictoryPoints(for:)` (`PlayerHUDView.swift:422`), a hand-*size* badge (`:459`) and a dev-card count — never the per-resource breakdown. The class doc at `PlayerHUDView.swift:8-12` claiming "Every player's resource hand is shown in full" is stale; the code is truth. Hiding a non-device human's hand therefore costs one filter change, not a new view.

---

## Amendments after implementation

Recorded rather than silently corrected, because this document was written before the code and a
reader needs to know where it now diverges.

- **Three-player tables were built.** Listed as a non-goal here; the supplied design carried a Table
  Size control, and shipping a toggle that did nothing would have been worse than doing the work.
  `GameSetup.supportedPlayerCounts` is `3...4`.
- **`GameSetupStore` never shipped under that name.** The consolidated per-game value is
  `MatchSetup` with `MatchSetupStore`, in `Settlers/Persistence/MatchSetup.swift`.
- **Five QA flags named here do not exist.** The authoritative list is the enum in
  `Settlers/QALaunchFlag.swift`, mirrored in `.claude/skills/run-settlers/SKILL.md`.
- **A4.4 (the AI honouring the victory target) is not implemented** and is now marked deferred in
  the acceptance-criteria document. It is a bot-strength change, not a settings change.
- **Four-player Epic is no longer offered for new games.** A measured base-board
  game reached 11/11/11/10 and then remained unchanged through 10,000 actions,
  so a four-player 12-point game can have no winner. Three-player Epic remains
  available. Intrinsic match validity is separate from current product
  availability so existing four-player 12-point checkpoints still resume.

---

## 1. Goal and non-goals

**Goal.** Turn the title screen into the screen where a match is configured, and make the four seats configurable along the three axes that are cheap and safe today: **who occupies each seat** (1–4 humans on the fixed four-seat table, with a hot-seat handoff that keeps one person's hand off another person's screen), **which empire each seat plays** (per-seat civilization assignment with a guaranteed-distinct roster and per-human names), and **how long the match runs** (victory target 8/10/12). Everything is presented in the existing painted gold-trim chrome; the one-tap path from launch to a playing game is preserved. Exactly one piece of this reaches the engine — the victory target — and it is paid for with a `schemaVersion` bump, a tolerant `decodeIfPresent`, and a `SaveCompatibilityTests` case.

**Non-goals.**
- **Bot difficulty tiers — deferred.** The three `BotPersonality` values are play *styles*, not strengths; nothing exposes `BotWeights`' constants as levels, and an honest strength claim needs ~1,248 games per arm against a frozen anchor (the `bot-strength` skill). A settings change cannot carry that cost.
- **Variable table size — deferred.** `GameSetup.newGame` builds `(0..<4).map` (`Models/GameState.swift:196`); `StateEncoding.seatCount` and the HUD layout both assume four. This stage decides who occupies four seats, not how many there are.
- Human-to-human trading (see D-11), networked play, per-seat pacing, banner art, per-player colour independent of civilization, discard-threshold or robber-on-7 variants, masking `GameObservation.state` from bots (a recorded engine deferral, `GameSession.swift:8-15`), and moving `policySeed` into `GameState`.

---

## 2. Decision log

Every decision from the five inputs, de-duplicated and resolved. Where inputs disagreed it is marked **⚔ CONFLICT**.

| # | Question | Decision | Why |
|---|---|---|---|
| **D-1** | How is "which seats are human" represented? | `GameViewModel.humanSeats: Set<PlayerID>` plus a `sortedHumanSeats: [PlayerID]` accessor used for **every** enumeration. | Membership is the dominant question at the call sites (`$0.id != humanPlayer` appears in `seatRoster` :265, the trade resolver :405, the QA filter :372, `BotHUDRow` :24, the offer filter `GameView.swift:1055`). A bare count cannot express "humans in seats 0 and 2". `[SeatKind]` reintroduces the raw index `PlayerID` exists to hide. The sorted accessor is not decoration — §2 of the review standard. |
| **D-2** | Where does "who is holding the phone" live? | `GameViewModel.seatAtDevice: PlayerID?`, `nil` until claimed. Resolved as `seatAtDevice ?? sortedHumanSeats[0]`, with a precondition that `humanSeats` is non-empty. | Optional is what makes relaunch correct with no second flag: a killed hot-seat game has nobody at the device. It cannot live in `GameView` `@State` — `ContentView` rebuilds `GameView` on `.id(viewModel.gameGeneration)` (`ContentView.swift:41`), and `openIncomingOffer` (`GameViewModel.swift:769`), which the bot loop reads, needs it. The `??` fallback is what keeps every single-human call site byte-identical. |
| **D-3** | Event-driven handoff or derived state? | **Derived.** `needsHandoff = humanSeats.count > 1 && owedHumanSeat != nil && owedHumanSeat != seatAtDevice`. Tapping Ready assigns `seatAtDevice = owedSeat`. | An event needs a firing site at every transition that can hand control to a person, and the bug is always the site nobody remembered. `GameView` already carries those scars — `GamePhase.awaitingSeatIndex` exists because six hand-written copies of "is it my turn" disagreed. Derived state cannot miss a transition, is idempotent, and gets the relaunch case free (`nil != anySeat`). |
| **D-4** | Does `GameViewModel.apply(_:)` gain a seat parameter? | **No.** It keeps `apply(_ move:)` and applies as `seatAtDevice`, with an assertion that `seatAtDevice ∈ humanSeats`. | There is exactly one person who can tap at any moment. A seat parameter is the same value threaded through ~15 call sites for no added information and fifteen chances to pass the wrong one. `GameView.swift:466` already made that mistake once — driving a move for a seat whose turn it was not, with `try?` swallowing the rejection. |
| **D-5** | Is the handoff cover a `PopupCard`? | **No — a dedicated opaque full-bleed view** on `PaintedChromeBackground`, dismissible only by its one gold button. | `PopupCard`'s scrim is `Color.black.opacity(0.45)` (`DevCardPopupView.swift:172`) and it dismisses on an outside tap. 45% leaves `HumanPlayerPanel`'s resource dots legible, and tap-to-dismiss hands the phone to nobody while revealing the previous player's hand. Same paint box, opposite mechanics. |
| **D-6** | Does the cover reappear on return from background? | **No.** It is a turn-boundary mechanism only. | The person who backgrounded the app is the person already holding it. Re-covering after every notification reads as broken. The genuine boundary is the device lock screen, which is not this app's to enforce. `ContentView.swift:99-105` already hooks `scenePhase` if playtesting reverses this. |
| **D-7** | Does seat composition go into `GameState`? | **No.** It goes into a new per-game `GameSetupStore`, which subsumes `HumanSeatStore` and `CivilizationAssignmentStore`. | §1: the engine must not learn which seat is human — that assumption has produced a real bug all five times it was made, most recently `GameSession.nextActor()` guessing seat 0 in `.discarding` (now fixed at `GameSession.swift:122-133`). §2: every `GameState` field is a schema event on a struct where one added field deleted every save in the field. |
| **D-8** | ⚔ **CONFLICT.** One store per fact, or one consolidated per-game store? | **Consolidate.** One `Codable` `GameSetup` value (human seats, seat→civilization, victory target, human names snapshot) in one store, written at `startNewGame`, cleared where the save is cleared. `load()` falls back to the legacy `HumanSeatStore` integer and `CivilizationAssignmentStore` file when the new value is absent. | Today per-game state is already split with **two different lifecycles and one leak**: `EndGameView.swift:67-68` clears `GameStore` and `CivilizationAssignmentStore` and **not** `HumanSeatStore`. Adding two more separate stores multiplies a live inconsistency. Legacy fallback is mandatory: `HumanSeatStore.load()` reads `object(forKey:) as? Int ?? 0` (`HumanSeatStore.swift:20`), which returns seat 0 for any miss — getting this wrong silently moves an in-progress game's human to seat 0 with no error. |
| **D-9** | ⚔ **CONFLICT.** Where does the identity model live — app layer, or a new `CatanIdentity` SPM target? | **App layer** (`Settlers/Theme/`, `Settlers/Persistence/`), tested in `SettlersTests`. | The argument for a new SPM target rested entirely on "there is no app test target" — which is **false** (see the verification note). `SettlersTests` exists, runs in `gate.sh:164`, and already `@testable import Settlers` (`PersistenceTests.swift:3`). A new package product also risks the XcodeGen `- package: CatanEngine` declaration (`project.yml:52`) needing an explicit `product:`. Zero benefit, real build-system risk. |
| **D-10** | ⚔ **CONFLICT.** How does the picker resolve a civilization another seat holds — disable, push-to-random, or swap? | **Swap**, with the dimmed tile labelled with the owning seat's number in that seat's `accentColor`. | Disabling is a dead end the player must back out of and solve; the app's existing dimmed-inert pattern (`SettingsView.swift:~168`) reads as broken rather than as a rule. Pushing the other seat to Random silently discards a choice. Swap resolves it in the tap already made and always leaves four distinct civilizations — a property test can assert that. |
| **D-11** | Can a human trade with another human? | **No, this stage.** Proposals are answered by bot seats only; other human seats neither see nor answer them. The 4-human case must be closed at the button. | `TradeOffer` carries no recipient — `proposeTrade` is a broadcast. Making it work between people on one phone needs a handoff round-trip per recipient and interacts with `waitForFairAcceptWindow`'s timing model. The button already reads "Propose to Bots" (`TradePopupView.swift:384`). **This is not hypothetical:** `resolveHumanProposedTrade` withdraws a universally-rejected offer via `decisions.first?.bot` (`GameViewModel.swift:447`); with no bot seats `decisions` is empty, the withdrawal is skipped, and `Trading.respond` requires `responder != offer.from`, so the proposer cannot withdraw it either. The offer sits in `pendingTradeOffers` for the rest of the game. |
| **D-12** | Do multi-human games count toward the lifetime win rate? | **No.** Skip `GameStatsStore.recordGameEnd` entirely when `humanSeats.count > 1`. | "Win rate" means "how often do you beat the bots". Crediting any human win makes a 4-human game a guaranteed 100%; crediting only the first human records three in four as losses for someone who was not playing. `GameStatsStore` keeps totals, not per-game records (`GameStatsStore.swift:9-13`), so corruption is unrecoverable short of Reset Stats. |
| **D-13** | ⚔ **CONFLICT.** How are human seats labelled? | **Per-human names, keyed by human *slot*, not seat.** Slot 0 keeps the existing `playerDisplayName` key and its "You" fallback; slots 1–3 get their own keys defaulting to "Player 2/3/4". With exactly one human seat and no custom name, every label is byte-identical to today. | The handoff card is the feature, and "Pass the phone to Sam" is materially better than "Pass the phone to Player 3". Slot keying (not seat keying) because seat is randomised per game (`GameViewModel.swift:193`) — a seat-keyed name follows the chair, not the person. Keeping slot 0's existing key means no migration; `PlayerNameStore.save` already trims (`PlayerNameStore.swift:26`). |
| **D-14** | Can a human rename an AI seat? | **No.** An AI seat is always `Civilization.generalName`. | The general name is what the `TradeMessages` pools are written around — Ragnar delivering a Norse line coheres, "Dave" does not. It is also a second free-text field per seat on a 375pt portrait screen for no gameplay value, and a derived name cannot drift out of sync with the civilization. |
| **D-15** | Name length cap? | **12 characters at input**, ellipsis truncation as backstop. | `PlayerChip`'s 10pt serif was sized to fit "Charlemagne" (11) across a chip that gets a third of the screen, and deliberately carries **no** `minimumScaleFactor` so all chips render at one size (`PlayerHUDView.swift:389-397`). 12 keeps every possible seat name inside a layout already proven to hold. |
| **D-16** | Where does the victory target live? | **A `GameState` field** `victoryPointTarget: Int`, with `WinCondition.standardTarget = 10` as the named default and `decodeIfPresent ?? standardTarget` in `init(from:)`. `schemaVersion` → 2. | A static/global makes `legalMoves` depend on process history rather than position — the class of defect the four `Set`-ordering bugs were, and it would not survive a save (a 12-point game resumed would silently revert to 10). Threading a parameter through `RulesEngine.apply` is the exact shape of the already-rejected `inout RandomNumberGenerator` proposal. A `UserDefaults` store is wrong because the win threshold is unambiguously a rule the engine owns; keeping it beside the position makes resume, replay and the log correct for free. |
| **D-17** | Free number or named lengths? | **Three tiles — Short 8 / Standard 10 / Long 12** — persisted as a plain `Int` via `@AppStorage`, with an engine `precondition(6...13)`. | Players want "a shorter game", not 11. Storing the `Int` keeps `@AppStorage` simple and makes a fourth length a one-line change. The `6...13` guard is honest: buildings alone cap at 13 (`Building.maxSettlementsPerPlayer` 5 + `maxCitiesPerPlayer` 4 = 13), so a target above 13 can be unreachable from buildings; below 6 the setup phase nearly decides it. The UI never offers the edges. |
| **D-18** | Does `StateEncoding.victoryPointTarget` (`StateEncoding.swift:127`) follow the game's target? | **No.** Keep it fixed at 10, **rename it** `victoryPointNormaliser`, and correct its doc comment, which after D-16 falsely claims to mirror `WinCondition`. | It is a *scale*, not a rule: feature slot meaning must be constant across every position forever, and `StateEncoding`'s own doc (`:51-69`) argues at length that a silently shifted scale produces no error, only a model that plays badly. Verified dead code today — nothing in `CatanAI` or `Settlers` calls `StateEncoding.*`; only `StateEncodingTests` does. The right time to add a target *slot* (with a `layoutVersion` bump) is when a trainer exists. |
| **D-19** | Does a changed target need `CatanAI` changes? | **No — and say so in the commit body so it is not re-investigated.** | Verified, not assumed: `ThreatAssessment.score` contributes `victoryPoints * victoryPointWeight` linearly (`ThreatAssessment.swift:23`) and every consumer reads it through `relativeWeight` (`:79`) or `ownStanding` (`:106`), both *ratios* against the field average, then clamped. It is the only VP reference in all of `Packages/CatanAI/Sources`. No absolute threshold exists anywhere. The bots will not accelerate into a closing move at target 8 — but they have no closing-move concept at any target, which is a bot-strength question this stage must not open. |
| **D-20** | Does the main menu become the new-game screen, or push to one? | **The main menu becomes it.** Wordmark shrinks into a top bar. | A pushed screen makes starting a game two taps where it is one today. A "Quick Game / Custom Game" split guarantees most players never see the seat rows, defeating the point. Height budget on the tightest target (375×667, ~647pt usable): top bar 44 + Resume 52 + section label 24 + 4×60pt rows with 8pt gaps 264 + collapsed Match Options 44 + pinned Start 56 + padding ~48 ≈ **532pt**. Fits collapsed; scrolls only when Match Options is deliberately expanded. |
| **D-21** | What happens to Settings' "Bot Roster" checkbox list? | **Keep it, redefined as the pool that seats set to "Random" draw from.** Every AI seat defaults to Random. | Deleting it forces a decision nobody asked to make; today's default ("three random opponents from a roster I curated") is a good default worth preserving. Redefining it needs no `Codable` migration on `CivilizationSettings` and makes the seat row a strict superset of today's behaviour. |
| **D-22** | `CivilizationSettings.minimumIncludedBots = 3` with fewer AI seats? | **Leave the constant at 3** as a Settings floor. It is a standing preference for a pool, not a per-game requirement; the draw already falls back to all civilizations when the pool is short (`GameViewModel.swift:282-284`). Hide the Bot Roster section entirely when the last-chosen configuration has 4 humans. | Changing the floor per-game would make Settings' behaviour depend on a game not yet started. The pool only needs `4 − humanCount` distinct entries at draw time, and the existing fallback already guarantees that. Zero code change to `CivilizationSettingsStore`. |
| **D-23** | "Randomize Seat" vs. a screen that shows which seat you are in. | **Tapping any seat's role control turns Randomize Seats off**, visibly, and the Match Options summary line changes from "Random seats" to name the seats. While randomisation is on, seat pips show a shuffle glyph rather than numbers. When randomisation places a human onto a seat, **swap that seat's civilization with the human's chosen one**, so the human always plays the empire they picked and the table still holds exactly the four configured civilizations. | Disabling the role controls shows four seat rows and refuses to let you use the one thing they are for. Dropping the toggle removes a shipped feature that defaults on (`MainMenuView.swift:28`) and would fix every game's draft position. Auto-off makes choosing a seat *be* the act of turning randomisation off. |
| **D-24** | Is "New Game" allowed to destroy a save silently? | **No.** When `GameStore.shared.hasSave()`, Start Game shows a `PopupCard` confirmation reusing `PauseMenuView.confirmation`'s layout, extracted into a shared component. With no save, Start Game is one tap and shows nothing. | Today one tap silently overwrites the save at `GameViewModel.swift:202`. A system `.confirmationDialog` is ruled out by the same precedent that produced `PauseMenuView` (`PauseMenuView.swift:3-9`). Gating on `hasSave()` — which is one `fileExists`, `GameStore.swift:58-60` — protects the one-tap premise. |
| **D-25** | Where do the lifetime stats tiles go? | **Into `SettingsView`, next to Reset Stats.** | They cost ~44pt on the screen's most contested axis and answer a look-backward question on a look-forward screen. "Reset Stats" (`SettingsView.swift:~230`) currently offers to clear numbers you cannot see from that screen; moving them fixes both. |
| **D-26** | Do the two `Toggle`s survive as system switches? | **No** — painted check rows, following `SettingsView.civilizationRow`'s existing pattern. | Inside an options block that also holds three painted victory-target tiles, a system switch is the one element not from the same paint box — the exact failure `PauseMenuView` was written to fix. |
| **D-27** | ⚔ **CONFLICT.** New Settings UI: painted gold chrome, or `SettingsView`'s existing flat dark? | **Flat dark**, matching `SettingsView.civilizationRow` (`SettingsView.swift:266-298`: `RoundedRectangle(cornerRadius: 10)` on `Color(white: 0.14)` over a `Color(white: 0.08)` ground). The **new-game screen** and the **pause menu's new Settings row** are painted, because they sit on the game surface. | The constraint is "no bare system controls", not "everything must be gold". `SettingsView` is internally consistent across five sections and its own doc calls the flat look deliberate. Dropping gold-hairline plaques into two of seven sections produces a screen with two idioms, which is worse than either. A full repaint of Settings is one clean pass later, not a reason to be inconsistent now. |
| **D-28** | Retire `pacing.yml` and its launch-time `fatalError`? | **Yes** — delete the file, the parser (`PacingSettingsStore.swift`), and `SettlersApp.init()`'s forced read (`SettlersApp.swift:6-17`). Replace with two named preference enums. | The strictness rationale (`PacingSettingsStore.swift:56-62`) scopes itself precisely to a developer hand-editing a bundled file, and says so: "cannot be triggered by a player, since the file ships inside the app". With a three-way choice row, that failure mode becomes *unrepresentable*, not merely mitigated. Keeping both sources means a precedence question — and this repo already has evidence that goes wrong unnoticed (see D-30). The `# why` comments in `pacing.yml` are genuinely valuable and must move onto the preset constants, not be deleted with the file. |
| **D-29** | Discrete presets or sliders? | **Three named speed presets (Relaxed/Normal/Brisk) plus a three-option Trade Offer Timer (Off / 15s / 30s).** | Presets make invalid states unrepresentable, which is what lets the parser be deleted rather than reimplemented as clamping. A slider is not screenshot-verifiable ("the thumb is about two-thirds along" is not an assertion); "the Relaxed plaque is lit" is. `secondsPerBotAction` and `rollHighlightSeconds` are correlated and should not be separately settable. And `Slider` is a system control that renders grey-on-grey here. The timer stays separate because it governs whether the app **answers a trade on your behalf** — nobody who wants brisk bots has thereby asked to be auto-declined. |
| **D-30** | ⚔ **The shipped trade-offer timeout contradicts three doc comments.** What is the default? | **Off (0).** And correct the three stale comments in the same change. | Verified live discrepancy: `Settlers/pacing.yml:28` sets `incomingOfferTimeoutSeconds: 15` and the file overrides the Swift default, so the app **today auto-declines an unanswered offer after 15 seconds** — while `PacingSettings.swift:36-38` ("Zero means wait for the human indefinitely, which is the default"), `IncomingTradeCardView.swift:19-20` ("shipping as 0") and `:34-42` ("the timer is off unless someone deliberately turns it on") all say otherwise. Off is the behaviour that cannot silently cost a player a trade, and it is now two taps to turn on. |
| **D-31** | Pacing in Settings or on the new-game screen? | **Settings — global, changeable at any time — and Settings becomes reachable from the pause menu.** | It follows from the per-game rule in §5: pacing changes nothing about legal moves, who is playing, or what winning means. More importantly, the symptom that created it (quoted at `PacingSettings.swift:8-9`: "the computer's making turns so quickly that I don't even see what they're doing") is formed twenty minutes into a game, not on a setup screen. Settings is reachable only from the main menu today (`MainMenuView.swift:75-87`), so fixing pacing mid-game currently costs you the game. |
| **D-32** | `GameLogStore.SeatRoster` — keep `humanSeat` alongside `humanSeats`, or replace it? | **Replace** `humanSeat: PlayerID` with `humanSeats: [Int]` (sorted), bump `currentLogSchemaVersion` (`GameLogStore.swift:87`) 1 → 2. | Verified: `GameLogStore` contains **no `JSONDecoder` at all** — it only writes entries and lists URLs (`logFiles()`, `:118`). No in-app read path breaks. Keeping a non-optional `humanSeat` as a "first human" alias encodes a lie for an all-bot game and a half-truth for a 2-human one. Sorted, not a `Set`, so recorded order is stable across processes. |
| **D-33** | `nextBotPlayer()` — update or delete? | **Delete** (`GameViewModel.swift:780-798`). | Verified: referenced only from its own doc comments at `:558` and `:570`. It is a fifth copy of "which seat is human"; updating it keeps the copy alive. The live loop is `while case .seat = session.nextActor()` (`:661`), which already handles any number of human seats. |
| **D-34** | `-qaFastForwardToRollDice` with more than one human? | **Assert loudly and refuse.** | It drives moves as a single seat via `viewModel.apply` (`GameView.swift:449-479`) and would fast-forward one seat's setup while leaving the others. That file already records what happens when this hook silently does nothing on some iterations. |

---

## 3. Requirements

Every requirement's acceptance criteria are objectively checkable by a `SettlersTests` / SPM test or by a named `-qa` flag + screenshot. Verification is mapped in §7.

### A. Seat composition and hot-seat play

#### SEAT-1 — The app models a set of human seats and a seat at the device
A game is configured with 1–4 human seats on the fixed four-seat table. Every non-human seat is driven by a bot policy exactly as today.

- Given a new game configured with humans in seats 0 and 2, `viewModel.humanSeats == [PlayerID(0), PlayerID(2)]` and `session.policies` has keys exactly `{1, 3}`.
- Given 4 human seats, `session.policies.isEmpty == true` and `session.nextActor() == .awaitingExternalSeat(PlayerID(0))` immediately.
- Given any configuration, the `GameState` written by `GameStore.save` gains **no new key**; `GameState.currentSchemaVersion` is unaffected by this requirement (VPT-1 owns the only bump).
- `grep -rn "in humanSeats" Settlers/` returns no `for` loop over the raw `Set` — every enumeration goes through `sortedHumanSeats`.
- `seatAtDevice` is `PlayerID?`; `apply(_:)` resolves it as `seatAtDevice ?? sortedHumanSeats[0]` and precondition-fails if `humanSeats.isEmpty`.
- With exactly one human seat, reading `seatAtDevice` at any point resolves to that seat whether or not anything set it.

**Touches:** `GameViewModel.swift:28`, `:193`, `:297`, `:630`.

#### SEAT-2 — The 35 `humanPlayer` reads are split into three questions
Invisible to the player, and the whole of the change. Each read is re-pointed at exactly one of `humanSeats.contains(_:)`, `seatAtDevice`, or `sortedHumanSeats`.

- After `humanPlayer` is deleted, the app compiles with every former call site bound to exactly one of the three.
- **Membership → `humanSeats.contains`:** `seatRoster` personality skip (`GameViewModel.swift:265`), `resolveHumanProposedTrade`'s loop (`:405`), the QA bot filter (`:372`), and the incoming-offer proposer filter (`GameView.swift:1055`).
- **Seat at the device → `seatAtDevice`:** `GameView.human` (`GameView.swift:178`) and everything derived from it; `TradePopupView.human` (`TradePopupView.swift:60`), its `TradeOffer(from:)` (`:389`) and `rate(for:)` (`:543`); `DiscardPopupView.human` (`DiscardPopupView.swift:22`); and the seat `apply(_:)` applies as (`GameViewModel.swift:299`).
- `apply(_ move:)` keeps its one-argument signature; calling it while `seatAtDevice ∉ humanSeats` trips an assertion naming the seat rather than applying a move on a bot's behalf.
- `nextBotPlayer()` (`GameViewModel.swift:780-798`) is **deleted**, and the two doc comments at `:558`/`:570` that name it are reworded.

#### SEAT-3 — Hot-seat handoff cover
With more than one human, whenever the game waits on a human seat other than the one at the device, an **opaque full-bleed painted view** covers everything: "Pass the phone to \<Name>" and one gold button "I'm \<Name> — Ready".

- Humans in seats 0 and 1; seat 0 taps End Turn; phase becomes `.rollDice(1)` → the cover is presented and `seatAtDevice` is still seat 0 until Ready is tapped.
- Humans in seats 0 and 3, bots in 1 and 2; seat 0 ends their turn → the board stays visible while 1 and 2 play, and the cover appears only when the loop stops on seat 3.
- While presented, a screenshot shows **no** part of `HumanPlayerPanel`, `BotHUDRow`, the board, or any popup. The view is not a `PopupCard` and has no outside-tap dismissal.
- Tapping Ready sets `seatAtDevice` to the owed seat and dismisses the cover in the same frame; no separate acknowledgement flag exists to clear.
- A 7 is rolled and humans in seats 0 and 2 both owe a discard: when seat 0 finishes, the cover appears for seat 2 **before** `DiscardPopupView` renders seat 2's hand.
- A two-human game force-quit and resumed presents the cover before any hand is drawn (`seatAtDevice == nil`).
- With exactly one human seat, the cover is never presented across a full played game (`needsHandoff` short-circuits on `humanSeats.count > 1`).
- While presented, the pause button and every board tap target are unreachable.
- **On dismissal, `GameView`'s per-seat interaction `@State` is cleared** — armed placement mode, `roadBuildingFirstEdge`, `isRoadBuildingActive`, robber target, `seenTradeOfferIDs` — so seat B cannot inherit seat A's half-finished road-building pair. `ContentView`'s `.id(gameGeneration)` (`ContentView.swift:41`) resets these only on restart.

#### SEAT-4 — Only the seat at the device sees a full hand
A human seat that is not at the device renders exactly like a bot seat does today.

- Humans in 0 and 1, seat 0 at the device → exactly one `HumanPlayerPanel` (seat 0) and three `PlayerChip`s.
- `BotHUDRow`'s filter changes from `$0.id != human` (`PlayerHUDView.swift:24`) to `$0.id != seatAtDevice`, so exactly three chips show at every configuration and the row still fits 375pt.
- A human seat not at the device shows `state.publicVictoryPoints(for:)` (`PlayerHUDView.swift:422`) and the hand-size badge (`:459`) — **never** `state.victoryPoints(for:)` and never per-resource dots, so a held victory-point card of a human opponent is not revealed.
- No `DevCardHUDTile` is rendered for any human seat that is not at the device.
- The `isHuman ? playerLabel : generalName` ternary at `PlayerHUDView.swift:398` is removed — `CatanTheme.playerLabel(for:)` already returns the general name for a non-human seat (`CatanTheme.swift:81`), so the ternary is a second copy of the human/AI decision.
- The trade popup's `handTray` reads `seatAtDevice`'s resources only.
- The stale class doc at `PlayerHUDView.swift:8-12` ("Every player's resource hand is shown in full") is corrected.

#### SEAT-5 — The bot loop runs with 0–3 bots and stops for any human seat
- `makeSession` takes the human-seat set and assigns a `HeuristicPolicy` to every seat **not** in it, iterating `state.players` in seat order (`GameViewModel.swift:630-639`).
- Humans in 1 and 3, loop run from `.setupForward(0)`: seat 0 plays, the loop exits on `.awaitingExternalSeat(1)`, and no move is applied for seat 1.
- 4 human seats: `runBotTurnIfNeeded()` returns without applying a move and **without sleeping** `secondsPerBotAction`.
- Humans in 0 and 2 and bots in 1 and 3 all owe a discard: the two bots discard first (`GameSession.nextActor()` prefers a policy seat, `GameSession.swift:133`) and the loop then stops on the lowest-index pending human seat, chosen from `pending.sorted()`.
- `personalityIndex(for:humanSeat:)` (`GameViewModel.swift:830-834`) takes the human set instead of one seat: with 3 humans the single bot seat gets `botRoster[0]` ("balanced"); with 4 humans it is never called.
- In a 2-human game, each bot seat's personality recorded in the log matches the policy actually installed in `session.policies` (same `botRoster` index).

#### SEAT-6 — A saved game remembers who sat where
- `GameSetupStore.load()` with no new value present but the legacy `humanSeatIndex` integer present returns that one seat as a single-element array — an existing in-progress game must not move its human to seat 0.
- With neither present, it returns `[PlayerID(0)]` plus a fresh civilization draw, matching today's fallback (`GameViewModel.swift:144-146`).
- A 3-human game started → `GameSetupStore.load()` returns those three seats and 4 **distinct** civilizations.
- Relaunching into a saved 2-human game: `humanSeats` matches what was saved and `seatAtDevice == nil`.
- `GameStore.load()` returning `.unreadable` → the replacement game is `[seat 0]`, and **also assigns `CivilizationAssignment.current` from the player's preferences** (this is a live bug today: `GameViewModel.swift:147-157` never assigns it in the `.unreadable`/`.none` branches, leaving the hardcoded `[.medieval, .greece, .egypt, .aztec]` at `Civilization.swift:235`, so a player who chose Rome is put in Britannia).
- The per-game value is cleared in the same place `GameStore.clear()` is called (`EndGameView.swift:67`), closing the `HumanSeatStore` leak.

#### SEAT-7 — A table with no bots does not strand a trade offer
- With `humanSeats.count == 4`, "Propose to Bots" (`TradePopupView.swift:384-388`) is **disabled** and carries a caption naming the reason ("No AI empires at this table") — not a silent grey button.
- With `humanSeats.count == 4`, `openIncomingOffer` (`GameViewModel.swift:769`) is always `nil` and the bot loop is never held.
- A `SettlersTests` case asserts that with no bot seats, `resolveHumanProposedTrade` is unreachable from the UI (the button is disabled), because reaching it leaves the offer in `state.pendingTradeOffers` permanently.
- In a 3-human game, exactly one bot seat exists, is given a policy, and a human proposal produces one real accept/reject decision row.

#### SEAT-8 — Stats, log and end screen stop assuming one human
- A game with `humanSeats.count > 1` ending → `GameStatsStore.recordGameEnd` is **not** called, at either site (`GameViewModel.swift:240` and `:736`).
- A single-human game ending → stats recorded exactly as today, with the clamp from VPT-2.
- `EndGameView` takes the human-seat set instead of `human: PlayerID` (`EndGameView.swift:12`): a human win in a multi-human game reads "\<NAME> WINS" in that seat's colour; "YOU WIN!" (`:91`) is used only when there is exactly one human seat and they won.
- The VP table (`EndGameView.swift:122`) uses `CatanTheme.playerLabel(for:)` for every row and no two rows read "You".
- `GameLogStore.SeatRoster.humanSeat` becomes `humanSeats: [Int]` (sorted); `currentLogSchemaVersion` (`GameLogStore.swift:87`) becomes 2. A v1 log on disk still lists and shares without crashing (`logFiles()` only enumerates URLs; nothing decodes entries).
- In a 2-human game's log, `botPersonalities` has entries for exactly the two bot seats and none for the human seats.

---

### B. Player identity

#### ID-1 — Human seat names, keyed by human slot
- Exactly one human seat with no custom name → every label reads "You", byte-identical to `CatanTheme.swift:83`.
- Two or more human seats, no custom names → "You" and "Player 2"/"Player 3"/"Player 4"; **no two seats ever read "You"**.
- A whitespace-only name is treated as unset (`PlayerNameStore.save` already trims, `:26`).
- Slot 0 uses the existing `playerDisplayName` key, so an existing install's saved name still appears with no migration step.
- Names are capped at 12 characters at input; a 12-character name renders on one line in a `PlayerChip` at 375pt with no ellipsis.
- Two human seats given the same name are accepted and remain distinguishable by colour dot and civilization line.

#### ID-2 — AI seats are named by their general; one label resolver
- An AI seat shows `Civilization.generalName` everywhere and has no editable field anywhere in the app.
- A seat toggled AI → human gains a name field pre-filled "Player N" (not the general name); toggled human → AI loses it and reads the general name in the same render pass, with no stale human name on any surface.
- `grep -rn "generalName" Settlers/Views/` returns hits **only** in the setup/settings picker's own row subtitles — never a seat label.
- All eight display sites agree for a given roster: `HumanPlayerPanel` (`PlayerHUDView.swift:85`), `PlayerChip` (`:398`), the trade popup's pending and resolved rows (`TradePopupView.swift:~499`, `:~532`), `IncomingTradeCardView` (`:126`), the robber victim picker (`GameView.swift:~718`), and `EndGameView`'s headline and VP table.
- Every seat colour comes from `CatanTheme.color(for:)` (`CatanTheme.swift:71`); no view derives one another way.

#### ID-3 — Civilization uniqueness holds for any human count
- Over **all 256 subsets** of `Civilization.allCases` as the included-bot pool (including empty and one containing the human's own civ), and for human counts 1–4, a drawn roster is pairwise distinct — an enumerating test in `SettlersTests`.
- A persisted per-game roster whose civilizations are not pairwise distinct is rejected and redrawn, without crashing (`CivilizationAssignmentStore.load()` today validates only `count == 4`, `:32`).
- `drawAssignment` (`GameViewModel.swift:280-288`) is rewritten to fill `4 − humanSeats.count` AI seats plus `humanSeats.count − 1` extra human seats from the pool; human slot 0 gets `settings.yourCivilization`; nothing is inserted twice.
- The draw uses the **system** RNG, never `state.rng` — asserted by `SeededGameFingerprintTests` staying green in a fresh process.
- Enumeration of the pool is `.sorted()` before `.shuffled()`, so the draw does not depend on `Set` hash order (`GameViewModel.swift:285` currently calls `Array(botPool).shuffled()` directly on a `Set`).
- `Civilization.allCases.count >= 4` is asserted rather than assumed (there are 8, `Civilization.swift:28-35`).

#### ID-4 — Flavour text is gated on control, not civilization
- A trade offer proposed by a **human** seat renders in `IncomingTradeCardView` with **no** `TradeMessages.pitch` line — name and give/get summary only. Today `IncomingTradeCardView.swift:126-129` calls `pitch` unconditionally and is unreachable for a human proposer only because of the `$0.from != humanPlayer` filter at `GameViewModel.swift:771`, which stops being sufficient with two humans.
- `tradeResponseMessage` (`GameViewModel.swift:389-392`) is reached only for AI seats.
- The same offer id rendered twice returns the same line (unchanged determinism of `TradeMessages`).

#### ID-5 — `tradeMessagesEmpire` cannot crash on a new civilization
- `Civilization.tradeMessagesEmpire` (`Civilization.swift:48-50`) replaces `TradeMessages.Empire(rawValue: rawValue)!` with an exhaustive `switch self`, so a ninth civilization without a matching `Empire` case is a **compile** error rather than a runtime crash on the first trade offer.
- A `SettlersTests` case asserts every `Civilization.allCases` maps to an `Empire` (this is the test the module boundary previously made impossible: `TradeMessagesTests` cannot import `Civilization`).

---

### C. Victory target — the only engine change

#### VPT-1 — `GameState.victoryPointTarget` ⚠ **CODABLE CHANGE**
- `GameSetup.newGame(board:)` with no target argument → a player reaching 10 VP ends the game, identical to today. All three overloads (`Models/GameState.swift:175`, `:186`, `:195`) default to `WinCondition.standardTarget`.
- Created with `victoryPointTarget: 8` → the game ends the move a player reaches exactly 8; at 7 VP `state.phase` is unchanged.
- A `GameState` JSON payload with the `victoryPointTarget` key removed decodes successfully with `state.victoryPointTarget == 10` — a new key in `SaveCompatibilityTests`'s `laterAdditions` array (`SaveCompatibilityTests.swift:33-34`).
- `GameState.currentSchemaVersion == 2` (`Models/GameState.swift:6`), and `aFreshGameCarriesTheCurrentSchemaVersion` still passes.
- All five pinned fingerprints in `SeededGameFingerprintTests` are **byte-identical** in a fresh process, with no re-recording.
- `WinCondition.checkForWinner` (`WinCondition.swift:19`) contains no integer literal; `WinCondition.standardTarget = 10` is the single named default.
- `GameSetup.newGame` `precondition`s the target into `6...13` with an explaining message.

#### VPT-2 — Correct the two app-layer clamps that assume 10
- A won 8-point game finishing on 9 VP (a knight can take Largest Army and jump the threshold) records `finalVP == 8` — clamped to `state.victoryPointTarget`, not the literal 10.
- A won 12-point game finishing on 12 records `finalVP == 12`.
- **Both** sites — `applyLogged` (`GameViewModel.swift:247`) and `recordAppliedMove` (`:738`) — are changed identically; neither contains the literal 10 afterwards.
- **No property is added to `GameStats`.** `GameStats` uses synthesized `Codable` (`GameStatsStore.swift:6-19`) and `load()` swallows a decode failure with `?? GameStats()` (`:47`), so one added property would silently zero every player's lifetime record. Averages now mix game lengths; a comment at both sites says so.

#### VPT-3 — The target is visible while playing
- Target 8, human on 5 VP → the human's VP pill reads `5 / 8`.
- A bot/other-seat row shows that seat's **public** VP over the target (`state.publicVictoryPoints(for:)`, `PlayerHUDView.swift:422`), never `victoryPoints(for:)`.
- The value comes from `state.victoryPointTarget`; no view recomputes or re-declares it (§1 of the review standard).
- A two-digit target does not clip the pill at 375pt.
- `EndGameView` names the length that was played.

#### VPT-4 — Tests and the sim harness stop hard-coding 10
- `FullBotGameSimulationTests.swift:62`, `:66` and `:149` assert against `state.victoryPointTarget`.
- `GameSessionTests.swift:88` asserts against the session's own target.
- New `WinConditionTests` cases: a target-8 game driven to 8 VP fires `.gameOver`; a target-12 game at 10 VP does not.
- The `sim` executable accepts an optional target and records it in each JSON Lines row; omitting the flag reproduces today's output byte-for-byte including the fingerprint.
- A finished game's log `start` line decodes with the game's target — free from VPT-1, since the whole `GameState` is already serialised (`GameLogStore.swift:~103`). No `Entry` shape change; this alone does not bump the log schema (SEAT-8 does).

---

### D. The new-game screen

#### NG-1 — The title screen becomes the new-game screen
Top to bottom: compact top bar (small EMPIRES wordmark left, Settings pill right) · Resume row when a save exists · "The Table" with four seat rows · a collapsed "Match Options" disclosure with a one-line summary · a pinned Start Game bar.

- Fresh install, no save: top bar, four seat rows, collapsed Match Options, Start Game; **no** Resume row.
- On a 375×667 device with Match Options collapsed, Start Game is fully inside the safe area **without scrolling** — asserted by a pure layout-height function in `SettlersTests` and confirmed by a 375pt screenshot.
- With Match Options expanded, the middle section scrolls and the Start bar stays pinned and fully visible.
- Tapping Start Game immediately after a fresh launch produces exactly today's defaults: randomized board on, seat randomisation on, saved `yourCivilization`, three bot seats drawn from `includedBotCivilizations`, first to 10.
- Start Game is reachable in **one tap** from launch — no intermediate screen, no required disclosure.
- The lifetime stats tiles no longer appear here (`MainMenuView.swift:133`, `:149-160`); they appear in `SettingsView`.

#### NG-2 — `SeatRow`
One 60pt painted plaque per seat, 8pt gaps: 24pt gold seat pip (number, or shuffle glyph while randomisation is on) · 36pt `CivilizationBadge` (or a gold "?" for Random) · flexible identity column (bold title, caption subtitle) · 44pt two-state human/AI role control. Plaque border is that civilization's `accentColor` via `playerCardBorder`.

- AI seat with a chosen civilization: title is `generalName`, subtitle "Bot · \<displayName>".
- AI seat set to Random: gold "?" badge, "Random Empire", "Bot · drawn at start", gold border.
- Human seat: title is that slot's name (or "You"/"Player N" per ID-1), subtitle "\<slot label> · \<displayName>".
- A Britannia seat's plaque border equals `Civilization.medieval.accentColor` — the same value `CatanTheme.color(for:)` hands the board.
- At 375pt with 20pt page padding, no title or subtitle truncates or wraps for the longest label ("Charlemagne" / "Bot · Britannia").
- The role control is ≥44×44pt and is a painted two-state pill, not a `Picker`.
- Tapping a role control turns "Randomize Seats" off (D-23) and the Match Options summary updates in the same pass.
- Role state is a **per-row property** passed into `SeatRow`, never read from `CivilizationAssignment.humanSeat` inside the row.
- Tapping the human seat's title opens an inline `TextField` bound to `PlayerNameStore`, saved on every keystroke. Editing it here and then opening Settings shows the same value — one stored value, two editors; `SettingsView` is a `.sheet` over this screen, so on dismissal the row re-reads the store rather than trusting its own `@State`.

#### NG-3 — Civilization picker (painted popup, swap on collision)
A `PopupCard` titled "Seat N" holding a 3-column grid of nine tiles (eight civilizations plus "Random"), each a 44pt `CivilizationBadge` over its name.

- Seat 1 is Britannia, seat 3 is Greece; open seat 1's picker and tap Greece → seat 1 becomes Greece **and seat 3 becomes Britannia**; no other seat changes.
- Seat 1 is Random, seat 3 is Greece; tap Greece from seat 1 → seat 1 is Greece, seat 3 is Random.
- Property test: over a sequence of random picks, at most one seat ever holds any given specific civilization. "Random" is never "taken".
- A dimmed tile shows the owning seat's number in that seat's `accentColor`.
- All nine tiles fit inside `PopupCard` (32pt inset per side) at 375pt with no horizontal scrolling and no clipped label.
- Tapping the scrim closes the picker leaving the seat unchanged.
- A **human** seat's picker does not offer "Random" — you always know which empire you are playing.

#### NG-4 — Match Options
One painted row reading "Match Options" with a summary caption and a chevron; expands in place to a victory-target choice (three tiles: 8 "Short" / 10 "Standard" / 12 "Long") plus painted check rows for "Randomized Board" and "Randomize Seats".

- Fresh install: collapsed, caption reads "First to 10 · Random board · Random seats".
- Selecting "12" → caption reads "First to 12 · …", and the choice persists across relaunch via `@AppStorage("victoryPointTargetSetting")`.
- Unchecking "Randomized Board" → caption reads "… · Standard board · …" and `startNewGame` receives `randomizedBoard: false`.
- Target 10 (the default) → the started game's `GameState.victoryPointTarget == 10` and its save decodes identically to one written before this feature (covered by VPT-1's `SaveCompatibilityTests` case).
- No control in the expanded block is a system `Picker`, `Stepper`, `Slider`, `Toggle`, `Form` or `List`.
- Restart from the pause menu (`GameView.swift:316-320`) reuses **all** the current menu choices — board, seat randomisation, human count, victory target — rather than reverting to defaults. This is the exact failure `randomizedBoardSetting`/`randomizeSeatSetting` (`GameView.swift:117-118`) were added to fix.

#### NG-5 — Resume coexists with Start; Start no longer destroys a save silently
- `GameStore.shared.hasSave()` true → a "Resume Game" row above "The Table", subtitled "Continues your saved game. The table below is for a new one."
- `hasSave()` false → no Resume row, and Start Game starts immediately with no confirmation.
- Save exists + Start Game tapped → a `PopupCard` confirmation appears and `startNewGame` has **not** been called.
- Cancel or scrim → card dismisses, save file unchanged on disk, screen unchanged.
- "Start New Game" → `startNewGame` runs and the app enters `GameView`.
- The confirmation reuses `PauseMenuView.confirmation`'s layout (stacked `GoldRowButton`s, 280pt max width, red destructive title, `PauseMenuView.swift:82-101`), **extracted into a shared component** rather than copied.
- Deciding whether to show Resume costs one `FileManager.fileExists` and never a `JSONDecoder` pass.

#### NG-6 — Painted chrome; system controls banned on this screen
- Every new interactive surface on the new-game screen uses `PaintedChromeBackground` with `FrameCornerRect` notched corners.
- `grep -rn "Picker(\|pickerStyle\|Menu {\|Form {\|List {\|Stepper(\|Slider(\|Toggle(" ` over the new-game-screen files returns nothing. The two existing `Toggle`s (`MainMenuView.swift:102`, `:109`) are gone.
- Both overlays this screen introduces (civ picker, start confirmation) are `PopupCard` in the same `ZStack` — not `.sheet`, not `.confirmationDialog`.
- The wordmark uses the same serif face and tracking as today's `titleBlock` (`MainMenuView.swift:193-195`) at reduced size; the Settings pill keeps its current treatment (`:86`).
- New view files are split out (`SeatRow.swift`, `CivilizationPickerView.swift`, `MatchOptionsView.swift`) — SwiftLint's `type_body_length` errors at 900 lines under `--strict`.

#### NG-7 — Lifetime stats move to Settings
- `SettingsView` gains a stats section adjacent to Reset Stats, showing Played / Win Rate / Avg Time / Avg VP, hidden when `gamesPlayed == 0` (matching today's condition at `MainMenuView.swift:151`).

---

### E. Pacing and the settings model

#### PACE-1 — Two named preferences replace three free numbers
- Fresh install: `PacingPreferences.default.resolved == PacingSettings(secondsPerBotAction: 1.1, rollHighlightSeconds: 1.5, incomingOfferTimeoutSeconds: 0)` — the speed half byte-identical to today's shipped `pacing.yml:17,20`, the timer half being the 0/never that three doc comments already claim (D-30).
- `GameSpeed` `.relaxed`/`.normal`/`.brisk` → `secondsPerBotAction` 1.6 / 1.1 / 0.6 and `rollHighlightSeconds` 2.2 / 1.5 / 1.0; every value inside the ranges the retired parser enforced (`PacingSettingsStore.swift:129-134`).
- Over `GameSpeed.allCases`, `resolved.secondsPerBotAction > 0` — a case added later cannot reintroduce the free-spinning bot loop.
- Both enums use `String` raw values. A stored blob missing a field takes its default; an unrecognised raw value falls back for **that field only**, not the whole preference set. Every field is read with `decodeIfPresent` and a `??`.

#### PACE-2 — Retire `pacing.yml` and the trapping loader
- `Settlers/pacing.yml` and `Settlers/Persistence/PacingSettingsStore.swift` do not exist; `xcodegen generate` has been re-run (`project.yml:18` globs `Settlers/`).
- `SettlersApp.init()` (`SettlersApp.swift:6-17`) is removed entirely; no code path in the app can `fatalError` over configuration.
- `SettlersTests/PacingSettingsTests.swift`'s parser tests are replaced by tests over `PacingPreferences` (defaults are sane, store round-trip, tolerant decode). **Net test count must not fall.**
- `grep -rn "PacingSettingsStore\|pacing.yml" Settlers/ SettlersTests/` returns nothing.
- The `# why` comments from `pacing.yml` (notably the 25-actions-per-turn arithmetic at `:14-16`) move onto the preset constants.

#### PACE-3 — Pacing is read live
- No pacing value is stored in a `static let`. Each of the three call sites (`GameViewModel.swift:683`, `GameView.swift:1135`, `IncomingTradeCardView.swift:43`) reads the current preference at the moment it needs it, from an `@Observable` singleton persisting on change.
- Changing Game Speed mid-game → the **next** `Task.sleep` in `runBotTurnIfNeeded` uses the new value. Asserted by a test that flips the preference and reads the value the loop would use.
- `IncomingTradeCardView.totalSeconds` becomes `@State` captured once in `startTicking` (`:232-252`) rather than a computed property, so a running countdown's denominator cannot jump mid-tick.
- `highlightProducingTiles` reads the value once at the top, not after the sleep.
- A change made during a sleep does not shorten the sleep already running. This is accepted and documented, not fixed.

#### PACE-4 — Settings is reachable from the pause menu, and says what applies when
- A "Settings" row sits between "Resume" and "Restart Game" in `PauseMenuView.menu` (`PauseMenuView.swift:50-64`), styled as a **non-destructive** `GoldRowButton` (white icon and title), presenting `SettingsView` as a sheet over `GameView`.
- Dismissing it returns to the still-open pause menu with game state untouched.
- The Pacing section carries a caption: applies immediately, including to a game in progress.
- "Your Civilization" and "Bot Roster" each carry a caption: applies to the next new game — the behaviour `SettingsView.swift:4-9` documents but has never shown the player.
- At 375pt, no label truncates and the page does not scroll horizontally.

#### PACE-5 — One shared themed choice row
- A new `SettingsChoiceRow` built from the same materials as `SettingsView.civilizationRow` (`SettingsView.swift:266-298`) — `RoundedRectangle(cornerRadius: 10)` on `Color(white: 0.14)`, `.subheadline.bold()` label, `.caption` subtitle at `.white.opacity(0.6)`, accent on selection.
- Each plaque is ≥44pt tall and ~104pt wide at 375pt ((375 − 48 content width − 16 spacing) / 3).
- Which option is selected is unambiguous from a screenshot alone — accent fill or border **plus** a checkmark, not a subtle tint.
- `grep -rn "Picker(\|Slider(" Settlers/` returns nothing app-wide.

#### PACE-6 — The fair-accept hold scales with Game Speed
- `waitForFairAcceptWindow` (`GameViewModel.swift:753-761`) derives its range from the current `secondsPerBotAction` rather than the literal `2...4`: `2s'…4s'` where `s' = secondsPerBotAction / 1.1`. Relaxed 2.9–5.8s, Normal **exactly 2–4s**, Brisk 1.1–2.2s.
- `SettlersTests/IncomingOfferHoldTests.swift` stays green with no edits.
- No engine or AI file is touched; the `Double.random` stays in the app layer where an unseeded generator is already used.
- No new player-facing control is added for this.

---

### F. Verification hooks

#### QA-1 — New `-qa` flags
Six new cases on `QALaunchFlag` (`QALaunchFlag.swift:26-56`), each `#if DEBUG` at the declaration **and at every call site**, each documented in `.claude/skills/run-settlers/SKILL.md`'s table.

| Flag | Puts the app in |
|---|---|
| `-qaTwoHumans` | With `-qaAutoStart`, a game with humans in seats 0 and 1, bots in 2 and 3 |
| `-qaShowHandoff` | The handoff cover, presented for the second human seat |
| `-qaSeatSetupFixture` | The new-game screen with a fixed lineup (human "Alex" seat 2 / Britannia; Alexander/Greece, Augustus/Rome, Ragnar/Norse) so screenshots are byte-stable |
| `-qaShowCivPicker` | Seat 1's civilization picker open, with at least one civ shown as taken |
| `-qaExpandMatchOptions` | Match Options expanded (the tallest layout state) |
| `-qaShowNewGameConfirm` | The "Start a new game?" confirmation card |

- `-qaFastForwardToRollDice` combined with a multi-human configuration trips an assertion rather than fast-forwarding one seat (D-34).
- The app compiles with `-configuration Release` (`gate.sh` builds Release on every run).

#### QA-2 — Single-human parity is pinned by test, not by inspection
- A `SettlersTests` case plays a scripted single-human game through `GameViewModel`; `needsHandoff` stays `false` for the whole game.
- `SeededGameFingerprintTests` in a fresh process: all five sequences unchanged, none re-recorded.
- `scripts/gate.sh` green: coverage at or above the 95/90 floors, Release compiles.
- `IncomingOfferHoldTests`'s four calls to `replaceStateForTesting(_:humanSeat:)` (`:32`, `:71`, `:79`) keep passing via a single-seat overload — their intent is not rewritten.

#### QA-3 — Layout fit is a test, not a screenshot
- A pure function returning the new-game screen's required content height for a given width, asserted ≤ the safe-area height at **375×667** with Match Options collapsed, across the same spread of candidate frames `SettlersTests/BoardFitTests.swift` already uses.

---

## 4. The hot-seat hand-hiding decision

**This is the largest product question in the stage.** Everything else is layout and persistence.

**The question.** Four people share one 375pt phone. In real Catan a hand is hidden information. What, concretely, hides it?

**The answer, in four parts:**

1. **A non-device human seat is rendered exactly as a bot seat is rendered today.** This is nearly free, and cheaper than any prior analysis assumed, because `PlayerChip` already hides everything that matters: it shows `state.publicVictoryPoints(for:)` (`PlayerHUDView.swift:422`), a hand-*size* badge (`:459`), a dev-card *count*, roads and played knights — all genuinely public in Catan — and **never** the per-resource breakdown. The work is one filter (`$0.id != human` → `$0.id != seatAtDevice`, `PlayerHUDView.swift:24`), removing one ternary (`:398`), and correcting a stale class doc (`:8-12`) that says the opposite of what the code does.

2. **A full-screen opaque cover at every human→human turn boundary, driven by derived state.** `needsHandoff = humanSeats.count > 1 && owedHumanSeat != nil && owedHumanSeat != seatAtDevice`. It is **not** a `PopupCard` — `PopupCard`'s 45% scrim (`DevCardPopupView.swift:172`) leaves `HumanPlayerPanel`'s resource dots legible, and its tap-outside dismissal would hand the phone to nobody while revealing the previous player's hand. It is an opaque `PaintedChromeBackground` view with exactly one gold button. Derived rather than event-fired because an event needs a firing site at every transition that can hand control to a person — end turn, a discard resolving, the bot loop finishing, a resumed save, a restart — and the bug is always the site nobody remembered. It also gets the relaunch case free: `seatAtDevice` starts `nil`, which equals no seat, so a force-quit hot-seat game is covered before any hand is drawn.

3. **`GameView`'s per-seat interaction state is cleared on handoff.** Sixteen pieces of `@State` — armed placement mode, `roadBuildingFirstEdge`, robber target, `seenTradeOfferIDs` — belong to the seat that armed them. `ContentView`'s `.id(viewModel.gameGeneration)` (`ContentView.swift:41`) resets them on restart only. Without this, seat B inherits seat A's half-finished road-building pair — the same shape as the bug that comment records fixing.

4. **Human-to-human trading is closed, not hidden.** A proposal is answered by bot seats only (D-11), and with four humans the "Propose to Bots" button is disabled with a stated reason — because reaching `resolveHumanProposedTrade` with no bot seats leaves the offer in `state.pendingTradeOffers` permanently, with no actor able to withdraw it.

**The limitation, stated up front so it is not later reported as a defect.** The cover is software; the peek is human. Someone who taps "Ready" without actually passing the phone sees the next player's hand, and there is nothing the app can do about that. The cover is also **not** re-armed on return from the background (D-6): the person who backgrounded the app is the person already holding it, and the genuine "someone else picked up the phone" boundary is the device lock screen, which is not this app's to enforce.

**And the failure mode with no error message:** a hidden-information leak is silent. Every one of the ~15 `seatAtDevice` call sites in SEAT-2 that should have been `humanSeats.contains` renders one person's hand to another; nothing crashes, nothing logs, and no test fails unless one is written. SEAT-4's criteria are that test.

---

## 5. Per-game vs global settings

**The rule, to be written into the `GameSetup` type's doc comment:** a setting is **PER-GAME** if changing it mid-game would change what a legal move is, who is playing, or what winning means. Everything else is **GLOBAL**. Equivalently: per-game settings are part of the match contract (a save and a replayed log must reproduce them); global settings are how this device presents a match to this player.

**Corollary for reviewers:** Settings contains no per-game control, and the new-game screen contains no global preference. A per-game control in Settings is a bug — it either does nothing until next game (confusing) or changes a running game (unsafe).

| Setting | Kind | Shown where | Saved game must remember | Storage |
|---|---|---|---|---|
| Human seats (which seats, how many) | **PER-GAME** | New-game screen, seat rows | **Yes** | `GameSetupStore` (app layer). Never `GameState` — D-7 |
| Seat → civilization assignment | **PER-GAME** | New-game screen, seat rows + civ picker | **Yes** | `GameSetupStore`; legacy fallback to `CivilizationAssignmentStore` |
| Victory target (3p: 8/10/12; 4p: 8/10) | **PER-GAME** | New-game screen, Match Options | **Yes** | `GameState.victoryPointTarget` — the only engine field. Existing 4p/12 checkpoints remain loadable. Menu default in `@AppStorage("victoryPointTargetSetting")` |
| Randomized board | **PER-GAME** | New-game screen, Match Options | No (an input to board generation; the board itself is saved) | `@AppStorage("randomizedBoardSetting")` |
| Randomize seats | **PER-GAME** | New-game screen, Match Options | No (an input to the seat draw; the result is saved) | `@AppStorage("randomizeSeatSetting")` |
| Bot personality mix | **PER-GAME**, derived | Not shown | Yes, implicitly — derived from `humanSeats` (`personalityIndex`), which is saved | none of its own |
| Your name / human slot names | **GLOBAL**, applies immediately | Settings, and inline on the human seat row | No — it is presentation, resolved through `CatanTheme.playerLabel(for:)` | `PlayerNameStore`, keyed by human slot (D-13) |
| Your civilization | **GLOBAL** preference; the *assignment* is per-game | Settings ("Your Civilization") | No (the assignment is) | `CivilizationSettingsStore` |
| Bot roster (the "Random" pool) | **GLOBAL** | Settings ("Bot Roster") | No | `CivilizationSettingsStore` |
| Game Speed (Relaxed/Normal/Brisk) | **GLOBAL**, applies immediately incl. mid-game | Settings ("Pacing"), reachable from the pause menu | No — `GameSession` has no notion of elapsed time and the log records no timestamps, so two replays are identical at any speed | `PacingPreferences` (`@Observable` singleton, UserDefaults-backed) |
| Trade Offer Timer (Off/15s/30s) | **GLOBAL**, applies to the next offer card | Settings ("Pacing") | No | `PacingPreferences` |
| Lifetime stats | **GLOBAL**, read-only + reset | Settings | n/a | `GameStatsStore` — **no new properties** (VPT-2) |

---

## 6. Implementation order

Each step is independently buildable, independently verifiable, and independently PR-able. Cheapest and safest first.

**Step 0 — Correct `CLAUDE.md`.**
Its "The gate" / "Anti-false-green" sections state `test: targets: []` and "xcodebuild test -scheme Settlers runs NOTHING". Both are now false (`project.yml:76-104`, `scripts/gate.sh:164`). Anyone implementing this stage will otherwise conclude the acceptance criteria cannot be automated. *Verified by:* reading the corrected file against `project.yml`.

**Step 1 — Dead-code removal and the stale-doc pass.** *(no behaviour change)*
Delete `nextBotPlayer()` (`GameViewModel.swift:780-798`, D-33) and reword the two comments naming it. Correct `PlayerHUDView.swift:8-12`. Make `Civilization.tradeMessagesEmpire` an exhaustive `switch` (ID-5).
*Verified by:* `gate.sh` green + a new `SettlersTests` case mapping every `Civilization` to an `Empire`.

**Step 2 — ⚠ `victoryPointTarget` on `GameState` (VPT-1, VPT-4). CODABLE CHANGE.**
Add the field, `decodeIfPresent ?? WinCondition.standardTarget` in the hand-written `init(from:)` (`Models/GameState.swift:111-136`), `currentSchemaVersion` 1 → 2, `precondition(6...13)` in `GameSetup.newGame`, remove the literal from `WinCondition.swift:19`, de-literal the four test assertions and the sim harness.
*Verified by:* a new `laterAdditions` entry in `SaveCompatibilityTests` **seen to fail** with `decode` in place of `decodeIfPresent`; new `WinConditionTests` cases at targets 8 and 12; `SeededGameFingerprintTests` in a **fresh process** with all five unchanged; `swift test --package-path Packages/CatanEngine` and `--package-path Packages/CatanAI`.

**Step 3 — VP clamps and the target in the HUD (VPT-2, VPT-3).**
Both `min(…, 10)` sites, the VP pill, the end-game standings. No `GameStats` property.
*Verified by:* `SettlersTests` covering both recording paths at targets 8 and 12; screenshot via `-qaAutoStart -qaFastForwardToRollDice` reading `n / 10`.

**Step 4 — `GameSetupStore`: consolidate per-game state (SEAT-6, D-8).** *(still single-human)*
One `Codable` value; legacy fallback to `HumanSeatStore`'s integer and `CivilizationAssignmentStore`'s file; cleared where `GameStore.clear()` is called (`EndGameView.swift:67`). Fix the `.unreadable`/`.none` branches to assign `CivilizationAssignment.current` from preferences (`GameViewModel.swift:147-157` — a live bug).
*Verified by:* `SettlersTests` legacy-format round-trip using `StoreFile.preserving` (`PersistenceTests.swift:25-46`) against a real pre-change save value; a case asserting the unreadable-save path lands in the player's chosen civilization.

**Step 5 — Identity: names by slot, one label resolver (ID-1, ID-2, ID-4).** *(still single-human)*
`CatanTheme.playerLabel(for:)` takes the human-seat set; remove `PlayerHUDView.swift:398`'s ternary; gate `TradeMessages` on control.
*Verified by:* `SettlersTests` over the label rules (one human/no name → "You"; two humans → no "You" collision; whitespace → fallback); screenshot at 375pt confirming no chip truncation with a 12-character name.

**Step 6 — Civilization draw for any human count (ID-3).** *(still single-human by configuration)*
Rewrite `drawAssignment` (`GameViewModel.swift:280-288`): `.sorted()` before `.shuffled()`, system RNG, distinctness as a construction invariant, redraw on a non-distinct persisted roster.
*Verified by:* an enumerating `SettlersTests` case over all 256 pool subsets × human counts 1–4; `SeededGameFingerprintTests` fresh-process green (proving no `state.rng` was touched).

**Step 7 — Split `humanPlayer` (SEAT-1, SEAT-2, SEAT-5).** *(the load-bearing refactor; still one human at runtime)*
`humanSeats` + `sortedHumanSeats` + `seatAtDevice`; re-point all 35 reads; `makeSession`, `personalityIndex`, `seatRoster` take the set; `replaceStateForTesting` gains a set overload keeping the single-seat one.
*Verified by:* `IncomingOfferHoldTests` green **unedited**; a new scripted single-human game test through `GameViewModel`; `gate.sh` green including Release.

**Step 8 — Hand hiding and the handoff cover (SEAT-3, SEAT-4).**
`BotHUDRow` filter, `HumanPlayerPanel` gating, `needsHandoff`, the opaque cover, `GameView` `@State` clearing on dismissal.
*Verified by:* `-qaTwoHumans -qaAutoStart -qaShowHandoff` screenshot at 375pt (cover fully opaque, name and Ready visible, no board); `-qaTwoHumans -qaAutoStart` screenshot (one `HumanPlayerPanel`, three chips); `SettlersTests` asserting `needsHandoff` is `false` for a whole single-human game and `true` at every human→human boundary in a two-human one.

**Step 9 — Trade dead-end and end-of-game (SEAT-7, SEAT-8).**
Disable Propose with a reason at 4 humans; skip `recordGameEnd` when `humanSeats.count > 1`; `EndGameView` takes the set; `SeatRoster.humanSeats` + `currentLogSchemaVersion` → 2.
*Verified by:* `SettlersTests` on the stats-skip and the log roster shape; `-qaAutoStart -qaShowEndGame` screenshot for the single-human "YOU WIN!" path unchanged.

**Step 10 — The new-game screen (NG-1…NG-7, QA-1, QA-3).** *(largest UI step; split across ≥3 files)*
`SeatRow`, the civ picker, Match Options, Resume + confirmation, painted check rows, stats moved to Settings, `ContentView.onStart` signature change (keeping the bot-loop kick at `ContentView.swift:53`, without which a game whose seat 0 is a bot sits frozen).
*Verified by:* the `SettlersTests` layout-height assertion at 375×667; screenshots via `-qaSeatSetupFixture`, `-qaShowCivPicker`, `-qaExpandMatchOptions`, `-qaShowNewGameConfirm`, `-qaPretendSaveExists`; a `SettlersTests` property test that no picker sequence produces a duplicate civilization.

**Step 11 — Pacing (PACE-1…PACE-6).** *(fully separable; ship last or as its own PR)*
`PacingPreferences`, delete `pacing.yml` + `PacingSettingsStore` + `SettlersApp.init`, live reads, Settings section, pause-menu entry, `SettingsChoiceRow`, scaled fair-accept window. **Run `xcodegen generate` after deleting the two files.**
*Verified by:* replacement `SettlersTests` (net test count not reduced); `IncomingOfferHoldTests` green unedited; `-qaShowSettings` screenshot of the Pacing section; `-qaShowPauseMenu` screenshot showing the Settings row.

**Only Step 2 touches `GameState`'s `Codable`.** It is the only step requiring a `schemaVersion` bump and a `SaveCompatibilityTests` case, and that test must be **seen to fail** before it is trusted.

---

## 7. Verification matrix

| Req | Proven by |
|---|---|
| SEAT-1 | `SettlersTests`: policy-key assertions for {0,2} and 4-human; `grep` for unsorted `humanSeats` enumeration |
| SEAT-2 | Compilation after `humanPlayer` is deleted; `IncomingOfferHoldTests` unedited; `SettlersTests` assertion trip on `seatAtDevice ∉ humanSeats` |
| SEAT-3 | `-qaTwoHumans -qaAutoStart -qaShowHandoff` screenshot @375pt; `SettlersTests` on `needsHandoff` at every boundary; **the `GameView` `@State`-clearing criterion is only partly testable** — the state is `@State` inside a SwiftUI view, so it is verified by code inspection plus a screenshot showing a fresh action row after handoff, not by an automated assertion |
| SEAT-4 | `-qaTwoHumans -qaAutoStart` screenshot (one panel, three chips); `SettlersTests` asserting a non-device human's chip data source is `publicVictoryPoints` |
| SEAT-5 | `SettlersTests`: loop-stop assertions for humans {1,3}, 4-human no-sleep, discard ordering from `pending.sorted()` |
| SEAT-6 | `SettlersTests` legacy-format round-trip under `StoreFile.preserving`; unreadable-save civilization case |
| SEAT-7 | `SettlersTests` on the 4-human disabled state and `openIncomingOffer == nil`; `-qaShowTradePopup` screenshot of the disabled button + caption |
| SEAT-8 | `SettlersTests` on stats-skip and `SeatRoster` shape/schema version; `-qaAutoStart -qaShowEndGame` screenshot |
| ID-1 | `SettlersTests` label rules; 375pt screenshot with a 12-char name |
| ID-2 | `grep` for `generalName` in `Settlers/Views/`; screenshots of all eight display sites |
| ID-3 | 256-subset × 4-count enumerating test; `SeededGameFingerprintTests` fresh process |
| ID-4 | `SettlersTests` asserting no pitch line for a human proposer |
| ID-5 | Compile-time exhaustive `switch` + `SettlersTests` mapping every civilization |
| VPT-1 | `SaveCompatibilityTests` new case (seen to fail); new `WinConditionTests`; `SeededGameFingerprintTests` fresh process |
| VPT-2 | `SettlersTests` on both recording paths at 8 and 12 |
| VPT-3 | Screenshot via `-qaAutoStart -qaFastForwardToRollDice` |
| VPT-4 | `swift test` on both packages; `sim` run with and without the flag, fingerprints compared |
| NG-1 | `SettlersTests` layout-height assertion @375×667; `-qaSeatSetupFixture` screenshot |
| NG-2 | `-qaSeatSetupFixture` screenshot @375pt; `SettlersTests` on the role-control → randomisation-off coupling |
| NG-3 | `SettlersTests` swap property test; `-qaShowCivPicker` screenshot |
| NG-4 | `SettlersTests` on target persistence + Restart reuse; `-qaExpandMatchOptions` screenshot |
| NG-5 | `SettlersTests` asserting `startNewGame` is not called until confirm, and the save file is byte-identical after Cancel; `-qaShowNewGameConfirm` + `-qaPretendSaveExists` screenshots |
| NG-6 | `grep` for banned control names over the new files; screenshots |
| NG-7 | `-qaShowSettings` screenshot |
| PACE-1 | `SettlersTests` on defaults, presets, `> 0` over `allCases`, tolerant decode |
| PACE-2 | `grep` returning nothing; `xcodegen generate` + build; test-count comparison |
| PACE-3 | `SettlersTests` flipping the preference and reading the loop's value. **The "next sleep uses 1.6s" wall-clock claim is not automatable** — it is confirmed by a stopwatch over two screenshots of consecutive bot actions, and stated as such |
| PACE-4 | `-qaShowSettings` and `-qaShowPauseMenu` screenshots @375pt |
| PACE-5 | `grep` for `Picker(`/`Slider(`; screenshot showing an unambiguous selected plaque |
| PACE-6 | `IncomingOfferHoldTests` green unedited; `SettlersTests` on the derived range at all three speeds |
| QA-1 | Each flag launched and screenshotted; `gate.sh` Release compile |
| QA-2 | Scripted single-human `SettlersTests` case; `SeededGameFingerprintTests` fresh process; `gate.sh` |
| QA-3 | The layout-height test itself |

**Not automatable, stated rather than dropped:** (a) the `GameView` `@State`-clearing half of SEAT-3; (b) the wall-clock half of PACE-3; (c) every "looks right in the painted idiom" criterion, which is a screenshot someone actually opened with `Read` — a green gate has never built the Debug binary the `-qa` flags live in (`gate.sh` compiles Release; `--debug-app` is opt-in).

---

## 8. Risks, ordered by cost if they bite

1. **`GameState`'s new field, decoded with `decode` instead of `decodeIfPresent`.** Every existing save becomes undecodable, `GameStore.load()` returns `.unreadable`, and the player's game is gone — the alert at `ContentView.swift:72` only tells them so. This has already happened once in the field (`tradesAcceptedThisTurn`). The `SaveCompatibilityTests` case in VPT-1 is the only guard, and it must be **seen to fail** before it is trusted. Only Step 2 is exposed.

2. **Adding any property to `GameStats`.** It uses synthesized `Codable` with property defaults, and Swift's synthesized `init(from:)` does not fall back to those defaults for an absent key — `GameStatsStore.load()` then hits its `?? GameStats()` (`:47`) and silently zeroes every player's lifetime record, unrecoverably. This is the identical mechanism aimed at a different file, and it would be reported as "my stats vanished" with no error anywhere. **Do not extend `GameStats` in this stage** (D-12, VPT-2).

3. **A silent hidden-information leak.** Every `seatAtDevice` in SEAT-2 that should have been `humanSeats.contains` renders one person's hand to another. Nothing crashes, nothing logs, no test fails unless written. The specific traps: `BotHUDRow`'s filter (`PlayerHUDView.swift:24`) and `HumanPlayerPanel` reading `victoryPoints` rather than `publicVictoryPoints` for a seat not at the device, which reveals held VP cards — the one thing the chips were deliberately built to hide (`PlayerHUDView.swift:415-422`).

4. **A wrong default on `victoryPointTarget` at any construction site.** The five pinned fingerprints hash a move *trace*, so adding a field is invisible to them — but a changed threshold shortens or lengthens every game and moves all five at once. If they change, the cause is a wrong default, and re-recording buries a real bug.

5. **`GameSetupStore`'s legacy read.** `HumanSeatStore.load()` reads `object(forKey:) as? Int ?? 0` (`:20`), which returns `nil` for an array value and `0` for a miss. Reading the new key with the old accessor, or failing to fall back, silently moves an in-progress game's human to seat 0. The game still loads, so the symptom is "the app is playing my opponent's seat", not an error.

6. **`humanSeats` as a `Set` reaching a comparison unsorted.** Swift seeds hash order per process, so an unsorted `.first` or `for` gives a different answer between launches — the class of defect that cost a day in `CatanAI`. Three places it can bite: which pending human discards first, the civilization draw (`GameViewModel.swift:285` already `.shuffled()`s an `Array(Set)`), and bot-personality assignment by seat order.

7. **Seat and civilization drawing must never touch `state.rng`.** `startNewGame` uses `Int.random(in: 0...3)` (`:193`) — the system generator, correct, and it must stay that way. Drawing from the game's own generator shifts every subsequent dice roll and fails all five pinned sequences, and the failure would look like a bot-behaviour regression.

8. **The bot-loop race under multi-human `.discarding`.** `apply(_:)` spawns a fresh `Task { await runBotTurnIfNeeded() }` after every human move (`GameViewModel.swift:304`), and `isProcessingBotTurns` (`:573`) is the only thing stopping two loops racing — a race that previously reproduced a `preconditionFailure` in `Bot.decideDiscard`. Two humans double the number of human moves arriving during one 7-roll resolution, so the guard is under more pressure. **The handoff cover must not introduce a second path that calls `apply` while a loop is in flight.**

9. **`GameView`'s sixteen pieces of per-seat `@State` surviving a handoff.** Seat B inherits seat A's armed knight or half-finished road-building pair — the same failure that dropped a player into a new board already in robber-targeting mode (`ContentView.swift:36-40`).

10. **The 4-human trade dead-end is live code today.** SEAT-7 closes it at the button; if that guard is ever removed the permanently-stuck offer comes straight back.

11. **A new `-qa` flag repeating the Release break.** The declaration went behind `#if DEBUG` and the call sites did not (`ContentView.swift:87`, `GameView.swift:353`), and every gate stayed green because only Debug was built. `gate.sh` now compiles Release on every run — but only if it is run before the PR.

12. **`SettlersTests` singletons write the simulator's real app container.** `PersistenceTests` snapshots and restores every file it touches for exactly this reason (`:13-46`), but `StoreFile.preserving` covers **files only** — there is no UserDefaults equivalent, and `HumanSeatStore`, `CivilizationSettingsStore`, `PlayerNameStore` and the new pacing preferences are all UserDefaults-backed. A naive test silently overwrites the developer's own settings on every `gate.sh` run. Add a UserDefaults-preserving helper or inject a suite name.

13. **Deleting a `.swift` file without `xcodegen generate`.** Fails as `cannot find 'PacingSettingsStore' in scope` — naming the symbol, not the file. Affects Step 11.

14. **`SettingsView` reached from the pause menu exposes controls that do nothing to the game in progress.** Always true from the main menu, newly confusing mid-game. The per-section "applies next game" captions in PACE-4 are the mitigation and are not optional decoration.

15. **375pt is the constraint; the default simulator is 402pt** (iPhone 17 Pro, per the run-settlers skill). A screenshot on the default simulator proves nothing about fit. Take it on a 375pt-class simulator or rely on the `SettlersTests` height assertion — and say which was done.

16. **`MainMenuView` grows substantially.** SwiftLint `--strict` warns at 700 lines and errors at 900 for `type_body_length`. `SeatRow`, the civilization picker and the Match Options block belong in their own files.

17. **The cover is software; the peek is human.** Stated in §4 so it is not later reported as a defect in the handoff.
