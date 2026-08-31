# Empires — The Three Settings Surfaces

**Date:** 2026-08-30 · **Status:** for review · **Scope:** what belongs on each surface, and the acceptance criteria for each. Not layout.

This document exists to be handed to a design pass. It says **what must be present and what must be true**. It deliberately does not say where anything sits on screen, what it looks like, or what it is called in the UI.

---

## 0. The rule that decides where a setting goes

A setting belongs to exactly one surface. Apply these in order:

1. **Would changing it mid-game change what a legal move is, who is playing, or what winning means?**
   → **New Game Setup.** It is part of the match contract, fixed once Start is pressed, and a saved game must reproduce it.
2. **Is it about how the running game is presented to whoever is holding the phone?**
   → **In-Game Settings.** Takes effect immediately, changes no rule, and a saved game need not remember it.
3. **Otherwise** — a default, a preference, or stored data.
   → **App Settings.** Never the source of truth for a running game; only a prefill or a record.

**Corollaries, and each is a review check:**

- A match-contract control appearing in App Settings is a bug: it either does nothing until next game (confusing) or mutates a running game (unsafe).
- App Settings may *prefill* New Game Setup. It may never *be* the value the game runs on.
- Anything a saved game must reproduce lives in the match contract, not in a preference store.

**Today's arrangement violates this**, which is the reason for this document:

| Currently on | What | Should be |
|---|---|---|
| Main menu | Randomized Board, Randomize Seat toggles | New Game Setup |
| App Settings | Your Name | App Settings (as a **default**) + New Game Setup (as the **value**) |
| App Settings | Your Civilization | New Game Setup (App Settings keeps a preferred default only) |
| App Settings | Bot Roster | App Settings (it is the pool a "Random" seat draws from) |
| Nowhere | Victory target, seat composition, per-human names | New Game Setup |
| Nowhere | Bot speed, trade timer | In-Game Settings |
| Pause menu | Resume / Restart / Main Menu | In-Game Settings (keep) |

---

## 1. Surface A — New Game Setup

**Purpose:** define the match contract. Everything here is fixed for the duration of the game and must survive save/resume.

### A1. Seat composition

- **A1.1** The table is three or four seats, selectable. The screen shows every seat at once.
  *(Amended after the fact: this said "exactly four" and 3-player was listed out of scope. The
  supplied design included a Table Size control, so it was built for real rather than shipped as a
  dead toggle - `GameSetup.supportedPlayerCounts` is `3...4` and three-seat play is tested.)*
- **A1.2** Each seat is either **Human** or **AI**, and can be switched between them.
- **A1.3** At least one seat must be Human. The last remaining Human seat cannot be switched to AI.
- **A1.4** All four seats may be Human (zero AI) and the game must be startable and playable in that configuration.
- **A1.5** The number of Human seats is derived from the seat rows; there is no separate "number of players" control that could disagree with them.

**Acceptance criteria**
- Given four seats with one Human, when the user switches a second seat to Human, then the game starts with two human seats and two AI seats.
- Given exactly one Human seat, when the user attempts to switch it to AI, then the change is refused and the reason is stated.
- Given four Human seats, when the game starts, then no seat is bot-driven and the game reaches a winner through human input alone.
- Given any composition, when the game is saved and resumed, then the same seats are Human and the same seats are AI.

### A2. Identity — names

- **A2.1** Every Human seat has a name. **A name is required**; there is no unnamed human seat.
- **A2.2** Start is unavailable while any Human seat has no name, and the reason is stated.
- **A2.3** A name is prefilled from App Settings where one exists, so the common case needs no typing.
- **A2.4** Names are unique across Human seats — two humans cannot both be "Alex".
- **A2.5** A name has a maximum length, enforced at input rather than by truncation at display.
- **A2.6** Whitespace-only input does not satisfy A2.1.
- **A2.7** AI seats are named after their civilization's general and cannot be renamed.

**Acceptance criteria**
- Given a Human seat with an empty name, when the user attempts to start, then the game does not start and the unnamed seat is identified.
- Given a name of only spaces, when the user attempts to start, then it is treated as empty.
- Given two Human seats, when the user enters a name already used by the other seat, then it is refused with a reason.
- Given a name at the maximum length, when the user types another character, then it is not accepted.
- Given a seat switched from Human to AI, when the seat is redrawn, then it shows its general's name and offers no name field.

