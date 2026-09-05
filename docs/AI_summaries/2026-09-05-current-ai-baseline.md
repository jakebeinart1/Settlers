# Empires current AI baseline

**Audit date:** 2026-09-05

**Branch:** `codex/ai-strategy-discovery`

**Committed source snapshot:** `6ec560df96d0617b39359a20fbf628814e043a30`

**Scope:** current Empires implementation and retained measurements only. This memo does not select or recommend an AI algorithm.

Concurrent work added comment-only count corrections and other research memos to the shared working tree during this audit. Those changes do not alter the behavior audited here. This auditor edited only this memo.

## Evidence labels

- **RUN** — executed against the source snapshot during this audit.
- **MEASURED** — a quantitative result retained in the repository with its protocol and provenance; not rerun during this audit unless also marked RUN.
- **IMPLEMENTED** — present in source, tests, or checked-in tooling at the audited snapshot; this is not itself a quality or strength claim.
- **NOT IMPLEMENTED** — absent from the current product/runtime, or an experiment explicitly removed after failing its gate.

Current source and executable tests outrank older comments. Historical numbers below are reported only when the repository preserves the protocol and result. Generated datasets and model artifacts are not in git, so their retained checksums and summaries are provenance records rather than independently re-opened artifacts.

## Executive baseline

| Area | Status | What exists at this snapshot |
| --- | --- | --- |
| Shipping opponent | **IMPLEMENTED** | One deterministic, legal-move-constrained heuristic policy with three style presets. Every app bot is a `HeuristicPolicy`; no other policy ships. |
| Decision loop | **IMPLEMENTED / RUN** | App, tests, and headless simulator use the same `GameSession`; policy RNG and queued trade replies survive checkpoints. |
| State contract | **IMPLEMENTED / RUN** | `GameObservation` plus a versioned 5,182-float numeric encoding and compact text rendering. |
| Action contract | **IMPLEMENTED / RUN** | Action layout v2; fixed four-chair training head of 9,335 indices; invertible mapping and legal mask. |
| Information model | **IMPLEMENTED** | The live policy receives full `GameState`, including private state. An optional public-counts mask exists for exported/text/numeric encodings, but it is not enforced at the live policy seam. |
| Planning | **IMPLEMENTED** | Hand-authored setup, build, road, robber, discard, development-card, threat, and trade heuristics; no tree search or learned planner ships. |
| Personality | **IMPLEMENTED / MEASURED** | Balanced, Aggressive, and Cautious alter three style dials. Two behavioral separations have been measured; strength intervals overlap. |
| Dialogue | **IMPLEMENTED** | Deterministic, civilization-specific canned trade pitches and accept/reject lines. Dialogue is cosmetic and cannot alter a decision. |
| Simulation/evaluation | **IMPLEMENTED / RUN** | Deterministic Release-capable self-play, strict configuration/provenance output, behavior counters, paired chair-rotated analysis, and training JSONL validation. |
| Learned/search/LLM runtime | **NOT IMPLEMENTED** | No trained checkpoint is loaded by the app or simulator; no search, RL, or LLM policy is present at HEAD. Prior small prototypes were measured, rejected, and removed. |
| Difficulty levels | **NOT IMPLEMENTED** | No calibrated Easy/Standard/Hard ladder and no difficulty control. Personality is explicitly not difficulty. |

## 1. Runtime decision flow

### The common loop

**IMPLEMENTED.** `GameObservation` contains the acting seat, a complete `GameState`, and the exact seat-scoped legal moves. `Policy` exposes one stable ID and one deterministic decision method with injected randomness (`Packages/CatanEngine/Sources/CatanEngine/GameSession.swift:23-53`). `GameSession` is deliberately the one loop shared by the app and simulator (`GameSession.swift:55-77`):

1. `nextActor()` resolves the phase, including deterministic ordering of simultaneous discards, and stops at a human/external seat (`GameSession.swift:221-264`).
2. `decideNextDetailed()` asks `RulesEngine.legalMoves(for:seat:)`, removes trade proposals that would violate the per-turn retry/pending-offer gate, constructs the observation, calls the seat's policy, and traps if the selected move is outside the supplied legal list (`GameSession.swift:279-310`).
3. `commit` is the sole policy-move application path. It delegates to the rules engine, records turn bookkeeping, and queues an out-of-turn bot response when the move is a proposal (`GameSession.swift:313-325`). Human moves use the corresponding `applyExternal` path (`GameSession.swift:334-345`).
4. A main turn is forcibly ended after 25 actions as a runaway backstop, not as a Catan rule (`GameSession.swift:98-105,303-306`).

