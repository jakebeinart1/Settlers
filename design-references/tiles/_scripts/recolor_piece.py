#!/usr/bin/env python3
"""Recolor an existing painted piece PNG to a new target material color while
keeping its shape, shading, and linework byte-for-byte identical in
everything except hue - a duotone remap (black -> target color) driven by
each opaque pixel's own perceptual luminance, not a fresh AI generation.

Why duotone instead of re-generating via generate_icon.py: a fresh generation
risks drifting the silhouette/detail (see STATUS.md's "restyle the original"
history of re-rolls), and the ask here is explicitly "the same piece, just a
different material color" - a per-pixel luminance-preserving color remap is
the deterministic way to guarantee that, at zero OpenRouter spend.

For each opaque pixel: convert to grayscale luminance L (Rec. 601 weights),
then output = lerp(black, target_rgb, L). This keeps existing black outline
ink at (or near) black, keeps existing highlights bright, and recolors every
midtone toward the target hue - i.e. it's exactly what the original
grayscale-ramp-into-target-color duotone effect looks like, so a piece that
was "blue with shading" becomes "target-colored with the same shading."

Usage:
  python3 recolor_piece.py <in.png> <out.png> <R> <G> <B> [floor] [ink_cutoff]

  R/G/B are 0-255 ints for the target color. `floor` (default 0.0) is the
  minimum normalized brightness given to any non-ink pixel - raise it toward
  1.0 to push a piece whose original shading sits mostly in the dark/mid
  range (e.g. a piece painted in a dark material) up into a bright/white
  range instead of reproducing it as a dark-to-mid duotone. `ink_cutoff`
  (default 0.0) is the luma below which a pixel is treated as outline/detail
  ink and forced to pure black regardless of `floor`, so linework stays
  crisp even when the fill is pushed bright. Both default to 0, which
  reproduces the original plain duotone (every pixel from black at luma=0 up
  to the full target color at luma=1).

  A high `floor` compresses most of the piece's luma range into a narrow
  band near white, which also stretches the source art's fine paper-grain
  noise into visible blotches (measured on columbia-city: readable "painted
  white building" became a mottled/patchy mess at floor=0.8). `smooth`
  (default 0, pixels) Gaussian-blurs the luma used for the *fill* remap only
  - not the ink mask, so outline/detail lines stay exactly as crisp as the
  source - which removes that per-pixel grain before it gets stretched,
  while the real shading gradient (a dome's curve, a wall's shadow side)
  survives since it varies over a much larger area than the blur radius.

  A plain darkness threshold cannot tell "thin outline/detail stroke" apart
  from "a large but genuinely dark shadow-side fill region" - both are just
  "dark pixels" to it. Measured on Columbia: a threshold loose enough to
  paint the settlement's real detail strokes black also painted its whole
  dark shadow-side base solid black (39% of the piece - too much, "needs to
  be more white"), while a threshold strict enough to avoid that missed the
  city's actual window/column divider strokes entirely (they sit in a
  mid-luma range, not near-black) - "no border," "needs more black lines."
  Both are shape mismatches, not a threshold-tuning problem, so ink
  detection is edge-based instead: a Sobel gradient magnitude on `smooth`-
  blurred luma finds actual lines (a real stroke is a sharp luma transition
  against its neighbors, regardless of how dark it is in absolute terms) OR
  the pixel is very close to true black (`ink_cutoff`, a small backstop for
  genuinely solid ink that a gradient alone might miss, e.g. deep in a
  uniformly-black doorway). A uniform dark fill region has near-zero
  internal gradient, so it correctly falls to `floor`-remapped fill instead
  of solid black, while a thin divider stroke - a sharp transition - is
  caught either way. `line_dilate` (pixels) grows the detected lines inward
  after detection, for "needs MORE black lines" specifically: strokes found
  correctly but read as too thin/faint at real in-game (much smaller) size.

  `ink_threshold` (0-255 luma scale, default 20) is the near-black backstop.
  `edge_threshold` (0-1 scale, default 0.12) is the minimum blurred-luma
  Sobel gradient magnitude to count as a line. Both combine with a binary
  opening (`scipy.ndimage`, 8-connected) to drop isolated noise, matching
  the same despeckle `thicken_piece_lines.py` already uses for its own,
  differently-computed ink mask.

  Neither threshold reliably reproduces the OUTER silhouette border, though,
  on a piece whose shadow-side fill sits at nearly the same luma as its own
  outline ink (measured on columbia-settlement: no single global cutoff drew
  a solid border without either erasing it or also blackening the whole
  shadow-side facade - the two are barely distinguishable by tone alone in
  that source file). Fixed by not inferring the outer border from color at
  all: `border_px` (pixels, default 0 - disabled) forces a fixed-width ring
  along the shape's own alpha boundary to pure black outright (erode the
  opaque mask by `border_px`, ring = opaque minus the eroded mask), the same
  guarantee this art style's original outline already gestures at - a
  border drawn right along the silhouette edge - just made unconditional
  instead of dependent on that pixel's own color happening to be dark
  enough. Interior detail lines (window/column dividers, doorways) still
  come from the edge/threshold detection above, since those aren't at the
  alpha boundary and have no equivalent shortcut.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy.ndimage import binary_dilation, binary_erosion, binary_opening, generate_binary_structure, sobel


def main():
    if len(sys.argv) not in range(6, 14):
        print(
            "usage: recolor_piece.py <in.png> <out.png> <R> <G> <B> [floor] [ink_cutoff] "
            "[smooth] [ink_threshold] [edge_threshold] [line_dilate] [border_px]",
            file=sys.stderr,
        )
        sys.exit(1)

    in_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    target = np.array([int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])], dtype=np.float64)
    floor = float(sys.argv[6]) if len(sys.argv) >= 7 else 0.0
    ink_cutoff = float(sys.argv[7]) if len(sys.argv) >= 8 else 0.0
    smooth = float(sys.argv[8]) if len(sys.argv) >= 9 else 0.0
    ink_threshold = float(sys.argv[9]) if len(sys.argv) >= 10 else 20.0
    edge_threshold = float(sys.argv[10]) if len(sys.argv) >= 11 else 0.12
    line_dilate = int(sys.argv[11]) if len(sys.argv) >= 12 else 0
    border_px = int(sys.argv[12]) if len(sys.argv) >= 13 else 0

    im = Image.open(in_path).convert("RGBA")
    arr = np.array(im).astype(np.float64)
    rgb = arr[..., :3]
    alpha = arr[..., 3]
    opaque = alpha > 10

    # Rec. 601 luma, normalized 0..1, per-pixel (preserves the existing
    # shading gradient rather than flattening to one flat color).
    luma = (rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114) / 255.0

    # Alpha-weighted blur, so transparent background doesn't bleed a dark
    # fringe into the shape's edge. Both the fill remap AND ink detection
    # read from this blurred luma - a genuine outline/detail stroke is
    # several pixels wide and survives a small blur, while isolated
    # single-pixel grain specks get averaged into their bright neighbors and
    # stop registering as either a threshold hit or a gradient spike.
    fill_luma = luma
    if smooth > 0:
        opaque_f = opaque.astype(np.float64)
        weighted = Image.fromarray((luma * opaque_f * 255).astype(np.uint8))
        weight = Image.fromarray((opaque_f * 255).astype(np.uint8))
        weighted = np.array(weighted.filter(ImageFilter.GaussianBlur(smooth)), dtype=np.float64)
        weight = np.array(weight.filter(ImageFilter.GaussianBlur(smooth)), dtype=np.float64)
        fill_luma = np.where(weight > 1, weighted / np.maximum(weight, 1e-6), luma)

    # Ink detection reads RAW (unblurred) luma, not fill_luma - a genuine
    # border/outline stroke is itself a roughly flat run of near-black a few
    # pixels wide, and a `smooth` blur wide enough to fix fill-noise
    # blotchiness (see above) is wide enough to dilute that stroke's own
    # interior toward the brighter pixels around it before ink detection
    # ever sees it (measured: the outer silhouette border came out faint
    # gray instead of solid black once ink detection read blurred luma).
    # Grain noise is handled here by a stronger opening (2 iterations)
    # instead of a pre-blur.
    gradient_x = sobel(luma, axis=1)
    gradient_y = sobel(luma, axis=0)
    gradient_magnitude = np.hypot(gradient_x, gradient_y) / 4.0  # sobel kernel sums to 4

    is_ink = np.zeros(luma.shape, dtype=bool)
    if ink_cutoff > 0:
        is_ink = ((gradient_magnitude > edge_threshold) | (luma * 255 < ink_threshold)) & opaque
        if is_ink.any():
            is_ink = binary_opening(is_ink, structure=generate_binary_structure(2, 2), iterations=2)
        if line_dilate > 0 and is_ink.any():
            is_ink = binary_dilation(is_ink, iterations=line_dilate) & opaque

    if border_px > 0:
        eroded = binary_erosion(opaque, iterations=border_px, border_value=0)
        border_ring = opaque & ~eroded
        is_ink = is_ink | border_ring

    # Below ink_cutoff: outline/detail linework, forced pure black. Above it:
    # remapped from [ink_cutoff, 1] to [floor, 1] before scaling by target -
    # so raising `floor` brightens the whole fill without touching the ink.
    normalized = np.clip((fill_luma - ink_cutoff) / max(1e-6, 1.0 - ink_cutoff), 0.0, 1.0)
    out_luma = np.where(is_ink, 0.0, floor + (1.0 - floor) * normalized)
    out_luma = out_luma[..., None]

    recolored = target[None, None, :] * out_luma  # lerp(black, target, out_luma)
    recolored = np.clip(recolored, 0, 255)

    out = arr.copy()
    opaque_mask = alpha > 10  # leave fully-transparent background pixels untouched
    out[..., :3] = np.where(opaque_mask[..., None], recolored, rgb)

    out_im = Image.fromarray(out.astype(np.uint8), mode="RGBA")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_im.save(out_path)
    print(f"saved: {out_path}")


if __name__ == "__main__":
    main()
