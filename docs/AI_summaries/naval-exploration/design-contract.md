# Voyages design and implementation contract

Selected October 4, 2026 under Alex's instruction to build the complete mode and
resolve its remaining design work. These are delegated product decisions, distinct
from the charter's human commitments. Three independent reviews examined gameplay,
engine/AI information and phone interaction before implementation. Quantitative
balance remains a hypothesis until the acceptance evidence exists.

## Full match rules

The opening begins in opaque mist. A central survey reveals its radius-two home
island footprint, then normal snake setup places two settlements and two roads
per seat. Both starting settlements may use any legal home site, including
inland corners. Coastal access is required to launch a ship and to found a
settlement by ship, not for ordinary land placement. October 5's D38 corrects
the overly broad first-opening coast restriction. New version 2 matches measure building vision within two hexes
of the actual corner, using its three canonical hex centers; version 1 saved
matches retain the earlier survey from adjacent land. Ships use their actual
hex center. Roads reveal nothing. Starting sight cannot reach overseas land.
Reveals remain public forever. October 5's D36 records the correction and evidence.

A ship costs two lumber, one wool and two ore: the existing resources represent
the agreed wood, sheep and iron. A ship launches in a sea hex touching an owned
settlement or city. Each builder has six purchasable hulls over the match; capture
does not return a hull to stock. Captures have no controller fleet cap, preserving
the promise that any opposing ship may be selected. Ships may share and pass
through sea hexes. Stacked ships get explicit identity selection, never an
ambiguous tap that silently picks an owner.

Every owned ship receives three steps at its controller's turn boundary. Newly
purchased and newly captured ships receive three steps immediately. Each sailing
action commits one adjacent sea step during the main turn; trading and building
may happen between steps. Radius-two sight makes all next-step terrain known.
Preview and cancellation reveal nothing. Each committed step reveals radius two,
with cosmetic mist withdrawal. All ship locations are permanently discovered.
Ships cannot enter land or leave the public world envelope.

A ship touching a coastal vertex permits a normal-cost settlement without a road,
subject to the ordinary distance and piece limits. This also permits another
outpost on an already settled island. The ship remains and pays no additional
step. Ordinary road-connected settlements also remain legal. Roads grow from an
owned land network; sea-only edges never accept roads. The first settlement on
each of a player's first two overseas land components grants one permanent colony
point. This rewards completed expansion rather than discovering empty sea or
holding a large fleet. Public point totals expose earned bonuses; hidden component
metadata must not enter policy observations or descriptions.

An 11 produces ordinary resources, resolves resource-choice production, then lets
the roller capture one opposing ship or skip, then enters the main turn. Every
opposing ship qualifies globally. Capture keeps its location and ID, changes its
controller and gives three steps; buildings, the victim's hand and hull builder
remain unchanged. Control never expires automatically. No-target rolls enter main
turn directly. Robber and Knight retain land stealing and never affect ships.

Voyages uses 14 points, two-point Longest Road and Largest Army, their existing
five-road/three-knight thresholds, six settlements, five cities, twenty roads,
38 bank cards per resource, a doubled 50-card development deck and a ten-card
discard threshold. Ships do not count as roads. Colony points provide at most two
points per player. Ordinary production and trades use each player's normal hand.

## Geography and controlled variation

Use a public radius-seven envelope of 169 hexes. Home has 19 land hexes at radius
two; exactly 28 overseas land hexes occupy radius five or greater. Rings three
and four are sea. The fixed extent prevents camera fit from exposing hidden
coastlines. It also provides an honest world overview while a deliberate local
camera makes home and expedition decisions legible.

Three selectable families, equally likely under Surprise me:

- Archipelago: four medium island groups with varied coast lobes and approaches.
- Peninsula: one crescent or branching peninsula landmass with separate satellites.
- Twin Islands: two substantial groups with smaller satellites and different routes.

The peninsula is overseas. A home-connected peninsula was considered: roads could
make the primary expedition optional before ships repay their fixed investment.
The chosen family retains peninsula-shaped exploration and separate sea expansion.
Straight chains were rejected because they turn free sailing into one obvious
route; unbounded scattered tiles were rejected for weak settlement sites and
empty travel. Family constraints vary coastlines, division and orientation rather
than shuffling unrelated single hexes.

Validate connected navigable sea, useful approaches, no home land bridge, at least
three viable coastal sites per overseas component and all land within two hexes
of reachable sea. Credible home harbors need two distinct overseas opportunities
within six sea steps. Measure real routes and legal settlement capacity. First
landings may take one turn; distant or around-coast voyages may take two. Do not
derive journey duration from radial distance alone.

