# Every Expert and Classic that ever shipped, at one table (2026-09-29)

## The question

After the hand-size rule (`HandDiscipline`, `a168a4b`) measured as costing Expert
nothing, Jake did not believe it: "I think you'd have to test that further to see
what the expert that holds the cards versus uses the cards." He also asked for every
version of Expert and of Classic that ever lived to play every other, often enough to
trust the answer.

## Answer

**Spending wins, by about 2 points of win rate.** The earlier "no difference" came from
too few games to see an effect this size.

| 12,000 games, seeds 7000000-7001499, 4 seats, full chair rotation | win rate | 95% CI | null |
|---|---|---|---|
| today's Expert (spends) vs 3 holders | 26.3% | 25.2-27.4 | 25% |
| holder vs 3 of today's Expert | 24.2% | 23.1-25.3 | 25% |

The two arms agree in direction; the combined gap is ~2 points (z ≈ 2.6). In the
tournament's rating fit below, today's Expert sits **+27 above the holder (95% bootstrap
interval +5 to +47)**, which is the same finding measured another way.

**Why the gap is small:** the rule only changes a decision when Expert would otherwise
end its turn over 7 cards. The holder does that on 7.1% of its turns; today's Expert on
0.4%. That saves ~2.2 cards a game to the robber (10.6 → 8.4 discarded per game).

**The holder is not a made-up arm.** The probe below found that Expert as shipped from
2026-09-17 until the rule landed (`5c354a8`) plays move-for-move identically to today's
Expert with `handDiscipline: false`.

## The tournament

**Rules for every seat are today's** (`GameSession` + `RulesEngine`, standard 4-seat,
10 VP, randomized board). Each historical commit runs as its own process, built from
that commit (`scripts/tournament/build-version.sh` + `seat-server.swift`), and is asked
for a move over a pipe (`arena`, a new `CatanAI` executable). Moves today's rules
reject are replaced with a neutral move and counted. Today's Expert played through the
pipe produces the same game, move for move, as in-process.

**Distinct versions.** Every main-line commit that touched bot code (63) was built and
probed; commits whose bots play move-for-move identically on six probe seeds collapse
into one variant:

- **Expert: 8 distinct**, from `1f2c8f0` (09-14, the first) to today (`a168a4b`).
- **Classic: 26 historical + today** (unchanged since `50dc5ee`, 09-08), plus today's
  aggressive and cautious personalities.

**Schedule.** Every Expert vs every Expert (30 seeds) and every Expert vs every Classic
(4-8 seeds), each 1 hero vs 3 copies, hero in all four chairs, both directions:
**14,851 games, 100% decisive.** Ratings are a winner-only Plackett-Luce fit over every
game (mean variant = 1500), with 95% bootstrap intervals (40 resamples).

| rating | 95% | variant |
|---|---|---|
| 2018 | 1995-2046 | **Expert today** (`a168a4b`, spends) |
| 1997 | 1974-2018 | Expert `5c354a8` 09-17 = today without the hand rule |
| 1987 | 1974-2012 | Expert `328c235` 09-16 |
| 1964 | 1945-1979 | Expert `0000a33` 09-15 |
| 1901 | 1882-1920 | Expert `bee0ea3` 09-15 |
| 1843 | 1832-1865 | Expert `cd014d0` 09-15 |
| 1745 | 1735-1762 | Expert `a772413` 09-14 |
| 1730 | 1689-1790 | Classic `a1ce686` 08-29 (see below) |
| 1577 | 1504-1639 | Classic cautious (today) |
| 1538 | 1528-1555 | Expert `1f2c8f0` 09-14 (the first) |
| 1480 | | Classic balanced (today) |
| 1045-1540 | | the other 25 Classics; the two 08-09 baselines are last |

Every Expert beats every Classic lineage by a wide margin except the first one:

| Expert, 1 vs 3 Classics (29 Classics pooled, ~510 games each) | win rate |
|---|---|
| today | 90.9% (88.0-93.1) |
| today without the hand rule | 90.1% (87.2-92.5) |
| `328c235` / `0000a33` | 90.3% / 90.9% |
| `bee0ea3` / `cd014d0` | 79.6% / 76.4% |
| `a772413` / `1f2c8f0` | 67.8% / 65.0% |

A single Classic at a table of three of today's Experts won **0-6%** in every lineage but
one.

