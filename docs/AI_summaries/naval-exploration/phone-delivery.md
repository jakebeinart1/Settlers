# Naval phone delivery

## Build 25 delivered

Production is frozen at `a9e0e88`, 1.0/build 25, with 376 inputs; test-only
`cffe613` passes/publishes the replacement full gate, all ten mandatory stages.
[E30](acceptance.md#build-25-follow-up-e30-delivered) retains the failed first
gate and correction. All 112 package inputs match build 24 exactly. Fresh ordinary
Release survives six seconds without QA arguments or new own crashes; root
approves 26 final-gate Debug originals plus the ordinary Release menu.

[Archive](evidence/receipts/build25-archive-command-receipt.json) and
[export](evidence/receipts/build25-export-command-receipt.json) exit 0, with
strict [review-export signing](evidence/receipts/build25-signed-export.json).
[Upload](evidence/receipts/build25-upload-command-receipt.json) exits 0 and
preserves the actual [signed payload](evidence/receipts/build25-uploaded-payload-signature.json):
SHA256 `5b020ca35ac4dfed60fc4a428ce241e282ff47f8c8e47252cbbf23dba5926691`,
36,308,759 bytes; MD5 `8443b7a3de5668f16c46a99f243568d0`.
The [comparison](evidence/receipts/build25-uploaded-payload-comparison.json)
checks all 14 ZIP entries, only executable signature differs from the review
export, with 5,874,672 identical prefix bytes. ContentDelivery confirms MD5 three
times and accepts UUID `409a8bbf-4931-4a9b-b70d-da2c8bbc4860`.

Fresh [Apple readback](evidence/receipts/build25-testflight.json) at
17:57:29.535 UTC confirms the same exact UUID, marketing 1.0/build 25,
VALID/unexpired until January 5, 2027, internal IN_BETA_TESTING. Alex's exact
tester ID has access through Internal's all-build group. External state is
READY_FOR_BETA_SUBMISSION; no external release or physical-device install/play
is recorded.

[Owned QA cleanup](evidence/receipts/build25-simulator-cleanup.json) exits 0,
readback Shutdown at 17:59:07 UTC, only device `937692FF-BFBF-4683-80E5-2590F5288D56`.
All 14 devices remain; Ferrule/Switchbard's Booted states are untouched. All
376 production inputs still match. [Tested-head CI](evidence/receipts/build25-tested-head-github-ci.json)
passes; later metadata CI is separate. PR #60 remains unmerged, awaiting approval.
The [independent final audit](evidence/receipts/build25-final-independent-release-audit.json)
passes with no blockers, binding the fresh Apple readback, both signed payloads,
accepted checksum/UUID, original gallery and cleanup. E30 is complete for internal
delivery; build 24's exact historical facts remain below.

## Build 24 delivered

**October 7: Empires 1.0/build 24 is available to Alex in internal TestFlight.**
Apple build `9b3882ef-a85c-46c2-8d1a-2d83f5483aef` is VALID, unexpired and
internally IN_BETA_TESTING. Alex Chandler belongs to Internal with access to all
builds, confirmed by the [Apple/access receipt](evidence/receipts/build24-testflight.json)
at 13:06:46 UTC (9:06:46 a.m. EDT) and independently at 13:06:40 UTC in the
[final release audit](evidence/receipts/build24-final-independent-release-audit.json).
The audit passes, binding 376 production inputs, 303 matrix hashes, 23 original
capture hashes, ordinary Release runtime and actual uploaded payload/signature/
checksum/access. External state is READY_FOR_BETA_SUBMISSION; external build 24
is unreleased. Physical-phone installation/play, hardware timing, manual
VoiceOver and new AI strength remain unobserved. Open TestFlight → Empires →
Update. New Naval matches use two-hex voyages; v1/v2 saves retain their rules.

D45–D49 implement painted harvest/derived progress, natural ship language,
visible goals, accepted-bot-offer competition and Naval v3 destination voyages.
Production source is `9bce5f77a38684bd6e011fac8838c74b38440798`; tested/archive
head `67efbad` differs only in two test corrections. All
[376 production inputs](evidence/receipts/build24-final-production-inputs.json)
and 112 package files match the freeze. Naval is integrated above main `83d8525`,
retaining its resource-square/Skip/Block/leaderboard/ghost-rename fixes. Jake's
committed signing defaults remain unchanged.

The first full pre-push gate failed two obsolete test oracles, retaining Git exit
141/no published push. Test-only correction passes three functions/eight runs.
The [final gate](evidence/receipts/build24-final-prepush-command.json) passes all
ten mandatory stages, session `91604`, exit 0, and publishes `67efbad`. App/UI
has 754 functions: 753 pass, zero failures, one size-specific skip, 1,512 passing
runs; hosted 581/82, Engine 391/31 and AI 308/31 pass, coverage 96.78%/96.05%.
Optional separate Debug app build skips; native tests built Debug. The sole
375×667 footer case skips on 402×874 QA; no current compact execution is claimed.
E29 retains all earlier failures and exact three-ID/live ≥7:1 contrast guards.

Fresh [v3 evidence](evidence/receipts/build24-v3-summary.json) passes 48 matches
and six complete-byte result/trace repeats. There are no forced ends, idle
sailing/trade cycles or duplicate proposals; two raw revisits are productive.
Independent reveal reconstruction covers only two retained fog-off checkpoints,
with engine/source fog tests separate. These are functional results, not strength.

The [ordinary Release receipt](evidence/receipts/build24-release-runtime.json)
passes fresh 1.0/24 install without QA arguments, PID `93934` surviving six
seconds, no new own crashes and root-inspected menu. Executable SHA256 is
`33d7746154466774d4359d897e8727710515f8ba11afd595660fca25329c010b`.
Root approves all [23 final originals](evidence/screenshots/build24-final-manifest.json):
22 Debug attachments and its ordinary Release menu, with three informational
caption crops. Exact source/test/time/configuration and unchanged hashes remain;
Release capture time was unrecorded, so verification/inspection times stay
separate. Simulator/native media and signed device payload retain attribution.

The [archive/export receipt](evidence/receipts/build24-archive-command-receipt.json),
[archive log](evidence/receipts/build24-archive.log),
[export log](evidence/receipts/build24-export.log),
[upload receipt](evidence/receipts/build24-upload-command-receipt.json) and
[upload log](evidence/receipts/build24-upload.log) pass at exit 0. Both
[review export](evidence/receipts/build24-signed-export.json) and
[actual uploaded payload](evidence/receipts/build24-uploaded-payload-signature.json)
pass strict/deep App Store/Production signature checks: beta reports active,
get-task-allow false, no provisioned devices and correct Production CloudKit.

| Payload | Size | SHA256 |
|---|---|---|
| Actual preserved uploaded IPA | 36,268,869 bytes | `0ef24d00609c2f2830448ddcdf817d167a0673d060442631c31d1e4e3f87becc` |
| Review export | 36,268,871 bytes | `f899e4d02bc252a70eb6d675ba51741328c0d2fdf501786958769abdaef06770` |

The [comparison](evidence/receipts/build24-uploaded-payload-comparison.json)
checks 14 ZIP members; only designated executable signature bytes differ, with
its first 5,855,808 bytes identical. Actual upload MD5
`dfcd6ece91320bbe705a2ce46c26bd0a` matches three ContentDelivery checksum records
and delivery ID `9b3882ef-a85c-46c2-8d1a-2d83f5483aef`, matching Apple's build.

The [cleanup receipt](evidence/receipts/build24-simulator-cleanup.json) verifies
QA `937692FF` alone is shut down at 13:07:05 UTC; no device is created/deleted.
Ferrule Dice Review and Switchbard Small Owner Review 2a7e remain booted and
untouched. Three implementation helpers are recoverably archived; both root
checkouts/durable artifacts remain. All 376 inputs still match after delivery.

[E29](acceptance.md#build-24-follow-up-e29-delivered) is complete for internal
delivery. [PR #60](https://github.com/jakebeinart1/Settlers/pull/60) is attached
and awaits at least one actual approval; no merge is recorded. Tested `67efbad`
passes required Linux/SwiftLint [CI](evidence/receipts/build24-tested-head-github-ci.json),
[run 37624311095](https://github.com/jakebeinart1/Settlers/actions/runs/37624311095).
Workflow-dispatch-only project drift skips; local drift passes. Main remains
`83d8525` at this snapshot. Build 23/22 records below preserve their attribution.

## Build 23 delivered

**October 7: Empires 1.0/build 23 is available to Alex in internal TestFlight.**
At 08:16:30 UTC (4:16:30 a.m. EDT), Apple build
`cfcb926b-7b11-4178-9d19-8df7a9e5e597` is VALID, unexpired and internally
IN_BETA_TESTING. Alex Chandler is a member of Internal with access to all builds,
confirmed in the [processing/access receipt](evidence/receipts/build23-testflight.json).
The [independent readback](evidence/receipts/build23-testflight-independent.json)
confirms the same build/state/access at 08:18:25 UTC (4:18:25 a.m. EDT).
The [final release audit](evidence/receipts/build23-final-release-audit.json)
passes at 08:21:23 UTC with no blocking defects, binding source, current tests,
uploaded payload/checksum, signing, media and intended access.
External status is READY_FOR_BETA_SUBMISSION; external build 23 is not released.
Physical-phone installation/play and hardware timing remain unobserved.

Alex's October 7 follow-up adds clearer Ready/Unavailable construction with
exact held/cost shortages, eight painted controller fleets without castle
overlays, and separate Skip/Retry versus incoming-trade answer targets (D42–D44).
The work remains on the integrated Naval branch with build 22's gameplay,
compatibility and Expert-card revision retained. Source is frozen at
`1dfae7cb8e46ca4b343c0415fef18e71cd3a6ed4`; `project.yml` names 1.0/build 23.
The [371-input binding](evidence/receipts/build23-final-production-inputs.json)
matches app/package/configuration/assets to that production source.

[E28](acceptance.md#build-23-follow-up-e28-delivered) records the legal
stale-touch failure and targeted Build/trade/artwork passes. The fourth combined
command failed its two new artwork assertions despite passing the eleven other
UI journeys; the corrected artwork follow-up then passed. The strengthened
maximum-zoom guard passes with the ship visibly contained after real drags.
The [visual record](evidence/visual-review.md#build-23-final-source-gallery-local-review-verified)
keeps those development Debug captures separate from final release media.
Compact Ready/scarce paint is root-inspected, and real purchases/sailing prove
mixed-controller stack choices. The compact scrolling-test failure and corrected
rerun remain separate from production defects.

The [complete gate log](evidence/receipts/build23-full-gate.log) and
[exit receipt](evidence/receipts/build23-full-gate-exit.json) pass all eleven
stages at `1dfae7c`, exit 0: Engine 371/28, AI 303/30, hosted 565/80, coverage
96.67%/96.01%, Release/Debug compile. The
[app/UI summary](evidence/receipts/build23-full-gate-native-summary.json) reports
732 functions, 731 passed, zero failures, one size-specific skip; 1,477 runs:
1,476 passed and one skipped. The 375×667 footer skip on regular QA passes
independently on compact.
All [111 engine/AI package inputs](evidence/receipts/build23-engine-ai-source-equivalence.json)
match build 22; its 48-match/six-repeat functional evidence is reused without
running new games or making a new strength claim.

The [final manifest](evidence/screenshots/build23-final-manifest.json) binds
seventeen unmodified, root-inspected images to source `1dfae7c`, version 1.0/23,
including all eight local fleets, Build/trade/World-stack/chooser/zoom-nine proof
and the ordinary Release menu. Debug native captures and the Release menu retain
separate configuration identities.

The [ordinary Release receipt](evidence/receipts/build23-release-runtime.json)
records fresh 1.0/23 installation, no QA arguments, PID 54344 surviving six
seconds, no new own crash reports and root-inspected menu. Its simulator executable
SHA256 is `2dc38e9d20c221a104cd6400e0eaceec03af2a9bdfb579e9a746c332b129250d`.

The [archive/export receipt](evidence/receipts/build23-archive-command-receipt.json),
[archive log](evidence/receipts/build23-archive.log) and
[export log](evidence/receipts/build23-export.log)
record both commands exiting zero at production/archive source `1dfae7c`, with
all 371 inputs frozen and Jake's committed signing defaults unchanged. Manual
Alex signing retains certificate `76465B06C2E157D857641F5B3D25CF5A3110C4A9` and
profile `86da5771-8640-4c53-8867-0b4fbd4f1035` (“Empires App Store 20261004”).
The [local review export](evidence/receipts/build23-signed-export.json) passes
strict/deep signature verification, beta reports enabled, debugger access false,
no device list and Production `iCloud.com.alexchandler.empires` entitlement.
Review IPA SHA256 is `fce46b79f06b0ab7b292bce81168269880eb8766e7b42d980959476898c550b0`,
33,718,519 bytes; executable SHA256 is
`f54dd716d5bf3c4ca78d58d42d5f9403fc81535c402fa6b0bbd1c7d3a297f280`.

The separately preserved upload payload is
[Settlers-uploaded-23.ipa](/Users/alex/.codex/artifacts/naval-exploration/build23-sprites-build-trade-safety/Settlers-uploaded-23.ipa),
SHA256 `2707f35bbfd8c3a374773d77defc6fee4c8a4b83291efe8c07c278e93b9c8aa1`,
33,718,518 bytes, MD5 `55379f183a2e383be69b7af12805c56e`. Its
[signature receipt](evidence/receipts/build23-uploaded-payload-signature.json)
records executable SHA256
`22f645e0bbe2530ce712dc29ed4f103e6dd934aba244ef373f17ba51e1918c47`
and passing strict/deep verification with the same profile/certificate and
Production entitlements. The [upload receipt](evidence/receipts/build23-upload-command-receipt.json)
and [log](evidence/receipts/build23-upload.log) record exit zero, complete ZIP CRC
validation and preservation of the actual staged bytes.

The [independent payload comparison](evidence/receipts/build23-uploaded-payload-comparison.json)
finds fourteen ZIP members matching except the executable's code signature;
all 5,771,184 executable bytes before that signature are identical. Accepted
ContentDelivery MD5 is `55379F183A2E383BE69B7AF12805C56E`, independently confirmed
at three occurrences in the owned delivery log. ContentDelivery ID
`cfcb926b-7b11-4178-9d19-8df7a9e5e597` matches Apple's exact build ID. Upload
re-exports/re-signs, so the review export and actual uploaded IPA retain distinct
bytes and hashes.

The [simulator cleanup receipt](evidence/receipts/build23-simulator-cleanup.json)
records reused QA `937692FF` shut down, zero release-created/deleted devices and
other projects' devices untouched. The earlier compact device alone was deleted
after preservation in its [separate cleanup](evidence/receipts/build23-compact-cleanup.json).
Both helpers are [recoverably archived](evidence/receipts/build23-helper-worktree-cleanup.json);
root Naval and durable evidence remain. All 371 production inputs still match
the freeze after delivery. Build 22/21 below retain their historical source,
signed payload and access attribution.

## Build 22 delivered

**October 7: Empires version 1.0/build 22 is available to Alex in internal
TestFlight.** At 12:59 a.m. EDT, Apple build
`45c00f05-28b4-42de-93f6-016e4ed8e67a` is VALID, unexpired and internally
IN_BETA_TESTING. Alex Chandler belongs to Internal with access to all builds.
The [processing/access receipt](evidence/receipts/build22-testflight.json),
[independent read-back](evidence/receipts/build22-testflight-independent.json)
and [final release audit](evidence/receipts/build22-final-release-audit.json)
confirm the exact build and intended tester access. External status is
READY_FOR_BETA_SUBMISSION; external build 22 is not released. Physical-phone
installation and hardware play have not been observed.

Current source `1cf1c0f` makes known home harbors visible through mist and restores
the exact preceding camera through World → Return, including fitted zoom one.
It retains inland home placement, the Expert card revision and recorded move
effects. Strict compatibility refreshes older queued trade observations without
resampling their replies. [E27](acceptance.md#build-22-follow-up-e27-delivered)
records the passing complete gate, earlier targeted corrections and 48-match
functional checks.

The [complete gate](evidence/receipts/build22-full-gate-summary.json) passes all
eleven stages at `1cf1c0f`, exit 0: Engine 371/28, AI 303/30, coverage
96.72%/96.01%, app/UI 704 functions (703 passed, zero failed, one size-specific
skip), 1,433 passing runs. The natural-seven cold resume and all nine harbor/
navigation functions pass, including the fitted Return guard. The footer skip
requires 375×667 points; the tested device is 402×874.

The [ordinary Release receipt](evidence/receipts/build22-release-runtime.json)
records a fresh 1.0/build 22 install with no QA arguments, surviving PID 46232
after four seconds and no new own crash reports. The
[final gallery](evidence/visual-review.md#build-22-final-source-gallery-local-review-verified)
contains five root-inspected current-source Debug images plus the inspected
Release main menu. The two earlier intermediate images remain separately labelled.
All [111 package files](evidence/receipts/build22-final-package-source-binding.json)
and [349 production inputs](evidence/receipts/build22-final-production-inputs.json)
match the frozen production source.

### Build 22 signed and uploaded artifacts

The [archive/export command receipt](evidence/receipts/build22-archive-command-receipt.json),
[archive log](evidence/receipts/build22-archive.log),
[export log](evidence/receipts/build22-export.log) and
[upload receipt](evidence/receipts/build22-upload-command-receipt.json)/
[log](evidence/receipts/build22-upload.log) record exit 0. Production and archive
source are `1cf1c0f`; only documentation was uncommitted at archive, and all
349 tracked production inputs match that source. Jake's committed signing defaults
stay unchanged. Manual signing reuses certificate
`76465B06C2E157D857641F5B3D25CF5A3110C4A9` and profile
`86da5771-8640-4c53-8867-0b4fbd4f1035` (“Empires App Store 20261004”).

The actual [Settlers-uploaded-22.ipa](/Users/alex/.codex/artifacts/naval-exploration/build22-harbors-navigation/Settlers-uploaded-22.ipa)
is preserved independently of the local review export. Its
[signature/payload receipt](evidence/receipts/build22-uploaded-payload-signature.json)
records:

- Uploaded IPA SHA256: `9f062568af41cf1533d558e78fc5aaee90f673afa20085f3e701aee166e02db6`; 24,907,514 bytes.
- Uploaded executable SHA256: `e9a66939d0edccdcb7311be0c9556e198dec45e791fc080cf74579b905b8dfb1`.
- Accepted ContentDelivery MD5: `E06897305D3A2B3F1C6ED0253A24337E`, independently confirmed at three occurrences in the owned delivery log.

The [review export](evidence/receipts/build22-signed-export.json) has IPA SHA256
`a5c84dba786deb498393875b9242ca99a95a64399f56c8c89de0e5ed7181d01f`,
24,907,517 bytes and executable
`56926cdcd17ceb880dbfb053db03b886914a77590f9fb5cd1c18543d11b7853d`.
The [independent payload comparison](evidence/receipts/build22-uploaded-payload-comparison.json)
finds fourteen ZIP members matching except the executable's code signature;
all 5,704,080 executable bytes before that signature are identical. Upload
re-exports and re-signs; these are distinct signed IPA bytes.

Both payloads pass strict/deep signature verification. Beta reports are enabled,
debugger access is false, no provisioned-device list exists and signed CloudKit
uses Production with `iCloud.com.alexchandler.empires`. The
[final audit](evidence/receipts/build22-final-release-audit.json) confirms no
unresolved release blocker, with physical installation/play and new AI strength
remaining outside the observed evidence. Debug captures and the simulator
executable retain their own identities.

The [simulator retirement receipt](evidence/receipts/build22-simulator-cleanup.json)
records reused QA `937692FF` shut down after verification, zero task-created
devices/clones/deletions and other devices untouched. Both helper worktrees were
[recoverably archived](evidence/receipts/build22-helper-worktree-cleanup.json);
root Naval and durable AI/release artifacts remain retained. Build 21's earlier
delivery below keeps its original source and artifact attribution.

## Build 21 delivered

**October 6: Empires version 1.0/build 21 is available to Alex in internal
TestFlight.** Apple build `23440fef-103a-4c7b-8896-a0164c7bab74` is VALID,
unexpired and internally IN_BETA_TESTING. Alex Chandler belongs to Internal,
which has `hasAccessToAllBuilds=true`. The [processing/access receipt](evidence/receipts/build21-testflight.json)
and independent read-back confirm availability at 8:38 p.m. in Alex's timezone.
External status is READY_FOR_BETA_SUBMISSION; external build 21 is not released.
Physical-phone installation and hardware play have not been observed.

Production source `60394e6361b2db372311920c4cc9ae481e5dec0f`, archived at docs-only
head `d56581de31e9569ee7b7dc1319213eba4fdec942`, restores ordinary inland
home-island settlements. Ships constrain founding without a road to the exact
accessible coastal corner; established islands still expand inland through owned
roads. Distance, resource costs and saved Naval v1/v2 vision remain intact.

Alex's earlier October 6 phone screenshot showed Standard/Conquest in build 20.
That independent Expert-card release came from `16f6afd`, whose rules row and
engine contain no Naval mode. Build 21 combines that retained card revision with
Naval, including the inland correction. The full passing gate's
[Rules selector](/Users/alex/.codex/artifacts/naval-exploration/build21-final/gate-attachments/FC0CBE2C-E184-46B6-BFC6-8772838A486E.png)
shows Standard, Conquest and Naval. The image remains simulator evidence.

### Signed and uploaded artifacts

The original-project [archive](evidence/receipts/build21-archive.log),
[export](evidence/receipts/build21-export.log) and
[upload](evidence/receipts/build21-upload.log) each exit 0. Manual signing uses the
same existing certificate `76465B06C2E157D857641F5B3D25CF5A3110C4A9` and
“Empires App Store 20261004” profile UUID `86da5771-8640-4c53-8867-0b4fbd4f1035`.
Strict/deep signatures pass; beta reports are enabled, debugger access is false,
no provisioned-device list exists, and signed CloudKit uses Production with
`iCloud.com.alexchandler.empires`.

The actual uploaded IPA is preserved as
[Settlers-uploaded-21.ipa](/Users/alex/.codex/artifacts/naval-exploration/build21-final/Settlers-uploaded-21.ipa).
Its [payload receipt](evidence/receipts/build21-uploaded-payload.json) records:

- Uploaded IPA SHA256: `1f1d7319d182daf74783f1412cce3e2ad8d89517706ccaac8cd13f1853c83202`; 24,887,137 bytes.
- Uploaded executable SHA256: `5d0c0af2a7547051b5fc3fedec63bf1f1d1e66a0437c9f0238fabf1bbbeba270`.
- Accepted ContentDelivery MD5: `52f1ecc02a294a79a82faa6c0b47f010`.

The separate [review-export receipt](evidence/receipts/build21-signed-export.json)
records IPA `a1a1b182cb3db195146ee5e1ffe5678b9e59531d6c44f13fc7f837743d5ef25c`
and executable `ae8a30aab990fa7a1cb59fa550a9ebf877a3dd171f403fc8158354a4c44b96bd`.
Upload re-exports and re-signs; these are not identical IPA bytes. Independent
comparison finds fourteen matching ZIP members except the executable's signature.
All 5,687,504 bytes before that signature and every other member are identical.
Both actual uploaded payload and local export pass signature/profile/Production
checks. The [durable artifact bundle](/Users/alex/.codex/artifacts/naval-exploration/build21-final)
retains source-bound results, both artifacts and delivery evidence.

### Verification

The [full gate](evidence/receipts/build21-full-gate.log),
[summary](evidence/receipts/build21-full-gate-summary.json) and
[valid result](/Users/alex/.codex/artifacts/naval-exploration/build21-final/full-gate.xcresult)
pass all eleven stages, exit 0: Engine 365 functions/26 suites, AI 303/30,
coverage 96.63%/96.01%, Release/Debug builds and app/UI 694 functions (692 passed,
zero failed, two skipped), 1,419 passing runs. Existing skips are the natural-seven
trajectory without a human obligation and the trade-footer test requiring 375×667
points rather than the 402×874 QA destination.

The initial interrupted result lacked Info.plist and supplies no complete verdict.
Audit found completed-checkpoint restoration could enqueue a real trainer before
a test replaced it. Injection before restoration, isolated stores and completion
awaits repair the test isolation; production still uses real ghost learning. The
[49-function focused check](evidence/receipts/build21-ghost-isolation-summary.json)
passes, followed by the full gate including all six GhostTrainerTests. No timeout
was raised or new skip introduced.

The ordinary Release artifact was freshly installed on reused QA simulator
`937692FF-BFBF-4683-80E5-2590F5288D56`. PID 59749 survived without QA arguments,
and root opened its main menu. The [runtime receipt](evidence/receipts/build21-release-runtime.json)
records executable `b3c0f45c26ed40364ccb17c2286c47fed11289248e7e9bab78b3ac88e52ba324`.
The [final gallery](evidence/visual-review.md#build-21-inland-settlement-gallery-delivered)
and [manifest](evidence/screenshots/build21-final-manifest.json) attribute final
native Debug captures and ordinary Release media separately from signed device
artifacts. Earlier `8a394132` captures remain historical.

[Naval functional evidence](evidence/receipts/build21-naval-functional-compact-receipt.json)
records 48/48 completed matches, 28,743 actions and six byte-identical
separate-process repeats. All 111 recorded engine/AI hashes match the release
source, and the retained Release CLI digest matches provenance. These functional
checks make no new strength claim.

### Historical signing failures and observed recovery

The [initial archive](evidence/receipts/build21-archive-signing-failed.log) and
[explicit-login-keychain retry](evidence/receipts/build21-archive-keychain-failed.log)
failed at CodeSign with `errSecInternalComponent`. Read-only checks then proved
unlocked/readable/writable status (bits 7), UID 501/Aqua context, an associated
private key and already unrestricted GUI access. The generic unlock request was
unsupported. Local code-signing certificate trust passed; old/new profiles and
signing entitlements matched exactly. Securityd reported `CSSMERR_CSP_INVALID_DATA`.

Native Xcode Product Archive independently failed at CodeSign after 66.3 seconds.
Its [report](evidence/receipts/build21-native-xcode-signing-failed.log) and
[source/configuration receipt](evidence/receipts/build21-native-xcode-signing-failed.json)
preserve the failure. The artifact-only XcodeGen project referenced the same
149 source/two resource inputs, byte-identical Info.plist and existing manual
identity/profile. Original production/project files and the local override were
restored intact. GUI reproduction excluded a CLI-only explanation; the prior
Terminal discriminator was superseded without Terminal automation.

Alex then performed the targeted local lock/unlock authentication refresh.
The same signing probe succeeded immediately; the original manual CLI archive,
export and upload subsequently passed. This is observed recovery after refresh,
not proof of the macOS failure's underlying cause. No password was supplied in
chat, and no certificate recreation, keychain reset/deletion, trust alteration
or key-access broadening was performed.

### Simulator lifecycle

This task created no simulator or certificate. Two confirmed disposable
simulators were deleted after verified save backups, reclaiming about 5 GB;
[the retirement receipt](evidence/receipts/build21-simulator-retirement.json)
records each archive. The run/play/verify/ship skills in both checkouts retain
host inventory, owned-device reuse, pinned QA, one serial worker and individual
cleanup. The [post-verification inventory](/Users/alex/.codex/artifacts/naval-exploration/build21-final/simulators-after-verification.json)
records 13 devices and zero booted; reused QA and existing review devices are
shut down. Other projects' devices were not stopped or deleted. Jake's committed
signing defaults remain unchanged.

After delivery, only the task's native Xcode project was closed. Its
workspace-identified temporary cache was removed after verifying the preserved
failure-log hash: 283,072,424 logical bytes. The signed archive, review export and
exact uploaded IPA remain retained. The [cleanup receipt](evidence/receipts/build21-native-cache-cleanup.json)
records ownership and confirms that other projects were untouched.

## October 5 build 18 delivery (historical)

**Available to Alex in TestFlight: Empires version 1.0/build 18.** Apple reports
VALID processing and IN_BETA_TESTING for build
`0be8eac0-2a08-4756-ba47-701e4d1f6ccb`. Alex Chandler belongs to the Internal group
with `hasAccessToAllBuilds=true`. The [Apple/access receipt](evidence/receipts/build18-testflight.json)
was verified October 5 at 19:36:07 UTC. Open **TestFlight → Empires → Update**, then
**New Game → Rules → Naval**. The paired phone was unavailable to CoreDevice;
physical installation and hardware play remain unverified.

Alex requested wider aligned Match Settings, one information control per row,
reviewed screenshots and delivery to his iPhone. Source
`8953413e0fe62609ebb458bcba6f941494329c7f` includes the complete Naval mode, refined
setup and current phone-release behavior. Production files match `3950bfd`; the
later change improves native observation after one Confirm tap. The primary
checkout and Jake's committed signing defaults were preserved.

## Verification

The first full release gate passed ten stages, including Engine 347 functions/
23 suites, AI 295/29, coverage 96.61%/96.03%, lint, secret scan and Release/Debug
builds. Its parallel app/UI stage failed four checks. Those original failures
remain in the [gate log](evidence/receipts/full-release-gate.log) and
[valid failed result](/Users/alex/.codex/artifacts/naval-exploration/full-release-gate-failed.xcresult).
The complete serial app/UI rerun at `8953413` passed **684 functions: 683 passed,
zero failed, one skipped; 1,376 passing runs**. The short-phone-only trade test
requires 375×667 points and is skipped on this 402×874 destination. This is
composed verification of all stages, not a full-gate exit-zero claim.

The [serial summary](evidence/receipts/release-app-ui-serial-summary.json),
[original log](evidence/receipts/release-app-ui-serial.log) and
[valid result](/Users/alex/.codex/artifacts/naval-exploration/release-app-ui-serial.xcresult)
are retained. The focused integrated check passes 30 functions/41 runs. All 48
declared Naval bridge trajectories match every result field except buildID;
this preserves the original frozen AI evidence without declaring new strength.
[Release compatibility](release-compatibility.md) records fixture corrections,
failed reruns and the policy/persistence/privacy boundaries.

The [current visual review](evidence/visual-review.md#build-18-final-source-captures)
contains original, inspected build 18 selector/help captures and earlier regular/
SE refinements. Named help explains each option, including Standard, Conquest
and Naval, with stable selection/footer and readable full Naval copy.

## Release artifact

The separate Release simulator build was freshly installed and launched without
QA flags, survived and produced no new crash reports. The [runtime receipt](evidence/receipts/build18-release-runtime.json)
records executable SHA256
`741350c68d42bf6328d2430a25af7fed5ef1052ecac25d98082d74c234c20635`.
The separate **Empires Build 18 Review**, iPhone 17 Pro Max/iOS26.5, is open on the
main menu with the same Release artifact; it preserves the earlier review device.
Its [inspected screen](evidence/screenshots/build18-review-main-menu.png) uses no
QA arguments or prepared extra-card position.

Manual distribution signing uses Alex's existing certificate/profile and enables
the same production CloudKit container as the phone release. The [signed export](evidence/receipts/build18-signed-export.json)
proves version 1.0/build 18, strict code signature, beta-reports-active=true,
get-task-allow=false, no provisioned-device list, and CloudKit Production.
The exported IPA SHA256 is
`aecefe55035eab2f47c06629bfc43701996f50d664a3b9f6dc7f1eaa7ed54fa2`.
The [upload log](evidence/receipts/build18-upload.log) records accepted upload;
Apple's exact processing/access response completes delivery evidence.

The signed archive, IPA and receipt bundle are preserved under
[build 18 artifacts](/Users/alex/.codex/artifacts/naval-exploration/testflight-build18).
Hash-verified duplicate temporary xcresults were removed after copying to the
durable artifact directory when the host ran out of disk space. Source files,
user saves and other tasks' artifacts were untouched.

Human enjoyment, manual VoiceOver play, physical-phone timing and unscripted
hardware matches remain measurements for Alex's review.

## Build 19 refinement delivered

**Historical TestFlight delivery: version 1.0/build 19**, source
`5c01f39d20fe20bbae734850dd30beb9f0d1f1e8`. Apple build
`ecd04a90-3e32-44cd-b3db-fdf4bc2c2b21` is VALID and IN_BETA_TESTING. Alex's
Internal group has access to all builds; the [processing/access receipt](evidence/receipts/build19-testflight.json)
records fresh confirmation. Physical installation is unverified because the
paired phone is unavailable to CoreDevice. The existing separate iPhone17ProMax
review simulator was updated in place to the ordinary Release 19 main menu.

Advanced Settings replaces inline island families/mist/resources. Its live draft
choices, retained prefill, selected-family explanation and pinned Done survive
real navigation. Regular setup fits from title through Turn Order. Maximum-text
option descriptions no longer exceed their viewport and VoiceOver receives the
explanations as hints. The first native passes exposed genuine page overflow and
oversized explanation, plus an ambiguous title query and floating-point 44pt
representation; all failed logs remain in receipts. Exact viewport assertions
were retained. The [regular five-test check](evidence/receipts/build19-advanced-bounded-summary.json)
and [SE five-pass/one-height-specific-skip check](evidence/receipts/build19-advanced-small-summary.json)
precede the complete final gate.

New Naval v2 settles survey from the actual three-center corner; ship range remains
centered on the ship. Native confirmation at the reported corner changes public
coverage from 19 to 25, versus the legacy 32, and cold resume preserves 25. Existing
Naval v1 matches and archives keep their recorded rules and all public discoveries.
The home 19 setup survey remains a separate explicit rule; no answer was received
to the optional request to change it. D36 and the contextual rulebook explain it.

The complete source-bound [gate log](evidence/receipts/build19-full-gate.log) and
[summary](evidence/receipts/build19-full-gate-summary.json) pass all 11 stages, exit 0.
Engine 358 functions/25 suites and AI 295/29 pass; coverage 96.65%/96.03%. App/UI 688
functions: 686 passed, 0 failed, 2 skipped; 1,379 passing runs. Skips are the conditional
naturally-pending-seven journey when its dice path does not reach that phase,
and a trade-footer test requiring 375×667 instead of this 402×874 destination.
The [complete result](/Users/alex/.codex/artifacts/naval-exploration/build19-full-gate.xcresult)
preserves exact native settings, sailing/capture/harvest/complete-match/replay,
ReduceMotion and hidden-production pixel checks.

[Fresh v2 functional AI evidence](evidence/receipts/build19-naval-v2-functional-compact-receipt.json)
contains 48/48 completed configurations and 28,311 actions. All six separate-process
repeats are byte-identical with zero excluded fields. Twelve raw revisits in nine
games follow fresh discovery or settlement/fleet opportunities; no idle loops,
forced ends, duplicate proposals or checkpoint failures. Historical v1 strength
is not reassigned to v2. All110package-source hashes match the final release tree.

The [reviewed gallery](evidence/visual-review.md#build-19-refinement-gallery) and
[capture manifest](evidence/screenshots/build19-manifest.json) preserve original
build19 screenshots. Fog/coast rendering reads only public redacted terrain and
coordinate noise; the hidden-cell core remains opaque. World and maximum 9×zoom
screens retain the board's own clipping boundary.

The freshly installed Release simulator artifact survives without QA flags or
new crash reports. Its [runtime receipt](evidence/receipts/build19-release-runtime.json)
records SHA256 `3fe8ce9ab337ddd819891d50e518fe5ec45e1b260f56897d6f40f153e88aa625`.
The [signed export](evidence/receipts/build19-signed-export.json) verifies manual
existing-certificate/profile signing, strict signature, beta-reports-active,
get-task-allow=false, no device list and production CloudKit. IPA SHA256:
`99a1bf0c64e38a75a85ccc8766c1fda31a1a026907fb59796fbf503300f79703`.
[Upload](evidence/receipts/build19-upload.log) exited 0. Archive, IPA and exact Apple
response are retained in [the artifact bundle](/Users/alex/.codex/artifacts/naval-exploration/testflight-build19).

Human enjoyment, unscripted hardware games, physical-phone timing and manual
VoiceOver play remain measurements for review.
