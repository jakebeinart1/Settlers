# Empires visual redesign — status

Direction: Avatar: The Last Airbender-style (`approved/master-reference-full-screen.png`, the original
approved "v4" generation). Warm, legible, bird's-eye board, one dominant color per resource tile, painted
landmark pieces with a soft textured single-color look, gold-trimmed UI chrome.

OpenRouter key spend so far: **$56.46 of $67 bought, ~$10.54 left** (read live from
`/api/v1/credits` on 2026-09-09). This line said "~$2.02 of $10 budget" for a long time
after it stopped being true, and was quoted back to Jake as fact - read the endpoint, do
not trust this number without checking it.

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
| `resource-cards/resource-{brick,lumber,ore,grain,wool}.png` | Resource **card** art — the commodity itself (bricks, a log, ore, a sheaf, a sheep) on a gold-rimmed hexagon. Distinct from the tile textures above, which are terrain seen from above: a hex on the board and a card in your hand are different objects. Supplied by Jake at 1254x1254 as RGB with a **hard black background and no alpha**, so they cannot be dropped into the UI as-is. `Settlers/Assets.xcassets/resource-*.imageset` holds the wired-in versions: background flood-filled to transparent **from the border inward** (a blanket black-to-alpha would punch holes in the artwork, whose outlines are near-black too), trimmed to the hexagon, and downscaled to 240px. `CatanTheme.iconImageName(for:)` is the one place the art's commodity names are reconciled with the engine's terrain names — lumber is a forest, grain is wheat, wool is a sheep. |
| `resource-cards/_contact-sheet-octagonal-variant.png` | An alternative treatment of the same five as octagonal plaques, supplied alongside. **Not wired in** — kept because the octagon reads better at large sizes and may suit a future full-card view. |
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
| Greece | Painted (flat pictogram, 2-column house shape, matches greece-city; light tan, Sep 4) | Painted (flat pictogram, bold outline; light tan, Sep 4) |
| Rome | Painted (3-arch rectangular arcade, heavy black frame, double cornice + plinth; `#E16256`) | Painted (2 storeys x 4 arches, same rectangular block grown; regenerated 2026-09-09 - see "Sep 9 Rome city" below) |
| Columbia | Painted (white obelisk/dome; AI-regenerated white, Sep 4 - see "Columbia white / Greece tan recolor" below) | Painted (white Capitol dome; AI-regenerated white, Sep 4) |
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
  **Superseded:** `PauseMenuView` no longer exists - it was absorbed into `InGameSettingsView` (Surface B of
  `docs/superpowers/specs/2026-08-30-settings-surfaces-acceptance-criteria.md`), a full painted screen that
  adds AI turn speed and the incoming-offer timer above the same three actions. The "are you sure" step
  survives as `ConfirmationPopupCard` in `SettingsChrome.swift`, still on `PopupCard`.
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

## Aug 21 follow-up: Rome/Aztec even thicker, Japan settlement size, Britannia opacity

Three more rounds of feedback after the pass above:

- **Rome/Aztec needed noticeably more** than the first thickening pass gave them - ran
  `thicken_piece_lines.py` a second time on top of the already-thickened files (rome +4/+3,
  aztec +6/+5 city/settlement) rather than starting over, since dilation composes fine.
- **Japan's settlement read as small** even though its art is already tightly cropped to 100% canvas fill
  (nothing left to gain by re-cropping) - it's just a visually lighter/more compact shape (a single
  flat-roofed pagoda tier) than e.g. Britannia's turreted castle at the same nominal size. Added
  `Civilization.pieceSizeCorrection(isCity:)`, a per-piece multiplier on top of `BoardView`'s uniform
  settlement/city size (default `1.0` for everything except Japan settlement, `1.18`) - the intended escape
  hatch for exactly this "already-tight art, still reads small due to its own shape" case, rather than
  bumping the uniform multiplier for every civ to compensate for one.
