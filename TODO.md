# Settlers — To Do

Updated September 16, 2026. Completed UI/menu/replay notes and previous research context are preserved in [the historical list](docs/archive/2026-09-11-todo-history.md).

## Start here — next session, in this order

1. **Tune the weights for Vast** (Current work #4). It ships playing Expanded's hand-set weights as a placeholder, never swept on this board. Highest-value open item, and the machine is free.
2. **Fix bank-trade churn** (#6) — a known bot defect with a measured number and a designed fix, waiting only on a strength measurement and Jake's nod.
3. **Soften the first-settlement overlay on Vast** (#5) — small, visual, and the only rough edge a player will notice.

Everything through the Vast replacement is committed, gated and pushed, and running on Jake's phone. Nothing is half-finished; the three above are new work.

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

- [x] **1. Expert trading overhaul — shipped.** Composed offers (bundles, 3+ cards), the counterparty's gain modelled, and Jake's "worth it, don't go down the ladder" rule. Design: [trade cascade](docs/AI_summaries/2026-09-14-position-evaluation-bot.md). Measured against Expert as shipped at `dac279c`, 624 rotated held-out games vs three shipping bots: **80.3% against 65.5%, +14.7 points**, and validated across all four table mixes (+13.3/+11.7/+7.2/+5.0 at 3/2/1/0 shipping bots, every one significant).
- [x] **2. Retrain `EvaluationWeights` for the new trading, Classic — run, and the result is "keep the shipped weights".** 40 sign-SPSA iterations took the training number 47.9% → 51.0%, but it peaked on the last iteration and held-out validation across all four mixes did not hold it up: **−3.7 against three shipping bots** (p = 0.100) and **+2.7 Expert-vs-Expert** (p = 0.239). The arm that had to not regress did, and the arm that had to improve didn't. [Full numbers and reasoning](docs/AI_summaries/2026-09-16-classic-retrain-not-adopted.md). The rig's control arm returned exactly 25.0%, so the numbers are trustworthy.
- [x] **3. Replaced Expanded with Vast, a 61-tile board played to 26.** The 25-point mode's target was unreachable: four players claim only ~8-9 vertices each on 37 tiles, capping a player near 17 points of buildings, so the rest had to come from a deck those same four were emptying. [The diagnosis](docs/AI_summaries/2026-09-16-expanded-endgame-supply-cliff.md) and [the replacement](docs/AI_summaries/2026-09-16-vast-mode.md). Measured over 24 seeded games, four Experts:

  | | Expanded (25) | Vast (26) |
  |---|---:|---:|
  | decisive | 39/40 | **24/24** |
  | deck emptied | 19/40 | **0/24** |
  | a piece cap reached | 24/40 | **0/24** |
  | bank trades per turn | 0.49 (peak 3.29) | **0.34** |
  | moves per game | 1,188 | **1,020** |
  | ms per move | 71 | **66** |

  Expanded stays decodable so an in-progress save resumes, and only leaves `GameMode.newGameChoices`. Both predicted risks were wrong and measured so: Vast is *faster* than Expanded, and the 38-road cap never bound (30 was the most any bot used).
- [x] **Simplified the New Game screen** (Jake, 2026-09-16): Game Mode is a chip row rather than a popup, the table is fixed at four players, match length is a label derived from the mode (Classic 10, Vast 26) rather than an 8-vs-10 dial, and seat 4's "Optional" pill is gone. Everything now fits without scrolling. Existing three-player and 8/12-point saves still resume - `supportedPlayerCounts` stays `3...4` and `isValidMatch` does not read the new-game target list.
- [ ] **4. Tune the weights for Vast, and re-run the trading tests there.** It currently plays Expanded's hand-set weights as a placeholder - never swept, never validated on this board. Same rule as Classic: no table mix regresses, Expert-vs-Expert improves. The sweep must count an unfinished game as a loss for every seat, or the optimiser learns to stall.
- [ ] **5. Soften the first-settlement placement overlay on Vast.** All 150 vertices highlight at once and merge into chainmail; it clears as soon as the distance rule culls candidates, so only the opening placement is affected. Screenshot in the delivery note. Ordinary play is legible and was verified at real render size.
- [ ] **6. Fix bank-trade churn when nothing is buildable.** `bankTrade` is scored through the generic one-ply path, so hand synergy alone can pay for a 4:1 with no purchase to spend it on. Measured at **3.29 bank trades per turn** in a dead Expanded endgame against 0.29 in short games. Vast makes it rarer (0.34/turn) but does not fix the cause. Proposal: require a bank trade to enable a purchase this turn, or price it against `bestPurchaseGain` the way `TradeValuation` already prices a proposal. Needs a strength measurement before adoption - it is a policy change, not a bug fix.
- [ ] **7. Measure Expert against an opponent this repository did not design.** Every number so far is against our own bots, which measures how well a candidate exploits *them*. Catanatron is GPL-3.0: usable as an external benchmark process, never linked into the app.

**How the bots learn:** [the whole pipeline, explained](docs/AI_summaries/2026-09-15-how-the-bot-learning-works.md) — what the bot is, how SPSA training works, how strength is measured without fooling yourself, and which parts are real machine learning versus ordinary engineering.

## Backlog

- [ ] **"Impossible" opponents that hunt the human all game.** Jake's idea, 2026-09-16: a difficulty above Expert where the bots are not merely strong but *personal* - they target the human specifically from the first placement to the last turn, take the spots the human is reaching for, block their roads, and generally set out to ruin their game rather than to quietly maximise their own position.
  - The engine already supports this without new rules. `PositionEvaluator`'s objective is `my standing - rival x (best opponent's standing)`, where `rival` weights whoever is currently closest to winning. An Impossible tier is that same term re-pointed at one fixed seat - the human - with a much larger weight, so every bot at the table prices "how much does this hurt *them*" above "how much does this help me".
  - Concrete levers, all of which exist: contested-site value in `BoardIndex.approachableSites` (take the vertex the human is one road from), robber targeting (the human, always, on their best tile), trade acceptance (never accept anything that helps the human, and never offer them anything), and Longest Road cuts.
  - **Two honest cautions, both worth deciding before building it.** First, three bots co-operating against one player is not the same game as Catan - it is three-on-one, and it will be *unwinnable* rather than *hard*, which is what Jake asked for but is worth confirming once it exists. Second, this is exactly the behaviour the relative objective was built to avoid: a bot that spends its turns hurting someone instead of advancing itself usually loses to a bot that just plays well, so **Impossible may measure as weaker than Expert under the `bot-strength` protocol while feeling far harder to a person.** Measure it as an experience, not a win rate - and if it does win less, that is a finding about the mode, not a bug.
  - Related: this and [Expert](docs/AI_summaries/2026-09-14-position-evaluation-bot.md) are the two ends the difficulty ladder should be calibrated across.
- [ ] **Player-trained ghost opponents and a rating ladder.** Jake's idea, 2026-09-15: every game a person plays trains a model of *them*; past a quality threshold it becomes a named opponent other players face offline — "other people's shadows", a Mario Kart ghost run but a trained model rather than a recorded lap, or Super Auto Pets' asynchronous opponents. Play style carries over, so opponents feel like people rather than one engine wearing different names. Both the person and their bot earn an Elo-style rating, Clash-of-Clans style: your ghost winning someone else's game moves you up by a smaller step than winning yourself.
  - **The training-export plumbing was deleted on 2026-09-16** (`StateEncoding`, `ActionSpace`, `TrainingExample`, `sim --training-jsonl`, and the two Python trainers) as part of the ponytail audit: it had no consumer, and this repository had already failed twice at learning a policy from it. `GameLogStore` still records full move histories and the engine still replays them exactly, so the *data* is not lost - but anyone picking this up restores the exporter from history (`git log -- Packages/CatanEngine/Sources/CatanEngine/StateEncoding.swift`) rather than finding it in the tree.
  - The gap is a *learned* policy, and this repository has failed at that twice (67.7% sign accuracy against a 74.0% baseline; an imitation policy at 0/40). Imitation from one player's games is the research question; the plumbing is not.
  - Blocker that was never cleared, and that the restored exporter still faces: composed trade offers have no fixed action index, so training export refused Expert seats outright.
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