**IMPLEMENTED.** Trade responses are part of this loop rather than a simulator-only special case. A bot proposal asks eligible policy-controlled responders in stable seat order until one accepts; an external responder leaves the offer pending for the UI (`GameSession.swift:391-470`). A decision record retains the exact observation/mask presented to every responding policy, not only the eventual committed response (`GameSession.swift:79-88,211-219`).

**IMPLEMENTED.** Engine randomness is held in `GameState.rng`; policy tie-break randomness is separate in `GameSession.policyRNG` (`GameSession.swift:75-77`; `Packages/CatanEngine/Sources/CatanEngine/Models/GameState.swift:31-35`). A session checkpoint persists the complete game state, policy IDs, policy RNG, evaluation counter, queued trade response, and per-turn action count, and rejects a different policy roster on restore (`GameSession.swift:114-199`).

### What the app actually instantiates

**IMPLEMENTED.** The running app converts each persisted opponent profile into `HeuristicPolicy(personality:id:)`; `GameViewModel.makePolicies` contains no alternate search, learned, or LLM branch (`Settlers/ViewModels/GameViewModel.swift:1037-1051`). `HeuristicPolicy` is a thin adapter over `Bot.decide` and passes the observation's legal list and session RNG through unchanged (`Packages/CatanAI/Sources/CatanAI/HeuristicPolicy.swift:3-30`).

**IMPLEMENTED.** `RulesEngine` remains the legality and transition authority. It enumerates phase-specific moves—including all concrete development-card choices and trade responses—and applies those moves to state (`Packages/CatanEngine/Sources/CatanEngine/RulesEngine.swift:7-103,179-207,217-406,487-516`). The policy scores choices; it does not implement a second ruleset.

## 2. Observation and state contracts

### Raw observation

**IMPLEMENTED.** The policy-facing contract is intentionally algorithm-neutral, but it is not information-safe: `GameObservation.state` is the full value (`GameSession.swift:10-17,23-36`). That state includes all players, the ordered development-card deck, pending offers, private development-card identities, per-turn history, and both engine and board state (`Packages/CatanEngine/Sources/CatanEngine/Models/GameState.swift:1-80`).

### Numeric encoding

**IMPLEMENTED / RUN.** `StateEncoding.layoutVersion == 3`. Its vector is fixed at **5,182 finite values in `0...1`**:

- 3,881 global slots: phase, roll, bank, deck count, offer count, VP target, observer chair, table size, **3,840 slots for 256 exact offer rows**, and robber location;
- four 31-slot seat blocks: holdings, standing, and ports;
- 19 × 7 tile slots;
- 54 × 14 vertex ownership/port slots;
- 72 × 4 edge-ownership slots.

The decomposition is executable source, not an estimate (`Packages/CatanEngine/Sources/CatanEngine/StateEncoding.swift:145-217,480-531`). Three-player positions retain the four-seat shape by zero-padding the absent chair (`StateEncoding.swift:399-409,514-523`). Canonical sorted tile/vertex/edge indices are shared with `ActionSpace` (`StateEncoding.swift:300-341`).

**IMPLEMENTED.** Layout v3 explicitly carries the observer's absolute chair, table size, each pending offer's proposer/give/want terms, and static shoreline port topology. This resolves the previously contradictory inputs where an absolute victim action or offer slot could not be interpreted from the encoded state (`StateEncoding.swift:157-176,536-568,676-721`).

**IMPLEMENTED.** The encoder deliberately omits the engine RNG, development-deck contents, save schema, and transient robber-mover bookkeeping (`StateEncoding.swift:17-26`). That omission applies to the encoded vector/text only; those fields remain reachable through the raw `GameObservation.state` contract.

### Text encoding

**IMPLEMENTED / RUN.** `promptDescription` describes the same layout in compact text, including the observer, phase, target, bank, seats, board, offers, and every legal move (`StateEncoding.swift:759-807,844-929`). Its action numbers are **local positions in the current observation's `legalMoves`**, not global `ActionSpace` IDs (`StateEncoding.swift:28-44,909-929`).

**RUN.** The current state-encoding test sampled setup through late-game states and measured a worst observed compact-text/JSON size ratio of **4.8×**: 4,622 prompt characters (about 1,155 rough tokens) for 152 legal moves versus 22,149 JSON characters. The test's acceptance bar is only `>4×`, not a general token-cost guarantee (`Packages/CatanEngine/Tests/CatanEngineTests/StateEncodingTests.swift:515-557`; audit run described in section 9).

## 3. Action space

