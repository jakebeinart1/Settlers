# Empires AI strategy: evidence, architecture, and research program

**Date:** 2026-09-05

**Status:** discovery decision record; no production policy selected

**Scope:** strategic play, trade negotiation, personalities, difficulty, and
character dialogue. Gameplay UI and rules correctness are outside this decision.

## Executive decision

Do **not** choose “heuristics”, “PPO”, “AlphaZero”, “an LLM”, or any other
single algorithm yet. The evidence supports a **measured hybrid research
program**, not a production architecture choice:

1. Keep the current heuristic as the shipping fallback and frozen comparator.
2. Instrument trade and road decisions well enough to diagnose *why* they are
   bad before changing them.
3. Use Eli6th AlphaBot as the first runnable public challenger, while keeping
   its engine external and treating the protocol mismatch as unresolved.
4. Establish a structured policy/value baseline on Empires' exact rules,
   masks, player counts, and victory targets.
5. Compare reactive learning, search, and policy-guided search through the
   same evaluation rig; advance only what wins on held-out games and device
   constraints.
6. Keep character language downstream of verified game events and strategic
   facts. Begin with deterministic, context-rich templates; test an LLM
   renderer later.

The most plausible eventual shape is a deterministic rules engine plus a
masked strategic policy, optionally strengthened by bounded search, with a
separate opponent model and a separate language renderer. That is a hypothesis
to test, not a conclusion to implement.

## Decision ledger

| ID | Decision for this phase | Status |
| --- | --- | --- |
| AI-1 | Preserve the current heuristic as shipping fallback and frozen comparator. | Decided |
| AI-2 | Select no final strategic algorithm until the ordered gates produce comparable evidence. | Decided |
| AI-3 | Treat strength, style, opponent modelling, negotiation, and voice as independent contracts. | Decided |
| AI-4 | Give every experiment an explicit reveal-all or public-information contract; do not mix their results. | Decided |
| AI-5 | Keep rules and legal-move authority deterministic and outside every learned or language model. | Decided |
| AI-6 | Keep initial character text downstream of verified game events and strategic facts; free-form chat is a later product. | Decided |
| AI-7 | Reproduce promising public agents as external benchmarks before borrowing architecture conclusions. | Partially executed: Eli6th current command reproduced; historical protocol unresolved |
| AI-8 | Profile the complete 4090 pipeline before funding a faster/second simulator. | Decided |
| AI-9 | Profile the current 9,335-action contract before decomposing compound decisions. | Deferred gate |
| AI-10 | Implement R0/R1 observability before tuning trade or road behavior. | Next proposed implementation |
| AI-11 | Treat Eli6th as the lead runnable permissive candidate and Dobre POMCP-TS-CR as the lead published standard-ish result; do not conflate them. | Decided |
| AI-12 | Compare narrow reactive adapters before any foreign-engine port; Empires remains the sole rules authority. | Decided |

## What Empires has today

### Implemented and usable

- A deterministic rules engine and one game-session loop.
- A replaceable `Policy` seam that receives a `GameObservation` and exact
  legal moves.
- A versioned global action codec and legal-action mask. The current standard
  four-chair head is **9,335** actions; ordered Road Building pairs and discard
  bundles consume about 87% of it.
- A versioned **5,182-feature** state vector and a text rendering for prompt
  experiments. Of those slots, **3,840 (74%)** reserve 256 possible pending
  trade-offer rows; this is a correct fixed contract, but an inefficient dense
  neural input until profiling proves otherwise.
- Two explicit information policies: current perfect information
  (`revealAll`) and shape-compatible public counts (`publicCountsOnly`).
  This switch applies to encodings/exports only; the live `Policy` still
  receives raw `GameState`, so it does not yet enforce no-peeking.
- Versioned deterministic training examples containing provenance, observer,
  player count, victory target, board mode, state/action layout versions,
  sparse legal mask, selected action, and terminal outcome.
- Deterministic headless three- and four-player simulation, configuration
  matrices, chair rotation, frozen anchors, clustered confidence intervals,
  training-data validation, and cross-process fingerprints.
- One shipping hand-scored heuristic policy and a deliberately weaker Greedy
  evaluation anchor.
- Three measured **style** presets—Balanced, Aggressive, and Cautious—and
  stable named opponent profiles.
- Deterministic culture-specific trade phrases selected after the strategic
  action is known.

### Not implemented or not demonstrated

- No learned policy or model is loaded by the iOS app.
- No calibrated Easy/Standard/Hard ladder exists. Personality is not
  difficulty.
- No evidence establishes expert-level play against strong humans or a strong
  external Catan agent.
- No belief model estimates hidden resources, development cards, intent, or
  opponent type.
- No persistent social model tracks reciprocity, trust, grudges, deception,
  or adaptation to an individual player.