Home retains Classic's resource and token multisets. Overseas baseline contains
six lumber, six grain, six wool, five brick and five ore. Its tokens are two each
of 2 and 12 and three each of 3, 4, 5, 6, 8, 9, 10 and 11. Adjacent 6/8 terrain
is prohibited. Region specialties affect placement without hiding a required
ship ingredient behind the first voyage. Four home ports are two generic, grain
and wool; five overseas ports are two generic, lumber, brick and ore. Ports use
actual land/sea coasts and have no shared endpoints.
Harbors are charted when the land beside their shared edge is public. All home
harbors are visible before placement; overseas harbors appear with their coast.
Cosmetic mist never covers a charted badge or dock, and no surrounding sea is
revealed solely to show a harbor. Existing endpoint ownership activates 2:1 or
3:1 exchanges; visibility alone grants no rate.

Generate the complete world before play with seeded, stable enumeration. Bound
generation at 64 attempts and use a verified same-family fallback when needed.
Fallback must pass the same constraints and remain reproducible. Fog and resource
choice options cannot change topology, underlying ordinary terrain, token positions
or random draw consumption. This enables paired option comparisons.

## Resource-choice economy

Default fog and resource-choice settings are on, independently switchable. With
resource choice on, two designated baseline grain/wool positions on separate
substantial islands become resource-choice terrain, with tokens 4 and 10. Off
restores those ordinary resources at the same positions and numbers. A settlement
earns one choice, a city two individually chosen units. Flexible production is
allocated once; valuation cannot spend it as all five resources simultaneously.

Pay fixed yields first, then resolve flexible units in clockwise seat order
starting with the roller. Choices include stocked resources only. If the bank is
entirely empty, remaining units expire and the phase advances; no bank debt or
wildcard inventory is created. After choices on an 11, capture follows. These
obligations are durable and recover unselected after cold launch.

## Product options and compatibility

Preserve current New Game's four-seat, one-human configuration and civilization
assignment. The engine, replay and evaluation support three/four seats and legacy
multi-human matches. Do not restore removed pass-and-play controls as unrelated
scope. Both Traditional and Expert support Voyages; mixed tables are evaluated
through the shared policy/session interface. Naval Expert has a new persisted
revision; existing Expert revisions retain their existing meaning.

New Game presents **Rules → Standard / Conquest / Naval** (Alex, October 5).
Naval selects the existing naval world and Standard engine variant, with its
own island map and 14-point target; it cannot combine with Conquest or Classic/Vast
land boards. Leaving Naval restores the land board selected in that editing
session. Saved Naval prefills reopen with Naval selected; no engine encoding changes.
Ghosts remain Classic-only; naval games are local
and unrated and must not train or publish incompatible ghost/rating/sync records.
History, statistics, logs, import/export and replay retain the naval rule/version
identity. Existing Classic/Vast starts and legacy Expanded saves remain supported.
Mode name is Voyages; option explanations describe behavior rather than engine
details. Costs use existing resource art and terminology consistently.

## Visual and interaction direction

Retain the painted sea background, serif hierarchy, civilization art, notched
gold chrome and blue command surfaces. Use a continuous painted sea with quiet
hex guides, opaque silver cloud banks with shaded troughs and a soft decorative
frontier, varied sea ripples, known-coast foam and established textured land. D42
replaces the old ship drawing with eight transparent painted civilization styles,
broad current-controller cloth and distinct hulls, without a castle/building
overlay. Board, Fleet, Build and proposals share the same asset selection.
Actual/proposed board ships share `max(22, hexSize × 0.92)` visual diameter;
thin selection decoration is capped at 2.5 points and hit geometry remains
separate. Capture changes presentation only after commitment; its preview paints
one prospective hull and stacks retain explicit owner/identity selection.
Resource-choice
terrain reads as a distinct productive island feature. Mist withdrawal is the
memorable motion; idle decoration remains restrained.

