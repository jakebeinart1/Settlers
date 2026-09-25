# Ghost opponents, Elo and a leaderboard: design

**Date:** 2026-09-25 · **Requested by:** Jake · **Status:** design, awaiting Jake's review
**Builds on:** `feat/ghost-player` (the person model and `GhostPolicy`;
`docs/AI_summaries/2026-09-25-ghost-player-research.md`)

## What Jake asked for (his words, condensed)

1. **Remove pass-and-play completely.** The top-left seat on New Game is always
   you, so it loses its Human/AI control.
2. **Every other seat is an opponent.** Each seat's top control becomes
   **Opponent: AI | Ghost** instead of Human/AI. Choosing Ghost shows a
   picker of available ghosts.
3. **Match settings:** the difficulty row becomes **AI opponents: Classic |
   Expert**.
4. **Ghost Elo.** Every game you play updates your ghost (it relearns from
   you). Your ghost playing well against others raises its Elo.
5. **Classic and Expert bots have an Elo too.**
6. **A leaderboard, reachable from the home screen.**

## Decisions Jake made (2026-09-25, in the session)

| Question | Answer |
|---|---|
| Whose ghosts are in the picker | Ghosts built on this phone, **plus Jake's ghost bundled in the app** so testers can play him |
| How a ghost earns Elo | **Only in real games** where someone seats it. No background sims |
| When a ghost relearns | **After every finished game**, automatically, in the background |
| Bot Elo | **Fixed anchors**: Classic 1000, Expert at the rating its measured strength implies |

## Defaults I chose (say if any is wrong)

- **Ghosts are Classic-only.** The model is fitted on Classic standard games, so
  Ghost is offered only when mode is Classic and variant is Standard. In
  Expanded, Vast or Conquest the seat control shows AI only.
- **A ghost appears after 10 finished Classic games** by that person. Jake has
  24.
- **Random seat order stays.** "You" is the top-left card on the New Game
  screen, and turn order can still be shuffled. The engine continues not to
  know which seat is human (CLAUDE.md, "Seat 0 is the human").
- **A person's Elo and their ghost's Elo are separate numbers.** The coupling
  Jake once described (your ghost's wins lift you by a smaller step) is left
  out of v1, because on one phone your ghost only plays in your own games.
- **λ (how much the ghost leans toward you versus Expert) is one shipped
  constant.** It is calibrated once on the Mac: the ghost plays the shipping
  bots, and λ is set where its win rate matches the person's own (Jake: 13 of
  24, 54%). This is phase 4 of the research plan, which is still open.

## Design

### 1. New Game screen (`NewGameSetupView`, `SeatCardView`, `MatchSetup`)

- **Seat 1 (top-left) is always the human.** No role control; name and
  civilization stay.
- **Seats 2–4:** the role control becomes `AI | Ghost`. With Ghost selected,
  the civilization block is replaced by a ghost picker: the name, games
  learned from, and Elo. A ghost already seated elsewhere is greyed out.
- `MatchSetup.Seat` gains `ghostID: String?`, decoded with `decodeIfPresent`
  (saves predate it). `isHuman` stays on disk, because **old pass-and-play
  saves must still resume.** `matchProblem` already separates "resumable"
  from "offered on New Game", and new-game validation now requires exactly
  one human, at seat 0.
- The Difficulty row is relabelled **AI opponents**. `BotDifficulty` is
  unchanged (it is already `classic | expert`, per match).

### 2. Removing pass-and-play

The remove list: `HandoffCoverView`, and the multi-human branches in
`GameView`, `ContentView` and `GameViewModel` (hand-off prompts and per-human
panels). `HotSeatTests` goes too. The **decoding** of multi-human setups and
checkpoints stays, so an in-progress hot-seat save still opens and plays to
the end. This is a product removal, not a schema change.

### 3. Ghost storage (`Settlers/Persistence/GhostStore.swift`, new)

A ghost is a `Codable` record:
`{ id, name, source: .local | .bundled, person: PersonModel, gamesLearned, lambda, elo, eloGames }`

- **Local ghosts** live in Application Support, `ghosts/<id>.json`, one file
  each.
- **The bundled ghost** is a resource (`Settlers/Resources/ghosts/jake.json`),
  produced by `ghost fit` on the Mac. On Jake's own phone, his local ghost
  supersedes the bundled one (same person, fresher data).
- **Per-person decision records** (`DecisionRecord` JSONL, one file per game)
  are kept next to the ghost, so retraining never re-replays old games.

