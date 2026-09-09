# Heuristic evidence workflow — first practical trial

Started September 8; updated September 9, 2026. Stage 4 of the [AI program](AI-PROGRAM.md).
**Decision: keep developing the diagnostic method; do not tune the bot or create
the reusable skill yet.** This is a trade-only development trial, not a stronger
AI, a general strategic audit, or proof of representative human-facing behavior.

## What changed and what actually ran

- One shared trade scorer now exposes the actual gain, cost, acceptance threshold
  and threshold contributions used by `Bot`. Recording does not call the policy
  a second time. Missing/unevaluated scores are not invented.
- Native `sim` records invocation before the policy runs, its returned move and
  scores, then committed moves and session checkpoints. This matters because
  automated trade consultations can return without ever becoming committed moves.
- A frozen **24-game schedule** ran under the existing **600-second watchdog**,
  with a 60-second per-process limit and 2 GiB total trace limit. It completed
  in about **113 seconds**, including a separate untraced run for every game.
- Every game reached a winner. All **24 traced/untraced result records matched**,
  including move fingerprints. This is functional parity, not strength evidence.
- The batch covers 3/4 players, standard/randomized boards, all-Balanced and
  mixed Balanced/Aggressive/Cautious rosters, at **10 VP only**. Four mixed seed
  families rotate through every chair; ten fresh all-Balanced families bring
  the total to **14 independent families**. Rotations are not independent games
  for statistical inference.

The frozen source/executable, predeclared schedule, per-game results, raw traces,
progress and watchdog receipt are in the
[trial artifact directory](</Users/alex/Library/Application Support/EmpiresResearch/experiments/heuristic-corpus-20260908/>).
`trial-01/source/` is the collection-time source snapshot; later packet renderer
revisions do not change those games. Raw artifacts stay outside git.

## What the data says — and does not say

| Recorded population | Count | Interpretation |
| --- | ---: | --- |
| Policy invocations/returns | 13,137 | Includes automated responder consultations. |
| Committed moves | 10,840 | Not the same denominator as policy calls. |
| Scoped trade-response consultations | 4,158 | A consultation is not necessarily an executed exchange. |
| Acceptance absent from legal choices | 2,867 (69%) | Forced rejection; not evidence of overly harsh valuation. |
| Acceptance available | 1,291 | Actual valuation opportunities in this small self-play batch. |
| Returned accept among optional responses | 537/1,291 (42%) | The remaining 754 returned reject. Not a human-offer acceptance rate. |

Calling this a 13% acceptance rate (537/4,158) would mix forced rejection with
choice and point us toward the wrong fix. Neither denominator establishes
whether any individual trade was strategically good. Repeated consultations
and offers from the same game are correlated; these are descriptive counts,
not confidence intervals or prevalence claims about all play.

## Actual blind/revealed LLM review

Twelve packets were selected by seed family, then game, then scoped decision.
Two reviewers each read six **blind** packets before seeing the corresponding
actual choice and scores. They received no eventual winner, future RNG/deck
order, seed, raw trace, or scorer source. The policy currently receives all
players' resource hands and development-card identities; the packet must label
that reveal-all contract rather than imply hidden-information play.

- **Nine forced cases:** both reviewers found the missing payment resource.
  This corroborates feasibility; the packet already supplied the legality flag,
  so agreement is not an independent engine-verification score.
- **Three optional cases:** both reviewers withheld strategic judgment. Hands,
  public points, cards and ports did not identify production, useful legal
  destinations, or which player could act on the trade first.
- **After reveal:** scalar arithmetic explained all three optional decisions
  (two accepts, one reject). It did not explain why particular resources were
  assigned those values or prove those values were sensible.
- A useful falsifiable question emerged in case 009: the receiver gets wool
  but pays away its only ore. A story that this "completes a development card"
  would be false. The current scorer values gains/losses against the original
  hand; investigate atomic before/after usefulness rather than assume a positive
  score means a complete useful plan. **No replacement rule was adopted.**

Original reviews and packets:
[review-02](</Users/alex/Library/Application Support/EmpiresResearch/experiments/heuristic-corpus-20260908/review-02/>).
Blind and revealed judgments are separate files and remain unchanged.
Six separately labelled optional-trade packets were also generated from the
same raw batch (`optional-01`); their September 9 review is recorded below.
They are a focused cohort, not a replacement representative sample.

