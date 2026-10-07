# Voyages product and implementation audit

## Audit checkpoint

October 5, 2026, isolated branch `codex/naval-exploration`. This record separates
selected design, implemented corrections, observed verification and final delivery.
The mode is **ready for local human review**. Frozen `971a615` passes all eleven
gate stages, exit 0 (E20); every one of the twenty-three audit findings has a
correction verified on this final source. Exact-gated native gameplay passes E21,
and fresh installation, surviving process, independently inspected final images
and sequential motion frames close E22. F01–F15 are closed in the
[acceptance register](acceptance.md).

The first `02eb013` gate failed on app/UI tests; its receipt remains preserved.
Terminal/session/confirmation/contrast corrections then passed the core `a8bd01c`
gate. Later A21/A22 map counterexamples include a deliberate renderer-only fog
negative control. A23's clipped maximum-text paint was found despite functional
success and corrected with stronger full-row checks and inspected regular/SE
Nearby/Fleet screens. Historical failures are retained rather than recast as passes.

The audit used the human [charter](README.md#confirmed-commitments), delegated
[design contract](design-contract.md), [decision record](decisions.md), actual
engine/app/policy source, counterexample tests, native gameplay logs, reviewed
simulator screenshots and [generation evidence](evidence/map-gallery.md).
Source inspection explains a correction; a test declaration alone is not a run.
Receipts from earlier trees do not automatically verify later changes.

## Fundamentals and design critique

| Question | Selected design and its basis | Practical limit or further evidence |
|---|---|---|
| What makes this more than linked maritime roads? | Independently positioned hulls have three steps, permanent public discovery, reusable landing access and global persistent capture. Exact ship price remains two wood/one sheep/two iron through lumber/wool/ore. | Six lifetime purchases limit spending without forbidding captured control. Capture creates luck and public-discovery free riding; enjoyment/fairness needs human play as well as self-play. |
| Why can colonies be built without cargo? | The normal personal hand funds all construction. A ship grants coastal access; the first owned settlement establishes the land network for roads. | Preserves the existing economy and keeps decisions focused on position/investment. Costs still need full-match pace evidence. |
| How does exploration repay an expensive ship? | Reusable access, productive overseas coastlines, two maximum permanent first-component colony points and optional low-frequency flexible production. | Buying ships is an option, not a condition for victory. A land-only strategy winning does not establish a defect; conversely completed naval games alone do not establish balanced opportunity cost. |
| Why these maps and distances? | A fixed home, two sea rings and outer island belt prevent early overseas sight and hidden-boundary camera leakage. Three families vary coast shape, group size and routes within a known envelope. | Controlled sectors remain recognizable. Coordinate diversity includes rotations/reflections. Real routes and site production, not a colorful gallery alone, justify travel distances. |
| Why permanent public fog clearing? | Shared discovery is Alex's rule. No tracking of private sight or returning fog is introduced. Ship/building sight remains radius two. | Policies must avoid authoritative hidden metadata even though the generated world already exists. Initial home survey is a delegated opening decision rather than a human-specified start rule. |
| Why is flexible production not just another resource hex? | Two tokens at 4/10, one choice per settlement/two per city, finite bank and one allocation of each yield to recipe deficits. | Raw production pips do not value flexibility. Option-paired worlds support a fair comparison; match-level economics and human feedback are still separate. |
| Why separate durable phases from previews and motion? | Committed state is persisted before publication. Harvest/capture obligations survive cold launch; optional previews reopen unselected or disappear. Cosmetic motion cannot create a gameplay transition. | Native interruption/retry and historical painted frames need independent checks; semantic state can be correct while the screen is wrong. |
| What establishes an Expert tier? | A complete, fair-information, versioned naval policy plus declared held-out comparison against the actual shipping Traditional anchor. | Development win rates, complete matches and old Classic promotion results are insufficient. Candidate changes affecting both tiers require refreezing the corrected Traditional anchor before Expert-only comparison. |
| What establishes polished UI? | Existing painted blue/gold theme, distinct ship silhouettes/pennants, fixed viewport, Home/World/Fleet, explicit confirmation and native accessibility paths. | Screenshots cannot prove mist timing, all human comprehension or physical-phone performance. Winner contrast, modal isolation and large-text layout require actual-scale review. |

## Findings and corrections

“Targeted pass” below describes the cited scenario at its recorded snapshot.
Final-tree verification is E20, exact-binary gameplay E21 and inspected installation/media E22. Earlier targeted evidence retains its own source attribution.
The register now contains twenty-three concrete defect/audit findings.

| ID | Defect or audit risk | Correction and evidence | Status at checkpoint |
|---|---|---|---|
| A01 | History equality could overlook naval state while accepting an otherwise coherent checkpoint. A saved state can be valid yet not result from its recorded moves. | Compare complete authoritative `GameState`, with only the documented declined-offer cache normalization. `NavalHistoryIntegrityTests` mutates position, controller, movement, discovery, builder stock and colony points; cold and incremental validation reject all six. E03: thirteen hosted functions across history/timeline/incremental suites pass. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A02 | A naval saved/imported seat could retain a ghost profile identity even if no explicit ghost ID was present. | Shared ghost identity/prefix logic guards both explicit and profile-only setup identity. `MatchSetupGhostTests` rejects naval variants and preserves Classic resume. E03: ten hosted functions pass; the mixed command's unrelated earlier max-text failure remains recorded. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A03 | AI road approach search could value a future site reached through undiscovered land. | Road candidates use known public land only. `roadsCannotPromiseASiteWhoseCoastIsStillHidden` is a counterexample rather than a copy of the implementation. Hidden-world/hand/deck/RNG paired tests cover both tiers. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A04 | Colony telemetry could count home coast or sea as overseas expansion; raw route revisits could label productive backtracking a failure or conceal actual idle loops. | Colony diagnostics require real overseas land. Navigation progress tracks discoveries and new access/settlement context rather than step/resource counters. Tests distinguish idle returns, legitimate colony backtracking, city-only changes and actual discovery. Evaluation schema 3 retains raw revisits separately from idle cycles. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A05 | Replay captions and accessibility values could advance while the map still painted opening fog and missing pieces. Semantic counts falsely suggested a correct final replay. | Historical `BoardView` disables animated state changes; selected historical pieces and mist paint immediately while camera controls remain usable. `NavalReplayRenderingTests` completes a real seed-7501 Expert match and compares painted building/road/sea probes, opening restoration and repeated final restoration. E05: pixel test passes in 225.452 s. E13's live final-candidate 644/644 replay also visibly paints pieces/discovery. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A06 | A publicly certain first colony at twelve points could be undervalued as one point, choosing a productive nonwinning city instead of the fourteen-point win. | `NavalEconomy.colonyPoints` adds the permanent colony point only when the public component is provably closed, overseas, previously unowned by that player and within the two-bonus limit. Unknown connectivity cannot promise it. Both-tier winning-colony and uncertain-component counterexamples were added. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A07 | Reserving any legal landing could prohibit every sailing step, freezing a ship at a poor site while an adjacent better site preserved its access. | Permit a strict one-step landing improvement while retaining coastal access. The poor→rich move is eligible; reverse rich→poor movement is rejected as idle. Both tiers receive the counterexample. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A08 | A policy at thirteen points could retain an immediate victory-card draw premium even while owning all ten victory cards. | Remove that premium using the player's known owned cards and the rules' fixed deck composition. No hidden remaining deck order is inspected. `owningEveryVictoryCardRemovesTheFalseImmediateDrawPremium` covers both tiers. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A09 | Maximum accessibility text consumed the harvest header/confirmation area, leaving resource choices unreachable on a small phone; fixed icon width caused icon/text overlap. | Compact the accessibility header, use available sheet height, preserve a dedicated resource scroll region and pinned forty-four-point Collect control, and scale icon column width. E02/E04/E09 reach every resource and confirm at AX XXXL on iPhone SE; E09's latest max-text harvest pass takes 14.785 s. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A10 | A native harvest accessibility audit found contrast failure on a covered Greece label. A later automation assertion overstated `exists` as evidence of VoiceOver exposure; automation query presence alone does not prove navigation by VoiceOver. | Use a native full-screen presentation, heading accessibility focus and forty-four-point actual button hit shape. Covered Build/navigation/HUD are not hittable. E08's SE audit passes unfiltered; E14 later corrects the separate regular-phone disabled-plaque defect A20 and passes both sizes. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A11 | A Reduce Motion test tapped the center of the native Settings switch row without enabling the system switch, so it tested a false precondition. | Native XCUITest operates the switch thumb, asserts its actual value, launches Voyages, verifies SwiftUI receives Reduce Motion and restores the previous preference afterward. E04: corrected system-preference test passes in 20.576 s. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A12 | User-facing ship names began at Ship 0, exposing an implementation identifier. | A shared presentation helper labels hulls Ship 1 onward in board, capture, feedback, controls and replay; stored IDs and automation identity are preserved. E11's historical Fleet image explicitly shows Ship 1. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A13 | A winner headline used low-contrast player color against a bright painted sky and could compress result/actions at large text or small height. | White winner text on a dark themed plaque; vertically scrollable result contents when needed, with accessible action heights. E09's native maximum-text results test reaches the menu action and returns to the main menu in 8.573 s. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A14 | Save validation could accept impossible wild entitlement queues/capture phase, or Standard naval state contaminated by Conquest armies. | Validate actual roll entitlement and clockwise suffix, partial first/full later units, capture after 11, no incompatible armies/deck/hands. Maximum malformed ship IDs are rejected without overflow. Engine save/production counterexamples and whole-suite warnings-as-errors run precede final gate. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A15 | Expert's certain multi-step sailing/launch wins could rank below a greater-than-ninety-percent but uncertain victory-card draw, so a provable same-turn win could be discarded. | Give certain sailing, launch/landing and direct wins scores of 18,500/19,000/20,000 above the uncertain draw band. `aCertainSailingWinBeatsEvenANinetyOnePercentFinishingDraw` and `aCertainPurchaseAndLandingWinBeatsAHigherThanNinetyPercentDraw` retain those counterexamples. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A16 | Expert's road funding target depended on a future settlement approach. With settlement supply exhausted or all approaches blocked, it could miss a funded finishing Longest Road despite a legal road winning independently. | Add a distinct legal Longest Road funding target near the threshold. `expertFundsAWinnableRoadEvenWithNoSettlementSupplyOrApproach` funds the road and confirms the resulting win. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A17 | The inspected first-gate replay says “discovered 1 hexes”; discovery announcements and Fleet/ship labels could similarly say “1 steps remaining.” | Shared `NavalQuantityText` uses singular/plural hex/step wording across replay, board announcements, Fleet and ship controls. Stored IDs and counts are unchanged. Manual VoiceOver navigation is not claimed. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A18 | A winning move with an open trade refreshed an automated response after game over. Legacy Bot received an empty terminal legal-move set and hit its precondition, crashing the hosted worker and producing collateral zero-duration failures. | Stop terminal queue generation and reject queued checkpoints outside the correct main-turn phase. `winningWithAnOpenTradeEndsAutomatedNegotiation`, `completedPositionDoesNotReconstructAnOpenTradeResponse` and `aCoherentTerminalTradeQueueCannotReviveTheGame` pass (0.005 s). Completed-human checkpoint restore passes serially, then in E14's 22-function hosted suite. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A19 | Two Classic trade flows failed and reproduced serially: the unified automated response queue consumed a human's pending confirmation, so the receipt or still-open proposal vanished. Popup visibility was an insufficient durability boundary. | Pause bot continuation whenever `pendingTradeConfirmation` exists at all three continuation guard points. A new live/cold-resume test preserves the exact session until explicit human confirmation and proves repeat confirmation does not transfer again. E14's hosted suite and native receipt/new-offer flows pass (9.897/24.518 s). | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A20 | The regular iPhone 17 Pro harvest audit still failed on disabled “Collect resource” despite the earlier SE audit pass. `PlainButtonStyle` faded the entire disabled label/plaque against the bright card; serial reproduction confirmed the defect. | A custom `GoldRowButtonStyle` keeps the painted plaque opaque and applies pressed feedback without default whole-label disabled fading. Unfiltered regular-phone audit passes 10.285 s; final SE audit 10.011 s, maximum-text harvest 14.280 s and results 8.456 s pass, no issues waived. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A21 | At World zoom, adjacent forty-four-point ship button regions overlap because hex geometry can be only 14.66 points. Tapping hull A's visible center may activate neighboring B; same-cell stacks did not handle neighboring cells. | Explicit nearby identity choice precedes focus/selection; unambiguous controls stay direct. Typed/SDK follow-ups compile. Hosted geometry/state counterexamples and regular/SE World tests verify adjacent/stacked identity, exact sea target, preview preservation, chosen-hull-only movement and cold resume (E16/E17). A bounded one-billionth-point assertion allowance handles floating frame rounding. | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A22 | Authoritative rolled-number coordinates painted white production rings above mist, disclosing unknown islands/numbers for roughly 1.5 seconds. | Producer uses `Naval.visibleBoard`; renderer independently rejects fog, sea, desert and robber-blocked production. Hosted and regular/SE pixel counterexamples pass. Deliberately removing only renderer guard produces hidden difference 0.5157907 >0.02 with known positive control passing; exact source restored (E16/E17). | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. |
| A23 | Maximum-text SE nearby chooser painted “Ne…”/“Clo…” and clipped row fragments despite ten-function semantic/native success (E17). Hittability did not prove readable identities or rows. | `971a615` retains ordinary compact popovers and adds full-screen painted Nearby/global Fleet at accessibility sizes. Natural wrapping heading, forty-four-point Close, separate uncapped Ship/owner/steps and remaining-space scroll list replace the clipped panel. ID context persists through dismissal while values derive from current public ships. Stronger native tests fully contain each row, exercise both entry points, preview/cancel invariants and Close. Root/documentation reviewers opened all four two-size screenshots (E19). | Closed; correction final-gate verified E20, exact-binary native/media/installation handoff E21/E22. Two-size full-row paint and independent source review pass E19. |

Implementation anchors:
[history validation](../../../Settlers/Persistence/MatchCheckpointStore.swift),
[session/terminal queues](../../../Packages/CatanEngine/Sources/CatanEngine/GameSession.swift),
[human bot-continuation guards](../../../Settlers/ViewModels/GameViewModel.swift),
[gold row style](../../../Settlers/Views/GoldRowButton.swift),
[setup compatibility](../../../Settlers/Persistence/MatchSetup.swift),
[naval state validation](../../../Packages/CatanEngine/Sources/CatanEngine/Naval/NavalStateValidation.swift),
[policy economy](../../../Packages/CatanAI/Sources/CatanAI/Naval/NavalEconomy.swift),
[navigation](../../../Packages/CatanAI/Sources/CatanAI/Naval/NavalNavigation.swift),
[card valuation](../../../Packages/CatanAI/Sources/CatanAI/Naval/NavalCards.swift),
[navigation diagnostics](../../../Packages/CatanAI/Sources/CatanAI/Naval/NavalNavigationDiagnostics.swift),
[replay view](../../../Settlers/Views/GameReplayView.swift),
[replay narration](../../../Settlers/Models/GameReplayNarrator.swift),
[board discovery presentation](../../../Settlers/Views/Board/BoardViewNaval.swift),
[replay pixel test](../../../SettlersUITests/NavalReplayRenderingTests.swift),
[resource choices](../../../Settlers/Views/NavalResourceChoiceView.swift) and
[winner view](../../../Settlers/Views/EndGameView.swift).

## Observed evidence and its boundaries

E01's ordinary-phone command reports **nine hosted functions in two suites** and
**seven native journeys**, both passing. Those journeys purchase/sail/resume,
capture/skip, use Home/World/pinch/pan, configure a clear non-wild Twin Islands
Expert game, harvest one bank card and reach/archive actual victory. Most focused
journeys begin from explicit QA starting positions built through rules/session
moves with documented bank-conserving resource grants. The complete-match test
starts a normal seeded match and drives actual policies/session transactions;
it is not a forced-win fixture. It does not stand in for unscripted human play.

E02 repeats purchase/sail, camera, setup/resume and maximum-text harvest on iPhone
SE. E04 later verifies maximum text and actual system Reduce Motion. Its earlier
harvest audit fails; that failure remains recorded. E08 supersedes the failure
with an unfiltered native audit pass (9.279 s) and seven hosted functions (2.339 s),
overall `TEST SUCCEEDED`. Those functions include a failed city-harvest write
retaining both units until saved-state reconciliation. E09's same-human two-choice
city cold resume passes in 14.221 s; max-text harvest, max-text results and one-card
cold resume pass in 14.785/8.573/14.368 s respectively. The earlier combined E09
commands fail superseded audit/assertion cases, so their individual passes are not
described as entirely green runs. Manual VoiceOver navigation was not measured.
E05 establishes painted replay restoration even though its combined command
fails other tests. The missing
xcresult metadata after disk exhaustion is a receipt failure, not proof of test
failure or permission to claim an entire command passed.

E06 preserves 3,000 generated worlds and fifteen actual exports. Four option
pairings preserve worlds and RNG draws. All 72 forced same-family fallback
combinations pass. Every island offers a best coastal landing worth 6–9 pips;
median harbor/destination route is five steps, and p90 is eight/nine by family.
These measurements support purposeful travel and production capacity. They
do not prove economic equivalence of flexible output or human preference.

The historical development artifact at source `9fd0f8d` is frozen with Release
SHA256 `f7f07042b8fd9f1611c24859df39cfa4231e197bad6137faecc0cbedfbdab5b6`
in [its provenance](/tmp/naval-ai-evidence/anchor-9fd0f8d/provenance.json).
Later A06–A08 corrections affect both policy tiers, so that artifact is historical
and cannot silently serve as the shipping corrected Traditional anchor. Development
matrices and mixed-table pilots guide refinement. The early four-seat pilot did
not establish the intended meaningful Expert improvement. A15/A16 further refine
closing decisions; their targeted counterexample passes are correctness evidence,
not themselves a strength claim. Completed declared confirmation is now preserved
in [the final AI study](evidence/ai-study.md).

The corrected Traditional anchor and final Expert candidate are now frozen.
[Anchor provenance](/tmp/naval-ai-evidence/anchor-a316139/provenance.json) identifies
source `a316139bb2daa22d7224c19953f4a2e32c699c2f`, Release SHA256
`1b0117a4d44fbe4888ab4868f7c4cb0a22001213766ea284bc4b9c4afa9bd582`.
[Candidate provenance](/tmp/naval-ai-evidence/candidate-d863991/provenance.json)
identifies source `d8639917f68563b6fd2ca0d38c5fc28d3fc80a18`, Release SHA256
`509f0b575250a2426c9d026ef3eab9c764dea35e5d68c7fa0e68402f6ee2c952`.
The [portable tool/evidence package](../../../Packages/CatanAI/Tools/NavalEvaluation/README.md)
preserves protocol, raw results, scripts/checksums and arithmetic revision. Root
independently reran 39 Python tests, the 939 retained-file checksums and strict
analysis with the actual frozen artifact bytes. The confirmation ran all twelve
map/option cells with every chair and balanced personalities; table sizes are
separate. Three-seat Expert wins 205/396 (51.77%, Wilson 46.85–56.65%) versus
132/396 control (33.33%): paired +18.43 percentage points, 95% CI +13.64–23.23.
Four-seat wins 154/336 (45.83%, 40.58–51.18%) versus 84/336 (25.00%): paired
+20.83 points, CI +16.37–25.30. All 1,464 games complete without functional
rejection. Both observed effects exceed ten points and paired intervals exclude
zero, meeting the unchanged declared criteria for this policy/anchor pair.
Human opponents, other personality mixes and phone timing are unmeasured.

Contended full-study aggregate latency meets the declared percentile budgets,
but its 48 decisions above 150 ms and worst per-game 53.562/194.267 ms tails are
retained, not hidden. The uncontended 24-game matrix has maximum per-game p95/p99
21.079/49.637 ms and zero above 150 ms. Timing excludes engine application,
checkpoint encoding and rendering. A separately labeled integrated `a8bd01c`
48-development-trajectory equality bridge after the terminal guard passed,
preserved in the [integrated bridge](evidence/integrated-ai-equivalence.md): all 48 result records/fingerprints match after excluding
only build ID, with 48 complete games and zero rejection. Commit `df5ca979` preserves
109 checksummed files and a separate integrated artifact; its report/data are
now integrated. The frozen study's artifact/performance identity
does not change.

E12's [first gate log](evidence/receipts/full-gate.log) verifies
329 engine functions in nineteen suites (29.179 s) and 281 AI functions in
twenty-seven suites (628.389 s). Coverage is 96.52% engine and 95.63% AI, both
above the 95% floors. Every non-app stage, gitleaks and Release/Debug builds pass.
The **whole gate fails**, exit 1, on app tests. The
[failed receipt](/Users/alex/.codex/artifacts/naval-exploration/first-gate-failed.xcresult)
and [manifest](/Users/alex/.codex/artifacts/naval-exploration/first-gate-manifest.json)
pin source `02eb013ecb5a175e2b53b931a171172ca171b08d`, Debug executable SHA256
`81a96f379dedd36a6b66e98894ea6c362849435b30531f5693ff4287dc59fcdb`, simulator
`937692FF-BFBF-4683-80E5-2590F5288D56`, iOS 26.5. A18's hosted crash caused
collateral failures; two Classic trade flows and regular-phone disabled Collect
contrast also failed and reproduced serially. They are not dismissed as worker
count flakes.

E14 preserves those serial failures and the corrections: three engine regressions
pass; the second serial native command passes 22 hosted functions in two suites
(9.104 s), receipt (9.897 s), new-offer popup (24.518 s), and unfiltered iPhone 17
Pro harvest audit (10.285 s), overall `TEST SUCCEEDED`. The final SE command also
passes unfiltered audit (10.011 s), max-text harvest (14.280 s) and max-text results
(8.456 s), overall `TEST SUCCEEDED`. Corrections are committed `be5ddeb`, tools/report
`a8bd01c`. The [complete corrected gate](evidence/receipts/full-gate-final.log)
passes all eleven stages at `a8bd01c`, exit 0 (E18). Engine 332 functions/19 suites
pass (16.871 s), AI 281/27 (413.559 s), coverage 96.54%/95.65%; app/UI summary
has 538 functions/1,191 parameterized runs, zero failed/skipped. The valid core
receipt is preserved. This precedes later map and accessibility chooser changes.

E16's regular positive map run passes 37 hosted functions/four suites and seven
native functions (44 functions/54 runs), zero failed/skipped. E17's SE ten native
functions also pass (154.552 s), including maximum-text nearby reachability. Its
opened screenshot still paints clipped heading/Close/rows: A23 was an actual
visual defect despite that test pass. E19's correction at `971a615` subsequently
passes complete-row tests and independently inspected two-size paint. Partial
preceding rows in the scrolled list are expected; the chosen Ship 3 card is whole.

E11's [visual review](evidence/visual-review.md) preserves original opening stills
with checksums. It records historical opening withdrawal and bounded purchased-ship
launch vision/explicit focus. The opening is a fresh random match with unrecovered
seed and a pre-final-AI binary. The launch/Fleet subset still has three steps and
a staged Sail decision, so it does not prove committed sailing/capture motion.
E13's opened live final-candidate replay shows a correctly painted 644-move final
frame, but remains visual inspection ahead of the official test verdict/export.

E20 preserves the [final gate log](evidence/receipts/full-gate-971a615.log),
[summary](evidence/receipts/full-gate-971a615-summary.json) and
[durable receipt](/Users/alex/.codex/artifacts/naval-exploration/full-gate-971a615.xcresult).
Frozen source `971a615` passes all eleven stages, exit 0. Engine 332 functions in
nineteen suites pass (16.379 s), AI 281/twenty-seven (395.098 s), coverage is
96.59%/95.63%, and app/UI has 552 functions/1,211 runs, zero failed/skipped.
App stage takes 1,342 s; Release and Debug builds pass in 44/2 s. Exact Debug
executable SHA256 is
`2ab9e0852e6e5db7ef13f9b3eaeba8bf7291bc315e6abeadf5e1ea2dc1c458f8`.
All audit corrections are final-gate verified. The exact executable also passes
`test-without-building` native purchase/three-step discovery/cold resume (31.122 s),
capture/cold resume/confirmation (14.281 s), and actual Settings Reduce Motion/
Home/World/preference restoration (19.636 s), exit 0, with unchanged SHA (E21).
E22 closes fresh final opening, inspected sequential media, process survival and
F05. The raw movie is paired with decoded frames actually opened by both reviewers;
no unsampled frame-rate claim is made. Native rare-state journeys are Traditional,
while the ordinary opening and live review position are Expert.

## Final delivery record

The final [gate log](evidence/receipts/full-gate-971a615.log) and
[summary](evidence/receipts/full-gate-971a615-summary.json) preserve all eleven
passing stages. The unchanged executable has a separate
[native journey log](evidence/receipts/final-artifact-journeys.log) and
[summary](evidence/receipts/final-artifact-journeys-summary.json), fresh
[installation/process receipt](evidence/receipts/final-installed-artifact.json),
[screenshot manifest](evidence/screenshots/final-artifact-manifest.json),
[motion manifest](evidence/motion/final-motion-manifest.json) and
[independent visual review](evidence/visual-review.md#final-gallery-and-motion).
These are completed records. Original valid xcresults and raw movies remain in
`/Users/alex/.codex/artifacts/naval-exploration/`; source-bound selected receipts,
images and decoded frames are portable within the repository.

The frozen [AI study](evidence/ai-study.md) and
[integrated 48-trajectory bridge](evidence/integrated-ai-equivalence.md) retain
separate artifact/timing identities. Both policy reports and checksummed tooling
remain beneath `Packages/CatanAI/Tools/NavalEvaluation/`. Earlier failed gate,
serial reproductions, clipped-paint counterexample and deliberately failing fog
negative control remain in the acceptance evidence index.

## Final disposition

| Field | Recorded result |
|---|---|
| Full-gate production source | `971a615ba701e2eca9e22ae538cadbfd8d243d8a`; subsequent setup-only correction `ac3dec5` places Naval under Rules and has separate targeted verification E23. |
| Original E20/E22 gated/installed Debug artifact | Version 1.0/build 16, SHA256 `2ab9e0852e6e5db7ef13f9b3eaeba8bf7291bc315e6abeadf5e1ea2dc1c458f8`. |
| Traditional / Expert frozen identities | `a316139bb2daa22d7224c19953f4a2e32c699c2f` / `d8639917f68563b6fd2ca0d38c5fc28d3fc80a18`; Release checksums and exact protocol retained in the AI study. |
| Three-seat held-out conclusion | +18.43 pp, 95% paired CI +13.64–23.23; 396 complete games per arm. Declared criteria pass. |
| Four-seat held-out conclusion | +20.83 pp, 95% paired CI +16.37–25.30; 336 complete games per arm. Declared criteria pass. |
| Final gate | PASS exit 0 E20; all eleven stages, 552 app/UI functions/1,211 runs, zero failed/skipped. |
| Interface and modal audit | Unfiltered regular/SE audit, maximum-text choices and two-size complete-row paint pass E19/E20. Final inspected gallery E22. No issues waived. |
| Motion and exact native gameplay | E21 transactions/cold resume/system Reduce Motion pass; E22 reviewed seeded opening and sequential committed sailing/capture/Reduce Motion frames. |
| Current installation and process | E23 updates in place to `ac3dec5`, preserves the checkpoint byte-for-byte and leaves PID 86428 on main menu without QA setup/seed/position flags; no new crashes. E22 retains the original installation. |
| F01–F15 and all 23 findings | Closed for required local-simulator delivery; ready for human review. |

The conserved saved review position is Expert/Naval V1 Archipelago with fog and
resource choice ON, four seats, human 0 main turn and no pre-purchased human ship.
**Build → Ship** begins a real purchase; **menu → Quit → Main Menu → New Game → Rules → Naval** starts
ordinary play. The review worktree remains isolated and available.

The later Rules placement correction is independently reviewed and has real
shipping-control start/resume/prefill checks on both sizes, all four land-rule
return paths and a maximum-text SE row screenshot. A label-column paint issue
was corrected with a scoped native geometry guard; its initially ambiguous
background-text lookup is preserved as a failed-test counterexample in E23.
Engine, policies and saved-field definitions remain unchanged.

Human enjoyment, unscripted human difficulty, other personality mixes, manual
VoiceOver play and physical-phone performance remain unmeasured. Simulator native
audits, semantic queries and screenshots do not certify those claims. There is no
claim of unsampled animation frame-rate or TestFlight distribution. No required
local acceptance item is waived because implementation was expensive.
