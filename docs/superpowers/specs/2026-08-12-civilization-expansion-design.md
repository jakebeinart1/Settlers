# Civilization expansion + picker

## Why

Two asks from the Claude Design pass (`https://claude.ai/design/p/140e91a8-c0f8-4db9-b69c-7f2e1e7ce984`,
"Civilization Building Pieces"):

1. Refine the four existing civilizations' building pieces (etched detail,
   gold pennant city marker instead of a white ring).
2. Add the design's extra civilizations (Columbia, plus the Rome/Japan/Norse
   sketches) as real playable civilizations, and let the player choose their
   own civilization and which others are in the mix before a new game.

## A. Visual refresh (all 8 civilizations)

`CivilizationPieceShapes.swift` / `CivilizationBadge.swift`:

- The existing four (Britannia, Greece, Egypt, Aztec) keep their current
  silhouette and accent color — the design doc's "refined" fills are
  pixel-equivalent to what's already implemented. What's new: each shape
  gains one small stroked "etch" detail, always shown on both settlement and
  city (a doorway rect for Egypt/Aztec/Britannia, an outlined pediment
  triangle for Greece).
- The city marker changes from a white stroke ring to a small gold
  pennant-on-a-pole above the shape (`CatanTheme.cityPennantGold`,
  `#D4AF37`), drawn within the same square frame as the settlement (the
  shape is scaled down slightly to leave headroom) rather than growing the
  frame — keeps board layout untouched.
- Four new civilizations, each with its own silhouette, etch detail, city
  pennant (shared `PennantGlyph`), accent color, emblem SF Symbol, and
  general name. Rome/Japan/Norse exist in the doc only as single un-split
  sketches; their settlement/city/etch variants are derived following the
  same pattern as Columbia (which is fully specced).

  | Civilization | Silhouette | Color | General | Emblem |
  |---|---|---|---|---|
  | Columbia | domed capitol | `#6B7F99` slate-blue | Washington | `star.fill` |
  | Rome | arena/colonnade | `#B5674A` terracotta | Augustus | `crown.fill` |
  | Japan | pagoda | `#5F8B76` jade | Tokugawa | `mountain.2.fill` |
  | Norse | longhouse | `#7E93A3` steel-blue | Ragnar | `bolt.fill` |

## B. Seat assignment stops being hardcoded

Today `Civilization.forSeat(index)` is a fixed switch (0=Britannia/you,
1=Greece, 2=Egypt, 3=Aztec), read from ~10 call sites across board/HUD/
settings/trade views. Rather than thread a new parameter through all of
them, `forSeat` reads from a shared assignment
(`CivilizationAssignment.current`, a 4-element array set once per game)
instead of a switch — every existing call site keeps working unchanged.

Two persisted layers:

1. **User preferences** (`CivilizationSettingsStore`, UserDefaults):
   `yourCivilization: Civilization` (default `.medieval`, matching today's
   default) and `includedBotCivilizations: Set<Civilization>` (default: all
   other 7). Edited in Settings; applies to the *next* new game.
2. **Per-game assignment** (`CivilizationAssignmentStore`, a small JSON file
   next to the existing save): the actual 4 civilizations in seat order for
   the game in progress. Written when `startNewGame` runs (seat 0 = your
   chosen civ; seats 1-3 = 3 distinct random draws from your included set,
   excluding your own civ). Read back on relaunch so a resumed game keeps
   the same bots instead of re-randomizing. Cleared together with the save.

## C. Settings screen becomes the picker

`SettingsView`'s current read-only "Civilizations" list (which assumed the
fixed mapping) is replaced with:

- **Your Civilization** — a picker over all 8, each row showing its badge
  and name.
- **Bot Roster** — the other 7, each with a toggle for "in the mix this
  game"; a minimum of 3 stays enforced (can't uncheck below 3 available
  opponents). Switching "Your Civilization" auto-removes it from the roster
  if it was toggled on there.

Both write straight to `CivilizationSettingsStore` on change. Doesn't affect
the in-progress game — only the next "New Game".

## Not in scope

- Player count stays fixed at 1 human + 3 bots (engine hardcodes 4 seats —
  changing that is a separate, bigger project).
- No migration for old saves — a save from before this change fails to
  decode under the new format and is treated as absent (matches existing
  `GameStore.load()` behavior), so the player lands on a fresh main menu
  instead of a broken resume.