**IMPLEMENTED / RUN.** The current global four-chair action head is **9,335 indices**, `ActionSpace.layoutVersion == 2`. The source constructor defines these ordered segments: setup settlement/road; roll; normal road/settlement/city/dev-card purchase; Knight; ordered Road Building pairs; Year of Plenty; Monopoly; robber moves; discard multisets; bank trade; player-trade proposal; indexed trade response; end turn (`Packages/CatanEngine/Sources/CatanEngine/ActionSpace.swift:61-155`). The independently recomputed test pins 9,335 and requires a layout-version decision if it changes (`Packages/CatanEngine/Tests/CatanEngineTests/ActionSpaceTests.swift:17-36`).

The largest segments are 5,112 ordered Road Building edge pairs and 3,002 discard multisets—8,114 indices, or 86.9% of the current head. The remaining 1,221 indices encode every other move class. This is a description of the current flat representation, not an argument for or against it.

**IMPLEMENTED / RUN.** `index(of:)` and `move(at:)` are inverses; `mask(for:)` produces a full-width Boolean legal mask and traps rather than silently dropping a legal but unrepresentable move (`ActionSpace.swift:163-280`). Current explicit capacity limits are a 10-card discard and 256 pending offers (`ActionSpace.swift:70-92`). Trade proposals encode one give resource × one different wanted resource × give quantity 1–3 × wanted quantity 1–2, or 120 proposal slots (`ActionSpace.swift:127-145`; `RulesEngine.swift:153-177`).

**IMPLEMENTED.** The generic `ActionSpace` constructor can size robber-victim segments to a supplied player count, but training records always instantiate it with the fixed four-chair count. Thus both supported three- and four-player datasets use the same 9,335-wide head and mask absent-chair victim actions (`Packages/CatanAI/Sources/CatanAI/TrainingExample.swift:41-90`).

## 4. Information exposure

**IMPLEMENTED.** Two encoder policies exist:

- `.revealAll` exposes exact resource and development-card identities for every seat and is the default.
- `.publicCountsOnly` preserves the observer's exact cards and each opponent's public total resource/dev-card counts while zeroing only the opponents' per-kind resource and dev-card slots. Vector width is unchanged.

The choke point and public/private split are explicit in `StateEncoding` (`StateEncoding.swift:219-298,589-615`). The simulator can export either mode, defaulting to reveal-all (`Packages/CatanAI/Sources/sim/main.swift:137-175,260-268`).

**IMPLEMENTED, but not enforced in live play.** The optional mask is applied while creating `TrainingExample.features`; it does not replace or sanitize `GameObservation.state` before a shipping heuristic runs (`TrainingExample.swift:73-90`; `GameSession.swift:10-17`). Therefore a public-counts dataset is possible, but a public-counts shipping bot is not presently guaranteed by the interface.

**IMPLEMENTED current hidden-information reads.** This is more than theoretical exposure:

- `ThreatAssessment` uses `state.victoryPoints(for:)`, which includes hidden VP cards, and the exact number of held development cards (`Packages/CatanAI/Sources/CatanAI/ThreatAssessment.swift:12-27`; distinction at `GameState.swift:189-215`).
- Monopoly targeting sums exact opponent resource quantities by kind (`Packages/CatanAI/Sources/CatanAI/DevCardHeuristics.swift:227-242`).
- Trade evaluation simulates whether the proposer can immediately afford a settlement or city using the proposer's exact hand (`Packages/CatanAI/Sources/CatanAI/TradeHeuristics.swift:119-149`).

The current heuristics inspect only the development deck's size in their documented purchase/late-army decisions, but the full ordered deck and RNG are still exposed by the raw observation. “Not currently read” is not the same as “not observable.”

## 5. Shipping heuristic modules

### Top-level chooser

**IMPLEMENTED.** `Bot` is a phase dispatcher constrained to the supplied legal list (`Packages/CatanAI/Sources/CatanAI/Bot.swift:42-84`):

- setup settlement and initial-road choices use `PlacementHeuristics` (`Bot.swift:87-132`);
- roll phase normally rolls unless the supplied mask contains only another legal choice (`Bot.swift:61-63`);
- discard sheds redundant resources from a legal exact-size combination (`Bot.swift:150-195`);
- robber intent comes from `RobberHeuristics`, then is reconciled with eligible legal victims (`Bot.swift:197-228`);
- main-turn trade responses, development-card use, builds, purchases, bank trades, proposals, and rejection cleanup compete in an explicit priority/score flow (`Bot.swift:231-353`).

**IMPLEMENTED.** `BotWeights` centralizes the heuristic tuning constants as a serializable value rather than scattered literals; default values reproduce the extracted policy (`Packages/CatanAI/Sources/CatanAI/BotWeights.swift:1-34,484-491`). The simulator CLI does not accept an alternate weight file or overrides, so comparing weight sets currently requires source-level construction rather than selecting two configurations in one frozen executable.

### Setup, threat, robber, and development cards

