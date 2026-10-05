# October 4 human review — implementation and evidence ledger

Base: `38f7885ddfd30deefdfa9b1b3bde7756804f8570` (TestFlight Build 16).
Integration: `/Users/alex/.codex/worktrees/expert-city-integration/Settlers`,
branch `codex/human-review-20261004`. The primary checkout and separate Expert
experiments belong to other agents and are not edited here.

## Interpretation, scope and acceptance

| ID | What Alex is reporting | Investigation / required outcome |
|---|---|---|
| H1 | Setup and later turns sometimes stop until reopening; waiting is invisible. | Reproduce at real session/lifecycle seams. No duplicate bot runners or stale commits. CPU wait/thinking has a visible status; Skip bypasses artificial pacing only. Settings, private receipts and required human decisions still hold the game. Policy/write failure is actionable, never a silent disabled board. |
| H2 | Trade has too many rows and ambiguous direction. | Compare designs, then implement two labelled rows from the local human's perspective: **You give / You receive**. Counts add/remove explicitly, rates appear only for Bank, hand availability remains visible, invalid/stale drafts have truthful errors. Success retains a receipt with New trade/Close. Incoming quantities and resources wrap legibly, never marquee. |
| H3 | Expert might get favored dice or replay one Monopoly card. | Check shared rules/RNG/controller parity and card conservation. Knight steals one card; Monopoly transfers one selected resource type and consumes a card. Add tests capable of detecting taking a whole mixed hand or reusing an exhausted card. No odds changes justified without evidence. |
| H4 | Bot offers are bank-inferior, repetitive and lopsided after rejection. | Add human-facing offer eligibility/budget separate from Expert valuation. Compare exact bank feasibility, respect resource quantities, suppress rejected lopsided classes across resource names. Suppressed offers must not invisibly hold the bot loop. Accepted/rejected/timeout behavior and cold resume remain coherent. |
| H5 | Development-card inventory and popups look generic/neon. | Audit all five types. Reuse coherent painted/gold-trim illustrated emblems across inventory/reveal/detail. Name, effect, count, new/ready/passive/disabled reason stay legible on small phones; no visual change can alter consumption or enable illegal play. |
| H6 | Robber ignores public leader and strong city production. | Diagnose current Expert formula/candidates using explicit positions, public points, tile probability × buildings, self harm and steal opportunities. Produce tested hypotheses for the separate Expert owner; do not silently alter saved versioned brains. |
| H7 | Raw replay file is not useful sharing. | Generate an actual local MP4, public-safe scores/captions, bounded frame memory, progress/cancel/retry/preview/share. Raw JSONL remains clearly warned diagnostics. Partial or unreconstructable recordings cannot be represented as complete wins. No invented public-link service. |
| H8 | Knight seems to take everything; rules are unclear. | Source/history and official-rule comparison; explain Knight versus Monopoly versus seven/discard. Extend accessible Empires rulebook with actual current configuration and explicit Conquest/Vast differences. |
| H9 | Robber can only be dragged from the dock. | On-board current robber can begin a drag in a local-human robber decision. It stages a destination only; old/new positions remain clear, retarget/cancel works, Confirm is required. Normal pan/zoom and opponent turns remain unaffected. |
| H10 | Roads lead to impossible settlements or unattainable Longest Road. | Audit legal distance-rule destinations, path reachability, costs, piece limits, blocking and realistic bonus contest. Do not overfit the screenshots or revive failed frozen road experiments without new evidence. Record prioritized strategy hypotheses and validation requirements for the other Expert agent. |

## Screenshot observations (not established root causes)

All seven source images were inspected: `/Users/alex/Downloads/IMG_1706.PNG`,
`IMG_1705.PNG`, `IMG_1703.PNG`, `IMG_1702.PNG`, `IMG_1701.jpg`, `IMG_1700.PNG`,
`IMG_1699.PNG`. The last two show disabled controls during empty setup and a
seven respectively; neither proves why progress stopped. 1705/1703 show clipped
incoming trade copy. 1702/1703 show the neon Year of Plenty inventory treatment
and grain-eight cities. The end-game screenshot is not a replay trace.

