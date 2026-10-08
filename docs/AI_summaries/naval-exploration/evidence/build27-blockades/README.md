# Build 27 — defensive ship evidence

Open [the screenshot gallery](gallery.html) for eight final-source captures, the ordinary Release menu, eight earlier passing captures and the separately marked failed predecessor. Click an image for the unchanged original PNG.

The **full pre-push gate passed** on source `2d985b9` and 378 frozen inputs: 779 native functions, 777 passed, 0 failed, 2 skipped; 1,560 runs, 1,558 passed. Gate and hook kernel exits were 0. The original Git transport returned −13 SIGPIPE; the unchanged-source transport retry then passed.

**TestFlight 1.0 (27) is delivered:** Apple reports VALID and unexpired, and Alex’s Internal tester access is confirmed. [Latest status](status-latest.json) records delivery, source CI and the remaining root-owned metadata/PR checks. Physical iPhone installation and play remain unobserved; no external release was performed.

The original [status-at-export snapshot](status-at-export.json) and [post-gate snapshot](status-after-gate.json) remain unchanged as historical pending evidence.

## Verified Release and TestFlight delivery

- [TestFlight receipt](receipts/testflight.json): build `1.0 (27)`, Apple UUID `a49ab68c-859a-4467-8454-c1c5fde1677a`, VALID, unexpired, Internal group and intended Alex tester access confirmed.
- [Release menu original](release/ordinary-menu.png), [fresh runtime](receipts/release-runtime.json), and [original root review](receipts/root-release-menu-review.json): the gate-built Release app launches without QA arguments; physical iPhone installation/play was not observed.
- [Delivery summary](receipts/delivery-summary.json), [root recomputed review](receipts/root-final-delivery-review.json), [independent release audit](receipts/final-independent-release-audit.json), [accepted-payload signature metadata](receipts/uploaded-payload-signature.json), [review/upload comparison](receipts/uploaded-payload-comparison.json), and [signed export metadata](receipts/signed-export.json). Source, tests and archive are bound to the same `2d985b9` and 378 frozen production inputs.
- Actual operation receipts: [archive](receipts/archive-command-receipt.json), [export](receipts/export-command-receipt.json), [upload](receipts/upload-command-receipt.json), and the [bounded export log](logs/release-export.log). All three operations exited 0. No raw transporter log, signing key/profile file or IPA is exported.
- [Source CI](receipts/source-ci-checks.json): Engine + AI (Linux) passed in 19m31s, SwiftLint passed, on-demand drift skipped. Final metadata-head CI and PR61 disposition remain root-owned.
- [Simulator finish metadata](receipts/simulator-finish-and-source-guard.json): owned QA was individually shut down, all 14 devices retained, and the other 13 states unchanged. Two unrelated project simulator names are omitted; the gallery manifest retains the original source SHA and explicit redaction. [Three helper worktrees were archived](receipts/helper-worktree-cleanup.json).
- [Safety receipt](release-export-safety.json) and [zero-findings gitleaks report](receipts/release-gitleaks-report.json): selected metadata scanned before repository export. Signing profile names, UUIDs and certificate hashes are verification metadata; actual profiles and private material are excluded.

## Final-source captures and full gate

Root reviewed these eight original pixels at full resolution. The gate's ordinary winner is **Washington 14 VP**, with Alex 7, Charlemagne 8 and Ragnar 11. The earlier Tokugawa winner is preserved separately below.

| Final capture | Point |
| --- | --- |
| [Defensive hex](final-source/01-defensive-hex.png) | Occupied rival sea cannot be entered; the straight destination beyond it exceeds the two-hex budget. No global choke claim. |
| [World and Return](final-source/02-world-return.png) | Return remains available and the occupied-cell touch cannot snap or change the camera. |
| [Capture proposal](final-source/03-capture-proposal.png) | Preview remains uncommitted until Capture. |
| [Route after capture](final-source/04-captured-ship-opens-route.png) | Confirmed ownership opens the route; Sail still commits the voyage. |
| [Cold resume](final-source/05-cold-resume.png) | Completed travel and captured ownership survive termination and Resume. |
| [Blocked launch](final-source/06-launch-blocked.png) | The funded unavailable purchase names its blocked coast and spends no cards. |
| [Largest text](final-source/07-largest-text.png) | Complete maritime instruction is visible, with the stated compact-text cap. |
| [Final ordinary winner](final-source/08-ordinary-match-winner.png) | Washington wins the final native scripted ordinary match at 14 VP. |

