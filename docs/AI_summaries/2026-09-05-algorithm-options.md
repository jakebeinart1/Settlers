# Algorithm options for Empires AI

**Date:** 2026-09-05

**Status:** research map; no algorithm selected

**Question:** What algorithm families are plausible for a stochastic, turn-based,
three- or four-player Catan-like game with hidden hands, negotiation, chance,
long horizons, and a large legal-action mask?

## Scope and evidence rule

This note compares options and defines experiments that can falsify them. It
does **not** choose a winner, prescribe a production architecture, or treat a
result from another game as evidence that the same method will work in Empires.

Sources are limited to original papers, author/institution copies of those
papers, and official project source or documentation. Secondary surveys,
blog summaries, Reddit claims, and vendor comparisons are excluded. The source
search was completed on 2026-09-05.

The most important evidence boundary is that no Catan result reviewed here
matches the whole Empires problem:

- Gendre and Kaneko train on **two-player Catan without player trading**, then
  identify four-player trading as future work
  ([paper](https://arxiv.org/abs/2008.07079)).
- Szita, Chaslot, and Spronck apply MCTS to a **perfect-information** Catan
  variant and omit negotiation
  ([paper](https://doi.org/10.1007/978-3-642-12993-3_3)).
- Dobre and Lascarides study four-player play and trading, but explicitly make
  hands visible and leave imperfect information to future work
  ([paper](https://www.pure.ed.ac.uk/ws/portalfiles/portal/31304332/final_2.pdf)).
- Cuayáhuitl, Keizer, and Lemon learn only trade offers and responses; JSettlers
  supplies the rest of each player's behavior
  ([paper](https://arxiv.org/abs/1511.08099)).
- The public MIT-licensed [`catan-rl`](https://github.com/Eli6th/catan-rl)
  project is useful implementation evidence. Its historical 82% protocol is
  still an author report, but the current first-party evaluator was executed
  locally at 83/100 and 157/192 (81.8%). That is not an exact reproduction:
  the ledger says first-to-7, while the current CLI has no victory-target flag
  and uses the engine's 10-point default. The reported experiment uses four
  players, perfect information, frozen heuristic opponents, and a restricted
  trade grammar
  ([experiment ledger](https://github.com/Eli6th/catan-rl/blob/main/training/results/EXPERIMENTS.md),
  [engine scope](https://github.com/Eli6th/catan-rl/blob/main/rust/README.md),
  [reproduction log](2026-09-05-public-catan-reproduction-log.md)).

Those studies are useful feasibility evidence for individual components. None
is a transfer guarantee for a three- or four-player game containing all of the
features at once.

## 1. What problem is actually being solved?

### 1.1 Formal model

The closest general formalism is a finite-horizon **partially observable
stochastic game** (POSG), or equivalently a procedural extensive-form game with
chance and imperfect-information sets. A POSG gives every player its own
actions, observations, reward, and belief over states and other players'
future plans. Exact finite-horizon POSG dynamic programming exists, but even
the original paper only establishes optimality for the special shared-payoff
case and emphasizes the growth of conditional strategies
([Hansen, Bernstein, and Zilberstein, 2004](https://aaai.org/papers/ws04-08-005-dynamic-programming-for-partially-observable-stochastic-games/)).
Even the cooperative decentralized special case is NEXP-hard for two agents
([Bernstein et al., 2002](https://doi.org/10.1287/moor.27.4.819.297)). These are
complexity warnings, not claims that practical approximation is impossible.

Empires combines six sources of difficulty:

1. **Multiple strategic players.** Every chair maximizes its own outcome; an
   opponent is not a stationary environment during self-play.
2. **Imperfect information.** Exact opponent resources and development cards
   are private, while hand sizes, purchases, public pieces, offers, and prior
   actions provide evidence about them.
3. **Chance.** Dice, random steals, development-card order, and randomized
   boards create explicit chance nodes.
4. **Long, variable horizons.** A locally sensible move may affect production,
   access, threats, and trades hundreds of decisions later.
5. **A sparse combinatorial action space.** Most global action indices are
   illegal in any one state, and compound discards, road pairs, robber victims,
   and trades have internal structure.
6. **Negotiation.** An offer is valuable only through another policy's response;
   a mutually useful trade can also improve a future rival.

### 1.2 Constant-sum is not the same as two-player zero-sum

If evaluation awards the sole winner 1 and every loser 0, terminal utility sums
to 1. That is an **n-player constant-sum** objective. It does not make a
three- or four-player game reducible to ordinary two-player minimax: coalitions,
kingmaking, threat response, and bilateral trades remain player-specific.
`max^n` was introduced precisely because n-player perfect-information search
backs up a utility vector rather than one maximizing/minimizing scalar
([Luckhardt and Irani, 1986](https://cdn.aaai.org/AAAI/1986/AAAI86-025.pdf)).

The practical learning problem becomes general-sum as soon as training adds
non-constant shaping rewards, human-likeness, trade reciprocity, personality
goals, or different per-player objectives. In many-player stochastic games,
even choosing a solution concept is substantive; Nash computation is generally
intractable, and weaker correlated-equilibrium targets require assumptions of
their own
([Brown, 2021](https://proceedings.mlr.press/v161/brown21a.html)). Therefore
“converged in self-play” cannot stand alone as a correctness claim.

### 1.3 Observation is not just the current board

A policy that may not peek needs an **information state**, not merely a masked
snapshot. Two worlds can look identical now but imply different beliefs because
the player observed different prior production, spending, stealing, and trade
messages. Recurrent policies can carry an action-observation history; belief
models can estimate a distribution over hidden hands; tabular extensive-form
methods require information sets with perfect recall. OpenSpiel's official game
API makes the same distinction and requires information states to be
perfect-recall representations
([source documentation](https://github.com/google-deepmind/open_spiel/blob/master/open_spiel/spiel.h)).

This is a prerequisite decision. Masking private values in one vector prevents
direct leakage, but it does not automatically provide the public history needed
for rational inference.

### 1.4 “Best AI” is not one objective

The following product goals must be evaluated separately:

- **Strength:** maximize win probability against a declared opponent
  population.
- **Robustness:** avoid policies that one counter-strategy can exploit.
- **Human-likeness:** remain inside a plausible human behavior distribution.
- **Difficulty:** provide measurably ordered strength tiers.
- **Strategic personality:** make different, persistent choices while obeying
  the same rules and remaining reasonably competitive.
- **Voice:** express a character consistently in text.
- **Fun:** finish games, trade enough to be social, avoid loops and spiteful or
  inexplicable play, and operate at humane latency.

A method can improve one and regress another. No experiment below may collapse
them into a single “AI quality” number.

## 2. What Empires already provides

The current repository is unusually well positioned for controlled probes, but
it is not yet a complete imperfect-information research environment.

| Capability | Current contract | Consequence for research |
| --- | --- | --- |
| One rules path | [`GameSession`](../../Packages/CatanEngine/Sources/CatanEngine/GameSession.swift) drives app and simulation policies through one `Policy.decide` seam. | Heuristics, search, learned policies, and LLM adapters can be compared without rebuilding the game loop. |
| Exact simulator | [`RulesEngine`](../../Packages/CatanEngine/Sources/CatanEngine/RulesEngine.swift) applies legal moves; engine and policy RNG streams are explicit. | Model-free and model-based methods can both be tested. A learned dynamics model is optional, not required to obtain a simulator. |
| Numeric state | [`StateEncoding`](../../Packages/CatanEngine/Sources/CatanEngine/StateEncoding.swift) layout v3 emits 5,182 fixed-width features for three- and four-seat games. | A trainer has a versioned input contract, but must record the hidden-information policy and decide whether history/belief is needed. |
| Text state | The same encoder emits a compact prompt and numbers only the current observation's legal moves. | An LLM can select among a small local list without inventing a global move id. |
| Global action space | [`ActionSpace`](../../Packages/CatanEngine/Sources/CatanEngine/ActionSpace.swift) layout v2 provides a move/index bijection and legal mask. Its executable test pins **9,335** indices. | Flat policy heads are possible, but action factorization and category sampling remain open. Documentation-only corrections made with this audit now agree with the tested value; artifact generation must still fail on version mismatch. |
| Hidden-information switch | The encoder supports `.revealAll` and `.publicCountsOnly`, while `GameObservation.state` still contains the full state. | A policy can still peek unless its adapter is constrained to a masked encoding. The public observation/history boundary must be enforced, not assumed. |
| Baseline policies | [`CatanAI`](../../Packages/CatanAI/Sources/CatanAI/Bot.swift) ships transparent heuristics with balanced, aggressive, and cautious parameters. | Every learned or search candidate has a frozen functional baseline and interpretable behavior counters. |
| Reproducible data | The simulation/export path records layout versions, legal masks, policy decisions, provenance, and cross-process fingerprints. | Paired common-seed comparisons and exact replay are available before expensive training. |

Existing local experiments are also prior evidence, not a conclusion about the
families themselves:

- A phase-conditioned masked prior achieved 31.5% held-out top-1 imitation
  accuracy versus 14.1% for uniform legal choice.
- A small state-conditioned imitation model improved to 42.4% top-1, yet went
  **0/40** in complete games against frozen greedy anchors.
- Its value model's 67.7% sign accuracy lost to a 74.0% majority comparator.
- A 3,360-game difficulty-anchor run exposed completion failures and rejected
  the proposed product tier despite several strong matchup results.

The full protocols and provenance are in
[`2026-09-03-ai-approach-evaluation.md`](2026-09-03-ai-approach-evaluation.md).
The lesson is narrow but important: legal masked prediction accuracy and a
decreasing regression loss are not substitutes for complete-game behavior.

## 3. Comparison at a glance

The entries below describe native fit and required adaptation. “Low” cost is
relative to the other families, not a promise before profiling this engine.

| Family | Hidden information | 3–4 player / non-zero-sum | Chance and long horizon | Large legal action set | Training/sample cost | Shipping latency/cost | Explainability and personality |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Transparent heuristics | Only if inputs are masked; explicit beliefs can be hand-built | Native utility vector or threat rules, but strategically brittle | Chance handled by analytic odds or simulation; long horizon must be designed | Scores only legal moves; category logic is natural | None; tuning/evaluation still costs games | Very low, local, deterministic | Strongest causal audit trail; direct personality knobs |
| Expectimax / `max^n` / adversarial search | Not native; requires beliefs, determinization, or information-set search | `max^n` is native to n-player utility vectors; “everyone versus me” paranoid search changes the game | Exact chance nodes are natural; depth explodes over long horizons | Needs aggressive ordering, pruning, abstraction, or hierarchical moves | No model training; high per-decision simulation cost | Potentially high and variable; local | Candidate values and principal variations are inspectable; personality via utility/evaluator/opponent model |
| MCTS | Plain MCTS peeks; ISMCTS searches information sets; POMCP samples a belief | Vector backups work, but do not create a general-sum equilibrium guarantee | Sampled chance and long rollouts are native | Progressive widening, action categories, priors, or sampled actions are usually needed | Online simulations; learned priors add training | Anytime but tail latency can be large | Visit/value statistics are inspectable; explanation still depends on rollout/evaluator quality |
| CFR / MCCFR / NFSP | Native extensive-form treatment if information sets and perfect recall are correct | Strong Nash guarantee is for two-player zero-sum; multiplayer guarantees/targets are weaker | Chance is native; full long-horizon tree is the scaling problem | Action abstraction and sampling required | Often high memory/iterations; NFSP adds neural training | Distilled/average policy can be cheap; online solving is not | Regret tables are auditable in small abstractions; personality is awkward unless explicitly constrained |
| AlphaZero / Gumbel / MuZero style | Original recipe is perfect-information; needs belief/public-state redesign | Original result is two-player; n-player backups or equilibrium search are adaptations | Search plus policy/value handles long horizons; exact chance needs explicit treatment | Masking works; Gumbel and sampled-action variants reduce root/action budget | High self-play and repeated search | Network alone is cheap; search budget controls latency | Search statistics help; learned value is less causal; style conditioning is possible |
| Actor-critic / PPO self-play | Masked recurrent or belief-conditioned policy is required | Directly trainable, but independent self-play is non-stationary and has no general equilibrium guarantee | Sampled chance is automatic; sparse terminal credit is difficult | Legal masking plus flat, autoregressive, or hierarchical heads | Usually high and seed-sensitive; on-policy PPO discards old-policy data quickly | One local forward pass can be cheap | Feature attribution is limited; conditioned rewards/latents can express style but may leak into strength |
| League / PSRO population training | Depends on the oracle policy | Designed to reduce overfitting to one opponent and expose cycles | Inherits oracle's handling | Inherits oracle's handling | Multiplies training and evaluation cost | Final mixture/selector can be cheap | Population roles can encode styles; a mixture needs a user-facing identity rule |
| Imitation / offline RL | Learns only the information present in the logs | Copies the logged population; no equilibrium guarantee | Long-horizon distribution shift is the central risk | Masked classification is straightforward | Efficient if high-quality representative data exists | Usually one cheap local forward pass | Human clusters can support style; behavior cloning is easy to audit statistically, not causally |
| LLM move policy | Safe only if the prompt is masked and contains permitted history | No game-theoretic guarantee; can model language and opponents in context | Can verbalize plans, but exact long-horizon game reasoning is unproven here | Best grounded to an enumerated legal list or tool, not free-form moves | Little task training for API use; fine-tuning/local models add data and compute | Cloud calls add money, network dependence, and long-tail latency; local models add memory/app-size cost | Strong voice control; generated rationales are not automatically faithful explanations |
| Hybrid architecture | Can put one enforced information boundary in front of all modules | Can combine opponent population, vector value, and separate negotiation policy | Exact simulator/search can cover what a learned prior misses | Natural place for category proposal, learned reranking, and legal validation | Ranges from low to very high | Route forced/easy moves cheaply and deliberate only when useful | Best opportunity to separate strategy, difficulty, personality, and speech; also the most integration risk |

## 4. Family-by-family analysis and falsifiers

### 4.1 Transparent heuristics

**Mechanism.** Enumerate legal moves, compute named strategic features, weight
them, and choose or sample from the resulting scores. A planner can expose
intermediate goals such as “reach this vertex,” “deny this production tile,” or
“hold resources for a city.” JSettlers2 remains an official open-source example
of a hand-built Catan implementation with robot opponents
([official source](https://github.com/jdmonin/JSettlers2)).

**Fit.** Heuristics naturally consume the exact legal list, use analytic dice
odds, run locally, and preserve deterministic replay. They are the easiest way
to guarantee that aggressiveness, trade appetite, expansion, and risk tolerance
mean named things. They are also the easiest family to instrument with a causal
decision ledger: candidates, feature contributions, rejected constraints, and
the winning score.

**Limits.** Local scores can conflict, hand-tuned scales drift, and unseen
interactions create bizarre roads or trade refusals. Long-horizon value is
usually approximated through manually chosen subgoals. More parameters do not
automatically make the policy more intelligent; they can make it less
identifiable.

**Small falsifiable probe H.** Build a frozen corpus of 60 states: ten each for
initial placement, road planning, city/settlement choice, robber movement,
trade response, and endgame closure. Each state has allowed choices, forbidden
pathologies, and one or more acceptable rationales. A heuristic revision
proceeds only if it:

- returns a legal move in every case;
- removes the targeted pathology without regressing any previously passing
  case;
- emits a score decomposition that exactly recomputes the selected score; and
- changes only its declared personality metric in a paired simulation pilot.

Failure means revise the explicit model or stop; it does not justify adding
weights until the cases pass.

### 4.2 Adversarial search, expectimax, and `max^n`

**Mechanism.** Minimax assumes an adversary minimizes the focal player's scalar
utility. Expectimax inserts probability nodes and backs up expected values;
`*-minimax` provides pruning for games with chance but explicitly assumes no
concealed information
([Ballard, 1983](https://doi.org/10.1016/S0004-3702%2883%2980015-0)). `max^n`
backs up an n-component payoff vector, with each acting player selecting the
child maximizing its own component
([Luckhardt and Irani, 1986](https://cdn.aaai.org/AAAI/1986/AAAI86-025.pdf)).

**Fit.** The exact Empires simulator can supply successors and explicit dice
probabilities. Shallow search is attractive for tactical questions with short
resolution: can a road reach a settlement, can a trade immediately enable a
city, or which robber move has the best one-roll impact?

**Limits.** Full-width chance expansion, 3–4 utility components, hundreds of
actions, and a 9,335-slot global space make exhaustive depth tiny. `max^n`
assumes the leaf evaluator and modeled opponents choose their own component;
paranoid search assumes all opponents coordinate against one seat. Both are
modeling choices, not neutral facts. Neither handles hidden hands without a
belief or information-set layer. A depth-limited result can reverse when the
horizon expands, so “searched farther” must be measured rather than assumed.

**Small falsifiable probe S.** Construct three reduced games whose complete
trees fit in memory: one exact dice/build game, one three-player blocking game,
and one hidden-card trade game represented by a tiny belief. Exhaustive
enumeration is the oracle. A candidate implementation proceeds only if:

- expectimax matches exact expected values at every chance state;
- `max^n` matches the oracle utility vector at every perfect-information state;
- hidden states are never supplied as ground truth to the acting policy; and
- increasing depth on the reduced games converges to the oracle rather than
  oscillating because of a bookkeeping or perspective error.

Only after this should the same code receive a strict node/time budget on full
Empires states.

### 4.3 MCTS, ISMCTS, and POMCP-style planning

**Mechanism.** UCT uses upper-confidence bandits to focus Monte Carlo rollouts;
its original consistency and finite-sample analysis is for finite-horizon or
discounted MDPs with a generative model
([Kocsis and Szepesvári, 2006](https://doi.org/10.1007/11871842_29)). Ordinary
MCTS over the actual `GameState` would see all hands. Two relevant adaptations
are:

- **ISMCTS:** aggregate statistics at information sets instead of separate
  determinized states, addressing some duplicated work and strategy-fusion
  failures of naive determinization
  ([Cowling, Powley, and Whitehouse, 2012](https://eprints.whiterose.ac.uk/id/eprint/75048/)).
- **POMCP:** maintain particles over a belief and run MCTS over action-observation
  histories using only a black-box POMDP simulator
  ([Silver and Veness, 2010](https://proceedings.neurips.cc/paper/2010/hash/edfbe1afcf9246bb0d40eb4d8027d90f-Abstract.html)).

POMCP is a single-agent POMDP method. In a game, other players must therefore be
embedded in its transition model as fixed or sampled opponent policies. That is
useful but is not an equilibrium guarantee.

**Catan evidence.** Szita et al. found that MCTS plus Catan knowledge could
challenge heuristic agents, but used perfect information and removed
negotiation. Dobre and Lascarides later showed that choosing an action category
before an action reduced waste caused by dominant categories, cycles, and very
unequal category sizes. Their full Catan experiment still revealed hands. The
second result maps directly to Empires, where compound roads and discards occupy
most global indices and trade choices can dominate a legal list, but it does not
settle how hidden information should be modeled
([Dobre and Lascarides, 2017](https://www.research.ed.ac.uk/en/publications/exploiting-action-categories-in-learning-complex-games/)).

One newer implementation report sharpens two probes without settling either.
In `catan-rl`'s own records against three frozen heuristic opponents, flat PPO
plateaued around 65%, 48 full rollouts with an 80-turn horizon reached 72.5%,
and a learned-policy prior pruning to eight candidates with 96 full rollouts
reached 82%. The ledger defines 192 games for its primary PPO gate but describes
the Alpha design variants as 120–150 games without tying an exact sample to the
82% row. Three PPO-critic leaf variants reported 38.3%, 15.8%, and 25.8%
([ledger](https://github.com/Eli6th/catan-rl/blob/main/training/results/EXPERIMENTS.md)).
The same project compresses decisions into a fixed 299-id codec by reusing ids
across mutually exclusive phases and making some compound decisions sequential
([codec](https://github.com/Eli6th/catan-rl/blob/main/rust/catan-env/src/codec.rs)).
This motivates testing full rollouts, policy-prior pruning, leaf calibration,
and sequential action grammars separately. It is **not** comparative evidence
for Empires: the source experiment is documented as first-to-7 and
perfect-information, its trades are limited to giving one or two of one
resource for one other resource with at most three offers per turn, and its
opponent is the same project's fixed heuristic. The current 10-point command
rerun validates executability and approximate rate, not standard-Catan strength
or the historical protocol.

**Fit.** MCTS is anytime, uses the existing simulator, can sample chance rather
than enumerate it, and can reuse heuristic policies as priors, rollouts, or leaf
evaluators. Search effort can be reserved for consequential choices while
forced responses remain cheap.

**Limits.** Weak rollouts over a long game create noisy values. Opponent-policy
assumptions dominate trade and threat forecasts. Hidden-state particles need a
valid generative belief update. Tree reuse is difficult when private
observations differ. Wide action sets need categories, priors, progressive
widening, or sampled actions. Tail latency matters more than median latency in a
phone UI.

**Small falsifiable probe M.** On 200 frozen full-game decisions plus the exact
reduced games from probe S, run 32, 128, 512, and 2,048 simulations under three
rollout policies. Record simple regret against the reduced-game oracle, root
visit entropy, selected move, completed rollouts per second, p50/p95/p99 time,
and memory. Repeat with full-state MCTS, ISMCTS, and a deliberately simple
particle belief where applicable. Proceed with a variant only if:

- oracle regret decreases as budget increases;
- a hidden-information variant is invariant to which ground state inside the
  same information state happened to be used to construct the test;
- action-category sampling is compared to flat sampling at equal simulations
  and equal wall time; and
- its p95 time fits a numerical device budget locked **before** seeing results.

If no budgeted curve improves, “more rollouts” is not an implementation plan.

### 4.4 CFR, MCCFR, NFSP, and related imperfect-information solvers

**Mechanism.** Counterfactual regret minimization decomposes regret across
information sets. In two-player zero-sum extensive-form games, average
strategies converge toward Nash as counterfactual regret falls
([Zinkevich et al., 2007](https://papers.nips.cc/paper_files/paper/2007/hash/08d98638c6fcd194a4b1e6992063e944-Abstract.html)).
Monte Carlo CFR samples portions of the tree to reduce iteration cost. NFSP
approximates fictitious self-play with reinforcement learning and supervised
average-policy memory; its primary demonstrations are Leduc and limit Texas
Hold'em
([Heinrich and Silver, 2016](https://arxiv.org/abs/1603.01121)).

**Fit.** Information sets, private observations, chance, mixed strategies, and
bluff-like trade behavior are first-class concepts. A solved or distilled
policy can be cheap at runtime.

**Limits.** The familiar CFR-to-Nash statement does not transfer unchanged to
three- or four-player non-zero-sum play. Work on multiplayer poker shows useful
behavior and elimination of iteratively dominated actions, while explicitly
stating that general-sum theoretical guarantees are less understood
([Gibson, 2013](https://arxiv.org/abs/1305.0034)). In a many-player stochastic
game, external-regret dynamics target coarse-correlated behavior under specific
conditions, not automatically one stationary Nash policy
([Brown, 2021](https://proceedings.mlr.press/v161/brown21a.html)). The complete
Empires extensive form—histories, chance, variable legal offers, and long
turns—would also be enormous and would need abstraction or function
approximation.

ReBeL is important evidence that learned values, self-play, and search can be
combined in imperfect-information games, but its convergence claim is expressly
for **two-player zero-sum** games
([Brown et al., 2020](https://arxiv.org/abs/2007.13544)). It is an architectural
reference, not a theorem about Empires.

**Small falsifiable probe C.** Implement no full Catan tree. First reproduce:

1. falling exploitability on a tiny two-player zero-sum imperfect-information
   game;
2. falling external regret and coarse-correlated-equilibrium gap—not “Nash
   exploitability”—on a three-player general-sum trade toy; and
3. chance reach probabilities on a dice-augmented version of that toy.

The gate fails if the metric is mislabeled, perfect recall is violated, or the
measured gap does not trend downward over three logarithmically larger budgets.
Only then estimate information-set growth from real Empires traces and decide
whether abstraction, MCCFR, NFSP, or a local subgame solver merits another
probe.

### 4.5 AlphaZero-, Gumbel-, and MuZero-style planning

**Mechanism.** AlphaZero iterates self-play, policy/value learning, and MCTS.
Its reported domains—Go, chess, and shogi—are two-player perfect-information
games
([Silver et al., 2017](https://arxiv.org/abs/1712.01815)). Gumbel AlphaZero
samples root actions without replacement and was designed to provide a more
principled policy-improvement target, especially with few simulations
([Danihelka et al., 2022](https://openreview.net/forum?id=bERaNdoegnO)). Sampled
MuZero extends policy improvement and planning to sampled subsets of complex
action spaces
([Hubert et al., 2021](https://proceedings.mlr.press/v139/hubert21a.html)).

**Fit.** Empires already has exactly what the broad recipe needs: deterministic
replay, a simulator, policy/value tensors, and legal masks. A learned prior can
focus search; search can produce better training targets than raw heuristic
imitation. Gumbel-style root sampling and sampled actions are directly relevant
when few simulations can inspect only a fraction of legal candidates.

**Limits.** The standard scalar value, two-player backup, and perfect-state
tree are wrong abstractions for this game without adaptation. A credible design
needs player-vector or declared focal-seat values, explicit chance handling,
an information-state/belief representation, and a multiplayer training target.
MuZero learns dynamics because the true model may be unknown; Empires already
has exact rules, so replacing them with a latent dynamics model introduces
model error unless another measured benefit justifies it
([MuZero paper](https://arxiv.org/abs/1911.08265)). Repeated self-play search is
also a major compute multiplier.

**Small falsifiable probe A.** On the exact reduced games and 200 tactical
states, train a deliberately small masked policy/value model. Compare raw prior,
vanilla PUCT, Gumbel root search, and sampled-action search at 16, 32, and 64
simulations. Lock the state information policy and value target first. A variant
proceeds only if:

- search improves the predeclared oracle or tactical score over its own raw
  prior at equal model weights;
- improvement is present across at least four of five training seeds, not only
  in the best checkpoint;
- chance and player perspective tests pass exactly; and
- low-simulation p95 latency meets the locked device budget.

This probe tests whether planning improves a prior; it does not claim that the
resulting self-play process approaches a multiplayer equilibrium.

### 4.6 Actor-critic, PPO, self-play, and league training

**Mechanism.** PPO is an on-policy actor-critic method that reuses each sampled
batch for several clipped surrogate-objective updates
([Schulman et al., 2017](https://arxiv.org/abs/1707.06347)). In Empires, chance
is sampled naturally by the environment and legality can be enforced by
state-dependent action masking; masking has a policy-gradient justification and
becomes increasingly important as invalid actions dominate the global space
([Huang and Ontañón, 2020](https://arxiv.org/abs/2006.14171)).

**Fit.** A trained policy can make one inexpensive local forward pass. Recurrent
actor-critics can consume public action-observation histories. A shared model
can condition on chair, table size, target, and a style vector. Self-play can
discover behaviors that are hard to hand-code.

**Limits.** Sparse terminal rewards and hundreds of actions create severe
credit assignment. Shaping can change the game being optimized. A flat
9,335-way head spends capacity on mostly masked choices; action branching gives
linear output growth but assumes some independence between action dimensions,
which is questionable for coupled trades and road pairs
([Tavakoli, Pardo, and Kormushev, 2018](https://ojs.aaai.org/index.php/AAAI/article/view/11798)).
Autoregressive or category-then-argument heads preserve coupling but create
more decisions and require exact conditional masks.

Independent self-play sees a moving opponent distribution and can overfit to
the policies it happened to meet. PSRO addresses this by training approximate
best responses to mixtures of prior policies and evaluating a meta-game
([Lanctot et al., 2017](https://proceedings.neurips.cc/paper_files/paper/2017/hash/3323fe11e9595c09af38fe67567a9394-Abstract.html)).
League training can preserve counter-strategies and diversity, as AlphaStar's
official account describes, but it multiplies infrastructure and evaluation
cost
([AlphaStar](https://deepmind.google/blog/alphastar-grandmaster-level-in-starcraft-ii-using-multi-agent-reinforcement-learning/)).
OpenAI Five is evidence that PPO-style self-play can handle long horizons at
scale; it is also a warning against assuming one consumer GPU reproduces a
system trained for ten months with massive distributed rollout throughput
([paper and system description](https://openai.com/index/dota-2-with-large-scale-deep-reinforcement-learning/)).

**Small falsifiable probe R.** Use a reduced but still three-player environment
with dice, one private resource, and a short build/trade objective. Train five
seeds under a hard cap on environment decisions and wall-clock hours. Compare
flat masked PPO, category-then-argument PPO, recurrent PPO, and a frozen-policy
population. Proceed only if:

- zero illegal actions occur in 100,000 sampled decisions;
- at least four of five seeds beat the uniform-legal anchor on untouched seeds
  and every chair;
- recurrent input passes the no-peeking paired-state test;
- performance does not collapse against a held-out scripted opponent; and
- throughput demonstrates that a powered full-game experiment fits an explicit
  time budget on the available 4090 plus CPU simulator.

The probe is a scaling test. It is not permission to launch an uncapped full
self-play run.

### 4.7 Imitation learning and offline RL

**Mechanism.** Behavioral cloning learns the action distribution in logged
states. DAgger addresses sequential distribution shift by repeatedly collecting
states visited by the learner and asking an expert for the correct action
([Ross, Gordon, and Bagnell, 2011](https://publications.ri.cmu.edu/a-reduction-of-imitation-learning-and-structured-prediction-to-no-regret-online-learning)).
Offline RL tries to improve from fixed data, but ordinary off-policy value
learning can overestimate actions outside the data distribution. CQL learns
conservative values
([Kumar et al., 2020](https://papers.nips.cc/paper_files/paper/2020/hash/0d2b2061826a5df3221116a5085a6052-Abstract.html));
IQL avoids directly evaluating unseen actions during training
([Kostrikov, Nair, and Levine, 2022](https://openreview.net/forum?id=EblVBDNalKu)).
Decision Transformer instead conditions sequence prediction on desired return
([Chen et al., 2021](https://papers.nips.cc/paper/2021/hash/7f489f642a0ddb10272b5c31057f0663-Abstract.html)).

**Fit.** This family is attractive when high-quality human or strong-search
logs exist. It is sample-efficient relative to learning every rule from random
self-play, can bootstrap a policy prior, and usually deploys as one local model.
Clustering or labeling demonstrators can support style conditioning.

**Limits.** A policy cannot learn choices absent from its data merely because a
loss decreases. Logged opponents and rule variants define the behavior
distribution. Long-horizon compounding error is acute, and hidden-information
logs must contain only what the acting player observed. Offline reward labels
are especially sparse in multiplayer play. Empires' own 42.4%-accurate model
going 0/40 is direct evidence that classification metrics alone are unsafe here.

**Small falsifiable probe I.** Freeze whole-game train/test splits by seed and
never split individual decisions from one game across both. Compare uniform,
phase-only cloning, state-conditioned cloning, DAgger with the shipping
heuristic as oracle, and one conservative offline method. Before any device
integration, require:

- zero illegal selections by masked decoding;
- calibration and top-k accuracy reported beside top-1;
- 100 complete rollouts with decisive rate, game length, build/trade/dev-card
  behavior, and chair-rotated win results;
- no worse than a predeclared non-inferiority margin against the teacher or
  frozen anchor on the primary complete-game metric; and
- a separate held-out opponent population, not only teacher self-play.

If the policy predicts the teacher but cannot complete competent games, stop or
use it only as a prior. Do not relabel it a strength model.

### 4.8 LLM move policies

**Mechanism.** Serialize the permitted observation and current legal moves,
then ask a language model to return one local move number or a typed tool call.
The engine, never the model, validates and commits the move. Structured or
grammar-constrained output can guarantee a syntactic schema, but not strategic
correctness
([official Structured Outputs description](https://openai.com/index/introducing-structured-outputs-in-the-api/)).

**Evidence.** Language models can produce high-level plans but naive plans may
not map to admissible actions
([Huang et al., 2022](https://arxiv.org/abs/2201.07207)). A recent primary study
combines language models with internal or external planning in chess,
Chess960, Connect Four, and Hex—perfect-information games, not negotiated
multiplayer Catan
([Feng et al., 2025](https://openreview.net/forum?id=KKwBo3u3IW)). The Catan trade
dialogue paper reports a 53% win rate for its learned trade component against
three bots, versus 27% for its supervised component, but leaves all non-trade
behavior to JSettlers and operates on semantic trade acts rather than free-form
language
([Cuayáhuitl et al., 2015](https://arxiv.org/abs/1511.08099)).

**Fit.** The existing prompt encoder and short observation-local legal list are
well suited to a bounded test. An LLM can also render varied character dialogue
from a structured strategic intent. It may supply broad commonsense priors
before domain-specific training data exists.

**Limits.** A cloud policy pays network latency and monetary cost on every
decision, requires an offline/error fallback, and can drift when a remote model
changes. A local model trades those costs for app size, memory, thermal load,
and likely lower capability. Neither route has a game-theoretic guarantee.
Prompts can leak hidden state, move ordering can bias selection, and generated
explanations may rationalize rather than reveal the cause of a decision;
chain-of-thought faithfulness cannot be assumed
([Turpin et al., 2023](https://proceedings.neurips.cc/paper_files/paper/2023/hash/ed3fea9033a80fea1376299fa7863f4a-Abstract-Conference.html)).

**Small falsifiable probe L.** Use 250 frozen observations stratified across all
phases, including adversarially similar hidden states. Evaluate at least three
models/configurations with the same prompt and three random permutations of
the legal-move list. Lock numerical ceilings for p95 latency and dollars per
complete median-length game before sending requests. Require:

- 100% parseable, in-range output after bounded retries, with an explicit
  fallback measured separately;
- no private field in any prompt under the public-information condition;
- materially better tactical-scenario agreement than uniform legal choice;
- move-choice stability under semantically irrelevant list permutations, or a
  measured mitigation;
- complete-game results, not vignette accuracy alone; and
- separately scored strategy and prose. Characterful text cannot compensate
  for a strategically invalid move.

An LLM failing the move-policy gate may still remain viable as a dialogue-only
renderer.

### 4.9 Hybrid architectures

Hybrid is a family of explicit interfaces, not permission to assemble every
method at once. Several combinations have a clear causal story:

1. **Heuristic proposal, learned reranking:** rules and strategic modules
   generate a small candidate set; a learned value ranks it.
2. **Learned prior/value, exact MCTS:** a network focuses simulation while the
   real engine owns transitions and legality.
3. **Belief model plus ISMCTS/POMCP:** a learned or analytic model samples
   hidden hands; search plans against those particles.
4. **Category policy plus argument policy:** choose build/trade/dev-card/end
   turn, then choose legal parameters. Dobre and Lascarides provide direct
   Catan evidence for category-first rollout sampling.
5. **Imitation-regularized planning or RL:** remain near human behavior while
   improving strategic utility. Diplodocus uses this pattern in no-press
   Diplomacy
   ([Bakhtin et al., 2022](https://arxiv.org/abs/2210.05492)).
6. **Strategic policy plus language renderer:** the policy chooses intent and
   binding game actions; a language model expresses them. CICERO's official
   paper and source separate strategic reasoning from dialogue in seven-player
   Diplomacy
   ([paper](https://doi.org/10.1126/science.ade9097),
   [official source](https://github.com/facebookresearch/diplomacy_cicero)).
7. **Budgeted router:** forced moves use deterministic logic, ordinary moves
   use a local policy, and only high-value ambiguous states receive search or a
   remote call.

**Fit.** Hybrids can reserve expensive reasoning for the decisions where it has
measured value, preserve a transparent fallback, and keep voice independent of
game legality.

**Limits.** More modules create version skew, duplicated state semantics, and
attribution problems. A weak learned value can make search worse; a bad belief
model can make a principled search confidently wrong; a fluent renderer can
contradict the committed move.

**Small falsifiable probe Y.** Every hybrid experiment must include all
single-component ablations at the same wall-clock or simulation budget. Proceed
only when the combination improves a predeclared primary metric over every
component alone, does not violate legality/information/latency gates, and logs
which module caused the final choice. Without the ablation, complexity is not
evidence of synergy.

## 5. Cross-cutting design decisions that precede selection

These are decisions to log, not assumptions for an implementation.

| ID | Decision to lock | Why it changes the algorithm comparison | Required evidence |
| --- | --- | --- | --- |
| D1 | **Product objective:** strongest, robust, human-like, fun, difficulty tier, or research agent | Each implies a different target distribution or utility. | Rank primary and guardrail metrics before a run. |
| D2 | **Utility vector:** terminal one-hot only or shaped training rewards | One-hot is n-player constant-sum; shaping can be general-sum and can reward stalling or cosmetic progress. | For every shaping term, show a state where it helps and a state where it could be exploited; evaluate on unshaped wins. |
| D3 | **Information policy:** reveal-all research baseline or public-information production policy | Search, value targets, logs, and claimed fairness change. | Paired hidden-state leakage test and prompt/export audit. |
| D4 | **Memory/belief:** snapshot, recurrent public history, or explicit hand particles | Hidden-hand inference is impossible from a snapshot when histories differ. | Tiny belief-update oracle plus perfect-recall test. |
| D5 | **Action representation:** flat 9,335 mask, category→argument, autoregressive, or sampled candidates | It changes exploration, network heads, search breadth, and artifact compatibility. | Coverage/bijection test; category-frequency and latency measurements on real traces. |
| D6 | **Negotiation protocol:** offers only, accept/reject, counteroffers, target seat, memory, and repeated-offer rules | Trade value depends on responder policy and whether offers can cycle. | Fixed trade scenarios and a no-repeat/no-deadlock invariant. |
| D7 | **Opponent objective:** one frozen bot, current self, historical pool, human model, or adversarial population | Training against one policy can overfit and misstate strength. | Full matchup matrix including unseen policies and mixed tables. |
| D8 | **Solution concept:** exploitative best response, Nash-like robustness, CCE/EFCE target, or empirical population ranking | “Regret,” “exploitability,” and “convergence” mean different things. | Name the metric and theorem assumptions; never report two-player exploitability for a four-player policy. |
| D9 | **Deployment envelope:** fully offline, optional network, or cloud-required | It determines acceptable model size, call count, failure mode, cost, and latency. | Lock p95/p99 latency, memory, app-size, and dollars/game limits before benchmarking. |
| D10 | **Personality contract:** strategic preferences, difficulty, and voice | Conflating them makes a “cautious” bot merely weak or a witty bot strategically random. | Separate behavioral, strength, and language scorecards. |
| D11 | **Artifact contract:** layout versions, rule commit, hidden policy, model checksum, opponent pool, seeds | Silent state/action drift invalidates a trained model. | Loader must refuse every mismatched field. |

## 6. Personality, difficulty, and speech

These should remain three different layers even if one model eventually serves
more than one.

### Strategic personality

Possible controls include explicit heuristic weights, search priors and rollout
policies, reward/goal conditioning, policy populations, or latent style codes.
Universal value-function approximators establish the general idea of
conditioning a value function on a goal
([Schaul et al., 2015](https://proceedings.mlr.press/v37/schaul15.html)); they
do not establish that an unlabeled latent becomes a human-recognizable Catan
personality.

A personality is validated only if:

- a held-out classifier or predefined metric can distinguish styles above
  chance;
- the intended axes move in the declared direction—for example trade rate,
  blocking, development-card appetite, or expansion/consolidation;
- illegal moves, completion, and strategic competence remain guardrails; and
- the same identity persists across board seeds, chairs, table sizes, and game
  phases.

### Difficulty

Difficulty is a measured strength ordering against a declared population, not
a personality label. Deliberately bad random moves can create an “easy” tier but
may also create nonsensical games. Candidate tiers need chair-rotated common
seeds, confidence intervals, completion rates, and human playtests. The prior
Empires anchor experiment demonstrates why passing some matchup cells is not
enough.

### Voice and chat behavior

Voice can be a deterministic template bank, grammar, small local model, or
cloud LLM. The strategic layer should emit a structured speech act such as:

```text
intent=trade_offer
give={brick:1}
want={ore:1}
reason=city_plan
tone=boastful
commitment=non_binding
```

The renderer may vary phrasing but may not change quantities, claim hidden
knowledge, promise an unsupported future action, or contradict the move. This
separation follows the useful architectural lesson from CICERO; it does not
imply Empires needs CICERO's model or compute.

## 7. A probe ladder before any full implementation

Every family starts at the cheapest stage capable of disproving it. Passing a
stage authorizes only the next probe, not production adoption.

### Gate G0 — research contract

Write and freeze one machine-readable experiment manifest containing:

- source commit and Release simulator checksum;
- rules, state-layout, action-layout, and exporter versions;
- hidden-information policy and history representation;
- candidate, anchors, opponent population, seats, table sizes, board modes,
  victory targets, and seed ranges;
- primary metric, guardrails, confidence method, stopping rule, compute cap,
  and device latency/cost budgets.

**Fail:** any value is inferred after results, or a training seed reaches final
evaluation.

### Gate G1 — engine, legality, and information integrity

Run 100,000 policy decisions sampled across all phases and supported table
sizes.

**Pass only if:** every selected move is in the exact legal list; every legal
move required by the sampled states has a representable action; replays are
cross-process identical for deterministic policies; the chance oracle matches
all 36 two-die outcomes and card/steal distributions; and paired states that are
identical to the observer produce identical policy inputs despite different
opponent hands.

This audit reconciled the current 9,335 executable action-size assertion with
stale 9,295 and 8,815 source comments. Preserve that agreement before
persisting any model artifact.

### Gate G2 — exact toy oracles

Use the three reduced games from probe S. Each algorithm must match the metric
appropriate to its claim:

- expectimax: exact expected value;
- `max^n`: exact utility vector;
- MCTS/AlphaZero style: simple regret versus the exact action;
- CFR style: two-player exploitability or multiplayer regret/CCE gap, clearly
  separated;
- belief policy: exact Bayesian update in the tiny hidden game.

**Fail:** a family cannot recover the tiny answer as budget increases. More
full-game compute cannot repair a perspective, chance, or information-set bug.

### Gate G3 — tactical scenario corpus

Freeze the 60-state corpus from probe H plus adversarial trade, robber, road,
dev-card, and endgame cases. Store all acceptable actions rather than one
subjective label where several moves are reasonable.

**Pass only if:** the candidate clears all hard safety/pathology cases and
improves its predeclared target subset without regressing the frozen set.
Scenario accuracy remains a diagnostic, not a strength claim.

### Gate G4 — bounded learning or planning signal

Run each family's named probe under a fixed wall-time, decisions, simulations,
and seed budget. Report all seeds and all attempted variants.

**Pass only if:** improvement appears on untouched states against the correct
baseline, scales in the expected direction with budget, and does not depend on
one lucky seed. A failed value comparator, non-monotonic search curve, or 0-win
rollout result ends that variant.

### Gate G5 — full-game functional screen

Before a powered strength study, require at least 100 complete games per
candidate across three- and four-player tables with full chair rotation and
common random seeds.

Report:

- decisive and timeout rates;
- win vector by chair and opponent composition;
- median, p95, and maximum decisions per game;
- resource conservation and rule invariant failures;
- build, road, robber, dev-card, offer, acceptance, counteroffer, repeated-offer,
  and end-turn behavior;
- policy latency distribution, memory, and simulator throughput.

**Fail:** any crash, illegal action, information leak, new deadlock, or material
completion regression. A candidate can pass functionally without yet being
declared stronger.

### Gate G6 — powered multiplayer evaluation

Use a pilot to power the final sample size, then lock new held-out seeds. Rotate
every candidate through every chair against:

- shipping heuristics and each personality;
- random and simple greedy anchors;
- prior candidate checkpoints;
- mixed populations rather than only three copies of one opponent; and
- at least one unseen scripted counter-policy.

Use seed-clustered confidence intervals so all chair rotations of one board stay
together. Report the complete matchup tensor, not a pooled win rate. Inspect
cycles; if A beats B, B beats C, and C beats A, use population analysis rather
than forcing a single Elo story. Alpha-Rank is one primary method designed for
many-player empirical games and non-transitive populations
([Omidshafiei et al., 2019](https://www.nature.com/articles/s41598-019-45619-9)).

**Pass:** only the predeclared claim—for example non-inferiority, a minimum
effect, or robustness across cells—passes its interval. No adjacent claim is
inherited.

### Gate G7 — product and personality validation

Measure on the oldest supported iPhone, not only the development Mac:

- p50/p95/p99 decision latency and thermal/memory behavior;
- app size and offline startup for local models;
- request count, failure rate, retry behavior, p95/p99 latency, and dollars per
  median-length game for cloud models;
- fallback behavior with airplane mode and service errors;
- blinded human ratings of fun, competence, frustration, personality identity,
  repetitiveness, and explanation usefulness.

**Fail:** the candidate exceeds any locked product ceiling, loses its character
under blind evaluation, or requires generated prose to make nonsensical play
appear reasonable.

## 8. What outcomes would justify further work?

This is a routing table, not a ranking.

| Observed result | Justified next probe | Not justified |
| --- | --- | --- |
| Heuristic scenario ledger is accurate and targeted metrics move | Tune or deepen the explicit planner on new held-out cases | Claim expert play from unit scenarios |
| Shallow exact search solves tactical cases within device budget | Test a budgeted tactical-search hybrid | Assume full-game expectimax is tractable |
| ISMCTS/POMCP improves with particles and passes no-peeking tests | Improve the belief/opponent model and test full-game budget curves | Claim equilibrium robustness |
| CFR/NFSP converges on exact toys and empirical information-set growth is manageable | Prototype one abstract trade or endgame subgame | Build a full-game tree immediately |
| Gumbel/sampled search improves a fixed prior at low simulations | Train a stronger prior on bounded self-play data | Import AlphaZero's two-player guarantee |
| PPO learns the reduced game across seeds and generalizes to held-out opponents | Run a capped full-engine smoke with frozen opponents | Launch weeks of self-play from one successful seed |
| Imitation completes games and passes non-inferiority | Use it as a prior, initialization, or human regularizer | Equate top-1 accuracy with strength |
| LLM decisions clear legality, order-bias, latency, cost, and rollout gates | Compare move-policy and dialogue-only roles | Let free-form text commit engine actions |
| A hybrid beats every ablation under equal budget | Power a full matchup study | Attribute the gain to the most fashionable component |

Multiple families may survive and serve different roles. For example, one
policy may ship locally, a search policy may generate training targets, a
population may evaluate robustness, and an LLM may render dialogue. That is not
the same as selecting all of them for production.

## 9. Explicit non-conclusions

- The available 4090 makes bounded experiments practical; it does not prove
  simulator throughput, sample efficiency, or weeks-long training are adequate.
- A method succeeding in Global Conquest would not establish anything about
  Empires beyond reusable experimental discipline.
- A Catan paper that reveals hands, removes trading, or uses two players does
  not answer the full Empires question.
- A legal action mask prevents illegal sampling; it does not solve exploration
  across action categories.
- A state vector prevents ad hoc parsing; it does not become a sufficient
  information state without public history or belief.
- A lower loss, higher imitation accuracy, or better tactical score is not a
  complete-game strength result.
- A pooled win rate can hide chair bias, opponent overfitting, non-transitivity,
  and table-size failures.
- “Self-play” names a data-generation process, not an equilibrium guarantee.
- “CFR” and “AlphaZero” do not carry their two-player theorems into a
  four-player negotiated game by name.
- Fluent explanations are not proof of faithful reasoning.
- Personality, difficulty, and voice must be measured separately.
- This note deliberately selects no winner. The gates exist to let evidence,
  including negative evidence, narrow the field.

## Primary sources

### Catan-specific

- Quentin Gendre and Tomoyuki Kaneko, “Playing Catan with Cross-dimensional
  Neural Network,” 2020: <https://arxiv.org/abs/2008.07079>
- István Szita, Guillaume Chaslot, and Pieter Spronck, “Monte-Carlo Tree Search
  in Settlers of Catan,” 2009/2010:
  <https://doi.org/10.1007/978-3-642-12993-3_3>
- Mihai Dobre and Alex Lascarides, “Exploiting Action Categories in Learning
  Complex Games,” 2017:
  <https://www.pure.ed.ac.uk/ws/portalfiles/portal/31304332/final_2.pdf>
- Heriberto Cuayáhuitl, Simon Keizer, and Oliver Lemon, “Strategic Dialogue
  Management via Deep Reinforcement Learning,” 2015:
  <https://arxiv.org/abs/1511.08099>
- JSettlers2 official source: <https://github.com/jdmonin/JSettlers2>
- Eli6th, `catan-rl` official MIT-licensed source, experiment ledger, and fixed
  action codec: <https://github.com/Eli6th/catan-rl>,
  <https://github.com/Eli6th/catan-rl/blob/main/training/results/EXPERIMENTS.md>,
  <https://github.com/Eli6th/catan-rl/blob/main/rust/catan-env/src/codec.rs>

### Games, search, and imperfect information

- Eric A. Hansen, Daniel S. Bernstein, and Shlomo Zilberstein, “Dynamic
  Programming for Partially Observable Stochastic Games,” 2004:
  <https://aaai.org/papers/ws04-08-005-dynamic-programming-for-partially-observable-stochastic-games/>
- Daniel S. Bernstein et al., “The Complexity of Decentralized Control of
  Markov Decision Processes,” 2002:
  <https://doi.org/10.1287/moor.27.4.819.297>
- William Brown, “Learning in Multi-Player Stochastic Games,” 2021:
  <https://proceedings.mlr.press/v161/brown21a.html>
- Carol Luckhardt and Keki Irani, “An Algorithmic Solution of N-Person Games,”
  1986: <https://cdn.aaai.org/AAAI/1986/AAAI86-025.pdf>
- Bruce W. Ballard, “The *-Minimax Search Procedure for Trees Containing Chance
  Nodes,” 1983: <https://doi.org/10.1016/S0004-3702%2883%2980015-0>
- Levente Kocsis and Csaba Szepesvári, “Bandit Based Monte-Carlo Planning,”
  2006: <https://doi.org/10.1007/11871842_29>
- Peter I. Cowling, Edward J. Powley, and Daniel Whitehouse, “Information Set
  Monte Carlo Tree Search,” 2012:
  <https://eprints.whiterose.ac.uk/id/eprint/75048/>
- David Silver and Joel Veness, “Monte-Carlo Planning in Large POMDPs,” 2010:
  <https://proceedings.neurips.cc/paper/2010/hash/edfbe1afcf9246bb0d40eb4d8027d90f-Abstract.html>
- Martin Zinkevich et al., “Regret Minimization in Games with Incomplete
  Information,” 2007:
  <https://papers.nips.cc/paper_files/paper/2007/hash/08d98638c6fcd194a4b1e6992063e944-Abstract.html>
- Richard Gibson, “Regret Minimization in Non-Zero-Sum Games with Applications
  to Building Champion Multiplayer Computer Poker Agents,” 2013:
  <https://arxiv.org/abs/1305.0034>
- Johannes Heinrich and David Silver, “Deep Reinforcement Learning from
  Self-Play in Imperfect-Information Games,” 2016:
  <https://arxiv.org/abs/1603.01121>
- Noam Brown et al., “Combining Deep Reinforcement Learning and Search for
  Imperfect-Information Games,” 2020: <https://arxiv.org/abs/2007.13544>
- OpenSpiel official source and algorithm documentation:
  <https://github.com/google-deepmind/open_spiel>

### Learned policies, planning, and populations

- David Silver et al., “Mastering Chess and Shogi by Self-Play with a General
  Reinforcement Learning Algorithm,” 2017: <https://arxiv.org/abs/1712.01815>
- Ivo Danihelka et al., “Policy Improvement by Planning with Gumbel,” 2022:
  <https://openreview.net/forum?id=bERaNdoegnO>
- Thomas Hubert et al., “Learning and Planning in Complex Action Spaces,” 2021:
  <https://proceedings.mlr.press/v139/hubert21a.html>
- Julian Schrittwieser et al., “Mastering Atari, Go, Chess and Shogi by
  Planning with a Learned Model,” 2019/2020:
  <https://arxiv.org/abs/1911.08265>
- John Schulman et al., “Proximal Policy Optimization Algorithms,” 2017:
  <https://arxiv.org/abs/1707.06347>
- Shengyi Huang and Santiago Ontañón, “A Closer Look at Invalid Action Masking
  in Policy Gradient Algorithms,” 2020: <https://arxiv.org/abs/2006.14171>
- Arash Tavakoli, Fabio Pardo, and Petar Kormushev, “Action Branching
  Architectures for Deep Reinforcement Learning,” 2018:
  <https://ojs.aaai.org/index.php/AAAI/article/view/11798>
- Marc Lanctot et al., “A Unified Game-Theoretic Approach to Multiagent
  Reinforcement Learning,” 2017:
  <https://proceedings.neurips.cc/paper_files/paper/2017/hash/3323fe11e9595c09af38fe67567a9394-Abstract.html>
- OpenAI, “Dota 2 with Large Scale Deep Reinforcement Learning,” 2019:
  <https://openai.com/index/dota-2-with-large-scale-deep-reinforcement-learning/>
- Google DeepMind, AlphaStar official research description, 2019:
  <https://deepmind.google/blog/alphastar-grandmaster-level-in-starcraft-ii-using-multi-agent-reinforcement-learning/>
- Shayegan Omidshafiei et al., “α-Rank: Multi-Agent Evaluation by Evolution,”
  2019: <https://www.nature.com/articles/s41598-019-45619-9>

### Imitation, offline learning, language, and control

- Stéphane Ross, Geoffrey Gordon, and J. Andrew Bagnell, “A Reduction of
  Imitation Learning and Structured Prediction to No-Regret Online Learning,”
  2011:
  <https://publications.ri.cmu.edu/a-reduction-of-imitation-learning-and-structured-prediction-to-no-regret-online-learning>
- Aviral Kumar et al., “Conservative Q-Learning for Offline Reinforcement
  Learning,” 2020:
  <https://papers.nips.cc/paper_files/paper/2020/hash/0d2b2061826a5df3221116a5085a6052-Abstract.html>
- Ilya Kostrikov, Ashvin Nair, and Sergey Levine, “Offline Reinforcement
  Learning with Implicit Q-Learning,” 2022:
  <https://openreview.net/forum?id=EblVBDNalKu>
- Lili Chen et al., “Decision Transformer: Reinforcement Learning via Sequence
  Modeling,” 2021:
  <https://papers.nips.cc/paper/2021/hash/7f489f642a0ddb10272b5c31057f0663-Abstract.html>
- Wenlong Huang et al., “Language Models as Zero-Shot Planners,” 2022:
  <https://arxiv.org/abs/2201.07207>
- Xidong Feng et al., “Mastering Board Games by External and Internal Planning
  with Language Models,” 2025: <https://openreview.net/forum?id=KKwBo3u3IW>
- Miles Turpin et al., “Language Models Don't Always Say What They Think,”
  2023:
  <https://proceedings.neurips.cc/paper_files/paper/2023/hash/ed3fea9033a80fea1376299fa7863f4a-Abstract-Conference.html>
- Meta Fundamental AI Research Diplomacy Team, “Human-Level Play in the Game of
  Diplomacy by Combining Language Models with Strategic Reasoning,” 2022:
  <https://doi.org/10.1126/science.ade9097>
- Anton Bakhtin et al., “Mastering the Game of No-Press Diplomacy via
  Human-Regularized Reinforcement Learning and Planning,” 2022:
  <https://arxiv.org/abs/2210.05492>
- Tom Schaul et al., “Universal Value Function Approximators,” 2015:
  <https://proceedings.mlr.press/v37/schaul15.html>
- OpenAI, Structured Outputs official description, 2024:
  <https://openai.com/index/introducing-structured-outputs-in-the-api/>
