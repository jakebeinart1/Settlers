# Stage 4 heuristic closeout — cold-start handoff

September 9, 2026. **Close this bounded iteration; personality is next.**
This is not completion of strategic-quality research, expert AI, proof of stronger
play, or a claim that road strategy is fixed. No further research, tuning, policy
promotion or delivery is authorized by this handoff.

Branch: `codex/heuristic-corpus-plan-20260908`. Main `4737471` was integrated at
`0479681` before the final comparison. **Retain Balanced.** The joint-trade
candidate failed promotion: against Balanced at four seats, 53/256 wins (20.7%)
versus 64/256 (25.0%), difference −4.3 points, 95% interval −8.6 to 0.0.
All 1,792 comparisons plus 28 qualification games finished under their original
deadlines. See the result report for all four separate comparisons. Do not infer
adoption from an experimental class being present in the source.

**Final comparison boundary:** freeze fresh Balanced from
`47374713ce8010f63a8b3942f5408dbc2f376113` and the candidate on that same main.
Main includes Jake's `50dc5ee` hidden-VP threat fix: opponents contribute public
VP, the bot's own standing includes its own hidden VP, and held-card count stays
visible. This changes shared threat-dependent decisions, not just trade replies.
The old `ec058ab` screen is historical evidence only; do not reuse its executable
hashes or pool its results into the fresh comparison. Full observations still
expose state; this fix is not a general hidden-information projection.

## Read first; chronology matters

- [AI program](/Users/alex/Documents/Personal%20Projects/Settlers/docs/AI_summaries/AI-PROGRAM.md): six stages; Stage 4 is strategy, Stage 5 personality, Stage 6 optional models/search/training.
- [Corpus protocol](/Users/alex/Documents/Personal%20Projects/Settlers/docs/AI_summaries/2026-09-08-heuristic-corpus-plan.md): larger cohorts, tuners and causal continuations are proposals, not completed work.
- [Trial and mechanical findings](/Users/alex/Documents/Personal%20Projects/Settlers/docs/AI_summaries/2026-09-08-heuristic-corpus-trial.md): collection, reviews, accounting controls and reusable commands.
- [First native screen](/Users/alex/Documents/Personal%20Projects/Settlers/docs/AI_summaries/2026-09-09-joint-trade-screen.md): exact match structure, wins, uncertainty, safeguards and no-ship decision.
- [Paused research restart map](/Users/alex/Documents/Personal%20Projects/Settlers/docs/AI_summaries/2026-09-08-research-handoff.md): neural/search source, weights, failures and separate restart boundary.

The trial's earlier “Python only” candidate paragraph describes an intermediate
state: the later Swift candidate exists. The corpus protocol's larger cohorts,
road investigation and automatic tuning remain future proposals, not an active
queue. Do not flatten historical sections into current status.

## Authoritative architecture map

Read the named functions, not historical claims in their comments. These are
source-verified mechanisms, not newly runtime-verified behavior.

