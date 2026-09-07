# Smoke verification — not a strength claim

Development seeds; small sample. See manifest.json and run.watchdog.json.

# balanced-vs-original-balanced-opponents

- Games: 256 (64 seed/config clusters × 4 seat rotations)
- Decisive: 256/256
- Wins: 64/256 = 25.0% (seed-cluster bootstrap 95% CI 25.0%–25.0%)
- Median moves: 503

| Behavior per game | Mean | 95% CI margin |
| --- | ---: | ---: |
| `roadsBuilt` | 9.547 | ±0.505 |
| `settlementsBuilt` | 2.160 | ±0.168 |
| `citiesBuilt` | 1.004 | ±0.119 |
| `developmentCardsBought` | 5.996 | ±0.136 |
| `knightsPlayed` | 3.117 | ±0.142 |
| `robberMoves` | 7.414 | ±0.484 |
| `bankTrades` | 7.715 | ±0.924 |
| `tradesProposed` | 20.141 | ±1.593 |
| `resolvedTradeAcceptances` | 7.320 | ±0.624 |
| `resolvedTradeRejections` | 12.820 | ±1.227 |
| `turnsEnded` | 24.512 | ±1.405 |
| `settlementCityOpportunities` | 0.043 | ±0.026 |
| `settlementsChosenInMixedBuildOpportunities` | 0.039 | ±0.022 |
| `citiesChosenInMixedBuildOpportunities` | 0.004 | ±0.008 |
| `cityBuildOpportunities` | 1.086 | ±0.132 |
| `citiesChosenWhenBuildable` | 1.004 | ±0.119 |
| `developmentCardBuildOpportunities` | 1.023 | ±0.146 |
| `developmentCardsChosenOverPermanentBuild` | 0.016 | ±0.019 |
| `tradeResponseOpportunities` | 15.855 | ±1.708 |
| `tradeResponsesAccepted` | 7.320 | ±0.624 |
| `proposalCardsGiven` | 25.879 | ±2.095 |
| `proposalCardsRequested` | 20.559 | ±1.694 |
| `playableKnightOpportunities` | 20.695 | ±1.945 |
| `knightsChosenWhenPlayable` | 3.117 | ±0.142 |
| `differentiatedRobberTargetOpportunities` | 5.816 | ±0.435 |
| `highestPublicVPRobberTargets` | 4.387 | ±0.319 |
| `tradeProposalOpportunities` | 52.945 | ±3.645 |

| Opportunity-normalized behavior | Rate | Opportunities |
| --- | ---: | ---: |
| city choice when city and settlement were legal | 9.1% | 11 |
| development-card choice when a permanent build was legal | 1.5% | 262 |
| city chosen when buildable | 92.4% | 278 |
| trade acceptance | 46.2% | 4059 |
| knight use when playable | 15.1% | 5298 |
| highest-public-VP robber target when targets differed | 75.4% | 1489 |
| player-trade proposal | 38.0% | 13554 |

## Paired strength

| Arm | Build ID | Evaluated policy | Opponent policy | Pooled win rate | Decisive rate | Median moves |
| --- | --- | --- | --- | ---: | ---: | ---: |
| Candidate | `frozen-140f9f7ac53512671687e5d5b77b209a273af7858e6525877812710a81c1573d` | `heuristic-balanced` | `heuristic-balanced` | 64/256 = 25.0% | 256/256 = 100.0% | 503 |
| Baseline | `frozen-140f9f7ac53512671687e5d5b77b209a273af7858e6525877812710a81c1573d` | `upstream-v1-hybrid-greedy-swift-compounds-trade-scheduler-fallback-heuristic-balanced-declared-sha256-21f3b380786a53998172896caac44191dea3d44efd11d3bf8c92150d8b18c8a5` | `heuristic-balanced` | 25/256 = 9.8% | 256/256 = 100.0% | 477.5 |

- Paired win-rate difference: +15.2 percentage points
- Seed-cluster bootstrap 95% CI: +10.5 to +19.1 percentage points

## Paired differences from `upstream-v1-hybrid-greedy-swift-compounds-trade-scheduler-fallback-heuristic-balanced-declared-sha256-21f3b380786a53998172896caac44191dea3d44efd11d3bf8c92150d8b18c8a5`

| Opportunity-normalized behavior | Difference | Seed-cluster 95% CI | Candidate / baseline opportunities |
| --- | ---: | ---: | ---: |
| city choice when city and settlement were legal | -57.6% | -100.0% to +7.1% | 11 / 6 |
| development-card choice when a permanent build was legal | -39.4% | -46.4% to -32.3% | 262 / 247 |
| city chosen when buildable | -1.6% | -5.6% to +2.5% | 278 / 317 |
| trade acceptance | +0.3% | -2.6% to +3.3% | 4059 / 3946 |
| knight use when playable | -34.0% | -40.9% to -28.0% | 5298 / 1874 |
| highest-public-VP robber target when targets differed | +35.2% | +30.0% to +40.2% | 1489 / 1351 |
| player-trade proposal | -0.8% | -2.4% to +0.8% | 13554 / 11690 |

## Decision routes (evaluated chair only)

Selections include forced choices; these are not network inference-call counts.

- candidate: routes `{"policy": 40938}`; intentional fallbacks `{}`.
- baseline: routes `{"heuristic": 17660, "neural": 19393}`; intentional fallbacks `{"heuristic_trade_proposal": 4545, "player_trade_negotiation": 12437, "unsupported_pre_roll_development_card": 678}`.
