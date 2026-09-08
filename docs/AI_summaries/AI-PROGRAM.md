# Empires AI — current plan

Updated September 8, 2026. Alex has authorized merging verified product code;
Jake's review is welcome but is not a prerequisite or delivery blocker.

## Six stages

| Stage | Status | Finish line |
| --- | --- | --- |
| 1. Run the published AI | Upstream execution complete; native reproduction incomplete | Preserve identifiable source, weights, training and evaluation evidence. |
| 2. Find stronger, phone-fast search | Paused | Reopen only by explicit decision; native strength and physical latency must both pass. |
| 3. Verify and deliver the heuristic | Closing delivery | Merge the tested product, verify beta access and gameplay; distinguish simulator evidence from physical-phone verification. |
| 4. Personality and character expression | Not started as the next dedicated stage | Agree on character experience and implement/test expression without silently changing strategy. Existing voices remain available. |
| 5. Targeted heuristic improvements | Not started as the next dedicated stage | Reproduce trade acceptance and road planning complaints, change one policy at a time, measure against frozen Balanced. |
| 6. Optional models, search and training | Parked | Explicit research question, compatible comparison, bounded run and active watcher. |

Personality and heuristic strength are separate projects, not one combined stage.
No new training, search optimization or personality implementation is authorized
by this closeout. No candidate has demonstrated stronger native play than
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

Next: close stage 3, then plan stage 4. Stage 5 needs its own scenarios and
evaluation; dialogue changes are not evidence of stronger play.