**IMPLEMENTED.** Initial settlements score pip production, resource diversity, port value, and second-placement complementarity; initial roads point toward the higher-scoring endpoint (`Packages/CatanAI/Sources/CatanAI/PlacementHeuristics.swift:3-56`; `Bot.swift:89-132`).

**IMPLEMENTED.** `ThreatAssessment` combines total VP, production, development-card count, and proximity to Longest Road/Largest Army, then normalizes a target relative to the opponent field. Build blocking, robber targeting, trade caution, and Monopoly all share this model (`ThreatAssessment.swift:3-26,56-122`).

**IMPLEMENTED.** Robber placement avoids the bot's own production where possible, scores city/settlement disruption weighted by opponent threat and aggressiveness, and selects the highest-threat eligible occupant with hand size as fallback (`Packages/CatanAI/Sources/CatanAI/RobberHeuristics.swift:3-86`).

**IMPLEMENTED.** Development-card logic:

- buys when affordable and the deck is nonempty, with the top-level build score deciding whether that purchase wins;
- plays Knight to remove self-blocking, claim/pursue Largest Army, or apply aggressive pressure;
- plays Road Building and chooses its two edges sequentially using the normal road scorer;
- plays Year of Plenty when one or two missing units complete the nearest build target;
- plays Monopoly against a sufficiently large threat-weighted exact opponent stash.

Source: `Packages/CatanAI/Sources/CatanAI/DevCardHeuristics.swift:20-138,141-242`.

## 6. Trade proposal and acceptance

### Legal proposal surface

**IMPLEMENTED.** During a main turn, the engine can enumerate at most 120 one-resource-type-for-one-resource-type proposals. Give quantity is 1–3, want quantity is 1–2, and the proposer must hold more than the offered amount so ordinary enumeration retains at least one card (`RulesEngine.swift:106-177`). A turn records declined offers, permits at most three declined proposals, and clears proposal/acceptance history plus pending offers at end turn (`RulesEngine.swift:134-151,381-396`; `GameState.swift:66-80`).

### Acceptance

**IMPLEMENTED.** `TradeHeuristics.evaluate` computes marginal resource values against the receiver's nearest build targets and accepts only when net gain exceeds a threshold adjusted by trade willingness, proposer threat, receiver standing, prior accepted deals that turn, and whether the trade immediately unlocks a settlement/city for the proposer (`TradeHeuristics.swift:3-55,57-149`). This is deterministic weighted arithmetic; there is no negotiation model, belief state, learned valuation, or language-model judgment.

**IMPLEMENTED.** Affordability is enforced outside the valuation function. `GameSession` includes accept only when both sides can honor the offer (`GameSession.swift:391-470`). The app's human-to-bot path separately checks the responding bot's hand before calling the same evaluator, then records all bots' reactions and the first accepter (`Settlers/ViewModels/GameViewModel.swift:812-868`). Resume reconstructs this presentation decision from the persisted pending offer (`GameViewModel.swift:871-885`).

### Proposal generation

**IMPLEMENTED.** `proposeTrades` identifies the nearest blocked target, asks for its largest missing resource (up to two cards), ranks genuinely surplus give resources, skips pending/previously declined terms, and returns at most one candidate per call. After an ordinary rejection it may retry another candidate and, for a near settlement/city only, escalate up to a bound better than the bot's own bank/port rate. It stops after three declines (`TradeHeuristics.swift:151-316`). A separate fallback selects a legal bank/port conversion toward the nearest build (`TradeHeuristics.swift:318-400`).

**MEASURED.** When trade quantities first widened to two per side, a 15-game audit changed proposal shape from 1,110 one-for-one offers only to 761 one-for-one, 342 two-for-one, and a handful of other lopsided offers; the contemporaneous random-floor check remained 40/40. This is a historical shape/safety measurement, not current human-satisfaction evidence (`Packages/CatanAI/Tests/CatanAITests/SeededGameFingerprintTests.swift:41-47`). The later give-three “generous unlock” path is scenario-tested, including a plausible receiver accepting it, but has no retained post-change strength result (`Packages/CatanAI/Tests/CatanAITests/TradeHeuristicsTests.swift:412-465`; commits `b3d7a62`, `ea7036c`).

## 7. Road and placement planning

**IMPLEMENTED.** Paid road choices use one-ply hand-authored scoring, not a search tree. `BuildPlanner` scores all currently legal builds and randomly breaks near ties through the injected policy RNG (`Packages/CatanAI/Sources/CatanAI/BuildPlanner.swift:3-38`). Road terms currently include:

- best newly reachable legal settlement value;
- denying an opponent frontier;
- immediately claiming Longest Road;
- pursuing or defending Longest Road;
- bridging two disconnected pieces of the bot's road network;
- reducing distance to a recomputed expansion target up to four hops away;
- continuity with roads already invested toward that target.

