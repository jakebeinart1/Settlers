#!/usr/bin/env python3
"""Find a tight, low-variance sub-region within an existing painted tile
texture and crop it out - used instead of regenerating tiles from scratch
when the *whole* source canvas has too much visible brushstroke-to-
brushstroke color variation ("paint splotches") for `TileDrawing.drawTile`
to read as one solid resource color once it's stretched into a hex's
bounding box (see design-references/STATUS.md, "Aug 21 bugfix/redesign
pass").

Scores every window of a given size by a mix of local color std-dev and
Sobel-style edge magnitude (weighted higher - a straight brushstroke edge
crossing the window reads as a seam even when the raw color std-dev on
either side of it is low), and keeps the lowest-scoring one: the most
visually uniform patch in the source image.

Requires numpy (not a dependency of the other scripts in this folder):
  python3 -m pip install --break-system-packages numpy

Usage:
  python3 find_uniform_tile_crop.py <source.png> <out.png> [--win 220] [--stride 12]
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image


def find_best_crop(path: Path, win: int, stride: int) -> tuple[int, int, int]:
    gray = np.asarray(Image.open(path).convert("L")).astype(np.float32)
    arr = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    height, width = gray.shape
    gy, gx = np.gradient(gray)
    edge_mag = np.sqrt(gx**2 + gy**2)

    best_score, best_x, best_y = None, 0, 0
    for y in range(0, height - win, stride):
        for x in range(0, width - win, stride):
            patch = arr[y:y + win, x:x + win, :]
            std = patch.std(axis=(0, 1)).mean()
            edge_patch = edge_mag[y:y + win, x:x + win]
            edge_score = edge_patch.mean() + edge_patch.max() * 0.05
            score = std * 0.6 + edge_score * 2.5
            if best_score is None or score < best_score:
                best_score, best_x, best_y = score, x, y
    return best_x, best_y, win


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--win", type=int, default=220)
    parser.add_argument("--stride", type=int, default=12)
    args = parser.parse_args()

    x, y, win = find_best_crop(args.source, args.win, args.stride)
    print(f"best crop: ({x},{y},{x + win},{y + win})")
    im = Image.open(args.source).convert("RGB")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    im.crop((x, y, x + win, y + win)).save(args.out)
    print(f"saved: {args.out}")


if __name__ == "__main__":
    main()
