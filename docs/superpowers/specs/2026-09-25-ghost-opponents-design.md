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

**Two rules, both Jake's (2026-09-25):**
- **A ghost's *model* changes only from its person's own play.** Retraining
  reads the human seat's decisions and never the ghost's.
- **A ghost's *rating* changes only in games it sat in with exactly one human
  at the table.** That includes games against its own person: if Jake plays
  Jake's ghost and the ghost wins, it counts. "I wouldn't exclude that data
  unless problematic." The known cost is that a person and their own ghost
  trade points directly. That is visible on the detail page, and nothing
  corrupts the model, because only the human's decisions train it.

**A ghost's Elo changes only in games it sat in**, per Jake's answer. Retraining
does not reset it. The number means "how this ghost has done", and the ghost's
games are its record.

**Backfill:** Jake's 24 logged games cannot be rated after the fact, because
the log roster does not record the AI tier. Everyone starts at 1000, and
Jake's ghost starts at his own rating once his first rated game is played.

### 7. Leaderboard (`LeaderboardView`, new; entry on `MainMenuView`)

A `GoldRowButton` titled "Leaderboard" sits beside Game History. Each row shows
rank, name, a kind badge (You / Ghost / AI), Elo, and games rated. Anchors are
marked "fixed". **Tapping a person or a ghost opens its detail page (§8).**

### 8. Detail page (Jake, 2026-09-25, revised the same day)

Opened from any ghost's leaderboard row, **your own or an opponent's**: every
ghost on the phone, bundled or local, has the same page. It shows:

- **Header:** the ghost's name, whose ghost it is, and Elo.
- **Games learned from its human:** how many of its person's games trained it.
- **Games played against humans:** the rated games it sat in with a human at
  the table, with wins, losses and win rate. Self-play games against its own
  person are included (Jake's rule) and broken out on their own line.
- **FIFA spider graph:** six categories rated 1–99. It is drawn with a SwiftUI
  `Path`, because Swift Charts has no radar chart and no dependency is added.
- **Style:** the person model's top habits in plain words ("offers often",
  "robs the leader", "rarely plays dev cards"), from the fitted `theta`, sign
  and rank only. Section 7 of the research doc says sizes are not reliable.

The recent-games list is dropped (Jake: "the last 10 I don't need to see"). A
person's own leaderboard row shows the same header and graph, from their own
games.

**Radar categories.** Each is measured per game from the seat's own play:

| Category | Per-game measure |
|---|---|
| Production | resource cards received from rolls, per turn |
| Expansion | settlements + cities built |
| Trading | player trades completed (proposed and accepted, either side) |
| Development | dev cards played, plus Largest Army held at the end |
| Robber | share of robber moves that hit the leader |
| Finishing | final VP ÷ target |

**What "how good" means.** Each measure is scaled against the Expert bot's
average on the same measure, which is set once from seeded self-play
(`ghost` CLI) and shipped as constants with their source. **Expert maps to
75**, and each category is clamped to 1–99, so a rating reads "better or
worse than Expert at this". A ghost with fewer than 3 rated games shows its
**person's** games instead, drawn dashed and labelled "learned from Jake's
games".

**Where the numbers come from:** a `SeatStats` record (the six measures plus
VP and a win flag) is computed for every seat when a game completes. The
completed game is replayed through `GameSession` and its events are read. The
records are stored per match (`SeatStatsStore`), so the detail page never
replays a game on the main thread.

### 9. Keep everything (Jake, 2026-09-25: "All the data needs to be saved")

Nothing the ghost system produces is ever deleted, because it is also the
training data for making Expert better:

- **Game logs:** `GameLogStore` currently prunes to 500 (`maxKeptLogs`). That
  becomes **no pruning**. A log is about 20–50 KB, so 10,000 games is about
  0.5 GB, a real ceiling that is stated in the store's doc comment. If it is
  ever reached, the answer is compression, not deletion.
- **Decision records** (per game, per person), **seat stats** (per game, per
  seat), **rating history** (every update, not just the current number), and
  **every ghost version** (`ghosts/<id>/v<n>.json`, never overwritten) are all
  append-only.
- The existing phone-to-Mac copy (`xcrun devicectl … copy from`) pulls all of
  it for offline work.

### 10. "If my ghost beats Expert's Elo, is it better than Expert?"

Roughly yes, with three caveats. Being better than Expert is also the route to
improving Expert.

1. **Uncertainty.** After about 30 games an Elo is only good to about ±100. A
   ghost at 1250 against Expert's 1229 is a tie, not a win.
2. **Different pools.** Expert's 1229 comes from Expert-vs-Classic bot games.
   A ghost's rating comes from games with a human at the table. Elo assumes
   results carry over between pools, which is plausible but unproven.
3. **The real test is head-to-head,** and it can be run any time on the Mac:
   the `bot-strength` protocol with the ghost in every chair against three
   Expert bots, 1,248 games, held-out seeds. A win rate significantly above
   25% means it is better than Expert, full stop.

**Why this matters.** `GhostPolicy` is literally Expert plus a person term. If
Jake's ghost beats Expert head-to-head, adopting its weights and habits *is*
an Expert upgrade, learned from a human. That is the first time this repo
would have learned strength from people rather than self-play. The plan adds a
`ghost strength` command for exactly this test.

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
