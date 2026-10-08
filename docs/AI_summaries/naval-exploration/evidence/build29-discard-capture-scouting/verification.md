# Build 29 verification status

October 8, 2026: [E35](../../acceptance.md#build-29-follow-up-e35) is closed for
Internal delivery. Production/focused source `5851930` and final tested/archive
head `c09e084` retain their exact identities. All 386 [frozen production inputs](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-production-input-manifest.json)
match. The retained diagnostics below keep their original scopes and verdicts;
final-gate/runtime/delivery evidence is recorded separately.

| Actual retained command | Exit / scope | Attribution |
|---|---|---|
| [Seven proof](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/seven/proof.json) | Red 1; scoped green 0 (44 functions); full helper Engine 0 (413 functions). | Seven helper `d1720df`; actual natural roll, not a preseeded discard phase. |
| [Capture proof](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/capture/proof.md) | Disabled-11 red; engine green 0 (41 functions); helper Debug compile 0. | Capture helper and subsequent native refinements retain their individual source IDs. Compile is not gameplay. |
| [Return red](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/ai-final/return-red2-receipt.json) | 1; both frozen 47/77 committed sequences reward the idle return. | Before origin-history correction. Initial 96-case completion is insufficient acceptance. |
| [Return edge green](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/ai-final/return-edge-green-receipt.json) | 0; 15 AI functions / two suites. | Exact sequences, useful funded return and actual winning colony. |
| [Broader AI helper](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/ai-final/history-final-ai-tests-receipt.json) | 0; 74 functions / nine suites. | Corrected history helper `dba284a`; includes Naval, revisions and seeded fingerprints. |
| [Broader Engine helper](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/ai-final/history-final-engine-tests-receipt.json) | 0; 142 functions / 23 suites. | Naval, save compatibility, rule-version replay and session checkpoints. |
| [Masked return test](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/ai-final/history-masked-tests-receipt.json) | 0. | Concealed-world/rival-hand/deck/RNG variants cannot change return decisions. |
| [final focused native command](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-naval-acceptance-command.json) / [native summary](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-naval-summary.json) | 0; 61 functions/101 runs, zero failures/skips. | Unchanged root `5851930`; actual hosted/app/UI tests on reused QA, no new devices. |
| [corrected functional summary](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/ai-final/corrected/summary.json) / [independent readback](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/ai-final/corrected/independent-matrix-readback.json) | 96 winners, six byte-exact separate-process repeats, ten complete transition checks; all commands exit 0. | Frozen root `5851930`, V5/scoutingV2; all 1,302 package/113 production files and Release binary hash match. Functional evidence only. |
| [App-brain static checks](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/naval-brain-draft/static-proof.json) | Strict lint, syntax parse, XcodeGen and diff 0. | `452d16e`; hosted compilation later caught a mutating call inside a test macro, fixed by `b9c87e9`. Static parse is not hosted execution. |

## Final focused native and original review

The actual command at `5851930` preserves all 14 devices and uses one reused
owned QA device. A nonzero human seat rolls seven with eight resources plus
Knight, selects/minimizes, cold resumes with a blank draft, then submits four
resources back to the bank before the original roller's robber decision. Both
ordinary and maximum-text flows pass. Loss/gain, swipe-dismiss rejection, blocked
board/Settings, cold resume, saved Continue and a committed two-hex voyage pass.
Actual settlement/city harvests still use the shared cover. Hosted revision,
rulebook, receipt/save-failure and legacy compatibility cases pass.

Root approves eight unchanged originals in the [attachment manifest](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-naval-attachments/manifest.json):
`10782D98` settings/default-Off; `C6F92C17` loss; `1CFE5466`/`29DA07DA` maximum
text; `6088F388` rolled-seven discard; `70A56885` maximum discard; `4D2A5F82`
gain; `647E7CB6` acknowledgement→two-hex voyage. This is simulator evidence;
manual VoiceOver, physical-phone gameplay and full-gate verdicts remain separate.

## Corrected functional and replay proof

All 96 family/tier/table-size/fog/wild/stealing cells reach a winner at 14 or
more points: 60,007 actions, 320 bought hulls, 3,403 sailed hexes and 608 colonies.
No forced ends, idle sailing/trade cycles, duplicate proposals or disabled
captures occur. There are 15 raw revisits; zero idle revisits does not mean ships
never revisit water. Both formerly failing 47/77 cells now have zero raw/idle
sailing cycles. Six fresh processes match entire result/trace/audit bytes.

Ten full inspections check 6,126 replay/conservation/fog transitions, 14,280
legal sea routes, 4,877 explicit rival destination blocks, 172 cold checkpoints
and 118 sevens/63 discard obligations. No inspected End turn ignores a
positively scored voyage. The six periodically restored traces match the harness
exactly. Both shipped V4/V1 original-stall trajectories retain exact old bytes
and never populate new sailing history.

The independent readback hashes all 1,302 package inputs and 113 production
inputs against the frozen manifest, checks the actual Release executable hash,
all case provenance/results and each repeat/legacy trace's actual bytes. Bound
package digest is `0828ff28351571a3753e3eeb76c6628912c1fa02ea703749f49e3acafd33956a`;
production digest `30a8ca0aeff943b6147a038d33086e68a194858bd2511b024d4dff2b09f096be`;
executable `5f69d47d34fccb2ac18c442a4a6e4298cd42722764ab68fcb335498e5ebe70b2`.
These are functional checks, not an improved-strength estimate.

## First full gate and fixture correction

The [actual push/hook command](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-attempt1-prepush-command.json)
at `416a0c6dd9d466ff7802795337cc51dc8cac18a6` exits 1; the [gate log](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-attempt1-prepush-gate.log)
and [native summary](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-attempt1-native-summary.json)
retain the failed verdict: 805 functions/1,610 runs passed, four functions/nine
runs failed, one existing compact-device skip. No upload followed. All nine
failed runs are in NavalBlockadePresentationTests: six stale version assertions,
one stale equality assertion after real discovery, and two invalid synthetic
saved states rejected by the strict validator. [Diagnosis](diagnosis.md#first-full-gate-stale-blockade-fixtures)
links the exact failure values and crash evidence.

Test-only correction `c4d0bee60b8b0516a69648c4275815ede95d4445` updates these
fixtures and asserts validation before saving; production/package files remain
unchanged. Its [first focused command](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/blockade-v5-fixture-correction-command.json)
exits 65 at the same unchanged source; the [compile log](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/blockade-v5-fixture-correction.log)
shows a nested throwing `#require` on the right of `&&` inside `#expect`.
No tests ran in that attempt. A separate [retry command](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/blockade-v5-fixture-correction-retry-command.json)
at unchanged `c09e084528b7cdcb6cef02653adddb11294c5a90` exits 0; its [summary](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/blockade-v5-fixture-correction-retry-summary.json)
passes all seven affected functions/12 runs, zero failures/skips. This is the
complete affected suite, not a full-gate verdict. Earlier failures remain failed,
regardless of the replacement gate's result.

## Final gate, runtime and Internal delivery

[normal push/full-gate receipt](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-prepush-command.json) passes all ten mandatory stages; the optional standalone Debug build is explicitly skipped, while native Debug app/UI did run at tested `c09e084`.
[full-gate native summary](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-attempt2-native-summary.json) reports 809 functions/1,619 runs passed, zero failures and one existing 375×667 destination skip; [final original-image review](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-gate-originals-review.json)
records complete native play and original-image approval. [independent static review](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/independent-code-review.json)
reports no P1/P2 findings. [ordinary Release runtime](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/release-runtime.json) records ordinary fresh Release,
no QA arguments, surviving six seconds without a new own crash and approved original menu.
The [Release executable origin](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/release-binary-origin.json) retains a cached compilation at `416a0c6` with all
386 production inputs unchanged, revalidated by the `c09e084` gate. That gate
did not recompile the executable. [archive visual approval](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/root-archive-visual-go.json) approves the ordinary
menu and 12 unchanged final native originals; the [final screenshot gallery](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-reviewed-screenshots.md)
includes actual Traditional/Expert winners and final replay exploration.

[uploaded payload comparison](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/uploaded-payload-comparison.json) verifies actual uploaded signed bytes, accepted checksum/UUID
and [Apple/Internal access](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/testflight.json): exact 1.0/29 VALID/unexpired, internally IN_BETA_TESTING,
Alex's access at `2026-10-08T08:35:27.164Z`. [owned simulator cleanup](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/simulator-finish.json) verifies individual
owned cleanup. [PR #63](https://github.com/jakebeinart1/Settlers/pull/63) identifies the integration;
[final integration proof](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-merge-source-proof.json) owns final PR disposition and source equivalence
after integration. The tested/archive
head stays `c09e084` through later source-equivalent documentation updates.

[Archive](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/archive-command-receipt.json),
[export](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/export-command-receipt.json)
and [actual upload](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/upload-command-receipt.json)
all exit 0 at frozen `c09e084`. [Strict staged-payload signing](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/uploaded-payload-signature.json)
uses the existing profile/certificate and CloudKit Production. The actual upload
is 37,472,832 bytes, SHA256
`172ce1698918cff776be8b4e8aa118afabfa005eca7d475d9c900776e1df404c`,
MD5 `d4ae6dd918f26c5137321e8605e7a355`. The signed review export differs only
within the code signature; the staged payload's exact asset checksum and accepted
UUID match. The [actual ASC record](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/asc-build29.json)
confirms build `980b2f6c-fae9-4e1f-a858-f14287baeee5`, VALID/unexpired and
internally IN_BETA_TESTING, with Alex's membership and all-build access confirmed.
No physical installation/play or external release was observed.

[Executed owned compiler/cache cleanup](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/storage-cleanup/compiler-cleanup-execution.json)
removes eleven exact owned paths, about 1.31 GiB allocated at planning. Every
non-cache file/link was byte-identical before/after cleanup; Products, standalone
binaries, screenshots, xcresults, payloads and receipts are preserved.

Earlier failures remain retained; helper/focused counts are not substituted for
final-gate counts. Earlier build28 delivery remains historical. No comparative
strength, physical-iPhone install/play, external release or manual VoiceOver claim.