## Ownership and workflow

- Main: H1 stall/pacing, integration, requirements, focused app/UI tests, final
  generation/gate, independent Standards + Spec review, PR and merge.
- Newton: H3/H8 fairness tests and rulebook (shared parent, disjoint files).
- Chandrasekhar: H4 human-offer eligibility and H6/H10 strategy diagnosis.
- Ptolemy: H2 trade design/build in `human-review-trade/Settlers`; GPT-6.1 Sol
  Ultra explicitly requested for this design task.
- Bohr: H5 card design/build in `human-review-cards/Settlers`.
- Avicenna: H9 board drag in `human-review-robber/Settlers`.
- Darwin: H7 replay video (shared parent, disjoint files).

Only one app build/test process at a time, two compiler jobs and one UI worker.
Disk was 5.2 GiB free after the child worktrees; reuse the parent's DerivedData.
No user simulator erasure, other-process termination, credential output, or
changes to Jake's committed signing defaults.

## Findings and verification status

**Not merged; not shipped; implementation is in progress.** Prior Build 16's
green gate is baseline evidence, not verification of these new changes.

H3/H8 source audit: all controllers roll the same two d6 from engine RNG.
Knight transfers one random card, consumes one Knight and never causes discard.
Monopoly takes all opponents' cards of one resource, consumes one card and is
subject to the one-active-card-per-turn limit. No favorable Expert dice path
or card reuse was found. UI attribution of a later loss is a plausible but
unreproduced explanation for the report. Sources: `DevCards.swift`,
`Robber.swift`, `RulesEngine.swift`, `GameSession.swift`; official base rules:
https://www.catan.com/sites/default/files/2021-06/catan_base_rules_2020_200707.pdf

H7 audit: raw JSONL includes initial hands, deck/RNG, roster and timestamps;
ordinary replay narration includes stolen-resource identity. Video must use a
separate public-safe presentation, not screen-record the existing private UI.

For every implementation record: reproduced symptom → root cause → regression
command/result → inspected screenshots/native taps → review findings/fixes →
commit/PR/merge. Do not turn a planned check into a claimed pass.

## Implemented integration and current evidence

- H1: off-main value-snapshot policy/rule evaluation, one runner, generation and
  checkpoint-revision publication fences, retained resume kicks, cancellable
  viewing intervals, CPU status/Skip, and actionable policy/save failure Retry.
  Finite-worker regressions proved a main-actor pause remains responsive and
  prevents stale publication. This does not forcibly interrupt an infinite
  synchronous policy or prove the cause of the historical screenshots.
- H2: two illustrated quantity rows with explicit add/remove, Bank-only rates
  and stock, wrapped incoming terms plus full Review, and exact success receipt
  with Trade again/Close trade. No pointer-dependent dragging is required.
- H4: durable one-offer-per-bot-turn and table-size-aware per-round budgets;
  bank-equivalent offers and equal/worse explicitly refused lopsided exchange
  classes are actually declined through the engine. The runner and rendered
  offer now share one model projection, not two queues that can disagree.
- H5: one painted emblem/card vocabulary across all five inventory, HUD,
  reveal, detail and choice surfaces. Mixed held/new counts and disabled reasons
  remain inspectable; readiness still comes from the engine.
- H7: local public-safe MP4 generation, bounded frame buffers, cancel/retry,
  preview/native share sheet and warned optional raw diagnostics. Recorded rule
  versions are preserved; missing versions produce an explicit warning, and
  incomplete replays never claim a complete result. No public-link server built.
- H8: contextual rulebook available from the title screen and paused match,
  documenting actual Classic/Conquest/Vast rules and card behavior.
- H9: current on-map robber or dock emblem starts the same camera-aware staged
  drag. Invalid drop/retarget/cancel preserve the prior committed robber, and
  confirmation/victim selection still belong to the existing coordinator.
- H6/H10: tested mechanism handoff only. See
  [strategy evidence](2026-10-04-strategy-mechanism-evidence.md) and the separate
  Expert worktree references inside it. No valuation formula was changed here.

Focused receipts (not the final merge gate):