### A3. Identity — civilizations

- **A3.1** Every seat, Human and AI, has a civilization.
- **A3.2** No two seats share a civilization. This is an invariant, not a warning — the seat colour *is* the civilization's colour, so duplicates make the board unreadable.
- **A3.3** A civilization already taken by another seat is visibly unavailable.
- **A3.4** All available civilizations are reachable without the list running off the screen. Scrolling, if any, must be visibly indicated.
- **A3.5** A seat may be set to draw its civilization at random from the eligible pool (see C3).
- **A3.6** Every seat has a valid civilization before Start, whether chosen or drawn.
- **A3.7** The user's preferred civilization (see C2) prefills their seat, and can be changed here without changing the preference.

**Acceptance criteria**
- Given seat 1 is Greece, when the user opens seat 2's picker, then Greece is shown as unavailable.
- Given any sequence of picks and random draws, when the game starts, then the four seats hold four distinct civilizations.
- Given a seat set to random, when the game starts, then it holds a civilization from the eligible pool that no other seat holds.
- Given the full set of civilizations, when the picker is open, then every one can be reached, and any scrollable region indicates that it scrolls.

### A4. Match length

- **A4.1** The victory point target is selectable from a small set of named lengths.
- **A4.2** The default is the standard game.
- **A4.3** The chosen target governs the win condition, the victory-point display, and the end-of-game standings.
- **A4.4** ~~The AI evaluates the game against the same target.~~ **NOT IMPLEMENTED - deferred.**
  The engine's win check honours the target, and the UI reports against it, but `CatanAI`'s own
  notion of proximity to winning still assumes ten. Measured: an 8-point game's move trace is a
  byte-identical *prefix* of the 12-point trace across three seeds, which is what "the bots play
  identically and the game simply stops sooner" looks like.

  Deferred rather than done because changing how a bot values a position is a bot-strength change,
  and an honest strength claim here costs roughly 1,248 games per arm against a frozen anchor. That
  is the difficulty work, not a settings change. The practical consequence is mild - bots play a
  strong game and it ends early - but it is a real gap and is recorded as one.
- **A4.5** A saved game resumes at the target it was started with.

**Acceptance criteria**
- Given a target of 8, when a player reaches 8 victory points, then the game ends and that player wins.
- Given a target of 8, when the HUD shows a player's score, then it is shown against 8, not 10.
- Given a target of 12, when a game is saved at 9 points and resumed, then the game has not ended.
- ~~Given a target of 8, when a bot evaluates its position, then its notion of proximity to winning uses 8.~~
  **Deferred - see A4.4.**

### A5. Board and seating

- **A5.1** The board can be the standard layout or a randomized one.
- **A5.2** Seat order can be randomized, or set explicitly by the arrangement on this screen.
- **A5.3** When seat order is randomized, the user still plays the civilization they chose.
- **A5.4** The resulting turn order is visible before Start, or clearly indicated as random.

**Acceptance criteria**
- Given randomized seating, when the game starts, then the user's seat may be any of the four and their civilization is the one they picked.
- Given explicit seating, when the game starts, then turn order matches the order shown on the setup screen.

### A6. Starting, and not losing an existing game

- **A6.1** Start is unavailable until the configuration is valid (A1.3, A2.1, A2.4, A3.2, A3.6), and the reason it is unavailable is stated.
- **A6.2** If a saved game exists, starting a new one destroys it, and the user is warned before that happens.
- **A6.3** Resuming an existing game does not pass through this screen.
- **A6.4** The screen opens prefilled with the last used configuration, so a repeat game is fast.
- **A6.5** Leaving this screen without starting changes nothing about the saved game or the stored preferences.

**Acceptance criteria**
- Given an invalid configuration, when the user looks at Start, then it is visibly unavailable and names what is missing.
- Given a saved game in progress, when the user starts a new game, then they are warned that the existing game will be lost and can cancel.
- Given the user cancelled that warning, when they return to the menu, then the saved game is still resumable.
- Given a previous game was configured with three humans, when the setup screen is next opened, then it shows three humans.

---

