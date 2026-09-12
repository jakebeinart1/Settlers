# Stage 5 — recognizable opponents without reopening AI research

September 12, 2026. **Product proposal and source audit, not implemented behavior.**
Baseline inspected: `3c4fed9`, including Expanded mode and its opening-economy
and persistence fixes. Retain Balanced, the existing rule-based bot. The
[Stage 4 handoff](2026-09-09-heuristic-handoff.md) remains the research restart
map; its results concern its frozen Classic baseline, not every later version.

## Outcome and boundaries

An opponent should be recognizable from its choices and its voice, remember
relevant events within a match, and feel entertaining without becoming an
obstacle to playing. A boast must not invent a success; a grudge must not mean
permanent, irrational targeting. No runtime LLM, free-form chat, neural/search
work, automatic weight tuning, new difficulty levels, or general road-planning
rewrite is part of this stage.

Separate two independently testable changes: **behavior** chooses the move;
**expression** describes an actual decision or event. Muting or changing phrases
must never change moves, game randomness, offer deadlines or saved identities.
We can add playful departures from strict optimization, but must measure and
disclose their cost rather than label every personality equally strong.

## What exists, checked against source

| Existing piece | Reuse and missing work |
| --- | --- |
| `OpponentProfile.catalog` | Eight named generals with civilization/voice and a saved strategy. All new catalog entries are Balanced; older saves may retain Aggressive/Cautious. Do not silently replace those profiles. |
| `BotPersonality` | Aggression, trade willingness and expansion bias already affect several choices. These are coupled scoring controls, not independent promises or difficulty levels. |
| `TradeMessages` | Eight voices with 10 pitches, 8 acceptance and 8 rejection lines each. UUID-based selection is stable within an unchanged bank, but has no match history or reason awareness. |
| `TradeAssessment` | Actual acceptance scores and threshold contributions exist. The human-offer UI still requests only a Boolean and gives unaffordable offers the same rejection pool as undesirable offers. |
| `GameEvent` | Committed robber, building, card and trade events exist. Longest Road ownership changes need before/after ownership comparison; there is no dedicated award event. |
| Checkpoint and recording | Existing durable save/replay paths should carry new match-owned data. Preserve incremental validation and turn-boundary exports; don't replay the whole history for every utterance. |

Two independent source audits confirmed additional traps: withdrawing a human
offer can create a rules-level rejection attributed to a willing bot, so that
event alone must not be narrated as the bot changing its mind. Existing profile
snapshots freeze labels, not executable code; adding a behavior-version contract
is future work. Evolving grudges must not mutate the immutable setup/profile
snapshot, which would defeat the new incremental checkpoint validator.

Read these exact sources before implementation:
[profiles](../../Settlers/Models/OpponentProfile.swift),
[traits](../../Packages/CatanAI/Sources/CatanAI/BotPersonality.swift),
[phrases](../../Packages/CatanAI/Sources/CatanAI/TradeMessages.swift),
[trade evidence](../../Packages/CatanAI/Sources/CatanAI/TradeAssessment.swift),
[human trade handling](../../Settlers/ViewModels/GameViewModel.swift),
[events](../../Packages/CatanEngine/Sources/CatanEngine/Models/GameEvent.swift),
[checkpoint](../../Settlers/Persistence/MatchCheckpointStore.swift).
The [September 5 audit](2026-09-05-personality-trade-dialogue.md) is historical
background, not an instruction to build its LLM/chat alternatives.

## Proposed character direction — not final roster assignments

- **Competitive raider:** enjoys robber pressure and contests, can remember who
  robbed it, speaks in short cheeky challenges. Suggested first character: Ragnar.
- **Practical dealmaker:** seeks useful exchanges and can acknowledge repeat
  partners; refuses impossible or unacceptable deals without calling every offer
  insulting. Cooperation is not collusion or automatic acceptance.
- **Proud builder:** celebrates real growth and road/army achievements, with
  restrained competitive commentary. This does not promise new multi-turn planning.

Use recognizable fictional character writing, not assertions that whole cultures
behave alike. Keep the existing roster, names, painted identities and eight voices;
do not silently assign all eight new play styles from these three examples.
Build one complete character first, then use its playtest to choose the rest.
Trait magnitudes, rivalry duration and final voice assignments remain product
choices to settle before behavior changes, not constants inferred from prose.

## Acceptance criteria

