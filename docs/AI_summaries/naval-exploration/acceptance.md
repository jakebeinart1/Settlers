# Voyages requirements and acceptance

<a id="build-27-follow-up-e32"></a>
## Build 27 follow-up (E32): delivered

[D55](decisions.md#build-27-decision-d55-defending-occupied-water) makes stationed
ships a passive defense. New Naval v4 games block opposing sea entry, transit
and launches, including at zero moves. Friendly hulls may share water; existing
ships can leave a mixed-owner stack after capture. Saved v1–v3 preserve rules,
movement, AI scores and policy IDs. Build 27 is available to Alex in Internal TestFlight.

[Production](evidence/build27-blockades/manifests/final-production-input-manifest.json)
freezes at `2d985b9570efb27ae3fab8c491275427d4d44fad`, 1.0/27, 378 inputs.
The [source audit](evidence/build27-blockades/receipts/final-gate-source-audit.json) matches all 112 package inputs to the
[new v4 matrix](evidence/build27-blockades/matrix/final-functional-receipt.json):
48 winners reach 14 points over 28,239 actions; six fresh-process repeats match
complete result/trace bytes. [Metrics](evidence/build27-blockades/matrix/metrics.json)
record no forced ends, idle sailing/trade cycles or duplicate proposals;
[five raw revisits](evidence/build27-blockades/matrix/raw-revisit-review.json)
retain their productive settlement/discovery context. No strength claim follows.

The [first native pass](evidence/build27-blockades/receipts/first-focused-summary.json)
(44 functions/71 runs) still [fails maximum-text pixels](evidence/build27-blockades/failed/first-root-visual-review.json).
The repaired maritime scaffold, Vision OCR, blockade/cold-resume flows and layout
invariance [pass eight checks](evidence/build27-blockades/receipts/readable-dock-focused-summary.json),
zero failures/skips. Earlier focused Tokugawa evidence remains separate from
final-gate Washington 14 VP, Alex 7, Charlemagne 8 and Ragnar 11.

All ten mandatory stages [pass](evidence/build27-blockades/receipts/final-gate-success.json); optional standalone Debug skips,
while native Debug ran and Release compiled. Native: 779 functions, 777 passed,
zero failed, two skipped; 1,560 runs, 1,558 passed. Skips are an unreached natural
seven and a 375×667 check on 402×874 QA. Actual kernel gate/hook exits are 0;
original Git SIGPIPE−13 remains preserved. The [same-source transport-only retry](evidence/build27-blockades/receipts/transport-only-retry.json)
exits 0 with `--no-verify` after verified checks, bypassing no failed gate.
Root approves [eight final-gate originals](evidence/build27-blockades/receipts/root-final-gate-visual-review.json) and the ordinary
[Release runtime](evidence/build27-blockades/receipts/release-runtime.json): fresh 1.0/27, no QA arguments, alive six
seconds, no new own crash, with its original menu separately approved by root.

Archive/export/upload exit 0. [Strict payload signing](evidence/build27-blockades/receipts/uploaded-payload-signature.json)
uses the existing certificate/profile and CloudKit Production; [comparison](evidence/build27-blockades/receipts/uploaded-payload-comparison.json)
finds only signature bytes differ from the review export. Actual IPA is
36,334,326 bytes, SHA256 `b6b899817bc508f829dfce946b9fce65178bea324993e82b4985d660d8ad2ff8`,
MD5 `534d84d459b273e5b64033f40c0003b0`. [Apple](evidence/build27-blockades/receipts/testflight.json) confirms the
accepted UUID `a49ab68c-859a-4467-8454-c1c5fde1677a`, VALID/unexpired,
Internal IN_BETA_TESTING and Alex's all-build access. [Independent release audit](evidence/build27-blockades/receipts/final-independent-release-audit.json)
passes with no blockers. Physical installation/play is unobserved; no external release occurred.

[Finish](evidence/build27-blockades/receipts/simulator-finish-and-source-guard.json) individually shuts QA937 down, retaining all 14 devices
and the other 13 states. [Three helper checkouts](evidence/build27-blockades/receipts/helper-worktree-cleanup.json) are recoverably
archived. [PR #61](https://github.com/jakebeinart1/Settlers/pull/61) is the integration record for this verified source. Earlier pending
delivery snapshots retain their original identities.


## Build 26 follow-up (E31): delivered

D54 fixes an omitted public quantity: Monopoly collects finite supply minus
bank stock minus your own hand. Classic has 19 per resource, Expanded/Naval 38
and Vast 60. Each choice shows “N to collect”; Play previews “Collect N Wool
from rivals”. Zero remains legal with a plain warning. Missing/impossible legacy
stock is unknown, never fabricated. Plenty explicitly says “in bank”. The
adapter accepts only public inputs; no private rival composition, rule, AI,
save field, replay or RNG behavior changes.

[Production](evidence/receipts/build26-final-production-inputs.json) freezes at
`e13d4a1cac8930063ee89438207a5da56f215e26`, 1.0/build 26, 377 inputs. All
[112 package inputs](evidence/receipts/build26-engine-ai-source-equivalence.json)
match build 24/25, retaining 48 matches/six fresh-process byte repeats without
an AI-strength claim. [Focused](evidence/receipts/build26-focused-summary.json)
checks pass 28 functions/44 runs, zero failures/skips, including actual payouts,
zero consumption, public masked equivalence, mode supplies and maximum text.

The [full pre-push](evidence/receipts/build26-final-prepush-command.json) exits 0
at `f1b9b1442defadc5ce7f9d45eb012e4858765a32`, all ten mandatory stages PASS.
[Native](evidence/receipts/build26-final-native-summary.json): 768 functions,
767 passed, zero failed, one skipped; 1,542 passing runs. The sole skip requires
375×667 while QA is402×874. Hosted 588/83, Engine 391/31, AI 308/31;
coverage 96.74%/96.05%. Release compiles; optional standalone Debug was not
requested, while the native test action ran Debug. [Independent source audit](evidence/receipts/build26-final-source-gate-audit.json)
reproduces the raw verdict, frozen inputs and exact current-main composite tree.
[Source CI](evidence/receipts/build26-tested-head-github-ci.json) passes Linux
Engine/AI and SwiftLint; hosted drift is workflow-dispatch-only SKIP and local
mandatory drift passed. Later metadata CI is a separate run.

Root reviews all 11 selected unchanged [originals](evidence/screenshots/build26-final-manifest.json):
ten full-gate Debug captures plus the ordinary Release menu. Counts, zero warning,
38-card prediction/receipt, pinned maximum-text actions and uniform disabled bank
choices pass. The ordinary inspected match reaches Tokugawa 14 VP/human Alex 5 VP;
natural Knight checkpoints are separate from conserved all-type fixtures.
[Combined review](evidence/receipts/build26-final-gallery-root-review.json) adds
Release to the exact [earlier Debug-only review](evidence/receipts/build26-final-debug-gallery-root-review.json),
preserving the original source-audit hash. [Runtime](evidence/receipts/build26-release-runtime.json):
fresh ordinary 1.0/26, no QA arguments, PID 49545 survives 6 seconds, no own new crash.
Prior accessibility qualifications remain exact and narrow; no blanket audit
or physical-phone-play claim is made.

Archive/export/upload exit 0. [Strict signing](evidence/receipts/build26-signed-export.json)
and the [actual payload](evidence/receipts/build26-uploaded-payload-signature.json)
verify the existing leaf/profile and signed CloudKit Production. Actual IPA:
36,313,582 bytes, SHA256 `81bc6674970f56080f24295ca5c5535a8e48055e40dcc63d2728ea282db0f983`,
MD5 `3eb9b75e358b124642ef2fb71d4be03f`. [Comparison](evidence/receipts/build26-uploaded-payload-comparison.json)
checks 14 ZIP entries, only executable signature differs from review export;
5,907,456 prefix bytes match. ContentDelivery confirms MD5 three times and
accepts UUID `9f7d32a2-5336-4278-bf47-dab480ad46e5`. [Apple](evidence/receipts/build26-testflight.json)
at 20:11:04UTC confirms that exact 1.0/26 UUID VALID, unexpired until January 5, 2027,
Internal IN_BETA_TESTING and Alex's exact all-build access. [Independent delivery](evidence/receipts/build26-final-independent-delivery-audit.json)
agrees. No external release or physical installation/play is observed.

[Finish/source guard](evidence/receipts/build26-simulator-finish-and-source-guard.json)
records owned QA937 shutdown exit 0/readback Shutdown at 20:12:39UTC,14 devices
retained, every other state unchanged, no create/delete and 377 matching inputs.
The [retained policy](evidence/receipts/build26-simulator-policy-reconciliation.json)
subsumes PR #58's shared maximum-three devices, allocation lock and >48-hour latest
credible activity retention, preserving current flags/signing/default-one worker.
Alex explicitly delegates approval/merge to the agent; canonical
`~/.claude/rules/gitflow.md` removes a minimum human/GitHub approval. Dispositions:
[PR #60](https://github.com/jakebeinart1/Settlers/pull/60) merges the verified integrated
work; [PR #58](https://github.com/jakebeinart1/Settlers/pull/58) closes as subsumed after
the retained policy lands. Live GitHub records own their final status. Main's
`bc11db4` document is preserved via `746e56c`, and the clean composed tree equals
the fully gated tree. All build 25 and earlier approval waits below are historical.

[Final independent release audit](evidence/receipts/build26-final-independent-release-audit.json)
passes strict signatures, actual uploaded bytes, fresh Apple access and raw
individual cleanup inventories, with no blockers.

## Build 25 follow-up (E30): delivered

Alex's follow-up requests distinct development-card aesthetics, matching HUD
count baselines, compact names without READY, panels whose actual choices/actions
fit, and deliberate card inspection during a complete Naval match. D50–D53
record the choices and alternatives in [decisions](decisions.md#build-25-card-decisions-selected-verified-for-delivery).
Production freezes at `a9e0e88eb30e5bd0c5f96c6b1354ed2e7b7023c1`, 1.0/build 25,
with [376 matching inputs](evidence/receipts/build25-final-production-inputs.json).
The [112 package inputs](evidence/receipts/build25-engine-ai-source-equivalence.json)
match build 24 `9bce5f7` exactly, reusing its 48 matches/six complete-byte repeats
without a new strength claim. The [1908 prototype binding](evidence/receipts/build25-production-inputs-1908-prototype.json)
remains distinct from the final freeze.

The hand uses five native engraved emblems, shared 44-point resource/card HUD
slots and fonts, compact selectors and one compact selected detail. Purchase
and existing result receipts retain large illustrations. Monopoly chooses a
resource collected from rivals without misleading bank/private quantities.
Plenty shows two ordered removable picks, actual stocked-bank choices and progress.
Normal choices use one row and accessibility choices two columns. Header/actions
stay pinned; only that scaffold caps at accessibility size 1, while the middle,
effect text and choices retain full scaling. Exact width precedes wrapping and
horizontal selectors align within their viewport. Debug geometry markers are
behind controls and noninteractive after the first overlay marker blocked taps.

### Retained native command history

Portable [focused evidence provenance](evidence/receipts/build25-focused-evidence-manifest.json)
binds the unchanged summary bytes, original paths and command times. The logs,
xcresults, source snapshots and attachments remain in the original
[artifact directory](</Users/alex/.codex/artifacts/naval-exploration/build25-development-cards>).
Counts below are functions/runs, all with zero skips.

| Command | Verdict and passing/failed functions | Finding |
|---|---|---|
| [First](evidence/receipts/build25-first-focused-summary.json) | FAILED, 17/11 of 28 | Overlay geometry markers intercepted native card taps; first flow/invariance cases passed. |
| [Second](evidence/receipts/build25-second-focused-summary.json) | FAILED, 25/3 of 28 | Existing flows passed; Plenty selector reachability and largest-text resource clipping remained. |
| [Third](evidence/receipts/build25-third-focused-summary.json) | FAILED, 9/1 of 10 | All five normal details, HUD, scarcity and ordinary complete-match audit passed; largest-text selector failed. |
| [Fourth](evidence/receipts/build25-fourth-focused-summary.json) | FAILED, 1/1 of 2 | Conquest army passed; Monopoly selector extended beyond the horizontal viewport. |
| [Fifth](evidence/receipts/build25-fifth-focused-summary.json) | FAILED, 2/1 of 3 | Victory Point and normal detail passed; largest selector remained clipped. |
| [Selector probe](evidence/receipts/build25-selector-probe-summary.json) | FAILED, 0/1 of 1 | Retains the same measured 392-versus-409-point boundary failure. |
| [Sixth](evidence/receipts/build25-sixth-focused-summary.json) | FAILED, 1/1 of 2 | Normal details passed and selector geometry advanced; the remaining resource lookup failed on a lazy offscreen element. |
| [Seventh](evidence/receipts/build25-seventh-focused-summary.json) | PASS, 1/0 of 1 | Bounded largest-text Monopoly/Plenty fit, scrolling and pinned-action case. |
| [Prototype final focus](evidence/receipts/build25-final-focused-summary.json) | PASS, 24/0 of 24 | Session `10784`, exit 0, at `1908cd0`; not the final style freeze. |
| [Positive Monopoly](evidence/receipts/build25-monopoly-positive-summary.json) | PASS, 1/0 of 1 | Test-only `f7c6090` proves actual rival collection with an empty bank. |
| [Final availability](evidence/receipts/build25-availability-focused-summary.json) | PASS, 3/0 of 3 | Session `34838`, exit 0, at `a9e0e88`: all five disabled bank choices, largest-text commit/result and empty-bank Monopoly collecting 38 wool, then returning to Roll. |

Controlled fixtures now construct actual Naval legal setup and conserve finite
bank/deck totals. They inspect all five types and scarcity semantics; the rare
winning Victory Point fixture remains separate. The ordinary Expert Naval match
uses seed 7501 and raw Debug `-qaInspectCompleteMatch` only to pause production
play at natural purchase, mature-hand and resolution checkpoints. Native taps
inspect actually owned cards and acknowledge actual receipts. Root inspected
third-run originals at moves 160/175/177 and the actual winner. Knight is the
only naturally held type inspected in this ordinary match; all five types are
covered separately by conserved fixtures and actual purchases. This is one
functional complete match, not a strength measurement or physical-device play.

The green prototype did not close visual review: original `0CAB` still showed
the last tapped Grain brightly after two Plenty picks. The environment-aware
button style in `a9e0e88` fixes that cached label state. Root and independent
visual review approve original `AA7` (SHA256
`709e9b304fb0735f124819a9767a50dd6b9c6d5d939ea30471739f66af8b6dc4`):
all five bank choices dim while removable picks stay bright. Scaled-preview
clipping concerns were withdrawn after reading the same-hash A66/F9 originals;
no source change was made for those concerns. This closes those intermediate
defects, not approval of every final-gate image.

### Failed first full gate and replacement pass

The [first command](evidence/receipts/build25-first-full-prepush-command.json)
and [log](evidence/receipts/build25-first-full-prepush-gate.log) retain session
`4387`, exit 1, with push refused. Native [summary](evidence/receipts/build25-first-full-prepush-native-summary.json):
760 functions, 758 passed, one failed, one skipped; 1,517 passing runs plus one
failure/one skip. Hosted 581/82 and every other mandatory stage, including Release,
passed. The failure was
`GameplayFeedbackFlowTests/testYearOfPlentyNoticeNamesTheCardAfterRealSelection`:
the XXXL test tapped Ore before revealing the lazy grid; no card commit occurred.
The same full-gate large-card journey passed.

Test-only `cffe613` uses the existing shared measured-scroll helper before the
feedback choices, preserving exact notices and strict whole-control bounds.
The [correction focus](evidence/receipts/build25-feedback-correction-summary.json)
passes two functions/runs, zero failures/skips, exit 0, session `48432`.
Only two test files differ from production; all 376 production and 112 package
inputs remain unchanged.

Replacement [command](evidence/receipts/build25-final-prepush-command.json)
and [log](evidence/receipts/build25-final-prepush-gate.log), session `13288`,
exit 0, pass all ten mandatory stages and publish remote
`cffe613a3c112c6f99f5e6c1d4dca36c7fa719a0`. Final native [summary](evidence/receipts/build25-final-prepush-native-summary.json):
760 functions, 759 passed, zero failed, one skipped; 1,518 passing runs plus one
skip. Hosted 581/82; Engine 391/31, coverage 96.74%; AI 308/31, coverage 96.07%.
Optional standalone Debug skips because it was not requested; native Debug ran
and Release compiled. The sole native skip is the 375×667 trade-footer flow on
the 402×874 QA device; no new compact-phone proof is inferred. Existing native
caption Contrast flags retain their three exact-ID/live ≥7:1 qualification.
These are the replacement gate's coverage values.

[Helper cleanup](evidence/receipts/build25-helper-worktree-cleanup.json) confirms
recoverable archive/readback of `cards-qa-audit`, with no needed ignored files.
### Final-source gallery, ordinary Release and accepted upload

Root directly inspected all 27 selected original-resolution captures: 26 final
full-gate Debug images plus the ordinary Release menu, with no blocking defect.
The [review](evidence/receipts/build25-final-gallery-root-review.json),
[export metadata](evidence/receipts/build25-final-gallery-export-manifest.json)
and [portable gallery](evidence/screenshots/build25-final-manifest.json) retain
exact source/test/time/configuration and unchanged original hashes. This covers
all five hand details/purchase reveals, aligned HUD counts, largest-text choices/
results, real mixed/empty-bank outcomes, natural Knight checkpoints/winner,
Conquest Army, the committed public Plenty notice and the ordinary menu.

[Release runtime](evidence/receipts/build25-release-runtime.json) confirms a
fresh install of 1.0/build 25, no QA arguments, PID `2755` alive after six seconds,
no new own crash reports, expected menu, executable SHA256
`44209bea08cab40efb995b2a43e8c9e172189f8fcf4c41aee65e174390df2127`.
[Archive](evidence/receipts/build25-archive-command-receipt.json) and
[export](evidence/receipts/build25-export-command-receipt.json) exit 0, with
strict [review-export signing](evidence/receipts/build25-signed-export.json).
[Upload](evidence/receipts/build25-upload-command-receipt.json) exits 0 and
preserves the actual staged IPA. Its [signature](evidence/receipts/build25-uploaded-payload-signature.json)
binds SHA256 `5b020ca35ac4dfed60fc4a428ce241e282ff47f8c8e47252cbbf23dba5926691`,
36,308,759 bytes and MD5 `8443b7a3de5668f16c46a99f243568d0`.
The [comparison](evidence/receipts/build25-uploaded-payload-comparison.json)
checks all 14 ZIP entries: only the executable's code signature differs from
the review export (`aa03560724b57ae5bc121e214bdd8d9e3a8c6a458c19f9d25e7e882f0b62d205`,
36,308,763 bytes); its first 5,874,672 executable bytes match. ContentDelivery
confirms the actual MD5 three times and accepts UUID
`409a8bbf-4931-4a9b-b70d-da2c8bbc4860`. The fresh [Apple readback](evidence/receipts/build25-testflight.json) at
17:57:29.535 UTC confirms the matching ID, 1.0/build 25, VALID/unexpired
(expires January 5, 2027), internal IN_BETA_TESTING. Alex's exact tester ID
`a8ee9090-8182-4804-b5f9-eead9c032495` has all-build access through Internal
group `bf165450-034a-437d-b7f7-028bf3d57a5b`. External state remains
READY_FOR_BETA_SUBMISSION; no external release or physical-device install/play
is recorded.

[Tested-head CI](evidence/receipts/build25-tested-head-github-ci.json) passes at
`cffe613`: Linux Engine/AI and SwiftLint succeed in run `37660184339`.
Hosted project drift skips as workflow-dispatch-only; mandatory local drift
passed in the full gate. Later metadata CI is separate. PR #60 is published,
unmerged and awaiting approval. Live main `bc11db4` adds one research document
without production/package changes; `83d8525` remains the historical integration
base. [QA cleanup](evidence/receipts/build25-simulator-cleanup.json) shuts down
only owned `937692FF-BFBF-4683-80E5-2590F5288D56`, exit 0, with Shutdown
readback at 17:59:07 UTC. All 14 devices remain; Ferrule Dice Review and
Switchbard Small Owner Review stay Booted, untouched. Exact [before](evidence/receipts/build25-simulators-immediate-before-release-cleanup.json)/[after](evidence/receipts/build25-simulators-after-release.json)
inventories and 376 matching production inputs confirm cleanup boundaries.
The [root final readback](evidence/receipts/build25-root-final-release-readback.json)
binds 376 current hashes, Apple/access, upload UUID, QA cleanup, tested CI and
27-image approval. The [independent final audit](evidence/receipts/build25-final-independent-release-audit.json)
passes with no blockers, including a fresh 18:01:59 UTC Apple readback, both IPA
signatures, accepted payload/UUID, original gallery hashes and cleanup. E30 is
complete for internal TestFlight delivery; PR approval remains outstanding. Every build 24 and older historical body below is unchanged.

The complete mode is implemented in the isolated `codex/naval-exploration`
worktree. C01–C16 preserve Alex's commitments. Delegated D01–D32 are recorded in the
[design contract](design-contract.md); subsequent human D33–D49 are recorded in
[decisions](decisions.md). This register states their
observable outcomes, counterexamples and available evidence. It replaces the
planning-only register with source-bound final acceptance evidence.

**Build 24: delivered to Alex in internal TestFlight (E29).** D45–D49 select
painted harvest terrain/progress, natural ship language, visible win goals,
accepted-bot-offer competition and Naval v3 two-hex destination voyages. Current-main
integration is frozen at `9bce5f77a38684bd6e011fac8838c74b38440798`, version 1.0/build 24,
with [376 production inputs](evidence/receipts/build24-final-production-inputs.json).
The integrated focused command failed three checks; its refined follow-up failed
one contrast audit. Subsequent harvest verification passes three native cases
with a narrowly qualified contrast handler, retaining the raw native flags and
requiring live screenshot ratios of at least 7:1 for three exact IDs. Fresh v3
functional evidence passes 48 matches and six complete-byte result/trace repeats;
it does not establish strength. Root inspected integrated harvest paint and the
actual bot-winner notice. The first complete pre-push gate failed two test oracles;
their test-only correction passes three functions/eight runs. The replacement
full gate passes all ten mandatory stages, exit 0, and publishes the branch at
test-only head `67efbad`. App/UI has 754 functions: 753 pass, zero failures,
one skip; 1,512 passing runs. Optional Debug app build skips; the native test
action built Debug. Ordinary Release 1.0/24 is freshly installed without QA
arguments; PID 93934 survives six seconds with no new own crashes. Root approved
23 unmodified final-source images, including its menu. Archive/export/upload and
strict/deep Production signatures pass. Apple build
`9b3882ef-a85c-46c2-8d1a-2d83f5483aef` is VALID, unexpired and internally
IN_BETA_TESTING, with Alex's Internal all-build access independently confirmed.
The final release audit passes. PR #60 awaits actual approval; required tested-
head Linux/SwiftLint CI passes and no merge is recorded. External release, physical-phone play and new strength
remain unobserved.
[E29](#build-24-follow-up-e29-delivered) owns the receipts and limits. Build 23/22
records below retain their original source boundaries.

**Build 23: delivered to Alex in internal TestFlight (E28).**
D42–D44 add eight painted controller styles, explicit construction availability
and separated Skip/trade targets. The legal stale-touch guard fails before the
fix. The fourth command passes all eleven Build/trade/existing Naval UI functions
but fails two new artwork assertions; the corrected artwork follow-up and a
stronger visible-maximum-zoom guard then pass. Compact-phone and real mixed-owner
stack checks pass. Frozen `1dfae7c`, version 1.0/build 23, now passes all eleven
gate stages: Engine 371/28, AI 303/30, hosted 565/80, coverage 96.67%/96.01%;
app/UI 731 of 732 functions pass, zero failures, one size skip, 1,476 passing
runs. The skipped footer case passes independently at 375×667. All 371 production
inputs are bound to the freeze. All 111 package files match build 22, supporting
explicit reuse of its 48-match/six-repeat matrix without a rerun or strength claim.
Seventeen unmodified final-source images are root-inspected; freshly installed
ordinary Release survives six seconds without QA arguments or new own crashes.
Archive/export/upload/Production signing pass. Apple build
`cfcb926b-7b11-4178-9d19-8df7a9e5e597` is VALID, unexpired and internally
IN_BETA_TESTING with Alex's Internal all-build access confirmed at 4:16:30 a.m.
EDT, October 7. External build 23 is unreleased; physical installation/play,
hardware timing and new AI strength remain unobserved.
[E28](#build-23-follow-up-e28-delivered) owns the receipts and limits.

**Earlier build 22: delivered to Alex in internal TestFlight (E27).**
Source `1cf1c0f` includes charted home harbors, strict legacy queued-observation
compatibility and exact World → Return camera restoration. Earlier targeted
commands pass 20 functions/35 runs and 31 functions/36 runs; the final fitted
zoom-one regression passes separately. All 48 declared AI functional matches
complete and six fresh-process repeats match every result field and full trace.
The current-source complete gate passes all eleven stages, ordinary Release
survives and final-source media are inspected. App/UI has 704 functions: 703
passed, zero failed, one size-specific skip; 1,433 passing runs. Archive/export/
upload and independent final audit pass. Apple reports VALID, unexpired and
internal IN_BETA_TESTING with Alex's access confirmed at 12:59 a.m. EDT on
October 7. External build 22 is unreleased; physical-phone installation/play
remain unobserved. [E27](#build-22-follow-up-e27-delivered) retains the receipts.

**Earlier build 21 delivery: Alex's TestFlight access confirmed (E26).** Source
`60394e6` restores inland home settlements while retaining exact ship-access
rules for founding without a road. All eleven gate stages pass; the ordinary
Release 21 launch survives and final native placement/resume captures are
inspected. Apple build `23440fef-103a-4c7b-8896-a0164c7bab74` is VALID and internally
IN_BETA_TESTING with Alex's access confirmed. External build 21 remains unreleased;
physical-phone installation is unverified. [E26](#build-21-follow-up-e26-delivered)
retains the complete evidence, including resolved signing and historical failures.
Earlier closed deliveries below retain their
original source and attribution.

**Original local-simulator acceptance: October 5, 2026.** F01–F15 are closed for
this delivery. Frozen source `971a615` passes every one of the eleven repository
gate stages, exit 0 (E20). The unchanged gated Debug executable then passes actual
purchase/three-step sailing/cold resume, capture/cold resume and system Reduce
Motion journeys (E21). A fresh installation survives on the isolated Empires
Voyages Review simulator, and the final screenshots and sequential movie frames
have been opened independently by root and the documentation reviewer (E22).
The app is ready for local human review.

**Subsequent setup correction (E23):** source `ac3dec5` implements Alex’s
**Rules → Naval** placement. Targeted native setup/start/cold-resume/saved-prefill
passes on regular and SE simulators, all four land-board/rules return paths and
keyboard invariance pass, hosted setup suites pass, and Release/Debug compile.
The new app is installed in place with the original review checkpoint unchanged;
E20 remains the earlier full gameplay gate, not a claim of a second full gate.

The first `02eb013` gate failed; its hosted terminal-trade crash, reproducible
Classic confirmation failures and disabled-button contrast failure remain in
E12/E14 and the [audit report](audit-report.md). Subsequent map and maximum-text
paint counterexamples, including the intentionally failing fog negative control,
are also retained. All twenty-three findings have corrections and final-source
verification; a successful functional test never substitutes for inspected paint.

The frozen 1,464-game AI confirmation meets the declared three/four-seat criteria
(E15), and the separately attributed 48-trajectory integration bridge passes.
Human enjoyment, manual VoiceOver play, other personality mixes and physical-phone
latency remain unmeasured. They are explicit measurement limits, not waived
required simulator features. The later October 5 request authorizes TestFlight delivery, tracked in
[the build 18 record](phone-delivery.md).

## Requirement record

Every requirement receives a stable ID, player outcome, charter/decision source,
preconditions, normal/alternate/failure scenarios, expected durable result,
visual/accessibility result, verification method and evidence link/status. Record
the applicable map family, settings, seat/table configuration and policy revision.
An unresolved expected result points to its D record rather than a guessed rule.
The selected outcomes below are requirements, not claims of human enjoyment,
physical-phone performance or mathematical balance. Each final closure needs a
passing receipt for the final tree, or evidence that a later change cannot affect
the checked behavior.

## Feature coverage register

| ID | Required player outcome | Source/dependencies | Evidence required |
|---|---|---|---|
| F01 | Start, explain, remember and resume the naval mode and its settings. | C03–C06, C11; D01–D02, D14, D24, D30–D31 | Native setup/launch/resume, settings accuracy and compatibility. |
| F02 | Purchase and launch an independent ship at the agreed exact cost. | C01–C02; D04, D10, D13, D24 | Engine accounting, app confirmation/cancellation, no-location/capacity cases and clear cost feedback. |
| F03 | Select and sail a ship through approved legal movements. | C01; D03–D05 | Legal transitions, allowance/path/occupancy cases, native interaction and readable previews. |
| F04 | See only discoverable geography and retain public discoveries. | C04–C05; D02, D05–D06, D11 | Exact distance-two boundaries, distance-three concealment, public permanence, hidden-target/accessibility checks. |
| F05 | Experience considered opening and discovery mist clearing. | C05, C11; D25–D27 | Reviewed animation recordings, before/after screenshots, stable camera, Reduce Motion and interruption evidence. |
| F06 | Establish settlements on reached land and then build roads there. | C07; D07–D08, D13 | Landing/site/distance/connectivity cases, contested shore native play, player-hand accounting and inland growth. |
| F07 | Choose resources from the optional flexible-production feature. | C06; D18–D20 | Entitlement/bank/card-choice scenarios, both AI choices, UI accessibility and economy evidence. |
| F08 | Capture any eligible opposing ship on 11 and keep control. | C08–C09; D09–D11 | Production/order/no-target/recapture/allowance cases, global target selection, ownership feedback and persistence. |
| F09 | Play varied worlds with useful expeditions and viable growth. | C03, C06–C07; D15–D23 | Annotated map critique, constraint tests, held-out generation sample and match/strategy evidence across selected families. |
| F10 | Continue ordinary trade, cards, production, scoring and victory coherently. | C07, C09; D12–D14, D21 | Complete phase tables, finite supplies, win reachability, economy and full-match evidence. |
| F11 | Play against complete Traditional naval opponents. | C10; D28–D29 | All action responsibilities, failure diagnostics, fair observations, completed games and agreed behavior/strength evidence. |
| F12 | Play against complete, versioned Expert naval opponents. | C10; D28–D30 | Strategy/value critique, naval revision persistence, fair projections, held-out comparisons and app-equivalent evidence. |
| F13 | Interrupt/resume and replay the exact same game meaningfully. | C05, C08, C11; D26–D27, D30 | Cold resume, state/version migration, pending choices, forward/backward replay and separate-process fingerprints. |
| F14 | Understand and operate the whole polished interface. | C05, C11; D24–D27, D32 | Real-scale early/mid/late visuals, adequate touch targets, selection versus pan/pinch, tap alternatives to dragging, overlay hit testing, large text, VoiceOver, non-color ownership and camera invariance. |
| F15 | Complete the match and use the agreed history/statistics/integrations. | C11; D12, D30–D32 | Native game-over/history/replay, compatible rating/sync/import behavior and existing-mode regressions. |

These features remain on the final acceptance list. An internal implementation
milestone cannot erase one, substitute a neutral AI fallback or restrict a confirmed
option without a recorded product decision.

## Selected requirement scenarios

All failed authoritative actions preserve state and RNG. Optional previews may
change presentation only. Production choices and capture are durable obligations;
optional selection and camera animation are not gameplay state. E01–E22 refer to
the evidence index below.

The closure statements below describe the original local-simulator delivery.
D45–D49 add build 24 obligations, closed for internal delivery in E29 with
explicit measurement limits. Historical closures retain their original source.

### F01 — Configure, understand and resume Voyages

**Sources:** C03–C06, C11; D01–D02, D14, D24, D30–D31.
New Game offers **Rules → Standard / Conquest / Naval**, Surprise me or one of
three map families, independent fog
and resource-choice switches, and Traditional or Expert opponents. Both switches
default on. The shipping setup has four seats and one human; the engine and
evaluation support three or four. The human need not occupy seat zero. The opening
starts in opaque mist, then surveys the 19-hex home before snake placement. Each
starting settlement may use any legal home site, including inland corners (D38).

Verify selection, deselection, explanations, exact saved options, first legal
placement/road in every family and cold resume. Naval selects its own island world
and the Standard engine variant, and returning to land rules restores the chosen
Classic/Vast board and target. Saved setup reopens with Naval selected (D33).
Conquest and Classic-only ghost identities cannot enter through new setup, import
or resume. Old Classic/Vast and legacy Expanded remain loadable. E01/E02 exercised
real Twin Islands setup with both options off and Expert, then cold resume;
`NavalOpeningTests`, `NavalMatchFlowTests` and `MatchSetupGhostTests` cover the
other contracts.

**Closure: closed for local simulator review.** Final setup/settings/resume, compatibility and ghost guards pass E20. E22 adds an ordinary Expert opening and a live exact-binary installation with verified saved options.

### F02 — Buy and launch independent ships

**Sources:** C01–C02, C14–C15; D04, D10, D13, D24, D42–D43, D46–D47.
A ship costs exactly two lumber, one wool and two ore. Only a sea hex touching the
builder's own coastal settlement/city can launch it. Confirmation subtracts those
cards once, returns them to the bank, consumes one of that builder's six lifetime
purchasable hulls and creates a persistent ship with its versioned allowance:
two hexes in new v3 games, three in legacy v1/v2. Capture does
not refund hull stock. A controller may own additional captured hulls.

Verify unaffordable purchase, no eligible coastal building, exhausted builder
stock, already occupied water and stacked identity selection. Preview/cancel
spends nothing, creates nothing and reveals nothing. `NavalGameplayTests` covers
exact accounting, stacking and builder stock; `NavalMatchFlowTests` covers durable
confirmation. E01/E02 purchase and cancel through native controls. D46 uses
natural owner/ship language; stable stored IDs and automation identifiers remain
unchanged. Its build 24 validation is recorded in E29; E20's one-based labels remain
historical evidence.

D43's Build menu names Ready/Unavailable, exact cards-held/cost and missing
quantities or phase/supply/location reasons. Only a legal build during the
displayed actor's main turn enables it. Verify disabled physical taps leave the
displayed costs unchanged and, after dismissing the modal, leave cards,
discoveries and proposals unchanged. A ready ship still cancels freely and pays
exactly once on confirmation, including cold resume (E28 targeted checks).

**Closure: closed for local simulator review.** E20 covers accounting, capacity, cancellation and one-based names. E21 commits a real purchase after preview/cancel; E22 preserves the inspected launched hull and exact artifact identity.

### F03 — Sail with a bounded, readable allowance

**Sources:** C01, C14; D03–D05, D47.
New v3 matches give each controlled ship two sea hexes at its owner's turn
boundary; purchase/capture grant two immediately. One confirmation commits a
reachable public sea destination costing one/two hexes, bounded by remaining
allowance, over one canonical shortest route. Legacy v1/v2 retain three hexes
and adjacent-only actions. Ships stack/pass through one another. Trading, cards
and construction may occur between voyages. A ship cannot cross land, leave the
world, move for another controller or exceed its saved-version allowance.

Verify explicit ship selection, stacked choices, Fleet access, destination preview,
revision/cancel/confirm, exhausted steps, turn refresh and a captured hull's fresh
allowance. Radius-two sight makes the complete v3 range already public; every
reachable endpoint shows its cost above cosmetic mist. Preview/cancel reveal
nothing; commitment reveals the same route's intermediate-radius-two union.
E29 requires actual one/two-hex confirmation, remaining-range paint and legacy
exact replay. E01/E02 commit three historical adjacent moves
and cold resume; `NavalGameplayTests` exercises invalid movement and refresh.

**Closure: closed for local simulator review.** Final rules, budget and routing checks pass E20. E21 commits three steps, discovery and cold resume; E22 records sequential preview/commit/remaining-step frames and World navigation.

### F04 — Conceal unknown geography and share permanent discovery

**Sources:** C04–C05; D02, D05–D06, D11, D40.
Fog conceals unknown land/sea identity, terrain resource, production number,
coastline and port. Committed ships and buildings reveal within exactly two hexes;
roads do not reveal. All players retain every discovery for the rest of the match.
Fog off exposes the same generated world. Capture and departure never re-fog it.
The world extent is public and fixed; hidden coastline cannot change camera fit.
Ports on charted coast are public even while adjacent sea remains fogged. All
four home ports appear before placement; overseas ports stay concealed until
the land beside their shared edge is known. Seeing a port grants no trade rate
without an owned settlement/city on an endpoint. E27 verifies this correction.

Verify radius two versus three at boundaries, overlapping sources, already-known
regions, inland reach, concealed labels/targets/ports, preview cancellation and
historical visibility before/after discovery. Masked observations also remove
hidden component metadata, future engine RNG/deck order and rival hand composition.
`NavalObservationTests`, `NavalSaveTests`, `NavalPolicyTests` and geometry tests
exercise these boundaries; E01/E02 show public charted counts only changing on
confirmation.

**Closure: closed for local simulator review.** E20 verifies masking, permanence and historical visibility. A22 positive regular/SE pixel checks and the deliberate failing renderer-only negative control are retained in E16/E17. E22 confirms outside fog stays opaque during the opening and painted replay reflects its historical discoveries.

### F05 — Experience coherent mist withdrawal

**Sources:** C05, C11; D25–D27.
Opaque opening mist withdraws to reveal the home survey; committed discoveries
withdraw mist around the sailed position. Authoritative discovery is already
durable before the cosmetic transition. Multiple discoveries cannot duplicate
cards, steps or reveals, deadlock a phase or move the camera. Interruption finishes
cosmetics while preserving the committed world. Reduced Motion uses a brief
readable alternative. Historical scrubbing restores the selected frame immediately.

Verify opening, travel, overlapping reveal, background/cold launch during motion,
camera invariance and the actual system Reduce Motion preference. E04 proves
SwiftUI receives the enabled system setting while Home/World remain usable; E01
checks camera stability across discovery. E11 preserves reviewed historical
opening mist withdrawal and bounded purchased-ship launch vision. Its opening
uses a fresh random seed that has not been recovered and a pre-final-AI artifact.
The reviewed launch/Fleet subset retains three steps and a staged Sail decision;
it is not committed sailing proof.

**Closure: closed for local simulator review.** E22 closes the final opening and discovery sequence with independently opened 2.4/2.8/3.1-second opening frames and 28.5/29.0/29.5/33.1-second committed sailing progression. Capture and actual system Reduce Motion frames are inspected. E20/E21 cover durable interruption, exact state and camera invariance. This is bounded sequential motion review, without an unsampled frame-rate or human-enjoyment claim.

### F06 — Found colonies, then grow a land network

**Sources:** C07; D07–D08, D13.
An owned ship adjacent to a coastal vertex allows an ordinary-cost settlement
without a road. Normal distance and piece limits apply. The ship remains. Payment
comes from the player's normal hand, with no cargo system. Further roads require
that player's existing land network; sea-only edges cannot accept roads. A first
settlement on each of a player's first two overseas land components grants one
permanent colony point, including a component already occupied by another player.
Repeat sites on the same component grant no extra colony point.

Verify road-before-settlement rejection, coastal/inland eligibility, competing
sites, a departed/captured ship invalidating a draft, city upgrades, repeated
island landings, third island without a third bonus and a two-point first-colony
move ending a 12-point game. `NavalGameplayTests` covers access/scoring and the
winning colony; E01/E03 cover real colony accounting/resume. Telemetry counts
overseas land rather than a home coastline or sea.

**Closure: closed for local simulator review.** E20 covers landing, settlement-first road access, cities, colony accounting and winning alternatives. E15 supplies complete naval behavior; E22 adds inspected actual overseas growth in the complete painted replay, with separate harvest fixture provenance.

### F07 — Harvest optional flexible production fairly

**Sources:** C06; D18–D20.
Two designated grain/wool baseline hexes on separate substantial islands become
resource-choice terrain with tokens 4 and 10. Switching it off restores those
ordinary resources without changing geography, numbers, ports, deck or RNG stream.
A settlement earns one choice; a city earns two separately chosen cards. Fixed
production resolves first, then clockwise choice obligations beginning with the
roller, then any pending capture. The bank offers stocked resources only. An empty
bank expires remaining units without creating debt or inventory.

Verify several owners/cities, partial first entitlement and remaining clockwise
suffix, scarce/empty bank, invalid choice, robber blocking, choice/capture order,
preview versus confirmation and cold resume with an unselected obligation.
Flexible economic valuation allocates each yield once across recipe deficits.
`NavalProductionTests`, `NavalProductionValidationTests` and both-tier policy
tests cover accounting; E01 proves one actual bank card and cold resume. E02/E04/E09
make all five choices and Collect reachable at the largest accessibility text size
on iPhone SE. E09 also exercises both units of one human city's harvest across cold
resume; E08 verifies failed persistence preserves both units until reconciliation.
E08's native contrast/hit-region/description/text-clipping audit passes unfiltered
with zero waived issues. The regular iPhone 17 Pro audit then failed disabled Collect
contrast in the first gate/serial reproduction. Its opaque-plaque style correction
passes unfiltered in E14 at both regular and small phone sizes. The corrected full gate passes E20; earlier failures remain recorded.

**Closure: closed for local simulator review.** E20 verifies entitlement, finite bank, choice/capture ordering, two-unit city cold resume and failed-write reconciliation. Unfiltered regular/SE audits and maximum-text choices pass, with no waived issues. E22 preserves inspected final-source maximum-text harvest; earlier contrast failures remain recorded.

### F08 — Capture a distant opposing ship on 11

**Sources:** C08–C09, C14; D09–D11, D47.
After an 11's fixed and flexible production, the roller may capture any opposing
ship globally or explicitly skip. With no eligible opposing ships, play advances
directly to the main turn. Confirmation changes only the selected hull's current
controller and grants the saved match's allowance (v3 two; v1/v2 three); location, ID, builder stock, victim hand and
existing colonies remain unchanged. The transfer persists until another capture.
An unrelated 11 does not return it. Robber/Knight cannot destroy or capture ships.

Verify distant targets, own-ship exclusion, no-target/skip, original-owner and
third-player recapture, a previously moved target, maximum builder stock, saved
pending capture and unconfirmed selection. Capture identity/focus must not reveal
unknown geography; every ship's location is already publicly discovered.
`NavalGameplayTests`, production validation and app transaction tests cover the
rules. E01 exercises both skip and selected global takeover, including cold resume.

**Closure: closed for local simulator review.** E20 verifies global eligibility, skip, recapture, stock and allowance. E21 exercises selected capture, cold resume and confirmation; E22 shows the changed controller flag and durable capture receipt.

### F09 — Generate purposeful varied worlds

**Sources:** C03, C06–C07; D15–D23.
The radius-seven world has 169 hexes: 19 home land and 28 overseas land, separated
by two sea rings. Archipelago has 7/7/7/7 land groups; Peninsula 14/4/7/3; Twin
Islands 11/3/11/3. Surprise me chooses families equally. Generation varies actual
connected coast shapes, approaches, orientation, resources and ports while
preserving connected sea, no home bridge, at least three usable coastal sites per
component and land discoverable within two hexes of reachable water. Each credible
home harbor has at least two distinct destinations within six actual sea steps.

Verify resources/tokens/ports, no adjacent 6/8, island production floor, ordinary
resource viability, 64-attempt bound, all same-family fallback orientations and
four option pairings. E06 preserves 3,000 studied worlds, 12,000 option worlds,
72 validated fallback combinations and fifteen actual exports with critique.
Generation diversity counts include orientation; pips do not price wild flexibility.

**Closure: closed for local simulator review.** E06 preserves all three families, four option pairings and 72 validated fallbacks. E15 completes the twelve-cell naval matrix; E20 passes generation constraints. E22 verifies the actual saved Archipelago review world. Human map preference is unmeasured.

### F10 — Complete ordinary economy and fourteen-point victory

**Sources:** C07, C09; D12–D14, D21, D43–D44.
Voyages keeps normal personal-hand construction/trade, land robber and cards,
Longest Road/Largest Army (two points, thresholds five/three) and reaches victory
at fourteen. Ships contribute to neither road length nor a navy award. Supplies
are six settlements, five cities, twenty roads per player, 38 bank cards per
resource, fifty development cards and discard above ten. Colony bonuses total at
most two per player. Production/card/bank accounting remains finite.

Verify deck exhaustion, Year of Plenty ship funding, Road Building on eligible
land only, discard without invented cards, robber/fog/sea restrictions, winning
city/colony/Knight, phase advances and games without ship investment. E01 reaches
and archives an actual Expert match through the shared session. Engine and AI
tests exercise supplies and winning alternatives. Terminal victory must stop
pending automated negotiation; a winning move with an open offer cannot invoke a
policy on empty terminal legal moves or revive a saved game. E14's three engine
regressions and hosted completed-checkpoint restore cover this first-gate defect.

D44 separates the full Skip/Retry hit rectangle from trailing trade answers.
Repeated center/padding touches must leave the new offer unanswered and cards
unchanged. Verify deliberate accept/reject, actual expiry without exchange,
full-review hold, Back retaining the hold, summary-tap resume and occurrence-bound
timer replacement. The targeted E28 journeys include maximum text, cold resume
and restart; they do not change trade accounting or decision provenance.

**Closure: closed for local simulator review.** Finite economy, trade/cards, score, terminal guards and full-match regressions pass E20. E15 completes all held-out games. E22 preserves separately identified actual Expert victory and painted replay; completion is not a human pace judgment.

### F11 — Face complete Traditional naval strategy

**Sources:** C10; D28–D29.
Traditional deliberately buys/funds ships, navigates using public information,
reserves useful landing access, settles, grows roads/cities, captures, harvests,
trades, uses cards and closes wins. It has its own tier identity and personality
variation. No neutral fallback substitutes for an unsupported naval action.
Hidden terrain, component membership, rival exact hands, future deck and engine
RNG are unavailable to both decisions and projected candidates.

Verify every action responsibility, incomplete-observation rejection, fair paired
hidden-world decisions, deterministic response-only RNG, trade funding preservation,
capture recovery, exhausted bank, funded-voyage discard and winning alternatives.
`NavalPolicyTests`, mixed-session and navigation-diagnostic tests cover these cases.
Earlier development matrices completed across all twelve map/option cells. E07
now records the frozen corrected Traditional anchor and final Expert candidate;
completed confirmation and the durable full report are preserved in E15.
The frozen AI package suite passed in the first gate (E12).

**Closure: closed for local simulator review.** Complete Traditional responsibilities and information invariance pass E20; frozen naval-capable Traditional games complete in E15. E07 retains the integrated trajectory bridge. E21/E22 native rare-state journeys actually use Traditional, with explicit fixture bounds.

### F12 — Face a distinct, versioned Expert naval strategy

**Sources:** C10; D28–D30.
Expert uses a persisted naval revision and deliberately compares economic,
position and closing opportunities across the same complete action set. Existing
Classic Expert revisions retain their meaning. A publicly certain new component
can make a first colony worth two immediate points; uncertain fog connectivity
cannot promise that bonus. A better reachable landing may improve an unfunded
voyage without surrendering access; returning to the poorer site is not progress.
Owning every victory card removes an invented immediate winning-draw premium.
Certain sailing, launch/landing and direct wins rank above uncertain finishing-card
draws. Expert's funding targets include a winning Longest Road even when settlement
supply is exhausted or every settlement approach is blocked.

Verify those counterexamples, opportunity cost against cities/cards, shared
discovery, crowded shores, idle cycles, unfair information and persisted revision.
E10 records the latest focused corrections; E12 verifies the frozen integrated AI
package suite in the failed first gate. E15 records the completed held-out
confirmation; the final app/session gate passes E20.
Refinement uses development seeds. Strength confirmation requires frozen naval
Traditional and Expert binaries, paired held-out seeds, all chairs and separate
three/four-seat estimates with confidence intervals. The preregistered ten-percentage-point
meaningful improvement and reliability/latency criteria may not be lowered after
seeing results.

**Closure: closed for local simulator review.** E15 meets the unchanged declared improvement criteria at each table size with paired confidence intervals. E20 verifies revision persistence and counterexamples; E07 retains the bounded integration bridge. E22 separately attributes the Expert ordinary opening, saved review position and actual completed-match/replay records.

### F13 — Resume and replay exact recorded play

**Sources:** C05, C08, C11; D26–D27, D30.
Cold launch restores committed ships, steps, hull stock, public reveals, colony
points, options, policy revision and pending resource/capture obligations. Optional
drafts disappear; mandatory obligations reopen unselected. Failed persistence
keeps the pre-commit state and retryable draft. Every new state field has legacy
decode defaults; unsupported or incoherent naval state is rejected explicitly.
Replay paints the discoveries, pieces and controllers of the selected move.
Build 22 accepts an older queued trade reply only when its complete observation
matches the former harbor projection reconstructed from authoritative state.
Resume updates that public chart while preserving the sampled move, evaluation
index, counters, ledgers and RNG; every other integrity guard remains required.
Authoritative state and recorded move effects are unchanged (E27).

Verify same transcripts after cold checkpoint, separate-process fingerprints,
legacy modes, version routing and forward/backward history. History validation
compares the full authoritative state, apart from the documented declined-offer
cache normalization. Coherent unrecorded changes to position, controller, movement,
discovery, hull stock or colony points must fail both cold and incremental history
validation. E03 has thirteen hosted test functions; E08 verifies failed-city-harvest
persistence and reconciliation; E09 confirms its same-human two-unit cold resume.
E05 additionally checks actual
painted buildings, roads and sea after final/start/final scrubbing. E13 independently
shows the final candidate painting a completed 644-move replay in the live gate
worker, before an official app/UI verdict.

**Closure: closed for local simulator review.** E20 covers full-state corruption rejection, legacy saves, queued confirmation and painted replay restoration. E07 retains separate-process/bridge evidence; E21 commits and cold-resumes actual purchase/capture journeys. E22 preserves the inspected final-source 644-move painted replay and fresh process receipt. No incomplete historical result is counted as a final pass.

### F14 — Operate the complete themed interface

**Sources:** C05, C11; D24–D27, D32, D40–D44.
Painted sea/mist, established textured land, eight controller-colored painted
ship styles and gold/blue controls preserve the existing theme. The sail/hull
identifies current control without a castle overlay; shared actual/proposed
visual sizes and capped thin selection borders retain readability (D42).
Home, World and Fleet
offer readable local navigation, whole-world context and explicit ship selection.
The naval navigation strip sits inside the fixed board frame. Discovery never
auto-focuses. Every map layer clips to the same viewport at zoom/pan; command rows
stay fixed. Ownership and choices have text/shape cues as well as color.
Displayed and spoken discovery counts use appropriate singular/plural wording.
World changes to Return and restores the preceding local pose exactly, including
zoom one. Home and explicit ship selection end that excursion. Charted harbor
badges/docks paint above decorative mist, and the navigation strip stays clear
of the human HUD through setup, CPU pauses and cold resume (E27).

D43's compact Build popup has one measured choices ScrollView, with header and
Close pinned outside it. D44's answer controls mount once while only summary
terms scroll; clipped terms require Review before acceptance. E28 separates
asset/runtime checks from inspected paint and requires the entire ship to be
inside the viewport before using a maximum-zoom image as visual proof.

Verify forty-four-point action targets, magnification and tap alternatives,
neighbor/stack disambiguation, fixed board/dock across phases, modal isolation,
maximum text, VoiceOver labels, reduced motion and small/ordinary phone layouts.
E01/E02 test Home/World/pinch/pan; E04 proves actual system Reduce Motion.
E08's native cover blocks covered commands/navigation/HUD interaction and passes
the unfiltered harvest accessibility audit. The source provides heading focus,
an actual forty-four-point button hit shape and readable disabled opacity.
E09 verifies maximum-text harvest and results actions. Automation element existence
alone does not establish VoiceOver navigation, and manual VoiceOver play is not
claimed. One-based ship labels preserve internal identity.

**Closure: closed for local simulator review.** A21/A22 interaction and concealment checks, A23 complete-row maximum-text checks and unfiltered modal audits pass E20. E19 independently inspected Nearby/Fleet paint on both phone sizes. E21 proves camera/navigation behavior; E22 adds final opening, movement, capture, harvest, victory and replay images. Manual VoiceOver play and quantitative animation frame-rate remain unmeasured.

### F15 — Finish, inspect history and preserve integrations

**Sources:** C11; D12, D30–D32.
Victory exposes the result, colony point breakdown, new game/menu and replay.
History, local statistics and import/export preserve the naval mode, rules/map
versions and recorded trajectory. Voyages is local/unrated and cannot publish
unlike matches to the online ladder or train a Classic ghost. Imported/resumed
ghost identity is rejected as well as an explicitly selected ghost seat. Existing
mode histories, ratings and sync semantics remain compatible.

Verify actual game-over archive/history/replay, winner actions, coherent and
corrupt imports, profile-only ghost identity, no rated/ghost side effects and
Classic/Vast/Expanded regressions. E01 archives a real completed match; E03 covers
history integrity and ghost setup rejection while retaining Classic resume.
E09 proves the results action remains reachable at maximum accessibility text.

**Closure: closed for local simulator review.** E20 verifies actual completion/archive/replay, compatible imports, local unrated naval identity and existing-mode regressions. E22 preserves distinct Expert completed-match and replay journeys plus the fresh installed review profile. No rating or distribution claim is inferred.

## Cross-feature scenario catalogue

### Opening and geography

- Fully fogged introduction, the approved initial view, and the disabled-fog case.
- Hidden terrain, numbers, shorelines and inspection/VoiceOver text stay concealed.
- Radius two at the center, edge and corner; radius three remains unknown.
- Multiple ships' views overlap; one discovers a region already discovered by another.
- Peninsula, branching islands and selected alternative examples have navigable
  approaches, viable coastal sites and considered inland visibility.
- Narrow/blocked passages, tiny islands, land bridges, thick interiors and otherwise
  valid topology with a poor production distribution are examined explicitly.
- Rejected seeds terminate through the selected bounded generation behavior.
- The same seed/version/settings reproduce geography across separate processes.

### Ships, settlements and capture

- Exact purchase stock subtraction and unaffordable/capacity/no-launch outcomes.
- Selection, preview, path revision, cancel and confirm; cancellation reveals nothing.
- Travel through unknown cells, discovered land, occupied water and map boundaries
  follows the selected rules without exceeding movement or mutating state on failure.
- First overseas settlement, later roads, city upgrade and competing site occupation.
- Founding a settlement leaves the ship available for further voyages under D08.
- An 11 with no opposing ships, one ship or many ships, including a distant target.
- Production, capture and victory resolve in the approved order.
- Recapture by the original controller or a third player; no automatic reversion on
  a different 11; the victim's hand and existing colonies remain their own.
- Capture after movement, at fleet capacity, before another player's planned landing,
  during a stale preview, and on a game-ending turn.
- Capture and departure do not re-fog discoveries or award duplicate benefits.

### Economy and choices

- Both optional features work independently and together; off states have meaningful
  map/economy/play rather than becoming unsupported configurations.
- Fixed production and flexible production respect per-building entitlement, selected
  timing, finite bank, several owners and multiple simultaneous choices.
- Flexible output is allocated once; economic evaluation cannot spend the same yield
  toward every resource recipe simultaneously.
- Home-only building, expeditions, waiting for capture and rapid overseas growth are
  critiqued as strategies, including wildcard monopolies and exhausted supplies.
- Trades and development cards interact with ship funding and new phases correctly.
- Target score remains reachable with realistic site/piece/deck availability.

### AI behavior and information

- Both tiers buy, launch, move, discover, settle, extend roads, capture, choose
  resources, trade, use cards and finish games under the settled rules.
- Identical public state, own information and policy tie-break RNG produce identical
  decisions when undiscovered geography or authoritative future randomness differs.
- Legal action contents/order, heuristics, candidate projections and events cannot
  leak concealed geography. Private-hand access follows the explicitly selected
  information contract rather than being changed invisibly.
- Capture recovery, losing a contested landing, crowded shores and nearly complete
  discovery do not produce idle fleets, repeated routes or runaway trade loops.
- Versioned decisions/reasons and naval milestones make failures inspectable.
- A comparator incapable of naval play, or relying on neutral fallback counts, cannot
  stand in for a frozen naval-capable strength anchor.

### Lifecycle and presentation

- Interrupt opening, travel, discovery and capture with settings, handoff,
  backgrounding, termination and persistence failure.
- Durable state and mandatory obligations resume consistently. Uncommitted drafts
  and animation progress follow D26–D27's explicit recovery contract; optional
  drafts need not survive cold launch, and mandatory choices may reopen unselected.
  Cosmetic replay cannot duplicate resources, reveals, movement or control changes.
- Historical replay displays the discoveries and control at that move; backward
  scrubbing does not retain future knowledge in the displayed world.
- New previews do not move the command row or change board extent/fit/zoom/pan.
- Ships, pieces and mist clip to the actual board viewport at zoom and pan.
- Ownership is understandable without color; VoiceOver reveals only permitted
  information; large text and Reduce Motion remain usable.
- Action controls have at least 44-point touch targets. Closely neighboring ships
  and landing sites can be selected reliably without accidentally panning/zooming;
  dragging has tap alternatives. Controls hidden beneath overlays are excluded
  from hit testing and VoiceOver navigation.
- Opening beauty, quiet sailing, contested captures and crowded late-game readability
  each receive inspected evidence and refinement, not only a launch screenshot.

## Coverage matrix

Cross the selected map families with:

- Fog on/off × resource-choice on/off: all four setting combinations.
- Supported three- and four-seat tables; Traditional, Expert and mixed tables.
- Human in different/nonzero seats and agreed hot-seat configurations.
- Opening, first voyage, first colony, competition, repeated capture, late game
  and victory; interrupted/resumed variants for consequential transitions.
- Agreed narrow/ordinary simulator sizes, large text, VoiceOver and Reduce Motion.
- Existing Classic and Vast starts, legacy Expanded resume, persisted Expert
  revisions and the decided Conquest/ghost/rating/sync compatibility.

Engine and policy tests cover rule/setting combinations; native tests exercise
representative complete journeys and targeted interactions at ordinary and narrow
phone sizes. The shipping UI is four-seat/one-human; three-seat and legacy
multi-human behavior is covered at engine/session boundaries, not represented as
new shipping setup controls. One successful match does not cover this matrix.

## Evidence index

Selected final logs, summaries and manifests are retained with portable repository
links. Original valid result bundles and raw movies remain in the durable external
artifact directory. Earlier temporary receipts are explicitly historical. Relative
source links identify coverage, not proof that a test ran on the final tree.

| ID | Receipt and verified observation | Scope and limitation |
|---|---|---|
| E01 | [Integrated native log](/tmp/empires-naval-derived/integrated-naval-tests.log): nine hosted functions in two suites (2.862 s) and seven native journeys (220.745 s), overall `TEST SUCCEEDED`. | iPhone 17 Pro, iOS 26.5, Debug; setup, purchase/sail/resume, skip/capture, camera, harvest and real Expert victory/archive. Earlier snapshot; the initial semantic replay check did not prove painted final state. |
| E02 | [Small-screen log](/tmp/empires-naval-derived/small-screen-tests.log): four native journeys, zero failures (86.008 s), overall `TEST SUCCEEDED`. | iPhone SE (third generation), iOS 26.5, Debug; purchase/sail/resume, maximum text harvest, camera and shipping setup. Later icon/name/visual refinements require final recheck. |
| E03 | [History integrity log](/tmp/empires-naval-derived/history-integrity-tests.log): thirteen functions in three suites (1.819 s), overall `TEST SUCCEEDED`. [Ghost/AX log](/tmp/empires-naval-derived/ghost-and-accessibility-tests.log): ten ghost setup functions pass, but the combined command fails on the earlier max-text case. | Cold/incremental full-state validation and coherent six-way naval corruption; ghost import/resume identities. Do not call the mixed ghost/AX command green. |
| E04 | [Accessibility detail log](/tmp/empires-naval-derived/accessibility-audit-detail.log): max-text harvest passes (15.977 s), actual system Reduce Motion passes (20.576 s). | iPhone SE. The earlier native harvest audit fails contrast on an underlying Greece label (12.395 s); overall `TEST FAILED`. Subsequent modal/audit correction passes in E08. Element presence alone is not proof of manual VoiceOver reachability. |
| E05 | [Rendering/AX log](/tmp/empires-naval-derived/rendering-accessibility-tests.log): replay pixel test passes (225.452 s). | A real seed-7501 Expert match precedes final/start/final scrubbing; at least one painted home building, two roads and three sea probes are checked. Combined command has two AX/Settings failures. Disk exhaustion left its xcresult incomplete; the valid final rerun is E20 and inspected exported replay is E22. |
| E06 | [Map gallery and critique](evidence/map-gallery.md), [generation log](evidence/map-generation-study.log), [summary](evidence/map_study_summary.csv), [economy](evidence/map_study_economy.csv), [routes](evidence/map_study_routes.csv), [sample checksums](evidence/gallery_manifest.csv). | Actual generator `a15d72e`, unchanged by later save validation; 1,000 seeds/family, all toggle pairings and 72 forced fallbacks. Reproducible exports support geography claims, not human preference or bot strength. |
| E07 | [Frozen candidate provenance](/tmp/naval-ai-evidence/candidate-d863991/provenance.json), [Traditional anchor](/tmp/naval-ai-evidence/anchor-a316139/provenance.json), [durable study](evidence/ai-study.md), [integrated 48-trajectory bridge](evidence/integrated-ai-equivalence.md) and [portable tool/evidence package](../../../Packages/CatanAI/Tools/NavalEvaluation/README.md). | Earlier pilots remain development evidence. Declared confirmation is E15; bridge comparison excludes only build ID and retains original study/performance attribution. |
| E08 | [Harvest recovery and audit log](/tmp/empires-naval-derived/final-harvest-recovery-tests.log): seven hosted functions in one suite (2.339 s), including failed two-unit city harvest reconciliation; native harvest audit passes (9.279 s), overall `TEST SUCCEEDED`. | UI `02eb013`, iPhone SE, Debug. Full contrast, hit-region, sufficient-description and text-clipping audit, no ignored/waived issues. Covered Build, World and opponent HUD are not hittable. Final-tree verification is the separate passed E20 gate. |
| E09 | [Refined modal log](/tmp/empires-naval-derived/refined-modal-tests.log): same-human city two-unit cold resume passes (14.221 s). [Native modality log](/tmp/empires-naval-derived/native-modality-tests.log): maximum-text results (8.573 s), maximum-text harvest (14.785 s) and one-card cold resume (14.368 s) pass. | Maximum-text results use an explicit end-game layout fixture; E01 supplies actual victory evidence. These earlier combined commands each report `TEST FAILED` on superseded audit/assertion cases. Their named scenario passes remain evidence, not a claim that either complete command passed. E08 replaces the final harvest audit failure. |
| E10 | AI corrections integrated as `d7596bc` from `d8639917`: certain wins outrank uncertain draws; winning Longest Road gets an independent funding target. Thirty-four focused strict AI functions passed in 5.96 s, reported by the AI agent. | Actual counterexamples are in `NavalPolicyTests`. Current integrated full-package pass is E12; core gate and frozen confirmation pass E18/E15; final app-source gate passes E20. |
| E11 | [Visual/motion review](evidence/visual-review.md) and [original still checksum manifest](evidence/motion/opening-manifest.json): inspected opening 17/19/24/home images and bounded earlier launch/selection sequence. | Historical Debug binary SHA `e5410fbd…4435`, UI `02eb013`, pre-final AI `2099a14`. Opening movie is 3.046667 s including launch, random seed unrecovered. Mist clears at home while outside fog/viewport/dock stay fixed. Launch/Fleet subset does not prove committed sailing/capture; final reviewed footage is E22. |
| E12 | [First full-gate log](evidence/receipts/full-gate.log), source `02eb013`: engine 329 functions/19 suites pass (29.179 s); AI 281 functions/27 suites pass (628.389 s). Coverage engine 96.52%, AI 95.63%, each above 95%. All other non-app stages, Release and Debug pass. [Failed receipt](/Users/alex/.codex/artifacts/naval-exploration/first-gate-failed.xcresult) and [manifest](/Users/alex/.codex/artifacts/naval-exploration/first-gate-manifest.json) are preserved. | **Whole gate FAILED, exit 1: app tests failed.** Hosted terminal-trade crash caused collateral failures; two Classic trade native cases and regular-phone disabled Collect contrast also failed. Serial reproduction/fixes are A18–A20/E14. No whole-gate pass is claimed. |
| E13 | [Live first-gate replay screen](/tmp/empires-naval-final-evidence/live-gate-screen.png), opened by root/documentation reviewer at 00:53: Move 644/644, scores 5/14/4/8, correctly painted buildings/roads/sea, two overseas islands/ships and remaining fog. | Source candidate `02eb013`, task-owned XCTest worker `91F75F96…`. Visual inspection is preserved even though the overall first gate failed. Visible “1 hexes” is A17, now corrected in source; final corrected-source replay inspection is E22. |
| E14 | [Terminal engine log](/tmp/empires-naval-final-evidence/terminal-engine-tests.log): three meaningful terminal-queue regressions pass (0.005 s). [First serial follow-up](/tmp/empires-naval-final-evidence/gate-failure-followup.log): completed-checkpoint restore passes but two Classic trade cases/disabled Collect contrast reproduce, overall `TEST FAILED`. [Second serial follow-up](/tmp/empires-naval-final-evidence/gate-failure-followup-2.log): 22 hosted functions/two suites pass (9.104 s), including live/cold human confirmation and exact-once transfer; native bank receipt 9.897 s, popup/new-offer 24.518 s and unfiltered regular-phone harvest audit 10.285 s pass, overall `TEST SUCCEEDED`. [Final small-phone log](/tmp/empires-naval-final-evidence/final-small-screen.log): unfiltered audit 10.011 s, max-text harvest 14.280 s and max-text results 8.456 s pass, overall `TEST SUCCEEDED`. | Source fixes committed `be5ddeb`, tools/report `a8bd01c`. The core full-gate run at `a8bd01c` passes E18; final fresh-install/native evidence applies after later map/chooser fixes. |
| E15 | [Frozen AI study and exact evidence](evidence/ai-study.md): 1,464/1,464 held-out games complete, no functional rejection. Three seats: Expert 205/396 (51.77%, Wilson 46.85–56.65%), control 132/396 (33.33%), paired +18.43 pp (95% CI +13.64–23.23). Four: 154/336 (45.83%, 40.58–51.18%), control 84/336 (25.00%), paired +20.83 pp (+16.37–25.30). Both observed effects exceed ten points and paired CIs exclude zero. [Tool tests](/tmp/empires-naval-final-evidence/naval-tool-pytest.log): 39 pass; [retained-evidence hash check](/tmp/empires-naval-final-evidence/naval-tool-evidence.log) passes. | Twelve map/option cells, every chair, balanced personalities, table sizes separate; applies to this frozen naval-capable anchor/candidate pair. Uncontended 24-game host max per-game p95/p99 21.079/49.637 ms, zero >150 ms. Contended full study meets aggregate budgets but retains 48 >150 ms decisions and worst per-game tails 53.562/194.267 ms. Timing excludes rendering/phone execution; human experience and other personality mixes unmeasured. Integrated 48-trajectory bridge report/data are preserved and linked in E07. |
| E16 | [Regular map-fix log](evidence/receipts/map-fixes-final.log), [summary](evidence/receipts/map-fixes-final-summary.json) and [durable result](/Users/alex/.codex/artifacts/naval-exploration/map-fixes-final.xcresult): source `4f9eeb0`, 37 hosted/four suites plus seven native functions, 44 functions/54 runs, zero failed/skipped, overall exit 0. Adjacent 10.509 s, stacked 22.220 s, exact World launch 10.907 s and fog pixel 8.486 s pass. [Deliberate negative-control result](/Users/alex/.codex/artifacts/naval-exploration/fog-negative-control.xcresult)/[summary](evidence/receipts/fog-negative-control-summary.json): removing only the renderer guard fails hidden perimeter 0.5157907 >0.02 while known positive control passes; exact source restored. | Negative command exit 65 is intentional detector evidence, not a positive pass. Regular true-positive command is separate. Final adaptive chooser source/gate not covered by this receipt. |
| E17 | [Expanded SE log](evidence/receipts/map-fixes-small-final.log), [summary](evidence/receipts/map-fixes-small-summary.json) and [durable result](/Users/alex/.codex/artifacts/naval-exploration/map-fixes-small-final.xcresult): source `c00a07a`, ten native functions pass, exit 0 (154.552 s), zero failed/skipped. Buy/sail/cold resume 30.768 s, max-text nearby 29.757 s, stacked 23.366 s, exact launch 10.421 s, adjacent 10.055 s and fog pixels 8.349 s pass. | **Functional pass does not close F14 visuals.** [Inspected maximum-text screenshot](/tmp/empires-naval-final-evidence/map-fixes-small-attachments/1914B570-E85D-48DC-86C4-F0ACD3162E30.png) truncates Nearby/Close and paints row fragments. This preserved failure led to A23; correction/two-size paint pass E19 and final gate E20. |
| E18 | [Core full-gate log](evidence/receipts/full-gate-final.log), [summary](evidence/receipts/core-gate-summary.json) and [durable result](/Users/alex/.codex/artifacts/naval-exploration/core-gate-a8bd01c.xcresult): source `a8bd01c`, all eleven stages pass, exit 0. Engine 332/19 suites (16.871 s), AI 281/27 (413.559 s), coverage 96.54%/95.65%; app/UI 538 functions/1,191 parameterized runs, zero failed/skipped. Debug executable SHA `6ccf1db4302437ccaf6dabfcf51cc42acf5e08ae71a1240044fb17f88c3364e5`. | Core source precedes later map/chooser changes. A23 correction is verified E19; final-source full gate E20 and artifact E21/E22 close the later changes; the core gate alone did not waive them. |
| E19 | Source `971a615`: [regular durable receipt](/Users/alex/.codex/artifacts/naval-exploration/a23-regular.xcresult)/[summary](evidence/receipts/a23-regular-summary.json) passes the strengthened both-entry-point maximum-text test (56.713 s). [SE durable receipt](/Users/alex/.codex/artifacts/naval-exploration/a23-small.xcresult)/[summary](evidence/receipts/a23-small-summary.json) passes ten native functions, including Nearby/global Fleet (79.411 s). Root/documentation reviewers opened regular [Nearby](evidence/screenshots/nearby-accessibility-regular.png)/[Fleet](evidence/screenshots/fleet-accessibility-regular.png) and SE [Nearby](evidence/screenshots/nearby-accessibility-small.png)/[Fleet](evidence/screenshots/fleet-accessibility-small.png). | Complete selected Ship 3 cards, owner/steps, wrapping headings and forty-four-point Close are readable/themed. Previous partially scrolled rows are expected. Read-only lifecycle/current-ID/layout review found no actionable new defect. Final frozen-source gate passes E20; final installed media/process handoff passes E22. |
| E20 | [Final frozen-source gate log](evidence/receipts/full-gate-971a615.log), [summary](evidence/receipts/full-gate-971a615-summary.json) and [durable result](/Users/alex/.codex/artifacts/naval-exploration/full-gate-971a615.xcresult): `971a615`, all eleven stages PASS, exit 0. Engine 332 functions/19 suites (16.379 s), AI 281/27 (395.098 s), coverage 96.59%/95.63%, app/UI 552 functions/1,211 runs, zero failed/skipped. App tests 1,342 s; Release/Debug builds pass (44/2 s). Final Debug executable SHA256 `2ab9e0852e6e5db7ef13f9b3eaeba8bf7291bc315e6abeadf5e1ea2dc1c458f8`. | All 23 audit corrections are verified on this final source. Exact-binary fresh-install/process/media/F05 handoff passes E21/E22; it is evidenced separately from compile/tests. Earlier failed/negative receipts remain preserved. |
| E21 | [Exact-gated native journey log](evidence/receipts/final-artifact-journeys.log), [summary](evidence/receipts/final-artifact-journeys-summary.json) and [durable receipt](/Users/alex/.codex/artifacts/naval-exploration/final-artifact-journeys-971a615.xcresult): `test-without-building`, exit 0, source `971a615`, executable SHA unchanged from E20. Purchase preview/cancel, real purchase/three sailing steps/discovery/cold resume pass 31.122 s; capture proposal/cold resume/confirmed transfer 14.281 s; actual Settings Reduce Motion, Home/World and preference restoration 19.636 s. | Exact binary has real native gameplay proof. These rare-state journeys use Traditional, conserved QA baselines and actual subsequent commits. The raw 73.461667-second 1206×2622 movie and sampled progression are inspected in E22; ordinary Expert opening and live review configuration are separately attributed. |
| E22 | [Fresh installed-artifact receipt](evidence/receipts/final-installed-artifact.json), [screenshot manifest](evidence/screenshots/final-artifact-manifest.json), [motion manifest](evidence/motion/final-motion-manifest.json) and [independently inspected gallery/sequences](evidence/visual-review.md#final-gallery-and-motion). Exact E20 Debug binary, version 1.0/build 16, freshly installed on Empires Voyages Review, iPhone 17 Pro/iOS 26.5; ordinary opening PID 28765 survives, then deliberate reinstall/review PID 36072 survives with no new Settlers crash reports. | Expert/Naval V1 Archipelago review checkpoint: four seats, fog/resource choice ON, human 0 main turn, 46 charted hexes, zero human ships. Conserved extra-card review baseline; Build → Ship makes a real purchase. Ordinary Expert opening has no fixture grant. Traditional purchase/capture/motion journeys and final-gate instrumented Expert victory/replay are separately attributed. Sequential movie-frame review closes F05, without FPS/phone/manual-VoiceOver/human-fun claims. |
| E23 | [Naval Rules correction receipt](evidence/receipts/naval-rule-selector.json): `ac3dec5`; initial 22-function setup/navigation run, strengthened six-native run, 37-function/71-run SE hosted/native run and final aligned shipping journey on each size pass. Strict lint and Release/Debug exit 0. Historical PID 86428 survived; checkpoint byte-identical, no new crashes. | Original screenshots show Standard/Conquest/Naval, selected Naval/island settings and maximum-text SE Rules. Initial filename-style hosted filter matched no setup suites; actual suite IDs were subsequently run. Ambiguous background Rules lookup failed, was scoped/corrected and passed on both sizes. Engine/AI/save source unchanged. E20 remains the earlier full gate; no new full-gate or phone-install claim. |

The E01/E02 logs record result names `2026.10.04_23-43-51--0400` and
`2026.10.04_23-56-29--0400`. Those older result directories are no longer present
in the active DerivedData folder at this checkpoint; the retained logs and exported
images remain historical evidence. The `2026.10.05_00-05-12--0400` result was
incomplete after disk exhaustion. E20/E21 retain valid final result bundles. No absent or incomplete historical receipt
is treated as a passing final stage.

## Build 24 follow-up (E29): delivered

D45–D49 are integrated into the managed
`/Users/alex/.codex/worktrees/naval24-main-integration/Settlers` checkout above
current main `83d8525`. Naval squash `527e1ed`, artwork test port `09f5e94` and
accessibility/travel refinement `9bce5f7` preserve main's resource-square,
Skip/Block, leaderboard and ghost-rename fixes. Production is frozen at
`9bce5f77a38684bd6e011fac8838c74b38440798`, version 1.0/build 24. All
[376 app/package/configuration/asset inputs](evidence/receipts/build24-final-production-inputs.json)
match the freeze. The first complete pre-push full gate (session `52090`) failed;
two test-only oracle corrections are committed as `67efbad`. Production/package
inputs remain unchanged. The replacement full gate (session `91604`) passes all
ten mandatory stages, exit 0, and publishes `codex/naval24-main-integration` at
`67efbad`. Ordinary Release runtime and the 23-original final gallery now pass
local review. Archive/export/upload and strict/deep Production signing pass.
Apple 1.0/build 24 is VALID, unexpired and internally IN_BETA_TESTING, with
Alex's Internal all-build access confirmed at 13:06:46 UTC (9:06:46 a.m. EDT),
October 7, and by independent fresh readback at 13:06:40 UTC. Build 24 is now the
latest verified internal delivery.
[PR #60](https://github.com/jakebeinart1/Settlers/pull/60) is attached and awaits
at least one actual approval; required tested-head CI passes, no merge.
External availability and physical-phone installation/play remain unobserved.

### Retained development failures and native results

The original branch's first [attempt](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/first-focused.log>),
[second](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/second-focused.log>),
[third](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/third-focused.log>)
and [fourth](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/fourth-focused.log>)
failed compilation before tests ran: initializer self-capture, internal checkpoint
access/missing `for:`, mutating `#require`, and actor-isolated configuration.
The repaired [fifth summary](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/fifth-focused-summary.json>)
and [log](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/fifth-focused.log>)
pass 71 functions/107 runs, zero failures/skips, including 58 hosted functions in
eight suites and 13 native functions. These were intermediate 1.0/23 checks.
Root inspected eight originals; rival image `D759D58C` was taken after timed news
expired and remains excluded from result-news paint proof.

The current-main [integrated focused summary](evidence/receipts/build24-main-integrated-focused-summary.json),
[log](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/main-integrated-focused.log>)
and [result](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/main-integrated-focused.xcresult>)
report **FAILED**: 121 functions, 117 passed, three failed and one conditional
natural-seven skip; 155 passing runs, three failed runs and one skipped run.
The three failures exposed a 14-point progress `Other` element incorrectly marked
interactive, an obsolete numbered-ship oracle, and an exact-centering camera
oracle despite the full tile already being visible. The corrections expose
noninteractive `StaticText`, use stable vessel IDs, and require complete tile
bounds after actual camera clamping. The last two were test-oracle corrections.

The [refined summary](evidence/receipts/build24-main-refined-focused-summary.json),
[log](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/main-refined-focused.log>)
and [result](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/main-refined-focused.xcresult>)
still report **FAILED**: seven functions, six passed and one contrast failure.
Travel, artwork at local/World/zoom nine, and the maximum-text chooser pass.
Four later caption-variant audits also failed Contrast despite a visible-region
PIL ratio of 8.27:1. Their
[second](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/harvest-audit-second.log>),
[third](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/harvest-audit-third.log>),
[fourth](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/harvest-audit-fourth.log>)
and [measured](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/harvest-audit-measured.log>)
logs remain retained, together with the later
[green-named failed attempt](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/harvest-audit-green.log>)
and [final-named failed attempt](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/harvest-audit-final.log>).
Names do not change their failed verdicts.

The subsequent [verified log](evidence/receipts/build24-harvest-audit-verified.log)
and [native result](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/harvest-audit-verified.xcresult>)
pass three native cases: city two-choice harvest across cold resume, harvest
accessibility audit, and maximum-text harvest with every choice/Collect reachable.
The source caption is explicit white/bold and remains a separate accessible
`StaticText`; progress captions are explicit white and their combined progress
label is noninteractive. The audit requests Contrast, hit region, sufficient
element description and text clipping. **The raw native Contrast flags were not
cleared.** The handler accepts only Contrast on `naval.resource.source`,
`naval.resource.progress.collected` and `naval.resource.progress.remaining`,
and only when `SettlersUITests/WhiteTextContrast.swift` measures the actual live
element screenshot in sRGB at least 7:1. Ratios are 8.1257:1, 7.9583:1 and
7.9671:1 respectively. Missing measurement fails; every other audit issue fails.
The helper measures white text against the dominant backing color. The narrow
investigated false-positive workflow follows Apple's
[Perform accessibility audits for your app](https://developer.apple.com/videos/play/wwdc2023/10035/)
guidance on issue-specific handlers; Apple has not assessed this app's flags.
This qualified pass is not an unfiltered audit or manual VoiceOver play.

Root inspected original integrated/refined harvest images at local (`43F85FBC`),
World (`0C35E327`), maximum zoom (`D6E58A51`) and maximum text (`DD293FD2`).
It also inspected actual Expert-rival winner image `492962A6`, captured before
waiting for resources, showing the fixed “X traded with Y” notice. The
[visual record](evidence/visual-review.md#build-24-final-source-gallery-local-review-verified) links
those development originals separately from the later 23-image final gallery.
The generated harvest PNG was never edited.

### First complete pre-push gate and test-only corrections

The [completed command receipt](evidence/receipts/build24-first-full-prepush-command.json),
[complete log](evidence/receipts/build24-first-full-prepush-gate.log),
[native summary](evidence/receipts/build24-first-full-prepush-native-summary.json)
and [result](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/full-prepush-gate.xcresult>)
retain the first full gate separately from its replacement. Session `52090`
reports **gate FAILED**, with Git exit 141 and SSH closure during the hook;
`pushPublished` is false. App/UI reports 754 functions: 750 passed, two failed,
two skipped, with 1,509 passing runs. The hosted run has 581 functions/82 suites
and one failure; native has the second failure. Engine passes 391 functions/31
suites, AI passes 308/31, coverage is 96.74%/96.05%, and Release compilation
passes. Every other mandatory gate passes. The optional separate Debug app build
is **SKIP — not requested**, not a Debug-app pass.

The hosted `NavalHistoryIntegrityTests` `.movement` counterexample hardcoded
three remaining steps, making its supposedly valid v3 state exceed the two-step
allowance. Its correction reads `Naval.movementPerTurn(in:)` and first asserts
that the mutation actually changes the saved value; valid-state and cold/
incremental history-rejection assertions remain. The native
`HowToPlayFlowTests/testRulebookOpensInsidePausedMatchAndReturnsToSettings`
used `app.scrollViews.firstMatch`, which selected the background HUD rather than
the visible Settings scroller. It now scopes to `settings.scrollViews.firstMatch`
and retains existence, hittability and the rulebook round-trip assertions.
Commit `67efbadbdb061d9ded77628cf892c72d54e17fb4` changes only these two test files.
No product/package input changes, waived assertion or production repair is part
of that correction.

The [correction summary](evidence/receipts/build24-gate-oracle-corrections-summary.json),
[log](evidence/receipts/build24-gate-oracle-corrections.log) and
[result](</Users/alex/.codex/artifacts/naval-exploration/build24-travel-harvest-trade/gate-oracle-corrections.xcresult>)
pass three functions/eight runs, zero failures/skips: one hosted parameterized
history function with six cases and both How to Play native journeys.
This targeted pass does not replace the complete gate. The replacement full
pre-push session `91604` uses SSH keepalive interval 30/count 120; its completed
verdict and publication are recorded separately below.

The [helper cleanup receipt](evidence/receipts/build24-helper-worktree-cleanup.json)
confirms three implementation helpers recoverably archived with their changes
integrated. Both root Naval and main-integration checkouts remain retained;
needed ignored artifacts are preserved externally. Final delivery cleanup below
shuts down only the reused QA device.

### Final complete pre-push gate and published branch

The [final command receipt](evidence/receipts/build24-final-prepush-command.json),
[complete gate log](evidence/receipts/build24-final-prepush-gate.log) and
[native summary](evidence/receipts/build24-final-prepush-native-summary.json)
report **PASS**, session `91604`, exit 0: all ten mandatory stages pass.
App/UI has 754 functions: 753 passed, zero failed and one skipped; 1,512 passing
runs plus one skipped run. Hosted tests pass 581 functions/82 suites. Engine
passes 391/31 with 96.78% coverage; AI passes 308/31 with 96.05% coverage.
Release compilation passes. The optional separate Debug app build is
**SKIP — not requested**; the native Debug test action built the app/test bundles
separately. It is not a standalone Debug app-build pass.

The branch `codex/naval24-main-integration` is published with remote head
`67efbadbdb061d9ded77628cf892c72d54e17fb4`, matching the test-only local head.
Production remains `9bce5f77a38684bd6e011fac8838c74b38440798`, version 1.0/build 24,
with all 376 frozen production inputs and 112 package files unchanged. The fresh
48-match/six-repeat matrix remains bound to those production/package bytes.
No merge, signed device artifact, upload or Apple availability follows from the
branch push. Ordinary Release runtime, final gallery and signed/Apple delivery
have separate receipts below. The qualified three-ID
native contrast handler remains in place; a green gate does not mean those raw
flags disappeared.

### Final-source gallery and ordinary Release runtime

The [portable final manifest](evidence/screenshots/build24-final-manifest.json)
and [unchanged original root review](evidence/receipts/build24-final-gallery-root-review.json)
bind 23 unmodified originals to production `9bce5f7`, tested head `67efbad`,
version 1.0/build 24 and their configurations. Root directly opened all 22
selected final-gate Debug attachments and the ordinary Release menu, approving
them without a blocking visual defect. Native test IDs and exact epoch capture
times are retained; the Release exact capture time was not recorded, so its
verification/inspection times are kept separately. Three caption crops are
accessibility measurements, not complete gameplay views. The
[final gallery](evidence/visual-review.md#build-24-final-source-gallery-local-review-verified)
links every original and retains the three-ID/live ≥7:1 contrast qualification.
The original expired-news rival `D759D58C` remains excluded; final rival image
`54B41E08` visibly shows the actual winner notice while the human retains Grain.

The [ordinary Release receipt](evidence/receipts/build24-release-runtime.json)
records a fresh 1.0/build 24 install on reused QA without QA arguments. PID
`93934` survives six seconds and no new own crash reports appear. Root approves
the menu. Executable SHA256 is
`33d7746154466774d4359d897e8727710515f8ba11afd595660fca25329c010b`.
This simulator Release runtime is separately attributed from native Debug
fixtures and the separately signed device artifact. Physical-phone installation/
play and manual VoiceOver remain unobserved.

Signed device delivery and Apple availability are recorded separately below;
simulator/native verification does not establish physical-phone installation.

### Signed device delivery, Apple availability and cleanup

The [archive/export receipt](evidence/receipts/build24-archive-command-receipt.json),
[archive log](evidence/receipts/build24-archive.log) and
[export log](evidence/receipts/build24-export.log) pass at exit 0. Archive head
`67efbad` differs from production `9bce5f7` only in the two test corrections;
all 376 tracked production inputs match. Jake's committed signing defaults
remain unchanged. The [review export](evidence/receipts/build24-signed-export.json)
and [actual uploaded payload](evidence/receipts/build24-uploaded-payload-signature.json)
both pass strict/deep signature checks with App Store distribution, Production
CloudKit, beta reports active, no task-allow and no provisioned-device list.

The [upload command receipt](evidence/receipts/build24-upload-command-receipt.json)
and [upload log](evidence/receipts/build24-upload.log) pass, exit 0. Actual preserved
uploaded IPA is 36,268,869 bytes, SHA256
`0ef24d00609c2f2830448ddcdf817d167a0673d060442631c31d1e4e3f87becc`,
MD5 `dfcd6ece91320bbe705a2ce46c26bd0a`. Review export is 36,268,871 bytes,
SHA256 `f899e4d02bc252a70eb6d675ba51741328c0d2fdf501786958769abdaef06770`.
The [payload comparison](evidence/receipts/build24-uploaded-payload-comparison.json)
compares all 14 ZIP entries: only the executable's designated code-signature
bytes differ, with its first 5,855,808 bytes identical. ContentDelivery records
the actual uploaded MD5 three times and delivery ID
`9b3882ef-a85c-46c2-8d1a-2d83f5483aef`, matching Apple's build. The review export
is not substituted for the uploaded payload.

The [Apple/access receipt](evidence/receipts/build24-testflight.json) confirms
Empires 1.0/build 24 VALID, unexpired and internally IN_BETA_TESTING, with Alex
Chandler in Internal and that group having access to all builds, at
`2026-10-07T13:06:46.991Z`. The
[independent final release audit](evidence/receipts/build24-final-independent-release-audit.json)
passes at `13:06:41.579Z`, including a fresh Apple GET at `13:06:40.044Z`,
all 376 production inputs, all 303 matrix artifact hashes, all 23 original
capture hashes, Release runtime and actual uploaded signature/checksum/access.
It independently opens six selected originals. Its SHA256 is
`b68e04bd3cd3840f55f6da1a2fd677969eb78bd82df8b2e14aee2050830b61a8`.
External state is READY_FOR_BETA_SUBMISSION; external build 24 is unreleased.
Physical-phone installation/play, hardware timing, manual VoiceOver and new AI
strength remain unobserved.

The only final-gate skip is
`TradeRedesignFlowTests/testConfirmationFooterAndNewOfferRemainReachableAt375By667`:
it requires 375×667 while this QA run is 402×874. No current compact-device
execution is claimed. Raw native Contrast flags retain the exact three-ID/live
≥7:1 qualification; independent reveal reconstruction remains limited to two
retained fog-off checkpoints.

The [cleanup receipt](evidence/receipts/build24-simulator-cleanup.json) confirms
only reused QA `937692FF` is individually shut down at 13:07:05 UTC, with no
created/deleted devices. Ferrule Dice Review and Switchbard Small Owner Review
2a7e remain booted and untouched. Three implementation helpers are recoverably
archived, with both root checkouts and durable artifacts retained. All 376
production inputs still match after delivery.

[PR #60](https://github.com/jakebeinart1/Settlers/pull/60) remains attached,
awaiting the minimum one actual approval; no approval/merge is recorded. Required
Linux/SwiftLint [CI](evidence/receipts/build24-tested-head-github-ci.json) for
`67efbad` passes in [run 37624311095](https://github.com/jakebeinart1/Settlers/actions/runs/37624311095).
Manual project drift skips, with local drift passing. E29 is complete for the authorized internal TestFlight delivery;
merge/review is a separate remaining repository step.

### Frozen v3 functional and determinism evidence

The fresh [matrix summary](evidence/receipts/build24-v3-summary.json),
[provenance](evidence/receipts/build24-v3-provenance.json) and
[production binding](evidence/receipts/build24-v3-production-source-binding.json)
bind the harness to `9bce5f7` and all 112 frozen package files. Package sources
remain stable before the harness build through the matrix. All 48 declared
three/four-seat, map/option/tier matches pass; six separate-process repeats match
complete result bytes and full move traces with no excluded fields. Detailed
[functional results](evidence/receipts/build24-v3-functional-results.json),
[determinism results](evidence/receipts/build24-v3-determinism-results.json),
[travel review](evidence/receipts/build24-v3-travel-review.json) and
[revisit review](evidence/receipts/build24-v3-raw-revisit-review.json) remain
separate receipts. The [checksum seal](evidence/receipts/build24-v3-checksums.json)
contains 303 artifact checksums, independently matched; full traces and binaries
remain in the external `functionalmatrix` directory rather than copied into docs.

Measured route travel is 1,256 sea hexes across 687 sailing actions, including
569 two-hex voyages. There are zero forced ends, idle sailing cycles, trade cycles
or duplicate proposals. Two raw revisits are productive: a colony is built
between both visits and one also includes capture. Colonization occurs in 47/48
games; total purchases/colonies are 152 ships/276 colonies. Peak process RSS is
22.55 MiB. These results establish functional completion and reproducibility for
the declared harness, not comparative AI strength, human enjoyment or phone timing.

Independent whole-world reveal-union reconstruction covers only the two retained
completion/revisit checkpoints, both with fog off. Every committed move is
checkpoint-validated and decoded by the harness, which is a different check.
Additional fog/reveal-union evidence comes from engine/source tests. No independent
all-48-game fog trace reconstruction is claimed.

| Contract / affected requirements | Required build 24 evidence | Current status |
|---|---|---|
| D45 harvest; F07/F13/F14 | Original settlement one/city two/mixed entitlement and exact-once finite-bank progress after cold resume; pinned heading/Collect and real painted tile/token at all scales. | Integrated city/resume, largest-text, qualified native audit and final regression gate pass. Local/World/maximum and largest-text harvest originals are approved in the final selected gallery; native skip and physical/manual measurement limits remain explicit. |
| D46 language; F02/F03/F08/F13/F14 | Natural Fleet/launch/capture/narration plus exact stable-ID selection in multi-owner stacks and cold resume. | Integrated journeys and final regression gate pass after replacing retired numbered-label oracle with IDs; final Fleet/travel originals approved. |
| D47 travel/privacy; F03/F04/F08/F11/F12/F13/F14 | Complete cost-one/two public range, canonical route, single route-cost commitment and intermediate reveal union; preview/cancel privacy, blocked/exhausted/hidden-mask cases, policy costs. | Integrated native travel and fresh 48-match/six-repeat v3 matrix pass. Independent reveal reconstruction limited to two fog-off retained checkpoints; engine/source fog tests are separate. Final regression gate passes. |
| D47 legacy; F01/F13/F15 | v1/v2 three-hex adjacent-only exact replay, absent version→v1, v3 resume; map 1/schema 6, inland growth, harbors/Return and Expert cards. | New v3 cross-process repeats and final full-gate legacy/source regressions pass; one native skip remains explicit in the final summary. |
| D48 goal; F01/F10/F14 | Actual HUD/Settings/setup target, mode/draft/resume and nonzero human, regular/compact/maximum text. | Targeted goal/setup evidence and final full-gate layout/regressions pass; actual Settings goal/Fleet originals approved in the final gallery. |
| D49 trade; F10/F13/F14/F15 | Real willing/funded policies, uniform sorted pool/policy RNG, ordinary winner actor/provenance, fixed news, failed-write/cold-resume/replay exact-once transfer. | Real human/rival native outcomes pass; integrated rival notice inspected. Decline/expiry/manual human paths retain selected scope; final regression gate passes. |
| Full product/delivery | Required package/app/UI gate, ordinary Release runtime, final source-bound media and signed/Apple access receipts. | First full pre-push failure and three-function/eight-run oracle correction retained. Replacement `91604` passes all ten mandatory stages and publishes `67efbad`; 753/754 functions pass, zero failures, one skip, 1,512 passing runs. Optional separate Debug app build skipped; native test action built Debug. Frozen 376 inputs/112 packages and matrix unchanged; ordinary Release survives six seconds, all 23 final originals approved. Archive/export/upload/signatures and independent final audit pass; Apple VALID/internal IN_BETA_TESTING with Alex's access confirmed. Sole native skip is 375×667-specific; no current compact execution claimed. PR #60 awaits actual approval; tested-head CI passes, unmerged. |

The [harvest manifest](../../../design-references/approved/tiles/harvest-generation-manifest.json)
retains actual built-in imagegen source/prompt and unchanged approved/runtime PNG.
The Debug-only `-qaTradeCompetitionWinner=human|rival` modifier pairs with
`-qaBotTradeAfterPause`, using a bounded starting policy seed with a funded actual
rival and its current Classic/Expert policy; it injects neither accept nor result.
The [original run skill](../../../.claude/skills/run-settlers/SKILL.md#the--qa-launch-arguments)
owns usage and limitations. The optional scope question has no answer: D49 changes
only human Accept on a live bot proposal. Engine RNG/move encoding/schema do not
change for that session operation. Build 23's unchanged-package receipt and build
22's v2 matrix remain historical; E29 uses its own v3 evidence without a strength
claim. [Build 24 delivery](phone-delivery.md#build-24-delivered) is verified; measurement
limits and pending PR approval remain explicit.

## Build 23 follow-up (E28): delivered

E28 tracks Alex's October 7 D42–D44 requests: painted ships, clear construction
availability and repeated-touch trade safety. Production is frozen at
`1dfae7cb8e46ca4b343c0415fef18e71cd3a6ed4`, with `project.yml` naming 1.0/build 23.
Build 22's completed E27 gate and signed delivery stay attributed to `1cf1c0f`.
The [production-input receipt](evidence/receipts/build23-final-production-inputs.json)
binds all 371 tracked app/package/configuration/asset inputs to the freeze.
No engine/AI package, rules version, save schema, move effect or policy weight
change is part of this follow-up. Apple build
`cfcb926b-7b11-4178-9d19-8df7a9e5e597` is VALID, unexpired and internally
IN_BETA_TESTING, with Alex's membership in Internal and all-build access
verified at 08:16:30 UTC (4:16:30 a.m. EDT), October 7, in the
[processing/access receipt](evidence/receipts/build23-testflight.json). The
[independent readback](evidence/receipts/build23-testflight-independent.json)
confirms the same build/state/access at 08:18:25 UTC; the
[final release audit](evidence/receipts/build23-final-release-audit.json) passes
at 08:21:23 UTC with no blocking defects.

The [111-file package comparison](evidence/receipts/build23-engine-ai-source-equivalence.json)
matches every engine/AI source input to build 22's `1cf1c0f`. E28 therefore reuses
E27's [48-match functional matrix and six fresh-process repeats](#build-22-follow-up-e27-delivered)
as an unchanged-package baseline: 48 complete matches, 158 ships, 1,086 sailing
steps, 274 colonies and exact repeat results/traces. No games were rerun for
build 23 and no new strength result is claimed.

The eight approved transparent ship PNGs and runtime catalog copies have matching
bytes, with prompts, SHA256 and root inspection recorded in the
[generation manifest](../../../design-references/approved/ships/generation-manifest.json).
Runtime tests load all eight actual bundle images, check transparent/visible
pixels and distinct styles. Native purchases exercise every civilization through
Fleet, local focus and World. Real capture/stack journeys retain current-controller
identity and explicit choice. Shared `0.92 × hexSize` artwork sizing and capped
2.5-point selection decoration do not change hit geometry or production camera.

Build rows derive enabling from the real legal move set for the displayed actor's
main turn. Native scarcity taps verify no proposal/payment/discovery after the
modal is dismissed; ready purchase previews, cancels, commits and cold-resumes
exact payment. Classic construction and largest-text Conquest keep their choices
and pinned Close. The popup uses one measured action tree, with current intrinsic
heights replacing earlier measurements rather than retaining a largest-seen size.

The [legal pre-fix baseline](evidence/receipts/build23-trade-taps-legal-before-summary.json)
passes four hosted fixture cases, then fails the native stale-Skip guard:
“A stale Skip touch answered or opened the real offer.” Earlier
[SIGTRAP attempt](/Users/alex/.codex/artifacts/naval-exploration/build23-sprites-build-trade-safety/trade-taps-before-fix.log)
and [macro compilation failure](/Users/alex/.codex/artifacts/naval-exploration/build23-sprites-build-trade-safety/trade-taps-valid-before-fix.log)
are invalid bug-reproduction attempts, preserved separately. Skip/Retry now uses
the leading 92×52-point rectangle, disjoint from the trailing answer controls.
One stable answer tree stays outside the summary scroll. Review and Back retain
the timer hold; a deliberate summary tap resumes it. Complete offer content plus
proposal occurrence bind timer cancellation and summary measurement.

| Targeted result | Functions / runs | Verdict and scope |
|---|---|---|
| [Legal baseline](/Users/alex/.codex/artifacts/naval-exploration/build23-sprites-build-trade-safety/trade-taps-legal-before-fix.xcresult) | 2 / 5 | Failed: four hosted parameter cases pass; one native stale-touch failure, zero skips. |
| [Fourth combined command](evidence/receipts/build23-ui-art-fourth-green-summary.json)/[log](evidence/receipts/build23-ui-art-fourth-green.log) | 16 / 23 | Overall failed: 14 functions/21 runs pass, two new artwork assertions fail, zero skips. All four Build, five trade-safety and two existing capture/stack UI functions pass. The filename is not its verdict. |
| [Corrected all-eight artwork](evidence/receipts/build23-all-eight-artwork-green-summary.json)/[log](evidence/receipts/build23-all-eight-artwork-green.log) | 5 / 12 | Passed, zero failures/skips: eight UIImage parameter cases within three hosted functions, plus two native artwork journeys. Only the two new test oracles were corrected after the prior command. |
| [Visible maximum zoom](evidence/receipts/build23-artwork-visible-maximum-summary.json)/[log](evidence/receipts/build23-artwork-visible-maximum.log) | 1 / 1 | Passed, zero failures/skips; test 18.543 seconds. Real drags and full ship-frame containment replace the earlier blank/offscreen visual proof. |
| [Compact focused run](evidence/receipts/build23-compact-focused-summary.json)/[log](evidence/receipts/build23-compact-focused.log) | 8 / 8 | Seven pass, one scarcity scrolling-test assertion fails, zero skips. Ready construction, maximum text, trade safety and the 375×667 confirmation footer pass. |
| [Corrected compact scarcity](evidence/receipts/build23-compact-scarcity-green-summary.json)/[log](evidence/receipts/build23-compact-scarcity-green.log) | 1 / 1 | Passed, zero failures/skips, 18.253 seconds after correcting only this scrolling oracle. |
| [Mixed-controller stack](evidence/receipts/build23-mixed-stack-green-summary.json)/[log](evidence/receipts/build23-mixed-stack-green.log) | 1 / 1 | Passed, zero failures/skips, 8.636 seconds on the compact phone. Real purchases and sailing place two owners in one sea hex; count and separate owner choices remain explicit. |

The [independently inspected zoom-nine capture](evidence/screenshots/build23-visible-ship-nine-intermediate.png)
shows the painted Britannia ship fully inside the board, adjacent 2:1 harbor,
coast and navigation. These Debug captures precede the final source/version
freeze; the [build 23 visual record](evidence/visual-review.md#build-23-final-source-gallery-local-review-verified)
keeps them separate from final-source release media. Root also inspected compact
Ready/scarce build paint; the [mixed-stack original manifest](/Users/alex/.codex/artifacts/naval-exploration/build23-sprites-build-trade-safety/mixed-stack-attachments/manifest.json)
retains local/World/owner-choice attachments. The temporary task-owned compact
device alone was deleted after evidence preservation, as recorded by the
[cleanup receipt](evidence/receipts/build23-compact-cleanup.json); shared devices
and other projects were protected.

The frozen-source [complete gate log](evidence/receipts/build23-full-gate.log)
and [exit receipt](evidence/receipts/build23-full-gate-exit.json) pass all eleven
stages, exit 0, with serial QA `937692FF` and two build jobs. Engine passes
371 functions/28 suites, AI 303/30; coverage 96.67%/96.01% exceeds each 95% floor.
Hosted app tests pass 565 functions/80 suites. The
[audited app/UI summary](evidence/receipts/build23-full-gate-native-summary.json)
records 732 functions: 731 passed, zero failed, one skipped; 1,477 runs:
1,476 passed and one skipped.
The sole skip requires a 375×667 footer viewport, while the QA iPhone 17 Pro
measures 402×874. That exact footer test independently passes the compact run.
Release and Debug compile. Earlier targeted result counts are not added to this
full-suite total.

The [final-source manifest](evidence/screenshots/build23-final-manifest.json)
records seventeen unmodified, root-inspected images at `1dfae7c`, version 1.0/23:
Ready/scarce Build, largest-text Conquest, leading Skip, unanswered offer, contained
zoom-nine ship/harbor, mixed-controller World/chooser, all eight local fleet styles
and the ordinary Release menu. Sixteen are final-gate Debug attachments; the
Release menu has separate attribution. The
[final gallery](evidence/visual-review.md#build-23-final-source-gallery-local-review-verified)
links each selected image. The World stack clearly shows two silhouettes/count
and the chooser identifies both owners. Other exports are retained but are not
included in this seventeen-image inspection claim.

The [ordinary Release receipt](evidence/receipts/build23-release-runtime.json)
records fresh 1.0/23 installation, no QA arguments, PID 54344 surviving six
seconds, no new own crash reports and root-inspected menu. Simulator executable
SHA256 is `2dc38e9d20c221a104cd6400e0eaceec03af2a9bdfb579e9a746c332b129250d`.
The [archive/export receipt](evidence/receipts/build23-archive-command-receipt.json)
records both commands exiting zero at production/archive source `1dfae7c`;
[signed export](evidence/receipts/build23-signed-export.json) passes strict/deep
signature and Production CloudKit checks with the retained certificate/profile.
The [upload receipt](evidence/receipts/build23-upload-command-receipt.json) and
[log](evidence/receipts/build23-upload.log) record exit zero and preservation of
the actual staged payload. Its [signature receipt](evidence/receipts/build23-uploaded-payload-signature.json)
passes the same profile/certificate/Production checks. The
[independent payload comparison](evidence/receipts/build23-uploaded-payload-comparison.json)
finds fourteen ZIP members matching except the executable's code signature;
all 5,771,184 executable-prefix bytes are identical. Uploaded IPA
`2707f35…8aa1`, 33,718,518 bytes, is distinct from review `fce46b79…50b0`.
Accepted ContentDelivery MD5 `55379F183A2E383BE69B7AF12805C56E` is independently
confirmed at three occurrences; its delivery ID matches Apple's exact build ID.
The [delivery record](phone-delivery.md#build-23-delivered) retains complete
artifact attribution and verified internal tester access.

The [release simulator cleanup](evidence/receipts/build23-simulator-cleanup.json)
records reused QA `937692FF` shut down, zero release-created/deleted devices and
other projects untouched. The compact device's earlier individual deletion
remains in its own receipt. Both helpers are
[recoverably archived](evidence/receipts/build23-helper-worktree-cleanup.json),
with root Naval and durable evidence retained. All 371 production inputs still
match after delivery. The final independent audit also confirms frozen inputs,
actual uploaded signatures/checksum/Apple ID, all seventeen media hashes and
unchanged-package functional evidence. External build 23 is unreleased.
Physical-phone installation/play, hardware timing and new AI strength remain
unobserved.

## Build 22 follow-up (E27): delivered

E27 tracks Alex's D40 harbor-visibility and D41 navigation corrections. Current
source `1cf1c0fde5904aa1cbeae9320cae55afb9bdfcd0` retains the inland placement and
Expert-card compatibility already delivered in build 21. The current-source
complete gate, ordinary Release launch and final-source gallery pass.
Archive/export/upload and the independent final release audit pass. Apple build
`45c00f05-28b4-42de-93f6-016e4ed8e67a` is VALID, unexpired and internally
IN_BETA_TESTING; Alex's membership in Internal and access to all builds are
confirmed in the [delivery receipt](evidence/receipts/build22-testflight.json)
and [independent read-back](evidence/receipts/build22-testflight-independent.json).

The engine charts a port when revealed land borders its shared edge. The four
home ports are two generic 3:1 ports plus grain/wool 2:1 ports; five overseas
ports retain two generic plus lumber/brick/ore ports. Hidden island ports remain
concealed, surrounding fog and number masking remain unchanged, and visibility
alone grants no ownership or exchange rate. The renderer paints public harbor
badges/docks above decorative mist. No map, supply, reveal, schema, RNG or
recorded-move change is required.

Older queued replies can contain the former, narrower public port list. Resume
accepts only a complete observation match against that exact former projection
of authoritative state. It refreshes the chart without evaluating the policy
again or changing the stored reply, counters or RNG. Wrong public state, counts,
legal masks, actor, move, evaluation index and partial port lists remain rejected.

| Check | Verified result and attribution |
|---|---|
| Engine | The [red counterexamples](evidence/receipts/build22-engine-before-fix.log) catch missing harbors, projected trade rates and legacy replies. The [complete CatanEngine run](evidence/receipts/build22-engine-focused-full.log) passes 371 functions/28 suites with warnings treated as errors. Package source `56bf5f0` matches all 111 recorded package files at current app source `1cf1c0f`. |
| Initial navigation correction | The [baseline failure](evidence/receipts/build22-navigation-before-fix.log) shows absent Return in real three-/four-seat setup. The [focused summary](evidence/receipts/build22-navigation-focused-summary.json) and [log](evidence/receipts/build22-navigation-focused.log) pass 20 functions/35 runs, zero failures/skips, after the initial correction preceding the final fitted-pose fix. They cover real setup, CPU pacing, human turn, cold resume, pose measurements and HUD clearance. |
| Harbors and related play | The [summary](evidence/receipts/build22-harbors-related-play-summary.json) and [log](evidence/receipts/build22-harbors-related-play.log) pass 31 functions/36 runs, zero failures/skips, on the earlier harbor/navigation correction. Selection includes actual owned-port bank exchanges and the Naval purchase, sailing, capture, harvest, resume and archive journeys. These two focused commands overlap; their counts are not a complete-suite total. |
| Final fitted-pose correction | A later [native red regression](evidence/receipts/build22-fitted-return-before-fix.log) returned zoom 2.6 instead of the preceding fitted zoom 1.0. The correction committed as `1cf1c0f` stores the actual preceding pose. Its [passing run](evidence/receipts/build22-fitted-return-focused.log) has one native function/run, zero failures, 15.260 seconds. Earlier focused passes did not cover this counterexample. |
| Current-source complete gate | The [full log](evidence/receipts/build22-full-gate.log) and [summary](evidence/receipts/build22-full-gate-summary.json) pass all eleven stages at `1cf1c0f`, exit 0, including Release and Debug. Engine 371 functions/28 suites, AI 303/30; coverage 96.72%/96.01%. The [audited native summary](evidence/receipts/build22-full-gate-native-summary.json) has 704 functions: 703 passed, zero failed, one skipped; 1,434 runs: 1,433 passed and one skipped. |
| Ordinary Release | The [runtime receipt](evidence/receipts/build22-release-runtime.json) records a fresh version 1.0/build 22 installation, no QA launch arguments, PID 46232 surviving four seconds and no new own crash reports. Root inspected the [Release main menu](evidence/screenshots/build22-release-menu.png). Its simulator executable is separately attributed from Debug captures and the signed device artifact. |
| Final media | The [final manifest](evidence/screenshots/build22-final-manifest.json) binds five unmodified, root-inspected Debug harbor/Return/generic-trade/resource-trade/cold-resume images to `1cf1c0f`, plus the ordinary Release menu. The [final gallery](evidence/visual-review.md#build-22-final-source-gallery-local-review-verified) separates them from the preserved [intermediate manifest](evidence/screenshots/build22-intermediate-manifest.json) and [images](evidence/visual-review.md#build-22-intermediate-harbor-and-return-gallery). |
| Signed upload and access | [Archive/export](evidence/receipts/build22-archive-command-receipt.json) and [upload](evidence/receipts/build22-upload-command-receipt.json) exit 0. The [actual uploaded payload](evidence/receipts/build22-uploaded-payload-signature.json) and [comparison](evidence/receipts/build22-uploaded-payload-comparison.json) bind the accepted IPA and ContentDelivery checksum separately from the review export. Apple processing/access and [independent final audit](evidence/receipts/build22-final-release-audit.json) pass; the exact artifacts are recorded in [phone delivery](phone-delivery.md#build-22-delivered). |

The sole full-run skip is
`TradeRedesignFlowTests/testConfirmationFooterAndNewOfferRemainReachableAt375By667()`,
which requires 375×667 points; this run used 402×874. The natural-seven
cold-resume journey passed. All four `NativeHarborFlowTests` and five
`NativeNavigationFlowTests` passed in the complete run, including the final
fitted-pose guard at 13.873 seconds. The earlier focused commands and their
failures remain preserved; they are no longer the final app verdict.

The [final package binding](evidence/receipts/build22-final-package-source-binding.json)
matches all 111 package source files to `1cf1c0f`.
[Production input checks](evidence/receipts/build22-final-production-inputs.json)
match all 349 tracked app/package/configuration inputs to that source. Documentation
and delivery artifacts retain their own identities; a signed device executable
is not presumed identical to the simulator executable.

World is an inspection excursion with an explicit Return, rather than an
implicit Home focus. Home retains its separate behavior. Return restores both
zoom and pan without changing an uncommitted proposal, resources or discoveries.
The saved camera pose does not cache fitted geometry or container size.

The [declared functional plan](evidence/receipts/build22-ai-functional-plan.json)
reuses all 48 build 21 cases: three map families, fog/resource-choice on/off,
three/four players, and all-Traditional/all-Expert rosters. The
[summary](evidence/receipts/build22-ai-summary.json) reports 48 valid winners,
158 purchased ships, 1,086 sailing steps and 274 colonies. All 48 matches buy
ships and sail; 47 establish colonies. There are no forced endings, idle sailing
cycles, trade cycles or duplicate proposals. The
[harbor audit](evidence/receipts/build22-ai-harbor-voyage-review.json) independently
finds 149 seats starting without a coastal launch harbor, 121 later opening one,
and 97 buying ships. These coastal launch sites are distinct from trading ports.
The [raw revisit audit](evidence/receipts/build22-ai-raw-revisit-review.json)
retains six revisits in five games, each with intervening new discoveries or
settlement/fleet opportunity changes.

All six [fresh-process repeats](evidence/receipts/build22-ai-determinism-results.json)
match stdout bytes and every JSON field with no exclusions; complete move traces
also match byte for byte. All 48 trajectories and non-provenance result fields
match build 21. Only the declared build/arm identity changes in that historical
comparison. The [Release CLI provenance](evidence/receipts/build22-ai-provenance.json)
pins the separately rebuilt binary, two changed production files and stable
111-file package source set; the [integration comparison](evidence/receipts/build22-ai-integration-source-match.json)
was captured at `1e9c338`, and source inspection confirms the same package hashes
at `1cf1c0f`. The [327-file durable packet](/Users/alex/.codex/artifacts/naval-ai/voyages-build22/checksums.json)
preserves every raw run and repeat. This is functional regression evidence,
without tuning, new strength conclusions or physical-phone performance claims.

Local gate/runtime/gallery and [internal TestFlight delivery](phone-delivery.md#build-22-delivered)
are verified, with no unresolved release blocker in the
[independent audit](evidence/receipts/build22-final-release-audit.json). External
build 22 is not released. Physical-phone installation/play, hardware timing and
human enjoyment remain unobserved. The [simulator cleanup receipt](evidence/receipts/build22-simulator-cleanup.json)
records reused QA shutdown, zero created/cloned/deleted task devices and all
other devices untouched. Both helpers are [recoverably archived](evidence/receipts/build22-helper-worktree-cleanup.json);
root and durable evidence remain retained. Build 21's completed delivery below
keeps its original artifact and evidence.

## Build 21 follow-up (E26): delivered

E26 tracks Alex's D38 inland-settlement correction and D39 simulator lifecycle
request at current release target `60394e6`. Inland rules landed at `8a394132`;
`ad9c0bf` subsequently isolates completion-learning tests, and `60394e6` adds only
the TestFlight skill's lifecycle pointer. Both opening settlements allow
ordinary legal home-island corners, including inland sites. Paid land expansion
still needs owned roads; founding without a road still needs an owned ship
touching that exact known coastal corner. The founded island may expand inland
after its ship sails away. Distance, supply, surveyed-home setup, saved v1/v2
vision and previously recorded move effects remain intact.

The [before-fix counterexample](evidence/receipts/build21-inland-before-fix.log)
and [passing engine regressions](evidence/receipts/build21-inland-engine.log)
cover both opening rounds, all families, fog on/off, three/four players, resumed
v1/v2 setup, owned roads, unreachable/rival ships and colony expansion after real
sailing. The earlier full-gate attempt was interrupted during hosted tests.
Its `2026.10.05_21-33-11--0400.xcresult` contains only Data/Staging and has no
Info.plist; `xcresulttool` rejects it with exit 64. The partial session records
282 passed completions and no failure, but it is not a complete test verdict.
The fresh serial [full-gate log](evidence/receipts/build21-full-gate.log),
[summary](evidence/receipts/build21-full-gate-summary.json) and
[valid result](/Users/alex/.codex/artifacts/naval-exploration/build21-final/full-gate.xcresult)
at `60394e6` pass all eleven stages, exit 0. Engine 365 functions/26 suites and
AI 303/30 pass; coverage is 96.63%/96.01%. App/UI 694 functions: 692 passed,
zero failed, two skipped; 1,419 passing runs. The app stage takes 2,782 seconds.
The existing skips are the natural-seven journey whose sampled rolls produce no
human obligation and the trade-footer test requiring a 375×667-point destination
instead of this 402×874 device. No new skip or raised timeout was added.

Audit found that restoring a completed checkpoint could enqueue real ghost
extraction before a test replaced its trainer. `ad9c0bf` injects the factory
before restoration, isolates fixture stores and awaits completion before their
cleanup. The production default remains the real trainer; the existing real
extraction/fitting tests remain intact. The durable [focused log](/Users/alex/.codex/artifacts/naval-exploration/build21-final/ghost-isolation-confirmed.log),
[summary](/Users/alex/.codex/artifacts/naval-exploration/build21-final/ghost-isolation-summary.json)
and [result bundle](/Users/alex/.codex/artifacts/naval-exploration/build21-final/ghost-isolation-confirmed.xcresult)
pass 49 functions in seven suites, 56 passing runs, zero failures/skips
(147.933 seconds). They include the new completion/cold-resume injection guard,
completion-hook, local-sync, checkpoint and full-match coverage. Real candidate
extraction remains in the unchanged GhostTrainerTests, which the focused run
does not select. The subsequent complete gate passes all six GhostTrainerTests
and the new isolation guard, preserving real extraction/fitting coverage.

The [focused native summary](evidence/receipts/build21-inland-native-summary.json)
and [original log](evidence/receipts/build21-inland-native.log) pass three actual
journeys with zero failures/skips: inland tap/preview/Clear/Confirm/adjacent road
choices/cold resume, ship purchase/sailing/resume, and actual-corner discovery.
The three unmodified instrumented Debug captures at `8a394132`, opened by root
and the documentation reviewer, remain historical in the
[gallery](evidence/visual-review.md#build-21-inland-settlement-gallery-delivered).
Separate final-source captures exported from the complete passing gate are
recorded by [their source/hash manifest](evidence/screenshots/build21-final-manifest.json).
Root inspected the final options and settlement screens; the independent auditor
opened the final cold-resume image. All three original hashes and byte counts
match the manifest.

The [functional receipt](evidence/receipts/build21-naval-functional-compact-receipt.json)
records 48/48 completed ordinary unfiltered games across both tiers, three/four
players, all families and all four fog/resource-choice combinations: 28,743
committed actions at `8a394132`. An independent read-only check at `60394e6`
matches all 111 recorded package-source hashes and the retained Release CLI
binary digest in the [provenance receipt](evidence/receipts/build21-naval-provenance.json);
the later commits change no engine or AI package source.
All six [separate-process repeats](evidence/receipts/build21-naval-determinism-results.json)
are byte-identical across every result field, with no excluded fields. The
[harbor/voyage review](evidence/receipts/build21-naval-harbor-voyage-review.json)
finds ships and sailing in all 48 games and colonies in 47; the remaining game
wins through other scoring routes. These are functional checks, not a new
strength claim. The exact build 20 point-completing-card feature and refined
revision/archive tests are retained, with Naval routing and old saved city/legacy
policies preserved; [compatibility scope](release-compatibility.md#build-21-compatibility-with-the-retained-expert-card-revision)
and [focused AI tests](evidence/receipts/build21-combined-ai-focused.log) retain
the boundary.

The [retirement receipt](evidence/receipts/build21-simulator-retirement.json)
records two retired task-owned devices deleted after verified app-data backups,
leaving 13 host devices. Current QA and review devices are reused; this task
created no new device and stopped no other project's simulator. The original
run/play/verify/ship skills now point to the maintained inventory, ownership,
reuse and individual cleanup policy in both the worktree and primary checkout;
the gate defaults to one worker without parallel clones. About 5 GB of disposable
simulator data was reclaimed. The [final inventory](/Users/alex/.codex/artifacts/naval-exploration/build21-final/simulators-after-verification.json)
contains 13 devices and zero booted: reused QA `937692FF` is shut down and existing
review `FA10360F` remains shut down. Other projects' devices were not stopped or
deleted.

The ordinary Release 21 artifact was freshly installed on the reused QA device
and launched without QA arguments. PID 59749 survived; root opened its main menu.
The [runtime receipt](evidence/receipts/build21-release-runtime.json) records
executable SHA256 `b3c0f45c26ed40364ccb17c2286c47fed11289248e7e9bab78b3ac88e52ba324`,
independently matched to the compiled Release simulator executable. Debug and
Release builds pass in the gate; runtime evidence remains simulator-only.

**Implementation, simulator verification and internal TestFlight delivery: complete.**
The historical [ordinary archive](evidence/receipts/build21-archive-signing-failed.log)
and [explicit-login-keychain retry](evidence/receipts/build21-archive-keychain-failed.log)
exit 65 at CodeSign with `errSecInternalComponent`. The login keychain diagnostic
reports an incorrect user name or passphrase, but a subsequent read-only
Security.framework check proves unlocked/readable/writable status (bits 7).
The generic unlock request was therefore unsupported. Both CLI and Keychain
Access show the existing identity and associated key; its UI access is already
unrestricted. Current securityd errors include `CSSMERR_CSP_INVALID_DATA`.
The subsequent native Xcode Archive independently reproduces the same signing
error after successful compilation. Its [report](evidence/receipts/build21-native-xcode-signing-failed.log)
and [configuration/source receipt](evidence/receipts/build21-native-xcode-signing-failed.json)
bind manual signing, the existing identity/profile and unchanged production
inputs. No new simulator or certificate was created. This ruled out a CLI-only
failure. Alex then completed the targeted local lock/unlock authentication
refresh; the same existing-identity signing probe succeeded, followed by the
original-project [archive](evidence/receipts/build21-archive.log),
[export](evidence/receipts/build21-export.log) and
[upload](evidence/receipts/build21-upload.log), each exit 0. The observed recovery
does not establish why the earlier unlocked keychain failed; no trust/ACL change,
keychain reset or certificate recreation was used.

The [signed-export receipt](evidence/receipts/build21-signed-export.json) binds
production source `60394e6` and docs-only archive head `d56581d` to version 1.0/21,
existing certificate/profile, strict signature and Production CloudKit. The
[actual uploaded-payload receipt](evidence/receipts/build21-uploaded-payload.json)
records IPA SHA256 `1f1d7319d182daf74783f1412cce3e2ad8d89517706ccaac8cd13f1853c83202`
(24,887,137 bytes), distinct from review export
`a1a1b182cb3db195146ee5e1ffe5678b9e59531d6c44f13fc7f837743d5ef25c`.
All fourteen ZIP members match except the executable's signature; its first
5,687,504 bytes are identical. The uploaded staging bundle passes strict/deep
signature verification, and its MD5 matches ContentDelivery's accepted payload.

The [fresh Apple/access receipt](evidence/receipts/build21-testflight.json) and
independent read-back confirm build `23440fef-103a-4c7b-8896-a0164c7bab74` VALID,
unexpired and internally IN_BETA_TESTING. Alex Chandler belongs to Internal with
`hasAccessToAllBuilds=true`. External status is READY_FOR_BETA_SUBMISSION; external
build 21 is not released. Hardware installation and unscripted phone play remain
unverified.

## Build 19 follow-up (E25)

E25 closes the subsequent compact configuration, actual-corner surveying and
richer fog/water request (D35–D37). Final source `5c01f39` passes every gate
stage, exit 0: 686 of 688 app/UI functions pass, 0 fail and 2 explicit conditional/size
skips; 1,379 passing runs. Five regular settings cases, five SE cases with one
regular-height-only skip, native 19→25 corner confirmation/cold resume and fixed
World/Home/maximum 9× camera proof are retained. All 48 fresh v2 functional AI games and
six exact separate-process repeats pass, without a strength claim.
Apple 1.0/build 19 is VALID and IN_BETA_TESTING with Alex's access confirmed.
[Delivery record](phone-delivery.md#build-19-refinement-delivered) and
[current gallery](evidence/visual-review.md#build-19-refinement-gallery) own the
signed artifact, current media, retained failed iterations and evidence limits.

## Build 18 follow-up (E24)

E24 closes Alex's subsequent C13/D34 layout/help and phone-delivery request.
Selectors share the wider aligned axis, one info control names each option,
and reviewed regular/SE captures are preserved. Current source `8953413` passes
the complete serial app/UI rerun; successful original gate stages and the
retained failed parallel stage are distinguished in [release compatibility](release-compatibility.md).
Apple version 1.0/build 18 is VALID and IN_BETA_TESTING with Alex's access
confirmed. The [delivery record](phone-delivery.md) owns signed artifact, current
runtime/screenshots and processing/access evidence. Physical installation is
not claimed. E20–E23 below remain their original local-simulator receipts.

## Evidence and claims

| Claim | Evidence that supports it |
|---|---|
| The source compiles | Correct tool exit status for the relevant build/configuration. |
| A rule is implemented correctly | Meaningful transition and counterexample tests through authoritative rules. |
| A user journey works | Native UI interaction through the real session, including completion where required. |
| It looks good | Opened, inspected real-artifact screenshots at relevant sizes/states; animations also need recordings. |
| Resume/replay is exact | Matching uninterrupted/resumed histories and separate-process replay/fingerprint evidence. |
| A bot improved | Preregistered naval-capable anchors, held-out paired configurations, every-chair rotation, table-size-aware power, intervals and decisive rate. |
| Human difficulty and enjoyment are appropriate | Observed human play and feedback; self-play alone does not answer this. |
| Physical-phone latency is acceptable | Physical-device measurement; simulator timing alone does not answer this. |

Store each receipt with source commit, build/configuration, installed artifact
identity, simulator/runtime, seed/map/rules version, settings, occupied/human seats,
policy/revision, phase/action history, commands, exit statuses and evidence paths.
Keep directly seeded layout fixtures separate from states reached through play.

Use the existing [run](../../../.claude/skills/run-settlers/SKILL.md),
[play](../../../.claude/skills/play-settlers/SKILL.md),
[verify](../../../.claude/skills/verify-settlers/SKILL.md),
[bot strength](../../../.claude/skills/bot-strength/SKILL.md) and
[simulation](../../../.claude/skills/sim-harness/SKILL.md) workflows, checking current
source when historical prose differs. Their original scripts/definitions are the
authority; do not copy commands into this document as a competing workflow.

## Original E20–E23 local closure

All fifteen requirements are closed for the agreed local-simulator delivery.

| Requirement | Disposition | Final evidence |
|---|---|---|
| F01 | Closed | E20/E21/E22 |
| F02 | Closed | E20/E21/E22 |
| F03 | Closed | E20/E21/E22 |
| F04 | Closed | E20/E21/E22 |
| F05 | Closed | E20/E21/E22 |
| F06 | Closed | E20/E21/E22 |
| F07 | Closed | E20/E21/E22 |
| F08 | Closed | E20/E21/E22 |
| F09 | Closed | E06/E15/E20/E22 |
| F10 | Closed | E20/E21/E22 |
| F11 | Closed | E07/E15/E20/E21/E22 |
| F12 | Closed | E07/E15/E20/E22 |
| F13 | Closed | E20/E21/E22 |
| F14 | Closed | E19/E20/E21/E22 |
| F15 | Closed | E20/E21/E22 |

| Final field | Recorded result |
|---|---|
| Production source | `971a615ba701e2eca9e22ae538cadbfd8d243d8a` for E20/E22; E23 changes setup presentation, and build 18 integrates the current phone release. See [release compatibility](release-compatibility.md). |
| Gated/installed artifact | Debug, version 1.0/build 16, SHA256 `2ab9e0852e6e5db7ef13f9b3eaeba8bf7291bc315e6abeadf5e1ea2dc1c458f8`; exact-byte post-gate native proof and fresh installation E21/E22. |
| Full gate | PASS exit 0, all eleven stages; engine 332/19, AI 281/27, coverage 96.59%/95.63%; app/UI 552 functions/1,211 runs, zero failed/skipped E20. |
| Policies | Complete Traditional and Expert/Naval V1, frozen confirmation E15, separately attributed 48-trajectory integration bridge E07. |
| Native review | Earlier E23 update of Empires Voyages Review, iPhone 17 Pro/iOS 26.5; historical PID 86428 on main menu without QA setup/seed/position flags, checkpoint preserved and no new crashes E23. Earlier prepared match remains resumable. |
| Complete match/history | Real policy/session completion and painted replay pass E20; distinct winner/replay journeys inspected E22. |
| Interface/AX/motion | Two-size maximum-text Nearby/Fleet paint E19, unfiltered audits E20, exact native journeys E21 and final inspected images/sequential motion frames E22. |
| Durable bundle | Portable selected logs/summaries, AI/map studies, screenshot/motion/source-bound manifests; original valid xcresults and movies preserved externally. |

The review position supplies conserved extra cards after completed setup and has
no pre-purchased human ship. Begin with **Build → Ship**, then confirm a coastal
launch and use Fleet to sail. Start ordinary play through **menu → Quit → Main Menu → New Game → Rules → Naval**. The isolated worktree stays available for human review and refinement.

Human enjoyment, unscripted difficulty, other personality mixes, manual VoiceOver
play and physical-phone timing have not been measured. TestFlight distribution was requested on October 5; its separate
[delivery record](phone-delivery.md) retains build 18 verification. These explicit limits do not erase the completed local acceptance or
extend its evidence to those claims. Earlier failed receipts remain in the record.