The board and command-row frames remain fixed. Default camera focuses readable
home on the fixed world envelope. World fits the whole map and becomes Return,
which restores the user's preceding local zoom and pan, including an already
fitted zoom-one pose. The previous fitted pose must not be replaced with Home's
zoom 2.6. Home and explicit ship
selection focus a readable area and end that excursion. Discovery never moves the camera. All ship,
land, target, port and mist layers share geometry and clip to the board viewport.
Unrevealed kinds/numbers/ports never enter rendering or VoiceOver labels.
The final-source build 22 gate and native gallery verify charted harbor visibility
and exact Return, including the fitted-pose counterexample. [E27](acceptance.md#build-22-follow-up-e27-delivered)
preserves the red/passing sequence, full result, Debug/Release attribution and
verified internal TestFlight delivery. Physical-phone installation/play and
hardware timing remain unobserved.

Build → Ship stages launch with cost feedback. A ship tap or Fleet choice stages
sailing; a destination previews the voyage; Sail confirms one step. Settlement
uses the existing reversible piece preview. Capture lists every eligible ship
with current owner and stable ID; selecting focuses its location and Capture
confirms. Skip is explicit. The bottom dock remains the one confirmation surface.
Resource production gets a painted choice surface with bank availability.

D43 gives each Build choice an explicit Ready/Unavailable state, symbol and
cards-held/cost counts, with missing quantities or a phase/supply/location reason.
Only actual legal moves during that actor's main turn enable it. Public-state
explanations never authorize a move or probe concealed land. The compact popup
uses one measured action tree inside one ScrollView; the current intrinsic
measurements replace old values, while the header and Close remain pinned.
Disabled touches change no state; ordinary previews and durable purchases retain
their existing commit boundaries, including Conquest payment.

D44 keeps Skip/Retry on the command row's leading side and trade answers trailing,
with complete disjoint hit regions. One stable answer-control tree stays outside
the scrolling summary. Hidden terms require Review before acceptance; opening
Review pauses the countdown, Back keeps it held, and a deliberate summary tap
resumes it. Complete offer content and proposal occurrence bind both measurement
and timer lifetime, so a later reused offer ID cannot inherit old review/ticks.
These build 23 changes leave rules, saves and gameplay RNG unchanged. Frozen
`1dfae7c`, version 1.0/23, now passes its own complete gate. All 111 engine/AI
package files match build 22, so its 48 functional matches/six repeats are reused
as prior evidence, with no rerun or strength claim. Targeted/compact/mixed-stack
results, seventeen inspected final-source images, ordinary Release survival,
signed upload and verified internal TestFlight access are recorded in
[E28](acceptance.md#build-23-follow-up-e28-delivered). External build 23 remains
unreleased and physical-phone installation/play unobserved.

Action controls have 44-point targets. Board targets have selection alternatives
through fleet/choice controls and magnification; dragging is never mandatory.
Overlays remove hidden controls from hit testing and VoiceOver. Reduce Motion
replaces drifting mist with a brief readable transition. Any deliberate reveal
hold is bounded; interruption completes cosmetics while preserving durable state.
Drafts are temporary: outgoing handoffs clear them, cold launch drops optional
drafts and reconstructs mandatory obligations without old selections.

## State and policy boundaries

Engine API: `GameMode.naval`; `TileKind.sea`, `.resourceChoice`, observation-only
`.fog`; `GameState.naval: NavalState?`; `Ship(id, owner, coordinate, stepsRemaining)`.
`NavalOptions` contains `fogEnabled`, `resourceChoiceEnabled` and optional
`mapFamily`; `NavalState` contains `options`, `revealed`, `ships` and versioned
bookkeeping. `Naval.newGame(seed:playerCount:options:)` constructs a coherent match.
`Naval.visibleBoard(in:)` supplies public fog placeholders, ports and land topology.

Moves are `buildShip(at:)`, `sailShip(id:to:)`, `captureShip(id:)`, `skipShipCapture`
and `chooseResource`. Durable phases are `choosingResource(playerIndex:)` and
`capturingShip(playerIndex:)`. Land settlement retains `buildSettlement`.
Structured events carry committed purchases, steps, discoveries, transfers,
colony points and resource choices. Public ledgers account for costs and choices.

Naval observations mask hidden geography and metadata, ordered decks, future
engine randomness and opponents' exact hand compositions. Public counts and
counted beliefs remain available; old modes' deliberate information behavior
does not change. Central observation construction covers ordinary, queued and
human-offer responses; checkpoints compare projected observations appropriately.
Older queued replies using the former harbor filter are accepted only when their
whole observation matches that exact legacy projection from authoritative state.
Resume refreshes the public chart while preserving the sampled reply, evaluation
index, counters, ledgers and RNG; other integrity guards remain unchanged.
Policy candidates value public frontier potential, known coastal sites and
uncertain outcomes rather than simulating the real hidden world.

Both tiers deliberately handle purchasing, trade funding, navigation, colonies,
capture, production choice, cards, roads/cities and victory. Traditional has
transparent priorities with personality variation; Expert compares economic and
relative-position opportunity costs. `NavalPolicy` implements the shared ledger
contract with distinct tier IDs and deterministic response-only trade decisions.
The session action backstop allows the fleet's finite sailing budget while still
bounding trade loops. Engine/AI remain Foundation-only and deterministic.

## Requirements and verification readiness

F01–F15 remain required. Their scenarios cover normal, alternate and failed launch,
adjacent movement, over-budget and land movement, cancelled previews, stacked
ships, first and repeat colonies, global and repeated captures, skip/no-target,
production order/finite bank/city units, all four toggle combinations, saved
versions, historical visibility and complete victories. Illegal actions cannot
change state or RNG. Save/resume and replay must agree across processes.

Evaluate all families, both tiers, mixed tables, three/four seats, nonzero human
positions, native setup and legacy resume. Compare identical public observations
with different hidden worlds/future RNG; policy decisions must agree. Freeze
fully naval-capable anchors before tuning, use development seeds separately from
held-out seeds, rotate every chair, report intervals and completion/decisive
rates separately by table size. Measured thresholds and failure cases drive
refinement; old Classic promotion results cannot establish naval strength.

Real native controls must purchase, sail, reveal, settle, capture, choose resources,
resume and reach victory. Inspect opening, first voyage, competition and crowded
late-game screenshots plus mist/capture recordings. Record exact artifacts and
distinguish seeded starting positions from states reached by actual moves.
Run targeted tests during development and one final full gate for the completed
tree. No implementation or runtime acceptance is satisfied by this design record.
