# Settlers — To Do

Updated September 16, 2026. Completed UI/menu/replay notes and previous research context are preserved in [the historical list](docs/archive/2026-09-11-todo-history.md).

## Start here — next session, in this order

1. **Expert has no notion of self-sufficiency, and that is now the gap.** The
   weights are fitted against a refusing table (#8, landed) and Expert's edge
   there went from nothing to +19 points over the null - but it still wins
   78.8% at a trading table against 44.2% at a refusing one. Refitting existing
   terms has now been measured twice; the remaining distance is a **missing
   term**, not more sweeping. The evaluation cannot price "a plan that needs no
   counterparty".
2. **Nothing else is small.** Sessions A, B and D are done; C needs scoping
   before it is one worktree's work.

## Agent sessions — how the open work splits

Each row is **one unit of work: one worktree, one branch, one gate, one push** (CLAUDE.md,
"Concurrent agents"). The *touches* column is what makes two sessions safe to run at once —
rows touching different trees cannot collide. The only shared resources are the gate and the
`Empires QA` simulator, and those serialize at **push** time, so stagger the endings rather
than the beginnings.

| Session | Items | Touches | Cost |
|---|---|---|---|
| ~~**A — Weights & sweeps**~~ | ~~#8, #4~~ | `Packages/CatanAI` | **done** (`5c354a8`, `a50055b`) |
| ~~**B — Vast placement overlay**~~ | ~~#5~~ | `Settlers/Views` | **done** (`9a2f90f`), folded into A's branch |
| **C — External benchmark** | #7 | `scripts/` + a separate process | medium; no app or engine change |
| ~~**D — Tooling**~~ | ~~the `github` plugin~~ | `~/.claude`, not this repo | **done** — removed, no gate needed |

**A is one session, not two, and the reason is not convenience.** Both items are SPSA sweeps
against a frozen anchor under the `bot-strength` protocol — same harness, same rig, same
held-out-seed discipline, and the rig setup is most of the work. More importantly, #8 is what
#4 has to learn from: Classic's weights were fitted at a table that always trades, and that is
the whole defect. Sweeping Vast without `refuses-balanced` in the pool would bake the same
mistake into a second mode. Do Classic first, then carry the pool into Vast.

**B and D are done, and B did not get its own worktree.** Jake asked for both on A's branch
rather than opening two more trees, which is the right call when the second unit is a
two-file visual fix: a separate worktree would have bought isolation that nothing was
competing for, and cost a second gate run. The rule this bends — one worktree, one unit, one
gate — exists to stop *unfinished* work stranding *finished* work behind it. Both of these
finished first, so nothing is stranded; they simply ride A's single gate.

**C is independent of both.** Catanatron is GPL-3.0: an external benchmark *process*, never
linked into the app. That boundary is the design constraint, and nothing in `Settlers/` or the
packages changes.

**D barely needs a session.** It is `~/.claude` configuration, touches no repository file, and
therefore runs no gate.

Backlog items below are deliberately **not** sessions yet — they need scoping before they can
be one worktree's worth of work.

## Tooling

- [x] **Install ponytail and i-have-adhd globally.** Both installed at user scope (`~/.claude/settings.json`), so they load in every project and session. Installed with the `claude plugin` **CLI**, which works over Remote Control where the `/plugin` slash command is blocked:
  ```bash
  claude plugin marketplace add ayghri/i-have-adhd && claude plugin install i-have-adhd@i-have-adhd
  claude plugin marketplace add DietrichGebert/ponytail && claude plugin install ponytail@ponytail
  ```
- [x] **Both always-on, at their default modes.** `~/.claude/.i-have-adhd-always` loads that ruleset at session start, and `~/.config/ponytail/config.json` pins `defaultMode: "full"` — ponytail was already always-on at `full` implicitly, so this only stops it drifting if the package default changes. Per-session overrides remain `/ponytail lite|ultra|off` and `rm ~/.claude/.i-have-adhd-always`.
  - Worth watching against `CLAUDE.md`: both push toward brevity, and this repository's habit of recording *why* — what was measured, what failed, what was tried and rejected — is what has stopped mistakes repeating. A strict YAGNI ladder would have argued against the long doc comments, the frozen round-three policy kept only as a measurement anchor, and `trade-bench` built purely to make experiments fast; each has since paid for itself.
- [x] **Removed the `github` plugin** (2026-09-16). Root cause: its `.mcp.json` sends `Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}`, and that variable was never set, so the header went out as a bare `Bearer ` - "badly formatted" was literal, not an auth or network failure. Fixing it means a plaintext PAT on disk (settings `env` blocks do no command substitution, and the `gh` token is an OAuth `gho_` in the keyring) in a repository that runs gitleaks on every push. `gh` is already authenticated with `repo`/`workflow` scopes and is what `CLAUDE.md` drives every GitHub operation through, so the plugin was a second path to a working tool. Reinstall is one command if a PAT is ever set: `claude plugin install github@claude-plugins-official`.

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
- [x] **4. Vast plays the fitted weights — landed (`a50055b`), and it did not need a sweep.**
  Vast shipped `handSet`: hand-written, never fitted, inherited from Expanded on an argument
  rather than a measurement. Testing the argument before paying for an SPSA run is what made
  this cheap, and the argument was wrong by a margin no sweep would have closed. 480 rotated
  games per arm, held-out seeds, 100% decisive: **81.7% head to head** against three
  `handSet` Experts on their own board (25.0% null, z = +28.7), **85.2% against 67.7%** vs
  three `balanced`. The one dissenting cell, −5.2 vs a refusing table at p = 0.055, came back
  **−1.4 at p = 0.402** when re-run at 1,248 games on a fresh block. The stall that put
  `handSet` there in the first place — four Expert seats failing to finish 2 of 40 Expanded
  games — does not reproduce: **40/40 decisive** with four seats on the fitted set.
  [Numbers and the rule that turned out to be wrong](docs/AI_summaries/2026-09-17-vast-weights.md).
  - **Still open, and now a refinement rather than a repair:** these weights were fitted on
    Classic. "Much better than the alternative on Vast" is not "optimal on Vast". A sweep
    starting from here is available and was deliberately not run.
- [x] **5. Soften the first-settlement placement overlay on Vast — landed (`9a2f90f`).** The cause was geometric rather than a count: neighbouring corners sit exactly `HexGeometry.size` apart, and that spacing is set by how many tiles have to fit a viewport that deliberately never moves. Classic is 5 hexes across and leaves ~48pt between corners, so a 22pt ring had ~26pt of clear space; Vast is 9 across and leaves ~27pt, so the same ring nearly touched its neighbours and all ~150 of them merged into chainmail. The ring is now `min(22, spacing * 0.53)` — 0.53 is where 22pt over Classic's spacing already sat, so **Classic renders unchanged** (the ceiling binds) and Vast draws at ~14pt. Stroke width holds the same fraction of the ring; the invisible 44pt tap target is untouched. Verified by screenshot at real render size, same launch flags, before and after, on both modes.
- [x] **6. Bank trades now price the purchase they unlock — landed (`328c235`).** The cause named here was right and broader than the churn symptom: `.bankTrade` had **no handling anywhere** in `Sources/CatanAI/Evaluation` (`grep` returned nothing across all seven files), so it fell through to the generic one-ply path while proposals got `TradeValuation.bestPurchaseGain`. It is now scored as the swap plus the purchase it opens up, less the purchase already affordable without it — the same subtraction the proposal path uses, and what stops it becoming "always trade". Measured over 2,624 games in four opponent cells: bank trades up in every one (2.71 → 3.52 vs `balanced`; 3.11 → 4.30 vs `refuses-balanced`), cities up, games shorter, **and no significant win-rate change in any cell**. Kept as a correctness fix; no strength is claimed. Two tests pin it, and the "unlocks a city" one was confirmed to fail without the change.
  - **Not re-measured: the churn symptom itself.** The 3.29-per-turn figure came from a dead Expanded endgame, and Expanded is gone. The same check has never been run on Vast, where the rate was already 0.34/turn.
- [x] **8. Weights refitted against an opponent that refuses trades — landed (`5c354a8`).**
  Two held-out blocks, 1,248 rotated games per arm each, complete rotation, 100% decisive:

  | cell | shipped | fitted | diff |
  |---|---:|---:|---:|
  | vs 3× `refuses-balanced` | 40.8% | **44.2%** | **+4.3** (p = 0.019, 0.003) |
  | vs 3× `balanced` | 80.3% | 78.8% | −1.5 (p = 0.227, 0.448) |
  | head to head vs shipped (null 25.0%) | 25.0% | **27.2%** | +2.2 (z ≈ +2.5) |

  Value moved off the hand and onto the board — `handSynergy` −17.6%, `rival` −12.7%,
  `handCardOverflow` −11.3%, `buildableSites` +11.8% — which is the 2026-09-16 diagnosis
  arriving as numbers.
  - **The first sweep was rejected, and it is the part worth remembering.** Its objective
    summed only the two opponent cells, so it bought +5.0 at the refusing table with −3.0 at
    the trading one and lost head to head, **19.6% against a known 25.0% null** — weaker than
    the weights it would replace, while looking like a success in the row it was commissioned
    for. Putting the head-to-head arm *inside* the objective is the whole fix. **A sweep can
    only refuse a trade its objective can see.**
  - **Two cautions.** The trading cell is negative in both blocks (−1.1, −1.8); neither is
    significant but the sign repeats, so this is a small real cost for a larger real gain.
    And two SPSA runs on this objective disagreed on the *direction* of most weights — the
    surface is flat relative to the noise, so no single weight's move here is a fact.
  - [Full method, both sweeps](docs/AI_summaries/2026-09-17-no-trade-weight-sweep.md).
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
  - **2026-09-25: the person model is built, without a learned policy** (branch `feat/ghost-player`, write-up `docs/AI_summaries/2026-09-25-ghost-player-research.md`). It fits Expert's weights plus 14 style habits to one person's recorded choices, and `GhostPolicy` plays Expert pulled toward them (piKL). Fitted on Jake's 24 finished Classic games (2,612 decisions), it predicts 47% of his held-out turn moves against Expert's 9%. The composed-offer blocker does not apply: offers are scored as candidates, not indexed. Next: λ calibration against Jake's 54% win rate, ghosts as selectable opponents, and ratings.
- [ ] **Validate bot strength and repetitive behaviour against human play.** Bot-vs-bot evaluation cannot establish human difficulty, and the two bugs that mattered most so far — the repeated trade offer and the dev-card deck running dry — both came from Jake playing, not from simulation.
- [ ] **Give Expert a term for self-sufficiency.** The largest measured gap after the
  2026-09-17 refit: 78.8% at a trading table against 44.2% at a refusing one. The evaluation
  has no way to prefer a plan that completes without a counterparty — a settlement it can
  reach on its own production over one that needs two trades, a port that removes a
  dependency, a bank trade that closes a purchase this turn. Every large gain in this project
  has come from adding a missing term; the two weight sweeps that have now run are the
  evidence that refitting existing ones does not close this.
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
