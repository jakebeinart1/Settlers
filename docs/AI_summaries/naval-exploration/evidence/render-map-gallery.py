"""Render actual engine-exported worlds; this is analysis, not app artwork.

Requires Matplotlib 3.7.2. Run from any directory; inputs live beside this file.
"""

import json
import math
from pathlib import Path
from typing import Any

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, Patch, RegularPolygon

HERE = Path(__file__).resolve().parent
FAMILIES = ["archipelago", "peninsula", "twinIslands"]
TITLES = [
    "Archipelago · 7 / 7 / 7 / 7",
    "Peninsula · 14 / 7 / 4 / 3",
    "Twin Islands · 11 / 11 / 3 / 3",
]
COLORS = {
    "brick": "#b75430",
    "lumber": "#32604a",
    "ore": "#78848b",
    "grain": "#d6ad47",
    "wool": "#a3b66a",
    "desert": "#b79d69",
    "sea": "#173b50",
    "resourceChoice": "#367a73",
}


def center(coordinate: dict[str, int]) -> tuple[float, float]:
    """Match the app's axial projection, with its downward screen axis inverted."""
    q, r = coordinate["q"], coordinate["r"]
    return math.sqrt(3) * (q + r / 2), -1.5 * r


def material(kind: str) -> str:
    if "Resource." in kind:
        return kind.split("Resource.")[1].rstrip(")")
    return kind


def draw_tile(axis: Any, tile: dict[str, Any]) -> None:
    x, y = center(tile)
    kind = material(tile["kind"])
    land = kind != "sea"
    axis.add_patch(
        RegularPolygon(
            (x, y),
            6,
            radius=0.985,
            facecolor=COLORS[kind],
            edgecolor="#edcf8a" if land else "#285369",
            linewidth=0.65 if land else 0.20,
            zorder=2 if land else 1,
        )
    )
    if tile["number"] is not None:
        axis.add_patch(Circle((x, y), 0.34, color="#f2dfba", zorder=3))
        axis.text(
            x,
            y,
            str(tile["number"]),
            ha="center",
            va="center",
            fontsize=5.6,
            color="#a53329" if tile["number"] in [6, 8] else "#23333c",
            zorder=4,
        )
    if kind == "resourceChoice":
        for index, name in enumerate(["brick", "lumber", "ore", "grain", "wool"]):
            angle = index * math.tau / 5 + math.pi / 2
            axis.add_patch(
                Circle(
                    (x + math.cos(angle) * 0.67, y + math.sin(angle) * 0.67),
                    0.09,
                    facecolor=COLORS[name],
                    edgecolor="#fff0c7",
                    linewidth=0.35,
                    zorder=4,
                )
            )


def vertex(coordinates: list[dict[str, int]]) -> tuple[float, float]:
    points = [center(coordinate) for coordinate in coordinates]
    return tuple(
        sum(point[index] for point in points) / len(points) for index in [0, 1]
    )


def draw_port(axis: Any, port: dict[str, Any], sea: set[tuple[int, int]]) -> None:
    first = port["vertexA"]["touchingTiles"]
    second = port["vertexB"]["touchingTiles"]
    a, b = vertex(first), vertex(second)
    x, y = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    shared = {(c["q"], c["r"]) for c in first} & {(c["q"], c["r"]) for c in second}
    q, r = next(iter(shared & sea))
    sx, sy = center({"q": q, "r": r})
    distance = math.hypot(sx - x, sy - y)
    x, y = x + 0.52 * (sx - x) / distance, y + 0.52 * (sy - y) / distance
    resource = port["kind"].get("resource", {}).get("_0")
    axis.add_patch(
        Circle(
            (x, y),
            0.30,
            facecolor=COLORS[resource] if resource else "#f0efe5",
            edgecolor="#f6e5b6",
            linewidth=0.6,
            zorder=5,
        )
    )
    axis.text(
        x,
        y,
        "2" if resource else "3",
        ha="center",
        va="center",
        fontsize=4.5,
        color="#122d3c" if not resource else "white",
        zorder=6,
    )


def draw_world(axis: Any, family: str, seed: int) -> None:
    path = HERE / "map-samples" / f"{family}-{seed}.json"
    world = json.loads(path.read_text())
    sea = {(t["q"], t["r"]) for t in world["tiles"] if t["island"] is None}
    for tile in world["tiles"]:
        draw_tile(axis, tile)
    for port in world["board"]["ports"]:
        draw_port(axis, port, sea)
    axis.set_aspect("equal")
    axis.set_xlim(-13.5, 13.5)
    axis.set_ylim(-11.8, 11.8)
    axis.axis("off")
    axis.set_title(
        f"Seed {seed}", fontsize=11, fontweight="bold", color="#183744", pad=6
    )


def main() -> None:
    plt.rcParams.update({"font.family": "DejaVu Sans", "figure.facecolor": "#f3eee2"})
    figure, axes = plt.subplots(3, 5, figsize=(16, 11.1))
    for row, family in enumerate(FAMILIES):
        for seed in range(5):
            draw_world(axes[row, seed], family, seed)
    legend = [
        Patch(
            facecolor=color, label=name.replace("resourceChoice", "Choose one resource")
        )
        for name, color in COLORS.items()
    ]
    figure.legend(
        handles=legend,
        loc="lower center",
        ncol=8,
        frameon=False,
        fontsize=8,
        bbox_to_anchor=(0.5, 0.032),
    )
    figure.suptitle(
        "Voyages | 15 seeded worlds",
        fontsize=23,
        fontweight="bold",
        y=0.978,
        color="#173b50",
    )
    figure.text(
        0.5,
        0.940,
        "Same 169-hex envelope · 19-hex home · 28 overseas land hexes · 9 harbors",
        ha="center",
        fontsize=10,
        color="#49616b",
    )
    figure.text(
        0.5,
        0.014,
        "Engine a15d72e · map version 1 · seeds 0–4 · full generator view; "
        "gameplay mist conceals overseas terrain",
        ha="center",
        fontsize=8,
        color="#49616b",
    )
    figure.subplots_adjust(
        left=0.045, right=0.985, bottom=0.084, top=0.91, wspace=0.035, hspace=0.11
    )
    for row, title in enumerate(TITLES):
        bounds = axes[row, 0].get_position()
        figure.text(
            0.026,
            (bounds.y0 + bounds.y1) / 2,
            title,
            rotation=90,
            fontsize=11,
            fontweight="bold",
            color="#183744",
            ha="center",
            va="center",
        )
    temporary = HERE / "map-gallery.rendering.png"
    figure.savefig(temporary, dpi=190)
    temporary.replace(HERE / "map-gallery.png")
    plt.close(figure)


if __name__ == "__main__":
    main()
