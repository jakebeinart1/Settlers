# Naval AI confirmation study — 2026-10-05

The frozen Naval Expert passed the declared strength criteria at both supported
table sizes against the fully naval-capable Traditional anchor. All 1,464
confirmation games completed, with no illegal-action/checkpoint failures, forced
turn endings, idle sailing cycles, resource trade cycles, or duplicate proposals.
This is a headless policy result; the app's native acceptance receipt is separate.

| Table | Expert wins | Expert Wilson 95% interval | Traditional control | Paired improvement | Paired 95% interval |
|---|---:|---:|---:|---:|---:|
| Three players | 205/396 — 51.77% | 46.85–56.65% | 132/396 — 33.33% | +18.43 percentage points | +13.64–23.23 points |
| Four players | 154/336 — 45.83% | 40.58–51.18% | 84/336 — 25.00% | +20.83 percentage points | +16.37–25.30 points |

The acceptance rule was fixed before confirmation: observed improvement of at
least ten percentage points and a paired interval strictly above zero, separately
at **both** table sizes. Balanced personalities were used throughout. These
results concern this naval policy/anchor pair; earlier Expert revisions, other
personality mixes, and human opponents were not measured here.

The candidate is source `d8639917f68563b6fd2ca0d38c5fc28d3fc80a18`, Release SHA-256
`509f0b575250a2426c9d026ef3eab9c764dea35e5d68c7fa0e68402f6ee2c952`.
The corrected Traditional anchor is source
`a316139bb2daa22d7224c19953f4a2e32c699c2f`, Release SHA-256
`1b0117a4d44fbe4888ab4868f7c4cb0a22001213766ea284bc4b9c4afa9bd582`.
Both use engine source `81bb29c5a6c4acc35ff268976aef4c58c71b0a03`, map/naval rules
version 1, engine rules version 3, and result schema/protocol version 3. Sources,
commands, process exits, timing records, and manifests are preserved in the
[evidence package](../../../../Packages/CatanAI/Tools/NavalEvaluation/evidence).
The two original binaries and complete revisit checkpoints/traces are preserved
outside Git at `/Users/alex/.codex/artifacts/naval-ai/d863991/`.

The three map families were crossed with fog on/off and flexible resources on/off
for twelve cells. Cell c used confirmation seeds `800000 + c*1000`: eleven seeds
at three players and seven at four, with every occupied chair in both arms. This
produced 132 and 84 independent seed clusters, respectively. The paired bootstrap
used 20,000 stratified resamples, seed `20261004`, and quantile indices 499/19499.
Chair correlation was reported descriptively and never used to discount sample
requirements. Table sizes were not pooled. The corrected anchor's Traditional
trajectories also matched the candidate's Traditional trajectories across all
24 development configurations before confirmation.

An independent audit found a floating-point arithmetic edge before interpreting
confirmation results: nested sums of thirds could turn a mathematically zero
bound into a tiny positive epsilon. The canonical calculation sums integer
candidate-minus-control win counts before one division, preserving exactly the
same resamples and criteria. The [revision record](../../../../Packages/CatanAI/Tools/NavalEvaluation/arithmetic-revision.json)
and byte-identical original scripts are retained. For the actual completed
study, every descriptive field matches the original analyzer exactly; paired
numbers differ only by floating-point roundoff. The portable validator additionally
rejects asymmetric/missing/extra pairs, wrong source/policy/configuration labels,
failed processes, inconsistent executable identities, divergent control
fingerprints, action counts beyond 6,000, and incomplete timing evidence.

Both policies deliberately cover purchases, movement, global discoveries,
colonies, flexible production, capture, resource funding, trade responses, cards,
discarding, and victory. Expert adds public sea-route planning, complete-recipe
funding forecasts, spending opportunity cost, public rival urgency, marginal
fleet access, capture exposure, and provable same-turn colony wins. Development
traces justified refinements to closing recipes and excess hull spending; no
confirmation seeds were used for tuning. Regression fixtures prove certain wins
outrank uncertain draws, independently fund winning Longest Road recipes, and
avoid promising colony bonuses through fog. Opponent exact hands/cards, unseen
terrain/component identities, future deck order, and engine RNG are masked;
public card counts and trade ledgers remain available. Both tiers pass hidden
state decision invariance and response-only RNG preservation tests.

