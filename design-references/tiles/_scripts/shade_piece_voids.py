#!/usr/bin/env python3
"""Repaint a piece's arch OPENINGS in a darker shade of its own fill colour, so
the arcade reads as depth rather than as holes punched through the wall.

The two Rome pieces draw the same feature two different ways, so this handles
both and the caller says which:

  --mode void      the opening is painted black (Rome's city). Black openings
                   and black linework are the same colour, so nothing in the
                   pixel values separates them - what separates them is SCALE.
                   A morphological opening at `--radius` erases every stroke and
                   keeps only regions that are genuinely broad. Eroding that by
                   `--rim` leaves a black ring of exactly that width around each
                   opening, so the arch still reads as drawn.

  --mode interior  the opening is painted the same terracotta as the wall
                   (Rome's settlement), already ringed by its own black arch
                   outline. Here the openings are separate connected components
                   of the fill, and the discriminator is shape: an arch interior
                   is taller than it is wide, where the wall itself and the
                   cornice strips are wider than tall.

The shade is derived from the piece's own measured fill, never typed in, so a
retint upstream carries through. The fill's own grain is reproduced on top of
it: a perfectly flat opening beside a textured wall reads as a printing error
at board size.

Usage:
  python3 shade_piece_voids.py <in.png> <out.png> --mode void --darkness 0.45
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import (binary_opening, distance_transform_edt, find_objects,
                           generate_binary_structure, iterate_structure, label)

CONNECTIVITY = generate_binary_structure(2, 2)


def disk(radius: int):
    return iterate_structure(CONNECTIVITY, radius)


def masks(arr: np.ndarray):
    opaque = arr[:, :, 3] > 10
    lum = arr[:, :, :3].mean(axis=2)
    fill_ref = float(np.percentile(lum[opaque], 60))
    ink = binary_opening((lum < max(60.0, fill_ref * 0.45)) & opaque, structure=CONNECTIVITY)
    clean_fill = opaque & ~ink & (lum > fill_ref * 0.85)
    return opaque, lum, ink, clean_fill


def void_coverage(ink: np.ndarray, radius: int, rim: float, feather: float) -> np.ndarray:
    voids = binary_opening(ink, structure=disk(radius))
    if not voids.any():
        raise SystemExit(f"no opening wider than {2 * radius}px found")
    cov = np.clip((distance_transform_edt(voids) - rim) / feather, 0.0, 1.0)
    cov[~voids] = 0.0
    return cov


def interior_coverage(fill: np.ndarray) -> np.ndarray:
    lab, n = label(fill, structure=CONNECTIVITY)
    if n < 2:
        raise SystemExit("fill is a single region - no enclosed arch interiors")
    areas = np.bincount(lab.ravel())
    areas[0] = 0
    wall = int(areas.argmax())
    cov = np.zeros(fill.shape, float)
    for i, sl in enumerate(find_objects(lab), start=1):
        if i == wall or sl is None:
            continue
        height = sl[0].stop - sl[0].start
        width = sl[1].stop - sl[1].start
        # Taller than wide: an arch. Wider than tall: a cornice strip.
        if height > width and areas[i] > 0.01 * fill.size:
            cov[lab == i] = 1.0
    if not cov.any():
        raise SystemExit("no taller-than-wide fill region found")
    return cov


def run(src: Path, dst: Path, mode: str, darkness: float, radius: int, rim: float,
        feather: float) -> None:
    arr = np.asarray(Image.open(src).convert("RGBA")).astype(float)
    opaque, lum, ink, clean_fill = masks(arr)

    if mode == "void":
        cov = void_coverage(ink, radius, rim, feather)
    else:
        cov = interior_coverage(opaque & ~ink)

    base = arr[:, :, :3][clean_fill].mean(axis=0)
    shade = base * darkness
    # Match the wall's own grain so the opening is textured like everything else.
    noise_sd = float(np.std(lum[clean_fill])) * darkness
    grain = np.random.default_rng(0).normal(0.0, noise_sd, size=lum.shape)[..., None]
    target = np.clip(shade[None, None, :] + grain, 0, 255)

    arr[:, :, :3] = arr[:, :, :3] * (1 - cov[..., None]) + target * cov[..., None]
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(dst)
    print(f"{dst.name}: mode={mode} repainted={cov.mean() * 100:.1f}% of frame "
          f"shade=#{int(shade[0]):02X}{int(shade[1]):02X}{int(shade[2]):02X}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("dst", type=Path)
    ap.add_argument("--mode", choices=("void", "interior"), required=True)
    ap.add_argument("--darkness", type=float, default=0.45,
                    help="fraction of the piece's own fill colour; 0=black, 1=wall")
    ap.add_argument("--radius", type=int, default=35,
                    help="void mode: opening radius in px; must exceed half the widest stroke")
    ap.add_argument("--rim", type=float, default=10.0,
                    help="void mode: px of black outline kept around each opening")
    ap.add_argument("--feather", type=float, default=2.0)
    a = ap.parse_args()
    run(a.src, a.dst, a.mode, a.darkness, a.radius, a.rim, a.feather)