- **Britannia city/settlement were genuinely see-through** - checked actual alpha values (not just visual
  impression) and found 64-72% of their opaque pixels had partial alpha (mean ~170/255 instead of 255,
  unlike every other piece, which sit at a clean 255) - a real bug, not a style choice, likely predating the
  chromakey pipeline being standardized (same category as the `menu-icon` no-alpha-channel bug earlier in
  this file). Fixed by binarizing alpha at a 40/255 threshold (>40 -> fully opaque, else fully transparent)
  for just these 2 files, matching the hard-edged convention every other piece already has.

## Sep 4 Columbia white / Greece tan recolor

Jake asked for Columbia's material color to be white "across the board" and Greece's to move
from its white/grey marble to a light tan, with the settlement/city art regenerated to match
but the piece shape/shading left exactly as-is.

Recoloring via a fresh `generate_icon.py` call was rejected in favor of a deterministic
duotone remap: `tiles/_scripts/recolor_piece.py` takes each opaque pixel's own Rec. 601
luminance and maps it `lerp(black, target_rgb, luminance)` - existing black outline ink stays
black, existing highlights stay bright, every midtone shifts to the target hue. A fresh AI
generation risks silently drifting the silhouette (the whole point of the original "restyle
the original, one civ at a time" pass above was to avoid that), and the ask here was
explicitly "same piece, different material," which a per-pixel color remap guarantees at zero
OpenRouter spend - unlike every other regeneration logged in this file, this one cost nothing.

Ran on all 4 files (`columbia-{settlement,city}.png`, `greece-{settlement,city}.png`) in
`approved/pieces/`, then re-synced into `Assets.xcassets`. Greece's target was (230,208,166),
a pale wheat/sandstone tan - lighter and less saturated than Egypt's (196,148,79) sandstone so
the two don't read as the same material. Plain duotone (`floor`/`ink_cutoff` both 0), one
pass, approved as-is.

Columbia's first pass (plain duotone, target pure white) looked gray rather than white on
device - checked why rather than re-guessing: `columbia-{city,settlement}`'s original art is
genuinely mid-to-dark in luma (median luma 0.40 and 0.16 respectively, since it was a fairly
dark blue-grey material to begin with), and plain `lerp(black, white, L)` reproduces that same
tonal distribution, so a "dark" source piece stays visually dark even once every hue is
stripped to gray - looking gray/charcoal, not white. Fixed with `recolor_piece.py`'s added
`floor`/`ink_cutoff` params: pixels below `ink_cutoff` luma (0.15) are forced pure black
(keeps the outline/detail linework crisp) and everything else is remapped from
`[ink_cutoff, 1]` into `[floor, 1]` before scaling by the target color - so the fill is pushed
into a bright near-white band regardless of how dark the original shading was, while the black
ink stays exactly as sharp.

That second pass (floor 0.8, ink_cutoff 0.15) fixed the gray-not-white problem but introduced
a new one ("looks whak"): the source art's fine paper-grain texture, stretched by the high
floor, showed up as visible blotches. Iterated `recolor_piece.py` twice more on Columbia
specifically - adding `smooth` (an alpha-weighted Gaussian pre-blur so isolated grain pixels
don't trip a threshold the way a real several-pixel-wide stroke does), then a Sobel-gradient
ink signal plus an unconditional `border_px` alpha-ring border (since no single darkness
threshold could separate "thin outline stroke" from "large genuinely-dark shadow-side fill"
on this particular source file - one caught too little, the next caught the whole shadow
region as solid black). Each pass fixed the specific defect Jake had just flagged and revealed
the next one on-device: city dividers still barely visible ("no border... shades of light,
white, and gray"), then, once those were legible, "the interior lines aren't as thick as the
settlement's" - a plain darkness/gradient threshold was never going to reliably reproduce
"looks like the rest of the roster's bold painted-outline style," because that style is a
*rendering convention* the original artist applied by eye, not a property recoverable from
Columbia's own (differently-styled, blue, thin-lined) source pixels.

**Abandoned the deterministic pixel-math approach entirely and went back to
`generate_icon.py`** (the tool this whole approach was originally chosen over, "Recoloring via
a fresh `generate_icon.py` call was rejected..." above) - Jake's own call: "I don't think
drawing them yourself is the best way. I think you should reproduce the image through the
image generator." Regenerated both files image-to-image, feeding the ORIGINAL pre-recolor blue
piece as the shape/silhouette reference and an already-bold-outlined piece (Britannia's castle,
then Columbia's own freshly-generated settlement for the city's second pass) as the *outline
style* reference, with the prompt explicit that interior detail lines need their own bold
black stroke, not just the outer silhouette - directly asking the model to reproduce a
*rendering convention* is what the pixel math could never do, because that convention isn't
recoverable from Columbia's own source pixels at all. Two rounds: v1 for both files (clean
white/ivory fill, solid bold outline, but the city's interior lines read thinner than the
settlement's), then a v2 city-only regeneration adding the v1 settlement image as a second
reference specifically for line *thickness* ("match the outline THICKNESS of the SECOND
reference image exactly"), which fixed it. Total cost ~$0.19 across 3 calls - real spend,
unlike the free pixel-math attempts, but it's what actually matched the roster; budget still
nowhere near the original $10 note at the top of this file. Verified both via a side-by-side
composite and confirmed on Jake's own iPhone.

`Civilization.baseAccentColor` updated to match: `columbia` from the old slate blue-grey
(0.42, 0.50, 0.60) to near-white (0.96, 0.96, 0.96); `greece` from white/grey marble
(0.80, 0.81, 0.80) to light tan (0.90, 0.82, 0.65). Both still pass through `Self.vivid` like
every other civ's color.

**Follow-up: Columbia's settlement read small next to the roster.** Same "already-cropped-tight
but visually light shape" case `pieceSizeCorrection` exists for (see Japan's settlement,
above) - the new AI-generated obelisk/dome silhouette measures a normal alpha-bbox fill
(89% x 95%, close to Britannia's 94% x 97%) so there was no margin left to gain by re-cropping.
Added `(.columbia, false): 1.15` to `pieceSizeCorrection(isCity:)`.

**Follow-up: Greece's settlement read darker than its city.** Not a color-target mismatch -
both pieces' non-black fill pixels average essentially the same RGB (measured: (180.6, 163.3,
130.3) city vs (180.3, 163.0, 130.0) settlement) - it's that the settlement's original art
genuinely has much denser dark linework relative to its size (48.9% of its opaque pixels read
as near-black vs the city's 31.9%, and its 25th-percentile luma sits at 0.076 vs the city's
0.194), so the *same* tan target reads visually darker/denser overall on the smaller piece.
Regenerating via `generate_icon.py` again felt like overkill for a "nudge it lighter" ask, and
Greece's existing outline was already approved ("greece looks good") - re-deriving ink from
scratch risked breaking that. Instead: a small one-off blend, not routed through
`recolor_piece.py` (whose `floor` parameter also lightens genuine near-black ink pixels
directly, which would have grayed out the crisp outline this fix needed to leave untouched) -
every opaque pixel with `RGB sum >= 90` (i.e. not already near-black ink) blended 22% of the
way toward white (`rgb + (255-rgb)*0.22`), ink pixels left exactly as they were. Re-synced,
confirmed via a side-by-side crop against the city.

**Follow-up: Jake wanted the settlement's fill to be Greece city's exact color, not a nudge
toward it.** The 22%-blend fix above visibly narrowed the gap but wasn't literally the same
RGB. Fixed properly this time: eyedroppered the city's own flat-fill tone directly - the
single most common RGB among the city's non-ink, non-highlight opaque pixels (excluding
`sum<90` as ink and `sum>720` as near-white highlight) is (227,205,164), repeated across
271,699 candidate pixels with (228,206,164) a close second, so it's genuinely the dominant flat
tone, not an averaging artifact. Re-ran `recolor_piece.py` plain-duotone (no `floor`/
`ink_cutoff` - matching how greece was first recolored, before any of the follow-up tuning
above) on BOTH `greece-city.png` and `greece-settlement.png` from their pre-recolor originals
with that exact target, so city and settlement are now colorimetrically identical by
construction rather than independently-tuned approximations of each other.
`Civilization.baseAccentColor` for `.greece` updated to the same (0.890, 0.804, 0.643) so the
HUD/badge/road (which all read `accentColor`, still plain `vivid(baseAccentColor)`, no
per-civ road override - see the reverted `roadColor` note below) derive from the identical
eyedroppered value too, not the earlier hand-picked (0.90, 0.82, 0.65) approximation.

**Follow-up: still "just not the same," even with an identical target RGB by construction.**
The road (also driven by that same value) was fine, so this was specific to the settlement's
*fill*, not the color choice - confirms the earlier "denser dark linework relative to its
size" finding above: an identical duotone target still produces a visibly different result
once the two source pieces' own luma distributions differ this much, because the mapping is
per-pixel (`target * luma`), not a single flat color. Sampling yet another point on the city
wasn't going to fix a distribution-shape mismatch either. Regenerated the settlement via
`generate_icon.py` again (Jake: "you may have to regenerate Greece's settlement") - but this
time handed the model `approved/pieces/greece-city.png` itself as the color/style reference
(not a hex value) with the prompt explicit about matching the reference's overall *brightness
balance*, not just its hue, and asking it to avoid large heavily-shaded dark areas. This is a
strictly better ask of the image model than an exact RGB is: matching "reads as the same
overall material" is exactly the kind of holistic-appearance judgment a duotone remap (or any
single-target color math) structurally cannot make, since it only ever sees luma-in,
color-out for one pixel at a time with no notion of the OTHER piece's own tonal distribution.
Re-synced, confirmed via a side-by-side crop and reinstalled on Jake's phone.

**Follow-up tried and reverted: a separately-darkened Greece road color.** Jake first asked
for Greece's road to be darker than its light-tan `accentColor` for legibility against the
board. Added `Civilization.roadColor` (an HSB-darkened variant, Greece-only) and
`CatanTheme.roadColor(for:)`, wired into `BoardView.roadViews`'s one per-player road-fill call
site. On review the darkened shade read as too dark / not recognizably Greece's own color -
Jake asked for "the exact color" instead, i.e. no separate road shade at all. Reverted
`roadColor`/`CatanTheme.roadColor(for:)` entirely; `BoardView.roadViews` is back to plain
`CatanTheme.color(for:)`, so Greece's road (like every other civ's) is exactly `accentColor`,
no special case.