| Responsibility | Code and actual boundary |
| --- | --- |
| Shared decision/session contract | [GameSession.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanEngine/Sources/CatanEngine/GameSession.swift>): `Policy`, `GameObservation`, scoped legal masks, separate policy RNG, queued trade replies, checkpoints and 25-action backstop. Observation exposes full state; this is not hidden-information play. |
| Bot entry and arbitration | [HeuristicPolicy.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanAI/Sources/CatanAI/HeuristicPolicy.swift>) → [Bot.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanAI/Sources/CatanAI/Bot.swift>): phase dispatch, response-only fast path, category priorities, legal matching. A selected build competes at a fixed category score; internal build scores are not shared utilities or win probabilities. |
| Immediate build/road planning | [BuildPlanner.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanAI/Sources/CatanAI/BuildPlanner.swift>): `chooseBuild`, `score`, `expansionTarget`, `committedPathBonus`, Longest Road claim/pursuit/defense and `bridgesOwnFragments`. Thresholded scoring plus RNG near-ties; no stored multi-turn plan. |
| Supporting evaluations | [PlacementHeuristics.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanAI/Sources/CatanAI/PlacementHeuristics.swift>), [ThreatAssessment.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanAI/Sources/CatanAI/ThreatAssessment.swift>), [RobberHeuristics.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanAI/Sources/CatanAI/RobberHeuristics.swift>), [DevCardHeuristics.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanAI/Sources/CatanAI/DevCardHeuristics.swift>): production/ports, opponent threat, robber choice and card intent; Road Building picks first road then rescored second greedily. |
| Production trade scorer | [TradeHeuristics.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanAI/Sources/CatanAI/TradeHeuristics.swift>): `assessment` sums per-resource values across four build targets against the original hand. `proposeTrades`/`bestBankTrade` separately choose the nearest still-blocked resource-cost target; proposals have retry/quantity bounds. |
| Isolated candidate | [JointTradeResponsePolicy.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanAI/Sources/CatanAI/JointTradeResponsePolicy.swift>): native atomic acceptance on a copy; sum per-target differences of `2*w/(1+missing)`; strict `delta >` legacy threshold. Only single-offer response masks with rejection change; other decisions/RNG delegate to Balanced. |
| Diagnostic evidence | [TradeAssessment.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanAI/Sources/CatanAI/TradeAssessment.swift>), [TradeReviewContext.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanAI/Sources/CatanAI/TradeReviewContext.swift>), [CorpusPolicy.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanAI/Sources/sim/CorpusPolicy.swift>): actual scorer capture, offline native before/after facts, single policy invocation. Review context is not consulted by the bot. |
| App and human offers | [GameViewModel.swift](</Users/alex/Documents/Personal Projects/Settlers/Settlers/ViewModels/GameViewModel.swift>): `makePolicies` creates heuristic policies; `resolveHumanProposedTrade` and `restorePendingNegotiation` call legacy trade valuation directly with affordability checks. Simulator `joint-balanced` does not cover these paths. |
| Style and voice seams | [BotPersonality.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanAI/Sources/CatanAI/BotPersonality.swift>) separates three style dials from shared [BotWeights.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanAI/Sources/CatanAI/BotWeights.swift>). [OpponentProfile.swift](</Users/alex/Documents/Personal Projects/Settlers/Settlers/Models/OpponentProfile.swift>) persists identity/strategy; all current new-game catalog entries use Balanced. [TradeMessages.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanAI/Sources/CatanAI/TradeMessages.swift>) selects authored voice lines, not policy decisions. |

## Established evidence versus remaining risks

- **Reported corpus evidence:** 24 complete games/14 seed families, 10 VP,
  both board modes and table sizes; all traced/plain results matched. Of 4,158
  scoped trade consultations, 2,867 could only reject; 537/1,291 optional replies
  accepted. These are correlated self-play counts, not human acceptance estimates.
- **Reproduced accounting mechanism:** sole-ore→wool can receive development-card
  completion credit despite losing its prerequisite; surplus-ore controls genuinely
  unlock the purchase. Settlement/road prerequisite swaps also appear in controls.
  Arithmetic tests characterize this mismatch; they do not prove rejection is better.
- **Historical game screen against pre-Jake-fix `ec058ab`:** 448 comparisons plus 28 qualification games;
  16 families per table-size/opponent cell, all evaluated chairs, randomized/10 VP.
  Candidate tied Balanced in one cell and had higher point estimates in three;
  every interval included zero improvement. Receipt says `inconclusive-no-ship`.
  Fresh `4737471` confirmation is complete and supersedes this screen for the
  adoption decision; do not pool the cells or combine old/new baseline results.
- **Roads remain unresolved:** frontier, continuity and fragment-bridge bonuses
  exist, with [BuildPlannerTests.swift](</Users/alex/Documents/Personal Projects/Settlers/Packages/CatanAI/Tests/CatanAITests/BuildPlannerTests.swift>) covering local mechanisms.
  Expansion targets are recomputed, not remembered; hop searches use plain board
  adjacency rather than ownership-aware feasible routes. Legal immediate roads do
  not certify a reachable future settlement, a coherent sequence or worthwhile spending.
  The trade-only corpus did not audit route quality or establish better road strategy.
- **Trade risk remains:** both scorers omit acquisition time/scarcity, multiple
  purchases and usable build sites/deck availability from inventory value. The new
  potential discounts distant progress and rejects a reviewed scarce-grain deal
  that may be useful. The unchanged threshold is not calibrated to this new scale.
  Proposer “unlock” means newly affordable settlement/city resources, not legal build/win.
- **Source-level planning risk, not reproduced harm:** `bestBankTrade` checks a
  give resource against target needs before payment, not the remaining inventory.
  Trade, card and build selectors do not share an explicit actionable plan.
  No blanket prerequisite-swap prohibition or threshold adjustment is justified here.
- **Evidence gaps:** full native replay of corpus trajectories, useful route rankings,
  multi-action/causal continuation comparisons, representative human offers and
  physical-phone latency remain open. Frozen-board legal-option counts are neither
  useful-plan counts nor forecasts. Historical scalar reconstruction allows 1e-12
  rounding noise; it is not bit-exact recovery of unrecorded components.

## Retained archive inventory and availability limits

