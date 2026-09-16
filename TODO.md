# Settlers — To Do

Updated September 15, 2026. Completed UI/menu/replay notes and previous research context are preserved in [the historical list](docs/archive/2026-09-11-todo-history.md).

## Tooling

- [x] **Install ponytail and i-have-adhd globally.** Both installed at user scope (`~/.claude/settings.json`), so they load in every project and session. Installed with the `claude plugin` **CLI**, which works over Remote Control where the `/plugin` slash command is blocked:
  ```bash
  claude plugin marketplace add ayghri/i-have-adhd && claude plugin install i-have-adhd@i-have-adhd
  claude plugin marketplace add DietrichGebert/ponytail && claude plugin install ponytail@ponytail
  ```
- [x] **Both always-on, at their default modes.** `~/.claude/.i-have-adhd-always` loads that ruleset at session start, and `~/.config/ponytail/config.json` pins `defaultMode: "full"` — ponytail was already always-on at `full` implicitly, so this only stops it drifting if the package default changes. Per-session overrides remain `/ponytail lite|ultra|off` and `rm ~/.claude/.i-have-adhd-always`.
  - Worth watching against `CLAUDE.md`: both push toward brevity, and this repository's habit of recording *why* — what was measured, what failed, what was tried and rejected — is what has stopped mistakes repeating. A strict YAGNI ladder would have argued against the long doc comments, the frozen round-three policy kept only as a measurement anchor, and `trade-bench` built purely to make experiments fast; each has since paid for itself.
- [ ] **Fix or remove the `github` plugin.** Its MCP server fails to connect every session ("Authorization header is badly formatted"). A broken integration costs more than an unused one: it errors at startup and has to be rediscovered as dead whenever GitHub work comes up.

## Current work — finish in this order

- [ ] **1. Finish the Expert trading overhaul.** Composed offers (bundles, 3+ cards), the counterparty's gain modelled, and Jake's "worth it, don't go down the ladder" rule. Design: [trade cascade](docs/AI_summaries/2026-09-14-position-evaluation-bot.md). Measured against Expert as shipped at `dac279c`, 624 rotated held-out games vs three shipping bots: **80.3% against 65.5%, +14.7 points**. Still to do: validate across every table mix (3/2/1/0 shipping bots), then Expanded.
- [x] **2. Retrain `EvaluationWeights` for the new trading, Classic — run, and the result is "keep the shipped weights".** 40 sign-SPSA iterations took the training number 47.9% → 51.0%, but it peaked on the last iteration and held-out validation across all four mixes did not hold it up: **−3.7 against three shipping bots** (p = 0.100) and **+2.7 Expert-vs-Expert** (p = 0.239). The arm that had to not regress did, and the arm that had to improve didn't. [Full numbers and reasoning](docs/AI_summaries/2026-09-16-classic-retrain-not-adopted.md). The rig's control arm returned exactly 25.0%, so the numbers are trustworthy.
- [ ] **3. Repeat 1 and 2 for the 25-point Expanded mode.** Its sweep must count an unfinished game as a loss for every seat, or the optimiser learns to stall.
  - **The unfinished game is diagnosed, and it is not bot passivity.** [Measured 2026-09-16](docs/AI_summaries/2026-09-16-expanded-endgame-supply-cliff.md): seed 724 ends the move cap at **21/19/24/22** with three seats on the 8-city limit and the 50-card deck completely empty. Half the mode's games hit that cliff — 19/40 empty the deck, 24/40 cap someone's cities — and those run 1,383 moves against 1,011.
  - **Bot-side fix to decide on:** a bank trade is scored through the generic one-ply path, so it is chosen on hand synergy alone with no purchase to spend it on. In the dead position that rises to **3.29 bank trades per turn** against 0.29 in short games. Proposal: require a bank trade to enable a purchase, or price it against `bestPurchaseGain`. Not applied yet — the Classic sweep is running against a frozen binary.
  - **Rules-side question for Jake:** the 8-city cap and 50-card deck are what make the last points unreachable. Raising either, or lowering the 25-point target, changes the game and is his call, not a quiet fix.
- [ ] **4. Measure Expert against an opponent this repository did not design.** Every number so far is against our own bots, which measures how well a candidate exploits *them*. Catanatron is GPL-3.0: usable as an external benchmark process, never linked into the app.

