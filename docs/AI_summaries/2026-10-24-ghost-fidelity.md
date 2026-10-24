# Ghost fidelity: does a ghost play like its person? (2026-10-24)

Jake asked for ghosts judged by **how closely they play like their person**,
not by wins and losses. The method: pause at each pivotal moment (buying, knight
timing, what to do with a hand) and check the ghost makes the person's decision.

## The test: `ghost fidelity`

```bash
swift build -c release --package-path Packages/CatanAI --product ghost
ghost fidelity --cv 4 --detail LOGS...        # the shipping ghost, judged on games it never saw
ghost fidelity --profile GHOST.json LOGS...   # a stored ghost (in-sample if it trained on LOGS)
ghost fidelity LOGS...                        # plain Expert, for reference
```

`GhostFidelity.forEachDecision` replays each recorded game. At every choice the
person made, it hands the exact position to the ghost seat the app would seat,
with the same options a bot seat sees, and compares the two answers. A ghost is
deterministic at a given position, so agreeing there means agreeing every time.

Each moment is tagged by what the person **faced**, never by what they did, so
easy cases cannot flatter a ghost:

| situation | the moment |
|---|---|
| openingSettlement / openingRoad | setup placements |
| knightBeforeRoll | a knight is playable before the dice |
| canBuy | main turn, a settlement, city or dev card is affordable |
| knightInHand | main turn, a knight is playable |
| turnOther | main turn, nothing but roads, trades or ending |
| robber, discard, tradeResponse | as named |

Scoring:
- **exact:** the same move.
- **kind:** the same sort of move (end turn vs. bank trade vs. city...). For a robber move, the same hex.

One rule is relaxed on purpose: the app takes "six wool for a grain and two ore"
as **one** bank trade, while a bot seat makes it one swap at a time. The ghost's
first swap of such a trade counts as the same decision (`GhostFidelity.matches`).

`--cv 4` deals the person's games into four folds by id. Each fold is played by
a model fitted on the other three. **Every number below except the "in-sample"
row comes from games the model never trained on.**

## Data

- **Games:** Jake's 25 Classic games, pulled off his iPhone on 2026-10-24.
- **Decisions:** 826, from 21 games with at least one decision.
- **Other players:** Kbeast, Chandy, Noah and Kylesito could not be judged. Only their synced ghosts and seat stats reach Jake's phone, not their moves (`LiveSync` keeps no moves). Their ghosts retrain on their own phones (below).

## Results (4-fold, all 826 decisions)

| ghost | exact | kind | robber | openings | turn, nothing affordable |
|---|---:|---:|---:|---:|---:|
| plain Expert | 29% | 44% | 11% | 26% | 7% |
| **shipped ghost, lambda 0.01** | **39.1%** | **55.2%** | 11% | 29% | 29% |
| person model alone, lambda 1 | 61.9% | 76.9% | 13% | 24% | **70%** |
| person model alone, lambda 10 | 61.5% | 76.6% | 9% | 24% | 70% |
| choice model + person model as a feature | 62.2% | 78.1% | 24% | 38% | 65% |
| **choice model (shipped now)** | **63.1%** | **78.9%** | **33%** | **36%** | 65% |

Paired 90% intervals come from resampling whole games, 4,000 draws:

| comparison | exact | kind |
|---|---|---|
| choice model − shipped ghost | **+24.0 [+21.7, +26.3]** | +23.7 [+20.6, +27.2] |
| choice model − person model at lambda 1 | +1.2 [−1.1, +3.3], inconclusive | **+2.1 [+0.4, +3.7]** |

Choice model − person model at lambda 1, by situation:
- **robber:** +20.0 [+5.1, +35.5]
- **opening settlement:** +11.9 [0, +23.8]
- **turnOther:** −5.0 [−8.7, −1.4]. The person model is better at *which* bank trade or road; the kind of move is level (79.8% vs 78.5%).

**The shipped ghost was mostly Expert.** Lambda 0.01 was set to match Jake's win
rate against Classic bots (2026-09-25), and at that weight his habits barely
move a decision. It proposed trades where Jake ended his turn (153 times in
these games), played knights he held, and robbed a hex he would not have 89% of
the time.

## What changed: the choice model

`ChoiceModel` (`Packages/CatanAI/Sources/CatanAI/Ghost/`) decides in two steps,
both conditional logits fitted on the person's choices:
1. **What sort of move:** roll, end, bank trade, propose, build city... It is read against the seat's situation: hand size, over 7, points and lead, knight lead, robber on me, early game, biggest pile, whether a knight takes Largest Army.
2. **Which one,** within the kind's family:
   - **robber/knight:** pips, 6 or 8, rival buildings, the leader's, own, victim's hand.
   - **settlement:** pips, resources, port.
   - **road:** the far end's pips and whether it is open.
   - **bank trade:** from the biggest pile, for a missing card, opens a city, settlement, dev card or road.
   - **discard:** from the biggest pile, how many kinds.
   - **proposal:** cards given and asked.

