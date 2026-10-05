# October 4 human review — implementation and evidence ledger

Base: `38f7885ddfd30deefdfa9b1b3bde7756804f8570` (TestFlight Build 16).
Integration: `/Users/alex/.codex/worktrees/expert-city-integration/Settlers`,
branch `codex/human-review-20261004`. The primary checkout and separate Expert
experiments belong to other agents and are not edited here.

**Current release verdict, October 5: hold for the sharing follow-up and final
release checks.** Three earlier push attempts were refused. The full gate at
`b9753d1` passed and its branch pushed; nothing is merged or delivered yet.
Focused visual/interaction passes below are not a substitute for that gate.

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

Final two-axis follow-up at `d5820a7`: **Standards: zero verified remaining
blockers**; **Spec: zero verified remaining blockers**. Both reviews were
read-only source assessments, not substitutes for the current native/gate run.
The compiler batch count bounds per-module frontend fan-out, not peak total
memory; no hard 10-GB guarantee is claimed.

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
provide those checks). Build 17 was selected locally after the Apple preflight
confirmed Build 16 was the latest; it is not an exclusive reservation. Recheck
Apple before archiving/uploading because other release agents are active.

375-point captures inspected: `/tmp/empires-human-review-trade-375.png` and
`/tmp/empires-human-review-card-reveal-375.png`. Both trade rows and the pinned
footer fit; the Year of Plenty artwork, two-resource effect, New-this-turn
explanation and View/Continue actions fit without clipping. A native 375-point
run is separately exercising those actions, quantities and confirmation.

Small-phone native receipt `/tmp/empires-human-review-375-final.xcresult`:
10 of 11 tests passed, no skips. CPU Skip/mandatory confirmation, Settings
hold/menu resume, all three card appearance/usage flows and all five trade
clarity flows passed. The pending-confirmation test swiped a global
`scrollViews.firstMatch`, which resolved the covered player HUD scroller at
`(23,480,329,27.5)`, and its gesture landed on Decline. Video and hierarchy:
`/tmp/empires-human-review-375-proof/`. Terms and every footer action fit in
the observed confirmation frame before that erroneous gesture.

An attempted global accessibility-collapse modifier did not remove covered
elements from XCTest's queries. It was rejected, along with new assertions
that conflated query existence with accessibility exposure. No claim is made
that VoiceOver isolation was established by that failed experiment. The final
fix gives the dialog's actual vertical scroller the `trade.content` identifier
and scopes native scrolling to that element only. Exact-exchange, receipt,
footer reachability/position, Trade again and Close assertions are unchanged;
viewport assertions and tolerances are also unchanged.

Final focused receipt `/tmp/empires-human-review-dialog-target-375.xcresult`:
exit 0, both the actual 375×667 confirmation/exact trade/receipt/recompose/close
journey and original six-phase viewport-invariance test passed (no skips).
Both independent reviewers rechecked the final three-file source/test change
and found zero verified remaining issues in their respective axes.

Release evidence directory:
`/Users/alex/Library/Application Support/EmpiresResearch/deliveries/human-review-20261004/`.
It preserves inspected captures and logs outside transient `/tmp`. The final
gate uses QA device `07738152-016C-4216-A233-419FA732E9E4` through the existing
`SETTLERS_QA_SIMULATOR_ID` override. This fresh device is named **Empires QA**
as the selector requires, and was created because a different agent started
tests against `937692FF...`; neither that runner nor its device was disturbed.
The 375-point checks use the separate **Empires SE QA** device `2D63B5E8...`.

## Full-gate failure and recovery

The first attempt (`push-gate-interrupted.log` in the delivery directory) lost
the engine coverage artifact; the cause of that disappearance remains unknown.
Its attempted regeneration then explicitly failed with no disk space. The
owned native runner was interrupted, not counted as a pass; Release compiled.

