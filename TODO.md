# Settlers — To Do

## 1. Design pass (make it look better)
Taking the UI into Claude Design for fresh visual direction, starting narrow.

- [x] Hand off `BuildingsDesignExport/` (settlement/city pieces only) to
      Claude Design — got back a refined 4-civ look (etched detail, gold
      pennant city marker) plus 4 new civilizations (Columbia, Rome, Japan,
      Norse). Implemented in `Settlers/Theme/Civilization.swift`,
      `Settlers/Views/Board/CivilizationBadge.swift` +
      `CivilizationPieceShapes.swift`, plus a new civilization picker in
      `SettingsView` (choose your own civ + toggle the bot roster,
      persisted via `CivilizationSettingsStore`/`CivilizationAssignmentStore`).
      See `docs/superpowers/specs/2026-08-12-civilization-expansion-design.md`.
- [ ] Once buildings have a direction, take the full board into design via
      `ClaudeDesignExport/` (board, HUD, popups — already bundled, not yet
      sent).

## 2. Bot strength
Make the bot opponents play meaningfully better.

- [ ] TBD — scope out specific weaknesses/next steps.
