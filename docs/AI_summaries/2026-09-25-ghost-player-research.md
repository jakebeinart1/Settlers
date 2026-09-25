# Ghost players: a bot that plays like one specific person

**Date:** 2026-09-25
**For:** Jake. His requirement: the ghost must play like him **in every facet**
(openings, builds, robber, dev cards, discards, and above all trading: what he
offers, how often, to whom, what he accepts) **and** be about as strong as he
is. Both, not one or the other.

**Status:** research and plan only. Nothing is built. Every claim about this
repository below was checked against the source on 2026-09-25; claims about
outside work cite the paper.

---

## 1. The answer in one paragraph

Wanting both style and strength is a problem people have already solved, and
the solution has a name: **human-regularized search** (piKL, from Meta's
Diplomacy work). You build two things: a **model of the person** ("how likely
is Jake to make this move here?") and a **strong engine** ("how good is this
move?"). Then the ghost picks the move that maximises
`engine score + λ × log P(Jake plays it)`. The single dial λ slides the ghost
between "exactly Jake, mistakes included" and "the engine wearing Jake's name".
**We set λ so the ghost wins exactly as often as Jake does.** At that λ it makes
Jake's kinds of mistakes rather than random ones, so it matches him on style and
on strength at the same time. We already have the strong engine: Expert's
`EvaluationPolicy.score(_:)` scores every candidate move. What is missing is the
model of Jake, and the research below says how to build one from dozens of
games, not thousands.

---

## 2. What the outside research says

### 2.1 Imitating one person needs a shared base plus a few personal numbers

The Maia chess project is the most direct precedent: its models predict what a
*specific* human will play.

- Fine-tuning a whole network on one person needs **~5,000 games** before it
  beats the population model
  ([McIlroy-Young et al., KDD 2022](https://www.cs.toronto.edu/~ashton/pubs/maia-individual-kdd2022.pdf)).
  Later work puts the threshold at 10,000
  ([Generative Modeling of Individual Behavior at Scale](https://arxiv.org/pdf/2502.14998)).
- **Maia4All gets the same gain from 20 games (~800 positions).** It freezes
  the shared model and fits only a small per-player embedding, starting from a
  blend of the "prototype" players the new player most resembles. Accuracy
  goes from 51.4% to 53.2% at 20 games, and only to 53.5% at 200
  ([Learning to Imitate with Less, 2025](https://arxiv.org/html/2507.21488)).
- Style is real and identifiable: given 100 games, a model picks the right
  player out of 400 **98%** of the time
  ([Behavioral Stylometry in Chess, NeurIPS 2021](https://www.cs.toronto.edu/~ashton/pubs/chessembed-neurips2021.pdf)).

**Lesson for us:** do not train anything big per person. Keep a strong shared
base and fit a **small number of personal parameters**, pulled toward the base
when data is thin. Our base is Expert, which has 19 weights.

### 2.2 Style and strength together: KL-regularized search

[Jacob et al., ICML 2022, "Modeling Strong and Human-Like Gameplay with
KL-Regularized Search"](https://arxiv.org/pdf/2112.07544) showed, in chess, Go
and Diplomacy, that searching for strong moves while penalising distance from a
human-imitation policy gives a policy that **predicts human moves as well as the
imitation policy while scoring far higher**. The dial λ traces a smooth frontier
between the two. The same approach produced Diplodocus, which beat 62 humans at
no-press Diplomacy ([Bakhtin et al., ICLR 2023](https://arxiv.org/abs/2210.05492)).

**Lesson for us:** "both" is not a compromise we invent. It is a known
frontier, and we choose where on it the ghost sits.

### 2.3 Catan trading from human data

The Edinburgh STAC corpus of human Catan negotiations is the only large human
trading dataset I found. A trading agent trained only to copy it won **27%**
against three bots, versus 53% for one trained with reinforcement learning
([Evaluating Persuasion Strategies and Deep RL, EACL 2017](https://homepages.inf.ed.ac.uk/alex/papers/eacl_2017.pdf);
[Learning to Trade in Strategic Board Games](https://link.springer.com/chapter/10.1007/978-3-319-39402-2_7)).

**Lesson for us:** copying trades alone gives a weak trader. Trades also need
the regularized-search treatment: offer what Jake would offer, filtered by
what actually helps.

### 2.4 This repository's own evidence

- Two learned policies have failed here. The one that matters is imitation:
  42.4% top-1 accuracy, yet **0/40** against Greedy, because it stopped building
  permanent pieces (`docs/AI_summaries/2026-09-05-current-ai-baseline.md:278`).
  **Accuracy is not strength.** A copy that matches 42% of moves can still get
  the other 58% catastrophically wrong.
- The piKL shape fixes exactly that failure. The engine term still scores
  "never build a city" as terrible, so the ghost cannot drift there, whatever
  the imitation model says.

---

## 3. What we already have

| Need | Exists? | Where |
|---|---|---|
| Every human move recorded, with timestamp | **Yes** | `GameLogStore` JSONL (`Settlers/Persistence/GameLogStore.swift`), one line per move with `player`, `move`, `timestamp`; `SeatRoster.humanSeats` says which seats were human |
| Exact board state at every decision | **Yes** | deterministic engine; replay the log from `initialState` |
| Trade proposals with exact give/want | **Yes** | `GameMove.proposeTrade(TradeOffer)` |
| Accept/decline of incoming offers | **Yes** | `GameMove.respondToTrade(offerID:accept:)` |
| Bank/port trades, robber, knights, dev cards, discards, openings | **Yes** | all `GameMove` cases |
| A strong scorer for any candidate move | **Yes** | `EvaluationPolicy.score(_:state:ledger:evaluator:purchases:)` |
| A generator of composed/bundle offers | **Yes** | `TradeCascade.offers(from:)`, which already produces the multi-resource offers `legalMoves` cannot |
| Weight vector swappable from the CLI | **Yes** | `sim --weights` |
| Honest strength measurement | **Yes** | the `bot-strength` skill: rotated chairs, paired held-out seeds, CIs |
| **Jake's actual games** | **No** | only 2 logs on this Mac's simulators (5 and 20 lines). His real games are on his phone |
| Offers drafted then cancelled | **No** | not a `GameMove`; never logged |
| Which partner he picked when several bots accepted | **Yes** | `confirmPendingTrade` logs `respondToTrade(accept: true)` by `pending.selectedBot` (`GameViewModel.swift:958`) |
| Jake backing out after bots accepted | **Ambiguous** | `declinePendingTrade` logs `respondToTrade(accept: false)` **attributed to the bot** (`GameViewModel.swift:993`), so in the log "Jake changed his mind" looks like "the bot refused". The extractor must tell these apart (the bot's accept decision is recomputable by replay), or the log needs a marker |

---

## 4. The design

### 4.1 The model of Jake: a conditional logit over candidate moves

At each of Jake's decisions, list the candidates: legal moves, plus
`TradeCascade` offers, plus his actual move if it is a composed offer nothing
else generates. The model is

```
P(Jake picks m) ∝ exp( β · S_w(m)  +  θ · style(m) )
```

- `S_w(m)` is Expert's own position score with **Jake's** weights `w` instead
  of Expert's. `PositionEvaluator.evaluate` is `mine − rival × strongest`, and
  each standing is a weighted sum of features. So once the features are
  extracted per candidate, fitting `w` is ordinary logistic regression. **No
  SPSA and no games to play**: it fits in seconds from the log. This captures
  *what Jake values*: roads versus cities, ports, hand size, how much he fears
  the leader (his own `rival`).
- `style(m)` is a short list of **behaviour features** the evaluator cannot
  express, each a facet Jake named:
  - trade shape: 1:1, 2:1, 3:1, bundle; number of cards given
  - trade tempo: offers already made this turn; offering again after a refusal
  - trade target: offering to the leader or to the last-place player
  - response: accepting a trade that helps the offerer more than him
  - robber: targeting the leader, the player who robbed him last, or the biggest hand
  - dev cards: buying early or late; holding a knight versus playing it at once
  - opening: numbers versus resource variety versus port
  - bank versus player trade when both are open
- `β` measures how "sharp" Jake is: large means he nearly always plays his own
  best move, small means he is noisier. Together with `w` it carries his skill
  level.
- **Regularisation toward Expert.** `w` is pulled toward Expert's weights and
  `θ` toward zero, so a facet with little data falls back to sensible play
  rather than noise. This is Maia4All's lesson in 19 numbers rather than a
  network.

### 4.2 The ghost: human-regularized choice

```
ghost picks argmax_m [ S_Expert(m)  +  λ · log P(Jake picks m) ]
```

A deterministic tie-break keeps seeded replay intact. **λ is fitted, not
guessed:** run the ghost against the shipping bots at several λ and pick the
one where its win rate matches Jake's own win rate against the same table. If
Jake beats the bots more than Expert does, the ghost can exceed Expert, because
Jake's weights also enter through `P`.

### 4.3 Trading, specifically

Trading is where "like me" is most visible, so it gets three measured targets:

1. **Volume:** offers per turn and per game, and how far he escalates after a
   refusal (his own version of the cascade).
2. **Shape:** a histogram of give/want sizes and resource types.
3. **Responses:** his accept rate, split by whether the offer helps him, helps
   the offerer, or helps the leader.

Offers come from `TradeCascade`'s generator (bundles included) and are chosen
by the same `S + λ log P` rule. The ghost therefore offers the *kinds* of deals
Jake offers, only when they are not self-destructive. This is the lesson from
§2.3: copied trading alone won 27%.

### 4.4 Curated games ("drills") to fill the gaps

Ordinary games rarely produce some situations: a seven with three possible
victims, a 2-for-1 offer while he is one card from a city, a Monopoly with
only 3 turns left. The model is least sure exactly there. The drill loop:

1. Take positions from real and simulated games where the fitted model is
   least sure, or where it disagrees most with Expert. This is active
   learning's "query by uncertainty".
2. Rebuild each position exactly from its seed and move list. The engine is
   deterministic, so this is free.
3. Show it as a single decision: "your turn, what do you do?". Record the
   answer as an ordinary logged move tagged `drill`.
4. Refit. Each drill decision is worth several ordinary-game decisions,
   because it was chosen to be informative.

A fixed **standard drill set** (the same 30 to 50 positions for everyone) also
gives every future ghost a comparable fingerprint. That matters for the ghost
ladder: it lets two people's styles be compared on identical positions.

### 4.5 How we will know it works (all four, per facet)

| Test | Pass means |
|---|---|
| **Move prediction** on held-out Jake games | Jake's model predicts his move better than Expert-softmax does, reported **per facet** (openings, trades, robber, and so on) |
| **Behaviour match** in ghost self-play | Each §4.3 trading statistic, and each style-feature rate, falls inside the confidence interval of Jake's own |
| **Strength match** | Ghost win rate against the shipping bots falls inside Jake's own win-rate CI. Measured with the `bot-strength` skill |
| **Blind test** | Jake plays three-bot games where one seat may be his ghost, and cannot reliably tell which seat it is. Stylometry-style: a classifier trained to separate Jake-games from ghost-games should do no better than chance |

Accuracy alone is not a pass (§2.4).

---

## 5. Risks, stated plainly

- **Data volume.** Maia-style numbers suggest a usable personal model from ~20
  games, and 19 weights plus ~15 style numbers need far less data than a
  network. But **strength calibration is data-hungry**: from 20 games, Jake's
  own win rate is only known to about ±20 points. Style will converge long
  before strength does.
- **Jake is not stationary.** He gets better. Weight recent games more, and
  refit.
- **Bot-only opponents.** Jake's games are against bots, so his trading model
  describes how he trades *with bots*. Against another ghost, behaviour could
  differ. That cannot be fixed until people play people.
- **The evaluator's blind spots.** A habit that depends on something no
  feature sees (say, "always trade with whoever is losing") needs its own
  style feature. The per-facet prediction report shows where these are.
- **Think time** is in the log (timestamps). It is cosmetic, but cheap to copy
  for the ghost's move pacing, and it makes the ghost feel like him.

---

## 6. Proposed build order

Each phase has an exit test, and nothing ships to other players until phase 5
passes.

| # | Phase | Output | Exit test | Rough size |
|---|---|---|---|---|
| 0 | **Collect** | Jake exports his game logs from the phone archive (the export already exists) | ≥ 20 complete games on disk | Jake: 10 min |
| 1 | **Extract** | a `ghost-extract` tool: replays each log and, at every human decision, writes candidates + features + chosen move as JSONL | round-trips every log; replay divergence fails loudly | 1 day |
| 2 | **Profile** | "How Jake plays" report: every facet's statistics, with CIs | Jake reads it and agrees it is him | ½ day |
| 3 | **Fit** | Jake's `w`, `β`, `θ`; held-out per-facet prediction vs Expert | beats Expert-softmax overall and on trading | 1–2 days |
| 4 | **Ghost** | `GhostPolicy` = §4.2 inside `CatanAI`, plus λ calibration | behaviour and strength rows of §4.5 | 2–3 days |
| 5 | **Drills** | in-app drill mode + refit loop | uncertain facets narrow after one drill session | 2–3 days |
| 6 | **Blind test** | Jake plays against his ghost | the §4.5 blind-test row | Jake: a few games |

Deliberately **not** in v1: sending ghosts to other devices, ratings and the
ladder, and logging cancelled drafts. Those come after one ghost (Jake's) is
proven to be him.