## Efficiency and corrections earned by trying it

- Raw traces total **932,033,857 bytes**; lossless gzip copies total
  **40,316,406 bytes** (about 23× smaller). Originals were retained. Compression
  reduces archival cost; it does not by itself make every future query cheap.
- The twelve blind packets total **22,976 bytes**, ranging 1,629–2,192 bytes.
  These are measured bytes, **not token counts**. We did not measure total agent
  token cost or cost per resolved strategic issue; no strategic issue is resolved.
- Do not feed entire games to an LLM. Stream the raw evidence, sample bounded
  decision packets, and retrieve additional native facts only when required.
  The current packet cap is 8,000 characters, not a measured token budget.
- Final strict validation/formatting took **97 seconds**, with about **52 MB**
  peak resident memory, while tooling tests also ran. Streaming keeps memory
  bounded, but reparsing the full corpus for each presentation change will not
  scale well. After the evidence fields settle, materialize a validated compact
  decision index so review iterations do not repeatedly parse full states.
- An early analysis glob expanded before the final game existed and covered
  23 games. `review-01` is retained but **superseded** by the full 24-game review.
  This earned an explicit expected-game guard and exact schedule validation,
  rather than relying on a folder glob as proof of completeness.
- A read-only adversarial audit distinguished record counting from proof:
  scorer receiver/offer attribution, checkpoint/RNG continuity and exact schedule
  membership require validation. Full native replay from the recorded initial
  state is a separate unimplemented check; do not call these traces replay-verified.
  All three validator fixes were applied and the same 24 raw games passed again:
  [final validation manifest](</Users/alex/Library/Application Support/EmpiresResearch/experiments/heuristic-corpus-20260908/review-03-validated/manifest.json>).
  All twelve reviewed decision identities stayed identical; no favorable
  replacement sample was substituted. The final renderer is snapshotted beside
  that manifest. Original blind/revealed reviews remain attached to `review-02`.

## September 9 — native context closes one diagnostic gap

**Decision: keep the richer evidence workflow; do not change trade acceptance
yet.** No new training, weight tuning, personality work or strength experiment
ran. The same twelve selected cases were enriched, rather than collecting a
replacement sample that might make the method look better.

`TradeReviewContext` now applies acceptance to a copy through the native engine.
It reports each seat's before/after inventory, legal build options, port rates,
production and who can act now. An off-turn seat's options are explicitly
counterfactual: its own main turn on the frozen board. Eleven road placements
means eleven possible locations, not eleven affordable roads or eleven useful
plans. Production uses native payouts over the possible next dice rolls, with
the current bank and robber; seven's discard/steal losses are excluded.

The executing scorer can now record each resource's settlement/city/development
card/road contribution. Ordinary evaluation leaves this opt-in detail off.
For the old recordings, `trade-review` recomputes those inputs offline and checks
them against the original scalars. It allows only 1e-12 relative/absolute
rounding noise; the accept/reject result must match exactly. Historical offer
dictionaries can sum in a different order across processes, so this is a
**numerical match, not bit-exact historical component capture**. Nine unscored,
forced-rejection cases explicitly claim native context only, not matched scores.

### What the second blind/revealed review found

One reviewer read the same three optional cases blind, saved those judgments,
then saw the choices and score inputs. This is a usability follow-up, not three
new independent samples or a strategic truth label.

| Case | Before reveal | What the supplied evidence supports |
| --- | --- | --- |
| 002 | Insufficient evidence | Receiver gains two lumber for wool but no immediate option changes; proposer can buy a development card. The zero resource score is explained, not justified as optimal. |
| 007 | Tentative accept, low confidence | Receiving lumber unlocks eleven road-placement options. Neither those counts nor reviewer agreement establish route usefulness. |
| 009 | Insufficient evidence | The scorer credits wool toward a development card while the payment removes the sole ore required for that card. Native acceptance still leaves the purchase unavailable. |

Case 009's accounting mechanism is now reproduced in a native scenario test:
ore=1/grain=1 receives wool and pays ore; the wool gets a 1.5 development-card
contribution, while the ore loss gets zero development-card cost because costs
also use the original hand. A paired control with **two ore** awards the same
completion contribution but genuinely unlocks the purchase after payment.
Another test shows a trade can remove a purchase that was already available.
These characterize the current scorer; they do not change it.

