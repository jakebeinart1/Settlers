# Settlers — To Do

Updated September 11, 2026. Completed UI/menu/replay notes and previous research context are preserved in [the historical list](docs/archive/2026-09-11-todo-history.md).

## Current work — finish in this order

- [x] **1. Strengthen Expanded (25-point) bots.** Opening roads now score their outward endpoint instead of the settlement they all share, and a development card is refused while a city or settlement is within a few cards. Opening building actions rose 5.1 -> 10.7 per game and early card purchases fell 12.8 -> 0.8; this is a corrected production opening, **not** a demonstrated win-rate gain (3/12 against the old policy is the four-seat null rate).
- [x] **2. Make late Expanded games faster and smoother.** Committing a move no longer replays, re-decodes and re-archives the whole game: persistence work per move late in a 25-point game fell **317ms -> 27.6ms**, and bot pacing now measures against a deadline so the chosen speed no longer drifts slower as the game grows.

Plan and evidence: [25-point bot and performance work](docs/plans/2026-09-11-expanded-bots-and-speed.md).

## Backlog

- [ ] Validate bot strength and repetitive behavior against human play; bot-vs-bot evaluation alone does not establish human difficulty.
- [ ] Calibrate difficulty tiers against frozen anchors before adding a difficulty selector.
- [x] **Iterate the win-condition planner, or retire it.** Retired as a *decision rule* and replaced by a position evaluation. `EvaluationPolicy` wins **43.0% against a 25% null** (95% CI 40.3-45.8) over 1,248 rotated games on held-out seeds, with the all-heuristic control landing exactly on 25.0% - the first candidate in this repository to beat the shipping bot under the `bot-strength` protocol. Evidence: [the delivery note](docs/AI_summaries/2026-09-14-position-evaluation-bot.md). The planner's route model is kept and unused; folding its clock in as one weighted feature is open. **Not in the app roster.**
- [ ] Measure the evaluation bot against an opponent this repository did not design. Every strength number here is against our own heuristic, which measures how well a candidate exploits one opponent rather than how well it plays. Catanatron is GPL-3.0: usable as an external benchmark process, never linked into the app.
- [ ] Sweep `EvaluationWeights`. The weights are hand-set from the game's arithmetic and `EvaluationWeights.vector` exists so a sweep can reach them. This is also the first usable customer for the method `BotWeights` has documented and been unable to use since it was written.
- [ ] Compare future heuristic/search, RL/self-play, LLM and hybrid policies under the [AI research program](docs/AI_summaries/2026-09-05-ai-strategy-research-program.md). Research remains paused pending a separate decision.
- [ ] Add opponent reactions to blocked expansion, Longest Road changes and settlement/city builds, available from the in-game message window.
- [ ] Consider distinct background art for Expanded; the shipped mode uses the existing painted backdrop.

## Recently completed

- [x] Expanded mode: 37 tiles, 25 points, doubled supplies, mode selector, save/resume and replay. [Delivery and validation](docs/AI_summaries/2026-09-10-expanded-game-mode.md).
- [x] Board camera and viewport stability, UI cleanups, remembered player identity, Game History and visual replay. Details remain in the historical list.