## 2. Surface B — In-Game Settings

**Purpose:** change how the running game is presented, and leave it. Reached while a game is in progress. Nothing here alters a rule, so nothing here needs to be saved with the game.

### B1. Pacing

- **B1.1** The speed at which AI turns play out is adjustable.
- **B1.2** The change takes effect immediately, on the turn in progress, without restarting.
- **B1.3** The available speeds are a small named set, not a free value — an invalid speed must be unrepresentable rather than validated.
- **B1.4** No speed setting may make AI turns effectively instant, since being able to see what the AI did is the reason the delay exists.

**Acceptance criteria**
- Given a game in progress, when the user changes speed and returns, then the next AI action uses the new speed without a restart.
- Given any selectable speed, when AI turns play out, then each action is visibly separated in time.

### B2. Trade offer timer

- **B2.1** How long the user has to answer an incoming trade offer is adjustable, including "no limit".
- **B2.2** The setting is separate from pacing — wanting fast bots is not consent to be auto-declined.
- **B2.3** While an offer is open and awaiting an answer, the game does not proceed without the user.

**Acceptance criteria**
- Given "no limit", when an offer arrives and is left untouched, then it remains answerable indefinitely and no bot acts.
- Given a timed setting, when the timer expires with no answer, then the offer is declined and play resumes.
- Given an offer on screen, when the timer is running, then the remaining time is visible.

### B3. Game control

- **B3.1** The game can be resumed (dismiss the settings surface).
- **B3.2** The game can be restarted, with confirmation.
- **B3.3** The user can return to the main menu, with confirmation, and the game remains resumable afterwards.
- **B3.4** Reaching this surface does not advance the game while it is open.

**Acceptance criteria**
- Given this surface is open, when the user waits, then no AI turn is taken until it is dismissed.
- Given the user quits to the main menu, when they choose Resume Game, then the same position is restored.

### B4. What must NOT be here

- Anything from the match contract: seat composition, names, civilizations, victory target, board type.
- Rationale: changing them mid-game either does nothing (confusing) or corrupts the game in progress (unsafe). If a user wants a different match, that is a new game.

**Acceptance criterion**
- Given this surface, when it is reviewed, then it contains no control that changes a rule, a participant, or the win condition.

---

## 3. Surface C — App Settings

**Purpose:** defaults, preferences, and stored data. Reached from the main menu. Nothing here is the value a running game uses.

### C1. Default player name

- **C1.1** The user can store a default name, used to prefill their seat on the New Game screen.
- **C1.2** Changing it does not rename anyone in a game already in progress.
- **C1.3** It is optional here — the requirement to have a name is enforced at New Game (A2.1), not here.

**Acceptance criteria**
- Given a stored default name, when the New Game screen is opened, then the user's Human seat is prefilled with it.
- Given a game in progress, when the default name is changed, then the running game's labels are unchanged.

### C2. Preferred civilization

- **C2.1** The user can store a preferred civilization, used to prefill their seat.
- **C2.2** It is a preference, not an assignment — the actual civilization for a match is chosen at New Game (A3.7).
- **C2.3** Changing it does not affect a game in progress.
- **C2.4** All civilizations are reachable here without content running off screen unindicated.

**Acceptance criteria**
- Given a preferred civilization, when the New Game screen is opened, then the user's seat is prefilled with it.
- Given the user picks a different civilization at New Game, when that game starts, then the stored preference is unchanged.

### C3. AI civilization pool

- **C3.1** The user can choose which civilizations are eligible for seats set to draw at random.
- **C3.2** The pool must always contain enough civilizations to fill every seat that could draw from it.
- **C3.3** A pool too small to satisfy A3.2 cannot be saved.

**Acceptance criteria**
- Given the pool is at its minimum size, when the user tries to remove another civilization, then it is refused with a reason.
- Given a pool of N civilizations, when a game starts with seats drawing at random, then no two drawn seats share a civilization.

### C4. Stored data

- **C4.1** Lifetime statistics are viewable.
- **C4.2** Lifetime statistics can be reset, with confirmation, and the confirmation states what is lost.
- **C4.3** Past game logs are viewable.
- **C4.4** Statistics recorded from games with more than one human seat are excluded or clearly distinguished, since "your win rate" is meaningless when several people share the device.

