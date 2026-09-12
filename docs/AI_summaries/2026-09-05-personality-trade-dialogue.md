# Empires AI audit: personality, trade acceptance, and dialogue

Date: 2026-09-05
Code baseline: `6ec560df96d0617b39359a20fbf628814e043a30`
Status: research and audit only; no implementation and no architecture selection

**Historical baseline.** The September 12
[personality scope](2026-09-12-personality-scope.md) is the current product proposal.
Current code has structured trade assessments and defaults all new opponents to
Balanced; the Boolean-only and civilization-to-strategy claims below describe
September 5. Runtime LLMs and free-form chat are now outside the agreed scope.

## Scope

This document audits the current Empires bot personality, trade-decision, opponent-profile, and dialogue systems. It separates four concerns that are easy to conflate:

1. playing strength and difficulty;
2. strategic style and preferences;
3. opponent modelling and negotiation policy; and
4. language realization and character voice.

It also compares possible language and negotiation approaches, defines the instrumentation required to diagnose the report that bots reject too many human trades, and identifies evaluation and operational constraints. It deliberately does **not** choose heuristics, search, reinforcement learning, a local language model, a hosted language model, or a hybrid as the final architecture.

## Executive findings

1. **Empires does not have difficulty levels.** Balanced, Aggressive, and Cautious are style presets applied to one heuristic policy and one shared `BotWeights.default`; measured win-rate intervals overlap. Presenting those labels as Easy/Medium/Hard would be unsupported.
2. **Only three strategic-style differences have been demonstrated.** Aggressive uses playable knights more often, Cautious proposes player trades more often when one is available, and Cautious captures a buildable-city opportunity more often. Leader targeting, trade acceptance, and strength ordering have not been separated.
3. **`OpponentProfile` is a useful identity snapshot, not an opponent model.** It binds a stable general, civilization, voice, and one of three strategy labels. It does not learn a human's resource preferences, likely holdings, tolerance for ratios, reciprocity, or prior negotiating behavior.
4. **The current acceptance rule cannot explain a rejection.** `TradeHeuristics.evaluate` returns one Boolean. The app then gives unaffordable offers and strategically rejected offers the same character-flavored rejection treatment.
5. **Balanced and Cautious currently have the same base acceptance bar.** The floor clamps both to `0.4`; Aggressive starts at `0.58`. This matches the held-out result in which acceptance rates were 47.9%, 46.6%, and 48.0%, respectively.
6. **The acceptance documentation overstates what its build-target ordering does.** Resource valuation sums all four targets, so reordering city and settlement targets is mathematically irrelevant inside `resourceValue`. Expansion bias can break equal-deficit ties when proposing a trade, but it does not make acceptance value a city before a settlement.
7. **The measured bot-to-bot acceptance rate does not refute the human complaint.** Human offers may be unaffordable, clustered near the threshold, or disproportionately trigger leader/unlock penalties. Existing telemetry cannot distinguish those hypotheses.
8. **Dialogue is safely cosmetic today, but semantically blind.** It receives only empire, offer ID, and accept/reject. It cannot mention the offered resources, ratio, affordability, policy margin, strategic concern, or a truthful rejection reason.
9. **The 208 authored lines provide breadth, not contextual variety.** A stable UUID-to-pool index prevents flicker, but a content-derived bot offer repeats the same line whenever the same offer recurs. Reordering a phrase pool also changes old saved offers' rendered text.
10. **Current character writing needs an editorial safety pass.** Several pools rely on threats, insults, and broad cultural caricatures. That may be an intentional playful tone, but tests cover length and duplicates—not cultural quality, age-rating fit, truthfulness, or harm.
11. **Catan-specific research supports semantic negotiation as its own policy surface.** Prior systems learned or modelled offers, accept/reject, and counteroffers as structured game acts while legal actions remained constrained by the game. That evidence does not establish that Empires should use RL.
12. **Personality language can be independently parameterized.** Natural-language-generation research demonstrates that surface style can vary while preserving a fixed communicative goal. That is directly relevant to keeping character voice from changing game decisions.
13. **Any generated language must be replay data, not a reproducibility assumption.** Apple documents that its system model changes with OS releases; hosted APIs document variable outputs and changing model behavior. An exact replay therefore requires persisting the chosen utterance, not merely a prompt, seed, or model name.
14. **Chat influencing policy is a separate, high-complexity product.** It needs a typed dialogue-act layer, a commitment/opponent model, legal-action validation, abuse handling, and new evaluation. It should not be smuggled into a text-realization feature.

## 1. The four independent layers

| Layer | Product question | Current Empires mechanism | What is established | What remains unknown |
| --- | --- | --- | --- | --- |
| Strength / difficulty | How hard is this opponent to beat? | One heuristic implementation and shared weights; no difficulty field | Heuristic policies reliably finish games and beat the frozen Greedy anchor in the recorded regression setup | No calibrated ladder, target win rates, handicap design, or human-skill matching |
| Strategic style / preferences | What choices does this opponent favor at roughly comparable strength? | Three scalar presets: aggressiveness, trade willingness, expansion bias | Three opportunity-normalized differences are supported | Whether people can identify the styles blind; many intended axes still overlap |
| Opponent model / negotiation policy | What does this opponent believe about another player, and what offer/reply maximizes its objective? | Current state, resource-deficit values, threat/standing shifts, one-turn suspicion, and immediate-affordability guard | Several hand-authored scenarios behave as intended | No learned or persistent partner model, calibrated utility, counteroffers, or rejection trace |
| Language realization / character voice | How does an already-selected intent sound? | Civilization-specific complete-sentence phrase pools selected by offer UUID | Deterministic within an unchanged phrase-bank version; compact enough for the card | No semantic grounding, conversation memory, no-repeat policy, localization, safety review, or human recognition study |

The distinction is causal, not cosmetic. Increasing a bot's win rate is not the same as making its style recognizable. Making a bot sound generous is not the same as making it accept more trades. Learning that a human values ore is not the same as giving the Roman general a Roman-sounding line. Each layer needs its own state, metrics, and acceptance gate.