The second attempt (`push-gate.log`) passed 309 engine tests, 260 AI tests,
evaluation tooling, lint, generation, secret scan, coverage (96.08% engine /
96.32% AI), and Release. It failed the app stage. Its modern result summary
reported unknown/zero tests; the legacy action log was essential to diagnosis.
That log explicitly confirms Cocoa error 640 / POSIX 28 while writing a
CompleteMatch checkpoint. `qaPlayToEnd` converted the save error into a trap,
crashing the hosted suite and aborting unrelated tests. The two later LiveSync
host crashes hit the same catch; their individual underlying errors were not
recovered. Do not attribute the historical human stalls to this test incident.

Exact extraction command and verified error are preserved in
`qaloop-gate-rootcause.txt` in the delivery directory. No-space is not evidence
against the new offer policy or Expert strategy. An unchanged serial rerun of
CompleteMatch + LiveSync passed **19 tests, 25 parameterized executions, no
skips**, in 223.954 seconds (`qaloop-suites.log` /
`/tmp/empires-human-review-qaloop-suites.xcresult`). The first single-method
selection omitted Swift Testing's `()` and ran zero tests; it is not evidence.
The corrected selection ran one test and passed in 7.327 seconds.

The QA helper now throws into test callers instead of terminating the host.
The Debug launch fixture uses the actionable save alert for persistence errors
and a dedicated stopped-match alert for other errors; it never says gameplay
can continue after a blocked write. Production save-error behavior is unchanged.
A deterministic real-driver regression injects Cocoa error 640
at the atomic write boundary without filling the disk: it passed in 0.051
seconds and verifies the underlying error, save blocker, unchanged checkpoint,
state/policy cursor, empty event publication, and cold read-back. Receipt:
`diskfull-regression.log` / `/tmp/empires-human-review-diskfull-regression.xcresult`.
The independent Spec review also found that Boolean receipt acknowledgements
lost their underlying write error. Internal throwing seams now retain that
error while the existing UI wrappers still report the save blocker and return
false. The automated driver acknowledges a restored receipt before another move
or game-over return. Purchase and effect receipt tests were seen to fail with
four issues in two executions before that fix (`ack-red.log`, exit 65), then
pass with unchanged state, checkpoint, private receipt, and successful retry.
The final focused run passed **nine tests in two suites**, no failures/skips,
in 0.300 seconds (`ack-green.log`, exit 0;
`/tmp/empires-human-review-ack-green.xcresult`). Both independent reviewers
rechecked the entire eleven-file delta: Standards and Spec each reported zero
remaining verified findings. Those are source reviews, not a full-gate pass.
One-worker gates now disable redundant simulator cloning; default two-worker
behavior and all test targets/assertions are unchanged. This task's final gate
uses one test worker and two compiler batches, not a relaxed test list.

Only owned rebuildable SwiftPM caches were cleaned after coverage was preserved.
The temporary SE QA device was retired after its 375-point captures and native
passes; the manual-play simulator and other agents' devices were not erased.
Six superseded result bundles remain recoverable in Trash and in the validated
`superseded-test-bundles.tar.gz` (delivery directory). No user save was deleted.

The local Build 17 archive/IPA was signed and exported, with Production
CloudKit entitlements and strict signature validation. It was not uploaded.
Its source predates this QA and receipt-error hardening; rebuild before delivery so
the final release receipt identifies the exact verified source commit.

The third full gate at `1bf06b9` (`push-gate-final.log`) passed generation,
lint, 52 evaluation-tool tests, W=E builds, 309 engine tests, 260 AI tests,
coverage (96.08% / 96.32%), secret scan and Release. The app stage failed one
old positive offer fixture: 628 tests, 625 passed, one failed, two skipped;
1,115 parameterized executions passed and one failed. The native skip reasons
were no seven in three real rolls and the 375×667-only journey running on a
402-point destination. Dedicated 375 evidence above remains separate.