| Receipt | Observed result |
| --- | --- |
| `/tmp/empires-human-review-stall-red.log` | Baseline reproductions: main-actor policy stall and stale pause publication failed before the H1 fixes. |
| `/tmp/empires-human-review-focused-green6.log` | Focused app suites ran; a readiness assertion incorrectly matched “already” as “ready”, then was replaced by exact typed wording. Not claimed as an all-green run. |
| `/tmp/empires-human-review-native-third.log` | 58 app tests passed. Bank/card/rulebook/trade/video flows and three robber journeys passed; CPU tests had an invalid seat-2 draft assumption, zoom test required a visible origin first, and the 375-point case explicitly skipped on 402 points. |
| `/tmp/empires-human-review-recovery-final2.log` | 32 app tests across three suites passed, including persistence and provenance. Six native tests failed: five exposed the CPU container overwriting Skip identity; zoom used an overly strict fully-contained tile target. These failures were investigated, not ignored. |
| `/tmp/empires-human-review-strategy-focused.log` | Exit 0; 14 declarations across diagnostics and Ghost provenance suites passed. Every move still replays; automatic responses do not become human preference examples. |

## Independent review and fixes

Standards and Spec reviewers independently compared the integration against
`38f7885...HEAD`, then reviewed the follow-up delta. Source findings fixed:
unexpected reconciliation errors no longer disappear into `catch { return }`;
failure details reach the CPU row; obsolete duplicate camera gestures were
removed; dismissed save failures retain Retry and successful reload clears the
failed gate. Automatic refusals/timeouts preserve `isHumanDecision: false`
through checkpoint, archive, completion/catch-up Ghost learning and extraction.
Legacy records default true because historical origin cannot be recovered.
The reviewers also found the CLI importer dropping this flag. Its source fix
and real `ghost extract` regressions passed: three Python tests, exit 0 in
25.701 seconds (`/tmp/empires-human-review-ghost-cli.log`). Explicit false is
not learned; true and legacy missing values are learned; every automatic move
still applies during replay, including invalid replay rejection.

Native tests caught a visible Skip button whose identifier had been overwritten
by its parent. Explicit accessibility containment fixes the real tree without
relaxing button reachability or human-confirmation assertions. Zoom tests now
retain >15% zoom, reveal the current robber by a legitimate camera pan, then
drop onto a hittable legal tile center and require both piece/target frames to
remain unchanged during origin and dock drags. Product clipping is unchanged.

Remaining release checks: current native rerun, dedicated 375×667 interaction
and inspected captures, whole gate/complete-match/Release verification, final
two-axis follow-up, PR/CI/merge. Build 16 remains the last verified TestFlight
delivery until a separate new-build receipt is recorded. No phone installation
has been observed during this task.

Latest native receipt: `/tmp/empires-human-review-recovery-green.xcresult`
passed cold resume, CPU Skip with explicit human placement, incoming receipt
and suppression, and zoomed origin/dock robber drags. Settings still exposed
hidden CPU controls to accessibility; it now replaces ordinary commands with
a same-height empty slot instead of leaving hidden controls mounted. The
dedicated small-phone interaction rerun must verify that correction. The natural-seven
resume test explicitly skipped because no seven arose within three actual
human rolls; this is not counted as seven coverage. Deterministic pending-seven
model and native robber paths provide separate evidence.

Inspected 402-point captures: `/tmp/empires-human-review-trade-402.png` and
`/tmp/empires-human-review-cards-402.png`. Trade direction, quantities, inventory
availability and footer are legible; the card hand shows painted emblems,
separate Ready/New counts, explicit effect and pinned Play/Close. These fixture
captures prove layout, not the genuine purchase or trade flows (native tests
provide those checks). Build 17 is reserved locally after the Apple preflight
confirmed Build 16 was the latest; no new upload has happened yet.

375-point captures inspected: `/tmp/empires-human-review-trade-375.png` and
`/tmp/empires-human-review-card-reveal-375.png`. Both trade rows and the pinned
footer fit; the Year of Plenty artwork, two-resource effect, New-this-turn
explanation and View/Continue actions fit without clipping. A native 375-point
run is separately exercising those actions, quantities and confirmation.