**Important counterexample:** swapping readily produced ore into scarce wool
could still be sensible. The accounting mismatch does not prove rejection would
win more games. A candidate should evaluate joint before/after target progress,
not impose a blanket ban on prerequisite swaps. Test sole-prerequisite swaps,
surplus payments, genuine completions and production-scarcity cases before
considering any policy change. Future paired continuations also need explicitly
coupled chance events: equal starting seeds alone do not guarantee equal future
dice/deck draws when branches consume randomness differently. That evaluator
extension is proposed, not implemented here.

### Evidence, efficiency and audit corrections

- [September 9 artifacts](</Users/alex/Library/Application Support/EmpiresResearch/experiments/heuristic-corpus-20260909/>): `enriched-01/reviewer-blind.md` and
  `reviewer-revealed.md` preserve the actual review order and abstentions.
  `enriched-02/` is the corrected final publication with source/input/binary
  hashes, frozen renderer/enricher and a completion receipt.
- The twelve-case final enrichment took **0.58 seconds** locally, including
  source-hash checks and native processing. It reuses the previously validated
  selection and parses only selected lines. This is not a speedup measurement
  against the 97-second full-corpus validation: they perform different work.
- Blind packets are regenerated from verified input through an allowlist,
  not copied from potentially edited Markdown. No chosen move, scorer inputs,
  future dice, deck order or RNG state goes into the blind text. The richer
  packet limit is 12,000 characters, still not a measured token budget.
- A read-only audit caught an inaccurate provenance label on unscored cases;
  corrected in `enriched-02`. Historical scalar matching now explicitly allows
  rounding noise instead of requiring cross-process dictionary sums to match
  bit for bit. Accepted/rejected booleans and material score differences still
  fail. Original reviewed files remain unchanged.
- Publication tests exercise source/identity mismatch, private-data exclusion,
  contribution arithmetic, native subprocess failure with retained partial
  output, and packet-budget failure. Failure never publishes a success receipt.
  The native subprocess has a 60-second timeout, 8 MiB input and 120-case limits.

Still missing: useful route/settlement rankings, multi-action plans, full native
trajectory replay, a causal continuation test and evidence of stronger play.
The method is promising for narrow trade accounting; it has not earned a general
heuristic-audit skill or large collection run yet.

## Joint-accounting experiments and stopping rules

### Locked small experiment: joint-target accounting (September 9)

Before computing candidate results, fix one alternative: for each existing
build target with weight `w` and total missing resource count `D`, value is
`2*w/(1+D)`. Score the native atomic after-hand minus the before-hand, summed
over the same targets. The factor two preserves the existing credit `w` for
acquiring the final missing card. Earlier progress is deliberately less valued;
this is **a strategic reshaping as well as an accounting correction**.

Run offline only on the three original scored cases and six separately selected
optional cases. Keep original weights and thresholds unchanged; decision flips
are sensitivity, not demonstrated improvements or calibrated acceptance rates.
Require identity/cycle neutrality, reversal symmetry, bundle order independence,
monotonicity for additions, saturation past a target's resource needs, and sole
versus surplus prerequisite controls. Reject the implementation on any failure.
Keep the formula only as a candidate for a later controlled game experiment if
these checks pass; do not change the default Bot, tune it to reviewer votes or ship it.

Known counterexamples remain explicit: scarce resources, bank conversion,
multiple future purchases, inaccessible building sites and an empty development
deck. A coherent resource-value formula does not solve those planning problems.

### Result: retain the candidate for testing, not product adoption

The older six-case manifest lacked the newer validation receipt. Revalidating
all 24 games against the frozen schedule preserved **all six exact identities**;
`optional-validated-02/` records this. Native enrichment completed in under a
second. A fresh reviewer read all six blind, saved those judgments, then saw the
choices and scorer inputs. No outcomes, raw state or candidate scores were shown.

The blind/revealed round produced three agreements, two disagreements and one
abstention—not an accuracy score. Case 005 independently exposes the same
mechanism beyond development cards: lumber earns settlement and road completion
credit while payment removes the sole brick. Neither build becomes available.
The reviewer also corrected its own proposed bank-trade sequence: spending all
four grain for wool leaves no grain to buy the development card. This is why
plausible text must be checked against actual post-payment inventories.

