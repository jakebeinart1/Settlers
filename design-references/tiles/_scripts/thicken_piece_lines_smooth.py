#!/usr/bin/env python3
"""Uniformly thicken a painted piece's black linework WITHOUT destroying its
anti-aliasing.

Why this exists alongside thicken_piece_lines.py: that script hard-writes
`(0,0,0)` into every dilated pixel, so the widened line ends with a stair-step
edge. Measured on Rome's settlement, its anti-aliased edge pixels fell from
38.8% of the piece to 22.2% after one pass - which is exactly the "crunchy, not
clean" look Jake rejected. The heavier the radius, the worse it gets, so it is
the wrong tool for a big thickening.

Method: build a signed distance field from the ink mask, then set each pixel's
INK COVERAGE as a smooth ramp - fully black inside `radius`, fading to the
original colour across one pixel at the boundary - and alpha-composite black
over the artwork at that coverage. The line grows by exactly `radius` pixels
with a soft edge, so it still reads as drawn rather than as a stencil. Growth is
masked by the piece's own alpha, so the outer silhouette never moves.

Usage:
  python3 thicken_piece_lines_smooth.py <piece.png> <radius_px> [--threshold 70] [--feather 1.2]
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_opening, distance_transform_edt, generate_binary_structure


def run(path: Path, radius: float, threshold: int, feather: float) -> None:
    im = Image.open(path).convert("RGBA")
    arr = np.asarray(im).astype(np.float64)
    rgb, alpha = arr[:, :, :3], arr[:, :, 3]
    opaque = alpha > 10
    dark = (rgb.sum(axis=2) / 3 < threshold) & opaque
    if dark.any():
        dark = binary_opening(dark, structure=generate_binary_structure(2, 2))

    # Distance OUTWARD from the ink, in pixels.
    dist = distance_transform_edt(~dark)
    # Coverage 1 inside the grown line, ramping to 0 over `feather` pixels.
    coverage = np.clip((radius + feather - dist) / feather, 0.0, 1.0)
    coverage[dark] = 1.0
    coverage[~opaque] = 0.0

    out = arr.copy()
    out[:, :, :3] = rgb * (1.0 - coverage[..., None])   # composite black over
    Image.fromarray(out.astype(np.uint8), "RGBA").save(path)

    lum = out[:, :, :3].sum(axis=2) / 3
    ink = (lum < threshold) & opaque
    mid = opaque & (lum >= threshold) & (lum <= 110)
    print(f"{path.name}: radius {radius}, ink {100*dark.sum()/opaque.sum():.1f}% -> "
          f"{100*ink.sum()/opaque.sum():.1f}% of piece, soft edge pixels {100*mid.sum()/opaque.sum():.1f}%")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", type=Path)
    ap.add_argument("radius", type=float)
    ap.add_argument("--threshold", type=int, default=70)
    ap.add_argument("--feather", type=float, default=1.2)
    run(*[(lambda a: (a.path, a.radius, a.threshold, a.feather))(ap.parse_args())][0])


if __name__ == "__main__":
    main()
