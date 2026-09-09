#!/usr/bin/env python3
"""Thin a painted piece's INTERIOR detail lines while leaving its outer border
untouched.

The other two scripts here only ever grow ink (binary dilation, or an
anti-aliased coverage ramp). Nothing could take weight back off a line, so a
piece whose source art was drawn with heavy interior strokes - Rome's colosseum
arcade, where the raw art is already 56% ink before any thickening - had no way
down except regenerating it.

Method. Ink within `--rim-depth` of the silhouette edge is the outer border and
is preserved exactly; that is the weight the piece is recognised by. Everything
deeper is interior detail. For those, a distance field measured INSIDE the ink
gives each pixel its depth, and a coverage ramp erodes the shallowest `--amount`
pixels away with a soft edge rather than a stair-step. Vacated pixels take the
colour of the nearest surviving fill pixel (`distance_transform_edt`'s index
return), so an eroded band picks up the local paint rather than a flat average -
the piece keeps its texture across the repair.

Usage:
  python3 thin_piece_lines.py <piece.png> --amount 3 [--rim-depth auto]
                              [--threshold 70] [--feather 1.5]
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_opening, distance_transform_edt, generate_binary_structure


def run(path: Path, amount: float, rim_amount: float, rim_depth: float,
        min_rim: float, threshold: int, feather: float) -> None:
    im = Image.open(path).convert("RGBA")
    arr = np.asarray(im).astype(np.float64)
    rgb, alpha = arr[:, :, :3], arr[:, :, 3]
    opaque = alpha > 10
    lum = rgb.sum(axis=2) / 3
    ink = (lum < threshold) & opaque
    if ink.any():
        ink = binary_opening(ink, structure=generate_binary_structure(2, 2))

    dist_out = distance_transform_edt(opaque)          # depth into the piece
    if rim_depth <= 0:
        stroke = 2 * float(np.percentile(distance_transform_edt(ink)[ink], 95))
        rim_depth = stroke * 1.5
    border = ink & (dist_out <= rim_depth)
    interior = ink & ~border

    # Inpaint from CLEAN fill only. Sampling the nearest non-ink pixel is wrong:
    # right beside a line those pixels are the anti-aliased ramp, so an eroded
    # band gets refilled with half-dark ink colour and every thinned stroke ends
    # up wearing a muddy halo - visible as a maroon band between the black and
    # the paint. Restricting the source to pixels at true fill luminance means a
    # thinned line is replaced by actual paint.
    fill = opaque & ~ink
    fill_ref = np.percentile(lum[fill], 60) if fill.any() else 1.0
    clean_fill = fill & (lum > fill_ref * 0.85)
    if not clean_fill.any():
        clean_fill = fill

    # Depth inside the interior ink, then a ramp that removes the outer
    # `amount` pixels of every interior stroke.
    depth = distance_transform_edt(interior)
    keep = np.clip((depth - amount) / feather, 0.0, 1.0)   # 1 = stays ink, 0 = removed
    keep[border] = 1.0
    keep[~ink] = 0.0

    # Thinning the RIM is a different operation, not a symmetric one. A rim
    # pixel's nearest non-ink neighbour is usually the transparent background,
    # so eroding it the same way would eat the silhouette itself and shrink the
    # piece. Measure distance to the FILL only and erode from the inner face, so
    # the rim gets narrower while its outer edge - the piece's actual outline -
    # stays exactly where it was.
    if rim_amount > 0:
        d_fill = distance_transform_edt(~fill)
        rim_keep = np.clip((d_fill - rim_amount) / feather, 0.0, 1.0)
        keep = np.where(border, np.minimum(keep, rim_keep), keep)
        # A floor on what the rim may be reduced to. Without it the erosion eats
        # the FULL thickness wherever the drawn rim is naturally thin - the top
        # curve and the shoulders of Rome's drum - and punches holes right
        # through the outline, which the inpaint then fills with paint. The
        # result is a scatter of coral speckles sitting on the silhouette edge.
        # Ink within `min_rim` of the transparent background is never removed, so
        # the outline stays continuous however hard the rim is thinned.
        keep[ink & (dist_out <= min_rim)] = 1.0
        keep[~ink] = 0.0
    _, (iy, ix) = distance_transform_edt(~clean_fill, return_indices=True)
    nearest = rgb[iy, ix]

    removed = ink & (keep < 1.0)
    out = arr.copy()
    out[:, :, :3] = np.where(
        removed[..., None],
        rgb * keep[..., None] + nearest * (1.0 - keep[..., None]),
        rgb,
    )
    Image.fromarray(out.astype(np.uint8), "RGBA").save(path)

    new_lum = out[:, :, :3].sum(axis=2) / 3
    new_ink = (new_lum < threshold) & opaque
    print(f"{path.name}: interior -{amount}px, rim -{rim_amount}px (rim band {rim_depth:.0f}px); "
          f"ink {100*ink.sum()/opaque.sum():.1f}% -> {100*new_ink.sum()/opaque.sum():.1f}% of piece")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", type=Path)
    ap.add_argument("--amount", type=float, default=0.0, help="thin interior detail lines")
    ap.add_argument("--rim-amount", type=float, default=0.0, help="thin the outer border, from its inner face")
    ap.add_argument("--rim-depth", type=float, default=0.0)
    ap.add_argument("--min-rim", type=float, default=8.0,
                    help="ink this close to the silhouette edge is never removed")
    ap.add_argument("--threshold", type=int, default=70)
    ap.add_argument("--feather", type=float, default=1.5)
    a = ap.parse_args()
    run(a.path, a.amount, a.rim_amount, a.rim_depth, a.min_rim, a.threshold, a.feather)


if __name__ == "__main__":
    main()