**How the bots learn:** [the whole pipeline, explained](docs/AI_summaries/2026-09-15-how-the-bot-learning-works.md) — what the bot is, how SPSA training works, how strength is measured without fooling yourself, and which parts are real machine learning versus ordinary engineering.

## Backlog

- [ ] **Player-trained ghost opponents and a rating ladder.** Jake's idea, 2026-09-15: every game a person plays trains a model of *them*; past a quality threshold it becomes a named opponent other players face offline — "other people's shadows", a Mario Kart ghost run but a trained model rather than a recorded lap, or Super Auto Pets' asynchronous opponents. Play style carries over, so opponents feel like people rather than one engine wearing different names. Both the person and their bot earn an Elo-style rating, Clash-of-Clans style: your ghost winning someone else's game moves you up by a smaller step than winning yourself.
  - Most of the plumbing exists: `GameLogStore` records full move histories, the engine replays them exactly, `ActionSpace`/`StateEncoding` emit masked policy/value examples per decision, and `sim --training-jsonl` exports them.
  - The gap is a *learned* policy, and this repository has failed at that twice (67.7% sign accuracy against a 74.0% baseline; an imitation policy at 0/40). Imitation from one player's games is the research question; the plumbing is not.
  - Blocker to clear first: composed trade offers have no `ActionSpace` index, so training export currently refuses Expert seats.
- [ ] **Validate bot strength and repetitive behaviour against human play.** Bot-vs-bot evaluation cannot establish human difficulty, and the two bugs that mattered most so far — the repeated trade offer and the dev-card deck running dry — both came from Jake playing, not from simulation.
- [ ] **Calibrate the difficulty tiers.** Classic and Expert both ship; the ladder between them is measured only in Classic, and Expert's Expanded strength is unmeasured. An easier tier below Classic has never been calibrated against a frozen anchor.
- [ ] Compare future heuristic/search, RL/self-play, LLM and hybrid policies under the [AI research program](docs/AI_summaries/2026-09-05-ai-strategy-research-program.md). Research remains paused pending a separate decision.
- [ ] Add opponent reactions to blocked expansion, Longest Road changes and settlement/city builds, available from the in-game message window.
- [ ] Consider distinct background art for Expanded; the shipped mode uses the existing painted backdrop.

## Recently completed

- [x] **Expert difficulty ships in the app.** Chosen on the New Game screen beside Classic, stored with the match so a resumed game keeps the opponents it started with. [Delivery note](docs/AI_summaries/2026-09-14-position-evaluation-bot.md).
- [x] **Position evaluation replaced the win-condition planner.** The planner measured 1.0% against a 25% null and was retired as a decision rule; `EvaluationPolicy` reached **68.4%** (95% CI 65.9–71.0) on held-out rotated games, the first candidate here to beat the shipping bot under the `bot-strength` protocol.
- [x] **Swept `EvaluationWeights`.** Fifty SPSA iterations, +4.7 points (McNemar p = 0.010) on held-out seeds. Most of the apparent gain (67.2% against the training opponent against 47.3% against `balanced`) was exploitation rather than strength — both columns are recorded. `sim --weights` is the seam, and `BotWeights` can be swept the same way.
- [x] **Expanded stalls fixed and per-mode weights.** Sites more than one road away are visible, development cards price their victory-point chance, and cards past the discard threshold have their own weight — Classic and Expanded want opposite answers there.
- [x] **1. Strengthen Expanded (25-point) bots.** Opening roads now score their outward endpoint instead of the settlement they all share, and a development card is refused while a city or settlement is within a few cards. Opening building actions rose 5.1 -> 10.7 per game and early card purchases fell 12.8 -> 0.8; a corrected production opening, **not** a demonstrated win-rate gain.
- [x] **2. Make late Expanded games faster and smoother.** Persistence work per move late in a 25-point game fell **317ms -> 27.6ms**, and bot pacing measures against a deadline. [Plan and evidence](docs/plans/2026-09-11-expanded-bots-and-speed.md).
- [x] Expanded mode: 37 tiles, 25 points, doubled supplies, mode selector, save/resume and replay. [Delivery and validation](docs/AI_summaries/2026-09-10-expanded-game-mode.md).
- [x] Board camera and viewport stability, UI cleanups, remembered player identity, Game History and visual replay. Details remain in the historical list.
