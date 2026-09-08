# Heuristic delivery — Builds 6 and 7

## Decision and scope

Pause neural-network/search delivery and further training. Ship the existing
Balanced heuristic for new games. Build 6 used main `4552809`; Build 7 also
includes main through `b27d7fd`: menu cleanup, replay point breakdowns and the
board's reclaimed bottom space. This is a deployment choice, not a new strength
claim or a claim that heuristic play is expert play.

## Acceptance criteria

- New games use Balanced for every bot, including games prefilled from older
  setup preferences. Civilization, general name, artwork and dialogue remain.
- Resuming an existing match preserves its saved bot strategies and identities.
- Unsupported research-policy saves are not silently converted or overwritten.
- Human seats have no bot policy; three- and four-player setups remain playable.
- Package, app and interactive UI suites pass, including a complete match.
- A fresh Release launch survives without a new crash report.
- Jake's committed signing identity is unchanged. Alex's release is
  `com.alexchandler.empires`, version 1.0, Build 7 for the combined-main release.
- Delivery means Apple's exact build is processed and available to the intended
  testers; an archive alone is not delivery.

## Research handoff

The [six-stage plan](AI-PROGRAM.md) separates personality (stage 4) from
heuristic strategy improvements (stage 5). Neither starts during this release.
The [research findings and restart map](2026-09-08-research-handoff.md) index
the frozen archive outside this product-only branch at
`~/Library/Application Support/EmpiresResearch/handoffs/search-pause-20260908/`.
Its README, source bundle and terminal diagnostic preserve the experiments and
restart instructions. Search is not proven to beat Balanced within the phone
latency budget. No new training or personality work is part of this release.

## Build 6 verification and delivery (historical)

- Standards review: no findings. Spec review: no implementation blockers.
- Tests: 58 evaluation-tool tests, 222 engine tests, 110 AI tests; all passed.
- App/UI: 315 tests / 376 parameterized executions, no failures or skips.
  Includes the UI-hosted full game, new-draft routing, all supported human/bot
  seat compositions, cold resume and unsupported-checkpoint preservation.
- Engine/AI coverage: 95.95% / 96.93%, both above their 95% floors.
- Release and Debug builds passed. Fresh Debug and Release launches survived;
  screenshots inspected and the Release crash-directory diff was empty.
- Initial whole-history secret scan flagged two research README prose matches;
  exact-fingerprint exclusions were reviewed and the repeated scan passed.
- Signed Build 6 reached VALID and IN_BETA_TESTING internally and externally
  on September 8 at 13:18:33 UTC, attached to Jake's group. This is availability,
  not proof of installation on a physical phone.

Evidence is retained locally in `/private/tmp/empires-build6.ITWKqT/` during the
release and copied to the durable EmpiresResearch delivery artifact afterward.

## Build 7 integration and closeout

- [Product PR #46](https://github.com/jakebeinart1/Settlers/pull/46) is the merge
  and final verification receipt. Alex explicitly authorized merging after
  verification; no Jake review prerequisite. Research PRs are excluded.
- First combined-main revision (`e034391`, before the board refinement) passed
  the full local gate: 321 app/UI tests, 382 parameterized executions, zero
  failures/skips. Debug and Release builds passed; a fresh Release launch
  survived with no new crash report. New Game fit at 375pt and 402pt widths;
  settings and replay screenshots were inspected.
- Main then added `b27d7fd`; rerun the gate and rebuild the final archive against
  that source. Never label the earlier archive as including the later change.
- Physical phone was read back as Build 4. Its Documents, preferences and
  Application Support were copied before attempting an in-place update. The
  active match has four moves and preserves aggressive/cautious/balanced bots;
  only a new match gets all Balanced. Do not erase it for a test.
- Direct installation encountered CoreDevice tunnel/connection interruptions;
  a successful build or TestFlight upload does not resolve that runtime check.
  Final phone and Apple receipts belong with the release evidence below.
- Durable Build 7 evidence directory:
  `/Users/alex/Library/Application Support/EmpiresResearch/deliveries/heuristic-build7-20260908/`.
  Its README records final source, merge, tests, beta access, physical-device
  outcome and exact archive. Earlier artifacts are labeled as superseded.

Public beta link: https://testflight.apple.com/join/gc4xMVQm

### Signing recovery

The old `Empires App Store` profile names certificate `HRFB9B4356`, whose
private key in `nc-signing.keychain-db` failed a signing probe. The existing
login-keychain certificate `S2Q2L68J6M` passed the same probe. Created only an
Empires provisioning profile for that existing identity:

- Profile: `Empires App Store Login` (`X47H2XT47P`).
- Certificate SHA-1: `76465B06C2E157D857641F5B3D25CF5A3110C4A9`.
- Expiry: January 25, 2027.

Use these explicit manual-signing selections for this release. Neither
certificate was created/revoked; no keychain permissions or other app profiles
were changed. Jake's committed signing configuration remains unchanged.
