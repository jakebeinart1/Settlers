# Neural app integration — compatibility and release evidence

## Scope

Integrate the completed `gpu-baseline-20260906-r2` checkpoint into Empires
before starting new algorithm experiments. This is offline greedy neural play
with explicitly retained heuristic trading and compatibility fallbacks. It is
not AlphaBot search, expert-play certification, or an exact reproduction of
the upstream game inside the app.

The frozen upstream repository is `Eli6th/catan-rl` at
`021279c56834b6203480e5292e1de7246e47bd68`. Model digest, tensor format,
parent checkpoint and MIT notice live with the shipped resource in
`Packages/CatanAI/Sources/CatanAI/Resources/UpstreamPolicy/`.

## Acceptance gates

- The unchanged r2 model loads offline, once per app process. A failed load
  prevents replacing the current match; it does not masquerade as neural play.
- Every applied bot move belongs to the Swift rules engine's legal mask.
- Input slots and output arithmetic are checked against the original Rust
  implementation, not merely against a second copy of the Swift formulas.
- Discards, Road Building, Knight and robber choices resolve privately into
  complete legal Swift moves. No partial foreign action mutates the real board.
- Trade proposals and negotiations retain their existing heuristic behavior.
  An unavailable translation uses a recorded fallback reason.
- New games use the current neural profile. Existing checkpoint profiles and
  policy RNG cursors survive cold resume without adopting a different backend.
- Applied decisions carry their policy ID, selected move, route, fallback
  reason and any session override through the atomic checkpoint and export.
  `neural` identifies the neural route, including forced singleton masks which
  require no network call; it is not an inference-call counter.
- Supported three/four-seat games complete, remain responsive, save, resume,
  and expose the AI mode in the actual app. Compilation is not this gate.
- Review, full quality gate, native interaction and inspected screenshots
  precede a release claim. A simulator build is not a TestFlight delivery.

## Deliberate compatibility decisions

1. The existing 5,182-feature / 9,335-action Empires encoding remains intact.
   A separate adapter supplies the upstream 1,350 inputs / 299 action IDs.
2. Tile, vertex and edge slots use upstream geometry order. Unsupported or
   malformed topology is rejected before indexing, not inferred from counts.
3. The upstream road-length feature uses total roads below five. Empires'
   actual Longest Road rules remain unchanged. A Rust-generated fixture caught
   this discrepancy before integration was accepted.
4. During setup upstream keeps `current_player` at zero while separately
   advancing the placing actor. The model's turn-owner feature reproduces this
   convention. A live-context regression failed with 40 mismatched slots before
   the fix; the actual Swift turn owner was never changed.
5. Old saves have unknown completed-turn history. Missing history remains
   unknown rather than being invented from visible state. New games record
   completed turns and proposals; replay checks known context.
6. Full hands are available to the model, consistent with this checkpoint's
   perfect-information training and the explicitly allowed integration scope.

## Distribution differences that remain

- r2 was trained/evaluated in a fixed chair, four players, target seven, against
  its upstream opponents. Empires uses different opponent compositions and
  three/four-player targets eight/ten (and three-player twelve).
- Native port placement is encoded faithfully, but seven of the nine standard
  port edges differ from upstream's fixed topology. This is unseen placement,
  not a reason to falsify the observation or silently change the game board.
- Swift applies complete compound moves. Upstream can stop between individual
  subactions, including on reaching victory. The app's legal masks take priority.
- Trading and pre-roll development-card differences use the named hybrid
  boundary. They must not be presented as the reconstructed network's behavior.
- No search is included in this integration. Testing stronger search belongs
  to a later controlled experiment, against this frozen app-compatible baseline.

## Verification ledger

- Model: 9,300 outputs over 31 frozen vectors match Rust bit-for-bit; malformed
  artifact and concurrent prediction tests pass. Measured M5 Pro Release
  inference p95: 0.103 ms sparse / 0.267 ms dense. Not an iPhone measurement.
- Observations: every slot matches 39 Rust-generated three/four-seat positions;
  live setup parity, legacy-history rejection, malformed topology and stale
  robber bookkeeping tests pass.
- Engine provenance: single-evaluation RNG/commit, external-action isolation,
  and missing legacy trace tests pass.
- Full matches: 15/15 supported-configuration games completed (maximum 621
  actions). Two further processes reproduced all 15 outcomes and every
  non-timing field. Zero illegal choices, missing traces, unexpected fallbacks
  or action/time caps. Retained raw rows, source hashes and watchdog receipts:
  `evidence/neural-integration-20260906/`. Across 6,679 selections, 4,214 used
  the neural route and 2,465 the declared heuristic routes. Not a strength test.
- App persistence: a real neural bot placed its settlement and road through the
  production loop; both traces survived checkpoint reload and JSONL export.
  Legacy missing-trace decoding also passed (two hosted app tests).
- Visual: inspected New Game at 402pt and 375pt. The initial large AI notice
  displaced Turn Order; replaced it with a title-row info button. Both layouts
  now show every configuration row and pinned action without scrolling.
  A native iPhone SE UI test tapped the explanation, checked its contents,
  dismissed it and verified Turn Order / Start remain reachable. In-game
  settings at 402pt shows the actual saved policy mode and existing controls.
- Full quality gate and delivery remain pending; no release claim yet.

## Following work, in order

1. Finish and deliver this app-compatible integration, retaining the frozen
   original artifact and recording any compatibility fixes separately.
2. Extend evaluation to interchangeable named policies, paired seed/chair
   rotations, opponent pools, confidence intervals, completion rates, trade
   fallback rates, and latency. Keep functional gates separate from strength.
3. Profile environment rollout, transfer, inference and optimization; improve
   the measured bottleneck under equal training/evaluation budgets. Use the
   existing bounded-run watchdog and heartbeat for every GPU experiment.
4. Pre-register individual experiments: broader opponent/chair training,
   match-rule distribution alignment, search budget, trade policy, and road
   planning/reward changes. These are hypotheses, not promised improvements.
   Keep each arm's checkpoints, seeds, costs, failures and decision rationale.
5. Add character expression after strategy has a reliable baseline; do not
   entangle chat with policy decisions in this integration.