Source: `BuildPlanner.swift:45-149,151-287,289-420,422-575`.

**IMPLEMENTED.** Road Building uses the same scorer for the first edge, simulates that edge, then selects the second from the resulting legal network (`DevCardHeuristics.swift:180-225`).

**MEASURED.** The rationale retained beside the current code records two diagnosis datasets: roughly 19% of road builds in an earlier simulation opened no new territory/claim/block (`BuildPlanner.swift:151-174`), and a later 90-game audit found 53 fragmented player-networks; a played 12-point game also showed 3 branch junctions and 8–9 dead tips across 13 roads per bot (`Packages/CatanAI/Tests/CatanAITests/SeededGameFingerprintTests.swift:68-76,105-117`). Commits `902415f` and `96cce12` added continuity, fragment bridging, and Road Building use. The current scenario tests exercise each scoring term, but there is **no retained frozen-anchor strength or human-quality measurement after `96cce12`**.

**NOT IMPLEMENTED.** There is no persisted strategic objective, route reservation across turns, adversarial lookahead, probabilistic rollout, learned value, or explicit multi-turn plan. “Expansion target continuity” is a score bonus derived afresh from current state, not a durable plan object (`BuildPlanner.swift:289-420`).

## 8. Personalities, opponent identity, and messages

### Strategic personality

**IMPLEMENTED.** There are exactly three `BotPersonality` dials:

| Preset | Aggressiveness | Trade willingness | Expansion bias |
| --- | ---: | ---: | ---: |
| Balanced | 0.50 | 0.50 | 0.50 |
| Aggressive | 0.90 | 0.20 | 0.75 |
| Cautious | 0.15 | 0.80 | 0.30 |

These values affect robber/Knight behavior, trade thresholds/proposal priority, and settlement-versus-city/build priorities (`Packages/CatanAI/Sources/CatanAI/BotPersonality.swift:1-31`). They share the same underlying `BotWeights.default`; they are style presets, not separately trained policies.

**IMPLEMENTED.** The app persists stable opponent profiles that compose civilization, general name, strategy, and trade-dialogue voice. Eight explicit profiles map civilizations to one of the three strategies, with no difficulty field (`Settlers/Models/OpponentProfile.swift:4-65`). Realized profiles are restored as a unit and are the authority for both identity and strategy (`Settlers/ViewModels/GameViewModel+OpponentProfiles.swift:4-105`).

### What has been measured about personality

**MEASURED.** A held-out, fully chair-rotated program of 960 decisive games—480 for behavior and 480 for frozen-anchor strength—found two behavioral separations:

- Aggressive chose a Knight in 42.3% of playable-Knight opportunities versus Balanced's 15.4%, a +26.9-point difference with 95% cluster interval +24.4 to +29.5.
- Cautious proposed a player trade in 63.0% of proposal opportunities versus Balanced's 39.9%, a +23.1-point difference with interval +21.5 to +24.7.

Trade acceptance (Balanced 47.9%, Aggressive 46.6%, Cautious 48.0%) and highest-public-VP robber targeting did not meaningfully separate (`docs/AI_summaries/2026-09-02-personality-separation-results.md:28-74`).

**MEASURED.** Against three frozen Greedy anchors over 160 games per preset, Balanced won 83.1%, Aggressive 81.9%, and Cautious 81.2%; their seed-cluster confidence intervals overlap, so the retained result does not rank their strength (`personality-separation-results.md:65-74`). An additional consolidation metric found Cautious selected a buildable city 99.5% of the time versus Balanced's 93.0%, +6.5 points with 95% interval +3.1 to +10.3 (`docs/AI_summaries/2026-09-02-consolidation-metric-results.md:25-63`).

**NOT IMPLEMENTED.** No blinded human-recognition study demonstrates that players can reliably identify the personalities from play alone; the result memo explicitly keeps that requirement open (`personality-separation-results.md:87-98`).

### Messages and chat behavior

**IMPLEMENTED.** Trade dialogue is deterministic flavor text selected from civilization-specific pitch/accept/reject pools. It is capped at 38 characters and keyed by offer ID, and the source explicitly states that it never affects `TradeHeuristics.evaluate` (`Packages/CatanAI/Sources/CatanAI/TradeMessages.swift:4-58,60-94`). Tests require a substantial unique pool for every empire and disjoint acceptance/rejection text (`Packages/CatanAI/Tests/CatanAITests/TradeMessagesTests.swift:6-81`).

**NOT IMPLEMENTED.** There is no free-form chat, LLM-generated dialogue, dialogue memory, conversational negotiation, or path from words back into policy decisions. Non-trade event reactions—being blocked, losing Longest Road, or reacting to settlements/cities—remain open in `TODO.md:70-77`.

