# Settlers — UI export for Claude Design

This folder is a drag-and-drop bundle of the current UI layer from a native
**SwiftUI (iOS)** Catan-style board game called "Settlers." It is **not** a
web codebase — Claude Design can't render or edit SwiftUI live the way it
does React/HTML. Treat these files as reference for:

- current visual language (colors, spacing, corner radii, typography)
- component structure and naming (so redesign ideas map cleanly back)
- layout relationships between screens (board, HUD, popups)

Any redesign should come back as: (a) mockups/comps to react to, and/or
(b) a written spec (colors, type scale, spacing tokens, component-by-component
changes) that a SwiftUI implementer (e.g. Claude Code) can apply to the real
files in `Settlers/Views/`.

## What's here

- `Views/` — top-level screens and popups (main menu, game view, trade,
  build, dev cards, discard, end game, settings, HUD, resource chip, buttons)
- `Views/Board/` — the hex board itself (tiles, hex geometry, civilization
  badges/piece shapes)
- `Assets.xcassets/` — the current asset catalog (icon, accent color)

## Known UI areas worth fresh eyes on

- `PlayerHUDView.swift` — player resource/status HUD
- `TradePopupView.swift` — trade flow UI (recently reworked)
- `Board/TileView.swift`, `Board/BoardView.swift` — hex board rendering
- `Board/CivilizationBadge.swift`, `Board/CivilizationPieceShapes.swift` —
  per-civilization building silhouettes/markers

## Not included

View models, engine/game-logic packages (`CatanEngine`, `CatanAI`), and
non-visual code — only what's relevant to visual/UI design.
