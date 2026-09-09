# Empires AI — current plan

Updated September 9, 2026. Alex has authorized merging verified product code;
Jake's review is welcome but is not a prerequisite or delivery blocker.

## Six stages

| Stage | Status | Finish line |
| --- | --- | --- |
| 1. Run the published AI | Upstream execution complete; native reproduction incomplete | Preserve identifiable source, weights, training and evaluation evidence. |
| 2. Find stronger, phone-fast search | Paused | Reopen only by explicit decision; native strength and physical latency must both pass. |
| 3. Verify and deliver the heuristic | Balanced delivered in Build 7 | Preserve tested delivery; later source changes are not automatically a new phone build. |
| 4. Strategic quality and targeted heuristic improvements | Complete for this bounded iteration | Retain Balanced; preserve the measured corpus, rejected candidate and restart map. Broader strategy research remains open, not a prerequisite for Stage 5. |
| 5. Personality and character expression | Next, not started | Configurable behavioral traits and controlled randomness, followed by curated event/decision-linked phrases; no runtime LLM. |
| 6. Optional models, search and training | Parked | Explicit research question, compatible comparison, bounded run and active watcher. |

September 8 priority revision: strategic quality now precedes personality;
stages 4 and 5 have exchanged order. They remain separate projects. Current work
now includes Alex's authorized collection/review trial and one fixed trade-accounting
experiment. September 9 closeout ends this bounded iteration rather than claiming
expert heuristic play. It does not start tuning, personality or change the app's policy. No candidate has demonstrated stronger native play than
Balanced together with complete decisions within four seconds on an iPhone.

## Current delivery

Build 6 shipped the Balanced new-game default. Main subsequently gained menu
cleanup and replay victory-point breakdowns. Build 7 combines those changes with
the same heuristic delivery; its live verification and merge receipts belong in
[the delivery report](2026-09-08-heuristic-delivery.md), not inferred from this plan.
September 9: Apple still lists Build 7 as the latest upload; Alex's phone was read
back as 1.0 (7). Main `4737471` is versioned 1.0 (8) and adds Jake's hidden-VP
threat fix. Source versioning does not establish that Build 8 was delivered.
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
The first screen tied the existing bot in one row and had higher win rates in
three, without conclusive improvement. The
[native trade screen](2026-09-09-joint-trade-screen.md) records exact wins, intervals,
frozen source and the subsequent **1,792-game fresh-main confirmation**. That
confirmation failed promotion: four-player wins against Balanced fell from
25.0% to 20.7% (difference −4.3 points, 95% interval −8.6 to 0.0). All games and
28 parity checks completed within the original deadlines. **Retain Balanced;
archive the candidate rather than continuing to tune it.**

The [closeout handoff](2026-09-09-heuristic-handoff.md) is the cold-start entry
point, with final confirmation results, archives, verification and known gaps.
The app keeps Balanced; the joint-trade candidate remains an opt-in research
comparator, not a selectable app policy. Do not automatically restart larger
corpora, road planning, parameter tuning or search from historical next-step text.

Next milestone after closeout: agree the bounded Stage 5 personality scope,
keeping deliberate style differences separate from playing strength, and authored
expression separate from the policy. No runtime LLM. Do not create a general
heuristic-tuning skill from this one trade-only trial.
