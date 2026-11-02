# Player ratings and records

## Product contract

Give each person an understandable record against the computer, shared across
their devices, with the clarity of a chess profile and the existing painted
Empires presentation. The delivery for this request is a reviewed pull request
with native screenshots, not a production release or an automatic merge.

- Keep independent pools for Classic Standard, Classic Conquest, Vast Standard,
  Vast Conquest and Voyages. Each has Classic AI and Expert AI ratings. Retain
  retired Expanded contexts only for historical records.
- A person is their existing CloudKit account identifier, never their display
  name. Alex, Jake and Kyle are ordinary directory entries, not special cases.
- Count one game against a single shared AI-tier entity. Multiple computer
  chairs do not create multiple games. A win raises the person's rating; a
  loss or restart lowers it. Quitting to the menu preserves the active match.
- Only one-human games against ordinary, homogeneous AI qualify. Ghost games
  and legacy pass-and-play remain outside this record. Their established
  Classic ghost ladder and training remain available separately.
- Show the selected pool's Elo on the menu, alongside overall wins/losses.
  Never average Elo across pools. A zero-game pool says Unrated.
- A personal page offers a mode chooser, two AI-tier choices, current Elo,
  record, rating trend, every game's before/after change, and shared standings.
- A finished game shows its own before/after rating and signed change. Integer
  changes equal the difference between the displayed rounded endpoints.
- Make offline/local progress, pending sync, no iCloud account and empty
  history explicit. Preserve results when connectivity fails.

## Rating policy and critique

The old pairwise four-chair model scores ties between the three losing chairs.
It can award positive Elo after losing to Expert, which conflicts with this
feature's whole-game win/loss meaning. Preserve that historical algorithm for
the ghost ladder; derive the new record from binary whole-game outcomes.

For a person with rating H, shared AI rating A, and N computer opponents:

    expectedWin = 1 / (1 + N * 10 ^ ((A - H) / 400))
    change = 32 * (actualWin - expectedWin)

Apply that change to the person and its opposite to the one AI entity, once.
This accounts for the number of competitors without counting one loss three
times. Both start at 1000 in each independent pool. Reusing Expert's old 1229
calibration would assert measurements for modes where none exist; these pools
instead develop from recorded outcomes. Numbers from different pools are not
directly comparable. This is an Empires rating policy, not Chess.com's Glicko
system or a claim of measured bot-strength improvement.

Replay authoritative per-match records by (completion date, UUID), deduplicated
by match identifier. The same set gives all phones the same ratings regardless
of arrival order. Older games arriving later can revise historical deltas;
explain that in help. Do not sync derived rating totals or trust client claims
of winners: continue replaying uploaded legal moves to verify results.

## Identity, history and migration

Use the existing CloudKit Match asset and creator ownership. No new database
schema, credentials, tester account or manual player-name mapping is required.
Add optional rating context and restart provenance to local per-seat records;
old JSON must decode unchanged. Initial game state proves mode and variant;
AI entity keys prove tier for old ordinary-AI Classic Standard records.

Historical recordings without trustworthy difficulty metadata cannot be
assigned to a tier by guessing. Recover archives where provenance is known,
preserve the rest, and explain the boundary in the UI. Persist difficulty in
new recordings. Metadata backfill must also enrich existing same-owner records,
preserving local ghost aliases, and durably reset the old sync cursor once.
An offline/interrupted migration must retry rather than permanently skip data.

The per-game record is authoritative before derived ratings. Preserve unfinished
displaced checkpoints until restart loss persistence and queued upload succeed.
Finishing or restarting again after a crash must not create another result.
Keep Classic-only ghost learning separate from the broadened recording scope.

## Visual direction

Reuse the painted sea background, dark navy plaques, notched gold borders,
serif typography, existing crests and spacing. The menu gains one compact
personal standing panel; the detailed page contains the graph and filters.
Gold emphasizes rating, muted white labels context, and signed text communicates
gains/losses independently of color. Keep actions reachable with large text and
on shorter devices. Do not add a second dashboard aesthetic or new artwork.

## Verification and review

Verify pool isolation, binary outcome direction, shared-AI counts, malformed
and duplicate records, stable replay, old JSON decoding, renames/account
adoption, same-account devices, late arrivals, offline restart persistence and
interrupted migration. Retain existing ghost semantics and saved-game behavior.

Native interaction must exercise menu entry, filters, other players, history,
help, cold resume, restart disclosure and a real completed game. Inspect
screenshots of the menu (new and established players), detailed record,
another mode/tier, shared standings, win/loss receipts, restart disclosure and
offline presentation. Include large-text/compact checks without allocating
unnecessary simulator devices. Run the repository's complete declared gate,
Debug and Release, and independent source/visual review before opening the PR.

Design reference: [Chess.com statistics](https://support.chess.com/en/articles/8705902-what-does-my-stats-page-show)
informs clear records and trends; [its rating explanation](https://support.chess.com/en/articles/8566476-how-do-ratings-work-on-chess-com)
describes a different algorithm and is not the implementation specification.
