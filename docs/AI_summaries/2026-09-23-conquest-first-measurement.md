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