`TradeAccountingBoundaryTests` adds **60 synthetic native cases**: ordered
development-card resource swaps, quantities one/two, sole/surplus payment,
irrelevant-resource payment and paired stocked/empty-deck controls. They preserve
legacy decisions. Empty-deck cases confirm that resource completion credit is
not a promise of a legal purchase; that separate planning limitation is not fixed.

The alternative is implemented only in `scripts/trade_accounting.py`, not in
Swift `Bot`, the app, or the simulation policy roster. It reconstructs missing
resource totals from native scorer metadata and native after-hands. The script
checks transfer arithmetic, complete target metadata and source-output hashes;
it does not implement trading legality or copy runtime build costs into Python.

| Development cohort | Legacy accepts | Alternative accepts | Changes with the original threshold |
| --- | ---: | ---: | --- |
| Original three scored cases | 2/3 | 1/3 | Case 009 prerequisite swap: accept → reject. |
| Separate six optional cases | 3/6 | 1/6 | Case 005 prerequisite swap and case 006 scarce-grain trade: accept → reject. |

These are **sensitivity counts, not win rates or population acceptance estimates**.
The other nine original cases remain explicitly unscored. Final results live in
`joint-original-02/` and `joint-optional-02/`; reviewed packets/judgments remain
in `enriched-01/` and `optional-enriched-01/`. Hash-complete input publications
are `enriched-03/` and `optional-enriched-02/`.

Mechanical tests pass: **3,125 synthetic hands / 50,000 reversible swaps** match
an independent whole-hand potential calculation; **6,075 addition-order pairs**
check monotonicity, bundle equivalence and cycle neutrality. Worked examples
preserve genuine completion, remove false completion credit, and recognize a
lost purchase. These are arithmetic checks, not played games.

**Decision:** keep the fixed formula for an isolated game experiment, not as a
fix ready to merge into the bot. Case 006 reveals the risk: distant city progress
falls from 0.625 to 0.25, below the unchanged 0.4 threshold, rejecting grain that
is produced much less often than the surrendered brick. That could be a bad
rejection, but it could also avoid helping an opponent; neither is proven.
Do not tune the threshold to make the reviewer happy. An independent critic
verified the reconstruction and reproduced both result files; it also found
a missing input-transfer consistency check, now fixed and regression-tested.

**Subsequent native screen completed:** the isolated policy passed its controls
and all 448 comparison games. It tied Balanced in one comparison and won more in
three, but every interval still includes no improvement. The
[full-game report](2026-09-09-joint-trade-screen.md) has exact results and the
next independent-test boundary. Keep the candidate experimental; do not ship or
tune it to these development seeds. Personality and the proposed automated tuner
remain later work in the [larger protocol](2026-09-08-heuristic-corpus-plan.md).

## Verification and delivery boundary

September 8: Release `sim` built with warnings as errors; all 121 CatanAI tests passed,
including the existing seeded trajectory guards and 11 new assessment tests.
Eight process-level corpus tests passed (including separate-process semantic
RNG/trace agreement, masks, counts, bounded failures and overwrite refusal).
The complete Python tooling suite passed **91 tests after final validator
hardening**; its output is retained in the artifact's `validation/`.
SwiftLint and `git diff --check` passed. No app UI changed or new iOS build ran
as part of this trial; the full app/UI gate has not been rerun for this branch.

September 9: **134 CatanAI tests passed** in 69.73 seconds and **98 Python
tooling tests passed** in 129.96 seconds. These include the native enrichment
CLI, scalar rounding/material-change/decision-change checks, unscored provenance,
traced/untraced game parity, separate-process trace/RNG agreement, native context
and the sole/surplus-ore control. Release `sim` and `trade-review` built with
warnings as errors; SwiftLint and diff whitespace checks passed. All twelve
case identities and native before/after facts are unchanged between the reviewed
`enriched-01` and corrected `enriched-02`; only provenance/rendering was revised.
Logs are retained in the September 9 artifact's `validation/`. This is package
and tooling verification, **not** a new app/UI gate or on-phone gameplay claim.

The completed game-screen iteration additionally passed **143 CatanAI tests**
and **114 Python tooling tests**, including the new native candidate and frozen
runner. Source, raw games, both binaries and the terminal watchdog receipt are
retained with the [screen report](2026-09-09-joint-trade-screen.md).

