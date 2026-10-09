# Naval design decisions

## Build 27 decision D55: defending occupied water

**D55 — Rival hulls block their sea hex, delivered.** A stationed ship blocks
opponents entering, passing through or launching into its water, even at zero
moves. Friendly hulls may share water. Capture may create a mixed-owner stack;
existing ships can leave while opposing re-entry stays blocked. New matches
encode v4; saved v1–v3 retain their behavior.

The engine owns the public predicate used by previews and both AI tiers. AI
funding excludes inaccessible colonies and sealed expedition purchases. Touches
reject blocked water without choosing a neighbor. No combat, anchoring action
or strength-weight change is added. [E32](acceptance.md#build-27-follow-up-e32)
records the repaired dock, 48 functional winners, full gate, signed Internal
TestFlight delivery and owned-QA finish. [PR #61](https://github.com/jakebeinart1/Settlers/pull/61)
is the integration record for this verified source.


## Build 26 decision D54: public Monopoly gain, delivered

D54 corrects D53's omitted publicly derivable quantity: finite supply minus bank
minus your own cards is the combined rival holding. Choices show “N to collect”,
Play previews the exact gain and zero is plainly explained while staying legal.
Typed quantities distinguish Plenty's bank supply; missing/invalid stock remains
unknown. No private rival composition or rule/AI/schema change is added.
[E31](acceptance.md#build-26-follow-up-e31-delivered) binds all verification, eleven
reviewed originals and exact Apple26 delivery. Alex delegates approval and PR
resolution to the agent; earlier human-approval waits below are historical.

## Build 25 card decisions: selected, verified for delivery

Alex's current direction concerns all five cards, HUD count alignment, clean
compact names, fit and a deliberate full-match audit. D50–D53 apply to the current
production freeze `a9e0e88` (376 inputs); [E30](acceptance.md#build-25-follow-up-e30-delivered)
owns intermediate evidence. All 112 package inputs match build 24, whose 48-match/six-repeat evidence is
reused. The failed first full gate and test-only correction remain recorded; the
replacement gate passes all ten mandatory stages at `cffe613` and publishes the
branch. Ordinary Release runtime and root review of 27 unchanged final originals
pass. Signed archive/export/upload, payload comparison, Apple/access and QA cleanup
pass. Apple confirms VALID/unexpired internal IN_BETA_TESTING for
Alex. Tested-head CI passes; PR #60 remains unmerged, awaiting approval.
These choices do not reopen build 24's delivered rules or asset provenance.

**D50 — Distinct engraved card emblems and one HUD rhythm, selected.**
Knight uses a shield, Road Building a road, Year of Plenty two resource cards,
Monopoly a coffer and Victory Point a star/laurels. Native paths inherit the
painted navy, ivory and gold material. Shared 44-point icon/name/count slots and
fonts align resource and card counts. Compact card names omit READY/NEW/PLAYED;
availability remains in accessible values and the selected detail. A separate
status row displaces the count baseline, while the old generic symbol set does
not distinguish the five cards clearly enough. Dedicated raster paintings would
add an asset-generation dependency without improving these small emblems.
The native path correction replaces `addLines` after an existing move with
explicit continuations where a reset would break the intended outline.

**D51 — Compact browsing, one selected detail, selected.**
The hand shows compact emblem/name/held-count selectors and one compact effect
detail. Large art remains appropriate to a purchase reveal; the existing result
receipt also retains its illustration. Repeating expanded art and effect text
in every selector wastes the middle viewport and makes it harder to compare
cards. A name-only list loses recognition; compact emblems retain it. Every held
card stays inspectable when Play is unavailable, with the actual timing/reason
in its detail rather than a misleading READY suffix.

**D52 — Match the chooser to the card's source, selected.**
Monopoly says “Collect from rivals” and offers all five resources without bank
stock or private rival counts: bank scarcity does not limit this card. Year of
Plenty shows two ordered removable picks, selection progress and actual bank
stock; exhausted options cannot be added and the same resource can be chosen
twice when stock permits. At two picks every bank choice dims/disables while
removable picks stay bright. A cached last-choice highlight required an
environment-aware button-style correction and original-image review after
green tests. A common bank-labelled picker would misstate Monopoly,
while an unordered aggregate hides which Plenty pick a tap removes.

**D53 — Fit real controls and audit real ownership, selected.**
Normal resource choices use one row; accessibility sizes use two columns. Header
and actions stay pinned, while the middle scrolls. Only the fixed scaffold caps
at accessibility size 1; effect text and choices keep the full requested size.
Selectors receive their exact available width before wrapping and align within
the horizontal viewport. Debug frame markers sit behind controls, reject
interaction and do not intercept native taps. Merely shrinking the whole panel
or checking its outline would miss clipped choices and unusable actions.
Rare fixtures start from actual Naval legal setup and conserve bank/deck totals.
A separate ordinary Expert match pauses at natural purchase/mature-hand/result
checkpoints, inspects genuinely owned cards, and continues to a real winner;
seeding midgame cards would make that complete-match claim weaker.

The [charter](README.md#confirmed-commitments) owns confirmed commitments. Every
entry below records the questions analyzed before building. Under Alex's subsequent
instruction to build fully, D01–D32 have delegated selections in the
[design contract](design-contract.md). Status is **Decided**, with implementation
validation recorded in the acceptance register and final source-bound receipts.
Human charter commitments remain distinct from these choices.
Stage numbers refer to the program in `README.md`.

## Build 24 decisions: selected, verified for delivery

Alex's October 7 follow-up reopens the affected sailing and presentation choices.
D45–D49 are selected contracts; [E29](acceptance.md#build-24-follow-up-e29-delivered)
owns source-bound validation. Build 23's decisions and evidence below retain
their original source and outcome. Current-main integration is frozen at
`9bce5f7`, 1.0/build 24, with 376 matching production inputs. The fresh v3
48-match/six-repeat functional evidence passes. Integrated/refined native failures
are retained; the later three-case harvest audit pass uses three exact-ID live
screenshot contrast guards and retains the raw flags. Four harvest originals
and the actual rival notice are inspected. The first full pre-push gate failed
two obsolete test oracles; test-only `67efbad` then passes three functions/eight
runs with production unchanged. Final full-gate session `91604` passes all ten
mandatory stages, exit 0, and publishes test-only `67efbad`; optional separate
Debug app build skips while the native Debug test action built separately.
Ordinary Release survives six seconds after fresh install without QA arguments,
and root approves all 23 unmodified final originals. Archive/export/upload/
signatures and independent final audit pass; Apple confirms VALID/internal
IN_BETA_TESTING with Alex's Internal access. E29 is delivered. PR #60 awaits
actual approval, with required tested-head CI passing and no merge. No new
strength claim is made.

**D45 — Painted harvest and durable progress, October 7, human-selected.**
The any-resource tile must read as painted terrain beside the existing resource
tiles. A muted lavender field with restrained antique-gold botanical strokes
uses the ordinary hex outline, grout and number token. The old schematic
decoration leaves productive land unlike its neighbors; a market scene or five
resource symbols would compete with the production token. The selected asset
is the unmodified built-in imagegen output. Its [prompt/source/hash manifest](../../../design-references/approved/tiles/harvest-generation-manifest.json)
binds approved and runtime PNGs. Root inspected actual integrated local/World/
maximum-zoom and maximum-text renderings; the original PNG was never edited.
The later 23-original final gallery is approved at its recorded scales; native
skip and physical/manual measurement limits remain E29. Native caption contrast
acceptance is qualified by exact-ID live ≥7:1 guards, not cleared raw flags.

Harvest explains the producing buildings: a settlement contributes one choice,
a city two, and mixed buildings retain their combined original entitlement.
Heading and Collect stay pinned while choices scroll. Derive the original total
from the unchanged producing board/roll and progress from the durable remaining
obligation. Saving an additional presentation total would duplicate truth;
showing only remaining cards would relabel a partly collected city as a one-card
harvest after cold launch. No new save field or schema is needed.

**D46 — Natural ship language, October 7, human-selected.**
Fleet, launch/capture notices, board labels and replay narration describe a ship
and its current owner without labels such as “Ship 3.” Numeric IDs remain
internal for exact selection and replay. Numbered labels expose bookkeeping;
invented vessel names would add unrelated naming and persistence work. Painted
controller identity and explicit stack/nearby selection remain. Validate
multi-owner stacks and cold resume so simpler language cannot choose the wrong
vessel.

**D47 — Two-hex destination sailing, October 7, human-selected.**
New Naval v3 matches give each ship two sea hexes per controller turn, including
new launches and captures. Select any reachable public sea destination costing
one or two hexes, then confirm one voyage. Stable breadth-first traversal with
sorted neighbors picks one canonical shortest route; that same route determines
preview, cost, policy evaluation and the union of committed intermediate reveals.
Equal-length routes cannot change tomorrow's replay or preview a different
discovery. The allowance itself changes, rather than only the displayed number.

Adjacent-only taps add unnecessary repetition; unrestricted travel would remove
the human-selected limit. A route picker for equal paths adds an unnecessary
choice at this short range. Every reachable endpoint carries its cost above
cosmetic mist, with the selected route visible. Radius-two ship sight already
makes the complete v3 range public; concealed land cannot decide the action mask.
Preview and cancellation reveal nothing. Version 1/2 saves and replays retain
three hexes per turn and adjacent-only moves, including launch/capture allowances;
missing Naval versions still decode as 1. Map version 1 and state schema 6 stay.
Changed movement and policy costs require new functional/determinism evidence;
build 22's matrix cannot close E29. Integrated native range/route/commitment
journeys pass, and frozen `9bce5f7` passes 48 fresh matches plus six complete-byte
result/trace repeats. Actual travel includes 569 two-hex voyages. Independent
reveal reconstruction covers two retained fog-off checkpoints; engine/source
fog tests remain separate. Final regression gate remains open; functional
completion does not establish strength.

**D48 — Visible current win goal, October 7, human-selected.**
The human HUD shows score/current target. In-Game Settings explains the current
target in plain text, and New Game places the selected goal beside its existing
Match Settings heading. A new section would add the scrolling Alex rejected;
a fixed “14” would misdescribe other modes and resumed lengths. All three read
the actual draft or saved target. Verify compact/maximum-text layouts, mode
changes and a nondefault resumed target.

**D49 — Fair competition for an accepted bot offer, October 7, human-selected;
scope interpretation recorded.**
When the human accepts a live bot proposal, the human joins the other actual
seated policies that choose acceptance through the normal response mask and can
fund it. Uniform selection over the sorted recipient pool uses session policy
RNG. Funding alone does not mean willingness; inventing a policy for a human
seat would manufacture consent. Always favoring the human excludes willing
rivals; a fixed first responder favors seat order. Decisions, including a cached
ordinary reply, retain their telemetry.

The winner commits ordinary `respondToTrade` as its actual Step actor; a bot
winner is not recorded as a human move. A bot win posts “X traded with Y” in the
existing fixed information area. Candidate state, policy RNG and history publish
only after the durable checkpoint succeeds. No engine RNG, move type, save field
or schema changes. The narrower interpretation changes only human Accept on
live bot offers: Decline, expiry and manually composed human proposals retain
their existing paths. The optional question about broadening those paths has no
answer at this checkpoint, so they are not broadened. Reopen D49 if Alex answers
it. E29 retains real human/bot winner journeys and the inspected integrated
Expert-rival notice. Refusing/unfunded/missing policies, exact-once transfers,
failed writes, cold resume and replay remain final regression obligations.

**D42 — Painted controller fleets, October 7, human-selected.**
Alex requested beautiful, simple painted vessels in the Empires storybook style,
with broad controller-colored cloth and eight distinct silhouettes. The sail
carries ownership; a castle/building overlay is removed. Britannia uses a purple
cog, Greece a tan galley, Egypt an ochre crescent hull, Aztec a blue canoe-like
trader, Columbia a white cutter, Rome a coral ram-bow galley, Japan a jade junk
and Norse a steel-blue longship. The transparent generated PNGs are retained
unchanged beside their prompts and hashes in the
[approved ship manifest](../../../design-references/approved/ships/generation-manifest.json).
Runtime catalogs use the exact approved bytes.

Board, Fleet, Build and proposals share the same artwork. Current controller
identity selects its civilization, so a committed capture changes cloth/hull
without changing the ship's stable ID or introducing builder art/save fields.
The board visual diameter is `max(22, hexSize × 0.92)` for both actual and proposed
ships; the separate hit geometry stays at least 44 points. Selection borders are
capped at 2.5 points. A capture preview shows one prospective vessel instead of
blending it over the committed hull; stacks show separate silhouettes and retain
their explicit chooser. Asset checks and targeted native passes are E28 evidence;
an offscreen maximum-zoom label does not prove visible paint. The strengthened
pan/containment guard and real mixed-controller purchase/sailing test pass.
The full gate at frozen `1dfae7c`, version 1.0/23, passes; seventeen selected
final-source images are root-inspected, including all eight local fleets and the
World stack/two-owner chooser. Ordinary Release survival and archive/export/
Production signing and upload pass; Apple 1.0/23 is VALID/internal IN_BETA_TESTING
with Alex's Internal access verified in [E28](acceptance.md#build-23-follow-up-e28-delivered).
No production camera change is part of this correction.

**D43 — Explicit construction availability, October 7, human-selected.**
Alex requires ready actions to be visibly different from unavailable ones.
Every row states Ready or Unavailable with a symbol, readable fill and exact
cards-held/cost counts. Shortages identify missing quantities; other explanations
cover turn/phase, finite pieces/decks and accessible construction locations.
Enabling comes only from the actual legal move set when the displayed actor is
in their own main turn. Explanation text cannot authorize an action or inspect
concealed terrain. Conquest keeps its flexible army payment and inventory.

The painted popup stays compact when its content fits. One action tree lives in
one ScrollView, with independently measured current header/choices/footer/error
heights; fresh measurements replace prior ones and can shrink. Header and Close
remain outside scrolling. Disabled physical taps must leave costs, cards,
discoveries and optional proposals unchanged after dismissing the modal; a ready
ship still previews/cancels before paying once on confirmation. E28 records
targeted native/hosted and compact-phone evidence, including the corrected
scrolling test oracle. The frozen-source full gate and ordinary Release runtime
pass; signed internal TestFlight delivery and Alex's access are verified.

**D44 — Separate pacing from trade decisions, October 7, human-selected.**
Repeated Skip touches must not become acceptance or refusal when an incoming
offer takes over the fixed command row. Skip/Retry uses a 92×52-point leading
rectangle; trade answer controls remain trailing, at least 44 points, with
disjoint complete hit regions including padding. One answer-control tree mounts
once while only offer terms scroll. Covered commands stay unmounted beneath
Settings, preserving the modal privacy boundary.

Terms too long for the summary require full review before acceptance. Review
holds the countdown, and Back retains that hold; a deliberate summary tap
resumes it. The timer and intrinsic-height measurement belong to complete offer
content plus proposal occurrence, including identical later proposals with reused
IDs. Replacement/disappearance cancels the old task; timeout remains automatic
expiry, distinct from a human refusal. The legal baseline reproduced stale
touches answering a real offer; E28 retains it separately from earlier invalid
fixtures and confirms targeted ordinary/max-text, expiry and cold-resume paths.
Those guards are also included in build 23's passing full gate at `1dfae7c`.

**D40 — Charted-coast harbors, human-selected correction.**
Alex requires the retained 2:1 and 3:1 harbors to remain visible through mist on
the starting map. The home coast is already surveyed, so all four home harbors
are public before placement. An overseas harbor becomes public when the land
bordering its shared edge is discovered. Surrounding sea remains fogged, and a
hidden island's ports remain concealed. Badge and dock drawing sits above the
cosmetic mist, using only the public port list. Owning a settlement/city on an
endpoint activates the existing ratio; seeing a harbor grants no trading rights.

This changes public knowledge, not generation, resource supply, reveal radius or
recorded move effects. A legacy queued trade reply may retain the former port
projection. Resume accepts it only when its whole observation matches that exact
legacy projection reconstructed from authoritative state; the sampled reply,
evaluation counters, ledgers and RNG survive without another policy decision.

**D41 — Explicit World return, human-selected correction.**
World is a reversible camera excursion. Its control changes to Return and
restores the zoom and pan used before entering the overview, including an
already fitted zoom-one pose. Home separately
focuses the home island; an explicit ship focus also ends the excursion. Camera
inspection preserves an uncommitted proposal and never spends cards or reveals
terrain. The saved value is a user-selected camera pose, not a cached fitted
geometry or container measurement. The fit remains a pure function.

Native baseline tests showed the existing Home handler working through physical
center/padding taps, while the explicit Return affordance was absent. New real
3/4-seat journeys exercise setup, CPU pauses, human roll/main turn and cold
resume, measuring the pose itself and the navigation strip's clearance from the
human HUD. A later native counterexample found fitted zoom one returning to
Home's zoom 2.6 despite those initial focused passes. Source `1cf1c0f` preserves
the actual preceding pose in that case; the red and passing guard are retained
in [E27](acceptance.md#build-22-follow-up-e27-delivered). The earlier
harbor/Return images remain intermediate captures. The complete gate at
`1cf1c0f`, ordinary Release survival and inspected final-source images now verify
the local correction, including that fitted-pose guard. Signed upload, Apple
VALID/internal IN_BETA_TESTING and Alex's tester access are verified in E27's
independent final audit. External release and physical-phone play are not claimed.

**D38 — Inland home settlements, October 5, human-selected correction.**
Alex clarified that the ship-access requirement applies to founding by ship,
not to normal placement on land. The first-opening coastal filter incorrectly
generalized this condition. Both setup settlements now allow every legal home
corner, including the interior; setup still cannot jump overseas. Later ordinary
settlements follow owned roads. Founding without a road still requires an owned
ship touching that exact known coastal corner, plus visibility, spacing and
supply checks. Once founded, an island supports ordinary inland road expansion
even after its ship leaves. The opening dock and rulebook state the same rule.

This expands legality without changing any previously recorded move's effects.
It applies to fresh and resumed setup; no save migration or rules-version bump
is necessary. Naval v1/v2 vision and previously discovered terrain stay intact.
Regression tests reproduced rejection before the fix and cover both opening
rounds, three/four players, all families, fog on/off, old checkpoint resume,
owned-road inland construction, unreachable/rival ships, and real colony roads.
Ship-focused policy fixtures explicitly require a harbor instead of constraining
production policy choices. Unfiltered Traditional/Expert setup is also tested.

**D39 — Simulator inventory and lifecycle, October 5, human-selected.**
Alex requires shared-machine storage awareness and protection of other projects.
The existing run/play/verify skills now require inventory, ownership evidence,
reuse of a stable task device, an explicit QA UDID, serial native tests and
individual cleanup. The gate defaults to one worker without CoreSimulator clones.
Blanket shutdown/delete is prohibited. Guidance was updated in the original
project skill source as well as this worktree; no Codex-specific rule copy was
created. Two retired task-owned devices were deleted only after their Empires
app data was archived and verified; the current review and QA devices are reused.
Other projects' devices and running work are preserved.

**D35 — Compact Naval configuration, October 5, human-selected.**
Alex rejected the extra main-page scrolling caused by inline island/fog/resource
controls. Naval now shows one aligned Advanced Settings entry with the current
family and option states. A painted full-screen editor owns those choices and
explanations, with Done pinned outside its scroll area. Bindings edit the same
draft; dismissal does not start a match. Phone spacing uses the existing compact
layout so regular setup fits from its title through Turn Order. Accessibility
option text follows the editor's bounded type scale; explanatory subtitles are
also spoken as hints. Native full-viewport assertions remain required.

**D36 — Exact settlement vision, October 5, human-selected correction.**
Alex questioned visibility measured from touching hexes instead of the actual
settlement corner. Independent enumeration found 19/24/27 revealed centers for
one/two/three touching land hexes, versus a symmetric 12 from the actual corner.
Scale the three canonical axial coordinates by three, retain sea/off-envelope
coordinates, and compare their exact cube norm to six. Ship vision remains the
existing 19-center radius two. The [hex coordinate reference](https://www.redblobgames.com/grids/hexagons/#distances)
explains the cube distance; corner scaling and cutoff are this game's derived
implementation and independently enumerated regression cases.

New matches use Naval rules version 2. Version 1 saves and replays keep their
original survey behavior, missing versions decode as 1, and prior public
knowledge is never removed. Engine rules 3, map 1 and state schema 6 remain.
The whole 19-hex home survey is a separate setup rule, retained from D01; an
optional question about changing it has no response, so it is not silently
replaced. The in-app explanation now states that home starts charted.
Native confirmation at the reported coastal corner discovers six new sea hexes
(total 25), compared with the legacy thirteen (total 32), and survives cold resume.

**D37 — More convincing sea and fog, October 5, human-selected.**
Alex requested richer water and denser visible fog. The selected drawing uses a
continuous ocean wash, varied ripple density/spacing and known-coast foam;
opaque silver cloud banks have shaded troughs and a narrow soft frontier.
Fog's core remains completely opaque. Shore marks use the redacted board;
cosmetic noise uses public coordinates, without hidden geography or gameplay RNG.
Offscreen clouds are culled, fine water detail fades through overview scales,
and there is no idle animation. Normal discovery withdraws the banks; Reduce
Motion retains the brief non-drifting transition. The board's viewport and
clipping contract are unchanged. Native transactions, hidden-production pixels,
World/max-zoom captures and final source-bound media are required evidence.

**D34 — Settings spacing/help and phone delivery, October 5, human-selected.**
Alex requires wider horizontal selectors shifted left on one shared axis, readable
descriptions of every choice through one info control per row, screenshot review
and refinement, then iPhone delivery. The selected layout combines each label and
info glyph in one 114-point heading target, adds an 8-point gutter and uses
uniform 46-point choice targets. Accessibility layouts remain stacked. An opaque
painted navy/gold panel separates named options and scrolls into view; the footer
and selections remain stable. Build 18 also preserves the newer phone-release
behavior and data fields before delivery, rather than installing an older baseline.

**D33 — Setup entry, October 5, human-selected.** Alex requires Naval in the
Rules row beside Standard and Conquest. The app presents those three choices;
Naval maps to existing `mode: naval, variant: standard` and displays its own
island world, rather than suggesting Classic/Vast naval combinations. Returning
to land rules restores the board chosen during that editing session. Persisted
mode/variant values, generation, AI and running saves retain their identities.
The previous Voyages entry in Game Mode is removed from this screen only;
the mode remains supported by engine and prefill normalization. Validate actual
selection, saved prefill and all four land-board/rules return combinations.

**October 8 clarification and adjacent regression.** Alex requires fog only in
Naval: Classic, Vast, retained Expanded and Conquest land boards remain fully
visible during setup, play, cold resume, Restart and replay, regardless of
remembered Naval options. No reachable ordinary-mode fog leak has been
reproduced in the current audit. A shipping-control test did reproduce a related
setup leak: choosing a fixed land board, visiting Naval, then returning to land
silently selected Randomized (native failure after 7.572 seconds). The correction
remembers the draft's land randomization choice alongside its land mode and
restores both on leaving Naval. Naval match normalization and active saves remain
unchanged. Coverage includes fixed/randomized Classic/Vast with either land
rules choice, repeated Naval taps and later edits before another round trip.
The first corrected native focus passes 21 tests, including the real ordinary
match and replay. The final strengthened assertions additionally check actual
variant and the new settlement phase after Restart; their completion verdict is
owned by the [final full-gate receipt](/Users/alex/.codex/artifacts/naval-exploration/mode-isolation-audit/final-prepush-command.json),
not the earlier focused run. The audit keeps its unreproduced fog symptom
distinct from the reproduced board-choice defect.

## Decision record

For each decision, record:

1. The player problem, linked motivation/commitment and dependent requirements.
2. Concrete alternatives, including their full-match consequences.
3. Critique and counterexamples: fairness, pace, comprehension, option combinations,
   strategic incentives, visual demands and required integration.
4. A recommendation with its assumptions and why it serves the product.
5. Evidence: annotated maps, turn walkthroughs, visual comparisons or bounded
   experiments. Distinguish predictions, measured behavior and human feedback.
6. Decision authority/date, the selected rule and rejected alternatives; or an
   explicit provisional status with criteria for resolving it.
7. Observable acceptance scenarios, impacts on both bot tiers and compatibility.
8. Reopening conditions and validation results after implementation.

Use `Open → Analyzing → Proposed → Decided → Validated`. Decided means the rule
is selected; Validated requires evidence that the resulting behavior satisfies it.
Do not promote a convenient implementation default into a product decision.
Present related substantive player choices together after their concrete analysis;
routine technical choices remain autonomous within the settled requirements.

## Stage 1 Match contract

| ID | Question and alternatives to examine | Required critique/evidence |
|---|---|---|
| D01 | Starting arrangement: shared home land, separate starts, initial harbors; how first placements work on a fogged world. | Walk through setup without unseen-terrain choices or an opening deadlock. No full visible home island has been approved. |
| D02 | Initial vision: starting settlements, starting ships or another explicitly defined opening rule. | Show the fully fogged introduction and exact first two-hex clearing footprint. Opening animation is settled; the source of its reveal is not. |
| D03 | Sailing allowance and action timing: per ship or shared allowance; distance per turn; before/after trading/building. | Compare early, middle and large-fleet turns, first landing time and idle travel. Independent ships do not imply unlimited movement. |
| D04 | Ship location, launch and occupation: sea hexes or another position model; eligible purchase locations; passing, stacking, blocking and docks. | Narrow straits, occupied harbors, no launch space, map edges, land barriers and multiple opponents. |
| D05 | Discovery during travel: every traversed location or destination; atomic movement and presentation pacing. | Hidden destination becomes land; preview/cancellation; mid-path reveals; bounded detours. No preview may grant discoveries. |
| D06 | Continuing vision: which pieces reveal after setup, including settlements/roads and inland expansion. | Thick island interior cannot be permanently inaccessible to discovery. Keep C04's two-hex distance. |
| D07 | First settlement: qualifying ship presence, eligible coastline/interior sites, distance rule and the meaning of new land. | Two players arrive at one island; a ship leaves/captures before commitment; first colony then roads; already settled foreign island. |
| D08 | Ship after settlement: remains, docks, or is consumed; continued role after full exploration. | Fixed five-resource purchase payoff, repeated landings, fog-off play and late-game purpose. Consumption is not approved. |
| D09 | Capture on 11: optional selection, production timing, no targets, newly built ships and repeated captures. | Keep any-opponent/global eligibility. Walk production/capture order and a winning turn. |
| D10 | Capture bookkeeping: action allowance, fleet limits, controller identity and recapture this/next turn. | A target already moved, current-player capacity reached, third-player capture and existing colonies/hand unaffected. |
| D11 | Captured ship's location and user feedback; public target identification with fog. | Explain the selected vessel unambiguously; prove target selection and takeover do not reveal undiscovered terrain accidentally. All ships may already be in explored water; demonstrate the invariant rather than assuming a conflict. |
| D12 | Existing scoring: retain/remove Longest Road, Largest Army, victory target and other bonuses. | No Biggest Navy award is approved. Check reachability with finite pieces/sites/deck and demonstrate a complete finish. |
| D13 | Existing rules quantities and effects: pieces, bank, deck, discard threshold, robber/knight/Road Building and ports. | Sea cannot become a normal road/robber target accidentally. Define every card interaction and finite-supply outcome. |
| D14 | Supported match options and rules overlays. | Both Traditional and Expert and 3/4-seat product tables are required. Decide hot-seat variants, Conquest interaction and what New Game explains. |

## Stage 2 Geography and economy

| ID | Question and alternatives to examine | Required critique/evidence |
|---|---|---|
| D15 | Select map families and their frequency: branching archipelago, peninsula, contrasting clusters and other justified forms. | Draw multiple concrete examples before selection. Critique straight chains and empty distant seas. For road-connected peninsulas, assess whether roads make sailing unnecessary, ships offer useful shortcuts, and other islands preserve maritime expansion opportunities. |
| D16 | Map envelope, land/water budget, cluster sizes, thickness, coves, straits and maximum travel. | Count legal coastal settlement sites, road growth and actual navigable voyages. Apply the two-hex visibility rule to starting/early/mid-game footprints. |
| D17 | Fairness and variation from actual starting locations. | Compare useful expansion alternatives and production opportunity without requiring exact symmetry or revealing predictable hidden geography. |
| D18 | Resource-choice representation, entitlement, choice timing, city yields and finite-bank resolution. | One flexible yield cannot become five simultaneous yields. Examine multiple owners, city production and unavailable requested resources. |
| D19 | Resource-choice frequency, production numbers, site capacity and option-off replacement. | Its recurring flexibility must justify its balance; remoteness alone is insufficient. Fog/wild toggles should not hide a worse economy. |
| D20 | Ordinary terrain, numbers, ports and regional resource specialties. | Ship materials must be obtainable before owning a ship. Overseas opportunities must matter with resource-choice disabled; no sole essential resource behind capture-dependent access. |
| D21 | Exploration incentives and overall pace. | Compare buying ships, building at home, waiting for an 11 to seize a ship, repeated voyages and late-game fleets. Keep the fixed ship price unless Alex revises it. |
| D22 | Hidden-world generation: whole map prepared at setup versus another reproducible discovery method. | Assess information fairness, resource constraints, replay, option pairing, variety and bounded runtime. Whole-map generation was proposed, not approved. |
| D23 | Generation rejection, repair and failure behavior. | Define playable/fair constraints, bounded attempts, reproducible fallback/failure and a development/held-out map catalogue. Test combined economic/topological quality. |

## Stages 3 through 5 Requirements and design

| ID | Question and alternatives to examine | Required critique/evidence |
|---|---|---|
| D24 | Ship recipe's correspondence with existing resources, especially iron/ore; player-facing naming, setting defaults and explanations. | Preserve the exact agreed recipe while resolving resource identity. Test comprehension of costs, independent sailing, persistent global capture, fog and resource choice without engineering docs. |
| D25 | Visual direction: sea/fog/coasts, ship shapes/control marks, movement/settlement previews and takeover feedback. | Compare full compositions at real phone size, across quiet/crowded states and accessible variants. |
| D26 | Mist animation timing, opening reveal, multiple discoveries, interruption/resume and Reduce Motion. | Permanent state changes remain authoritative; cosmetics cannot duplicate discoveries, deadlock play, impose unbounded delays or move the viewport. Decide intentional brief command holds and visual sequencing. Capture does not restore fog. |
| D27 | UI decision priority, confirmation/cancellation, any selected hot-seat handoff and pending trade/recovery behavior. | Distinguish durable obligations, uncommitted drafts and animation progress. Preserve the current contract that clears outgoing drafts on handoff, drops optional drafts on cold launch and rebuilds mandatory decisions without old selections, or record a deliberate change and its privacy/failure cases. |
| D28 | Traditional/Expert information and strategy contracts. | Both choose all naval actions deliberately; hidden world/decks/future RNG are unavailable including in candidate projections. Decide private-hand policy explicitly; current observations are authoritative state. |
| D29 | AI calibration, behavior, completion and latency criteria. | Freeze fully naval-capable anchors, predeclare comparisons and distinguish strength, game completion, decision quality and human enjoyment. |
| D30 | Versioned save, policy, replay, game history and animation semantics. | Old Classic/Vast/Expanded games resume; old Expert revisions retain their meaning; historical replay never displays future discoveries. |
| D31 | Current product integrations: Conquest, ghosts, ratings, stats, sync/import/export, encodings and help. | Select explicit compatible behavior. Do not silently rate unlike modes together, train ghost features on incompatible state, publish hidden world contents or label unsupported choices as working. |
| D32 | Test/visual coverage, quality thresholds and delivery evidence. | Meaningful scenario/configuration coverage, complete native matches, actual installation provenance, reviewed screenshots/recordings, regression matrix and closure criteria. |

## Design questions to examine first

Stage 1 begins with D01–D08: a concrete opening-to-first-colony walkthrough fixes
the dependencies among initial sight, sailing and settlement. Analyze D09–D14
alongside it so capture and the endgame fit the same rules. Map distances are then
meaningful inputs to Stage 2 rather than guesses made before movement exists.

Do not ask Alex to fill the entire register as a questionnaire. Prepare considered
alternatives and critique, then bring the few connected choices that materially
shape the player experience. Preserve open questions in the register until settled.
