# Bot personality separation results

Date: 2026-09-02

Candidate source branch: `codex/personality-separation`

Release simulator SHA-256:
`456504f17d29bc8a90ab6a6db9d38cd4f8abc50df3d8eb145ca98d461ba14c16`

## Decision

Two player-visible style axes are now demonstrated:

- **Aggressive** spends owned knights proactively, creating more robber
  pressure. Once a robber target is actually chosen, leader targeting is not
  measurably different from the other profiles.
- **Cautious** tries a player trade before paying a poor bank rate more often.

The evidence does **not** support saying Cautious upgrades cities more often,
accepts materially more offers, or is stronger/weaker than another personality.
Those claims remain barred. Difficulty remains deferred and separate.

The app should also stop assigning strategy by bot-seat order in a later
product-profile change. Civilization/general identity, strategic style,
dialogue voice, and calibrated difficulty are independent fields; a stable
opponent profile should compose them explicitly.

## Protocol

- Behavior: seeds 34000–34039; each candidate rotated through all four chairs
  against three Balanced policies; 160 games per personality.
- Strength regression: seeds 35000–35039; each candidate rotated through all
  four chairs against three Greedy anchors; 160 games per personality.
- Every one of the 960 games was decisive and stayed below the move cap.
- Rates use the exact legal action mask supplied to the policy, captured at
  decision time by `GameSession.decideNextDetailed()`.
- Results were produced by simulator schema 3. Five pinned fingerprints were
  reproduced in three separate Release processes before re-recording.

## Held-out behavior results

| Opportunity-normalized choice | Balanced | Aggressive | Cautious |
| --- | ---: | ---: | ---: |
| Use a knight when playable | 15.4% (3,093) | **42.3%** (1,224) | 14.8% (3,138) |
| Target highest-public-VP victim when targets differ | 77.5% (854) | 81.3% (919) | 76.4% (876) |
| Propose a player trade when available | 39.9% (6,076) | 39.7% (6,037) | **63.0%** (4,860) |
| Accept an affordable incoming player trade | 47.9% (2,053) | 46.6% (2,048) | 48.0% (2,055) |

Parentheses contain opportunity counts, not games. The acceptance-rate and
conditional robber-target spreads are too small to support personality claims.
Settlement-versus-city choices occurred only 4–9 times per arm, so that metric
is underpowered and must not be interpreted.

Using each shared board seed as the independent cluster, Aggressive's knight-
use difference from Balanced is **+26.3 percentage points** (bootstrap 95% CI
**+23.9 to +28.8**). Cautious's player-trade-proposal difference is **+22.9
points** (95% CI **+21.3 to +24.4**). The control comparisons cross zero:
Aggressive proposals −0.3 points [−1.7, +1.0], Cautious knight use −0.9 points
[−3.0, +1.2]. This is the intended two-axis separation, not a general increase
in every action associated with a label.

## Strength-regression results

| Personality | Wins | Seed-cluster bootstrap 95% CI | Decisive | Median moves |
| --- | ---: | ---: | ---: | ---: |
| Balanced | 133/160 (83.1%) | 77.5%–88.1% | 160/160 | 375 |
| Aggressive | 131/160 (81.9%) | 75.0%–88.1% | 160/160 | 378 |
| Cautious | 130/160 (81.2%) | 75.6%–86.9% | 160/160 | 389 |

The intervals overlap. This is a regression smoke test against the current
Greedy anchor, not evidence of a strength ordering and not a difficulty ladder.

## Implementation consequences

- Simulator JSONL schema is now version 3 and includes opportunity denominators.
- `GameSession` exposes an additive detailed-decision API while preserving the
  existing app-facing `decideNext()` signature.
- Aggressive's proactive-knight threshold is above the Balanced preset.
- Cautious's trade-proposal priority clears bank-trade priority; Balanced and
  Aggressive remain below it.
- Trade willingness retains all existing loss, leader-feeding, immediate-build,
  and repeat-proposer safeguards.

## Remaining personality work

1. Add a reusable paired behavior-difference analyzer with seed-cluster
   intervals instead of relying on separate arm summaries.
2. Define a robust consolidation opportunity; city-versus-settlement is too
   rare to measure directly.
3. Run blind replay/live-play recognition before exposing style labels.
4. Replace seat-order strategy assignment with stable opponent profiles.
5. Keep dialogue persona cosmetic and semantically informed; do not let prose
   reach rules or policy selection.
