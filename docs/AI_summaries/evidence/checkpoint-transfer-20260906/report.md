# Smoke verification — not a strength claim

Development seeds; small sample. See manifest.json and run.watchdog.json.

# original-vs-r2-native-checkpoint-diagnostic

- Games: 128 (32 seed/config clusters × 4 seat rotations)
- Decisive: 128/128
- Wins: 74/128 = 57.8% (seed-cluster bootstrap 95% CI 46.9%–68.8%)
- Median moves: 434.5

| Behavior per game | Mean | 95% CI margin |
| --- | ---: | ---: |
| `roadsBuilt` | 4.781 | ±0.680 |
| `settlementsBuilt` | 0.852 | ±0.263 |
| `citiesBuilt` | 1.789 | ±0.168 |
| `developmentCardsBought` | 9.984 | ±1.262 |
| `knightsPlayed` | 5.508 | ±0.751 |
| `robberMoves` | 11.539 | ±1.348 |
| `bankTrades` | 15.547 | ±5.350 |
| `tradesProposed` | 39.992 | ±9.851 |
| `resolvedTradeAcceptances` | 0.000 | ±0.000 |
| `resolvedTradeRejections` | 0.000 | ±0.000 |
| `turnsEnded` | 35.641 | ±5.384 |
| `settlementCityOpportunities` | 0.031 | ±0.029 |
| `settlementsChosenInMixedBuildOpportunities` | 0.008 | ±0.015 |
| `citiesChosenInMixedBuildOpportunities` | 0.016 | ±0.021 |
| `cityBuildOpportunities` | 2.172 | ±0.412 |
| `citiesChosenWhenBuildable` | 1.789 | ±0.168 |
| `developmentCardBuildOpportunities` | 1.039 | ±0.254 |
| `developmentCardsChosenOverPermanentBuild` | 0.516 | ±0.233 |
| `tradeResponseOpportunities` | 0.000 | ±0.000 |
| `tradeResponsesAccepted` | 0.000 | ±0.000 |
| `proposalCardsGiven` | 56.320 | ±14.151 |
| `proposalCardsRequested` | 40.188 | ±9.872 |
| `playableKnightOpportunities` | 11.133 | ±1.749 |
| `knightsChosenWhenPlayable` | 5.508 | ±0.751 |
| `differentiatedRobberTargetOpportunities` | 9.391 | ±1.305 |
| `highestPublicVPRobberTargets` | 4.133 | ±0.842 |
| `tradeProposalOpportunities` | 101.977 | ±19.164 |

| Opportunity-normalized behavior | Rate | Opportunities |
| --- | ---: | ---: |
| city choice when city and settlement were legal | 50.0% | 4 |
| development-card choice when a permanent build was legal | 49.6% | 133 |
| city chosen when buildable | 82.4% | 278 |
| trade acceptance | not observed | 0 |
| knight use when playable | 49.5% | 1425 |
| highest-public-VP robber target when targets differed | 44.0% | 1202 |
| player-trade proposal | 39.2% | 13053 |

## Paired strength

| Arm | Build ID | Evaluated policy | Opponent policy | Pooled win rate | Decisive rate | Median moves |
| --- | --- | --- | --- | ---: | ---: | ---: |
| Candidate | `frozen-d77e862b5a34f3b67a88d7e33fb9fb43bd61f35d0de7eb1748b949c7f0775197` | `upstream-v1-hybrid-greedy-swift-compounds-trade-scheduler-fallback-heuristic-balanced-declared-sha256-21f3b380786a53998172896caac44191dea3d44efd11d3bf8c92150d8b18c8a5` | `greedy` | 74/128 = 57.8% | 128/128 = 100.0% | 434.5 |
| Baseline | `frozen-d77e862b5a34f3b67a88d7e33fb9fb43bd61f35d0de7eb1748b949c7f0775197` | `upstream-r2-hybrid-greedy-swift-compounds-trade-scheduler-fallback-heuristic-balanced` | `greedy` | 46/128 = 35.9% | 128/128 = 100.0% | 514 |

- Paired win-rate difference: +21.9 percentage points
- Seed-cluster bootstrap 95% CI: +10.2 to +32.8 percentage points

## Paired differences from `upstream-r2-hybrid-greedy-swift-compounds-trade-scheduler-fallback-heuristic-balanced`

| Opportunity-normalized behavior | Difference | Seed-cluster 95% CI | Candidate / baseline opportunities |
| --- | ---: | ---: | ---: |
| city choice when city and settlement were legal | +25.0% | -40.0% to +80.0% | 4 / 8 |
| development-card choice when a permanent build was legal | +48.0% | +33.3% to +60.3% | 133 / 374 |
| city chosen when buildable | -3.6% | -11.0% to +4.8% | 278 / 350 |
| trade acceptance | not observed | not observed | 0 |
| knight use when playable | -13.8% | -21.9% to -5.5% | 1425 / 507 |
| highest-public-VP robber target when targets differed | -2.2% | -13.8% to +9.0% | 1202 / 974 |
| player-trade proposal | +13.4% | +9.8% to +16.8% | 13053 / 12127 |

## Decision routes (evaluated chair only)

Selections include forced choices; these are not network inference-call counts.

- candidate: routes `{"heuristic": 5476, "neural": 15623}`; intentional fallbacks `{"heuristic_trade_proposal": 5119, "unsupported_pre_roll_development_card": 357}`.
- baseline: routes `{"heuristic": 3350, "neural": 18071}`; intentional fallbacks `{"heuristic_trade_proposal": 3135, "unsupported_pre_roll_development_card": 215}`.
