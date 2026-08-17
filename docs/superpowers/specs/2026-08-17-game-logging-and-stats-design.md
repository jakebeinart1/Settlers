# Game logging & personal stats

Date: 2026-08-17
Status: Approved for implementation

## Background

Prompted by investigating a player report ("bots build roads with no
plan") that turned out to need a bots-only simulation harness to root-cause
(see `2026-08-16-bot-threat-assessment-design.md`'s follow-up fix). There's
currently no durable record of what happened in a real game once it ends -
`GameStore` only persists the *current* in-progress game (overwritten every
move, cleared on completion), so a finished or abandoned game leaves nothing
behind to look at afterward.

## Goals

- Every completed game leaves behind a replayable log (`GameState` +
  `GameMove`s are already `Codable`, so a full game is exactly its initial
  state plus its ordered move list - nothing needs to be reconstructed by
  hand).
- The player can see their own running stats (win rate, average game
  length, average final VP) on the main menu.
- Both are best-effort, on-device only: a logging failure must never affect
  real gameplay.

## Non-goals

- No in-app export/share UI (player confirmed: on-device files are enough
  for now - they'll pull the file directly if something needs investigating).
- No stats beyond win rate / average duration / average VP for this pass
  (per-opponent-personality breakdown was considered and deferred - nothing
  about the storage format forecloses adding it later).
- No unified game ID across an app relaunch mid-game: a game resumed from
  `GameStore` after the app restarts starts a *new* log segment rather than
  appending to the log from before the restart, and the stats duration
  clock likewise restarts. Full continuity would need a persisted game ID
  threaded through `GameState` itself - out of scope for a debug/stats
  feature. Fine print, not a footgun: the finished game still gets exactly
  one stats entry (recorded once, at whichever process is running when it
  actually ends), just with the pre-restart wall-clock time not counted
  toward that game's duration.

## Design

### `GameLogStore` (new, `Settlers/Persistence/GameLogStore.swift`)

One JSON-Lines file per game under `Application Support/GameLogs/<UUID>.jsonl`.
Each line is a self-contained, independently-decodable record (so a log
that got cut off mid-game by a crash is still readable up to its last
complete line) - a `start` line with the game's initial `GameState`, one
`move` line per applied move (`player`, `move`, `timestamp`), and a final
`end` line with the winner.

```swift
public struct GameLogStore: Sendable {
    public static let shared = GameLogStore()

    /// Starts a new log file, returns its ID for subsequent calls this session.
    public func startNewGame(initialState: GameState) -> UUID

    /// Appends one applied move. Best-effort - swallows write errors.
    public func appendMove(gameID: UUID, player: PlayerID, move: GameMove)

    /// Appends the game-over line, then prunes log files beyond the most
    /// recent `maxKeptLogs` (20) by file modification date.
    public func finalizeGame(gameID: UUID, winner: PlayerID)
}
```

### `GameStatsStore` (new, `Settlers/Persistence/GameStatsStore.swift`)

A single small persisted JSON value - running totals, not per-game
records, so this file never grows:

```swift
public struct GameStats: Codable, Sendable, Equatable {
    public var gamesPlayed = 0
    public var gamesWon = 0
    public var totalFinalVP = 0
    public var totalDurationSeconds: Double = 0

    public var winRate: Double            // gamesWon / gamesPlayed, 0 if none played
    public var averageFinalVP: Double     // totalFinalVP / gamesPlayed
    public var averageDurationSeconds: Double
}

public struct GameStatsStore: Sendable {
    public static let shared = GameStatsStore()
    public func load() -> GameStats                // empty GameStats() if no file yet
    public func recordGameEnd(won: Bool, finalVP: Int, duration: TimeInterval)
}
```

### `GameViewModel` wiring

`RulesEngine.apply` is currently called directly at 6 sites (the human's
own move, a bot's move, and four trade-response paths). All six route
through one new private helper instead:

```swift
private func applyLogged(_ move: GameMove, by player: PlayerID) throws {
    let wasGameOver = if case .gameOver = state.phase { true } else { false }
    try RulesEngine.apply(move, by: player, to: &state)
    GameLogStore.shared.appendMove(gameID: currentGameLogID, player: player, move: move)
    if !wasGameOver, case .gameOver(let winner) = state.phase {
        GameLogStore.shared.finalizeGame(gameID: currentGameLogID, winner: winner)
        GameStatsStore.shared.recordGameEnd(
            won: winner == humanPlayer,
            finalVP: state.victoryPoints(for: humanPlayer),
            duration: Date().timeIntervalSince(gameStartedAt)
        )
    }
}
```

Two new `private` properties, `currentGameLogID: UUID` and
`gameStartedAt: Date`, are (re)initialized everywhere `state` itself is
(re)initialized - `init()` and `startNewGame(randomizedBoard:)` - via
`GameLogStore.shared.startNewGame(initialState: state)`.

### Main menu

`MainMenuView` reads `GameStatsStore.shared.load()` and shows a compact
stats row (games played / win rate / avg VP / avg time) below the
New Game/Resume buttons, only once `gamesPlayed > 0` (nothing to show
before a first game finishes).

## Testing

No test target exists for the `Settlers` app module today (`GameStore`,
`PlayerNameStore`, etc. are all unverified by automated tests, relying on
manual build+run verification) - this stays consistent with that. Verified
via: a throwaway scratch script exercising `GameLogStore`/`GameStatsStore`
round-trips directly (write, re-read, corrupt-file tolerance), then a real
build and a played-through game via the `run` skill to confirm the main
menu stats row updates and a `.jsonl` file lands in Application Support.
