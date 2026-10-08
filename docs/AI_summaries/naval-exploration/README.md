# Naval exploration product program

## October 8 follow-up: discard, optional stealing and purposeful scouting

Alex's screenshots `IMG_1770.PNG` / `IMG_1769.PNG` show a real seven followed by
robber placement while the human retains eight resource cards. The diagnosed
cause is Naval's ten-card rules configuration, not a missed discard editor.
New Naval v5 games must use seven: above seven resources, discard half rounded
down before moving the robber. Development cards do not count and a Knight
does not trigger discarding. Recorded v1–v4 games retain their original rules;
an explicit ongoing-match upgrade is a separate decision.

Ship stealing becomes an explained Naval Advanced Settings choice, Off for a
fresh game or an old implicit New Game prefill, while an explicit future On
choice remains remembered. Enabled stealing retains the existing after-production
11 rule, global selection and lasting control. A human-involved transfer must
produce an acknowledged, durable painted receipt identifying the former and
new controller. It cannot expire unseen in the ordinary notice queue. Ships,
colonies, builder hull stock and resource ownership otherwise retain their rules.

Both AI tiers currently hard-reject leaving any useful landing, even when they
cannot fund its settlement. Frozen, repeated real matches demonstrate waits
despite public voyages revealing three or nine hexes. A separately persisted
scouting revision must reserve a realistically fundable landing, avoid redundant
friendly reservations and value genuine frontier progress separately from the
best visible landing. It must respect fog, rival blockades, legal routes and
the two-hex allowance. No sailing merely for animation and no new strength claim.

<scratchpad>

Data flow: saved Naval version/options → effective engine rules → actual roll
and legal mask → session transaction → atomic checkpoint → discard/transfer UI
and policy observation. Scouting scores consume that public observation, never
authoritative hidden terrain. Receipts publish only after the same transaction
commits and must hold further gameplay until acknowledgement.

Constraints: exact old recordings and policy identities, conserved cards,
unchanged current ship identity/colonies, stable board viewport and command-row
reserve, one owned native test device and no other project's simulator changes.
Naive failure boundaries include seven resources plus development cards, odd
hand totals, another seat rolling seven, several simultaneous discarders,
Knight versus rolled seven, cold resume mid-discard, capture disabled during
an eleven harvest, human loss behind a modal, failed receipt writes, a funded
landing, duplicate friendly landing reservations and a rival-blocked route.

Alternatives rejected: changing the threshold globally would rewrite old
replays; defaulting every missing capture key to Off would erase old pending
captures; a longer transient toast still expires unseen; unconditional voyage
bonuses reward aimless movement. Verification must start before a real seven,
perform actual captures, acknowledge/resume receipts, reproduce the identified
idle decisions and finish real app-hosted matches. Directly seeded discard or
win screens cannot prove those transitions.

</scratchpad>

## Build 27 ship defense: delivered

Ship defense is live in Alex's Internal TestFlight. In new Naval games, an
opposing ship blocks entry, passage and launches into its sea hex, even after
its moves run out. Friendly ships may share water; an existing ship can leave
a mixed-owner stack after capture. Saved v1–v3 games keep their original rules.

