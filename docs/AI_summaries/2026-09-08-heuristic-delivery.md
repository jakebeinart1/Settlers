# Heuristic delivery — Build 6

## Decision and scope

Pause neural-network/search delivery and further training. Ship the existing
Balanced heuristic for new games on top of Jake's main at `4552809`, including
his game-history replay work. This is a deployment choice, not a new strength
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
  `com.alexchandler.empires`, version 1.0, Build 6.
- Delivery means Apple's exact build is processed and available to the intended
  testers; an archive alone is not delivery.

## Research handoff

The frozen research archive lives outside this product-only branch at
`~/Library/Application Support/EmpiresResearch/handoffs/search-pause-20260908/`.
Its README, source bundle and terminal diagnostic preserve the experiments and
restart instructions. Search is not proven to beat Balanced within the phone
latency budget. No new training or personality work is part of this release.

## Verification and delivery

Pending. Record observed results here before calling the release complete.

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
