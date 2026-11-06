# Leaderboard layout audit — November 2, 2026

## Status

PR 71 was moved from draft to ready at Alex’s explicit request, before the
requested code review. It remains open and unmerged. The published `bf0f804`
gallery is a rejected baseline; its historical gate does not qualify this
local redesign.

The five independent published-source review perspectives completed: standards,
introduced bugs, history, prior discussions and comment contracts. They found
no additional high-confidence introduced code defect. Local source review and
native visual review found the corrections described below.

## Product structure

- Keep the existing Leaderboard home action. Its small ordinary-text Elo
  accessory replaces the separate home rating plaque.
- Players and Ghosts share the Leaderboard feature. Mode and AI difficulty
  occupy one row; the ordinary overview contains all three people and the
  shared opponent on its first frame.
- Profiles, Games and accessibility rating history are deliberate destinations.
  Back, context selectors and dismissal remain outside scrolling content.
- Naming and sync explanations live in a secondary sheet. Existing ghost
  selection and radar survive a visit to a person’s mode-specific record.
- One snapshot resolves adopted local identities before Elo replay. An
  interrupted adoption cannot split the visible record; a historical owner
  does not become a later signed-in account. Loading changes no stored record.

## Native critique and refinement

The first complete redesigned-phone pass (`refined-standard-r1`, R5) executed
26 checks: **13 passed, 10 failed, 3 compact-only checks skipped**. This was a
real failed run, retained with its original source, results and captures.

It exposed a vertically expanding Players/Ghosts divider: the selector became
an enormous panel and squeezed the table, clipping the shared opponent. Largest
text also lost table space to a decorative Spacer. A mode-popup measurement
failed because its actual accessibility role was Alert while the query required
Other; the popup existed in the exported hierarchy.

The refinement fixes the selector at 44 points, gives accessibility rows the
remaining table space, aligns metric cells at their tops and sizes history
navigation consistently with other chrome. It preserves full rating/Unrated
text with a horizontal/vertical fallback, removes repeated sync copy, and uses
consistent number grouping. Picker checks now wait for a real control and find
geometry by its identifier across accessibility types.

The next complete standard-phone pass (`refined-standard-r2`, R6) returned
**23 passed, zero failed and 3 compact-only checks skipped**, native exit 0.
It used the actual **402×874-point iPhone 17 Pro / iOS 26.5** destination, serial
execution and unchanged-source verification. Summary and attachment export
both returned 0; the owned simulator was shut down. The tested Swift/project
source guard is `c128dec6b6aeac610dc6b2c2978b08df6d0d9e354f22be8eb632a1d703f35887`.

Independent uncropped-image review accepted that destination’s home and busy
home, complete standings, ordinary/long-name/Unrated profiles, populated and
empty history, selectors, help/account, receipts and preserved Ghost routes.
Largest-text captures show readable bounded scrolling, aligned metrics and
reachable navigation. Passing tests alone were not treated as image approval.

After that pass, the local candidate caps pinned record-context text at the
same accessibility range as other navigation chrome, and clarifies the
Voyages (Naval) naming in Help. Those final changes still require the next
native verification.

## Remaining acceptance

Actual **375×667** verification is pending. The guarded compact journeys cover
ordinary Unrated standings, largest text with the widest permitted name and
Vast Conquest context, full Unrated/Elo/explanation text, bounded empty history,
and invariant navigation while scrolling. Wrong-size skips do not establish
compact fit. Pre-fit screenshots are captured before assertions, with separate
accessibility top and bottom evidence.

The final gallery, exact-commit maintained gate and PR source update remain
pending. No merge, TestFlight delivery or live multi-account iCloud acceptance
is claimed. Synthetic screenshot records prove presentation; the replay and
fake-cloud tests provide their separate functional evidence.

Private source-bound logs, manifests, full-resolution originals and failed
iterations remain under `player-ratings-redesign-20261102` in the local task
artifacts. Simulator work uses the shared resource lease, reuses the existing
owned QA device, and requires separate admission for one necessary compact
device and its first boot. Other projects’ simulators and files are preserved.