**Findings worth acting on**

1. **Expert has only improved.** Each shipped Expert is at least as strong as the one
   before; today's is the strongest, and the first (`1f2c8f0`) was barely above Classic.
2. **The strongest Classic is one that cannot trade.** `a1ce686` (the 08-29 merge of
   #6) could not answer another seat's offer at all, so it declined everything. It rates
   ~250 above today's Classic and is the only Classic that beats three of today's
   Experts more than 1 time in 16 (18.8%). That is TODO "Start here" #3 seen from the
   other side: Expert leans on trading partners, and a refusing seat is its weak spot.
3. **Today's cautious Classic outrates today's balanced one** (1577 vs 1480), and
   aggressive (1529) does too. Balanced is what `BotDifficulty.classic` defaults to.
4. **Hoarding was a Classic problem too, and was fixed early.** The 08-09/08-10 Classics
   ended 18-35% of their turns over 7 cards and discarded 14-34 cards a game; since
   08-29 every Classic is under 1% and ~1.5-2 cards.

**Honest limits.** Expert-vs-Classic cells are 16-32 games each: fine for the pooled
numbers and the rating, too small for any single cell. Classics from before 08-29 are
not reproducible across processes (the per-process hash seed reached their decisions),
so two of them that play alike would still count as two. The two 08-09 baselines had
no robber or development-card logic yet; 1.3% of their decisions took the neutral
fallback. Before 09-02 no bot could answer someone else's offer; today's rules decline
for it (counted as `tradesBlocked`, not as incompatibility).

## What it cost: a leak that froze the Mac

The run rebooted Jake's MacBook Air three times (kernel panic: "watchdog timeout: no
checkins from watchdogd in 92 seconds") and once showed "Your system has run out of
application memory". It was first blamed on CPU load. **It was a leak**: a Swift
command-line loop doing Foundation pipe I/O (and, for the 2026-08 builds,
`JSONSerialization`) never drains its autorelease pool. Seat servers grew ~23MB/s,
workers ~3MB/s, and 20GB of swap filled. With `autoreleasepool` around each request
both hold ~12MB over the same 40s test that took a seat server to 955MB (`6b6e232`).

The first reboot also wiped `/private/tmp` and ~5,000 games with it. Now:
`tournament.py run` resumes from any earlier result files under any worker count,
defaults to half the cores at `nice 10`, holds `caffeinate`, and stops everything if any
worker or seat server passes `--max-process-mb` (1024). Keep results under
`~/Library/Caches/`.

## Reproduce

```bash
scripts/tournament/build-version.sh <sha> ~/Library/Caches/empires-tournament/seats   # per version
swift build --package-path Packages/CatanAI -c release --product arena
python3 scripts/tournament/tournament.py probe    --seats-dir $D/seats --out $D/probe.jsonl
python3 scripts/tournament/tournament.py run      --arena $D/arena --schedule $D/probe.jsonl --seats-dir $D/seats --results-dir $D/probe
python3 scripts/tournament/tournament.py roster   --results $D/probe-all.jsonl --out $D/roster.json
python3 scripts/tournament/tournament.py schedule --roster $D/roster.json --pairs expert --seeds 30 --first-seed 9000000 --out $D/ee.jsonl
python3 scripts/tournament/tournament.py schedule --roster $D/roster.json --pairs expert-classic --seeds 4 --first-seed 9100000 --out $D/ec.jsonl
python3 scripts/tournament/tournament.py run      --arena $D/arena --schedule $D/sched.jsonl --seats-dir $D/seats --results-dir $D/tour
python3 scripts/tournament/tournament.py analyse  $D/tour/*.jsonl --roster $D/roster.json
# the spend-vs-hold head-to-head: sim --seats eval,eval-holder,eval-holder,eval-holder (and rotations), seeds 7000000..7001499
```

## Also on this branch

**How to Play uses the game's own theme** (`d4bda13`, Jake: "use the exact theming from
the game"). Resource art, cost rows, dice, number token, road, robber, development cards,
hex frames, card plaques and the mode tag now reuse the board's and hand's components
and colours. Verified: `HowToPlayFlowTests` passes; development-card step screenshotted.
**Open:** the Rules text says "the dots under each number show how likely it is" and
Conquest strength is "the number of dots under its number", but the board draws no dots.
Jake to decide: reword, or add dots to the tokens.
