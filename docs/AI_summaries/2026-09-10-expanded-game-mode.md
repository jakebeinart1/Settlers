# Expanded Game Mode — Delivery Summary

Completed 2026-09-11 on `feat/expanded-game-mode` and delivered after the full repository gate.

## What shipped

- A scalable, exact Longest Road implementation, checked against the retained exhaustive oracle on 7,440 networks.
- `GameMode` and a centralized `Ruleset`, with Classic behavior preserved and a new Expanded mode.
- A radius-3 Expanded board: 37 tiles, 14 derived ports, doubled bank, development-card deck and piece supplies, 4-point Longest Road/Largest Army bonuses, and a fixed 25-VP target.
- Mode-aware game creation, validation, checkpoint save/resume and migration, game logs, replay summaries, and score breakdowns.
- A New Game mode picker whose Expanded selection presents 25 VP as a fixed rule rather than an editable match-length choice.
- Explicit refusal by Classic-only AI encoding/action-space APIs when passed Expanded state.

## Verification

The complete production gate passed with `GATE_TEST_WORKERS=1 scripts/gate.sh --debug-app` after project regeneration. This included strict lint, 126 evaluation-tool tests, warnings-as-errors package builds, CatanEngine tests, all 146 CatanAI tests and seeded fingerprints, training export, coverage (Engine 96.10%, AI 97.24%), gitleaks over 360 commits, the full native app test suite including `CompleteMatchTests`, and Release and Debug app builds.

A fresh uninstall/install/launch also passed via `scripts/verify.sh --skip-gate --launch-args '-ui-testing -ui-testing-reset -qaShowNewGame'`; the app remained alive after launch.

A temporary native XCUITest (removed after verification) exercised the real UI path from Main Menu through New Game, selected Expanded, confirmed the fixed 25-VP value, started the match, placed both human setup settlement/road pairs, handled incoming bot trade offers, and completed three full human turns while bots took theirs. The focused test passed in 86.198 seconds.

## Game-length measurement

Twenty deterministic games per mode used seeds 10001–10020, randomized boards, the same heuristic lineup, and the same policy-RNG derivation.

| Mode | Median turns | Max turns | Median moves | Max moves | Unfinished at cap | Median final score spread |
|---|---:|---:|---:|---:|---:|---:|
| Classic | 92.5 | 124 | 509.5 | 714 | 0/20 | 2.0 |
| Expanded | 125.5 | 182 | 869.0 | 1,211 | 2/20 | 7.0 |

Expanded's median game was 1.36× Classic by turns, below the plan's roughly 3× stop threshold. The two capped Expanded games remain the principal balancing risk; the measured rules were not changed to hide it.

## Visual evidence

- [Expanded board at resting fit](assets/2026-09-11-expanded-board-resting-fit.png)
- [Expanded board after human setup](assets/2026-09-11-expanded-board-after-setup.png)

Visual inspection on an iPhone 17 Pro simulator confirmed all 37 tiles fit the viewport, number tokens remain legible, all 14 port badges are visible without clipping, and placed settlements and roads remain inside the board bounds.

## Open items and accepted risks

- 2 of 20 Expanded heuristic games did not finish inside the measurement cap. This is recorded evidence for future balance work, not a release-gate failure.
- State encoding and the learned-policy action space intentionally remain Classic-only and reject Expanded explicitly.
- The Expanded board is denser at phone size, but the captured resting fit remained legible in the verified simulator viewport.
