# Ghost management - design

2026-10-08. Jake's asks, in his words: reset ghost training; "the user should also have power to
remove its ghost or old ghost, and rename each ghost"; "pause training on a ghost if happy with
it ... clear that the ghost is being trained, when it is done (games remaining) ... option to
start and stop training. Should be auto on though. The rename and sync should be for everyone."

## Where it lives

Main-menu Settings -> **Ghosts** section -> **Manage Ghosts** screen.

| Row | Shows | Actions |
|---|---|---|
| **Your ghost** | name; status line (below); games learned | Rename, Training On/Off, Reset, Remove |
| **Old ghosts** (your earlier generations, after a Reset) | name, games learned | Rename, Remove |
| **Other players' ghosts** | name, owner | Hide / Show (this phone only) |

Status line for your ghost, one of:
- `Training now...` while the ~1 min background fit after a game runs.
- `Learning - 3 more games until others can play it` (below `GhostStore.minimumGamesToPlay`, 10).
- `Learning from every game` (playable, training on).
- `Paused - your games are not being taught` (training off).

## Rules

1. **Training is on by default.** Off is `GhostProfile.isTrainingPaused` (synced). While off, each
   finished rated game is marked *skipped* (`<ghost>/skipped/<match>`), so launch catch-up never
   teaches it later, including after training is switched back on. Resuming teaches from the next
   game.
2. **Reset = fresh start.** The current ghost's versions move to a new id `<me>~<n>` and become an
   Old ghost (playable, renamable, removable, local to this phone). The live ghost restarts from
   the anchor with `gamesLearned = 0` (so it leaves the picker until 10 new games); its decision
   records stay, so catch-up does not re-teach pre-reset games.
3. **Remove your ghost** = Reset without keeping an Old ghost, plus training off; it uploads as a
   tombstone. Turning training back on starts a fresh ghost. **Remove an Old ghost** deletes it
   from the picker. Files go to `Application Support/GhostArchive/` rather than being deleted
   (Jake, 2026-09-25: "All the data needs to be saved").
4. **Rename** sets `GhostProfile.name` and `isNameCustom = true`; `LiveSync.refreshNames` leaves a
   custom name alone instead of rewriting `"<player>'s Ghost"` on every sync.

## Sync for everyone, with no CloudKit schema change

The server compares one integer, the record field `gamesLearned`, and every phone accepts a ghost
only when that number goes up (`prepareGhostUpload`, `downloadGhosts`). A reset, a rename or a
pause does not add a game, so today none of them would ever propagate - worse, the next sync would
re-download the old ghost over a reset one.

`GhostProfile` gains `revision`: bumped by every learned game AND by every rename, reset and
remove. It is decoded with a default of `gamesLearned`, so every existing ghost starts at the
number the server already holds. The record field keeps its name `gamesLearned` (no Dashboard
deploy) but carries `revision`. `isNameCustom`, `isTrainingPaused` and `isRemoved` travel in the
JSON payload, which older app versions decode and ignore.

A removed ghost uploads a tombstone (`isRemoved = true`, higher revision): other phones drop it
from their pickers. Older app versions keep showing it until they update - acceptable, they also
ignore the rename.

Paused state syncs as a flag only so other phones can label the ghost "paused"; training itself
only ever runs on the owner's phone.

## Not in scope

- Syncing Old ghosts (they stay on the phone that reset).
- Renaming other players' ghosts (rename is the owner's, and syncs; others can only hide).

## Tests

- `GhostProfile` decodes old files with `revision == gamesLearned` (CatanAI).
- Upload/download accept a higher revision with fewer games; reject a lower one.
- Catch-up skips matches marked skipped, and pre-reset matches.
- `refreshNames` leaves a custom name alone.
- UI: Manage Ghosts shows the status line and toggles training.