**Lesson for next time:** the earlier "restyle via AI, not by hand" choice in this same section
was right for a *fresh* civilization redesign, but this ask - "same piece, reproduce the
roster's own bold-outline rendering convention on a differently-styled source" - was also
fundamentally an AI-generation problem, not a pixel-math one, and four rounds of threshold/
gradient/blur tuning were spent establishing that the hard way. The tell in hindsight: once the
ask becomes about matching a *style convention* (line weight, "looks like the others") rather
than a *measurable pixel property* (hue, brightness), deterministic pixel math is the wrong
tool - reach for `generate_icon.py` with the right reference images instead of iterating
further on thresholds.

**Follow-up: the city's own interior lines still read thinner than its own outer border.** The
v2 city regeneration above (matched line thickness to the settlement) still left some interior
detail - the thin column dividers between window openings especially - visibly thinner than
the bold outer silhouette stroke on the city itself. Regenerated once more (v3), this time
using the CURRENT `columbia-city.png` as its own sole reference and asking narrowly for one
fix only: every interior line brought up to the same thickness as that same image's own outer
border, everything else (shape, color, shading, composition) held identical. Worked cleanly in
one pass - a self-reference plus a single, precisely-scoped instruction ("make X match Y,
already both present in this one image") gave the model an unambiguous target in a way
"thicker" or "bolder" in the abstract hadn't. Re-synced, reinstalled on Jake's phone.

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

## Aug 21 tile restyle: anime/cel-shaded instead of painterly

Jake felt the tile textures (even after the "paint splotch" uniform-crop fix earlier this session) were
still an oil-painting style he didn't want - he was after the reference board's brighter, more saturated,
**anime/cel-shaded cartoon** look (flat color masses with clean cel-shading and crisp line-art accents,
like Genshin Impact terrain textures), not brushstroke-textured painting at all, even a "clean" one.

Regenerated all 6 resource tiles (`forest`, `grain`, `pasture`, `clay`, `mountain`, `desert`) via
`generate_tile.py` with a prompt built around "anime cel-shaded cartoon illustration style... flat clean
color shading... NO oil-paint brushstrokes, NO visible canvas texture, NO impasto... crisp clean line art
accents". Ran the results back through `find_uniform_tile_crop.py` (same as the earlier paint-splotch fix)
to pull a seamless low-variance sub-region, since the tile still gets stretched into a hex's bounding box
by `TileDrawing.drawTile` and needs to read as one solid color.

**Bug found and fixed**: `grain` and `clay`'s first generation (`v1.png`) baked its own hexagon-grid
pattern into the texture (visible seam lines cutting across at an angle no matter where the crop window
landed), because the "top-down aerial tile texture" framing in the prompt read literally as "Catan hex
tiles" rather than "a generic ground texture". Regenerated `v2.png` for just those two with an explicit
"NO grid lines, NO hexagon shapes, NO tile seams... one continuous unbroken field" instruction, which
produced a clean continuous texture that crops without visible seams. Lesson for next time: when asking
for a "board tile texture," be explicit that the *ground material* should have no grid of its own -
the hex shape comes from the app's rendering, not the source art.

## Aug 21 tile restyle, take 2: match the reference exactly, not "anime"

Jake's "anime drawing" phrasing above led to an overcorrection - the cel-shaded/Genshin-Impact-style
regeneration was too illustrated (visible trees/wheat-stalks/rocks drawn into the texture, very high
saturation). What he actually wanted, shown by pointing straight at
`approved/reference/master-reference-full-screen.png` again: the reference board's own tile look - a flat,
moderately-saturated, single dominant color per resource with a **subtle fine canvas/linen grain texture**
running through it (barely-there, like a soft painted wash), and explicitly *no* drawn scene elements at
all (no trees, no wheat stalks, no rocks/cracks) and *no* bright cel-shaded cartoon look either. "A little
drawing texture, as if the drawing was done and not just a single solid color" - the texture is meant to
read as "this was painted," not as illustrated content.

Regenerated all 6 with `generate_tile.py`, extended with an optional trailing `ref1.png,ref2.png,...` arg
(same `input_references` image-to-image mechanism as `generate_screen.py`) so the prompt could point
directly at `master-reference-full-screen.png` as a style reference instead of describing the look in
words - much more reliable than iterating on adjectives. Center-cropped each 1024x1024 result to 512x512
(no seams/artifacts to route around this time - the whole canvas came out uniform). Colors: clay
warm burnt-orange, grain golden mustard, forest deep olive-green, pasture lighter yellow-green, mountain
cool gray, desert warm sandy-tan (deliberately close to grain but paler/more muted, matching the reference).

**Lesson**: when a user says "anime" or names a style, don't take the label at face value - the reference
image they keep pointing back at is the actual spec. If a regeneration technically fits the label but the
user says "no, not that" while re-sending the *same* reference image, the real ask is "match this
image," not "try harder at the label." Pass the reference image itself into the generation call
(`input_references`) rather than re-describing it, once that option exists.

## Aug 21 tile color tuning: forest, desert, and the frame/gap color

Two individual color notes after the take-2 regeneration above:
- **Forest** came out too dark/muddy-olive on the first try. Overcorrected once (too saturated/neon
  "kelly green") before landing on a natural, moderately-saturated pine-forest green
  (`generate_tile.py forest "...RGB around 50,120,55...NOT neon/kelly/grass green...think deep pine
  forest, not lime" ...`) - final average ~(44,94,37).
- **Desert** needed to match a specific close-up crop Jake sent of the reference board's desert tile
  exactly (not just "tan" in the abstract) - passed that crop image as a *second* `input_references` entry
  alongside the full board reference, with its sampled RGB (223,187,112) spelled out in the prompt too.
  Landed at (233,191,106), a close match.

**Frame/gap color bug**: `TileDrawing.drawTile` (`Views/Board/TileView.swift`) fills a full-size hex with
`CatanTheme.desert` *underneath* every tile's shrunk resource texture, so that flat color - not an image -
is what shows as the manila "grout" between tiles on the whole board. It's a hardcoded `Color(red:green:
blue:)` in `Theme/CatanTheme.swift`, completely independent of the `tile-desert.png` asset, so tuning the
desert tile's color doesn't automatically move the gap color - they only look consistent by manual
coincidence, which had already been asked for as "the gaps need to be the exact same color as the desert
tile." Fixed by resampling the new `tile-desert.png`'s actual average RGB `(233,191,106)` and hardcoding
that as `CatanTheme.desert`'s value with a comment noting where it needs to stay in sync. If the desert
tile's color is tuned again, `CatanTheme.desert` needs a matching update - it will NOT pick it up
automatically.

## Aug 21 board-wide serif type + number-token background tint

Jake pointed at the reference's serif numerals/labels (its actual body copy, not just a display face) and
asked for the same across the whole board screen, numbers included. No custom font file was needed - SwiftUI
ships a real serif system font (New York) selectable via `.fontDesign(.serif)`, and applying it once as a
view modifier on `GameView`'s root `ZStack` cascades to every popup (`TradePopupView`, `BuildPopupView`,
`DiscardPopupView`, `DevCardPopupView`, `InGameSettingsView`, `IncomingTradeCardView`) since they're all plain
children of that same ZStack, not separate `.sheet`s - one line covered the whole board, HUD, and every
in-game popup. `EndGameView` is presented separately from `ContentView`, outside that tree, so it needed
its own `.fontDesign(.serif)`.

**Caveat that cost a moment of confusion**: text drawn directly into a `Canvas`'s `GraphicsContext` (the
hex number tokens, the robber's number, port ratio labels - all in `TileDrawing`, `Views/Board/TileView.swift`)
does NOT pick up an ancestor's `.fontDesign` environment value the normal SwiftUI way; each of those
`Text(...).font(.system(size:weight:design:))` calls needed the design set explicitly to `.serif`.
Also had to hunt down every already-explicit `design: .rounded` project-wide (`grep -rn "design: \.rounded"`)
since an explicit design on a `Font.system` call always wins over the inherited environment one, even
after the `.fontDesign(.serif)` modifier was added.

**Number token background**: Jake wanted it "a slightly closer to white version of the desert color, not
all the way white" - rather than pick another independent cream value, added `Color.lightened(by:)` (blends
toward white via `UIColor` RGB extraction) and defined `CatanTheme.numberTokenBackground = desert.lightened(by: 0.5)`,
so it derives from `desert` and moves with it automatically - the fix for exactly the kind of manual-sync
drift the `CatanTheme.desert`/gap-color note above flagged just one round earlier.

## Aug 21 scenic background: replacing the flat waterBackground color

Jake wanted the board's flat dark-blue backdrop (`CatanTheme.waterBackground`) replaced with real scenic
art like the reference mockup's own background painting - mountains, a pagoda, a walled island city, a
junk ship - but blended toward the cleaner, softer linework and lighting of Studio Ghibli and "Frieren:
Beyond Journey's End" rather than the reference's heavier oil-painted texture.

Generated with `generate_screen.py`, using the master reference as an image-to-image composition/style
anchor and an explicit "background environment painting only - NO UI elements, NO game board, NO
hexagons, NO cards, NO text" instruction (the live app draws all of that itself; baking any of it into the
art would fight the real HUD). One generation landed well - saved as `full-screen/v1.png`, promoted to
`approved/board-background.png` and `Assets.xcassets/board-background.imageset` - a `GeometryReader` +
`.scaledToFill()` + `.clipped()` full-bleed `Image` behind `GameView`'s whole `ZStack`, replacing the old
`CatanTheme.waterBackground.ignoresSafeArea()` fill.

**Bug caught before calling it done**: the background was only visible in the small slivers of screen
above and below the board - `BoardView` itself had its *own* opaque `CatanTheme.waterBackground` fill
inside its `GeometryReader`/`ZStack`, painted independently of `GameView`'s, which fully covered the new
art everywhere the board sat (i.e. almost the entire screen). Removed that inner fill entirely now that
there's real art behind it. Every HUD chip/panel (`BotHUDRow`, `HumanPlayerPanel`, the dice/deck chips,
Trade/Build/Turn buttons) already paints its own solid background color, so legibility over the busier art
needed no further changes - confirmed by screenshot, not just assumed.

## Aug 21 background composition tuning: mountains + ship placement

Jake liked the new background but wanted the mountain range more prominent above the board, and the junk
ship visible peeking above the top-left player card instead of buried lower on the canvas where it's
invisible behind opaque HUD panels - "don't want to overwhelm the player but want some elements to be
seen." Same constraint each time: **keep the exact art style identical**, change composition only.

Iterated with `generate_screen.py` using the *previous* generation itself as the image-to-image reference
each round (not the original master reference) - the most reliable way to hold style/palette/rendering
technique fixed while only asking for a layout change: `v1`→`v2` pushed the mountain range taller/more
central and moved the ship from lower-left toward upper-left; `v2`→`v3` tried moving the ship into the top
12% of the canvas, which mapped in-app to directly behind the first player card (only a stray mast-tip
pixel survived) - the open sky band above the top HUD row turns out to be much thinner than it looks
(barely the status-bar height); `v3`→`v4` pushed the ship into the top ~6% specifically, which finally
landed it visibly above the card without touching it - confirmed by screenshotting and reading a tight crop
of the actual top-left device region on the phone's real resolution, not just eyeballing the full painting.

**Round 2 - wide-angle framing**: comparing his phone screenshot against the master reference side by side,
Jake wanted the composition itself more like the reference's spacious, wide-angle feel - pagoda AND island
city both clearly visible flanking the board, mountains further back as a calmer distant backdrop, instead
of the tighter/closer crop `v4` had. `v4`→`v5` pulled the mountains back, shrank the pagoda/city and pushed
them toward the true edges, opened up more calm water in the middle - a real improvement, confirmed by
screenshot. That regeneration also re-centered the ship horizontally without being asked to (it had
previously been pinned left-of-center in `v4`), landing it dead behind the dynamic-island/status-bar pill
cutout at the exact horizontal center - invisible again, for a *different* reason than round 1's "too far
down" issue. `v5`→`v6` fixed the vertical placement (top 3%) but the ship was still centered and still
hidden behind the pill. `v6`→`v7` finally pinned it back to ~25% across (left-of-center, clear of the
notch) while holding every other pixel fixed via the "everything else must stay pixel-identical" phrasing -
that phrasing earns its keep across every one of these single-element tweaks; each round only asks the
model to change the one thing actually being iterated on.

**Lesson**: an image-to-image regeneration that doesn't explicitly pin down every element's position can
silently drift ones you didn't ask to change - the ship recentered itself as a side effect of two rounds
asking only about the mountains/landmarks. When chaining several single-property tweaks, worth a quick
recheck of the *other* elements too, not just the one just asked about.

**Lesson**: when composition needs to land in a *specific* visible-vs-hidden screen region, don't reason
about the source painting's percentages in the abstract - crop and inspect the actual rendered app
screenshot at that exact region before deciding a placement worked. The first attempt (`v3`, top 12%)
looked like it should have cleared the card by a comfortable margin measured against the full canvas, but
the real HUD card starts much higher up the screen than that math suggested.

## Sep 9 Rome city - regenerated on the Columbia rule

Feedback: Rome was still the roster's oddball. Nine generations with
`openai/gpt-5.4-image-2` (~$0.25 each, $2.30 total) across three rounds, plus a lot of
free deterministic pixel work between them.

**What was actually wrong, and it was not texture.** The first hypothesis was that Rome's
grain was too coarse; measured, its fill noise was sd 9.6 - the *lowest* of all 16 pieces
(Japan 26.6). The real defect was structural, and it showed up by laying all 16 pieces out
settlement-above-city: **every other civ's city is its own settlement grown.** Britannia's
keep gains turrets, Greece's porch becomes a colonnade, Japan goes one tier to three.
Rome's city was a *different building* from its settlement - a curved barrel drum against a
crisp rectangular arcade - and it was the only city in the set carrying LESS detail than its
own settlement.

**The Columbia rule.** Columbia is the clearest statement of the roster's grammar, which is
why Jake named it: its city is bigger and BOLDER, not more ornate. Same building, one more
storey, more repeated plain openings, and - the part that matters - **every interior line is
the same heavy weight as the outer outline.** There are no mouldings, no keystones, no fine
lines anywhere. That uniform stroke weight is what makes the roster read clean at 80px.

An intermediate round violated exactly that and was rejected: pilasters, keystones, dentil
blocks and recessed inner arch lines, all of which are invisible-to-muddy at board size and
forced the interior strokes thin to fit. **Adding detail and matching the roster's line
weight pull against each other; the roster resolves it by having almost no detail.**

Shipped: `K3`, a rectangular block in the settlement's own vocabulary (double cornice band,
base plinth, terracotta arch interiors ringed in black), two storeys of four arches, one
stroke weight throughout, with a small `--outer 7` pass afterwards to firm up the frame
(26px -> 33px, 3.35% -> 4.2% of the piece; the settlement's own frame is 5.90%).

### Measurement lessons, each paid for by a wrong call this session

- **"Make the border like Greece's" was unmeasurable as stated.** Greece's border is
  *thinner* than Rome's was - 2.55% of the piece against 2.97%, and 1.42x its own interior
  lines against Rome's 1.77x. What Greece actually has is room: 28% ink coverage against
  Rome's 52%. A border reads heavy because little competes with it, not because it is thick.
  Thickening Rome's further did not fix it; dropping the detail did.
- **`scaledToFit` fits the IMAGE, not the ink in it**, so anything written into
  `approved/pieces/` must be cropped to its alpha bounding box first, and every generation
  needs its chroma-key fringe inpainted (561 stray magenta pixels on the shipped one, some
  14px deep inside the silhouette, not just at the edge).
- **`pieceSizeCorrection` must be re-derived on every redraw, not carried over.** It is
  calibrated on `sqrt(width * height) / longest side`, and that metric moved 0.9410 ->
  0.9958 -> 0.9759 across this session's silhouettes purely from shape. Holding one
  on-board size therefore meant 0.98 -> 0.93 -> 0.90 in `Civilization.swift`, none of which
  is a size change.

### New tooling in `tiles/_scripts/`

- `generate_piece_gpt54.py` - `openai/gpt-5.4-image-2` is a CHAT model, so reference images
  ride in as message content parts and the result returns on `message.images`, not `data[0]`.
  `OPENROUTER_IMAGE_MODEL` switches models. **`OPENROUTER_MAX_TOKENS` is not optional in
  practice**: OpenRouter reserves a request's *maximum* possible cost (128k completion
  tokens) against the key before running it, so a call that will really cost $0.26 is refused
  `402 Payment Required` with $0.57 still sitting on the key.
- `thicken_piece_edges.py` - grows the outer silhouette border and interior lines by
  different amounts. `--smooth` builds a coverage ramp instead of dilating hard, so a
  thickened line ends the way a drawn one does.
- `shade_piece_voids.py` - repaints arch openings in a darker shade of the piece's own fill.
  Two modes because Rome's two tiers draw the same feature differently: `--mode void`
  separates black openings from black linework by SCALE (a morphological opening wider than
  the thickest stroke), `--mode interior` separates terracotta openings from the wall by
  SHAPE (an arch interior is taller than wide; the wall and cornices are wider than tall).
  Not in the shipped art - kept because the separation problem recurs.
- `thin_piece_lines.py` - the inverse. Inpaints from CLEAN fill only: sampling the nearest
  non-ink pixel is wrong, because right beside a line those pixels are the anti-aliased
  ramp, so every thinned stroke ends up wearing a muddy halo.
