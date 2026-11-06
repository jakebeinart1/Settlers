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
  Classic ghost ladder and training remain available in Leaderboard's Ghosts
  scope, with their existing rating policy.
- Keep a single Leaderboard entry on the menu. Its small trailing accessory
  may show the selected pool's Elo; never add a separate ratings section.
  Overall wins/losses belong inside Leaderboard. Never average Elo across
  pools. A zero-game pool says Unrated.
- The initial Leaderboard shows side-by-side mode/tier selectors and a compact
  table of people plus one shared AI. Alex, Jake and Kyle must all fit before
  scrolling on ordinary 402×874 and 375×667-point phones.
- A person opens a distinct profile with Elo, record and a modest rating
  trend. Games opens a separate bounded result list. Back preserves person,
  mode and difficulty; results deep-link into this same Leaderboard flow.
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
serif typography, existing crests and spacing. Preserve the established menu
composition; ratings live in its existing Leaderboard action. The overview
contains one comparison table, with profiles and game history as drill-ins.
Gold emphasizes rating, muted white labels context, and signed text communicates
gains/losses independently of color. Keep navigation, filters and footer inside
the safe-area layout. Accessibility text may scroll within a framed table or
profile body, while navigation remains pinned. Do not shrink all body text to
force fit, or add a second dashboard aesthetic or new artwork.

## Layout correction and acceptance

The original gallery at `bf0f804` is a rejected baseline. Its tests scrolled to
Kyle and back to the filters, so they established eventual reachability while
missing an oversized overview. The independent audits agreed that clipping,
smaller padding or another scroll helper would preserve the wrong hierarchy.

The correction separates one snapshot-owning Leaderboard host from pure
standings/profile/history presentations and the established ghost pane.
Account naming and long sync explanations have their own sheet. Ghost radar
continues to filter through the old ladder's `ratedMatches`; mode-only results
must not enter that population. Parent-owned stable selection restores a ghost
detail after visiting the person's AI record.

First-screen tests now require full peer-row and shared-AI containment, equal
row geometry, disjoint sections, complete touch targets and pinned navigation.
Profile and history tests preserve selected context, and bounded accessibility
drags must not move the page chrome. Busy-menu, maximum-width valid names,
Unrated, empty history, help and account states also need visual review.

The first redesigned native run exposed real fit failures; its retained results
are the regression evidence. The refined 402×874 run passed 23 checks with zero
failures and three compact-only skips. Its complete device captures received
independent visual review. The 375×667 attempt stopped during build on the disk
growth guard before executing tests, so compact fit remains unverified.

On November 6, fetching main confirmed that `b6eef2b` remains the latest base;
the branch already contains it and rebase reported up to date. The reviewed
standard-phone captures and source are being published as a review checkpoint.
Their provenance identifies the captured source; later Help copy and context
size refinements still need recapture. The final exact-commit gate and compact
acceptance remain required before merge.

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
Debug and Release, and independent source/visual review before merge. The PR
was opened before the requested review, at Alex’s explicit instruction.

Design reference: [Chess.com statistics](https://support.chess.com/en/articles/8705902-what-does-my-stats-page-show)
informs clear records and trends; [its rating explanation](https://support.chess.com/en/articles/8566476-how-do-ratings-work-on-chess-com)
describes a different algorithm and is not the implementation specification.
