# Smoke verification — not a strength claim

Development seeds; small sample. See manifest.json and run.watchdog.json.

# neural-r2-native-transfer-diagnostic

- Games: 128 (32 seed/config clusters × 4 seat rotations)
- Decisive: 128/128
- Wins: 52/128 = 40.6% (seed-cluster bootstrap 95% CI 32.0%–49.2%)
- Median moves: 498.5

| Behavior per game | Mean | 95% CI margin |
| --- | ---: | ---: |
| `roadsBuilt` | 4.969 | ±0.595 |
| `settlementsBuilt` | 1.227 | ±0.206 |
| `citiesBuilt` | 2.352 | ±0.214 |
| `developmentCardsBought` | 5.250 | ±0.771 |
| `knightsPlayed` | 2.797 | ±0.431 |
| `robberMoves` | 9.375 | ±1.159 |
| `bankTrades` | 17.922 | ±2.572 |
| `tradesProposed` | 24.875 | ±3.245 |
| `resolvedTradeAcceptances` | 0.000 | ±0.000 |
| `resolvedTradeRejections` | 0.000 | ±0.000 |
| `turnsEnded` | 42.734 | ±4.658 |
| `settlementCityOpportunities` | 0.062 | ±0.038 |
| `settlementsChosenInMixedBuildOpportunities` | 0.031 | ±0.029 |
| `citiesChosenInMixedBuildOpportunities` | 0.016 | ±0.021 |
| `cityBuildOpportunities` | 2.750 | ±0.371 |
| `citiesChosenWhenBuildable` | 2.352 | ±0.214 |
| `developmentCardBuildOpportunities` | 3.258 | ±0.623 |
| `developmentCardsChosenOverPermanentBuild` | 0.008 | ±0.015 |
| `tradeResponseOpportunities` | 0.000 | ±0.000 |
| `tradeResponsesAccepted` | 0.000 | ±0.000 |
| `proposalCardsGiven` | 35.562 | ±4.592 |
| `proposalCardsRequested` | 24.992 | ±3.254 |
| `playableKnightOpportunities` | 4.445 | ±0.716 |
| `knightsChosenWhenPlayable` | 2.797 | ±0.431 |
| `differentiatedRobberTargetOpportunities` | 7.297 | ±1.082 |
| `highestPublicVPRobberTargets` | 2.984 | ±0.745 |
| `tradeProposalOpportunities` | 95.672 | ±9.453 |

| Opportunity-normalized behavior | Rate | Opportunities |
| --- | ---: | ---: |
| city choice when city and settlement were legal | 25.0% | 8 |
| development-card choice when a permanent build was legal | 0.2% | 417 |
| city chosen when buildable | 85.5% | 352 |
| trade acceptance | not observed | 0 |
| knight use when playable | 62.9% | 569 |
| highest-public-VP robber target when targets differed | 40.9% | 934 |
| player-trade proposal | 26.0% | 12246 |

## Paired strength

| Arm | Build ID | Evaluated policy | Opponent policy | Pooled win rate | Decisive rate | Median moves |
| --- | --- | --- | --- | ---: | ---: | ---: |
| Candidate | `frozen-db4050d19c788c977b6f9ffb08c8d6b2605f0a385e6eebb36d9cca0896c83767` | `upstream-r2-hybrid-greedy-swift-compounds-trade-scheduler-fallback-heuristic-balanced` | `greedy` | 52/128 = 40.6% | 128/128 = 100.0% | 498.5 |
| Baseline | `frozen-db4050d19c788c977b6f9ffb08c8d6b2605f0a385e6eebb36d9cca0896c83767` | `heuristic-balanced` | `greedy` | 112/128 = 87.5% | 128/128 = 100.0% | 396 |

- Paired win-rate difference: -46.9 percentage points
- Seed-cluster bootstrap 95% CI: -57.8 to -35.9 percentage points

## Paired differences from `heuristic-balanced`

| Opportunity-normalized behavior | Difference | Seed-cluster 95% CI | Candidate / baseline opportunities |
| --- | ---: | ---: | ---: |
| city choice when city and settlement were legal | +25.0% | +0.0% to +60.0% | 8 / 7 |
| development-card choice when a permanent build was legal | -7.1% | -12.8% to -2.1% | 417 / 286 |
| city chosen when buildable | -5.3% | -16.6% to +5.3% | 352 / 175 |
| trade acceptance | not observed | not observed | 0 |
| knight use when playable | +53.9% | +48.9% to +59.3% | 569 / 4347 |
| highest-public-VP robber target when targets differed | -37.0% | -48.6% to -25.5% | 934 / 754 |
| player-trade proposal | -8.0% | -9.9% to -6.1% | 12246 / 10238 |

## Decision routes (evaluated chair only)

Selections include forced choices; these are not network inference-call counts.

- candidate: routes `{"heuristic": 3445, "neural": 17811}`; intentional fallbacks `{"heuristic_trade_proposal": 3184, "unsupported_pre_roll_development_card": 261}`.
- baseline: routes `{"policy": 17222}`; intentional fallbacks `{}`.
