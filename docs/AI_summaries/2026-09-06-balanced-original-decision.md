# Balanced versus the published model: baseline decision

**Question:** which existing bot deserves the next improvement effort in Empires?
This protocol is recorded before running any of its games. No training or policy
change is part of this comparison.

## Fixed comparison

- Existing Balanced versus the author's original published CTNN, SHA-256
  `21f3b380786a53998172896caac44191dea3d44efd11d3bf8c92150d8b18c8a5`.
- Same native engine/adapter, reveal-all information, four players, ten points,
  randomized boards, held-out seeds **962001–962064**, all four seat rotations.
- Two separate opponent groups: three Balanced bots, then three Greedy bots.
  Report each group independently, not a pooled claim of universal strength.
- Each group plays Balanced first, then the original model: 256 games per bot,
  512 per group, **1,024 planned games** total. All-Balanced must yield exactly
  25% for its designated rotated seat when every game completes.
- The original model uses the same native neural adapter and declared heuristic
  trade/pre-roll fallback as earlier tests. This is **not AlphaBot search**, a
  reproduction of its full upstream system, or a human-opponent evaluation.
- Reuse `scripts/evaluate-bots.py` and the two named configs in
  `config/evaluation/`. Its `purpose: smoke`/report label remains unchanged:
  this prospective screen selects a next baseline; it does not certify expert
  strength, all game configurations, or a product difficulty tier.

## Budget and stop rules

Each config has its existing independent **600-second** process-group watchdog,
including build, games and analysis. Run groups sequentially, exactly once each,
even if the first group fails; do not alter sources between them. Launch neither
after **2026-09-07 00:00 UTC**; both must be terminal by **00:10 UTC**. The current
thread supervises actively; heartbeat `verify-empires-evaluation-ci` is enabled
before launch as backup, quiet unless completion/failure requires action.

Retain raw games, route audits, config/source/artifact hashes, commands and
terminal receipts. Do not weaken the existing cap/fallback checks or retry failed
shards. A cap/timeout prevents an adoption verdict; report any unplayed remainder.
No new GPU run, checkpoint selection or evaluation extension is implicit here.

## Decision made from the result

- A difference of **10 percentage points** in each opponent group is the practical
  selection threshold. Require all games complete, clean route audits, and the
  existing seed-cluster 95% difference interval exclude zero in that direction.
- If Balanced wins both groups by this rule: keep it as the app/improvement
  baseline; stop further r2 continuation/target adaptation. Only a separately
  justified experiment from the stronger published model or its omitted search
  deserves new research budget; do not assume more training improves it.
- If the original wins both: use it as the next neural research baseline;
  retain Balanced as the control. App promotion still needs supported settings,
  gameplay/latency checks and review; this screen does not authorize a default swap.
- Mixed/close outcomes: retain Balanced in the app and report a context-dependent
  or inconclusive ranking. No forced winner, pooled average or adaptive rerun.
- Before more training, record which earlier PR work to keep versus archive.
  Failed experiment findings are worth retaining, not shipping as improvements.

## Result

Not run yet. The current hypothesis does not predict a winner.
