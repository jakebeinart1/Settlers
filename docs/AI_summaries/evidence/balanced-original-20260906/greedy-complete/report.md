# Smoke verification — not a strength claim

Development seeds; small sample. See manifest.json and run.watchdog.json.

# balanced-vs-original-greedy-opponents

- Games: 256 (64 seed/config clusters × 4 seat rotations)
- Decisive: 256/256
- Wins: 214/256 = 83.6% (seed-cluster bootstrap 95% CI 78.5%–88.3%)
- Median moves: 381.5

| Behavior per game | Mean | 95% CI margin |
| --- | ---: | ---: |
| `roadsBuilt` | 10.039 | ±0.506 |
| `settlementsBuilt` | 2.430 | ±0.167 |
| `citiesBuilt` | 1.516 | ±0.154 |
| `developmentCardsBought` | 6.934 | ±0.408 |
| `knightsPlayed` | 3.348 | ±0.259 |
| `robberMoves` | 8.059 | ±0.500 |
| `bankTrades` | 12.430 | ±1.008 |
| `tradesProposed` | 26.367 | ±1.899 |
| `resolvedTradeAcceptances` | 0.000 | ±0.000 |
| `resolvedTradeRejections` | 0.000 | ±0.000 |
| `turnsEnded` | 27.652 | ±1.166 |
| `settlementCityOpportunities` | 0.051 | ±0.029 |
| `settlementsChosenInMixedBuildOpportunities` | 0.039 | ±0.025 |
| `citiesChosenInMixedBuildOpportunities` | 0.012 | ±0.013 |
| `cityBuildOpportunities` | 1.656 | ±0.172 |
| `citiesChosenWhenBuildable` | 1.516 | ±0.154 |
| `developmentCardBuildOpportunities` | 2.027 | ±0.233 |
| `developmentCardsChosenOverPermanentBuild` | 0.141 | ±0.096 |
| `tradeResponseOpportunities` | 0.000 | ±0.000 |
| `tradeResponsesAccepted` | 0.000 | ±0.000 |
| `proposalCardsGiven` | 34.875 | ±2.832 |
| `proposalCardsRequested` | 26.711 | ±1.977 |
| `playableKnightOpportunities` | 29.938 | ±3.627 |
| `knightsChosenWhenPlayable` | 3.348 | ±0.259 |
| `differentiatedRobberTargetOpportunities` | 6.406 | ±0.496 |
| `highestPublicVPRobberTargets` | 5.195 | ±0.475 |
| `tradeProposalOpportunities` | 77.980 | ±3.695 |

| Opportunity-normalized behavior | Rate | Opportunities |
| --- | ---: | ---: |
| city choice when city and settlement were legal | 23.1% | 13 |
| development-card choice when a permanent build was legal | 6.9% | 519 |
| city chosen when buildable | 91.5% | 424 |
| trade acceptance | not observed | 0 |
| knight use when playable | 11.2% | 7664 |
| highest-public-VP robber target when targets differed | 81.1% | 1640 |
| player-trade proposal | 33.8% | 19963 |

## Paired strength

| Arm | Build ID | Evaluated policy | Opponent policy | Pooled win rate | Decisive rate | Median moves |
| --- | --- | --- | --- | ---: | ---: | ---: |
| Candidate | `frozen-140f9f7ac53512671687e5d5b77b209a273af7858e6525877812710a81c1573d` | `heuristic-balanced` | `greedy` | 214/256 = 83.6% | 256/256 = 100.0% | 381.5 |
| Baseline | `frozen-140f9f7ac53512671687e5d5b77b209a273af7858e6525877812710a81c1573d` | `upstream-v1-hybrid-greedy-swift-compounds-trade-scheduler-fallback-heuristic-balanced-declared-sha256-21f3b380786a53998172896caac44191dea3d44efd11d3bf8c92150d8b18c8a5` | `greedy` | 148/256 = 57.8% | 256/256 = 100.0% | 470 |

- Paired win-rate difference: +25.8 percentage points
- Seed-cluster bootstrap 95% CI: +17.6 to +34.0 percentage points

## Paired differences from `upstream-v1-hybrid-greedy-swift-compounds-trade-scheduler-fallback-heuristic-balanced-declared-sha256-21f3b380786a53998172896caac44191dea3d44efd11d3bf8c92150d8b18c8a5`

| Opportunity-normalized behavior | Difference | Seed-cluster 95% CI | Candidate / baseline opportunities |
| --- | ---: | ---: | ---: |
| city choice when city and settlement were legal | +23.1% | +0.0% to +50.0% | 13 / 10 |
| development-card choice when a permanent build was legal | -42.3% | -51.8% to -32.7% | 519 / 337 |
| city chosen when buildable | +8.8% | +2.4% to +15.1% | 424 / 572 |
| trade acceptance | not observed | not observed | 0 |
| knight use when playable | -38.2% | -42.8% to -33.8% | 7664 / 2697 |
| highest-public-VP robber target when targets differed | +41.2% | +34.8% to +47.5% | 1640 / 2246 |
| player-trade proposal | -4.9% | -6.9% to -2.9% | 19963 / 27663 |

## Decision routes (evaluated chair only)

Selections include forced choices; these are not network inference-call counts.

- candidate: routes `{"policy": 33401}`; intentional fallbacks `{}`.
- baseline: routes `{"heuristic": 11413, "neural": 33741}`; intentional fallbacks `{"heuristic_trade_proposal": 10718, "unsupported_pre_roll_development_card": 695}`.