The affordable 1:1 ore/grain fixture is not bank-inferior or budget-suppressed.
It bypassed durable presentation registration and queried the card too early.
The revised test reconciles the offer, then runs the real bot loop and requires
the offer, state, session checkpoint and document revision to remain unchanged.
The first focused selection named the source file rather than its global test
functions and ran zero tests; its exit zero is explicitly not a pass receipt.

A separate legacy-restore crash risk was confirmed in the shared engine:
a legal winning move can leave a human trade pending, and constructing or
replacing a session from that terminal state sampled a bot after game over.
Current checkpoint restoration is guarded; old-save migration could reach the
unsafe initializer. No affected user save was found and historical stall cause
remains unproved. A central terminal guard preserves state, pending offers,
engine RNG and policy RNG; no formula/schema/default changes. The staged
regression was seen red before the guard, then green; the owned package rerun
passed two functions/three cases, including live-response control. The fixture
uses legal setup and a real winning upgrade, with conserved earlier VP cards
and funding constructed—not a fully replayed match.

Corrected offer selection: `hold-methods.log` /
`/tmp/empires-human-review-hold-methods.xcresult`, exit 0, seven actual global
test functions passed in 0.055 seconds. This includes the affordable offer
holding the actual runner without changing state/session/revision. Engine
receipt: `terminal-trade-owned.log`, exit 0, two functions/three cases passed.
Strict lint and diff whitespace checks passed. The terminal fix and fixture
correction still require the next complete gate before publication.

## First complete green gate, then final sharing containment

`push-gate-current.log` at `b9753d1f42fbebe2e2137e7bb286c216b794e9a6`
passed every required gate: 52 evaluation-tool tests, 311 engine tests, 260 AI
tests, 96.17% / 96.35% coverage, strict lint, generated project, W=E builds,
secret scan, hosted/native suites and Release. App stage: 2,360 seconds; hosted
Swift Testing: 512 functions in 70 suites, 595.701 seconds. Modern result:
628 tests, 627 passed, zero failed, one skipped; 1,117 executions passed.
The real seven/cold-resume journey passed. Only the 375×667 destination-specific
case skipped; its dedicated earlier native proof is above. Debug build was not
requested separately, but the app tests compiled Debug. Push exited 0.

The source bundle in the delivery packet passed `git bundle verify` and records
full history at that exact commit. This is not the final source after the small
sharing containment below; regenerate the release snapshot before shipping.

H7 last-mile safety review found a configuration gap, **not a reproduced crash**:
MP4 URLs enter an unrestricted activity sheet but the bundle has no Photos
add-only purpose key. Apple documents the write-access purpose-key requirement:
https://developer.apple.com/documentation/bundleresources/information-property-list/nsphotolibraryaddusagedescription
and the built-in video-saving activity:
https://developer.apple.com/documentation/uikit/uiactivity/activitytype-swift.struct/savetocameraroll
No claim is made about the system's permission/hiding behavior on every OS.
Direct camera-roll saving is excluded conservatively; no Photos permission or
feature is introduced. All other activities and callback/file lifetimes remain
unchanged. Public MP4 preview/native sharing remain the accepted product.

The SDK-controller exclusion regression was observed red (nil exclusions), one
test/one issue, exit 65 (`share-red.log`). Callback tests use a dummy URL to
verify real UIKit configuration and forwarding, not recipient delivery. A
separate actual-MP4 native rerun covers creation, preview, native share-sheet
opening/cancellation, retained preview and return to replay. Opening the sheet
does not prove another app or person received the video.

Sharing follow-up receipt: `share-green.log` /
`/tmp/empires-human-review-share-green.xcresult`, exit 0. Three test functions /
five executions passed, no failures/skips: exact UIKit exclusion, installed
success/cancellation/error callbacks, and the actual MP4 native journey.
Strict lint and whitespace checks passed. Final publication reruns every gate
on this follow-up source with the repository's supported two-worker default
and two compiler batches. This is one xcodebuild process using separate cloned
QA devices, not two competing builds; current free memory/disk are rechecked.