## 9. Simulator, export, and evaluation system

### Headless simulator

**IMPLEMENTED.** The `sim` executable supports:

- 3 or 4 players;
- 8, 10, or 12 victory points;
- standard or seeded-random boards;
- any explicit seat roster from Balanced, Aggressive, Cautious, Greedy, and Random;
- a build/provenance ID;
- human-readable or schema-v5 JSONL game results;
- optional versioned training JSONL under reveal-all or public-counts information.

The CLI rejects unknown policies and malformed/mixed configuration rather than falling back (`Packages/CatanAI/Sources/sim/main.swift:49-71,119-198,200-292`). Every game uses the real `GameSession`, records a canonical move fingerprint, every policy evaluation, and per-seat behavior metrics, then stops at game over or 3,000 moves (`main.swift:350-431`). Game JSON carries the configuration, policy IDs, seed, move count, winner, final VP, fingerprint, and behavior counters (`main.swift:448-499`).

**IMPLEMENTED, not RUN in this audit.** A package integration test drives two seeds through every 3/4-player × 8/10/12-VP × standard/randomized-board cell—24 games total—and requires a legal winner below the 3,000-move cap (`Packages/CatanAI/Tests/CatanAITests/ConfigurationMatrixGameplayTests.swift:8-83`).

**IMPLEMENTED.** `PolicyBehaviorMetrics` currently records 27 event/opportunity counters, including build choices, proposal/response rates, proposal quantities, Knight opportunities, and differentiated robber targets. Opportunity denominators are computed from the exact legal list shown to the policy (`Packages/CatanAI/Sources/CatanAI/PolicyBehaviorMetrics.swift:4-151`).

### Training export and lower-bound trainer

**IMPLEMENTED / RUN.** `TrainingExample` schema v2 records build ID, state/action layout versions, action count, seed, contiguous evaluation index, observer/winner, match configuration, policy ID, information policy, 5,182 features, sparse legal action indices, chosen global action, and observer-relative ±1 outcome (`Packages/CatanAI/Sources/CatanAI/TrainingExample.swift:12-118`). Export refuses to overwrite, writes to a temporary sibling, requires a decisive game and complete policy-evaluation capture, then atomically publishes (`Packages/CatanAI/Sources/sim/main.swift:508-576`).

**IMPLEMENTED / RUN.** The Python validator pins schema 2, state layout 3, action layout 2, 5,182 features, 9,335 actions, 3/4 players, 8/10/12 VP, both board modes, and both information policies. It rejects duplicate JSON keys, non-finite/out-of-range features, malformed masks, a chosen action outside the mask, wrong outcomes, duplicate decisions, and non-contiguous trajectories (`scripts/validate-training-data.py:1-27,45-120,123-175`).

**IMPLEMENTED, not shipped.** `train-policy-baseline.py` is a dependency-free offline plumbing baseline: a phase-conditioned action-frequency policy behind the legal mask plus a linear value regressor. It splits by whole seed, writes a versioned/provenanced checkpoint, and can reload it for prediction (`scripts/train-policy-baseline.py:1-24,54-91,98-174,177-211`). No app or simulator policy loads this checkpoint.

### Evaluation discipline

**IMPLEMENTED.** The analyzer requires one configuration and exact chair shards, reports decisive rate separately, excludes timeouts from the win-rate denominator, bootstraps whole seed/config clusters, and can compare paired candidate/baseline arms only when seed/chair/config keys match (`scripts/analyze-bot-evaluation.py:92-173,218-261,280-447,450-490,505-652`). The `bot-strength` workflow additionally requires a frozen binary/anchor, held-out seeds, every-chair rotation, and table-size-aware nulls (`.claude/skills/bot-strength/SKILL.md:1-375`).

### Audit RUN results at `6ec560d`

These were short contract checks, not new strength experiments:

1. **RUN:** `swift test --package-path Packages/CatanEngine --filter 'ActionSpaceTests|StateEncodingTests|SessionCheckpointTests'` — 40 Swift Testing tests passed. This exercised all 9,335 action round trips, legal-mask completeness over seeded walks, 5,182-feature shape/range/egocentric/hidden-info contracts, prompt rendering, and checkpoint RNG/trade-response restoration.
2. **RUN:** `swift test --package-path Packages/CatanAI --filter 'TrainingExampleTests|TradeHeuristicsTests|BuildPlannerTests|TradeMessagesTests|PolicyBehaviorMetricsTests'` — 58 tests passed. Compilation emitted two existing warnings in `DiscardRaceRegressionTests.swift` for ignored `try?` results; the selected tests themselves passed.
3. **RUN:** `scripts/verify-training-export.sh` — built Release `sim`, played the same 3-player/8-VP standard-board seed in two separate processes, byte-compared both game streams and both training streams, and validated **378 examples across one seed** (`scripts/verify-training-export.sh:1-32`).
4. **RUN:** `swift test --package-path Packages/CatanAI --filter SelfPlayReproducibility` — both serialized tests passed. The five current pinned fingerprints are seed 1 `7964368a77394abc`, 42 `77f1cbe943477e18`, 7 `e985537b0fe9ca79`, 1234 `e0be15d59b7df4c3`, and 99 `deddbc538f909be8` (`Packages/CatanAI/Tests/CatanAITests/SeededGameFingerprintTests.swift:136-142,189-251`).

