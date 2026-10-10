# Build31 development evidence before the final release gate

The selected changes are batch harvest collection and road continuation through rival towns in **new Naval v6 matches**. Resume/replay retain v1–v5 construction rules; rival buildings continue to split Longest Road.

The original city native regression failed before production changes (exit65). Road engine and AI regressions independently failed on the old construction/planning rule. Keep those failures distinct from subsequent passing evidence.

## Observed native journeys

Attempt3 failed overall (exit65), despite the complete photographed road journey passing. It found an incompatible mixed-harvest fixture, a rendered43.67pt minus target and an incorrect large-text scroll direction. The fixture now chooses two distance-legal coasts; quantity targets are48pt.

Attempt4 ran50 functions:49 passed,1 failed,0 skipped. Both complete policy-driven native matches reached actual winners and archived playable histories: Traditional seed19/Twin Islands (Ragnar14VP,564 moves in the reviewed replay) and Expert seed7501 (Alex15VP). These use real session/production turns and a policy-driven human test seat; no forced-win flag is used. They do not establish human enjoyment or bot-strength improvement.

The normal mixed harvest shows0/3 through3/3, permits repeated resources and removal, credits all three through one confirmation, and retains the credited hand after cold resume. City, bank-shortage, previously collected partial entitlement and the native accessibility audit passed. Hosted batch persistence/rules-guide/revision tests passed37 functions in3 suites. The road native journey previews, cancels, builds both interior-rival exits, pays each cost once and restores both after relaunch while preserving board/command frames.

Attempt4's remaining maximum-text case exposed whole-swipe oscillation around a small Ore control. Original recording positions show it below and then above the viewport. Production layout was retained; the native helper now drags slowly toward measured control frames, capped at35% of the scroll viewport. Both whole-control containment and hittability assertions remain. Attempt5 reruns both affected maximum-text journeys successfully (actual exit0,2/2 functions,0 skips).

The final selected-state pixel review found a separate real issue: gold quantity ink and translucent captions blended into the selected gold rows. The first full gate was deliberately cancelled at its native stage to include the correction; its actual native exit is-15 and the gate/push exit is1. Both app configurations still compiled, but that cancelled gate is not passing evidence.

Only selected Naval informational ink now becomes opaque white, including quantities, owned/bank captions and names; the collection progress is white too. Other popup defaults and resource availability are unchanged. Attempt6 passes all7 focused harvest/audit functions; the final title correction then passes attempt7's3 focused functions (batch editing/collection/resume, maximum text, selected-state contrast), both with actual exit0 and0 skips. Separate live bitmap crops check the quantity, title, stock caption and collection progress at partial and complete allocation, so unrelated white text cannot hide a regression. Independent directly adjacent pixel review supplements the native dominant-background measurement. Updated gallery copies come from attempt7; previous originals remain in the task artifacts and Git history.

## Functional simulation and boundaries

The source-bound24-match current-v6 matrix covers all3 map families, both fog choices, both resource-island choices and both AI tiers. All games finish with valid checkpoints, without forced endings. Two representative complete JSONL trajectories repeat byte-for-byte across separate processes. Three purposeful return voyages remain explicitly attributed; no claim of zero returns or greater bot strength is made. Engine/AI test and simulation receipts live in the task artifact folder under `road-rules/`.

## Original screenshot review

Root opened the original native captures; copies below preserve every byte. `original-screenshots.json` binds filenames, original attachments, native tests and hashes. Harvest/road screenshots start from replacement rare-state QA baselines, followed by real native selection/build/confirmation/resume actions. Winner and replay captures come from complete generated matches. Maximum-text rows retain full-sized resource text, with a bounded fixed header/footer.

- [Empty harvest](harvest-empty.png), [complete harvest](harvest-complete.png).
- [Both rival-town road exits](both-road-exits.png).
- [Maximum text before selection](harvest-maximum-text-empty.png), [maximum text completed](harvest-maximum-text-complete.png).
- [Traditional winner](traditional-winner.png), [explored world replay](traditional-explored-world.png), [Expert winner](expert-winner.png).

These are development checks, not a claim that the final full gate, signed archive/upload or Apple tester access has already passed. The frozen-source operation receipts and subsequent delivery disposition remain under `/Users/alex/.codex/artifacts/naval-exploration/build31-harvest-roads/delivery`. Physical-phone installation/play and manual VoiceOver behavior remain unobserved.
