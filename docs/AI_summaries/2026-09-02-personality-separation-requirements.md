# Bot personality separation requirements

Date: 2026-09-02

Status: implementation gate

## Product decision

Personality and difficulty are separate product axes.

- **Personality** describes recognizable choices: what a bot tends to pursue,
  avoid, accept, and disrupt when several reasonable moves are available.
- **Difficulty** describes calibrated playing strength against a frozen
  reference. It remains deferred until the evaluation ladder can support an
  honest strength claim.

The names Balanced, Aggressive, and Cautious must not appear as player-facing
settings until their behavior is measurably distinct. A different name, color,
or line of dialogue is not evidence of a different play style.

## Player-visible contracts

### Balanced

- Makes no extreme commitment to expansion, consolidation, army, or trading.
- Falls between Aggressive and Cautious on every metric used to justify those
  labels; it is the midpoint policy, not a fourth unrelated strategy.

### Aggressive

- More often invests in development cards when a permanent build is also
  available, creating more opportunities to contest Largest Army.
- More often creates robber pressure by proactively playing an owned knight.
- Targeting the publicly leading opponent is a separate hypothesis and must
  not be inferred from raw robber frequency.
- More often chooses blocking or outward-expansion builds over consolidation
  when both are legal and similarly valuable.
- Is less willing than Balanced to accept a merely adequate player trade.

### Cautious

- More often asks another player before paying a poor bank rate when both
  conversions are available.
- May accept more genuinely useful player trades than Balanced, but that is a
  hypothesis rather than part of the shipping claim until measured.
- Prefers reliable resource conversion and existing production over speculative
  blocking or army investment when alternatives are similarly valuable.

## Functional acceptance criteria

1. Every policy decision is measured against the exact legal action mask the
   policy received. The evaluator must not reconstruct a different mask later.
2. Telemetry records both an opportunity denominator and the chosen action for
   every claimed behavior. Raw event totals remain diagnostic only.
3. Trade-response metrics count the responder's decision, not only the final
   accepted/rejected event attributed to the proposer.
4. Simulator output remains deterministic across separate processes and carries
   a bumped schema version when telemetry fields change.
5. Existing consumers of `GameSession.decideNext()` remain source-compatible;
   richer evaluation data is additive.
6. All personalities complete legal games across three- and four-seat tables,
   8/10/12-point targets, standard/random boards, and shown/random seat order.
7. No personality may intentionally choose an illegal or dominated action just
   to look different.

## Measurement acceptance criteria

1. Directional hypotheses and seed ranges are written before tuning is measured.
2. Each candidate rotates through every chair on the same held-out boards.
3. Report seed-cluster confidence intervals, decisive games, timeouts, median
   game length, and the simulator binary/source identity.
4. A personality claim requires its predeclared opportunity-normalized metric
   to differ from Balanced with a 95% interval excluding zero on held-out seeds.
5. Balanced must lie between Aggressive and Cautious for every metric used to
   market the opposing styles.
6. Strength is checked separately against the frozen anchor. A style change is
   rejected if its confidence interval crosses the predeclared regression
   tolerance, even when style separation succeeds.
7. Final player-facing validation is a blind recognition test: testers see no
   label and must identify the intended style above chance.

## Initial telemetry contract

The first instrumentation slice records:

- settlement-versus-city opportunities and choices;
- development-card-versus-permanent-build opportunities and choices;
- player-trade response opportunities and acceptances; and
- cards offered and requested in player-trade proposals.

Robber targeting uses highest public victory points as the first canonical,
player-visible threat definition. Topology-based blocking metrics follow as a
later slice and must not be approximated from raw road counts.

## Explicit non-goals for this stage

- No difficulty selector or strength label in the app.
- No RL training, LLM move inference, or model-provider dependency.
- No personality-specific dialogue presented as proof of strategic behavior.
- No hidden-information change; that remains a separate engine decision.
- No claim that a higher win rate among four current heuristics proves strength.
