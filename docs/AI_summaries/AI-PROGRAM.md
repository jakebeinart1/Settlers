# Empires AI — current plan

Updated September 9, 2026. Alex has authorized merging verified product code;
Jake's review is welcome but is not a prerequisite or delivery blocker.

## Six stages

| Stage | Status | Finish line |
| --- | --- | --- |
| 1. Run the published AI | Upstream execution complete; native reproduction incomplete | Preserve identifiable source, weights, training and evaluation evidence. |
| 2. Find stronger, phone-fast search | Paused | Reopen only by explicit decision; native strength and physical latency must both pass. |
| 3. Verify and deliver the heuristic | Closing delivery | Merge the tested product, verify beta access and gameplay; distinguish simulator evidence from physical-phone verification. |
| 4. Strategic quality and targeted heuristic improvements | First trade candidate completed 448 games: promising, not yet proven stronger | Collect representative decision evidence, audit coherent planning, test changes against frozen opponents, then assess automated tuning. |
| 5. Personality and character expression | Deferred until strategic quality | Configurable behavioral traits and controlled randomness, followed by curated event/decision-linked phrases; no runtime LLM. |
| 6. Optional models, search and training | Parked | Explicit research question, compatible comparison, bounded run and active watcher. |

September 8 priority revision: strategic quality now precedes personality;
stages 4 and 5 have exchanged order. They remain separate projects. Current work
now includes Alex's authorized collection/review trial and one fixed trade-accounting
experiment. It does not start tuning, personality or change the app's policy. No candidate has demonstrated stronger native play than
Balanced together with complete decisions within four seconds on an iPhone.

## Current delivery

Build 6 shipped the Balanced new-game default. Main subsequently gained menu
cleanup and replay victory-point breakdowns. Build 7 combines those changes with
the same heuristic delivery; its live verification and merge receipts belong in
[the delivery report](2026-09-08-heuristic-delivery.md), not inferred from this plan.
Existing saves retain their strategies; unsupported research saves are preserved
and blocked, never silently converted. Jake's signing defaults remain unchanged.

## Reuse, do not rebuild

- App/runtime: [run-settlers](../../.claude/skills/run-settlers/SKILL.md),
  [play-settlers](../../.claude/skills/play-settlers/SKILL.md),
  `scripts/gate.sh --debug-app`, and
  [ship-testflight](../../.claude/skills/ship-testflight/SKILL.md).
- Strength claims: [bot-strength](../../.claude/skills/bot-strength/SKILL.md).
- Research source, reports, exact commands, weights and raw results:
  [research handoff](2026-09-08-research-handoff.md). Research-only evaluator/search
  entry points live in that frozen source, not necessarily this product checkout.
- Keep raw failures, budgets, source/config/model hashes and adopt/reject/inconclusive
  decisions. Rebuild reports from retained results before spending inference.
  Do not restart a paused experiment or invent a final rating from incomplete games.

Stage 4 method: [representative corpus, decision review and controlled improvement](2026-09-08-heuristic-corpus-plan.md).
The protocol inventories reusable native/archived tooling, sample sizes,
anti-overfitting controls, external heuristics and tuners. The
[first workflow trial](2026-09-08-heuristic-corpus-trial.md) records 24 complete
games and blind/revealed reviews. It proves useful diagnostic plumbing, not
better strategy. September 9: native context, two blind/revealed review rounds
and 60 synthetic controls isolate prerequisite-swap accounting across development
cards, roads and settlements. An offline joint-target alternative passes its
mechanical checks and flips three of nine scored decisions, including a possibly
useful scarce-grain trade. Native controls and **448/448 comparison games** passed.
The candidate tied the existing bot in one row and had higher win rates in three;
all confidence intervals still include no improvement. The
[native trade screen](2026-09-09-joint-trade-screen.md) records exact wins, intervals,
frozen source, the completed 5m 53s watchdog run and the no-ship decision.

Next milestone: independently test the unchanged candidate on more fresh seed
families using the existing runner; lock the promotion/non-regression criteria
before launching. This follow-up is proposed, not running. No active training or
simulation watcher remains. The app keeps Balanced. Create a reusable skill only
after the method earns it; personality stays deferred.