## 2. Current-system audit

### 2.1 Personality and profile composition

[`BotPersonality.swift`](../../Packages/CatanAI/Sources/CatanAI/BotPersonality.swift) exposes three values:

| Preset | Aggressiveness | Trade willingness | Expansion bias |
| --- | ---: | ---: | ---: |
| Balanced | 0.50 | 0.50 | 0.50 |
| Aggressive | 0.90 | 0.20 | 0.75 |
| Cautious | 0.15 | 0.80 | 0.30 |

Those values reach setup placement, building, robber targeting, development-card use, trading, and move-category priority. [`BotWeights.swift`](../../Packages/CatanAI/Sources/CatanAI/BotWeights.swift) then supplies dozens of shared coefficients. This is a compact tuning surface, but it has three consequences:

- a style edit can accidentally change strength because one scalar influences several decisions;
- labels describe bundled intentions rather than orthogonal traits; and
- there is no independent difficulty axis or per-difficulty weight set.

[`OpponentProfile.swift`](../../Settlers/Models/OpponentProfile.swift) improves identity stability by snapshotting one of eight named generals, its civilization, and an `OpponentStrategy`. `dialogueVoice` derives from civilization; `strategicPersonality` derives from strategy. Difficulty is deliberately absent. That separation is conceptually sound, but the catalog still fixes one strategy to each civilization, so voice and strategy are not independently selectable in the current product.

The profile is also not an opponent model in the AI sense. It describes **the bot itself**. There is no durable structure describing what Alexander believes Alex tends to accept, what resources Alex appears to seek, whether Alex reciprocates, or how reliable Alex's chat claims have been.

### 2.2 What personality measurements actually support

The held-out, every-chair evaluation in [`2026-09-02-personality-separation-results.md`](./2026-09-02-personality-separation-results.md) supports:

- Aggressive chose a Knight when playable 42.3% of the time versus Balanced's 15.4% (`+26.9` percentage points; seed-cluster bootstrap 95% CI `+24.4` to `+29.5`).
- Cautious proposed a player trade when one was available 63.0% of the time versus Balanced's 39.9% (`+23.1` points; 95% CI `+21.5` to `+24.7`).
- The later consolidation run in [`2026-09-02-consolidation-metric-results.md`](./2026-09-02-consolidation-metric-results.md) found Cautious chose a city in 99.5% of buildable-city opportunities versus Balanced's 93.0% (`+6.5` points; 95% CI `+3.1` to `+10.3`).

The evidence does **not** support:

- a difference in acceptance of affordable incoming player trades: Balanced 47.9%, Aggressive 46.6%, Cautious 48.0%;
- a meaningful difference in targeting the highest-public-VP robber victim;
- a strength ordering: the frozen-anchor intervals overlap; or
- a claim that a human can recognize any style during play.

These measurements are opportunity-normalized, which is the right standard: “Cautious built more cities” would otherwise conflate preference with having more chances to build a city. [`PolicyBehaviorMetrics.swift`](../../Packages/CatanAI/Sources/CatanAI/PolicyBehaviorMetrics.swift) already records the exact legal-action opportunity for several choices. It does not yet record why a trade crossed or missed its threshold.

### 2.3 Exact trade-acceptance rule

[`TradeHeuristics.evaluate`](../../Packages/CatanAI/Sources/CatanAI/TradeHeuristics.swift) calculates:

```text
gainValue       = marginal value to receiver of cards received
costValue       = marginal value to receiver of cards surrendered
netGain         = gainValue - costValue

baseThreshold   = max(0.4, 0.7 - tradeWillingness * 0.6)
threatShift     = (proposerRelativeThreat - 1.0) * 0.5
standingShift   = (receiverRelativeStanding - 1.0) * 0.25
suspicionShift  = proposerAcceptedTradesThisTurn * 0.35
unlockShift     = 0.6 if proposer newly affords a settlement or city, else 0

threshold       = max(0, baseThreshold + all shifts)
accept          = netGain > threshold
```

The base thresholds are therefore:

| Preset | Calculation | Base threshold |
| --- | --- | ---: |
| Balanced | `max(0.4, 0.7 - 0.5×0.6)` | 0.40 |
| Aggressive | `max(0.4, 0.7 - 0.2×0.6)` | 0.58 |
| Cautious | `max(0.4, 0.7 - 0.8×0.6)` | 0.40 |

The comparison is strict: a margin equal to the threshold is rejected.

#### What is good about the rule

- It is deterministic and inexpensive.
- It values resources in the receiver's context rather than treating every card as equal.
- It guards against feeding a threatening proposer, trading while comfortably ahead, enabling an immediate high-value build, and allowing one proposer to work the table repeatedly in one turn.
- Its parameters are named and injectable through `BotWeights`, rather than scattered literals.
- The policy still chooses from the legal move set supplied by the engine.

#### What prevents a trustworthy diagnosis

