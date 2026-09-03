# Consolidation metric results

Date: 2026-09-02
Candidate branch: `codex/personality-analysis`
Simulator schema: 4
Release simulator SHA-256:
`d88b497e5e2b213dbacf73622fe764985149a42c963fc00483c35a1277c2a7eb`

## Decision

Use **city capture rate**—the fraction of policy decisions that choose a city
when at least one city is in the exact legal action mask—as the consolidation
metric. It is observable, opportunity-normalized, and frequent enough for a
held-out comparison. It supports one additional style statement: Cautious
converts a buildable city more reliably than Balanced. It does not establish a
difficulty or strength ordering.

Do not use “city versus settlement” or “city versus outward build” as the
shipping metric. They sound more specific but are too sparse in actual games.
The first produced only 1–9 opportunities per 160-game arm. A calibration of
the second projected 28–36, and the full held-out run produced only 20–23;
Cautious's interval still crossed zero. Both would turn a handful of choices
into an overconfident product claim.

## Protocol

- Pre-tuning calibration: seeds 36000–36009, every candidate rotated through
  all four chairs against three Balanced policies.
- Held-out decision: seeds 37000–37039, the same four-chair rotation, 160 games
  per personality and 480 total.
- All 480 games were decisive.
- The simulator records the legal mask and chosen action at decision time; the
  analyzer does not reconstruct opportunities afterward.
- The paired analyzer requires identical seed/chair keys and resamples each
  board seed with all four chair rotations as one cluster.

## Held-out city-capture result

| Strategy | Cities chosen when buildable | Opportunities | Difference from Balanced | Seed-cluster 95% CI |
| --- | ---: | ---: | ---: | ---: |
| Balanced | 93.0% | 186 | — | — |
| Aggressive | 94.1% | 185 | +1.0 points | −3.5 to +5.9 |
| Cautious | 99.5% | 221 | **+6.5 points** | **+3.1 to +10.3** |

Balanced and Aggressive are not distinguishable on this axis. Cautious is.
The result is a behavior statement only; a separate frozen-anchor run guards
strength and legality.

## Frozen-anchor regression

The same Release binary then replayed seeds 35000–35039 with each candidate in
all four chairs against three frozen Greedy anchors. All 480 games were
decisive. The result exactly reproduced the pre-telemetry behavior run:

| Strategy | Wins | Seed-cluster 95% CI | Median moves |
| --- | ---: | ---: | ---: |
| Balanced | 133/160 (83.1%) | 77.5%–88.1% | 375 |
| Aggressive | 131/160 (81.9%) | 75.0%–88.1% | 378 |
| Cautious | 130/160 (81.2%) | 75.6%–86.9% | 389 |

This exact match is the expected result because the change observes decisions
without affecting them. It is a regression check, not a claim that one
personality is stronger than another.

## Tooling consequence

`scripts/analyze-bot-evaluation.py` now accepts a paired baseline arm and
prints the pooled rate difference with a seed-cluster bootstrap interval. It
rejects mismatched seed/chair sets, provenance, schemas, and missing
opportunities instead of producing an unpaired comparison. Simulator schema 4
adds `cityBuildOpportunities` and `citiesChosenWhenBuildable`.
