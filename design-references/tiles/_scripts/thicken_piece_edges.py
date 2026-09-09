#!/usr/bin/env python3
"""Thicken a painted piece's OUTER silhouette border and its INTERIOR detail
lines by DIFFERENT amounts.

Why this exists alongside thicken_piece_lines.py: that script grows every
near-black pixel by one radius, which is right when a piece has a few wide
openings (Japan's doorway) and wrong when it has many narrow ones. Rome's
arcade has 8-10 arch outlines per piece, so the radius that gives the outer
border the roster's weight simultaneously fattens every arch outline until
the arcade reads as a black band with slivers of terracotta in it. The two
kinds of line want different weights.

Method: `dist_out` is each opaque pixel's distance to the nearest transparent
pixel, so ink lying within `--rim-depth` of the silhouette edge is the outer
border and everything deeper is interior detail. The border mask is dilated by
`--outer`, all ink by `--inner`, and the union is intersected with the original
alpha - so growth only ever eats into the piece's own colour, and the outer
edge of the silhouette never moves.

Usage:
  python3 thicken_piece_edges.py <piece.png> --outer 15 --inner 4 [--rim-depth auto]
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import (binary_dilation, binary_opening, distance_transform_edt,
                           generate_binary_structure, iterate_structure)


def disk(radius: int):
    return iterate_structure(generate_binary_structure(2, 2), radius)


def stroke_width(dark: np.ndarray) -> float:
    """Typical ink width = twice the 95th-percentile distance-to-edge inside it."""
    if not dark.any():
        return 0.0
    return 2 * float(np.percentile(distance_transform_edt(dark)[dark], 95))


def run(path: Path, outer: int, inner: int, rim_depth: float, threshold: int,
        smooth: bool, feather: float) -> None:
    im = Image.open(path).convert("RGBA")
    arr = np.asarray(im).astype(np.uint8)
    alpha = arr[:, :, 3]
    opaque = alpha > 10
    dark = (arr[:, :, :3].astype(np.int32).sum(axis=2) < threshold * 3) & opaque

    # Drop speckle before growing anything, same reasoning as thicken_piece_lines.
    if dark.any():
        dark = binary_opening(dark, structure=generate_binary_structure(2, 2))

    raw = stroke_width(dark)
    if rim_depth <= 0:
        # The outer border ring is ink lying within roughly its own width of the
        # silhouette edge; 1.5x gives margin for the hand-drawn wobble.
        rim_depth = raw * 1.5

    dist_out = distance_transform_edt(opaque)
    border = dark & (dist_out <= rim_depth)

    if smooth:
        # Anti-aliased growth. Hard binary dilation leaves a stair-stepped edge -
        # measured on Rome, one pass cut anti-aliased edge pixels from 38.8% of the
        # piece to 22.2%, which reads as "crunchy". Instead, build a distance field
        # out from each mask and turn it into an INK COVERAGE ramp: solid inside the
        # radius, fading to the artwork across `feather` pixels. Black is then
        # alpha-composited at that coverage, so a thickened line ends the way a drawn
        # one does. The two masks are combined by taking the greater coverage.
        cov = np.zeros(dark.shape, dtype=np.float64)
        if inner > 0:
            cov = np.clip((inner + feather - distance_transform_edt(~dark)) / feather, 0.0, 1.0)
        if outer > 0 and border.any():
            cov_o = np.clip((outer + feather - distance_transform_edt(~border)) / feather, 0.0, 1.0)
            cov = np.maximum(cov, cov_o)
        cov[dark] = 1.0
        cov[~opaque] = 0.0
        out = arr.astype(np.float64)
        out[:, :, :3] *= (1.0 - cov[..., None])
        out = out.astype(np.uint8)
        grown = cov > 0.5
    else:
        grown = binary_dilation(dark, structure=disk(inner)) if inner > 0 else dark
        if outer > 0:
            grown = grown | binary_dilation(border, structure=disk(outer))
        grown &= opaque
        out = arr.copy()
        out[grown, 0] = out[grown, 1] = out[grown, 2] = 0

    Image.fromarray(out, "RGBA").save(path)

    bbox = Image.fromarray(out, "RGBA").split()[3].getbbox()
    w = bbox[2] - bbox[0]
    lum = out[:, :, :3].astype(np.int32).sum(axis=2) / 3
    soft = opaque & (lum >= threshold) & (lum <= 110)
    print(f"{path.name}: raw stroke {raw:.0f}px ({100*raw/w:.2f}%) -> "
          f"outer +{outer}, inner +{inner}, {'SMOOTH' if smooth else 'hard'}; "
          f"ink {100*dark.sum()/opaque.sum():.1f}% -> {100*grown.sum()/opaque.sum():.1f}%, "
          f"soft edge pixels {100*soft.sum()/opaque.sum():.1f}%")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", type=Path)
    ap.add_argument("--outer", type=int, required=True)
    ap.add_argument("--inner", type=int, required=True)
    ap.add_argument("--rim-depth", type=float, default=0.0, help="0 = derive from the piece's own stroke width")
    ap.add_argument("--threshold", type=int, default=70)
    ap.add_argument("--smooth", action="store_true",
                    help="anti-aliased growth instead of hard binary dilation")
    ap.add_argument("--feather", type=float, default=1.5,
                    help="width in px of the smooth mode's edge ramp")
    args = ap.parse_args()
    run(args.path, args.outer, args.inner, args.rim_depth, args.threshold,
        args.smooth, args.feather)


if __name__ == "__main__":
    main()
