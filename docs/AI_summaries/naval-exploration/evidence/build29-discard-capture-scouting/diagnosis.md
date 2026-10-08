# Build 29 diagnosis and correction boundaries

October 8, 2026. These are retained diagnostics with their original source/verdicts.
[E35](../../acceptance.md#build-29-follow-up-e35) now owns completed Internal
acceptance at tested/archive `c09e084`. The earlier failures remain failed; final
closure is recorded in [verification](verification.md), without retroactive
source or verdict changes.

## Seven with eight resources

`IMG_1770.PNG` showed a natural seven at robber placement with eight resources
and one Knight. The engine used Naval's ten-card limit; the discard editor was
never owed. [Natural-roll proof](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/seven/proof.json)
records actual red exit 1 before the fix, scoped green exit 0 (44 functions),
and the helper's complete Engine suite exit 0 (413 functions). These numbers
belong to that helper source, not the final integrated gate.

[Effective rules](../../../../../Packages/CatanEngine/Sources/CatanEngine/Models/GameState.swift)
now resolve the saved Naval version. New v5 uses seven; shipped v1–v4 keeps ten.
[NavalSevenTests](../../../../../Packages/CatanEngine/Tests/CatanEngineTests/NavalSevenTests.swift)
cover actual rolls, development-card exclusion, Knight, odd totals, other
rollers, simultaneous obligations, atomic rejection, replay and cold checkpoints.
No automatic ongoing-match rule upgrade is implemented. Resume/replay preserve
the recorded rules; Restart creates a fresh current-v5 board and rules while
retaining the realized roster, stealing choice and saved brain identity. The
game-over screen's New Game button also restarts that saved table; Main Menu →
New Game setup selects the current brain and normalizes implicit stealing Off.

Final documentation review corrected an earlier claim that Restart also kept the
ten-card limit. The [Restart source](../../../../../Settlers/ViewModels/GameViewModel.swift)
at lines 407 and 489 creates a new state, and the hosted Restart assertions cover
the retained roster, brain and options. This is a documentation correction to
existing behavior; no production change was made for it.

## Optional capture and an unread transfer

[Capture proof](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/capture/proof.md)
retains disabled-11 red behavior (capture still opened) and 41-function scoped
engine green. Old absent option data means historical On in an active match;
fresh New Game normalizes that implicit choice Off. Explicit On remains On.
[Receipt transactions](../../../../../Settlers/ViewModels/GameViewModel+ShipCapture.swift)
publish only committed transfers and require a saved acknowledgement. Cold
resume and failed writes cannot quietly consume the owed receipt.

The initial native run's four receipt queries used the wrong accessibility
element type. Extracted actual images then exposed fragmented maximum-text
owner labels; full-width labels replaced them. The following real native loss
flow still found the covered ship hittable. Root `3a9abe2` moved the painted
receipt into the shared mandatory native cover, preserving the original failing
assertion and adding Settings, swipe-dismiss and cold-resume isolation checks.
The [final focused native command](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-naval-acceptance-command.json) now exits 0 at unchanged `5851930`,
including that preserved covered-ship assertion. Root approved the final loss/
gain and maximum-text originals. Earlier failing commands remain retained; the
full-gate acceptance is recorded separately in verification.md. The corrected-source matrix and transition
checks subsequently pass under the separate receipts linked in verification.md.

A wildcard harvest followed by capture on the same 11 is unreachable in valid
supported maps: wildcard tokens are 4/10 and checkpoint validation enforces it.
No invalid 11-wildcard fixture was created. Actual 4/10 settlement/city harvests
and 11 loss/gain flows instead verify the shared native presenter.

## Frozen scouting failures and own-spending returns

Frozen masked V1 decisions chose End turn despite voyages exposing three or
nine new hexes. Scouting V2 reserves realistically near-funded landings, prices
public frontiers and avoids redundant hull reservations. It uses a separately
saved brain identity so shipped V1 decisions are preserved.

The first 96-case functional matrix reached every winner with no forced ends,
but cases 47/77 had an idle same-turn return. Case 47 sailed away, made a rejected
trade proposal and bought a development card, then sailed back without new
terrain. Case 77 built a road between departure and return. Spending flipped
the chosen travel objective; those voyages are defects, not successful play.
[Exact red](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/ai-final/return-red2-receipt.json)
exits 1 with both actual bad choices reproduced, including checkpoint reload.

[Return policy](../../../../../Packages/CatanAI/Sources/CatanAI/Naval/NavalScouting.swift)
now uses optional public v5 sailing origin history, retained through spending.
It rejects a zero-discovery immediate return unless an actually funded landing
strictly improves or a colony proves a win. [Exact stored sequences](../../../../../Packages/CatanAI/Tests/CatanAITests/NavalReturnPolicyTests.swift)
pass after the fix; [engine history cases](../../../../../Packages/CatanEngine/Tests/CatanEngineTests/NavalSailingHistoryTests.swift)
preserve human returns, old absent fields, v1–v4 replay, capture/turn resets,
discovery, settlement beyond the bonus cap and city history. Rival hands,
concealed geography, decks and engine RNG remain masked. The corrected full
matrix now passes 96 winners and six byte-exact repeats. Ten full transition
inspections pass, including 47/77; the shipped V4/V1 baseline traces remain
byte-exact. See [verification](verification.md) for bound source and limits.
No strength or physical-phone claim follows.


## First full gate: stale blockade fixtures

The [first full-gate command](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-attempt1-prepush-command.json)
at `416a0c6` exits 1. The [native summary](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-attempt1-native-summary.json)
records 805 functions/1,610 runs passed, four functions/nine runs failed and one
existing compact-device skip. The [immutable gate log](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-attempt1-prepush-gate.log)
retains the complete failed run. No upload followed.

Six generated-baseline runs incorrectly expected the newly generated v5 state
still to equal blockade introduction version 4. The [alternate-route failure](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-attempt1-failure-0-details.json)
incorrectly expected whole-ship equality after a real discovery: physical
ownership/position/allowance stayed unchanged, but public progress correctly
cleared the defender's previous sailing origin. The corrected test explicitly
chooses a discovering route and checks both the physical blockade and the reset.

Two saved synthetic states are invalid. The [legacy overlap failure](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-attempt1-failure-2-details.json)
and [crash](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-attempt1-failure-2-crash.ips)
change the v5 baseline to v3 while retaining v5 ship history. The [defender-turn failure](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-attempt1-failure-3-details.json)
and [crash](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/final-attempt1-failure-3-crash.ips)
refill the defender's allowance to two without clearing its old sailing origin.
The strict checkpoint guard correctly rejects both with `incompatibleCheckpoint`.
Correction clears history for the synthetic legacy/new-turn boundary and
validates the replacement state before saving. Geography, resource conservation,
ownership, route legality and actual cold-resume assertions remain intact.

The correction changes only NavalBlockadePresentationTests.swift at `c4d0bee`;
production, validator and replay contracts stay unchanged. Its [first focused command](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/blockade-v5-fixture-correction-command.json)
exits 65 before tests run; the [compile log](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/blockade-v5-fixture-correction.log)
attributes this to nested throwing test macros. The [focused retry command](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/blockade-v5-fixture-correction-retry-command.json)
at unchanged `c09e084528b7cdcb6cef02653adddb11294c5a90` exits 0 after separating
the throwing bindings. Its [summary](/Users/alex/.codex/artifacts/naval-exploration/build29-diagnostics/blockade-v5-fixture-correction-retry-summary.json)
passes all seven affected functions/12 runs with no failures/skips. This targeted
pass keeps its own source and never substitutes for the full gate.