Why two steps: a single flat choice let ten knight placements outvote one roll.
Before the dice, it played knights Jake would not have, and pre-roll agreement
fell from 94% to 54%.

Why not just raise lambda: the person model reweights Expert's position score,
and Expert's score has no term for "robs a 6 or 8" or "trades from the biggest
pile", so no reweighting reaches them (robber 9–13% at any lambda). It also
needs a slow extraction on the phone (about a minute per game on a Mac); the
choice model needs about half a second per game.

Features that did not improve held-out agreement were cut:
- what the person did earlier in the turn;
- what the hand can afford;
- the family's inclusive value at the kind step;
- the person model as a feature.

Penalty strength was chosen on the same folds and was flat over a wide range:
10–100 for kinds, 1–3 for families.

### Jake's habits, as fitted on all 25 games

- **Robber:** never his own hex (−1.9). Higher pips (+0.85) and a 6 or 8 (+0.77). Robs the points leader (+0.71). Prefers hexes with more rival buildings.
- **Openings:** pips (+0.73), ore (+0.34) and grain.
- **Bank trades:**
  - from his biggest pile (+0.92), for a card he has none of (+0.88);
  - when it completes a city (+0.95), dev card (+0.82) or road (+0.78).
- **Discards:** from the biggest pile, in as few kinds as possible.
- **Turn:**
  - proposes trades less as his points rise (−0.70 per point);
  - buys dev cards more as his points rise;
  - over 7 cards he trades or proposes rather than ends;
  - trades with the bank less early in the game.

## Where 100% is not reachable

A person is not deterministic, and some choices left no trace a fit could find:

- **Knights before the roll:** 8 in 136 chances. The robber on his own hex did not predict them, and no fitted rule beat "always roll" on held-out games. The ghost rolls (94% agreement), unless a knight wins the game outright.
- **Free-form trade offers:** 13 of Jake's 25 offers were ones a bot seat cannot make, either past the three-refusal cap or of a shape the cascade never lists.
- **Ties:** two hexes alike in pips, buildings and victim are the same decision to a rule, and only chance separates them.

## How a ghost learns now (app)

`GhostTrainer.learn` runs after every rated game, and the old person-model fit still runs. On top of that:
1. It writes the game's `ChoiceRecord`s to `<ghost>/choices/<match>.jsonl`.
2. It refits the choice model from every record on the phone. That takes seconds, so there is no incremental prior.
3. From 100 decisions (about 3 of Jake's games) the ghost plays by the choice model. Below that it keeps the old person-model ghost.

At launch, catch-up backfills each ghost once from the game logs still on the phone. This covers games learned before choice models existed, so Jake's and Kbeast's ghosts play like them after one app launch, not after many new games. The backfill:
- bumps the revision so the ghost syncs;
- leaves `gamesLearned` alone;
- is skipped for paused ghosts.

A reset archives the choice records and marks the backfill done, so old games
never return to a fresh ghost.

## Tests

- `GhostChoiceModelTests` (CatanAI):
  - **Situational recovery:** a person with a fixed robber rule. The ghost reproduces it on 35 of 40 robber placements on boards it never trained on; the bar is 80%, and Expert is far below.
  - The kind step comes first, the fit is deterministic, a choice ghost rolls first, combined bank trades match their first swap, and old ghost files decode.
- `GhostTrainerTests` (app):
  - records are written and fitted;
  - too few records keep the person model;
  - the one-time backfill;
  - no backfill after a reset.

## Strength

Jake's choice-model ghost was fitted on all 25 games and played every chair
against three Experts: 800 games on held-out seeds 900000–900199.

**It won 43 of 800 = 5.4% (95% CI 4.0–7.2%)** against a 25% null. Jake himself
won 11 of 20 against Experts.

The ghost makes Jake's move 63% of the time. The other 37% put it in positions
Jake would not have reached, and it plays those worse than Expert. This is the
compounding error of behaviour cloning.

By the north star (CLAUDE.md, "North star for ghosts") the ghost is closer to
Jake's decisions, but not yet to his results. Jake chose to ship it anyway
(2026-10-24). The next step is blending in Expert's judgement and scoring each
blend on both axes: agreement (`ghost fidelity --cv 4`) and win rate (`ghost
strength --choices`).