[E32](acceptance.md#build-27-follow-up-e32) records 48 new functional winners,
six exact process repeats, the full gate and verified signed Apple delivery.
Root reviewed the [final gallery](evidence/build27-blockades/gallery.html),
including the actual Washington winner, and separately approved the ordinary Release menu. Owned QA is
shut down; other projects and all 14 devices remain intact. Both AI tiers use
public blockades, with no strength claim. [PR #61](https://github.com/jakebeinart1/Settlers/pull/61)
is the integration record for this verified source.


## Build 26 Monopoly follow-up: delivered

[E31](acceptance.md#build-26-follow-up-e31-delivered) adds exact public collectible
counts, selected-gain previews and explicit bank/rival quantities without rule,
AI or save changes. Full gate,11 original reviews, ordinary Release, strict signed
payload, Apple26/Alex internal access and owned-QA cleanup pass. Agent review
now supplies approval: PR #60 integrates verified work; PR #58 is subsumed after its
unique simulator safeguards are retained. Live GitHub records own final status;
older approval-pending statements below are historical snapshots.

## Build 25 card follow-up: delivered, October 7

Alex's October 7 follow-up asks all five development cards to suit the painted
interface, align HUD counts with resources, remove READY from compact names,
fit their choices/actions and receive deliberate inspection in a complete Naval
match. D50–D53 select native engraved emblems, shared 44-point HUD slots,
compact browsing and rule-correct resource choosers. No generated PNG is replaced.

[E30](acceptance.md#build-25-follow-up-e30-delivered) freezes production at
`a9e0e88eb30e5bd0c5f96c6b1354ed2e7b7023c1`, 1.0/build 25, with
[376 matching inputs](evidence/receipts/build25-final-production-inputs.json).
All [112 package inputs](evidence/receipts/build25-engine-ai-source-equivalence.json)
match build 24 exactly, so its 48-match/six-repeat functional evidence is reused
without a new strength claim. The ordinary match naturally owns Knight at
purchase/maturity/result moves 160/175/177 and reaches a winner; all five types
are covered separately by conserved fixtures and actual purchases.

The failed first complete gate remains recorded. Test-only `cffe613` corrects
large-text test navigation and passes the replacement full gate, all ten mandatory
stages, then publishes the branch. Native: 760 functions, 759 passed, zero failed,
one skipped; 1,518 passing runs. Root approves all 27 unchanged final originals (26 Debug plus one Release).
Ordinary fresh Release survives six seconds without QA arguments or new crashes.
Archive/export/upload and actual payload signing/checksum comparison pass; Apple
confirms VALID/unexpired internal IN_BETA_TESTING for Alex. Owned QA cleanup
passes, preserving the other 13 devices and other projects' booted states. PR #60 is unmerged, awaiting approval;
[tested-head CI](evidence/receipts/build25-tested-head-github-ci.json) passes. Main's later `bc11db4` adds only a research document; `83d8525` remains
the historical integration base. Build 24's delivered record below is unchanged.

Created October 4, 2026, from Alex's design conversation. This is the canonical
product charter and delivery record for the complete Empires naval mode, Voyages.
Gameplay, map generation, both AI tiers, setup, persistence and presentation are
implemented in the isolated worktree. Original local-simulator acceptance is
complete; subsequent corrections and delivery retain their own source-bound
verification records below.

The intended experience is buying a ship, sailing into an unknown world,
watching mist withdraw to reveal meaningful new land, and establishing a lasting
presence there. Randomized geography should create different expeditions and
settlement choices. Global ship capture adds consequential changes of ownership.
Traditional and Expert opponents, a refined interface and complete-match evidence
are part of the finished product.

**Build 24 delivered, October 7:** D45–D49 implement
painted any-resource terrain, original harvest entitlement/progress, natural
ship language, current win goals and fair competition on human Accept of a bot
proposal. New Naval v3 matches receive two sea hexes per ship turn, highlighted
public endpoint costs and one canonical shortest route per voyage. Legacy v1/v2
matches retain three adjacent moves and exact replay behavior.

The managed `/Users/alex/.codex/worktrees/naval24-main-integration/Settlers`
checkout integrates Naval above main `83d8525`, retaining its four recent
resource-square/Skip/Block/leaderboard/rename fixes. Production is frozen at
`9bce5f77a38684bd6e011fac8838c74b38440798`, version 1.0/build 24, with
[376 matching inputs](evidence/receipts/build24-final-production-inputs.json).
The integrated focused command failed three checks and its refined follow-up
failed one contrast audit. The corrections and subsequent three-case native
harvest pass retain those failures. The native audit still emits three identified
Contrast flags; an exact-ID handler accepts each only after a live sRGB screenshot
measures at least 7:1 (8.1257, 7.9583 and 7.9671). Every other issue fails.
[E29](acceptance.md#build-24-follow-up-e29-delivered) gives the qualification.

Fresh frozen-source [v3 functional evidence](evidence/receipts/build24-v3-summary.json)
passes 48 matches and six complete-byte result/trace repeats, with 112 package
files stable. Actual travel is 1,256 sea hexes/687 actions/569 two-hex voyages;
there are no forced ends, idle sailing/trade cycles or duplicate proposals.
Two raw revisits are productive colony/capture visits. Colonies occur in 47/48
games; peak process RSS is 22.55 MiB. Independent reveal-union reconstruction
covers only two retained fog-off checkpoints; engine/source fog tests are separate.
No new strength claim follows.

Root inspected four integrated/refined harvest originals at local/World/maximum
zoom/maximum text and the actual Expert-rival notice. The generated harvest PNG
was never edited. Those development captures retain their own attribution;
the later final-source gallery and ordinary Release runtime have their own
verified receipts below.
The first complete pre-push gate (session `52090`) failed two test oracles:
754 app/UI functions, 750 passed, two failed/two skipped, 1,509 passing runs.
Engine 391/31, AI 308/31, coverage 96.74%/96.05%, Release and every other mandatory
stage pass; optional Debug app build is skipped. Test-only `67efbad` fixes the
versioned movement counterexample and scopes rulebook scrolling to Settings;
three functions/eight runs then pass. All 376 production inputs and 112 package
files remain unchanged. The
[replacement full gate](evidence/receipts/build24-final-prepush-command.json)
passes all ten mandatory stages, session `91604`, exit 0, and publishes
`codex/naval24-main-integration` at test-only `67efbad`. App/UI passes 753 of
754 functions, zero failures, one skip, with 1,512 passing runs; hosted 581/82,
Engine 391/31 and AI 308/31 pass, coverage 96.78%/96.05%. Optional separate
Debug app build skips; the native Debug test action built the app and bundles.
Ordinary Release 1.0/24 is freshly installed without QA arguments; PID `93934`
survives six seconds without new own crashes. Root directly approves all
[23 unmodified final originals](evidence/screenshots/build24-final-manifest.json):
22 Debug native attachments and its ordinary Release menu. Three caption crops
retain the native contrast qualification. Archive/export/upload and strict/deep
Production signatures pass. Apple build `9b3882ef-a85c-46c2-8d1a-2d83f5483aef`
is VALID, unexpired and internally IN_BETA_TESTING, with Alex's Internal all-build
access confirmed at 13:06:46 UTC (9:06:46 a.m. EDT), October 7, and independently
at 13:06:40 UTC. The [final audit](evidence/receipts/build24-final-independent-release-audit.json)
passes source, 303 matrix hashes, 23 image hashes, runtime and actual uploaded
payload/signature/checksum/access. The preserved uploaded IPA `0ef24d0…becc`
is distinct from review `f899e4d…6770`; only designated executable signature
bytes differ. [E29](acceptance.md#build-24-follow-up-e29-delivered) and
[delivery](phone-delivery.md#build-24-delivered) retain exact receipts and limits.
[PR #60](https://github.com/jakebeinart1/Settlers/pull/60) awaits one actual
approval, with no merge recorded. Tested `67efbad` passes required Linux/SwiftLint
[CI](evidence/receipts/build24-tested-head-github-ci.json); manual project drift
skips and local drift passes. QA alone is shut down; other projects' booted
devices remain untouched. Three helpers are
[recoverably archived](evidence/receipts/build24-helper-worktree-cleanup.json).
External build 24 is unreleased; physical-phone installation/play, hardware
timing, manual VoiceOver and new strength remain unobserved. The sole 375×667
footer skip on 402×874 QA is explicit; no current compact execution is claimed.
Build 23/22 history is preserved below.

**Build 23 delivered, October 7:** Empires 1.0/build 23 is available to Alex in
internal TestFlight, confirmed at 4:16:30 a.m. EDT. Apple build
`cfcb926b-7b11-4178-9d19-8df7a9e5e597` is VALID, unexpired and internally
IN_BETA_TESTING; Alex belongs to Internal with access to all builds. The
[independent final audit](evidence/receipts/build23-final-release-audit.json)
passes with no blocking defects, including an independent Apple readback at
4:18:25 a.m. EDT.
Alex requested clearer
construction availability, eight painted civilization ships with owner-colored
cloth and distinct hulls, and protection against repeated Skip touches answering
a new trade. D42–D44 record the selected presentation and interaction changes.
Frozen source `1dfae7c`, version 1.0/build 23, passes all eleven gate stages,
exit 0: Engine 371/28, AI 303/30, hosted 565/80, coverage 96.67%/96.01%;
app/UI 732 functions (731 passed, zero failed, one size-specific skip) and
1,476 passing runs. The skipped 375×667 footer case passes separately on the
compact phone. Targeted Build/trade/artwork and real mixed-controller stack
checks pass after the retained red baselines and test-oracle corrections.
All 371 production inputs are frozen; all 111 engine/AI package files match
build 22, so its 48-match/six-repeat functional evidence is reused without a
rerun or new strength claim. Seventeen unmodified final-source images, including
all eight local fleets and the ordinary Release menu, are root-inspected.
Ordinary Release 1.0/23 was freshly installed without QA arguments; root inspected
its menu, PID 54344 survived six seconds and no new own crash reports appeared.
Archive/export/upload and strict/deep Production signing pass. The uploaded
payload and accepted ContentDelivery checksum are preserved separately from the
review export, differing only within the executable's code signature.
[E28](acceptance.md#build-23-follow-up-e28-delivered) and the
[delivery record](phone-delivery.md#build-23-delivered) retain exact source,
artifact and access receipts. Reused QA is shut down, the compact device alone
was deleted and both helpers are recoverably archived; root/durable evidence
remain retained. External build 23 is unreleased; physical-phone installation/
play, hardware timing and new AI strength remain unobserved. Build 22/21 remain
historical with their original receipts intact.

**Earlier build 22 delivery, October 7:** Empires 1.0/build 22 is available to Alex in
internal TestFlight, confirmed at 12:59 a.m. EDT and by independent read-back.
Apple build `45c00f05-28b4-42de-93f6-016e4ed8e67a` is VALID, unexpired and
IN_BETA_TESTING; Alex's Internal group has access to all builds. Source
`1cf1c0f` charts all four home harbors through mist, retains hidden overseas
harbors until their coast is known, and makes World reversible through Return.
Return preserves the preceding zoom and pan, including an already fitted
zoom-one view; Home remains a separate explicit focus. Exact legacy queued
trade observations migrate without resampling their replies. Engine checks and
the two focused native commands pass, as does the later fitted-pose regression.
The current-source gate now passes all eleven stages, exit 0: Engine 371/28,
AI 303/30, coverage 96.72%/96.01%, app/UI 704 functions (703 passed, zero failed,
one existing size-specific skip), 1,433 passing runs. The natural-seven cold
resume passes. Ordinary Release 1.0/build 22 was freshly installed without QA
arguments; its main menu was inspected, PID 46232 survived four seconds and no
new own crash report appeared. Five final-source Debug captures and the Release
menu are inspected and separately attributed from the earlier intermediate images.
All 48 declared Naval functional matches complete and all six fresh-process
repeats match every result field and move trace. These are functional results,
with no new AI strength claim. Archive/export/upload and independent final
release audit pass; the actual uploaded IPA is distinguished from its review
export by code-signature-only differences. External build 22 remains unreleased,
and physical-phone installation/play are unobserved. The reused QA device is
shut down; both helpers are recoverably archived, with root and durable evidence
retained. [E27](acceptance.md#build-22-follow-up-e27-delivered) and the
[delivery record](phone-delivery.md#build-22-delivered) preserve source, artifact
and tester-access attribution.

**Earlier build 21 delivery, October 6:** Ordinary home-island settlements
can be placed inland. Ships restrict only founding without a road at the exact
accessible coastal corner; established islands still expand inland through
owned roads. Source `60394e6` passes all eleven gate stages, exit 0: Engine
365/26, AI 303/30, coverage 96.63%/96.01%, app/UI 694 functions (692 pass,
zero failures, two existing conditional/size skips), 1,419 passing runs.
All 48 Naval functional matches and six separate-process repeats pass, with
engine/AI source hashes unchanged. The ordinary Release 21 simulator process
survived, and the final inland placement/resume screenshots were inspected.
Apple build `23440fef-103a-4c7b-8896-a0164c7bab74` is **VALID** and internally
**IN_BETA_TESTING**; Alex Chandler's Internal group has access to all builds.
External build 21 is not released, and physical-phone installation is unverified.
Signing succeeded after Alex's local lock/unlock authentication refresh despite
the earlier confirmed unlocked status; the prior CLI and native Xcode failures
remain preserved. No certificate or access policy was changed. Production source
is `60394e6`, archived at docs-only head `d56581d`. Actual uploaded IPA
`1f1d731…3202` is separately attributed from local review export `a1a1b182…25c`;
their only payload difference is the executable's code signature. The
[delivery record](phone-delivery.md#build-21-delivered),
[E26](acceptance.md#build-21-follow-up-e26-delivered) and
[final gallery](evidence/visual-review.md#build-21-inland-settlement-gallery-delivered)
retain the completed verification and source attribution. No new simulator was created; two
disposable task-owned devices were backed up and deleted, reclaiming about 5 GB.
The reused QA and review simulators are shut down, and the original skills now
retain inventory, reuse and individual cleanup rules in both checkouts.
After delivery, the task's native Xcode project was closed and its temporary
compilation cache removed; signed artifacts and failure evidence remain retained.

**Earlier build 19 delivery, October 5:** Advanced Settings now owns island,
mist and resource choices on a separate painted surface; regular phone setup
fits without scrolling. Naval v2 settlement sight is centered on the actual
corner, with v1 saves/replays preserved. Water has varied ripples and known-coast
foam; opaque cloud banks replace the flat cover. Source `5c01f39` passes all
11 gate stages, exit 0: Engine 358/25, AI 295/29, coverage 96.65%/96.03%, app/UI
688 functions (686 pass, zero failures, two explicit skips), 1,379 passing runs.
All 48 fresh v2 AI matches and six separate-process repeats pass. Apple build
19 is **VALID**, **IN_BETA_TESTING**, with Alex's access confirmed. The
[delivery record](phone-delivery.md#build-19-refinement-delivered) and
[current gallery](evidence/visual-review.md#build-19-refinement-gallery) retain
the artifact, screenshots, limits and source attribution.

**Earlier build 18 delivery, October 5:** Alex authorized iPhone delivery after
widening and reviewing Match Settings. Source `8953413` prepares build 18 with
the current phone release's gameplay, trade, archive/provenance and public movie
behavior preserved. The [release integration](release-compatibility.md) records
the compatibility boundary. Selectors share a 114-point heading lane and an
8-point gap, with 46-point targets. One info control per row opens named option
descriptions and brings them into view. Regular/SE native captures were reviewed;
the combined 30-function/41-run focused check and all 48 trajectory comparisons
pass. The initial release gate passed ten stages and failed the app/UI stage.
The complete serial rerun now passes 684 functions: 683 passed, zero failed, one
size-specific skip, with 1,376 passing runs. Apple has accepted **1.0/build 18**:
**VALID**, **IN_BETA_TESTING**, with Alex Chandler's Internal tester access
confirmed. Open TestFlight → Empires → Update, then New Game → Rules → Naval.
The [delivery record](phone-delivery.md) retains the exact signed artifact and access result.

**October 5 setup correction:** Naval is offered in **Rules**, beside Standard
and Conquest, as Alex requested. Selecting it opens the island, mist and resource
options and identifies the 14-point island world. Classic/Vast remain land-board
choices and are restored when leaving Naval. Source `ac3dec5` changes presentation
and native regression tests only; the full gameplay gate below remains attributed
to frozen `971a615`, with subsequent selector verification recorded separately
in [E23’s receipt](evidence/receipts/naval-rule-selector.json). Actual setup/start/
resume/prefill passes on both phone sizes; land/rules transitions, keyboard
invariance, hosted setup suites, strict lint and Release/Debug builds pass.

## Read this program

- This file owns motivations, confirmed commitments and stage completion criteria.
- [Decisions](decisions.md) owns selected D01–D49 outcomes, alternatives and the decision process; feedback can reopen a recorded decision.
- [Acceptance](acceptance.md) owns the requirement and evidence framework.
- [Domain language](../../../CONTEXT.md) owns definitions, including the distinction
  between a player's hand and the bank.
- Repository `CLAUDE.md`, its referenced global rules, and original project skills
  remain the operational guidance. This program does not replace them.

## Current state and isolation

| Item | State |
|---|---|
| Stage 0 | Charter and planning framework recorded; independently reviewed |
| Stages 1 through 5 | Delegated design selected, critiqued and implemented; [contract](design-contract.md) |
| Stage 6 | Complete: engine/session/app/persistence/replay implemented; terminal and human-confirmation repairs plus map/interaction corrections pass final E20 gate and E21 exact-binary native journeys |
| Stage 7 | 3,000-map study, both naval tiers and frozen 1,464-game confirmation complete; declared three/four-seat improvement criteria and host latency pass. [Exact AI study](evidence/ai-study.md); [integrated-engine 48-trajectory equivalence](evidence/integrated-ai-equivalence.md) passes |
| Stage 8 | Complete: actual native journeys, cold resume, victory/painted replay, two-size accessibility refinement and independently inspected final opening/travel/capture/Reduce Motion media. E19/E21/E22 |
| Stage 9 | Complete for local simulator handoff: final `971a615` gate passes all eleven stages, exit 0; all 23 corrections verified; exact gated binary freshly installed, surviving and ready for human review. F01–F15 closed with E20/E21/E22 |
| Build 24 follow-up | Frozen `9bce5f7`, 1.0/24, 376 bound inputs above main `83d8525`; fresh 48-match v3 matrix and six complete-byte result/trace repeats pass. Integrated/refined failures retained; three harvest native cases pass with exact-ID, live ≥7:1 contrast qualification. Four harvest images and actual rival notice inspected. First full pre-push gate failed two obsolete test oracles; all other mandatory stages pass and optional Debug app build skips. Test-only correction passes 3 functions/8 runs; final `91604` passes all ten mandatory stages and publishes `67efbad`. App/UI 753/754 pass, zero failures, one skip, 1,512 passing runs. Ordinary Release survives six seconds and all 23 final originals are approved. Archive/export/upload/signatures and independent final audit pass; Apple VALID/internal IN_BETA_TESTING with Alex's access confirmed (E29). QA alone shut down; three helpers archived. PR #60 awaits approval, tested-head CI passes, unmerged. |
| Build 23 follow-up | Frozen `1dfae7c`, version 1.0/23: all eleven gate stages pass, 731/732 app/UI functions pass with one size skip independently passed on compact. Seventeen images inspected; ordinary Release survives six seconds. Archive/export/upload/signature pass; Apple VALID/internal IN_BETA_TESTING with Alex's access confirmed. E28 retains targeted and reused build 22 functional evidence. |
| Build 22 follow-up | Source `1cf1c0f`; all eleven gate stages pass, ordinary Release survives, final-source media inspected, 48 functional matches/six repeats pass. Signed upload and independent audit pass; Apple VALID/internal IN_BETA_TESTING with Alex's access confirmed (E27). |
| Latest verified phone delivery | Empires 1.0/build 24 internally available to Alex, verified October 7 at 9:06:46 a.m. EDT and independently at 9:06:40. External build 24 unreleased; physical installation/play unobserved. Build 23/22/21 remain historical. |
| Simulator evidence | Reused QA `937692FF`; build 24 full gate, ordinary Release six-second survival and 23 root-approved final originals have separate receipts. Build 23's seventeen-image gallery and all earlier/intermediate captures retain their source/configuration identities. |
| Worktree | `/Users/alex/.codex/worktrees/naval-exploration/Settlers` and main integration retained; three implementation helpers recoverably archived with their changes integrated; durable AI/release evidence retained |
| Build 24 integration checkout | Managed `/Users/alex/.codex/worktrees/naval24-main-integration/Settlers`, branch `codex/naval24-main-integration`; frozen production `9bce5f7` above Naval squash/main `83d8525`; test-only `67efbad` preserves production/package hashes; final pre-push `91604` passes all ten mandatory stages and publishes branch `67efbad`; PR #60 attached; gate/runtime/gallery/signatures/upload/Apple verified; tested-head CI passes, merge awaits approval |
| Branch | `codex/naval-exploration` |
| Planning base | `38f7885ddfd30deefdfa9b1b3bde7756804f8570`, fetched `origin/main` |

The primary checkout's unrelated research changes remain untouched. Its original
project skills were updated with Alex's requested simulator lifecycle guidance.
The new worktree starts from current main, including versioned Expert support.
It stays attached for the program's continuation. Implementation contributors
need separate checkouts under the repository's concurrent-agent guidance;
read-only review can inspect this checkout. Heavy simulator/gate runs serialize.

Current AI conclusions apply to the frozen naval-capable Traditional/Expert pair
with balanced personalities: paired improvements +18.43 percentage points at three
seats (95% CI +13.64–23.23) and +20.83 at four (+16.37–25.30), with every chair
and all twelve map/option cells. Host timing excludes rendering and physical-phone
execution; human enjoyment and other personality mixes are unmeasured. These
historical v1 strength conclusions do not transfer to the inland-corrected v2;
E26's and E27's matrices are functional evidence. Native product acceptance is
separately closed by E20/E21/E22 and refined by E26/E27. Build 22's local
gate/runtime/gallery, signed artifact and tester-access checks pass; unscripted
hardware play and new AI strength remain unmeasured. Build 23 changes app
presentation and interaction; it has no new engine/save schema or AI strength
claim. Its own frozen-source gate passes; the unchanged-package receipt supports
reusing E27's functional matrix explicitly, without reporting a new experiment.

Build 24 changes engine/session and Naval policy behavior. Its fresh v3 functional
and separate-process evidence binds to frozen `9bce5f7`: 48 matches and six
full-byte result/trace repeats pass. Neither E27's v2 matrix nor the historical
v1 strength study establishes v3 strength. Legacy replay, declined/expired/manual human trade paths,
the integrated inland/harbor/Return behavior and Expert-card baseline remain
required regressions. Trade competition uses policy RNG, preserving the engine
dice/deck sequence.

The [acceptance register](acceptance.md) closes all fifteen requirements for local
simulator review. The [audit report](audit-report.md) retains all twenty-three
findings, the failed first gate, later targeted counterexamples and their fixes.
Final frozen `971a615` passes all eleven gate stages, exit 0: engine 332 functions/
19 suites (16.379 s), AI 281/27 (395.098 s), coverage 96.59%/95.63%, and app/UI
552 functions/1,211 runs with zero failed/skipped; Release and Debug compile.
The [final gate summary](evidence/receipts/full-gate-971a615-summary.json) and
[valid result](/Users/alex/.codex/artifacts/naval-exploration/full-gate-971a615.xcresult)
are retained. The original E20/E22 Debug executable SHA256 is
`2ab9e0852e6e5db7ef13f9b3eaeba8bf7291bc315e6abeadf5e1ea2dc1c458f8`.

The exact binary passes post-gate native purchase, three sailing steps/discovery/
cold resume, capture/cold resume and actual Settings Reduce Motion journeys.
The [final gallery and sequential motion review](evidence/visual-review.md#final-gallery-and-motion)
include the ordinary Expert opening, Traditional rare-state transactions and
separately attributed actual Expert victory/replay. Historical failed receipts
and the intentionally failing fog negative control remain preserved.

**Earlier E23 simulator handoff:** Empires Voyages Review, iPhone 17 Pro/iOS 26.5, received the
updated `ac3dec5` Debug build, version 1.0/build 16, on the main menu. Open
**New Game → Rules → Naval**. The [historical installation receipt](evidence/receipts/naval-rule-selector.json)
records surviving PID 86428, executable/code-library hashes and no new crashes.
The in-place update preserves the original saved review checkpoint byte-for-byte.
Resume still offers the earlier prepared Expert/Naval V1 Archipelago match; its
conserved extra-card position supports a real **Build → Ship** purchase and Fleet travel.
That historical process had no setup fixture, fixed-seed or rare-position flags, so
future games and saved prefills follow ordinary behavior. The earlier E22
[installation receipt](evidence/receipts/final-installed-artifact.json) remains historical.
Human enjoyment, manual VoiceOver play and
physical-phone timing remain unmeasured. TestFlight delivery is now authorized
and its current verification is recorded above; E23 itself was simulator-only.
The canonical [simulator skill](../../../.claude/skills/run-settlers/SKILL.md#voyages-launch-arguments-and-fixture-bounds)
records actual naval QA arguments and their fixture/economy boundaries.

## Product motivations

1. **Discover a world.** An unfamiliar coastline or island changes a player's
   choices; revealing cosmetic terrain alone does not satisfy exploration.
2. **Give sailing a purpose.** Buying and moving a ship should make expansion
   opportunities available and remain strategically meaningful across a match.
3. **Keep the economy understandable.** Each player's existing hand funds their
   construction across locations. Mandatory cargo logistics is not in the charter.
4. **Make maps varied and playable.** Variation includes geography, travel and
   production opportunities, with limits that preserve functioning matches.
5. **Make discovery memorable.** Opening and subsequent mist clearing should be
   beautiful, readable and responsive on the actual phone-scale board.
6. **Provide capable opponents.** Both bot tiers must understand the complete
   rules and make considered naval decisions; old strength claims do not transfer.
7. **Finish the whole experience.** Setup, explanation, interaction, animation,
   accessibility, persistence, replay, complete games and regression evidence all
   belong to completion. Internal milestones do not reduce the finished scope.

## Confirmed commitments

Only human decisions from this conversation belong here. Changing one requires
recording Alex's revised direction and updating its dependent requirements.

| ID | Commitment | Why it matters |
|---|---|---|
| C01 | Ships are purchased and sail independently; they do not need to link into routes. | Creates position and expedition choices. Independent does not mean unlimited movement. |
| C02 | A ship costs two wood, one sheep and two iron. | Fixes the human-specified investment. Delegated D24 maps it to existing lumber/wool/ore without changing quantities. |
| C03 | Geography is randomized per match and can contain multiple islands and peninsulas. | Requires variation beyond one fixed arrangement. Delegated D15–D23 select families, generation limits and fairness constraints. |
| C04 | Fog can be enabled or disabled. With it enabled, outside geography is concealed until within two hexes of a source of vision. | Locks distance and concealment. Delegated D01–D06 settle the opening survey, ship/building sources and traversal. |
| C05 | Discovery is permanent and public for every player. The map starts fogged and mist clears with an impressive animation, including the opening. | Exploration is shared world knowledge and an important visual event. C04's disabled setting takes precedence over concealment. |
| C06 | Optional resource-choice production must be valued appropriately. | Requires desirable flexible output with proper opportunity cost. Delegated D18–D20 settle representation, frequency, entitlement and bank resolution. |
| C07 | Ordinary construction uses each player's hand across locations; a player establishes a settlement on new land before building roads there. | Preserves the economy and settlement-established access. Delegated D07–D08 settle coastal landing, eligibility, island components and continued ship use. |
| C08 | When Ship stealing is enabled, rolling 11 allows the roller to capture any opponent's ship, regardless of distance. Control persists until captured again. Fresh-game default is Off, with an explained Advanced Settings switch. | October 8 revises the earlier unconditional rule; old saved rules remain versioned. D09–D11 retain enabled production/capture order, allowance and identity bookkeeping. |
| C09 | Ship destruction and a Biggest Navy award are absent from the current design. | Preserves the human exclusions. Delegated D12–D13 retain Road/Army awards and settle the remaining score/supply rules. |
| C10 | Traditional and Expert AI are both required, including substantial refinement and evidence. | A legal fallback or an unsupported difficulty is not the finished experience. |
| C11 | Delivery uses an isolated worktree, simulator launch and real gameplay, UI refinement, screenshots and considered edge cases. | Compilation alone cannot establish product quality. |
| C12 | New Game offers Naval in its Rules row beside Standard and Conquest. | Matches Alex's requested setup location and label; selected October 5. |
| C13 | Match Settings selectors move left on one shared axis, provide readable option help from one info button per row, and are screenshot-reviewed before iPhone delivery. | Records Alex's latest layout and delivery request; D34. |
| C14 | New Naval matches allow each ship at most two sea hexes per turn, selecting a highlighted reachable destination and confirming one voyage. | October 7 direction; D47 retains prior saves and public-information boundaries. |
| C15 | Any-resource terrain is painted; harvest explains building entitlement and collection progress; ships use natural language; the current win goal is visible. | October 7 direction; D45, D46 and D48 use existing painted surfaces without extra New Game scrolling. |
| C16 | Accepting a bot proposal gives actual willing, funded recipients an equal chance, with a visible bot-to-bot result. | October 7 direction; D49 records the narrow Accept scope while the optional question remains unanswered. |
| C17 | A rolled seven requires every player with more than seven resource cards to discard half, rounded down; ship theft must be clearly acknowledged when enabled. | October 8 corrects the accidental ten-card Naval limit and the easily missed ownership notice. |
| C18 | Both AI tiers must scout useful reachable terrain rather than remain indefinitely at an unfunded landing. | October 8 requires decision-level reproduction, public-information correctness and complete-match verification. |

The ordinary per-player economy and settlement costs were carried forward in the
conversation. Exact costs, supplies, score target and interactions belong in the
rules review, whose delegated selections are recorded in the design contract;
they are not additional human commitments.
Capture was scoped as transferring the ship, not the victim's established colonies
or hand; D09–D11 make that explicit in the selected rules and acceptance cases.

## Design authority

Alex subsequently delegated the complete design and build while retaining the
human commitments above. The [design contract](design-contract.md) records the
selected map families, versioned sailing, opening survey, first-colony access,
economy, fourteen-point target and both AI strategies. These are delegated design
decisions with recorded alternatives and critique. Quantitative balance conclusions
require the separate generation and policy studies; a chosen rule alone is not evidence.

## How unresolved decisions are settled

Every consequential open question receives alternatives, critique, a recommended
answer, concrete scenarios and evidence proportionate to its consequences. Use
the [decision record](decisions.md#decision-record) rather than choosing the
easiest code path. Group related player-facing decisions for review. Routine
implementation details follow the settled requirements and repository guidance.

A recommendation becomes a decision only when its basis and decision authority
are recorded. Feedback can reopen a decided rule; record the change and affected
requirements. A testable provisional choice may support a design experiment, but
it cannot silently become a release rule. Existing human commitments are not
retuned as a convenience for generation, AI or interface work.

## Stages and completion criteria

### Stage 0 Product foundation

Capture this charter, motivations, definitions, unresolved decisions, scope and
delivery standard in the isolated worktree. Audit the conversation for assumptions.

**Exit:** confirmed commitments have human provenance; recommendations remain
separate; the plan covers both bot tiers and complete product delivery. This
stage records the plan, not a functioning naval game.

### Stage 1 Full match experience and rules

Walk through opening setup, earning ship resources, buying and launching, sailing,
discovery, landing, settlement, roads, continued ship use, capture, late game and
victory. Compare rules for movement, occupation, docking, capture timing, production,
development cards, supplies and scoring. Explain the experience to a new player.

**Deliverables:** complete turn/phase tables, action eligibility and cost rules,
opening-to-ending journeys, rule alternatives with critique, and resolved Stage 1
decisions. Include capture during contested expansion and a match with no ships.

**Exit:** the Stage 1 decisions are resolved in a coherent full-match walkthrough,
with cross-stage dependencies explicitly recorded. Initial visibility and first
settlement access are settled, and ships have a considered purpose after discovery.
Resource-choice and economy outcomes are completed in Stage 2; every rule outcome
must be settled before the implementation readiness review in Stage 5.

### Stage 2 Map design and economy

Draw multiple examples of each candidate family before selecting families.
Examine branches, peninsulas, coastlines, sea approaches, land thickness and legal
settlement capacity. Pair geography with the chosen movement and vision rules.
Define variability, production budgets, starting access, number-token distribution
and bounded generation behavior. Assess fog off and resource-choice off as full
experiences, not degraded test cases.

Critique home expansion versus purchased expeditions, waiting for global capture,
rapid colonization, crowded shores, ordinary productive islands and flexible
production monopolies. Count viable sites and actual sailing routes rather than
only hex totals or distance from the map center. Separate map fairness from
random capture luck. Examine thick interiors outside ship viewing range.

**Deliverables:** selected families and annotated examples; generation constraints
and rejection/repair policy; economy and pace hypotheses; contrasting strategies
and failure cases; a map/settings comparison plan.

**Exit:** selected maps justify expeditions and support complete matches with
either optional feature disabled. Randomness has explicit limits; balance claims
identify their evidence, and unresolved quantitative thresholds remain visible.

### Stage 3 Functional requirements and edge cases

Convert the rules and selected maps into player-observable requirements. Tie each
requirement to a motivation/commitment or a recorded decision, an expected result,
and a verification method. Define option interactions, invalid actions, no-target
states, repeated captures, finite-bank choices, interruptions and game-ending turns.

**Deliverables:** the expanded [acceptance register](acceptance.md), state/decision
tables, fixture catalogue and coverage matrix. Each open outcome points to a
decision rather than an invented default.

**Exit:** every required feature and rule has acceptance scenarios; decision-critical
questions are resolved; requirements describe user behavior without requiring
users to understand the implementation.

### Stage 4 Visual and interaction design

Compare compositions for sea, fog, mist withdrawal, islands, ships, control marks,
movement preview, landing, resource choice and capture. Storyboard early, middle
and crowded late-game positions at real phone sizes. Fit the existing painted
visual identity while developing a distinctive maritime treatment.

Design selection, revision, confirmation, feedback, cancellation, recovery, large
text, VoiceOver and Reduce Motion. Include hot-seat handoff if D14 selects it.
Plan adequately sized action targets, distinguishing neighboring ships and landing
sites from camera pan/pinch, and tap alternatives to dragging. Controls concealed
by overlays leave hit testing and VoiceOver navigation. Treat opening and discovery
animations as sequences, including any intentional brief command holds; screenshots
alone do not show their timing. Preserve the board's stable viewport and readable
controls as its content changes.

**Deliverables:** reviewed visual directions, full interaction storyboards,
animation treatment and accessibility behavior, with critique and revisions.

**Exit:** the complete journey is understandable and attractive at actual scale,
including busy states and non-animated alternatives. There is a recorded visual
direction and no essential interaction left to a coding convenience.

### Stage 5 Architecture and AI strategy

Map approved requirements onto the existing engine, session, policies, persistence
and views. Define ship identity/control, movement bookkeeping, discoveries, pending
decisions, settings and rules versions. Specify deterministic geography and replay,
backward decoding, public observations and cosmetic animation boundaries.

Design both tiers' purchase, voyage, settlement, capture, production-choice, trade,
card and victory reasoning. Separate fair uncertainty from authoritative hidden
world state. Define candidate evaluation without looking at real future randomness.
Choose compatibility for existing modes, Conquest, ghosts, rated games, sync and
encodings through explicit decisions. Include saved policy revision behavior.

**Deliverables:** architecture proposal and critique, transition/persistence
contracts, both AI strategy designs, version/compatibility plan, meaningful test
design and preregistered evaluation criteria.

**Exit:** implementation readiness review accounts for every functional requirement,
information leak, state transition and required integration. No unresolved decision
changes a required legal action or its outcome. Stages 1 through 5 have their
required artifacts; gameplay implementation starts after this review.

### Stage 6 Complete gameplay implementation

Implement the settled engine rules, map generation, configuration, session flow,
events, save/resume, replay and app interactions. Maintain the confirmed ship
price, visibility and capture behavior. Deliver internally in coherent changes
with targeted tests and review; all required features remain on the finish line.

**Deliverables:** a complete integrated naval rules path, meaningful engine/app
tests, deterministic fixture worlds, migration/replay evidence and requirement
traceability. Internal scaffolding cannot be presented as a finished feature.

**Exit:** humans and policy callers can exercise every approved action through the
same rules/session; invalid actions preserve state; resume/replay agree; existing
game behavior remains compatible. AI refinement and visual refinement remain
required in Stages 7 and 8.

### Stage 7 Traditional and Expert completion

Implement and refine both tiers' approved strategies. Inspect decision reasons
and bad games before tuning. Test ship investment against other purchases, travel
choices, competition, recovery after capture, shared discovery, flexible production,
trades, cards and approaching victory. Persist policy revisions appropriately.

Freeze naval-capable anchors before claiming improvement. Predeclare held-out
seeds, complete chair rotations, separate three/four-seat conclusions, opponent
pools, effect size, decisive rate, latency and rejection criteria. Extend the
actual current harness's schema and app-equivalent paths where needed. Existing
Classic results or neutral fallbacks do not establish naval strength.

**Deliverables:** both fully supported policies, decision/failure evidence, bounded
development studies, independent confirmations where warranted, configuration
coverage and responsive app integration.

**Exit:** both tiers deliberately perform the full naval game without leaks or
fallback substitutes; representative games finish; agreed strength/behavior and
latency criteria have evidence. Human experience is still assessed in Stage 8.

### Stage 8 Simulator play and visual refinement

Fresh-install and launch the actual artifact, then play through native UI. Run
complete human/bot scenarios and any hot-seat configurations selected by D14,
discovery races, distant captures,
resource choices and interrupted/resumed games. Observe opening, early expansion,
crowded middle/late game and victory. Refine artwork, mist, ownership changes,
instructions, selection, camera, pacing and accessibility against real play.

**Deliverables:** complete-match records, inspected screenshot sequences and
animation recordings tied to build/seed/configuration, issue/revision history,
accessibility checks and performance evidence on the agreed simulator sizes.

**Exit:** complete user journeys work and look considered across the coverage
matrix, no required state depends on direct fixture seeding alone, and identified
product defects have fixes or explicit release decisions. Simulator evidence is
not described as physical-phone performance.

### Stage 9 Acceptance and integration handoff

Close every acceptance item with exact-build evidence. Run applicable regression,
save/replay and compatibility checks; satisfy the repository gate for the final
tree and avoid duplicating its expensive run at push. Fresh-install the resulting
artifact, establish process survival, inspect visuals and exercise real gameplay.
Review the complete change, update user-facing help and provenance, and prepare
the PR to Jake. Preserve Alex's PR workflow and Jake's committed signing defaults.

**Deliverables:** closed acceptance register, remaining-risk decisions, gate and
native-play receipts, selected screenshots/recordings, complete-match evidence,
final documentation and PR review/handoff. Distribution follows the authorized
release workflow if requested; simulator completion is its own documented result.

**Exit:** the whole agreed mode is complete and reviewable; required AI, visual,
functional and compatibility work has evidence. A green build or a short opening
playthrough cannot substitute for this exit.

## Planning verification and continuation

The initial planning change received conversation-consistency review, local-link
and ID checks, and `git diff --check`. Runtime evidence was added only after the
corresponding engine, app and native interactions ran.

Alex subsequently authorized the complete build with discretionary design work.
The [design contract](design-contract.md) records selected rules, critique and
implementation boundaries after independent product, engine/AI and UI reviews.
The charter is carried through the completed mode. Stages 0–9 and F01–F15 now
have their required local-simulator evidence; human review can reopen specific
decisions or defects without changing the provenance of this delivery.
