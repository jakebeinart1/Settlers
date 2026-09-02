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

- [x] Added `ThreatAssessment` (`Packages/CatanAI/Sources/CatanAI/ThreatAssessment.swift`)
      — a per-opponent threat score (VP + production + hidden dev cards +
      proximity to Largest Army/Longest Road) — and wired it, proportionally
      via `relativeWeight`, into robber targeting, settlement/road
      placement (denies threatening opponents' frontier spots, blocks their
      road network), trade acceptance (raises the bar for high-threat
      proposers), and Monopoly targeting. See
      `docs/superpowers/specs/2026-08-16-bot-threat-assessment-design.md`.
- [x] Established a reproducible, seat-rotated baseline against the frozen
      Greedy anchor; added per-seat behavior metrics; and fixed bot-to-bot
      proposals so another policy answers before the proposer continues. See
      `docs/AI_summaries/2026-09-02-ai-baseline-and-personality-audit.md`.
- [ ] Make Balanced, Aggressive, and Cautious observably distinct on
      predeclared held-out metrics. They currently have overlapping behavior,
      so their names are tuning intent rather than demonstrated personalities.
- [ ] Calibrate genuine difficulty tiers against frozen anchors before adding
      a difficulty control to New Game. Personality and difficulty are
      separate axes and must remain separate in both evaluation and UI.
- [ ] Compare heuristic/search, RL/self-play, LLM, and hybrid prototypes through
      the shared `GameObservation`/`ActionSpace` seam. Do not select an
      algorithm from intuition or from another game's results.
