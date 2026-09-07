# Is omitted AlphaBot search the next experiment?

2026-09-06 investigation, reconciled September 7. No training, benchmarks or policy edits in this note. Remote primary links verified by browsing.
Upstream pin: `021279c56834b6203480e5292e1de7246e47bd68`; inspected files match HEAD.
Original CTNN SHA-256, verified locally: `21f3b380786a53998172896caac44191dea3d44efd11d3bf8c92150d8b18c8a5`.
Native source inspected at `d38443e7ed7579c6f75e8fcfbafef231bd43bd71`.

**Recommendation: conditional GO for a small search-feasibility experiment before more r2 training or speculative heuristic tuning; NO-GO for a substantial port or promotion now.**
This is a priority judgment about what to learn next, not evidence that search improves Empires.
The [completed native comparison](2026-09-06-balanced-original-decision.md#result) selected Balanced in both opponent groups. New-game integration PR #40 is DRAFT, not shipped; original weights in the native adapter do not include AlphaBot search.
The [current tracker](AI-PROGRAM.md) and the native source below distinguish these facts.

**What the upstream evidence establishes.**
The author's [experiment ledger][ledger] reports reactive PPO around 65%, policy-guided long rollouts at 82%,
and short/value-leaf variants at 38.3%, 15.8% and 25.8%, against three upstream Heuristic-v1 opponents.
More training and wider networks did not improve that historical gate materially.
These are small author experiments (search variants: 120–150 games); entropy and opponent changes shared one run.
They motivate a planning hypothesis, not a proof that training cannot help or that architecture caused a plateau.
The ledger declares four players, seven VP and perfect information.
Our prior [upstream execution record](2026-09-05-public-catan-reproduction-log.md#eli6th-executable-result)
reports 157/192 AlphaBot wins in fixed chair 0, but the executable used ten VP:
[CLI construction][cli] calls the [engine's ten-point default][state].
That is upstream-engine evidence, not an exact historical-protocol replication or an Empires result.

**What the existing native evidence establishes.**
Earlier separate matched Greedy groups found r2 below Balanced (52/128 versus 112/128)
and below original (46/128 versus 74/128). Both used four players, randomized boards, ten VP, all chairs, and 32 development seeds per arm;
see the retained [Balanced/r2 report](evidence/neural-evaluation-20260906/report.md)
and [original/r2 report](evidence/checkpoint-transfer-20260906/report.md), including paired intervals.
The new 64-board comparison also favors Balanced over original in both Greedy and Balanced groups; stop simply extending r2 training.
The [saved purchase witness](evidence/native-cap-diagnosis-20260906/candidate-move-873.json)
and [diagnosis](2026-09-06-native-cap-diagnosis.md#candidates-narrower-decision-witness)
show a different target-adaptation checkpoint choosing end turn with buy-card legal at nine VP.
It supports investigating decision-making; it does not prove original has the same failure.
No demonstrated heuristic defect here justifies an immediate weight change, and no opponent is certified expert.

**Exact upstream search and a cheaper adaptation are different experiments.**
[AlphaBot source][alpha] ranks legal roots by policy logit, usually excludes trade proposals,
then averages random playout scores for each retained root; it is flat search, not tree MCTS.
The [published command][readme] is `8,96,300`: up to 768 rollouts per decision.
“Full” in the ledger is approximate: code stops at 300 additional turns or absolute turn 1,000;
terminal scores are actor-relative ±1, absolute-cap scores zero, other unfinished leaves use the critic.
Depth zero means the actor's next qualifying decision, not no search.
The author's [approximately 50-ms Rust decision claim][performance] is not measured Swift or phone latency.
A smaller root/sample budget, different chance handling, native compound moves or shorter horizon cannot inherit 82%.

**What search can and cannot recover.**
[UpstreamActionScorer](../../Packages/CatanAI/Sources/CatanAI/UpstreamActions.swift) deduplicates/sorts allowed IDs,
returns singletons directly, otherwise takes their highest finite logit; it never uses the value.
[UpstreamPolicy](../../Packages/CatanAI/Sources/CatanAI/UpstreamPolicy.swift) checks all non-trade roots map,
then resolves one chosen root through [compound completion](../../Packages/CatanAI/Sources/CatanAI/UpstreamCompounds.swift).
An unmapped non-trade root triggers fallback, not silent pruning. Buy-card is directly mapped to 295.
Search can overturn greedy preference only among candidates it actually evaluates.
It cannot recover moves absent from the supplied legal mask, upstream-excluded proposals, a scheduled heuristic trade,
unsupported pre-roll decisions, roots below top-K, or alternate compound completions never generated.
The two-root purchase witness fits K≥2; earlier expansion decisions need a root-rank/coverage check. Widening roots or changing compound/trade selection would be a separate intervention.

**Reuse and the necessary changes.**
Reuse the pinned CTNN loader and [Network](../../Packages/CatanAI/Sources/CatanAI/UpstreamNetwork.swift)
(1,350 inputs, 299 logits plus clamped value), observation/layout codec, compound completion and fallback reasons.
Reuse value-copy GameState and [native legal/apply rules](../../Packages/CatanEngine/Sources/CatanEngine/RulesEngine.swift),
with the existing evaluator's frozen builds, audit records and analyzer; a new production harness is unnecessary. A small experiment still needs ranked roots and a bounded native rollout selector: these do not exist in the scorer.
Preserve [session](../../Packages/CatanEngine/Sources/CatanEngine/GameSession.swift) trade responses, turn backstop,
actor routing and victory timing; do not reconstruct unknown session counters as zero.
Uniform native bundled moves also differ from upstream uniform atomic actions; declare that rollout distribution.
Critical inference from [cloned upstream state][state] and [deck draws][cards]:
literal cloning preserves future RNG/deck order. Native [features](../../Packages/CatanAI/Sources/CatanAI/UpstreamObservation.swift)
omit those futures although GameState contains them. Resample simulation-only chance and undealt order from the
allowed information using a separate reproducible stream; do not inspect the real next card or advance live dice.
Keep perfect hand visibility fixed. The existing PPO critic is not a validated native outcome evaluator.

**Practical stop gate, proposed only; no run authorized or performed here.**
Before significant porting/training, cap a disposable saved-state probe at 10 CPU-minutes / 15 wall minutes, no GPU.
Use up to 12 fixed states spanning expansion, purchases, compounds and trade boundaries; known witnesses are diagnostic seeds.
Candidate proposal: top four distinct mapped roots, eight random terminal-seeking rollouts each, native 3,000-move ceiling;
keep current greedy compound resolution and trade/fallback routing. Average actor-relative terminal ±1 scores only when every candidate batch completes.
GO only if legality/session/chance contracts hold, cross-process decisions repeat, relevant alternatives survive pruning,
and ≥90% of decisions finish all their rollouts, with measured total decision p95 ≤250 ms and hard stop ≤500 ms on the target phone.
Also bound cumulative thinking to two seconds per bot turn; a many-action turn can defeat a per-decision budget.
Use fixed work counts for reproducibility; any truncated rollout or deadline abort returns the original greedy choice and is counted, never scored as a win.
If the phone is unavailable, latency feasibility remains unpassed. Rust timing or simulator timing cannot substitute. If even this small terminal-rollout budget fails, stop this candidate; do not quietly shorten to the failed critic recipe,
launch value retraining, widen roots or optimize an engine. Current gate status: UNPASSED, costs unknown.

**If the gate passes, one comparison; proposed only.**
Freeze original CTNN, native rules/encoding/compound/trade behavior and Greedy opponents; change only the root selector:
original greedy versus original plus the one fixed search configuration above. Use existing frozen-build/analyzer paths.
Propose 16 fresh, unused boards × four chairs per arm, four players/ten VP/randomized, at most 60 CPU-minutes /
30 wall minutes with two workers. This is an exploratory screen, not power to establish a small strength gain.
Predeclare +10 percentage points as a worthwhile lead, no completion regression, and the latency limits above. Any promising lead must then face Balanced on fresh boards before it can challenge the product baseline; beating the weaker original alone is insufficient.
Report paired seed-cluster 95% intervals, caps, fallback/abort counts and actual CPU/phone cost; retain partial failures.
A small or uncertain result is inconclusive, not equivalence; no retries or promotion follow automatically. Apply the [bot-strength method](../../.claude/skills/bot-strength/SKILL.md); other tables/rules require separate evidence.

[ledger]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/training/results/EXPERIMENTS.md
[alpha]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-env/src/alpha.rs
[readme]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/README.md
[performance]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/docs/PERFORMANCE.md
[cli]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-sim/src/main.rs
[state]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-core/src/state.rs
[cards]: https://github.com/Eli6th/catan-rl/blob/021279c56834b6203480e5292e1de7246e47bd68/rust/catan-core/src/dev_cards.rs