### 4. Retraining after every game (`GhostTrainer`, new)

When a Classic standard game ends with a single human seat:

1. Extract that game's decisions (`DecisionExtractor.decisions(in:anchor:humanTrading: true)`)
   at the ghost's current weights. About 100 decisions.
2. Refit on all of that person's stored decisions, starting from the current
   model (`PersonFitter.fit(start:)`, trust region and lapse as built).
3. Write the ghost atomically.

This runs on a background task after the end screen appears, and never on the
main actor. A failure logs, leaves the previous ghost untouched, and retries
at the next game end. On-device timing is **unmeasured**: the Mac took
seconds to minutes per round for 24 games. Measuring it on the iPhone 13 is
the plan's first gate. If it is too slow, fewer iterations per game come
before any redesign.

**Ceiling, stated:** re-linearisation happens incrementally (each new game is
linearised at the current weights). Old games keep their old slopes until a
full refresh, which v1 runs every 10 games.

### 5. Ghost in play (`GameViewModel+Policies`)

A ghost seat's policy is `GhostPolicy(person:, lambda:)`. It is Classic-only by
construction (section 1). The name on its HUD card is the ghost's name
("Jake's ghost"); the civilization art uses the person's civilization choice.
**Per-move latency on device is unmeasured.** `GhostPolicy` scores every
candidate twice, composed offers included. The existing bot pacing (600ms)
absorbs up to that; above it, the fix is to score the person's candidates only
for moves Expert ranks in its top N.

### 6. Elo (`RatingStore`, new, app target)

**Participants:** each human name, each ghost, and two fixed anchors, Classic
(1000) and Expert.

**Four-player update (pairwise decomposition):** the winner scores 1 against
each other seat, and two non-winners score 0.5 against each other. Each pair
applies a standard Elo update with K = 32/3 (so one game moves a player about
as much as one head-to-head game). Anchors never move; their results still move
their opponents.

**Expert's anchor:** measured at 68.4% wins against three Classic bots. Under the
pairwise scoring above, Expert's expected score against one Classic bot is
0.684 + 0.5 × (1 − 0.684 − 0.316/3) = 0.789, which gives
400·log10(0.789/0.211) ≈ **+229**, so **Expert = 1229**. The derivation is
kept in the store's doc comment.

**Who is rated in a game:** every seat. AI seats are the anchor for their tier
(`difficulty`), and ghost and human seats are themselves. Only complete games
count, and only in Classic standard (the same scope as ghosts, so the ladder
compares like with like).

**A ghost's Elo changes only in games it sat in**, per Jake's answer. Retraining
does not reset it. The number means "how this ghost has done", and the ghost's
games are its record.

**Backfill:** Jake's 24 logged games cannot be rated after the fact, because
the log roster does not record the AI tier. Everyone starts at 1000, and
Jake's ghost starts at his own rating once his first rated game is played.

### 7. Leaderboard (`LeaderboardView`, new; entry on `MainMenuView`)

A `GoldRowButton` titled "Leaderboard" sits beside Game History. Each row shows
rank, name, a kind badge (You / Ghost / AI), Elo, and games rated. Anchors are
marked "fixed". It is read-only in v1.

## Testing

- **Unit (SettlersTests):** Elo math (pairwise update, anchors immutable, the
  1229 derivation); `MatchSetup` decoding with and without `ghostID`, and an
  old multi-human save still resuming; new-game validation (exactly one human,
  at seat 0; Ghost only in Classic standard); `GhostStore` round-trip and
  bundled-versus-local precedence; `GhostTrainer` leaving the old ghost intact
  when a fit throws.
- **UI (SettlersUITests):** `MainMenuFlowTests` (Leaderboard entry),
  `NewGameModeFlowTests` (seat 1 has no role control; Ghost appears only in
  Classic standard; picking a ghost), and one end-to-end: start a game with a
  ghost seat, and the ghost's first move is legal.
- **Device measurements, recorded in the plan:** ghost move latency and
  retrain time on the iPhone 13.
- **Visual:** screenshots of New Game with a ghost seat, and of the
  leaderboard (run-settlers skill).

## Out of scope for v1

- Sharing ghosts between phones (beyond the one bundled ghost).
- Person-to-ghost Elo coupling.
- Ghosts in Expanded, Vast or Conquest.
- In-app drills and the blind test (research plan, phases 5–6).