Final local gate passed: **126 Python tooling tests, 222 engine tests, 145 AI
tests, and 322 app/UI tests (383 parameterized executions), zero failures or
skips**. Engine/AI coverage: 95.95% / 97.20%; Debug and Release builds passed.
The UI-hosted complete-match test passed in 33s, including its real recording,
game-over, new-game and save-clearing assertions. This is not manual play of
every move or proof against expert humans. A fresh QA install/launch survived
six seconds without a new crash report; its menu screenshot was opened and
inspected. Only the dedicated QA app container was reset; the phone/manual-play
save was not touched. Raw gate output, XCTest summaries, test tree and screenshot
are under the September 9 archive's `validation/`.

Closeout review boundary: `4737471...HEAD`, plus final runner/enrichment edits.
Standards review found a worker could start additional chunks after its sibling
failed; shared cancellation and a two-chair regression test now prevent that.
Spec review found missing sampling labels in enriched packets; all regenerated
blind/revealed packets and receipts now retain their cohort and frequency warning.
Confirmation additionally requires explicit binary hashes/source revision rather
than silently accepting historical defaults. Focused regression suites passed,
and targeted independent re-review closed these findings. The optional
`docs/agents/issue-tracker.md` review-plugin adapter is absent; this review used
the repository's actual checked-in corpus specification and GitHub baseline.

- [September 8 archive](</Users/alex/Library/Application Support/EmpiresResearch/experiments/heuristic-corpus-20260908/>): 24 raw trace files and `trial-01/schedule.json` present; collection source/binary retained. Use `review-03-validated/manifest.json` for validation and `review-02/` for original judgments; `review-01` covered only 23 games and is superseded.
- [September 9 archive index](</Users/alex/Library/Application Support/EmpiresResearch/experiments/heuristic-corpus-20260909/README.md>): final labelled packets are `enriched-04-cohort/` and `optional-enriched-03-cohort/`; native inputs/outputs match the preceding publications exactly. Earlier review judgments remain under their original paths. Final offline outputs are `joint-original-02/` and `joint-optional-02/`.
- [Native screen archive](</Users/alex/Library/Application Support/EmpiresResearch/experiments/heuristic-corpus-20260909/joint-game-01/>): **239/239 hashes verified**, including binaries, native source, baseline source archive, commands, analyses and receipts. All **908 final-confirmation hashes** were also verified. A fresh-context agent independently recounted all 1,792 games and regenerated both historical and final reports without running new games.
- [Final decision receipt](</Users/alex/Library/Application Support/EmpiresResearch/experiments/heuristic-corpus-20260909/confirmation-decision.json>) supersedes the immutable per-run `parent-decision-required` fields. Those fields mean the runner never promotes a candidate automatically, not that the closeout decision remains pending.
- [Screen watchdog receipt](</Users/alex/Library/Application Support/EmpiresResearch/experiments/heuristic-corpus-20260909/joint-game-01-watch.watchdog.json>): terminal `complete`, exit 0, September 9 17:28:08–17:34:01 UTC. This is a past run, not a live process check.
- [Historical screen source archive](</Users/alex/Library/Application Support/EmpiresResearch/experiments/heuristic-corpus-20260909/joint-screen-source.tar.gz>) is labelled `2c0a451`; exact pre-format executing source remains under the screen's `source/`. Use the portable closeout archive below for the final source and restore receipt.
- [Search archive](</Users/alex/Library/Application Support/EmpiresResearch/handoffs/search-pause-20260908/>): `research.bundle`, source, terminal evidence and archived watchdog/tournament tools exist. This older bundle is not a Stage 4 source backup. Follow its restart map only if search is explicitly reopened.

The [portable closeout archive](</Users/alex/Library/Application Support/EmpiresResearch/handoffs/heuristic-closeout-20260909/README.md>) contains a self-contained Git source bundle, both dated evidence roots and the exact watchdog. Its `SHA256SUMS` and `restore-verification.md` identify the final payloads and actual restore checks; missing receipts mean packaging is incomplete. These are local Mac artifacts, **not an off-machine backup**. Transfer and verify the archive on another host before assuming access there. Historical absolute paths remain unchanged inside hashed evidence; resolve them relative to the restored dated roots instead of editing receipts. Build caches and the redundant unpacked baseline checkout are excluded; its source archive/executable remain.

## Reuse commands; do not start another experiment by default

From the repository root, this rebuilds one report from retained games, not play
(executed by a fresh-context reviewer, exit 0; needs Python 3.11+ and `jq`):