- No free-form chat is understood by the policy, and no LLM is used.
- Current trade metrics say what was proposed or accepted, not the component
  values, threshold, alternative, or rejection reason.
- The trade evaluator returns only a Boolean. Affordability is checked outside
  it, so “cannot pay” and “strategically rejects” collapse into the same UI
  result. Balanced and Cautious also hit the same `0.4` base-threshold floor,
  which explains why their measured acceptance rates do not separate.
- A current trade comment overstates `expansionBias`: acceptance sums every
  build-target contribution, so reordering city and settlement targets cannot
  affect that sum. “Immediate build” also means resource-affordable, not that a
  legal build location and piece actually exist.
- Current road metrics count roads, but do not identify a destination,
  blocking objective, connection objective, Longest Road objective, dead end,
  or whether a multi-turn plan was followed.
- Existing style labels are only partially validated: Aggressive knight use
  and Cautious player-trade preference separated on held-out simulations.
  Blind human recognition has not been demonstrated.
- The existing 208 authored trade lines are deterministic but receive no
  resource bundle, ratio, score, threshold, or reason. They provide voice, not
  truthful contextual explanation, and need an editorial/cultural safety pass.

## Evidence already earned in this repository

Negative experiments are constraints, not embarrassments:

- A small short-horizon rollout candidate lost to the existing heuristic
  (**60.0% versus 87.5%** against the same Greedy table; paired difference
  -27.5 points, 95% interval -42.5 to -12.5). This rejects that horizon,
  rollout policy, and evaluator combination—not search as a family.
- A phase-only imitation baseline achieved **31.5%** top-1 versus **14.1%**
  uniform. That proved the dataset plumbing, not policy strength.
- A state-conditioned projected baseline improved imitation to **42.4%** but
  went **0/40** in live games and exhibited pathological trade/build behavior.
  Offline imitation accuracy is therefore not a promotion metric.
- A 3,360-game anchor run showed the shipping heuristic was substantially
  stronger than Greedy in most cells, but the predeclared all-cell margin and
  completion gate failed. Greedy is not an honest product “Easy” tier.
- A 3,024-game personality-preserving Easy prototype was weaker, but failed
  its random floor and long-game completion criteria and was removed.

These results rule out shortcuts: neither a low offline loss, a random-bot win
rate, nor “it looked smarter in a few games” is sufficient.

## The AI is six systems, not one

| Layer | Responsibility | Current state | Rule |
| --- | --- | --- | --- |
| Rules and legality | State transitions, randomness, legal mask | Strong deterministic engine | Never delegate authority to a model |
| Strategic policy | Build, card, robber, trade, and turn choices | Hand-scored heuristic | Every candidate consumes the same typed observation and mask |
| Opponent/belief model | Hidden holdings, goals, tendencies, reciprocity | Absent | Version independently from policy |
| Style/personality | Risk, expansion, hostility, trade posture | Three numeric strategy presets | Must not imply strength |
| Difficulty | Calibrated probability of winning against named populations | Absent | Earn labels through frozen, held-out evaluation |
| Language/character | Express a known offer, reason, reaction, or intent | Deterministic trade templates | Text may explain or decorate; it does not create legal moves |

Free-form chat is a seventh, optional input channel. It requires intent
parsing, abuse/safety handling, latency, cost controls, and a safe mapping into
typed game intents. It should not be bundled into the first language pass.

## Existing Catan AI: what is strongest, and what can actually be reused?

### Direct answer

There is no defensible public, cross-project “best Catan AI” leaderboard. The
projects use different rules, player counts, victory targets, visibility,
trading systems, opponents, chairs, and compute budgets. Raw win rates across
them do not share a denominator. Closed commercial bots also cannot be audited,
reproduced, or licensed from public evidence, so they are not reuse candidates.

### What the AlphaBot result means in plain English

- A research subagent in this Empires task downloaded the pinned public source
  and model, compiled the author's unchanged Rust program on this Mac, ran its
  documented command, and retained the output. This was a new local execution
  of the author's evaluator—not a result copied from the README and not an
  independent reimplementation of the algorithm.
- Every participant was an AI. The command `A,H,H,H` put AlphaBot in player
  slot 1 and three copies of that repository's own hand-written Heuristic-v1
  bot in slots 2–4. No human played these games.
- AlphaBot won 83 of 100 games and then 157 of 192 fixed-seed games (81.8%).
  The result means “AlphaBot usually beats this repository's Heuristic-v1 bot
  under this repository's rules and evaluator.” It does not mean “AlphaBot
  beats strong humans 81.8% of the time.”
- “Fixed chair” means AlphaBot remained in player slot 1 instead of rotating
  through all four starting-order positions. Catan's setup order and board
  access can make one slot easier than another, so a fair strength test rotates
  every candidate through every slot.
- “Perfect information” means the policy observation contains opponent-private
  cards. Empires' live policy seam currently also receives the full game state,
  so allowing this makes the systems closer; it must still be labeled because
  it changes what the resulting difficulty means.
