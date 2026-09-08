# Neural/search research — retained findings and restart map

Decision: pause research and ship existing Balanced heuristics. This is a product
decision, not proof that neural search cannot work. Complete native reproduction
and expert play remain unfinished. This report preserves the next-reader context;
it does not authorize new runs.

## Findings

- Native four-player/10-VP direct competition, 192 games, eight boards/all 24
  chair orders: Balanced 133 wins, author's original network without search 28,
  our retrained network without search 25, simpler Greedy heuristic 6. All four
  shared each table. The retrained network did not outperform Balanced.
- Separate native three-player/8-VP full-search screen, 12 games/two boards:
  Balanced 7, original network plus 96-continuation search 5, original no-search 0.
  Too small to establish superiority; not the four-player leaderboard above.
- Adaptive-budget and Greedy-continuation pilots each lost their small native
  screens to Balanced. Rejected as delivery leads, not universal impossibility.
- Search helped in the author's Rust engine (Rust is the programming language):
  original search 137/192 versus no-search 32/192; retrained search 114/192 versus
  no-search 44/192. Each pair faced the author's two heuristics in separate pools.
  These do not compare native Balanced or original versus retrained directly.
- Exact optimizations reduced one M5 Pro Mac CPU opening from about 27 to 8.3
  seconds, approximately 3x. Not a 4090/iPhone measurement or a general speedup.
  No combined phone <=4-second and strength-retention target was demonstrated.
- Final four-player diagnostic at source `100a867` timed out at its original
  7,200-second bound: 31/48 games completed, exit 124, owned processes reaped.
  Missing chair orders mean no valid final Elo/ranking/confidence interval.
- Two deterministic upstream/native oracle cases agree. Stochastic full-game
  parity, phone timing/thermals, cancellation and stale-result handling remain
  unfinished. Training before completing the algorithm was premature.

## Durable evidence (verified archive, not temporary worktree dependency)

Archive root:
`/Users/alex/Library/Application Support/EmpiresResearch/handoffs/search-pause-20260908/`.

- `README.md`: index with terminal diagnostic and delivery pointers.
- `research.bundle`: complete frozen Git history; restore using
  `git clone research.bundle <new-checkout>`. SHA-256:
  `792fa80304a5d060c82e46ee016cec944ca6b0191ad9ec971826e0d16249429d`.
- `source/docs/AI_summaries/2026-09-07-search-speed-strength.md`: complete
  experiment protocols, findings, limits and restart checklist.
- `source/docs/AI_summaries/2026-09-06-reusable-evaluation.md` and
  `2026-09-07-search-ab-results.md`: native and upstream leaderboards, uncertainty
  and commands for reproducing reports without new inference.
- `terminal-diagnostic.md` and `terminal-evidence/`: final timeout, raw completed
  shards and receipts. Read after the immutable source snapshot, which predates
  the terminal event. Never rewrite that snapshot to update status.
- Full frozen executables, configs, model resources, logs and manifests remain in
  `/Users/alex/Library/Application Support/EmpiresResearch/experiments/`.
- Original `catan-512.ctnn` resides beneath
  `EmpiresResearch/catan-rl/original-v1/models/`, SHA-256
  `21f3b380786a53998172896caac44191dea3d44efd11d3bf8c92150d8b18c8a5`.

Before reopening, read [the current plan](AI-PROGRAM.md), restore pinned source,
verify model and artifact hashes, and reuse its evaluation/leaderboard scripts.
Choose compatible rules and opponents, rotate chairs, retain whole-board
uncertainty and failures, and declare the deadline plus watcher before launch.
Research PRs are not approved product code merely because their artifacts exist.