This research remains on `codex/heuristic-corpus-plan-20260908`, not merged into the
shipped app. No new trained model or tuned production heuristic was produced.
The game comparison is exploratory, not evidence sufficient for adoption.
**Build 1.0 (7)** is the last verified TestFlight delivery
(September 8, 18:51 UTC), running Balanced for new games; physical full-game
verification remains separate. See the [delivery report](2026-09-08-heuristic-delivery.md).
No new delivery was performed by this trial; App Store Connect was not rechecked.

## Locked native development screen (before results)

Test exactly the same formula, weights and old threshold, through an explicit
`joint-balanced` simulator policy. Only scoped automatic trade replies change;
all other choices delegate to the existing Balanced bot. This is not a rewrite
of proposing trades, bank trades or full main-turn planning. The app keeps its
existing policy and cannot select this experiment.

Four separately reported strata: three/four seats × Balanced/Aggressive
opponents; randomized boards, ten points. Each uses sixteen fresh seed families,
every evaluated chair, candidate and unchanged-baseline arms: **448 games**.
Seed ranges begin 880000, 880100, 880200 and 880300. These become development
data, never a future held-out adoption test. Same starting seeds do **not**
guarantee identical subsequent dice after different RNG consumption.

Freeze both executables, source, commands and results. Check unchanged-policy
trajectory parity between binaries before play. Use at most two workers,
120 seconds per sixteen-game shard and the existing independent watchdog's
600-second total deadline. A crash, missing game or unfinished game invalidates
the completed-screen claim; retain failures rather than replacing seeds.

Report each stratum's wins and paired seed-family bootstrap interval, using
the existing analyzer. Five percentage points is the practical improvement
target. A 95% interval entirely below zero in any stratum rejects this version
for adoption; mixed or overlapping results remain inconclusive. Even a positive
screen is not a shipping decision: independent held-out evaluation, human-offer
coverage and phone performance remain required. No automatic parameter tuning
or favorable-seed reruns are allowed.

## Repeat the trial, not the whole research program

For a presentation/context iteration on an **already exact-schedule-validated**
review, skip recollecting games and reparsing every state:

```sh
swift build --package-path Packages/CatanAI -c release --product trade-review -Xswiftc -warnings-as-errors
python3 scripts/enrich_corpus.py --review '/path/to/validated-review' \
  --binary "$PWD/Packages/CatanAI/.build/release/trade-review" \
  --output '/path/to/NEW-enriched-review'
```

Send only blind Markdown files to the first-pass reviewer. Keep the private
snapshot, explained files and raw native output out of that pass. A retained
partial directory without `receipt.json` is **not** completed evidence.

The existing `sim-harness` workflow supplies native games; the archived watchdog
supplies the hard time bound. Use a **new output name** for each run. From the
repository root:

```sh
swift build --package-path Packages/CatanAI -c release --product sim -Xswiftc -warnings-as-errors
python3 '/Users/alex/Library/Application Support/EmpiresResearch/handoffs/search-pause-20260908/source/scripts/training_watchdog.py' run \
  --output '/Users/alex/Library/Application Support/EmpiresResearch/experiments/NEW-TRIAL/watch' \
  --seconds 600 -- python3 scripts/pilot_corpus.py \
  --binary Packages/CatanAI/.build/release/sim \
  --output '/Users/alex/Library/Application Support/EmpiresResearch/experiments/NEW-TRIAL/games'
```

Wait for watchdog completion, not merely a launched process. Keep its launcher
log and terminal receipt. Then validate **against its exact frozen schedule**:

```sh
python3 scripts/review_corpus.py \
  '/Users/alex/Library/Application Support/EmpiresResearch/experiments/NEW-TRIAL/games/'*.trace.jsonl \
  --schedule '/Users/alex/Library/Application Support/EmpiresResearch/experiments/NEW-TRIAL/games/schedule.json' \
  --expected-games 24 --sampling-seed 1983 --count 12 --cohort all \
  --output '/Users/alex/Library/Application Support/EmpiresResearch/experiments/NEW-TRIAL/review'
```

`--cohort optional` makes an explicitly filtered diagnostic sample, not a
prevalence estimate. Keep manifest/source references away from the blind reviewer;
send only `case-*-blind.md`, preserve that judgment, then reveal the matching
explained files. All these seeds are development data. This document records the
trial commands; it is **not** the requested future reusable skill.