No long simulation, full configuration matrix, full quality gate, simulator UI run, or device run was performed for this memo.

## 10. Retained quantitative baseline and failed experiments

### Strength anchors

**MEASURED.** `RandomPolicy` is the legal-uniform floor; `GreedyPolicy` is the middle anchor. Greedy follows a simple category ladder, never proposes or accepts player trades, and deliberately takes the first legal road with no positional reasoning (`Packages/CatanAI/Sources/CatanAI/HeuristicPolicy.swift:33-54`; `Packages/CatanAI/Sources/CatanAI/GreedyPolicy.swift:1-35,156-165`). Historical 40-game arms retained beside the tests were: Greedy 55.0% against three Random, shipping heuristic 90.0% against three Greedy, shipping heuristic 100% against three Random, and Random 7.5% against three Greedy. Those exact 40-game measurements are documentation; the routine tests now use smaller regression samples (`Packages/CatanAI/Tests/CatanAITests/PolicyTests.swift:131-176`).

**MEASURED.** The more rigorous initial personality baseline used randomized boards, deterministic policy RNG, 40 held-out seeds × four chair rotations per preset, decisive-only rates, and seed-cluster bootstrap intervals. It found 84.4% Balanced, 85.0% Aggressive, and 81.2% Cautious against Greedy, with all intervals overlapping (`docs/AI_summaries/2026-09-02-ai-baseline-and-personality-audit.md:28-44,57-70`). Later personality changes retained separation while producing the overlapping 83.1/81.9/81.2 result above.

### Search and learned prototypes

**MEASURED / NOT IMPLEMENTED.** A reduced one-rollout, two-action-horizon, three-candidate search took 349.8–481.2 ms p95 over 5,470 decisions in 40 complete games, then won 24/40 against Greedy versus 35/40 for the shipping heuristic on paired seeds. The paired difference was −27.5 points, 95% interval −42.5 to −12.5. Its implementation was removed. A larger debug-only budget measured 1,038 ms p95 and 4,025 ms max over 432 decisions but received no strength evaluation (`docs/AI_summaries/2026-09-03-ai-approach-evaluation.md:123-158`).

**MEASURED / NOT IMPLEMENTED.** A 20-game deterministic teacher corpus contained 11,687 examples. The retained phase-conditioned masked prior reached 31.5% top-1 imitation versus 14.1% uniform-legal expectation with zero illegal picks. Its linear value model improved MAE from 0.773 to 0.626 but had 69.8% sign accuracy versus a 74.0% majority comparator, so it was not fit to guide search (`ai-approach-evaluation.md:215-258`). The script remains as plumbing; no checkpoint is deployed.

**MEASURED / NOT IMPLEMENTED.** A small state-conditioned projection improved top-1 imitation to 42.4% with calibration error 0.061, but went 0/40 against Greedy and nearly stopped playing Knights/building permanent pieces. It was rejected and removed (`ai-approach-evaluation.md:259-284`).

### Difficulty attempts

**MEASURED / NOT IMPLEMENTED.** A locked 3,360-game anchor-calibration run found Balanced stronger than Greedy in every cell but failed its declared gate: 31 games timed out at 3,000 moves and 3-player/standard/10-VP missed the required 20-point margin. Greedy was rejected as a player-facing Easy tier (`ai-approach-evaluation.md:286-400`).

**MEASURED / NOT IMPLEMENTED.** A personality-preserving Easy prototype was then measured over 3,024 games (3,022 decisive). It preserved the intended personality axes and was weaker than Standard, but failed its Random floor in three four-player cells and its 12-point completion ceiling. The runtime and tests were removed without consuming the held-out seed bank (`ai-approach-evaluation.md:402-433`).

## 11. Known gaps at this snapshot

