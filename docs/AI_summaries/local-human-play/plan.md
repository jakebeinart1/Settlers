# Same-device human play — design interview

## Requested direction

Alex prioritized local human-versus-human play before online multiplayer on
November 6, 2026. People share one device; optional AI seats remain useful.
Use the existing Empires rules and visual language. This is a design interview,
not approval of an implementation or a completed functional specification.

The repository's [grill-me skill](../../../.claude/skills/grill-me/SKILL.md)
uses Context, Question, Option A, Option B and Recommendation for each question.
Record answers here as they arrive; recommendations remain proposals.

Online remains a later feature in [PR72](https://github.com/jakebeinart1/Settlers/pull/72).
Its settled direction is live and asynchronous play on existing three/four-seat
tables with optional AI seats. No two-seat ruleset was requested for this local
restoration; retain the current table and rules while defining local controls.

## Verified starting point

- `MatchSetup.newGameProblem` allows one human in the first seat, and
  `normalizeToOneHuman` removes extra humans from new-game preferences. Legacy
  multi-human saves still have restoration support. This is not a finished
  pass-and-play experience hidden behind a toggle.
- `SeatCardView.rolePicker` labels the human as “You” and offers AI/Ghost for
  other seats. Multiple named humans need explicit, understandable roles.
- `PlayerDirectory` has one phone/cloud owner, not a store of local human
  profiles. Match seats already retain names, but a name cannot authenticate a
  guest as the real Jake, Alex or Kyle.
- `ContentView.rememberPreferredIdentity` and
  `NewGameSetupView.applyAppPreferences` treat the first human as the phone
  owner. Restoring extra humans must not rename guests or change ownership.
- `GameViewModel` routes legacy local play toward the person owed an action;
  it has no privacy handoff cover. Discards, resource choices, private cards,
  trades and resume all need attention, beyond ordinary turn changes.
- The current trade interface was designed around a human and bots. Human
  negotiation and acceptance need an explicit product flow.
- AI ratings exclude multi-human matches. Preserve that boundary; a local
  result must not become the phone owner's solo AI Elo result.

These facts were inspected on merged main `2943bab`. No gameplay changes or
native builds have been made for this design interview.

## First decision round — unanswered

1. **Setup entry:** choose Human/AI/Ghost within the existing seat cards, or
   first select Solo/Pass & Play inside New Game and then configure the seats.
   Recommendation: reuse the seat cards without another main-menu item.
2. **Local identity and records:** use named guests with a remembered setup,
   or persistent device-local people with their own local records.
   Recommendation: persistent local people with optional guests, clearly
   separate from authenticated cloud identities and solo AI Elo.
3. **Human trade audience:** make a direct offer to one selected person, or
   open an offer to the table. Recommendation: table offers, preserving
   negotiation. Selection among multiple willing partners is a later decision;
   preserve the prior request for equal odds among AI-trade accepters while
   deciding the new human negotiation flow explicitly.

## Branches to explore after the first answers

Work through setup defaults and seat replacement, private handoffs and optional
hand inspection, off-turn decision ordering, human/AI trade interactions,
uninterrupted save/resume, result attribution and abandoned solo-save warnings.
Derive acceptance criteria across Classic, Vast, Conquest and Voyages, including
compact layouts and accessibility. Capture and strictly review the new screens
when implementation and native verification are authorized and resourced.

Protect private information during viewer changes, including accessibility and
resume. Preserve committed state, engine determinism, legal moves, existing
solo behavior and the board's fixed viewport. These are correctness obligations,
not reasons to ask the user to choose a broken alternative.

At the end of the interview, present the agreed plan and acceptance criteria
for shared understanding before implementing it.