1. **Boolean-only output.** The app cannot distinguish “I cannot pay,” “the deal is bad for me,” “you are leading,” “this completes your settlement,” or “you already completed another trade this turn.”
2. **Solvency is outside the evaluator.** `GameViewModel.resolveHumanProposedTrade` checks whether a bot holds the requested cards before calling `evaluate`; both paths become the same `accepted: false` presentation tuple. Other callers rely on legal-action construction. The evaluator alone is not a complete decision record.
3. **Balanced and Cautious collapse at the floor.** `tradeWillingness` strongly changes proposal priority, but it does not separate their base acceptance threshold. The existing measurements reflect that collapse.
4. **The build-target comment and computation disagree.** `resourceValue` says it values the “closest” target and `buildTargets` says expansion bias prioritizes city versus settlement. In fact, `resourceValue` loops over and sums settlement, city, development-card, and road contributions. Reordering those terms changes nothing. Expansion bias matters to equal-deficit tie-breaking in `nearestBlockedTarget` for proposals, but not to this acceptance sum.
5. **“Immediate build” means resource-affordable, not legally buildable.** The check does not establish that the proposer has a legal vertex/upgrade, remaining piece, or usable turn opportunity. It can impose a `0.6` penalty for a build that cannot actually happen.
6. **Marginal value is short-horizon.** It does not explicitly price production probabilities, ports as future options, development-card deck state, road access to future sites, turn order, robber exposure, scarcity at the table, or the receiver's best legal alternative.
7. **Opponent impact is coarse.** The proposer penalty uses public threat plus immediate settlement/city affordability. It does not compare the proposer's gain against the receiver's gain as a joint utility calculation or estimate downstream win probability.
8. **Suspicion is one-turn and proposer-wide.** It counts completed trades by the proposer this turn, not this receiver's history with this human. There is no reciprocity, trust, reputation, concession history, or learned reservation price.
9. **No counteroffer.** The response surface is accept/reject. A near-miss and an absurd offer both end as rejection, even if changing one card would make the deal useful.
10. **No partner targeting.** A `TradeOffer` is broadcast and contains no intended recipient. Offer generation cannot deliberately court the player most likely to have or release a resource.
11. **No uncertainty model.** The current policy receives full `GameState`. Whether a production bot may use hidden hands was deliberately deferred elsewhere; there is no separate belief-state evaluator for an observation-only policy.

The complaint “they reject all my trades” is therefore a valid unclosed observation. AI-to-AI acceptance near 48% measures offers generated by the same heuristic family. It says little about the distribution of offers a human naturally makes through the UI.

### 2.4 Offer generation

`TradeHeuristics.proposeTrades` is a deterministic hand-authored proposer:

- find the still-blocked build target with the smallest total resource deficit;
- choose its largest missing resource;
- rank the bot's surplus resources by their value to itself;
- propose one resource type for one resource type, ordinarily in quantities up to two;
- avoid exact pending or previously declined offers;
- after ordinary offers fail, optionally improve a settlement/city-unlocking offer up to one card better than the bot's own bank/port rate; and
- stop after the per-turn retry cap.

This fixed several concrete bugs and produces more plausible ratios than the original one-for-one-only behavior. It still does not optimize over a recipient, predict acceptance, compare several future plans, or negotiate a counteroffer. Proposal policy and acceptance policy are related but independently weak; changing only acceptance can increase completed trades while leaving bot-originated offers unconvincing.

### 2.5 Current dialogue realization

[`TradeMessages.swift`](../../Packages/CatanAI/Sources/CatanAI/TradeMessages.swift) contains eight civilization voices. Each has 10 pitch lines, 8 acceptance lines, and 8 rejection lines: 208 complete authored utterances. Tests enforce deterministic selection for one offer ID, at least eight lines per bucket, disjoint accept/reject pools, no duplicate or blank lines within a pool, and a 38-character maximum.

Selection is:

```text
index = sum(the 16 UUID bytes) mod pool.count
utterance = pool[index]
```

The realizer receives only:

- civilization/empire;
- offer UUID; and
- pitch versus response, plus accepted versus rejected.

It does **not** receive the actual give/want maps, ratio, actor names, reason, policy score, threshold, prior dialogue, turn state, or relationship. `GameViewModel.tradeResponseMessage` makes this explicit by constructing a dummy empty offer carrying only the original UUID.

Consequences:

- a line can be colorful but cannot be an explanation;
- claims such as “fair,” “my castle needs this,” or “honor is satisfied” are not grounded in the actual evaluation;
- the same content-derived bot offer maps to the same line across turns and games;
- no-repeat behavior within a match is impossible because dialogue history is absent;
- changing pool order or membership changes the line rendered for an old offer ID;
- voice is a cultural costume rather than a measured linguistic personality; and
- the current tests cannot catch stereotyping, misleading reasons, tonal mismatch, localization failures, or player fatigue.

The current line set includes mock threats, social-status insults, religious/cultural shorthand, and caricatures associated with real peoples and historical identities. This is not automatically unacceptable in a stylized strategy game, but it is an editorial, age-rating, and localization risk that deserves explicit review rather than being treated as a unit-test-complete asset.

### 2.6 Persistence and replay

Empires has strong engine determinism: state owns the RNG, enumerations are stabilized, fingerprints run across fresh processes, and legal decisions are recorded. The language and negotiation presentation have weaker version guarantees:

- `OpponentProfile` snapshots a stable strategy label, but that label resolves to today's `BotPersonality` constants; it does not freeze the numeric preset or `BotWeights.default` for an in-progress match.
- `restorePendingNegotiation()` recomputes each bot's acceptance with the current heuristic after relaunch. A policy update can change who appears to have accepted a pre-update saved offer.
- response text is recomputed from current phrase pools. It is not snapshotted with the decision.
- bot-generated offer IDs are content-derived for legal-move purity. That supports deterministic selection but makes repeated identical content repeat the same phrase.
- [`TrainingExample.swift`](../../Packages/CatanAI/Sources/CatanAI/TrainingExample.swift) records build provenance, state/action layout versions, seed, decision index, policy ID, legal mask, chosen action, and outcome. It does not record trade-value components, reason codes, an opponent belief, or language output.

This distinction matters: deterministic **game decisions**, deterministic **semantic dialogue acts**, and deterministic **surface wording** are three separate replay contracts.

### 2.7 Test audit

| Existing coverage | What it proves | What it does not prove |
| --- | --- | --- |
| `TradeHeuristicsTests` scenario tests | Clear gain/loss cases; threat, standing, repeat-trade, and immediate-affordability shifts; retries and generous offers; bank fallback | Calibration across realistic human offers; reason attribution; counteroffers; monotonic boundaries; opponent history; human fun |
| Test named `tradeWillingnessShiftsTheAcceptanceBar` | Aggressive and Cautious both reject one exactly break-even trade | Any observed decision difference caused by trade willingness; the name overstates the assertion |
| Comments in older trade tests/specs | Preserve historical rationale | Some still describe the pre-floor `0.5 - willingness` rule and are not current behavioral truth |
| `TradeMessagesTests` | Stable UUID selection, pool breadth, no local duplicates, compact lines | Semantic truth, cultural review, distribution over real content-derived IDs, no repetition in one game, version stability, localization, accessibility |
| `OpponentProfileTests` and integration tests | Complete civilization mapping, stable profile persistence, strategy follows the general rather than the chair | Independent voice/style selection, dynamic opponent modelling, recognizable persona, difficulty |
| `PolicyBehaviorMetrics` and paired simulator analysis | Opportunity-normalized action frequencies and paired seed/chair comparisons | Why a specific trade was rejected; score calibration; user-facing enjoyment; dialogue quality |
| Seeded fingerprints and replay tests | Exact policy trajectory for pinned configurations | Whether that trajectory is strategically good or fun; exact generated text after a model/content update |