- [Raw native summary](receipts/final-native-summary.json), [raw test nodes](receipts/final-native-tests.json), [gate success](receipts/final-gate-success.json) and [complete gate log](logs/final-prepush-gate.log).
- [Kernel exit observation](receipts/prepush-kernel-exit-observation.json) and [registration](receipts/prepush-kernel-registration.json) preserve actual gate/hook 0 and original Git −13. [Original push receipt](receipts/final-prepush-command.json) remains unchanged; [transport-only retry](receipts/transport-only-retry.json) is separate and passed against the same source.
- [Final original-pixel review](receipts/root-final-gate-visual-review.json), [final gate/source audit](receipts/final-gate-source-audit.json), and [earlier independent source audit](receipts/final-independent-source-audit.json), whose earlier pending gate status is historical.
- Two skipped flows remain unchecked by this full native run: a natural human seven did not arise, and the 375×667 compact destination was not allocated. The optional Debug gate build also skipped because it was not requested; focused Debug native actions ran separately.

## Earlier focused captures

| Capture | Verified point |
| --- | --- |
| [Defensive hex](screenshots/01-defensive-hex.png) | An opposing ship blocks its sea hex. The straight destination beyond it cannot be reached within the two-hex budget; this is not a global choke claim. |
| [World and Return](screenshots/02-world-return.png) | Return remains available; touching an occupied hex cannot snap to another legal destination or change the camera. |
| [Capture proposal](screenshots/03-capture-proposal.png) | The colour preview is a proposal. Native ownership assertions remain unchanged until confirmation, and a restart clears the proposal. |
| [Route after capture](screenshots/04-captured-ship-opens-route.png) | Confirmed capture opens a two-hex route through the now friendly ship; the voyage still requires Sail confirmation. |
| [Cold resume](screenshots/05-cold-resume.png) | Confirmed voyage, captured ownership and charted map survive termination and Resume. |
| [Blocked launch](screenshots/06-launch-blocked.png) | A funded purchase names the opposing ships blocking every owned launch cell and spends no resources. |
| [Largest text](screenshots/07-largest-text.png) | The full instruction is visible at Accessibility XXXL. Compact maritime text is capped at Large; Fleet and the rulebook remain unrestricted. |
| [Ordinary winner](screenshots/08-ordinary-match-winner.png) | An earlier native scripted ordinary match reaches Tokugawa's actual 14-VP winner screen, with Alex at 7 VP. It predates the dock readability correction. |
| [FAIL — earlier largest text](failed/first-largest-text-truncated.png) | Original pixels visibly truncate despite successful accessibility-label assertions. This failed predecessor is retained, not presented as current. |

## Receipts and inputs

- Corrected native: [command](receipts/readable-dock-focused-command.json), [raw summary](receipts/readable-dock-focused-summary.json): **8 passed, 0 failed, 0 skipped**.
- First native: [command](receipts/first-focused-command.json), [raw summary](receipts/first-focused-summary.json): **44 test functions / 71 parameterized runs passed**, with a separate [failed visual review](failed/first-root-visual-review.json).
- Source audits: [readability](receipts/final-readability-audit.json), [cross-module](receipts/final-cross-module-audit.json), [root visual review](receipts/root-final-visual-review.json). Reviewer authorship and runtime limits are disclosed in their receipts.
- Engine: [receipt](receipts/engine-receipt.json), [small final log](logs/engine-targeted-final.log). AI policy: [receipt](receipts/ai-policy-receipt.json), [small final log](logs/ai-second-focused-navals.log).
- Functional matrix: [summary](matrix/summary.json), [declared plan](matrix/functional-plan.json), [48 raw results](matrix/functional-results.json), [six determinism comparisons](matrix/determinism-results.json), [final receipt](matrix/final-functional-receipt.json), [metrics](matrix/metrics.json), [raw revisit review](matrix/raw-revisit-review.json). This establishes functionality and reproducibility; **no comparative AI strength claim**.
- Source binding: [378 production inputs](manifests/final-production-input-manifest.json) and [112 package input hashes](manifests/package-source-hashes-after-matrix.json).
- [Gallery manifest](gallery-manifest.json) records original source paths, exported relative paths, test names, capture timestamps and SHA-256 values for every selected image and copied receipt.

The attachment manifests preserve the complete original inventories; only the eighteen explicitly indexed captures are copied here. Relevant absolute source paths remain in raw receipts as provenance. All PNGs and unredacted raw receipts/logs are copied byte-identically. One derived simulator-finish receipt omits unrelated project names with its source SHA retained. No keys, actual provisioning profiles, IPA payloads, binaries, raw transporter logs or signed URLs, incomplete gate logs, unrelated user paths or large `xcresult` bundles are exported.

New Naval games use rules v4; saved v1–v3 games retain their earlier sharing, transit and launch semantics. Each corrected capture section represents seven selected native fixture checkpoints and one ordinary scripted full match. The final match uses production policies with deliberate UI checkpoints; the human did not choose every move. These are not a claim of exhaustive manual review.