1. **NOT IMPLEMENTED — algorithm selection.** The backlog still leaves heuristic/search, RL/self-play, LLM, and hybrid comparison open; no current code or retained result chooses among them (`TODO.md:49-54`).
2. **NOT IMPLEMENTED — calibrated difficulty.** There is one shipping strength policy with three style presets, not multiple measured strength tiers (`TODO.md:49-51`; `OpponentProfile.swift:29-32`).
3. **NOT IMPLEMENTED — enforced imperfect information.** A public-counts encoder exists, but every live policy receives full state and current heuristics consume hidden facts.
4. **NOT IMPLEMENTED — deployed learned/search/LLM inference.** There is no model artifact loader, on-device inference path, latency/fallback policy, search policy, RL checkpoint, or LLM call in the runtime.
5. **NOT IMPLEMENTED — trained value suitable for planning.** Both retained value screens failed their sign comparator; no value estimator is accepted for search.
6. **NOT IMPLEMENTED — long-horizon road strategy.** The road policy is increasingly structured but remains a one-move score over recomputed targets. Its latest continuity/fragment changes have scenario coverage and diagnostic history, not a post-change strength or player-quality result.
7. **NOT IMPLEMENTED — validated human trade quality.** Acceptance/proposal rules are extensively scenario-tested, but the measured personality acceptance rates are nearly identical and no retained human-offer corpus establishes whether the bots accept/reject at satisfying rates.
8. **NOT IMPLEMENTED — recognizable complete personalities.** Two axes separate statistically; blinded player recognition, broader style separation, and strength-equivalent profile calibration remain absent.
9. **NOT IMPLEMENTED — interactive character chat.** Existing lines are canned, trade-only, deterministic, and causally disconnected from play.
10. **IMPLEMENTED limitation — bounded flat representations.** The global head cannot encode discards over ten cards or responses beyond offer slot 255; the mask fails loudly if live rules cross either cap. Road Building and discards occupy 86.9% of the head.
11. **IMPLEMENTED limitation — outcome target.** Training examples use terminal ±1 win/loss only; there are no dense rewards, rankings, score margins, counterfactual targets, search targets, or uncertainty labels (`TrainingExample.swift:37-39,90`).
12. **IMPLEMENTED limitation — simulator/product boundary.** The harness is all-policy headless play. It validates rules/policy execution, not human UI comprehension, fun, or real-device behavior.

## 12. Contract reconciliation and remaining documentation drift

These are audit findings only; this memo intentionally changes no source or workflow file.

- **IMPLEMENTED truth: 9,335 actions and 5,182 state features.** The give-side trade ceiling widened the action head. Older comments cited 9,295 or 8,815; comment-only corrections were applied concurrently to `ActionSpace.swift`, `StateEncoding.swift`, and the earlier approach memo while this audit was running. Current source/tests and `scripts/validate-training-data.py:12-20` now agree on **9,335 / action layout v2**. State layout v3 remains **5,182**, of which 3,840 slots are the 256 pending-offer rows (`StateEncoding.swift:163-217`).
- **IMPLEMENTED truth: current fingerprints listed in section 9.** At the audited snapshot, `Packages/CatanAI/Sources/sim/main.swift:33-42` advertised an older seed-1 fingerprint (`46a24e9ecfe0feb8`). Concurrent documentation-only work removed that duplicate literal; the current serialized source test remains the authority and pins `7964368a77394abc` after the 2026-09-04 road/dev-card changes.
- **IMPLEMENTED truth: behavior telemetry exists.** At the audited snapshot, `.claude/skills/sim-harness/SKILL.md` described game output as coarse and lacking trade counts, while schema-v5 output already included 27 per-seat behavior counters (`main.swift:448-499`; `PolicyBehaviorMetrics.swift:9-37`). Concurrent documentation-only work corrected the skill while retaining the genuine trace-level gaps.
- **IMPLEMENTED truth: 9,335-wide training head.** The skill's stale 9,295 claim was corrected concurrently. The validator and current contract tests are the authority and reject that width.

## Bottom line

**IMPLEMENTED:** Empires already has the difficult plumbing required to compare future policies honestly: one app/simulator decision loop, deterministic and checkpointed randomness, legal seat-scoped action masks, a versioned numeric/text state contract, an invertible global action contract, strict training export validation, behavioral telemetry, and paired chair-rotated evaluation tools. The shipping behavior is a substantial hand-authored heuristic, not random “vibe code.”

**MEASURED:** It is clearly above Random and Greedy in the retained evaluations, two personality axes separate statistically, and the current data/export contracts pass live short checks. Several attempted search/learned/difficulty candidates were measured and rejected rather than left dormant.

**NOT IMPLEMENTED:** The repository has not selected an algorithm family, calibrated difficulty tiers, enforced hidden information for live agents, deployed a learned/search/LLM policy, proven the latest road changes stronger, validated trade behavior with humans, or built interactive character chat. Those unknowns remain unknown; this memo does not convert them into a recommendation.