## 3. What primary research contributes

### 3.1 Catan-specific negotiation research

The most relevant prior work does not treat prose as an unconstrained game action.

Cuayáhuitl, Keizer, and Lemon trained a Catan negotiation policy over a 160-feature state, 70 offer actions, and three reply actions—accept, reject, and counteroffer. The action set was dynamically constrained to legal offers, and interaction occurred at the **semantic** level; JSettlers handled the rest of gameplay. They report roughly 2,000 training games per learning curve and 10,000 evaluation games per comparison, with their DRL negotiation policy outperforming their baselines in that environment. This is evidence that offer/reply policy can be isolated and evaluated, not evidence that their network, features, reward, or reported win rate transfers to Empires ([Cuayáhuitl, Keizer, and Lemon, 2015](https://arxiv.org/html/1511.08099v1)).

The STAC Catan corpus separates surface speech acts from domain acts such as offer, counteroffer, accept, refusal, strategic comment, resource possession, and resource preference. Its authors emphasize incomplete information, evolving preferences, misleading implications, and discourse commitments. That makes a typed dialogue-act and preference ledger a research-grounded way to study future chat, while also showing why arbitrary text-to-move coupling is not a small feature ([Afantenos et al., 2012](https://www.research.ed.ac.uk/en/publications/developing-a-corpus-of-strategic-conversation-in-the-settlers-of-)).

Cadilhac et al. used Catan chats to dynamically build partial player-preference models and found that tracking preference evolution and reasoning about equilibrium trades both mattered for predicting executed trades. Their experiment used 10 games and more than 2,000 dialogue turns, so it is useful evidence for opponent-model features but not a production accuracy guarantee ([Cadilhac et al., 2013](https://aclanthology.org/D13-1035/)).

A later human-subject Catan study compared rule-based, persuasion, supervised, and deep-RL negotiators through chat. Persuasive arguments included grounded claims such as a resource immediately enabling a settlement. The study reports 62 full games total, with only 9–17 games in each arm, and changed both game and negotiation strategies across some comparisons. Its result is a promising signal that negotiation policy and persuasive explanations affect human play, but the small, between-subject design does not settle Empires' architecture ([Keizer et al., 2017](https://aclanthology.org/E17-2077/)).

Guhe and Lascarides explicitly argue for controlled component changes, simulation performance metrics, and comparison with human corpora when evaluating Catan strategy. That aligns with Empires' existing paired-seed and opportunity-normalized discipline ([Guhe and Lascarides, 2014](https://www.research.ed.ac.uk/en/publications/game-strategies-for-the-settlers-of-catan/)).

Public implementations are useful as benchmarks and sources of experiment ideas, not drop-in truth. [JSettlers](https://github.com/jdmonin/JSettlers2/blob/main/doc/Readme.developer.md) exposes a mature robot/client architecture used by several papers. [Catanatron](https://github.com/bcollazo/catanatron) offers fast simulations, datasets, a Gymnasium environment, and a stated goal of strong Catan play. Catanatron is GPL-3.0, so studying behavior or building an independent benchmark is legally different from copying or linking its implementation into Empires; any reuse would require a license decision first ([license](https://github.com/bcollazo/catanatron/blob/main/LICENSE)).

Gendre and Kaneko's Catan RL work reinforces the practical warning: multiplayer, stochasticity, imperfect information, heterogeneous board structure, and negotiation make this a difficult learning problem. Their result is evidence that specialized representations can matter, not evidence that a single published agent can be transplanted into Empires ([Gendre and Kaneko, 2020](https://arxiv.org/abs/2008.07079)).

### 3.2 Personality-aware language generation

PERSONAGE demonstrates a non-LLM alternative: start from a communicative content plan, then vary sentence-planning and realization parameters such as verbosity, polarity, acknowledgements, hedges, self-reference, formality, and lexical choice. Its 2007 evaluation found that human judges perceived intended variation along extraversion while the generator preserved the dialogue goal ([Mairesse and Walker, 2007](https://aclanthology.org/P07-1063/)). The later trainable system extended this to multiple continuous stylistic dimensions and again evaluated perception with human judges ([Mairesse and Walker, 2011](https://aclanthology.org/J11-3002/)). The domains differ from Empires, but the separation between **what must be communicated** and **how a character says it** is directly applicable.

### 3.3 Systems that couple language and strategy

End-to-end negotiation models can jointly learn language and reasoning, as Lewis et al. demonstrated on a multi-issue bargaining task with hidden reward functions and dialogue rollouts. That establishes feasibility in a bounded research environment, while also illustrating the data and evaluation burden created when policy and wording are learned together ([Lewis et al., 2017](https://aclanthology.org/D17-1259/)).

CICERO is a larger precedent in a different game. Meta describes a planning engine that models likely moves from board state and conversation history, then uses the resulting plan to control a free-form dialogue model. Its architecture is relevant because strategic intent grounds language; its Diplomacy results do not imply that Empires needs comparable complexity ([Meta AI, CICERO](https://ai.meta.com/research/cicero/)). The released code also shows the gulf between a research system and a mobile feature: some training configurations target hundreds of GPUs, human dialogue data is not included, and code and model weights have different licenses ([CICERO repository](https://github.com/facebookresearch/diplomacy_cicero)).

## 4. Option comparison—without selecting one

“Templates,” “retrieval,” and “models” are not single architectures. Each can be used only for wording, or can be allowed to cross into negotiation policy. The table assumes the first five options receive an already-final semantic decision; the last option deliberately crosses that boundary.

| Approach | Core mechanism | Context and voice potential | Latency / cost / privacy | Determinism and safety | Main evidence needed |
| --- | --- | --- | --- | --- | --- |
| Deterministic slot templates | Authored sentence frames fill typed fields such as resource, ratio, and reason | Low-to-moderate variation; very high factual control | Immediate, offline, negligible marginal cost; no data leaves device | Exact replay if template version and choice are persisted; every output can be exhaustively tested | Do truthful explanations feel too mechanical? Can the small card fit every slot combination? |
| Large curated phrase banks | Many complete authored lines, tagged by voice, act, reason, tone, and situation | Strong authored character; coverage grows through editorial work | Immediate, offline, no inference cost; app-size cost is tiny for text | Exact control, but repetition and combinatorial gaps; requires stable IDs rather than array positions | No-repeat rate, tag coverage, blind voice recognition, editorial/cultural review |
| Parameterized grammar | A semantic content plan is realized through deterministic syntax, lexicon, hedges, formality, verbosity, and tone parameters | More compositional variety than complete lines while retaining facts | Immediate and offline; moderate engineering and linguistic-authoring cost | Reproducible with versioned grammar and RNG; grammar combinations need exhaustive validation | Whether controlled dimensions are perceptible and natural in this short-form game domain |
| Retrieval | Select an authored utterance—or authored demonstration—from a tagged corpus using decision semantics and recent dialogue history | High if corpus covers the situation; can avoid recent repeats | Local lexical/tag retrieval is immediate and private; embedding retrieval adds model/runtime cost | Deterministic if features, corpus, scorer, and tie-breaks are versioned; retrieved text remains editorially bounded | Recall/coverage on held-out trade frames, semantic consistency, stable tie-breaking |
| Small local model | Generate or rank wording on device from a compact semantic frame | Higher surface variety and adaptation; quality depends on model and device | No network or per-request server bill, but model download/app size, memory, energy, thermals, and cold-start matter | Sampling and runtime/model updates can change output; must cache text and retain a safe fallback | Device matrix, p50/p95 latency, refusal/error rate, memory/energy, quality and safety evals |
| Hosted LLM, text-only | Send a minimal semantic frame to a server model; receive wording only | Highest general fluency and easiest iteration; can use rich character instructions | Network dependency, variable latency, metered tokens, backend/credential operations, and external data processing | Provider/model changes and sampling prevent exact replay unless output is saved; moderation and fallback required | Real measured latency/cost, outage behavior, privacy review, factuality, safety, and lift over local authored options |
| Chat influences policy | Parse conversation into beliefs, preferences, commitments, offers, or strategic intents that affect decisions | Enables genuine negotiation and relationship behavior | Highest state, UI, moderation, test, and possibly inference cost | Text becomes adversarial input; requires typed acts, confidence/confirmation, legal masks, commitment consistency, and full audit logs | Whether chat improves fun or strategy enough to justify complexity; exploit, abuse, and prompt-injection testing |

### Local-model operational facts

Apple's Foundation Models framework explicitly includes game-character dialogue as an on-device use case; Apple states that the system model runs offline, keeps inputs and outputs on device, and does not increase app size. It is available only on devices that support Apple Intelligence, so it cannot be assumed across Empires' entire iOS deployment range ([Apple Foundation Models](https://developer.apple.com/documentation/FoundationModels/), [WWDC25 overview](https://developer.apple.com/videos/play/wwdc2025/286/)). Apple also documents that the system model changes with OS releases and tells developers to retest/version prompts. That makes its operating cost attractive but its outputs unsuitable as an unsaved replay primitive ([Foundation Models updates](https://developer.apple.com/documentation/Updates/FoundationModels)).

A custom compact model through Core ML is a different option: its artifact can be version-pinned and run without a network, but the app owns model distribution, conversion, device performance, memory, and licensing. Apple documents that Core ML uses CPU, GPU, and Neural Engine and that on-device execution improves privacy and responsiveness; those are capabilities, not evidence that a particular dialogue model will meet Empires' latency or quality bar ([Core ML](https://developer.apple.com/documentation/coreml/)).

Apple's built-in model guardrails are not sufficient on their own. Apple's safety guidance explicitly calls for application-specific safeguards based on audience and cultural context ([Apple generative-output safety](https://developer.apple.com/documentation/FoundationModels/improving-the-safety-of-generative-model-output)).

### Hosted-model operational facts

A hosted API introduces a backend or another secure credential-minting boundary because a durable provider key must not ship inside the iOS binary. Costs are usage-based and model-specific, so estimates need the actual prompt/output token distribution and current official pricing rather than a remembered price ([OpenAI API pricing](https://developers.openai.com/api/docs/pricing)).

Privacy is configurable but not equivalent to local inference. OpenAI states that API data is not used for model training by default, while default abuse-monitoring logs may retain customer content for up to 30 days and some endpoints retain application state; eligible customers can request modified monitoring or zero-data-retention controls ([OpenAI API data controls](https://developers.openai.com/api/docs/guides/your-data)). For Empires, the smallest defensible text-only request would contain the public character identity and an already-final semantic dialogue frame—not full hands, the state vector, player email/name, or unrelated chat history.

Hosted output must also be treated as variable. OpenAI's API documentation says model behavior may change between snapshots and recommends pinned versions plus evals; its seed option is best-effort rather than a guarantee. Exact game replay therefore still requires saving the selected output ([OpenAI API compatibility](https://developers.openai.com/api/reference/overview), [seed behavior](https://platform.openai.com/docs/api-reference/chat/create)). A free-form chat surface also needs input/output safeguards; a moderation endpoint can classify categories such as harassment, hate, and threats, but product-specific policy and fallback behavior remain the app's responsibility ([OpenAI moderation](https://developers.openai.com/api/docs/guides/moderation)).

## 5. The non-negotiable separation invariant

No language approach should accidentally change a legal or strategic decision. The invariant can be stated without choosing how either side is implemented:

```text
GameObservation + exact legal mask
                |
                v
       Negotiation policy
                |
                v
  Typed semantic decision ----------------------+
  (accept/reject/counteroffer, offer, reasons,   |
   scores, policy version)                      |
                |                               |
                v                               v
      RulesEngine validates/commits      Read-only language frame
                                                |
                                                v
                                       Language realizer
                                                |
                                                v
                                         Displayed text only
```

Required properties:

1. The policy selects a typed action from the exact legal mask before wording begins.
2. The engine remains the final authority for affordability, phase, actor, and legality.
3. The language realizer receives immutable semantic facts, not mutation access to `GameState`, policies, tools, or the action executor.
4. A timeout, refusal, unavailable model, unsafe output, or malformed output falls back to wording; it does not re-run or alter the decision.
5. Displayed prose is never parsed back into a move in a text-only design.
6. A semantic decision and its policy/version metadata are recorded before realization.
7. The realized text or stable authored-line ID is persisted if exact resume/replay is required.
8. Tests assert that swapping, failing, or delaying realizers leaves the move fingerprint byte-identical.

If future human chat is allowed to affect policy, it adds a separate inbound path:

```text
Human text -> safety/length handling -> typed DialogueAct or NegotiationIntent
           -> confidence and, where needed, explicit player confirmation
           -> versioned opponent/commitment model -> policy -> legal mask -> engine
```

An LLM-produced sentence is not itself a `GameMove`. A parsed claim such as “I need ore” is evidence with provenance and uncertainty, not a fact. A promise requires a defined commitment lifecycle before policy can rely on it. That design is qualitatively different from adding better flavor text.

## 6. Instrumentation required for rejected-trade diagnosis

Raw accept/reject counts cannot answer why a player experiences universal rejection. A versioned trade-decision trace needs enough detail to reconstruct the score without reconstructing it from future code.

### 6.1 Per-decision trace

| Field group | Minimum content | Diagnostic purpose |
| --- | --- | --- |
| Provenance | trace schema, app build, engine build, policy ID/version, weights hash or snapshot, state/action layout versions | Prevents mixing behavior from incompatible binaries or tuning sets |
| Match position | match/seed ID, turn, decision index, proposer and receiver seats/profile IDs, table size, VP target, board mode | Enables exact reproduction and stratification |
| Offer | stable offer ID, sorted give/want quantities, proposer source (human/bot), retry number, targeted/broadcast status | Defines what was evaluated |
| Eligibility | proposer can honor, receiver can honor, response action legal, exact failure code | Separates “cannot trade” from “will not trade” |
| Receiver valuation | per-resource and per-build-target contributions, gain value, cost value, net gain | Shows whether the resource model explains the rejection |
| Threshold | willingness, unclamped base, floor-bound flag, proposer threat and shift, own standing and shift, prior trades and shift, unlock predicate and shift, final threshold | Makes every additive influence visible |
| Decision | margin (`netGain - threshold`), accept/reject/counteroffer act, all active reason codes, deterministic primary-reason rule | Supports truthful explanation and boundary analysis |
| Alternatives | bank/port rate, nearest blocked target, affordable legal builds, candidate counteroffers, optionally best-policy alternative score | Identifies rejections that look unreasonable because a better deal was close |
| Presentation | voice/profile, realizer kind/version, template or phrase ID, exact persisted text, generation latency/fallback/safety result | Separates policy quality from dialogue quality |
| Outcome | human confirms/withdraws/times out, trade executes/fails and why, subsequent build, match outcome | Connects a decision to actual experience and downstream value |

The trace should retain **all** active threshold contributors. Selecting only one reason can lie when threat, standing, suspicion, and unlock penalties all apply. A user-facing “primary reason” can be derived by a versioned deterministic precedence or largest-contribution rule, while the audit record keeps the full vector.

### 6.2 Initial reason taxonomy

This is an observability taxonomy, not a commitment to display every reason:

- proposer cannot honor;
- receiver cannot honor;
- response action not legal;
- non-positive receiver value;
- positive value below base bar;
- base bar constrained by floor;
- threatening proposer penalty;
- receiver-ahead penalty;
- repeat-proposer suspicion;
- proposer immediate settlement/city affordability;
- accepted above threshold;
- candidate counteroffer exists;
- no acceptable bounded counteroffer;
- evaluation or persistence failure.

### 6.3 Privacy boundary for traces

Full holdings are useful for local replay but are hidden game information and should not automatically become cloud analytics. A defensible split is:

- exact private trace in a local, user-exported diagnostic bundle;
- redacted or bucketed telemetry only with explicit analytics policy and consent; and
- no player names, emails, free-form chat, or complete hands in hosted language prompts unless a later reviewed feature truly requires them.

## 7. Evaluation plan by layer

This is a menu of decision gates, not a sequence selecting an architecture.

### 7.1 Trade-policy diagnosis

1. Capture a corpus of actual human offers from local play, including rejected, accepted, unaffordable, abandoned, and timed-out offers.
2. Replay those offers through the current policy with complete traces.
3. Plot acceptance probability/rate against policy margin, ratio, game phase, receiver/proposer standing, affordability, profile, and whether the floor bound.
4. Build boundary scenarios just below, equal to, and just above every threshold contribution.
5. Have skilled human raters label accept/reject/counteroffer and confidence **without** seeing the bot answer; measure inter-rater agreement rather than assuming one designer's intuition is ground truth.
6. Compare the heuristic with counterfactual candidates offline before altering live behavior.
7. Evaluate win impact and trade behavior on paired held-out seeds, every chair, three- and four-player tables, against frozen anchors.
8. Report unfinished/invalid games separately and retain legality and cross-process fingerprint gates.

The target is not “accept more.” A bot that accepts every trade may feel generous briefly while becoming strategically absurd or feeding the leader. Calibration should ask whether decisions are understandable, appropriately challenging, and near expert/human labels conditional on the same state.

### 7.2 Strategic-style evaluation

Each claimed style needs a predeclared, opportunity-normalized behavior metric and a strength guardrail. Candidate dimensions include trade initiation, demanded margin, counteroffer frequency, concession slope, city conversion, road expansion/blocking, dev-card appetite, leader pressure, and variance/risk tolerance. They should not all be driven by one adjective.

The existing paired seed/chair bootstrap protocol remains appropriate. Product exposure additionally needs blind recognition: after a game or controlled replay set, can players identify the intended style above chance, and do their descriptions match the intended traits without seeing the label?

### 7.3 Language and character evaluation

A controlled bake-off can render the **same semantic decisions** through each language candidate, preventing strategy quality from contaminating voice ratings. Measure:

- factual consistency with offer and reason;
- perceived voice distinctiveness and blind character identification;
- naturalness, clarity, humor, warmth/hostility, and appropriateness;
- repetition within a game and across several games;
- whether explanations make rejection feel fair without leaking hidden information;
- line fit, Dynamic Type, VoiceOver order, localization expansion, and reading time;
- harmful, demeaning, culturally reductive, or age-inappropriate outputs;
- generation failure/refusal/fallback rate; and
- desire to play again.

For authored systems, exhaustively enumerate output combinations. For generated systems, maintain fixed golden scenarios plus adversarial prompts and sample enough outputs per scenario to estimate failure rates rather than showcasing a few good lines.

### 7.4 Human-fun study

Game telemetry and surveys answer different questions. A small structured playtest should combine:

- completed-game rate, abandonment point, match length, trade response time, offer retries, counteroffers, completion rate, and settings changes;
- one-tap event feedback after notable trades (“fair,” “confusing,” “smart,” “annoying”) with optional notes;
- post-game scales for challenge, perceived competence, fairness, personality distinctiveness, dialogue variety, and desire to replay;
- player Catan experience and self-rated skill, because a novice and expert may judge the same refusal differently;
- randomized/counterbalanced variants to limit order and learning effects; and
- interviews or screen recordings for the small number of moments where a quantitative score cannot explain frustration.

The 2017 Catan human study used a training game and a between-subject design because a full five-condition within-subject comparison would take hours. Empires can reduce that burden by evaluating isolated trade vignettes first and reserving full games for candidates that pass them ([Keizer et al., 2017](https://aclanthology.org/E17-2077/)).

## 8. Latency, cost, privacy, and safety acceptance questions

### Latency

- Does wording appear before the player notices an empty or frozen trade card?
- What are warm and cold p50/p95 times on the oldest supported device, a current midrange device, and the simulator?
- Does generation consume the player's response countdown?
- Is cancellation reliable when the offer disappears, the app backgrounds, or a match ends?
- Is there an immediate deterministic fallback for offline, timeout, refusal, memory pressure, or server failure?

### Cost

- What are input/output tokens per utterance and utterances per completed game?
- What is cost per game and per monthly active player at p50 and heavy-use p95?
- Does caching identical semantic frames reduce cost without making dialogue repetitive?
- What backend, monitoring, abuse, and incident-response work accompanies the nominal token cost?
- For local models, what app-download, storage, memory, battery, and engineering costs replace per-token billing?

### Privacy

- Can the realizer operate on a minimal public semantic frame instead of full state?
- Are human chat and identifiers collected at all, and can play work without collection?
- Where are prompts, outputs, traces, and feedback retained, for how long, and how are they deleted/exported?
- Does a hosted path meet the provider's actual endpoint retention settings rather than relying on a general marketing statement?
- Are hidden hands excluded from cloud prompts and redacted analytics by construction?

### Safety and product integrity

- Are every authored line and every generated-output policy reviewed for the intended age rating and markets?
- Can a line make a false factual claim about the deal, a player's holdings, or why the bot decided?
- Can chat provoke harassment, hate, sexual content, self-harm content, real-person impersonation, or attempts to escape the game persona?
- Are historical/cultural voices playful without reducing a people to violence, religion, or stereotypes?
- Does the system disclose generated dialogue if required by platform or policy at ship time?
- Can a malicious chat message affect only the bounded dialogue model and never bypass `RulesEngine` or read secrets?

## 9. Research questions that remain open

1. What distribution of human-created offers produces the “everything is rejected” experience?
2. What trade objective should be optimized: immediate build utility, estimated win-probability delta, human-labeled reasonableness, fun, or a declared combination?
3. Should bots reason from full state or an observation/belief state for trading? This audit does not resolve the previously deferred hidden-information choice.
4. What typed counteroffer action space is expressive enough without exploding the global action space?
5. Which strategic traits are independently perceptible while preserving comparable strength?
6. Should a civilization imply one fixed strategy, or should identity, style, voice, and eventual difficulty be independently configurable?
7. What reasons may a bot reveal without leaking private information or making the policy easier to exploit?
8. How much authored dialogue is needed before repetition is no longer a problem in realistic matches?
9. Can a parameterized or retrieval-based authored system match generated-language quality on the game's very short utterances?
10. Which supported devices can meet an acceptable local-model latency and memory envelope?
11. Does hosted generation add enough player value to justify a backend, ongoing cost, network dependency, and external data processing?
12. Is chat intended to be flavor, structured bargaining, or genuinely policy-relevant strategic conversation? Those are three different products.
13. If chat becomes policy-relevant, what are the commitment, truthfulness, deception, abuse, and player-control rules?
14. What exact save/replay promise applies to dialogue: same semantic act, same authored line ID, or byte-identical generated text?

## 10. Decision gates, not decisions

Before any architecture choice, a candidate should be evaluated against the same gates:

1. **Observability gate:** the current policy emits a complete, reproducible trace for every human-offer response.
2. **Baseline gate:** a real human-offer corpus and expert/rater labels establish where the present heuristic fails.
3. **Policy gate:** candidate acceptance/counteroffer behavior improves predeclared calibration or utility metrics without legality, determinism, completion, or strength regressions.
4. **Style gate:** claimed strategic styles are opportunity-normalized, repeat on held-out seeds/chairs/table sizes, and are recognized blind.
5. **Language-faithfulness gate:** wording never contradicts the semantic decision or leaks hidden state.
6. **Voice gate:** players distinguish and prefer the voices in blinded comparison; repetition and cultural-safety review pass.
7. **Operational gate:** measured p95 latency, failure rate, offline behavior, device coverage, cost, privacy, and moderation satisfy declared budgets.
8. **Replay gate:** policy version, semantic act, and exact wording can be reconstructed to the chosen replay contract across relaunch and app update.
9. **Chat gate, if pursued:** typed dialogue acts, confidence handling, commitments, prompt-injection tests, and engine legal masks pass before text can influence policy.
10. **Difficulty gate, separately:** strength tiers are calibrated against frozen anchors and human skill bands rather than inferred from personality labels.

No option in section 4 has passed all of these gates yet. The immediate research deficit is not a missing model; it is a missing decision trace and human-offer evaluation corpus.

## Primary and official sources

### Empires source and project evidence

- [`BotPersonality.swift`](../../Packages/CatanAI/Sources/CatanAI/BotPersonality.swift)
- [`BotWeights.swift`](../../Packages/CatanAI/Sources/CatanAI/BotWeights.swift)
- [`TradeHeuristics.swift`](../../Packages/CatanAI/Sources/CatanAI/TradeHeuristics.swift)
- [`TradeMessages.swift`](../../Packages/CatanAI/Sources/CatanAI/TradeMessages.swift)
- [`PolicyBehaviorMetrics.swift`](../../Packages/CatanAI/Sources/CatanAI/PolicyBehaviorMetrics.swift)
- [`TrainingExample.swift`](../../Packages/CatanAI/Sources/CatanAI/TrainingExample.swift)
- [`OpponentProfile.swift`](../../Settlers/Models/OpponentProfile.swift)
- [`GameViewModel+OpponentProfiles.swift`](../../Settlers/ViewModels/GameViewModel+OpponentProfiles.swift)
- [`GameViewModel.swift`](../../Settlers/ViewModels/GameViewModel.swift)
- [`TradePresentationState.swift`](../../Settlers/ViewModels/TradePresentationState.swift)
- [`TradeHeuristicsTests.swift`](../../Packages/CatanAI/Tests/CatanAITests/TradeHeuristicsTests.swift)
- [`TradeMessagesTests.swift`](../../Packages/CatanAI/Tests/CatanAITests/TradeMessagesTests.swift)
- [`OpponentProfileTests.swift`](../../SettlersTests/OpponentProfileTests.swift)
- [`OpponentProfileIntegrationTests.swift`](../../SettlersTests/OpponentProfileIntegrationTests.swift)
- [`2026-09-02-ai-baseline-and-personality-audit.md`](./2026-09-02-ai-baseline-and-personality-audit.md)
- [`2026-09-02-personality-separation-requirements.md`](./2026-09-02-personality-separation-requirements.md)
- [`2026-09-02-personality-separation-results.md`](./2026-09-02-personality-separation-results.md)
- [`2026-09-02-consolidation-metric-results.md`](./2026-09-02-consolidation-metric-results.md)
- [`2026-09-02-opponent-profile-decision-log.md`](./2026-09-02-opponent-profile-decision-log.md)
- [`2026-09-03-ai-approach-evaluation.md`](./2026-09-03-ai-approach-evaluation.md)
- [`2026-09-03-creative-bot-trade-offers.md`](./2026-09-03-creative-bot-trade-offers.md)

### External primary research and official documentation

- Cuayáhuitl, Keizer, and Lemon, [“Strategic Dialogue Management via Deep Reinforcement Learning”](https://arxiv.org/html/1511.08099v1), 2015.
- Afantenos et al., [“Developing a corpus of strategic conversation in The Settlers of Catan”](https://www.research.ed.ac.uk/en/publications/developing-a-corpus-of-strategic-conversation-in-the-settlers-of-), 2012.
- Cadilhac et al., [“Grounding Strategic Conversation: Using Negotiation Dialogues to Predict Trades in a Win-Lose Game”](https://aclanthology.org/D13-1035/), 2013.
- Guhe and Lascarides, [“Game strategies for The Settlers of Catan”](https://www.research.ed.ac.uk/en/publications/game-strategies-for-the-settlers-of-catan/), 2014.
- Keizer et al., [“Evaluating Persuasion Strategies and Deep Reinforcement Learning methods for Negotiation Dialogue agents”](https://aclanthology.org/E17-2077/), 2017.
- Mairesse and Walker, [“PERSONAGE: Personality Generation for Dialogue”](https://aclanthology.org/P07-1063/), 2007.
- Mairesse and Walker, [“Controlling User Perceptions of Linguistic Style”](https://aclanthology.org/J11-3002/), 2011.
- Lewis et al., [“Deal or No Deal? End-to-End Learning of Negotiation Dialogues”](https://aclanthology.org/D17-1259/), 2017.
- Gendre and Kaneko, [“Playing Catan with Cross-dimensional Neural Network”](https://arxiv.org/abs/2008.07079), 2020.
- Meta AI, [CICERO research overview](https://ai.meta.com/research/cicero/) and [released repository](https://github.com/facebookresearch/diplomacy_cicero).
- [JSettlers developer documentation](https://github.com/jdmonin/JSettlers2/blob/main/doc/Readme.developer.md).
- [Catanatron repository and documentation](https://github.com/bcollazo/catanatron).
- Apple, [Foundation Models framework](https://developer.apple.com/documentation/FoundationModels/), [framework overview](https://developer.apple.com/videos/play/wwdc2025/286/), [model updates](https://developer.apple.com/documentation/Updates/FoundationModels), [generative-output safety](https://developer.apple.com/documentation/FoundationModels/improving-the-safety-of-generative-model-output), and [Core ML](https://developer.apple.com/documentation/coreml/).
- OpenAI, [API pricing](https://developers.openai.com/api/docs/pricing), [data controls](https://developers.openai.com/api/docs/guides/your-data), [API compatibility](https://developers.openai.com/api/reference/overview), and [moderation](https://developers.openai.com/api/docs/guides/moderation).