```sh
HEURISTIC_SCREEN='/Users/alex/Library/Application Support/EmpiresResearch/experiments/heuristic-corpus-20260909/confirmation-p4-balanced'
python3 -B "$HEURISTIC_SCREEN/source/scripts/analyze-bot-evaluation.py" \
  --name joint-balanced-confirmation --schema-version 5 \
  --candidate-build-id "$(jq -r .buildIDs.candidate "$HEURISTIC_SCREEN/manifest.json")" \
  --candidate-policy experimental-joint-balanced-v1 --foil-policy heuristic-balanced \
  --baseline-build-id "$(jq -r .buildIDs.baseline "$HEURISTIC_SCREEN/manifest.json")" \
  --baseline-policy heuristic-balanced --baseline-foil-policy heuristic-balanced \
  --candidate-files "$HEURISTIC_SCREEN/p4-balanced/"candidate-seat*.jsonl \
  --baseline-files "$HEURISTIC_SCREEN/p4-balanced/"baseline-seat*.jsonl
```

Use each other cell separately; Aggressive cells require both foil IDs to be
`heuristic-aggressive`. Read receipts/manifests before recomputing any result.

- Collection, exact-schedule validation and native enrichment commands are already in the [trial report](</Users/alex/Documents/Personal Projects/Settlers/docs/AI_summaries/2026-09-08-heuristic-corpus-trial.md>); use new output paths, preserve failed prefixes and completion receipts, and supply only blind packets to initial reviewers.
- Historical [screen_trade_policy.py](</Users/alex/Library/Application Support/EmpiresResearch/experiments/heuristic-corpus-20260909/joint-game-01/source/scripts/screen_trade_policy.py>) accepts `--binary`, `--baseline-binary`, `--output`; baseline expects sibling `source.tar.gz`. Its original baseline is `joint-game-baseline/sim`; the renamed screen copy lacks that sibling. This runner locks old hashes/development seeds; rerunning it is not fresh confirmation.
- The [runner](</Users/alex/Documents/Personal Projects/Settlers/scripts/screen_trade_policy.py>) accepts `--players`, `--opponent`, `--first-seed`, `--seeds` together. Confirmation requires explicit candidate/baseline SHA-256 locks and baseline source commit. It chunks at 16 games, preserves raw failures, stops scheduling new sibling chunks after failure, and never promotes a policy automatically. Historical default seeds are not fresh holdouts.
- Future authorized runs must reuse the archived `training_watchdog.py` and a declared terminal deadline. Read [sim-harness](</Users/alex/Documents/Personal Projects/Settlers/.claude/skills/sim-harness/SKILL.md>) and [bot-strength](</Users/alex/Documents/Personal Projects/Settlers/.claude/skills/bot-strength/SKILL.md>) first; no new general audit/tuning skill was earned by this trial.

## Answers the next agent needs

1. **Final decision:** keep Balanced; do not promote `experimental-joint-balanced-v1`. The 1,792-game confirmation used fresh `4737471` builds in both arms. No three-player gain reached the declared practical target; four-player point estimates were worse. No further candidate or automatic tuning round is queued.
2. **Personality foundation:** the app's existing Balanced policy, including Jake's hidden-VP fix in current main, not the experimental trade policy. Keep the candidate opt-in for reproducibility; it does not reach app settings or human-offer resolution. There is no newly trained network or new strength tier.
3. Can the next agent access the raw evidence and reproduce its hashes/reports? If not, transfer the retained artifacts before starting new collection.
4. Which player-visible traits and voice constraints define Stage 5? Separate strategic style, strength/difficulty, opponent modelling and authored expression. Preserve seeded decisions and saved identities; no runtime LLM under the current program.
5. What is the latest verified delivery versus physical-phone evidence? Apple checked September 9: latest Alex-app upload is **7, VALID**, uploaded September 8 18:45:09 UTC. At **18:10 UTC**, `devicectl device info apps` read **1.0 (7)** from Alex's paired iPhone for `com.alexchandler.empires`. Source `4737471:project.yml` says **1.0 (8)**; this is not evidence of a Build 8 upload or phone installation. No upload occurred in Stage 4. Tester access was not rechecked; [Build 7 history](</Users/alex/Documents/Personal Projects/Settlers/docs/AI_summaries/2026-09-08-heuristic-delivery.md>) and [durable receipts](</Users/alex/Library/Application Support/EmpiresResearch/deliveries/heuristic-build7-20260908/README.md>) retain that earlier verification.

Personality starting context: [September 5 layer/voice audit](</Users/alex/Documents/Personal Projects/Settlers/docs/AI_summaries/2026-09-05-personality-trade-dialogue.md>) is historical, not a current spec. Its Boolean-only scorer and civilization strategy mapping claims predate current code. Agree a bounded Stage 5 scope; do not silently reopen roads, automated tuning or neural/search research.