- “Bounded trading” means the foreign rules engine permits only one-resource
  offers—give one or two of one resource for one of another—and at most three
  offers per turn. More importantly, AlphaBot's search removes `ProposeTrade`
  whenever any non-proposal move exists, so the measured agent is not evidence
  of a strong, expressive trade negotiator.
- “Its own opponents” means the three opponents were written in the same
  repository. They were not humans, Empires bots, JSettlers, Catanatron, or an
  independently selected champion. This is a valid internal benchmark but can
  reward specialization against that particular heuristic.
- AlphaBot is a hybrid. A PPO reinforcement-learning network trained through
  self-play ranks the currently legal moves; the search keeps its top eight and
  simulates 96 possible futures for each using the repository's Rust rules
  engine. It then chooses the move with the best average outcome. Both the
  MIT-licensed source and trained `.pt`/`.ctnn` weights are public.

Here “Rust engine” means a second implementation of Catan written in the Rust
programming language, not a REST web service. Empires' authoritative engine is
written in Swift. The games are broadly the same, but their board coordinates,
state fields, action numbering, trade protocol, phase transitions, and some
rules contracts differ. The trained weights therefore cannot understand an
Empires state directly, just as a chess model cannot interpret another chess
program's internal numbers merely because both programs implement chess.

Empires also does not currently ship a neural network. It ships the hand-written
heuristic policy. The state encoder, action encoder, training exporter, and
failed experimental learners are infrastructure for a future model, not a
trained production network comparable to AlphaBot.

The useful answer is split by evidentiary role:

| Question | Best answer located | What that answer does and does not mean |
| --- | --- | --- |
| Best **runnable permissive** four-player package | [Eli6th/catan-rl](https://github.com/Eli6th/catan-rl) `AlphaBot` | MIT, shipped model, exact command, fast Rust engine. The current command was rerun locally at 83/100 and 157/192 (81.8%) against three in-project heuristics. This validates the package, not universal strength |
| Best published result under the closest ordinary four-player contract | [Dobre & Lascarides 2018](https://ojs.aaai.org/index.php/AIIDE/article/view/13014), POMCP-TS-CR | 53.65% over 2,000 games versus three STAC agents at 40,000 planning iterations, with 10 VP, hidden hands, and player trading. It is the strongest located result in that ecosystem, not a turnkey public policy or cross-project winner |
| Best large-sample published 1v1 external comparison | [Gendre & Kaneko 2020](https://arxiv.org/abs/2008.07079) | 56.5% over 10,000 games versus JSettler, but two-player and no player trading; no reusable public checkpoint was located |
| Best published trade-only result | [Cuayáhuitl, Keizer & Lemon 2015](https://arxiv.org/abs/1511.08099) | 53.36% over 10,000 four-player games versus three heuristic traders. JSettlers chose every non-trade move, so this supports a separate negotiation policy rather than a complete bot |
| Best evaluation discipline | [PeterLP123/catanatron-1v1](https://github.com/PeterLP123/catanatron-1v1) | Frozen parents, paired schedules, every-chair accounting, intervals, retained failures, and machine-readable summaries. Its game is two-player, 15 VP, balanced dice, friendly robber, and no player trades; the retained policy still lost most games to its hard `F` baseline |
| Best public rules/comparator lineage | [JSettlers2](https://github.com/jdmonin/JSettlers2), STAC, and [Catanatron](https://github.com/bcollazo/catanatron) | Mature reference engines and useful external controls. They do not establish one modern champion, and their GPL-family code should remain outside the current closed/TestFlight app |

Therefore the first public agent to **cross-evaluate** is Eli6th AlphaBot. The
best published architecture to study for standard-ish hidden-information play
is Dobre's POMCP work. Those are different answers; pretending they are one
ranking would choose for convenience instead of evidence.

### Normalized result boundaries

| Candidate | Reported or observed result | Contract behind the number | Decision value |
| --- | --- | --- | --- |
| Eli6th `AlphaBot` | Published 82%; this audit reran 83/100 and 157/192 (81.8%) | Four players, perfect information, bounded trades, candidate fixed in chair 0, three self-authored heuristics. The ledger says first-to-7, but the shipped CLI has no target flag and actually used its 10-point default | **Lead runnable candidate.** The protocol contradiction prevents an exact historical reproduction; no external opponent or chair rotation yet |
| Dobre POMCP-TS-CR | 53.65% | Four players, 10 VP, hidden opponent holdings, full trading, 2,000 games versus three STAC agents, 40k planning iterations | **Lead published standard-ish result.** Tuned against STAC; chairs/seeds unstated; public lineage is not a pinned paper artifact |
| Rubin de Lima MPT-EnsembleUCT | 58.2% | Four players, hidden cards, restricted one-for-one player trades, 10k rollouts versus three unspecified JSettlers | Relevant search/trade evidence, but the headline table omits sample size and no public artifact was located; 58.2 cannot outrank better-specified experiments |
| Gendre cross-dimensional A2C | 56.5% | Two players, 10 VP, hidden opponent holdings, no player trading, 10,000 games versus JSettlers2 2.2.00 | Strong external-comparator evidence for a materially easier game, not four-player Catan |
| Cuayáhuitl trade DRL | 53.36% | Four players, 10 VP, 10,000 games; only offer/accept/reject/counter changes | Strong evidence for an independent trade sub-policy; no evidence it should control builds, roads, robber, or cards |
| Szita MCTS | 27% at 1k simulations; 49% at 10k | Four players, perfect information, 100 games versus three JSettlers; candidate does not trade | Search scales, but the sample is small and no reusable implementation was located |
| Charlesworth PPO + root search | 47/100 | Four players, 10 VP, hidden information and trading; search wrapper versus three copies of its own base PPO | Relevant complete-game artifact, but only an internal ablation, old runtime, and no repository license |
| nogulong PPO/trade ONNX | No published completed metric | Four-player, 10 VP, hidden-safe observations, bounded trades; intended 10k comparison versus JSettlers | **Second adapter candidate.** Models exist, but the advertised evaluator is incomplete at the pinned revision and model/result provenance is missing |
| Catanatron alpha-beta depth 2 | 53/100 versus its value-function player | Two players, 10 VP, full state passed to policies; bot does not originate player trades | Useful executable baseline, not a robust strength result |
| SamiKoneru PPO | README says about 94% | Four players versus three random agents; player trading absent/unclear; N and checkpoint absent | Reject the headline as decision evidence until the missing model and result bundle exist |

The complete source-by-source audit is in
[`2026-09-05-open-source-catan-candidates.md`](2026-09-05-open-source-catan-candidates.md),
the commands and observed local outcomes are in
[`2026-09-05-public-catan-reproduction-log.md`](2026-09-05-public-catan-reproduction-log.md),
and the exact Empires compatibility audit is in
[`2026-09-05-catan-agent-integration-fit.md`](2026-09-05-catan-agent-integration-fit.md).

### Four meanings of “reuse the best existing AI”

| Reuse mode | Benefit | Failure mode | Empires decision |
| --- | --- | --- | --- |
| Embed another engine and its policy | Fastest way to replay the author's result | Two rule engines drift on setup, bank shortages, robber, cards, awards, trading, and victory; foreign runtime enters iOS | **Reject as product architecture.** Keep foreign engines as developer-side benchmarks |
| Import pretrained weights unchanged | Avoids training cost | Weights are inseparable from their exact coordinates, observations, actions, rules, and visibility | **Not a drop-in option.** No public checkpoint consumes Empires' 5,182-feature state and 9,335-action contracts |
| Build a narrow reactive adapter | Fast test of whether learned rankings transfer | Unsupported states fall back; a high fallback rate means the result is still mostly our heuristic | **Run as a research bake-off.** Compare frozen heuristic, heuristic + Eli reactive logits, and heuristic + nogulong logits; Empires remains the only legality/transition engine |
| Reimplement the winning idea natively and retrain | Exact Empires rules, one engine, controllable visibility and latency | More engineering/training; public headline may not survive | **Preferred production route.** Use permissive code where it genuinely helps, or reproduce the published method against Empires' contracts |

Eli6th's 82% agent cannot be “dropped in”: `AlphaBot` clones and advances its
own Rust state to run full-game rollouts, and filters trade proposals from that
search. Its strongest transferable hypothesis is policy-prior-guided terminal
rollouts. The same project's reactive PPO plateaued around 65%, unguided deep
rollouts reached 72.5%, and policy-guided full rollouts reached 82%; value-leaf
variants fell to 15.8–38.3%. That is a good reason to test an Empires-native
learned prior plus real rollouts, not a reason to ship its foreign engine.

### Decision gates before selecting PPO, search, or another training stack

1. Preserve the observed Eli6th baselines, pinned source/model hashes, commands,
   and raw output. Resolve the historical 7-versus-current-10-point mismatch
   and rotate the candidate through every chair.
2. Obtain nogulong's exact JSettlers dependency revision and result provenance;
   its core 142 Rust tests pass, but the published checkout cannot currently
   reconstruct the advertised evaluator unchanged.
3. Build the narrow `H`, `H + E`, and `H + N` adapter feasibility arms. All use
   the same frozen Empires heuristic fallback and count every unsupported move
   by phase and reason. Search remains off for this gate.
4. Prove coordinate, seat, resource, phase, visibility, and legal-action
   translation on a frozen scenario corpus before running strength games.
5. Run exact Empires rules at three and four seats, 10 VP first, every chair,
   common held-out seeds, zero illegal moves, full completion accounting, and
   Mac plus iPhone p50/p95/p99 inference latency. A high fallback rate or a win
   rate against random players cannot pass this gate.
6. If a reactive adapter transfers, use it as a teacher/prior. Then test the
   smallest Empires-native policy-guided rollout arm. Only after those results
   should the 4090 be committed to PPO, league self-play, AlphaZero-like
   iteration, or another long training program.

This sequence answers the practical reuse question before it makes an expensive
algorithm choice. It also preserves the option to conclude that the current
Empires heuristic plus native search is better than either public checkpoint.

### Strategic play and character behavior stay separate

The proposed two-layer product architecture is sound:

- The **strategic core** returns a typed legal move and stable facts such as
  target, utility, alternatives, and reason codes. It may evolve from heuristic
  to adapter, search, or learned policy.
- The **character layer** observes real game events and those stable facts,
  then selects authored lines for “you robbed me,” “I took Longest Road,” “that
  trade helps my city,” rivalry, winning, and losing. This does not need an LLM
  initially; character-specific variants, cooldowns, and recent-line history
  make it expressive, cheap, deterministic, and testable.
- A small local model may later paraphrase supplied facts. A hosted LLM belongs
  only in a deliberate free-form-chat feature with latency, cost, privacy, and
  safety controls. Neither renderer may mutate game state or invent moves.
- If “cheat model” literally means hidden-hand access rather than “chat model,”
  keep it out of normal play. It can be an explicit experimental mode, never an
  accidental property of the production policy.

### Licensing boundary

Not planning to make money does **not** waive copyright or license terms. MIT
permits commercial and noncommercial reuse but requires its copyright and
permission notice to accompany copies or substantial portions
([MIT text](https://opensource.org/license/mit)). GPL/AGPL conditions concern
conveying/distributing covered work, not charging money
([GPLv3](https://www.gnu.org/licenses/gpl-3.0.en.html)). A public repository with
no license does not grant general permission to copy, modify, or distribute its
code or weights
([GitHub licensing guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)).
TestFlight sends beta binaries to testers, so copied code inside a beta should
not be treated as purely private local use
([Apple TestFlight](https://developer.apple.com/testflight/)).

For Empires, MIT code is the low-friction reuse path after notices, dependency,
model, data, and asset provenance are recorded. GPL/AGPL and unlicensed
implementations stay as external research tools or clean-room specifications
unless a deliberate release decision and qualified legal review say otherwise.
This is an engineering risk classification, not legal advice.

## Algorithm-family fit for Empires

| Family | Best use here | Main risk | Discovery verdict |
| --- | --- | --- | --- |
| Hand heuristics / tuned evaluator | Shipping fallback, explanations, style controls, rollout policy, scenario oracle | Brittle interactions and a likely long-horizon ceiling | Keep and instrument; do not mistake more weights for a final answer |
| Flat supervised policy | Validate data/codec and bootstrap a stronger learner | Copies teacher flaws; class imbalance rewards locally common actions | Plumbing baseline only; already shown insufficient |
| Structured behavior cloning | Initialize board-aware policy heads from heuristic/search choices | Still imitates the target quality | Worth a bounded prototype after action/representation audit |
| PPO / masked actor-critic | High-throughput self-play improvement with one network for all seats | Sparse delayed reward, multiplayer nonstationarity, cycles, action imbalance, policy collapse | Plausible, not privileged; require mixed/frozen league evaluation |
| MCTS / stochastic rollouts | Long-horizon tactical lookahead and a teacher independent of heuristic scores | Chance/trade branching and current Swift throughput make full rollouts expensive | Re-test only with a better evaluator, faster simulator, or learned prior |
| ISMCTS / POMCP-style search | Search under hidden hands and sampled beliefs | Requires a credible generative belief/opponent model; huge variance and branching | Later hidden-information track, not the first baseline |
| AlphaZero-like policy/value search | Combine a learned prior, search, and search-improved targets | Ordinary AlphaZero assumptions do not cover 3/4-player general-sum hidden-information negotiation; value quality is hard | Promising empirical hypothesis after throughput and structured baseline gates |
| CFR / NFSP / ReBeL-like methods | Potentially useful for bounded negotiation or simplified information subgames | Most guarantees/results target two-player zero-sum games; full Catan is multiplayer general-sum | Research reference, not first full-game implementation |
| Direct LLM move selection | Low-frequency hypothesis generation or explanations | Cost, latency, nondeterminism, hallucinated state, weak numeric planning, no strong Catan evidence | Do not use as per-action authority |
| Hybrid typed policy + language renderer | Strong/cheap legal play with expressive, replaceable character voice | Requires disciplined boundary and coherent context | Preferred product architecture hypothesis |

Relevant general primary sources include [PPO](https://arxiv.org/abs/1707.06347),
[ISMCTS](https://eprints.whiterose.ac.uk/id/eprint/75048/),
[NFSP](https://arxiv.org/abs/1603.01121),
[ReBeL](https://arxiv.org/abs/2007.13544), and
[Gumbel AlphaZero](https://openreview.net/forum?id=bERaNdoegnO). Their algorithmic
results do not erase Empires' multiplayer, general-sum, stochastic,
partial-information, and negotiation-specific constraints.

## Trade AI: diagnose before tuning

The current accept/reject result is a single thresholded score. To explain
“they reject all my trades” and to support personality or learning, every
evaluated offer should emit a structured decision record with:

- game/build/seed/turn/seat/offer identifiers and information policy;
- exact offered and requested bundles;
- value of each resource before and after the trade;
- closest build objective and cards still missing;
- immediate-build unlocks for each party;
- best bank/port alternative and opportunity cost;
- proposer threat, receiver standing, and repeat-trade adjustment;
- personality/style adjustment;
- raw utility, final threshold, decision, and one stable reason code;
- best acceptable counteroffer, if one exists;
- later outcome labels: accepted, build achieved, points gained, and winner.

The semantic policy should return a typed result such as `accept`, `reject`,
`counter(offer)`, or `propose(offer)`, plus reason codes. A renderer can then
say the same strategic fact in fifty civilization-specific ways without
changing the decision. “Crazy trades” should mean a bounded, recognizable
style—risk appetite, generosity, bluff, urgency, grudge, or kingmaking guard—
not random illegal or obviously losing offers.

The first trade benchmark should be a hand-written scenario corpus: obvious
accepts, obvious rejects, build-unlocking concessions, bad bank alternatives,
leader feeding, reciprocal trades, repeated exploitation, and counteroffers.
Simulation aggregates come second; human judgment comes third.

## Road AI: represent intent, not just an edge score

A good road is usually the first step of a plan. The evaluator therefore needs
to log a plan and alternatives, not merely “edge 17 scored 4.8”:

- target settlement vertex and expected production/diversity gain;
- target port and conversion value;
- path length, remaining resource cost, and probability the target survives;
- connection of fragmented networks;
- block/contest value against each opponent;
- Longest Road claim, defense, or denial value;
- dead-end and self-block penalties;
- whether the chosen edge advances the prior turn's target;
- component score for every legal edge and why the winner beat runner-up;
- realized follow-through: target reached, stolen, abandoned, or made obsolete.

Start with curated board-state tests drawn from the failures Alex saw. A future
learned policy/search can then be compared on the exact same scenarios and
intent outcomes rather than on win rate alone.

## Personality, difficulty, and dialogue contracts

### Personality is a vector of behavior, not a label

An opponent profile may independently specify:

- expansion versus consolidation preference;
- development-card/army appetite;
- blocking and robber hostility;
- trade frequency, concession budget, reciprocity, and exploitation response;
- risk tolerance and willingness to pursue long plans;
- preferred strategic archetype and plan persistence;
- emotional/social state used only for future decisions explicitly designed
  to consume it.

Each axis needs an opportunity-normalized metric and blind recognition test.
If players cannot identify “aggressive” above chance from replays or games,
the label is decoration.

### Difficulty is calibrated strength

Difficulty may vary checkpoint/policy quality, search budget, or bounded
decision noise. It must not silently change a character's identity. A tier is
shippable only when it:

- occupies a declared win-rate band against a frozen opponent population in
  every supported product cell;
- remains ordered on untouched seeds with chair rotation and confidence
  intervals;
- completes games and preserves legality/determinism;
- preserves the profile's declared style within tolerance; and
- feels ordered in human playtests, not only bot-vs-bot statistics.

### Dialogue renders strategy

Do not begin by designing a dialogue-class hierarchy. Begin with the game events
and strategic facts the engine already knows: speaker, target, what happened,
the resources in an offer, and—once the strategy can provide it—the reason for
the choice. A small character renderer should choose deterministic authored
variants keyed by civilization, event, and recent-line history. This is cheap,
offline, testable, and can already cover being robbed, taking or losing Longest
Road, accepting or rejecting a trade, rivalry, winning, and losing without
making dialogue part of the strategic policy.

An optional LLM renderer can later paraphrase those supplied facts under a strict schema,
cache, latency deadline, moderation policy, and deterministic fallback. It must
never receive authority to alter an offer, choose a move, reveal hidden state,
or invent a rule. Free-form player chat affecting policy is a separate product
and safety decision.

| Language path | Advantage | Product cost / constraint |
| --- | --- | --- |
| Authored tagged phrases or grammar | Offline, instant, exhaustive factual/editorial control, exact replay | Authoring coverage and repetition management |
| [Apple's on-device Foundation Models](https://developer.apple.com/documentation/FoundationModels/) | Offline generation without bundling a custom model | Only Apple-Intelligence-capable devices; system model changes with OS, so save output and retain authored fallback |
| [Custom Core ML language model](https://developer.apple.com/documentation/coreml/) | Pin exact artifact and run locally | App/download size, conversion, memory, energy, device matrix, model/data license |
| Hosted LLM | Fastest iteration and broadest fluency | Backend/credentials, metered cost, variable latency/output, privacy/retention review, moderation, outage fallback |

No path should be selected from capability alone. Benchmark it against the
authored baseline on blind preference, semantic fidelity, repetition,
p50/p95/p99 latency, cost per median game, offline behavior, and exact replay.

This separation follows the broader negotiation result that strategic acts
and language generation are easier to control when decoupled
([He et al. 2018](https://aclanthology.org/D18-1256/)).

## Evaluation contract

No candidate advances on one metric. Every report must include:

1. **Correctness:** zero illegal moves, invariant failures, crashes, or codec
   mismatches; deterministic reproduction where the policy promises it.
2. **Completion:** decisive rate and move-count distribution for every
   supported player-count × VP-target × board-mode cell.
3. **Strength:** paired common seeds, complete chair rotation, clustered
   intervals, and a frozen *pool* (shipping heuristic, Greedy, random only as
   a floor, prior candidates, and reproduced external agents where possible).
4. **Robustness:** a cross-play matrix, not one Elo number. Multiplayer policy
   cycles and opponent exploitation can hide behind a scalar rating.
5. **Behavior:** opportunity-normalized trade, road, build, card, robber, plan,
   and style metrics.
6. **Human experience:** blind style recognition, perceived fairness,
   frustration, negotiation quality, and fun.
7. **Product cost:** p50/p95/p99 decision latency on target iPhones, model and
   peak-memory size, energy/thermal behavior, offline availability, cloud cost,
   and failure fallback.
8. **Provenance:** source commit, executable/model hashes, layout versions,
   seeds, hyperparameters, information policy, and retained raw reports.

Strength claims use table-size-aware nulls (1/3 or 1/4), never 50%, and do not
pool unlike configurations merely to produce a narrower interval.

## Ordered research program and kill gates

### R0 — freeze the question and benchmark suite

**Build:** an AI evaluation manifest listing exact product configurations,
frozen policies, development seeds, untouched final seeds, scenario fixtures,
latency devices, and promotion metrics.

**Exit:** one command produces a reproducible current-policy report and a
cross-play matrix; trade/road scenario fixtures reproduce Alex's complaints.

### R1 — add decision observability

**Build:** structured trade explanations and road-plan traces described above,
plus analyzers that use opportunity denominators.

**Exit:** every rejection and road choice has a stable reason, runner-up, and
component breakdown; replay can connect choice to later outcome.

**Kill:** do not tune weights if a failure cannot first be expressed as a
fixture or trace.

### R2 — reproduce public reference systems

**Build:** separate, disposable benchmark adapters for the most promising MIT
systems, starting with `Eli6th/catan-rl` and `nogulong/rust-catan-rl`; run their
own checks before cross-engine comparison.

**Current evidence:** Eli6th's first-party evaluator and tests run, with
83/100 and 157/192 (81.8%) AlphaBot wins; the 7-versus-10-point protocol drift
prevents an exact historical reproduction. Nogulong's core tests pass, but its
full evaluator is not reconstructible from the pinned checkout because the
JSettlers revision is omitted.

**Exit:** reproduce or falsify headline results, document exact rule deltas,
then play same-policy or matched-scenario comparisons where valid.

**Kill:** do not port a model whose result cannot be reproduced, whose license
is incompatible, or whose rules/observation contract explains the advantage.

### R3 — profile the 4090 path before redesigning the engine

**Measure separately:** Swift environment steps, JSON/data transfer, batch
observation encoding, GPU inference/training, and evaluation. A 4090 speeds
matrix work; it does not accelerate a serial Swift simulator by itself.

**Exit:** measured steps/second and games/hour identify the actual bottleneck,
and a small end-to-end training run reproduces byte/version provenance.

**Decision:** keep Swift plus batched inference, add a narrow FFI simulator, or
build a second fast environment only after the profile. A second engine must
pass cross-engine differential traces before training data is trusted.

### R4 — structured policy/value baseline

**Build:** a board-aware encoder (graph or canonical board blocks), phase-aware
or autoregressive action heads, exact masks, and whole-game train/test splits.
Begin with behavior cloning only to validate optimization and deployment.

**Exit:** beats phase and flat baselines offline, then completes legal live
games without pathological action distributions. It is not promoted on
imitation accuracy alone.

**Decision:** profile the existing 9,335-way masked head before changing it.
If gradients/data are dominated by Road Building pairs and discard bundles,
decompose them into sequential atomic choices under a new action-layout
version. The new MIT Rust reference uses exactly that pattern—one discard card
or road location per decision—and fits its more restricted trade rules into
299 global actions. That is useful design evidence, not proof that 299 is the
right Empires shape. Do not refactor pre-emptively.

### R5 — self-play and opponent-population experiment

**Build:** masked PPO or another reactive learner initialized from R4, trained
against self-play plus frozen/mixed opponents and a checkpoint league.

**Exit:** beats the structured imitation candidate and at least one frozen
competent policy on development seeds; no collapse, illegal moves, completion
regression, or exploitative cycle in the cross-play matrix.

**Kill:** random-bot dominance or training loss improvement alone is failure.

### R6 — policy-guided search experiment

**Build:** compare unguided stochastic rollouts, learned-prior candidate
selection, and outcome-trained value leaves under equal decision budgets.
Label perfect-information runs as diagnostic upper bounds.

**Exit:** paired strength gain over R5 with target-device p95 inside the pacing
budget. The value must be trained/evaluated as a position-outcome estimator,
not assumed useful because a PPO critic has good aggregate explained variance.

### R7 — hidden-information experiment

**Build:** train/evaluate under `publicCountsOnly`; then compare recurrence,
opponent models, belief sampling, and information-set search only if simple
partial-observation learning leaves measurable headroom.

Masking today's private values is necessary but not sufficient. Two positions
with the same public snapshot can imply different holdings because their
public production, spending, stealing, and offer histories differ. The fair
policy contract therefore needs either a versioned public history, recurrent
state, or explicit belief—not just zeroes in opponent hand slots.

**Exit:** no private-information leakage; fair-play strength and behavior are
measured anew. Perfect-information results are not carried over.

### R8 — difficulty calibration and product integration

**Build:** freeze candidates into explicit tiers, convert/export with strict
layout checks, benchmark real devices, and retain the heuristic fallback.

**Exit:** all evaluation-contract dimensions pass and human play supports the
labels. Only then add a difficulty selector.

### R9 — character language, then optional chat

**Build first:** stable game-event keys plus authored contextual variants for
trades, blocks, robber moves, races, victories, and grudges.

**Experiment later:** LLM paraphrase and, separately, chat intent parsing.

**Exit:** no hidden-state leak, semantic drift, move mutation, unacceptable
latency/cost, or missing offline fallback. Human raters prefer the experience.

## Decisions deliberately deferred

- Final strategic algorithm and model architecture.
- Whether a second high-speed engine is worth its differential-testing cost.
- Reveal-all versus realistic hidden holdings for the shipping bot.
- Exact network topology and whether the global action space is decomposed.
- Difficulty names, number of tiers, and which characters occupy them.
- Whether relationship state ever affects strategy rather than dialogue only.
- Any cloud LLM dependency or free-form chat feature.

## Immediate next deliverable

The next implementation should finish **R0 + R1**—freeze an evaluation
manifest, add trade-decision explanations, add road-plan/alternative traces,
and encode the observed bad decisions as scenario tests—then run the narrow
`H`, `H + E`, and `H + N` adapter-feasibility gate defined above. This improves
every later path without selecting PPO, POMCP, AlphaZero, or an LLM by taste.

R2's unchanged-package work is now partially complete, so the adapter gate and
R3's 4090 pipeline profile can proceed independently once R0/R1 define the
shared evidence. Their measured results determine whether the first serious
Empires candidate is a transferred reactive prior, an Empires-native search
hybrid, or neither.

## Related Empires evidence

- [`2026-09-05-open-source-catan-candidates.md`](2026-09-05-open-source-catan-candidates.md)
- [`2026-09-05-public-catan-reproduction-log.md`](2026-09-05-public-catan-reproduction-log.md)
- [`2026-09-05-catan-agent-integration-fit.md`](2026-09-05-catan-agent-integration-fit.md)
- [`2026-09-05-current-ai-baseline.md`](2026-09-05-current-ai-baseline.md)
- [`2026-09-05-algorithm-options.md`](2026-09-05-algorithm-options.md)
- [`2026-09-05-global-conquest-lessons.md`](2026-09-05-global-conquest-lessons.md)
- [`2026-09-05-personality-trade-dialogue.md`](2026-09-05-personality-trade-dialogue.md)
- [`2026-09-03-ai-approach-evaluation.md`](2026-09-03-ai-approach-evaluation.md)
- [`2026-09-02-ai-baseline-and-personality-audit.md`](2026-09-02-ai-baseline-and-personality-audit.md)
- [`2026-09-02-personality-separation-results.md`](2026-09-02-personality-separation-results.md)
- [`2026-09-02-consolidation-metric-results.md`](2026-09-02-consolidation-metric-results.md)
- [`2026-09-02-opponent-profile-decision-log.md`](2026-09-02-opponent-profile-decision-log.md)
- [`2026-09-03-creative-bot-trade-offers.md`](2026-09-03-creative-bot-trade-offers.md)