| Focal policy average per match | Three-player Expert | Three-player Traditional | Four-player Expert | Four-player Traditional |
|---|---:|---:|---:|---:|
| Ships purchased | 1.20 | 1.53 | 1.15 | 1.50 |
| Overseas settlements founded | 2.38 | 1.78 | 2.83 | 2.16 |
| Cities upgraded | 2.26 | 1.66 | 2.13 | 1.45 |
| Development cards purchased | 2.95 | 4.12 | 2.81 | 3.93 |

The refinement converts existing access into points instead of rewarding extra
hulls. Across confirmation games there were 7,335 purchased ships, 10,379 real
overseas settlements, 5,012 captures, and 1,389 flexible-resource choices. Ships
and overseas settlements occurred in 1,463/1,464 games. The remaining game,
seed 805001 at three players/chair 1, reproduced exactly: three city upgrades,
two held victory cards, and a guaranteed Largest Army Knight closed 12→14 VP in
523 actions. Every chair had zero affordable ship opportunities; its masked
decision audit and full trace are preserved. A naval investment is not compulsory
when an available home-economy finish is better.

All 124 confirmation games containing raw within-turn ship revisits were
inspected against their completed checkpoint, full trace length/fingerprint,
source identity, and detector verdict. They contained 152 raw revisits and zero
idle revisits. The [inspection index](../../../../Packages/CatanAI/Tools/NavalEvaluation/evidence/held-out/revisit-inspection.json)
pins the retained full artifacts. Discovery, new settlement access, or a fleet
ownership/purchase change can justify returning; position, remaining movement,
resources, logs, and action counters cannot erase an idle cycle. Fixtures cover
idle returns, productive colony backtracking, and city upgrades that do not
invent new access. Every committed action in every match validated, encoded,
decoded, revalidated, and compared its entire session checkpoint.

The declared land-only development probe also completed 84/84 games. At three
players it won 15/36 (41.67%, Wilson interval 27.14–57.80%); at four it won 7/48
(14.58%, 7.25–27.17%). It bought/captured no ships and founded no overseas
settlements. Its naval opponents bought 278 ships and founded 494 overseas
settlements. This small diagnostic does not establish shipping dominance or
necessity. It supports preserving multiple paths to victory while expedition
adoption is strong in the main study.

The contended confirmation run recorded 905,128 decisions: 1,867 exceeded 50ms
and 48 exceeded 150ms, meeting aggregate p95≤50ms/p99≤150ms budgets. Worst
per-game tails were 53.562ms/194.267ms and remain in the raw report. The separate
one-worker, all-Expert matrix covered all twelve development cells at both table
sizes: 24/24 complete and byte-identical trajectories to the frozen development
matrix. Of 14,157 decisions, thirteen exceeded 50ms and none exceeded 150ms;
worst per-game p95/p99 were **21.079ms/49.637ms**. The host had 18 physical/logical
cores and 48GiB; heavy native tests were paused for this run. Timing covers
`GameSession.decideNextDetailed`, excluding engine application, checkpoint JSON,
rendering, and physical-phone execution. Phone performance is unmeasured.

The pre-confirmation integrated package stages passed 329 engine tests and 281
AI tests, with coverage 96.52%/95.63%. Native integration and the subsequent
terminal trade-queue hardening require their own source and regression receipts;
see [product acceptance](../acceptance.md). They do not alter this frozen policy
study's artifact provenance. Reproduction commands and data-integrity checks are
in the [tool README](../../../../Packages/CatanAI/Tools/NavalEvaluation/README.md).