**Acceptance criteria**
- Given a reset is requested, when the user confirms, then statistics are zero and the action is not undoable — and the confirmation said so.
- Given a completed two-human game, when statistics are viewed, then that game has not inflated a single player's record.

### C5. What must NOT be here

- Seat composition, per-seat names, per-seat civilizations, victory target, board randomization — all match contract (Surface A).
- Bot speed and the trade timer — presentation of a running game (Surface B). They may be *reachable* from here for discoverability, but they are the same setting, stored once, not a second copy.

**Acceptance criterion**
- Given a setting appears on both App Settings and In-Game Settings, when it is changed on either, then the other reflects the same value — there is one stored value, not two.

---

## 4. Cross-cutting requirements

### X1. One source of truth

- **X1.1** Every setting has exactly one stored location.
- **X1.2** Where a value is prefilled from a preference, the match stores its own copy at Start; later preference changes do not reach back into the running game.

**Acceptance criterion**
- Given a game started with the user's preferred civilization, when the preference is changed mid-game, then the running game is unaffected and the save still resumes with the original.

### X2. Save and resume

- **X2.1** A saved game reproduces its full match contract: seats, who is human, names, civilizations, victory target, board.
- **X2.2** A save written before a setting existed still loads, taking the default for anything absent.
- **X2.3** Failing to load a save is reported, not silently replaced with a new game.

**Acceptance criteria**
- Given a save written before victory target was configurable, when it is loaded, then it loads and plays to the standard target.
- Given a corrupt save, when the app starts, then the user is told rather than being silently given a fresh game.

### X3. Validity is enforced at the boundary

- **X3.1** Invalid configurations are prevented at input, not detected at Start where possible.
- **X3.2** Where prevention is not possible, Start states precisely what is wrong.

**Acceptance criterion**
- Given any sequence of interactions on the New Game screen, when Start is available, then the resulting game is valid — no configuration reachable through the UI produces an invalid game.

### X4. Defaults make the common case fast

- **X4.1** A first-time user with no stored preferences can reach a playable game without filling anything in except a name.
- **X4.2** A returning user can start a repeat of their last game in as few steps as the current one-tap New Game.

**Acceptance criteria**
- Given a fresh install, when the user opens New Game, then every seat is validly configured and only a name is required.
- Given a previous game, when the user opens New Game, then the previous configuration is present and Start is immediately available.

---

## 5. Explicitly not in scope

Recorded so the design pass does not budget space for them:

- **Bot difficulty / strength tiers.** No strength ladder exists yet; the AI personalities are play styles, not levels. Needs AI work first.
- **Table sizes beyond 3-4.** Three and four are implemented. Five and six need more pieces and a
  rebalanced board, and both encodings are fixed-width against a four-seat maximum.
- **Human-to-human trading.** A proposal is currently answered by AI seats only.
- **Networked multiplayer.** No networking exists.
- **Rule variants** beyond match length (friendly robber, alternate discard threshold, etc.).
- **Per-seat AI personality selection.** Meaningless to a player until difficulty exists.
- **Sound and haptics.** None exist yet; when they do, they belong on Surface B and C.

---

## 6. Summary table

| Setting | Surface | Saved with the game | Notes |
|---|---|---|---|
| Which seats are Human vs AI | A — New Game | Yes | At least one Human |
| Human seat names | A — New Game | Yes | **Required**, unique, prefilled from C1 |
| Seat civilizations | A — New Game | Yes | Distinct across all four seats |
| Victory target | A — New Game | Yes | Also governs AI evaluation |
| Randomized board | A — New Game | Board itself is saved | |
| Seat order / randomize seats | A — New Game | Resulting order saved | |
| AI turn speed | B — In-Game | No | Immediate effect |
| Trade offer timer | B — In-Game | No | Includes "no limit" |
| Resume / Restart / Main Menu | B — In-Game | n/a | Restart and Quit confirm |
| Default player name | C — App | No | Prefill only |
| Preferred civilization | C — App | No | Prefill only |
| AI civilization pool | C — App | No | Minimum size enforced |
| Lifetime statistics | C — App | n/a | Reset confirms |
| Game logs | C — App | n/a | |
