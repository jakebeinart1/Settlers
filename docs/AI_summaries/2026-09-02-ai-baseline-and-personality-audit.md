# AI baseline and personality audit

Date: 2026-09-02

Candidate source commit: `a987a25` (`codex/ai-baselines`)

Frozen pre-change system: commit `2437cbf`

Frozen simulator SHA-256: `442da017e6a7111974c53b467b4a0b7ff1380c53d9e6438ee5cb541dd5e8733c`
Candidate simulator SHA-256: `41e9186043a5d0cc246597b2b900f8b7a2cf7938560f61ae05d9c3d06c92615a`

## Decision

The current heuristic remains the shipping policy. We are not exposing AI
difficulty yet, because no calibrated difficulty ladder exists. We are also
not claiming that Balanced, Aggressive, and Cautious are perceptibly different:
their measured behavior overlaps too much. The next AI change must first define
and demonstrate behavioral separation without conflating personality with
strength.

This audit found and fixed a more fundamental problem: bot-to-bot proposals
were never answered. `GameSession` returned control to the active proposer, so
the offer disappeared at end turn before another bot could respond. The shared
session now queues a legal policy response before the proposer continues. A
policy receives an explicit response-only action mask, which is also the seam a
future search, RL, or language-model policy must honor.

## Protocol

- Randomized boards, deterministic policy RNG, and one JSONL record per game.
- Every candidate rotates through all four chairs against the same opponents.
- Strength-regression seeds: 20000–20039; 160 games per personality against
  three Greedy policies. The policy source is unchanged, but it runs through
  the candidate session; this is a system-level regression check, not a
  frozen-binary head-to-head experiment.
- Behavior seeds: 30000–30039; 160 games per personality against three current
  Balanced policies.
- A result is decisive only when `GameSession` reaches `.gameOver`; timeouts are
  reported rather than silently counted as losses.
- Intervals treat each of the 40 shared board seeds as the independent unit;
  four chair rotations from one board are one cluster. Unfinished games are
  reported separately and excluded from the win-rate denominator.
- The fixed fingerprints were independently reproduced in three separate
  Release processes for seeds 1, 7, 42, 99, and 1234.

The checked-in analyzer consumes the simulator output and selects only the
candidate chair from each shard:

```bash
python3 scripts/analyze-bot-evaluation.py --name balanced \
  --build-id sha256-41e9186043a5d0cc246597b2b900f8b7a2cf7938560f61ae05d9c3d06c92615a \
  --candidate-policy heuristic-balanced \
  --foil-policy greedy \
  /path/to/balanced-seat{0,1,2,3}.jsonl
```

## Strength regression result

| Personality | Wins | Win rate | Seed-cluster bootstrap 95% CI | Decisive | Median moves |
| --- | ---: | ---: | ---: | ---: | ---: |
| Balanced | 135/160 | 84.4% | 78.8%–90.0% | 160/160 | 389 |
| Aggressive | 136/160 | 85.0% | 79.4%–90.6% | 160/160 | 393 |
| Cautious | 130/160 | 81.2% | 75.0%–87.5% | 160/160 | 377 |

The post-fix win counts exactly match the pre-fix system on the same seeds and
seat rotations. That is a system-level regression smoke result: no strength
change was detected while enabling live responses. It is not an isolated
policy comparison and not evidence that the change made the bots stronger. The
intervals overlap, so these data do not establish a strength ordering among the
personalities.

## Behavioral result

| Metric per game | Balanced | Aggressive | Cautious |
| --- | ---: | ---: | ---: |
| Roads built | 9.369 ±0.557 | 9.519 ±0.505 | 9.281 ±0.461 |
| Settlements built | 2.031 ±0.207 | 2.050 ±0.192 | 2.081 ±0.196 |
| Cities built | 1.038 ±0.173 | 1.006 ±0.172 | 1.163 ±0.191 |
| Development cards bought | 5.694 ±0.277 | 5.675 ±0.269 | 5.438 ±0.297 |
| Knights played | 2.931 ±0.207 | 2.900 ±0.207 | 2.794 ±0.218 |
| Robber moves | 7.069 ±0.663 | 7.019 ±0.655 | 7.006 ±0.617 |
| Bank trades | 7.394 ±0.943 | 7.537 ±0.928 | 8.069 ±0.873 |
| Player trades proposed | 14.394 ±1.148 | 14.281 ±1.116 | 14.694 ±0.978 |
| Resolved trade acceptances | 6.162 ±0.547 | 5.925 ±0.502 | 6.156 ±0.453 |
| Resolved trade rejections | 8.231 ±0.934 | 8.181 ±0.926 | 8.200 ±0.928 |
| Turns ended | 23.919 ±1.713 | 23.856 ±1.614 | 24.075 ±1.380 |

The live-trade path is now active—mixed smoke games produced 48–56 proposals
and 22–29 acceptances—but almost every personality interval overlaps. The names
therefore describe tuning intent, not a demonstrated player experience.

## Acceptance bar for personality work

Before changing weights, define a small set of player-visible traits. A future
candidate is acceptable only if:

1. its intended behavior differs from Balanced on predeclared metrics with a
   confidence interval that excludes zero;
2. the difference repeats on held-out seeds and from every chair;
3. all games remain legal, decisive, deterministic, and within the move cap;
4. its strength against the frozen anchor does not regress beyond a declared
   tolerance; and
5. blind human playtesting can identify the intended style above chance.

Aggressive should be tested on expansion pressure, opponent blocking, and army
competition—not merely raw win rate. Cautious should be tested on city timing,
resource conversion, and risk-adjusted trades. Personality and difficulty stay
separate axes.

## Model-path decision gate

No RL or LLM implementation should start until the heuristic baseline and
evaluation corpus are trustworthy. Then compare approaches against the same
`GameObservation`/`ActionSpace` contract:

- Heuristic/search: cheapest and easiest to debug; strongest immediate control
  over style, but likely capped below expert play.
- RL/self-play: plausible for tactical strength, but requires a correct masked
  action interface, reward/evaluation discipline, and substantial training.
- LLM policy: useful for explanation, negotiation voice, and perhaps strategic
  proposals; direct per-move inference has latency and cost risks.
- Hybrid: deterministic policy for legal/tactical play, with an LLM restricted
  to personality text or high-level intent, is the first architecture worth
  prototyping after the baseline work.

This is a gate, not a final algorithm selection. The next experiment should be
small, measurable, and reversible.