| ID | Required player outcome | Evidence required before calling it complete |
| --- | --- | --- |
| P1 | New Game explains the chosen opponent's tendencies in plain language, without a difficulty claim. | Real taps select/start the profile; inspect narrow/wide phone layouts and both game modes. |
| P2 | The neutral Balanced option retains the current baseline's decisions. | Compare the changed executable with a frozen pre-change Balanced executable under the same rules/seed/chair: identical moves and policy RNG across processes. Freeze the actual current baseline, not the September 9 executable. |
| P3 | The first character makes a documented behavioral difference in relevant opportunities, not merely different phrases. | Paired fixtures with alternatives and bounded matched games; report opportunities, selected actions and strength uncertainty separately. |
| P4 | A rivalry responds to an actual recorded interaction, expires, and does not always target the human or the weakest seat. | Robbed/not-robbed, repeated theft, expiry, seat rotation, three/four seats, no eligible rival and clearly better tactical alternative cases. Measure repeated-target streaks. |
| P5 | Personality never bypasses legality, invents resources, or displaces an immediate win the baseline would select just to express a trait. | Rules-approved choices plus explicit win/affordability/mandatory-phase fixtures. This is a new trait constraint, not a claim that Balanced already finds every immediate win. No universal percentage margin over unrelated scoring categories. |
| P6 | Human-facing and bot-to-bot trade decisions use the same character contract. | With identical configuration, state/history, scoped legal options and relevant RNG, equivalent offers yield equivalent decisions; unaffordability differs from valuation. Preserve all willing partners in the human UI, not just the automatic session's first accepter. Cold resume preserves the pending negotiation. |
| P7 | Trade text distinguishes valuation, willingness, selection and completed exchange. | Cancel/decline/expired offer emits no completed-deal celebration; only successful commit does. A positive assessment or `.succeeded` return alone is not that evidence. Freeze pending decision evidence across resume; omit unsupported motives and private hand facts. An affordability penalty is not proof of a legal or winning build. |
| P8 | Robbery, own growth and award changes have relevant reactions. | Real committed events and before/after award owners trigger once; previews, cancellation, replay seeking and rerendering do not trigger fresh reactions. A durable occurrence key distinguishes identical events; test interruption before/after commit and duplicate publication, not just a transient UI batch counter. |
| P9 | Reactions are readable but never block the board or mandatory decisions. | Reuse existing reserved UI geometry and trade components; a compact reaction history is new work, not an existing chat window. Inspect long lines, incoming offer, discard, placement, settings, handoff and VoiceOver. No new full-screen chat page. |
| P10 | Players can mute flavor and reread recent reactions; urgent gameplay information remains available. | Native mute/history flows; muted/unmuted runs have identical moves and deadline/pacing rules under a controlled clock, not identical wall-clock durations on a busy phone. Separate public reactions from private cards/hands. |
| P11 | Dialogue varies without flicker, spam or endless backlogs. | Choose once per event, avoid immediate repeats within eligible pools, define/configure cooldown and bounded history. If no truthful unused line fits, omit optional flavor rather than invent it. |
| P12 | Characters and relationships survive interruption and do not leak between matches or people sharing a phone. | Save/relaunch mid-negotiation, hot-seat handoff, restart/new match and legacy checkpoint fixtures. New match resets relationships; old saves do not silently adopt new temperaments. |
| P13 | Expression remains independent of game simulation. | Stable phrase IDs/version and chosen text survive save, export/reimport and content updates. This exact historical-expression contract is new work, not existing replay behavior. Wording selection never consumes engine or policy RNG; opening message history cannot alter subsequent decisions. |
| P14 | Personalities remain playable in Classic and Expanded. | Three/four-seat fixtures and complete matches on both modes; mode results kept separate. Engine-derived targets/bonuses, not literal 10-point assumptions. |
| P15 | Delivery is real. | Review, full gate, native interactive flows, inspected screenshots, Release launch, exact TestFlight build and tester access. Human enjoyment remains a playtest judgment, not a green-test claim. |
| P16 | Personality can vary choices within declared limits, not only vary wording. | Define eligible decisions and variation limits per trait; persist relevant policy RNG and any pending sampled commitment. Enabled-character decisions match across processes and uninterrupted/resumed runs. Expiry uses committed game progress, not wall time; evaluation/UI activity never resamples a promise or ages a grudge. Balanced's RNG consumption is unchanged; dialogue remains separate. |

## Execution order and stop rules

1. **Deliver the current baseline.** Reconcile source and TestFlight before claiming
   the latest merged work is on a phone. September 12 read-only Apple check still
   returns Build 7 VALID; source is 1.0 (8). No Build 8 upload yet at scope creation.
2. **Agree one character's behavior and presentation.** Start with the raider proposal
   above, a small explicit trait contract and sample situations. Keep the other
   new-game opponents on Balanced during this first implementation.
3. **Implement its actual choices and match memory.** First prove versioned,
   stateless traits, then add bounded rivalry as a separately verified increment.
   Reuse existing policy, trade
   assessment and checkpoint paths. Persist/restore every input affecting decisions;
   storing mutable memory only inside a policy object would lose it on restore.
4. **Complete its expression and UI.** Start with real completed-trade
   acknowledgements in both proposer directions and distinguish pending willingness.
   Then cover the first character's robbery/growth/award events, rather than
   calling trade-only text a finished character. Authored phrases grounded in events/decisions,
   saved selection, readable reactions, history and mute. This is part of the first
   character's finish line, not a later cosmetic stub.
5. **Evaluate, review and deliver that character.** Use existing simulation/strength
   and UI skills; declare seeds, run deadline, watcher and a regression tolerance
   before testing. Don't run unbounded tuning to force a personality win-rate result.
6. **Expand the roster after playtesting.** Decide which distinctions were noticeable
   and fun, then author and test additional characters. Do not inflate dialogue volume
   to compensate for behavior nobody can distinguish.

Stop promotion for broken saves, illegal/stalled games, hidden-information leaks,
fabricated outcomes, permanent targeting or unreadable/interfering UI. If behavior
loses beyond the predeclared tolerance against the frozen baseline, report the
trade-off for an explicit accept/revise decision; don't automatically ship it or
turn personality into an unending strength-preservation project. Stronger road
planning, broader trade valuation and automatic tuning remain separately archived
work, not blockers to writing this contract or prerequisites we restart by default.

## Work recorded this pass

- Fetched and fast-forwarded the clean checkout to `3c4fed9`; preserved `.agents`.
- Rechecked source seams and completed two independent read-only audits.
- Confirmed no open PRs and Apple latest upload Build 7; physical installation
  has not been rechecked this pass.
- Began a fresh full gate for baseline delivery. Its result is not yet known.
- No bot behavior, phrases, app UI or training changed by this scope document.
