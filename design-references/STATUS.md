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
| `tile-forest.png`, `tile-grain.png`, `tile-pasture.png`, `tile-mountain.png`, `tile-clay.png`, `tile-desert.png` | Board tile textures — a tight single-brushstroke crop of each original painted canvas (see "Aug 21 bugfix/redesign pass" below), not the whole multi-tone canvas |
| `{civ}-settlement.png` / `-city.png` (all 8 civs) | See "Piece art status" below for the per-civ table |
| `menu-icon.png` | Pause/menu button |
| `port-frame.png` | Decorative ring behind the functional port-ratio badge (that badge's own color-coding is untouched) |
| `dice-fill.png`, `bank-fill.png`, `button-fill-trade.png` / `-build.png` / `-turn.png` | Plain borderless repeating texture swatches for the 5 "painted plaque" chrome spots (dice chip, bank/dev-card chip, Trade/Build/turn-action buttons) - the gold + thin inset red border is drawn natively by the shared `PaintedChromeBackground` view, not part of any image. See "Aug 21 unified painted-chrome border" below. `dice-frame.png`/`bank-frame.png`/`button-frame-*.png` (the old bordered versions) are retired - only their `-fill`/`-fill-*` successors are actually wired in now. |

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

## UI chrome aspect-ratio pass

The fill+clip approach (see process notes) never distorts, but it does crop whatever doesn't match the
container's real on-screen aspect ratio - and several chrome pieces were generated at aspect ratios far
off from where they actually render, so their gold corner ornamentation was getting cropped away (read as
"cut off"). Fixed by measuring each container's real aspect ratio from the SwiftUI layout code and
regenerating art to match, via a new `generate_chrome.py` (landscape 1536x1024 canvas, prompted to confine
the ornamented design to a vertically-centered band at the target aspect so the crop only ever removes
intentionally-blank margin, never content):

- `button-frame-trade/-build/-turn`: were 1.58:1, real buttons are ~2.4:1 (three equal columns in the
  bottom action row) - regenerated wider/shorter.
- `dice-frame` was reused for both the dice capsule (~1.9:1, minor mismatch) and the bank/dev-card chip
  (~4.2:1, severe mismatch - a 5-resource-wide strip barely 34pt tall) from the same 1.63:1 source. Split
  into two assets: `dice-frame.png` re-tuned to ~1.9:1 for the capsule, and a new `bank-frame.png` at
  ~4.2:1 for the chip. `GameView.deckCountChip` now points at `bank-frame`.
- `port-frame` wasn't cropped at all - `TileView.drawPort` draws it via `Canvas.draw(image, in: CGRect)`
  into an exact square, which stretches non-uniformly rather than cropping. The 195x155 (1.26:1) source was
  being visibly squished into a circle. Regenerated as a true 1:1 square via `generate_icon.py` instead.
- `menu-icon` (scaledToFit into a 32x32 square, close to square already) was left alone.

## Aug 21 bugfix/redesign pass

Feedback from actually playing on-device turned up a real bug and three quality issues:

- **Wrong pieces (bug, now fixed).** `Settlers/Assets.xcassets`'s `civ-*.imageset` PNGs had gone stale -
  11 of 12 were byte-different from `approved/pieces/`, so the board was showing an old landmark-based
  piece design (twin-tower castle, Capitol dome, ...) instead of the current restyled-original set. Also,
  4 civs (Aztec/Egypt/Japan/Norse) had no city imageset at all and `Civilization.hasCityArt` still hardcoded
  `false` for them, even though painted city art exists for all 8 - so those civs' cities always fell back
  to the flat vector shape regardless. Fixed by re-syncing all 16 PNGs into the asset catalog and removing
  the `hasCityArt` flag entirely (`paintedPieceImageName` now always returns a name). **Worth a recurring
  check**: nothing currently guards against `approved/pieces/` and `Assets.xcassets` drifting apart again -
  a future pass should probably script a diff check instead of relying on someone noticing visually.
- **Dice widget.** The reference shows an actual bold ivory die tile (rounded square, black pips) roughly
  as tall as the digit next to it; the app was using a small SF Symbol at `.title2` inside a `Capsule()`
  with only 6pt vertical padding, which read as a thin outline in a squat pill rather than a die. Replaced
  the SF Symbol with `GameView.DieFaceView` (a real square: `RoundedRectangle` + positioned `Circle` pips,
  standard 6-face layout), gave the chip more vertical padding, and swapped `Capsule` for a fixed
  `RoundedRectangle` corner radius (a capsule pinches the frame's notched-corner ornament to nothing at
  short heights). `dice-frame` regenerated once more at ~1.66:1 to match the taller content.
- **Tile "paint splotches."** Each hex draws the *entire* tile PNG stretched into its bounding box (see
  `TileDrawing.drawTile`), not a repeating pattern - so the source canvases' big multi-tone brushstroke
  patches (bright highlight streaks next to darker base color) showed up as visible blotches on the board,
  not a solid resource color. Fixed without new generation: `tiles/_scripts/find_uniform_tile_crop.py`
  scans a source image for a tight low-variance sub-region (one consistent brushstroke, no patch boundary)
  and crops it out; that crop replaced `approved/tiles/tile-*.png` in place - the original full-canvas
  versions are only in git history now, not a separate file, if a bigger patch is ever needed again.
- **Pause menu.** Was a native `confirmationDialog` - a plain system action sheet, the one piece of chrome
  that didn't match the painted theme at all. Replaced with `PauseMenuView`, built on the same `PopupCard`
  every other popup (Trade/Build/DevCard/Discard) already uses, plus an inline "are you sure" step before
  Restart/Main Menu since those are now easier to tap by accident inside a themed card than a system sheet.
- **`menu-icon` (found right after this pass shipped).** Despite the blanket claim above that "all piece
  and UI-chrome images have verified real alpha transparency," `menu-icon.png` was plain opaque RGB - no
  alpha channel at all - so its cream canvas showed as a visible white/cream square behind the ring at real
  size, and the ring touched the bottom canvas edge with no margin (read as clipped, not fully round).
  Regenerated properly. **Lesson**: that verified-transparency claim was written once for a batch and never
  re-checked per-asset since - read back actual pixel alpha values (`im.getchannel("A")`, corner/edge
  samples) for a specific asset before trusting a blanket claim about the whole set, especially for an
  asset (like this one) that predates the chromakey pipeline being standardized.

## Aug 21 button-border pivot

The "UI chrome aspect-ratio pass" fix above (regenerate at the button's real aspect) turned out not to be
the end of it. Two more rounds of feedback on the 3 action buttons (Trade/Build/turn-action):

1. **Inconsistent gap.** Each of the 3 separately-generated `button-frame-*` plaques left a *different*
   amount of dead transparent margin inside its own canvas despite an identical prompt/target aspect -
   `.scaledToFill()` scales the whole canvas including that margin to cover the button, so an inconsistent
   margin became an inconsistent visible gap between buttons (Build looked right, Trade/Turn didn't).
2. **Fixing #1 broke it worse.** Tight-cropping each asset to its actual alpha content bbox (removing the
   dead margin) revealed the model's *natural* proportions for this ornate notched-corner plaque design are
   ~3.2-3.7:1 - it doesn't reliably hit a requested ~2.3:1 no matter how the prompt is worded (tried three
   times, at 1.75/2.3/2.4, always landed back around 3.2-3.7). The real button is ~2.3:1. Forcing a further
   crop down to that from the tight bbox ate directly into the notched corners (nothing left of them),
   and *not* forcing it meant `.scaledToFill()` cropped so much width off the real (narrow) button that the
   gold border vanished on the sides entirely, leaving flat unbordered color - worse than the original bug.

Root cause: an ornate thick plaque with notched corners is fundamentally the wrong shape family for a
button this narrow, and no amount of prompt-tuning was going to make an image-based border reliable here.
Re-examined the reference at this exact spot (`master-reference-full-screen.png`, the bottom action row)
and it isn't the thick notched-plaque style used elsewhere (dice/bank chip) at all - it's a plain **thin
gold pill/stadium border**, which is inherently tolerant of aspect mismatches (a uniform-width border
around a capsule has no distinct corner feature to lose).

Fix: stopped trying to bake the border into an image entirely. `button-fill-{trade,build,turn}.png` are now
plain, borderless repeating texture swatches (cropped from the interior of the earlier generations, well
clear of any border pixels); `UniformActionButton` fills a `Capsule()` with that texture
(`.scaledToFill()` + `.clipShape(Capsule())` - safe now, since a uniform texture has no border to lose to
cropping) and draws the gold border natively with `Capsule().strokeBorder(...)`. A native vector stroke is
correct at *any* aspect ratio by construction - this class of bug can't recur for these 3 buttons again.
**Takeaway for next time**: prefer a native SwiftUI shape/stroke over a whole bordered-image asset whenever
the container's aspect ratio isn't fixed/known ahead of time; reserve full painted plaque assets (dice
chip, bank chip, port frame) for spots where the container's proportions are stable enough to actually
match a single generation.

## Aug 21 piece-size pass

Feedback: settlements/cities read as too small on the board, Rome especially so. Checked actual pixel
content vs. canvas size (`im.getchannel("A").getbbox()`) across all 16 piece PNGs and found the real bug:
wildly inconsistent dead transparent margin baked into each canvas - `CivilizationBadge` renders via
`.scaledToFit()` into a fixed `size x size` box, so any margin directly shrinks the visible piece.
`rome-settlement.png` was the worst offender, filling only 65% width x 59% height of its own canvas (most
other pieces were near 90-100%) - exactly matching "Rome is extra small." Tight-cropped all 16 to their
actual alpha content bbox (4px safety margin), which fixed the inconsistency directly. Separately, also
bumped `BoardView`'s own size multipliers (`geometry.size * ...`) from 0.58/0.68 to 0.68/0.80
(settlement/city) for the general "make them bigger" ask on top of that.

## Aug 21 dice-chip border evenness

Same underlying bug class as the "Aug 21 button-border pivot" above, on the dice chip specifically:
`dice-frame.png`'s border was baked into the image, and at the chip's real aspect the
`.scaledToFill()` crop landed unevenly - flush left/right, none top/bottom. Fixed the same way: split out
`dice-fill.png` (a borderless crop of the same texture) and draw the gold border natively
(`RoundedRectangle.strokeBorder(...)`) in `GameView.diceChip`, which is even by construction regardless of
aspect. Padding was left untouched so the chip's own footprint doesn't change size - it's a `ZStack`
overlay on `boardArea`, not part of `BoardView`'s own layout, so this couldn't have shifted the board
either way, but confirmed via screenshot diff anyway. `bank-frame.png` (the top-right chip) has the same
baked-in-border shape and hasn't shown this symptom yet, but is built the same fragile way - worth
proactively converting it the same way if it ever does, rather than waiting to be asked twice.

## Aug 21 unified painted-chrome border

Followed up on the note above: converted `bank-frame` (the top-right chip) to the same native-border
approach right away rather than waiting for it to visibly break, and factored the whole pattern out of
`UniformActionButton`/`GameView.diceChip` into one shared `PaintedChromeBackground` view (texture fill +
native gold `strokeBorder` + a thin inset dark-maroon accent line, color sampled from the original
`dice-frame.png` generation's own baked-in accent rather than picked by eye) so all 5 painted-chrome spots
(Trade/Build/turn-action buttons, dice chip, bank chip) render identically and can't drift apart again.
`bank-fill.png` is the same borderless-crop treatment as `dice-fill.png`/`button-fill-*.png`. Port frame and
menu icon are unrelated (a filled ring/circle, not a bordered rectangle) and weren't touched.

## Aug 21 piece outline thickness (Aztec/Rome/Greece)

Feedback: piece outlines/detail linework read as too thin on Aztec, Rome, and Greece specifically (Japan,
Norse, Egypt, Britannia, and Columbia were already fine). Fixed deterministically rather than
re-generating - `tiles/_scripts/thicken_piece_lines.py` finds near-black pixels within a piece's own alpha
shape (covers both the outer silhouette border and interior detail lines - doorways, arches - since they're
the same "black ink" in this style), runs a binary opening first to drop stray anti-aliased specks inside
shaded areas (without it, dilation was amplifying single-pixel noise into visible blobs), then dilates the
real linework inward by a radius proportional to the piece's own canvas size (`~0.0052 * min(w, h)`, floor
2px) - dilation is intersected with the original alpha mask, so growth can only thicken the stroke, never
extend the silhouette's outer edge or bleed into the transparent background.

**Only applied to the 6 flagged files** (`aztec-/rome-/greece-{settlement,city}.png`), not all 16 - an
early test pass at the same formula on `japan-settlement.png` (already "good") visibly degraded its wide
roof edge into a jagged staircase (a curved/gently-sloped edge is more sensitive to a disk structuring
element's blockiness than the flagged pieces' already-more-angular silhouettes), so the extend-to-everyone
option got reverted (`git checkout`) rather than shipped. If a future pass wants that generalized
"thicker everywhere" look, `thicken_piece_lines.py` is reusable, but expect to hand-check each result -
don't assume a formula calibrated on one piece transfers cleanly to a differently-shaped one.

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
