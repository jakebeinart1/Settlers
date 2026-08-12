# Settlers — settlement/city piece export for Claude Design

Scope: **just the building pieces** (settlements and cities), not the board,
HUD, or any other screen. This is a narrower, focused hand-off — a separate,
fuller `ClaudeDesignExport/` (whole UI: board, HUD, popups) already exists
in this repo for later, once buildings have a direction.

This is a native **SwiftUI (iOS)** codebase, not web — Claude Design can't
render or edit these files live. Treat them as reference for the current
visual language, and hand back either mockups to react to or a written spec
(shapes, colors, proportions) that a SwiftUI implementer (e.g. Claude Code)
can apply to the real files in `Settlers/Views/Board/` and `Settlers/Theme/`.

## What's here

- `CivilizationPieceShapes.swift` — the actual building silhouettes: one
  `Shape` per civilization (Egypt pyramid, Aztec ziggurat, Greece temple
  front, Britannia castle keep). This is the part most worth redesigning —
  currently flat geometric silhouettes (triangles/rects), no illustration.
- `CivilizationBadge.swift` — wraps a piece shape into the actual on-board
  marker: fills it with the civilization's color, adds a thin black outline,
  and (for a city) an added white ring so the settlement → city upgrade is
  visible at a glance. This is what's actually placed at board corners.
- `Civilization.swift` — the four civilizations' names, generals, and fixed
  accent colors (the fill color each piece shape uses). Colors are locked
  per civilization, not user-customizable.

## Current design constraints worth knowing

- Pieces render **small** (roughly 20–40pt on screen) and must stay
  legible/distinguishable from across a hex board at that size — this is
  why past attempts at detailed isometric/illustrated buildings were
  dropped in favor of bold flat silhouettes.
- No "up" orientation issues to worry about (unlike roads, which run at
  several angles on a hex grid and are out of scope here) — buildings sit
  at fixed board vertices and can have a fixed orientation.
- Flat fill + thin black outline matches the rest of the board's style
  (straight borders, no isometric shading, no gradients).
- Four distinct silhouettes, four distinct fixed colors:
  - Britannia (medieval) — purple, castle keep
  - Greece — white/grey marble, temple front
  - Egypt — sandstone, pyramid
  - Aztec — slate blue, ziggurat

## Not included (deliberately)

The hex board, tiles, roads, HUD, and every other screen — see the
sibling `ClaudeDesignExport/` folder for those, once it's time to take the
whole board into design.
