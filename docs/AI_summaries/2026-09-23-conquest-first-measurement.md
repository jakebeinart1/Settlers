# Conquest — first measurement (2026-09-23)

Branch `feat/conquest-mode` at `511fbb7`. Spec: `docs/superpowers/specs/2026-09-23-conquest-mode-design.md`.

```bash
swift build -c release --package-path Packages/CatanAI --product sim
Packages/CatanAI/.build/release/sim --variant conquest --mode classic --seed 1000 --games 200 --jsonl
Packages/CatanAI/.build/release/sim --variant conquest --mode vast    --seed 1000 --games 200 --jsonl
```

Default seats (balanced, aggressive, cautious, balanced), randomized boards, no seat
rotation. **These are heuristic bots, not people** — the numbers describe how *these
bots* play the rules, which is a floor on how the rules play, not the answer.

| | Classic | Vast |
|---|---|---|
| games finished | 200 / 200 | 200 / 200 |
| mean moves per game | 528 | 730 |
| games where someone took a 6 or 8 | 61% | 44% |
| first 6/8 holder's win rate (baseline 25%) | **19.7% ± 7.1%** (n=122) | **28.1% ± 9.3%** (n=89) |
| army cards bought per game | **1.07** | **0.12** |
| games with any army card bought | 32% | 6% |
| player-vs-player captures per game | 0.87 | 0.55 |
| games with any PvP capture | 62% | 51% |

Intervals are 95% normal approximations, `p ± 1.96·√(p(1−p)/n)`.

## Verdicts on the spec's hypotheses

1. **Snowball — not found.** Both intervals contain 25%. Taking a 6 or 8 first does
   not measurably decide the game. Caveat: seats are not rotated and personalities
   differ, so 25% is only an approximate baseline.
2. **Armies are barely bought.** About one purchased card per Classic game and almost
   none on Vast. Most of the fighting happens with the **dealt starting card**: PvP
   captures happen in 62% of Classic games though only 32% of games buy any card.
3. **PvP happens, thinly.** Under one capture per game on either board.

## What this does and does not say

The spec's "armies come late" prediction held, and held too well. The mode as measured
is mostly a turn-one mini-game with the starting card, followed by ordinary Catan —
the passivity the design set out to avoid.

It is **not yet known whether that is the rules or the bots.** The bot considers buying
an army card only when no build is worth making (`Bot.decideMainTurn`, beside the dev-card
fallback), which is exactly the behaviour that would undercount purchases if armies are
in fact worth buying earlier. Two ways to separate them, cheapest first:

- Re-run with a bot that buys whenever it can afford a card and has a target, and see
  whether it beats the current bot. If it does, the rules are fine and the bot is timid.
- Try the spec's knob: the stronger deck (mean ~4.7) or a cheaper card, and re-measure.

Changing the rules is Jake's call; nothing here changes them.

---

# Follow-up: is it the rules or the bot? (same day)

Frozen binaries `bf1512d` (bold, strong deck) and `e959a75` (targeted); both contain the
unchanged idle bot. Held-out seeds 30000-30155 (rotations) / 30000-30199 (tables), never used
before. Four-player only (the only table size New Game offers). Every seat is `balanced`
personality; only the army-buying rule differs:

- **idle** — the shipped bot: buys a card only when no build is worth making.
- **bold** — buys ahead of building whenever affordable and a hex is not yet its own.
- **targeted** — buys ahead of building only when one more card at mean strength would let its
  hand take a 5, 6, 8 or 9 it touches.

Rotations put the candidate in each of the 4 chairs for every seed (624 games, all decisive);
the null is exactly 25% by symmetry. Declared effect size: 5 points.

| Candidate win rate (null 25%) | Classic | Vast |
|---|---|---|
| one **bold** vs three idle | **14.6% ± 2.8%** | **0.5% ± 0.5%** |
| one **idle** vs three bold | **38.0% ± 3.8%** | **77.6% ± 3.3%** |
| one bold vs three idle, **strong deck** (mean 4.7) | 14.9% ± 2.8% | 0.5% ± 0.5% |
| one **targeted** vs three idle | 25.2% ± 3.4% | 22.6% ± 3.3% |

| Whole-table behaviour (200 games) | Classic | Vast |
|---|---|---|
| all idle: army cards / PvP captures per game | 1.3 / 0.98 | 0.1 / 0.54 |
| all targeted | 1.8 / 1.35 | 15.7 / 6.57 |
| all bold | 11.7 / 4.00 | 53.7 / 15.85 |
| all bold, strong deck | 10.0 / 4.05 | 52.9 / 19.12 |
| first 6/8 holder wins (any table) | 21–30% | 17–32% |

Every game in every arm finished. All-bold Vast games are 60% longer (1,085 moves vs 673).

## Verdict

1. **Under the current rules, armies are at best break-even.** Buying for a reason
   (targeted) is statistically indistinguishable from not buying; buying freely (bold) is a
   large, significant loss, and on Vast a near-certain one. A player who ignores the mode's
   central mechanic loses nothing - and beats a table that embraces it.
2. **It is the rules, not only the bot.** The targeted bot fixes the overbuying and still gains
   nothing. Five resources for ~4 strength that pays +1 per roll of one hex does not return its
   cost against a settlement or city.
3. **The deck strength is not the lever.** Mean 4.7 instead of 4.0 moved nothing.
4. **Snowball stays absent.** No arm shows the first 6/8 holder winning out of line with 25%.

The levers left are the **payoff** (e.g. the occupier *captures* what blocked players would
have collected, instead of +1; or points for holding territory) or the **price**. These are
rules changes, for Jake.
