# Empires visual redesign — status

Direction: Avatar: The Last Airbender-style (`approved/master-reference-full-screen.png`, the original
approved "v4" generation). Warm, legible, bird's-eye board, one dominant color per resource tile, painted
landmark pieces with a soft textured single-color look, gold-trimmed UI chrome.

OpenRouter key spend so far: ~$2.02 of $10 budget.

## Folder layout

- `approved/` — the actual current deliverables. Everything in here is wired into the app or ready to be.
- `archive/` — every superseded attempt, kept for history, not in active use.
- `tiles/_scripts/` — the reusable generation tools (`generate_tile.py` for hex tiles, `generate_screen.py`
  for portrait full-screen concept art, `generate_icon.py` for square building-piece icons) plus
  `full-set-patch.html`/`.png`, a live preview of all 6 approved tiles composited into a real hex patch.

## In the app right now (`approved/`)

| File(s) | What it is |
|---|---|
| `tile-forest.png`, `tile-grain.png`, `tile-pasture.png`, `tile-mountain.png`, `tile-clay.png`, `tile-desert.png` | Board tile textures — bold, high-contrast brush strokes (confirmed to survive shrinking to real ~100pt tile size, unlike the first attempt) |
| `britannia-settlement.png` / `-city.png` | Britannia — castle, purple |
| `greece-settlement.png` / `-city.png` | Greece — the Parthenon, teal |
| `rome-settlement.png` / `-city.png` | Rome — the Colosseum, terracotta-red |
| `columbia-settlement.png` / `-city.png` | Columbia — the US Capitol dome, navy |
| `menu-icon.png` | Pause/menu button |
| `dice-frame.png` | Background frame behind the dice readout and the bank-count chip |
| `port-frame.png` | Decorative ring behind the functional port-ratio badge (that badge's own color-coding is untouched) |
| `button-frame-trade.png` / `-build.png` / `-turn.png` | Backgrounds for the 3 fixed action-row buttons only — every other use of that same button component keeps a plain background, since there's no fixed frame to paint ahead of time for open-ended labels (robber-victim picks, Cancel, dynamic Road/Settlement/City) |

All piece and UI-chrome images above have **verified real alpha transparency** (generated on a solid
magenta background, chroma-keyed out with an HSV-based key that also suppresses edge fringing, then
checked both numerically and visually against a colored backdrop before use — see git history of
`tiles/_scripts/generate_screen.py` for the method). Tiles are opaque by design (they fully cover their
hex, nothing shows through).

## Piece art status (as of the "restyle the original, one civ at a time" pass)

Direction changed again: instead of reinterpreting each civilization as a different famous landmark
(Colosseum, Capitol dome, ...), pieces are now a direct restyle of each civilization's own *original*
in-game silhouette (the real native design, screenshotted or captured from the actual
`CivilizationPieceShapes.swift` rendering) with Britannia's rugged painterly shadow/texture treatment
layered on. Shape stays recognizable as the original; only the rendering quality changes.

| Civilization | Settlement | City |
|---|---|---|
| Britannia | Painted (castle) | Painted (castle, grander) |
| Greece | Painted (flat pictogram, 2-column house shape, matches greece-city; redone per feedback) | Painted (flat pictogram, bold outline) |
| Rome | Painted (2-arch colosseum ruin, bold outline, rugged texture; redone per feedback) | Painted (4-arch colosseum ruin, bold outline, rugged texture; redone per feedback) |
| Columbia | Painted (blue obelisk/tower) | Painted (Capitol dome) |
| Egypt | Painted (cropped top tiers of the pyramid, Aztec-style crop logic; redone per feedback) | Painted (tiered pyramid) |
| Aztec | Painted (step-pyramid w/ staircase + carved detail, redone per feedback) | Painted (step-pyramid) |
| Japan | Painted (3-tier pagoda, redone per feedback) | Painted (pagoda) |
| Norse | Painted (longhouse) | Painted (longhouse, grander, flattened dragon-head roof finials; redone per feedback) |

`Civilization.paintedPieceImageName(isCity:)` looks up settlement/city independently per civ. All 8
civilizations now have both tiers painted in this restyled-original approach.

**Vector-shape system (`CivilizationPieceShapes.swift`) no longer has any active fallback use** - every
civ/tier now has real painted art. Not yet deleted; worth a follow-up pass to confirm nothing still
references it before removing it for good.

## Other pending work

1. **HUD player card (the colored info panel per player)** — deliberately not reskinned. It has 9 places
   styled with light text/icons for the current dark-blue background; dropping in a light card without
   retinting all of that would make text illegible. Real content-color work across `PlayerHUDView.swift`,
   not an asset swap.
2. **Roads** — intentionally left as their native flat-color rendering (`RoadShape`), not painted art. A
   per-segment static image would break the connected "snake" look consecutive roads have when they meet
   at a shared vertex.

## Known process notes (so the next round doesn't repeat mistakes)

- Fine/subtle texture on an image disappears once it's shrunk to real in-game size — always simulate the
  actual render size locally before judging a texture-heavy generation.
- This model's image-to-image mode (with `input_references`) rejects `background: transparent` outright —
  only `auto`/`opaque` are accepted. The working transparency method is: generate on solid magenta,
  chroma-key it out afterward, then verify both numerically (alpha histogram) and visually (composited
  onto a real background color) before wiring anything in.
- 9-slice (`capInsets`) stretching a background image onto a differently-proportioned button warps the
  corners — use fill+clip instead, which can only crop, never distort.
- `generate_screen.py`'s version numbering (`v1.png`, `v2.png`, ...) is NOT safe to call in parallel -
  two calls started close together can both compute the same "next" number and the second write silently
  overwrites the first. Run generations one at a time, or rename each output out of the shared folder
  immediately after it finishes, before starting the next one.
- When restyling an existing piece, feed the ACTUAL original piece image as the primary reference (not a
  text description of it) - a text description drifts into a new interpretation of the design, even when
  it's meant to just be a shape reference. `generate_screen.py` accepts a comma-separated list of
  reference image paths for this - the original piece first, then Britannia (or whatever the style
  reference is) second.
- Watch for "over-rendering": a piece with many small individually-outlined details (lots of arches,
  columns, tiles) reads as busier/less bold than the rest of the family even if its outline is
  technically the same width, because the fine internal linework competes with the outer border.
  Fixed by explicitly capping the count of large interior shapes (e.g. "exactly 3 arches, no columns
  between them") rather than just asking for a thicker outline.
- `generate_screen.py` always requests a portrait `1024x1536` canvas, which is wrong for square
  building-piece icons (stretches/distorts proportions vs. the square `approved/pieces` references) -
  use the new `generate_icon.py` (same reference-image + chromakey approach, but square `1024x1024`
  and takes an explicit output path instead of auto-versioning) for those instead.
