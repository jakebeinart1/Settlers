#!/usr/bin/env python3
"""Thicken the black outline/detail lines of a painted piece PNG in place,
without touching its silhouette size or any non-black color.

Finds near-black pixels within the piece's own alpha shape (the outer
silhouette border AND interior detail lines - doorways, arches, etc. - are
all the same "black ink" in this art style, so one operation covers both),
dilates that mask inward by `radius` pixels using a disk structuring
element, and recolors the newly-covered pixels black. Dilating is
intersected with the original alpha mask, so growth can only eat into the
piece's own colored area, never bleed outside the silhouette into the
transparent background - the shape's outer edge doesn't move, the stroke
drawn along it just gets wider.

Usage:
  python3 thicken_piece_lines.py <piece.png> <radius_px> [--threshold 70]
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_dilation, binary_opening, generate_binary_structure, iterate_structure


def thicken(path: Path, radius: int, threshold: int) -> None:
    im = Image.open(path).convert("RGBA")
    arr = np.asarray(im).astype(np.uint8)
    rgb = arr[:, :, :3].astype(np.int32)
    alpha = arr[:, :, 3]

    is_opaque = alpha > 10
    is_dark = rgb.sum(axis=2) < threshold * 3
    black_mask = is_dark & is_opaque

    # Opening (erode then dilate) with a small fixed structure first -
    # removes lone speckle noise (a few near-black anti-aliased pixels
    # inside a shaded area that happen to cross the darkness threshold,
    # not real linework) before growing anything, so growth only amplifies
    # actual connected stroke lines, not scattered specks into blobs.
    if black_mask.any():
        black_mask = binary_opening(black_mask, structure=generate_binary_structure(2, 2))

    if radius > 0:
        structure = iterate_structure(generate_binary_structure(2, 2), radius)
        dilated = binary_dilation(black_mask, structure=structure)
        dilated &= is_opaque
    else:
        dilated = black_mask

    out = arr.copy()
    out[dilated, 0] = 0
    out[dilated, 1] = 0
    out[dilated, 2] = 0
    # Alpha untouched - only recoloring existing opaque pixels, never
    # extending the shape's own silhouette.

    added_pct = 100 * (dilated.sum() - black_mask.sum()) / max(1, is_opaque.sum())
    print(f"{path.name}: black {100*black_mask.sum()/max(1,is_opaque.sum()):.1f}% -> "
          f"{100*dilated.sum()/max(1,is_opaque.sum()):.1f}% of piece (+{added_pct:.1f}pp), radius={radius}")

    Image.fromarray(out, "RGBA").save(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument("radius", type=int)
    parser.add_argument("--threshold", type=int, default=70)
    args = parser.parse_args()
    thicken(args.path, args.radius, args.threshold)


if __name__ == "__main__":
    main()
