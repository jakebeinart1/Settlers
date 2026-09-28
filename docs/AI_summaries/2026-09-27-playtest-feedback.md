# Trade, robber and production feedback

Scope: Alex's September 27 phone playtest. No AI strategy changes; isolated from
the ongoing research worktree. Official harbor rule: receive a **different**
resource (https://www.catan.com/faq/basegame).

## Acceptance criteria

- Bank: six grain at 2:1 can buy three ore. Repeated card taps always add;
  separate minus buttons remove one output or one input bundle. No overloaded
  toggle. Counts never become negative or exceed the available hand/bank.
- The same resource cannot be both given and requested. The engine remains the
  authority for a final trade; stale drafts report the actual failure.
- Only a committed trade shows success. A quiet receipt names the partner and
  exact cards given/received. It stays until **Trade again** or **Close trade**;
  failures and bot willingness are not presented as completed exchanges.
- All trade controls remain reachable on 375-point phones. Normal content hugs
  its height; overflow scrolls inside the panel with the footer always visible.
- Production feedback is local to the seat holding the phone: readable +N
  resource indicators, actual city/settlement quantities, no all-player card
  shower, no fabricated gains on shortages or robber-blocked tiles. Respect
  Reduce Motion and do not move the board or delay engine state updates.
- Robber confirmation is investigated with real legal fixtures, including
  rolled seven, Knight, nonzero seats and victim selection. Do not claim a fix
  without a reproduced failing case.

## Design decisions

Keep the painted chrome, blue panel (#215285), gold (#DAAB5F) accents and existing
resource colors. Success uses one checkmark and a legible exchange receipt,
not a new modal or confetti. Give/Get are stable five-column rows. Adding and
subtracting have different controls with at least 44-point touch targets.
Keep errors actionable and the completed transaction separate from the next draft.

## Evidence

Artifacts: `/Users/alex/Library/Application Support/EmpiresResearch/deliveries/trade-robber-feedback-20260927`.
`bank-red.xcresult`: native taps reproduced 6 grain / ore taps three times -> 1
ore, expected 3. The engine already supports multiple outputs and rejects bank
resource overlap. Root cause is the output selector's remove-on-repeat branch,
not a credit calculation or engine quantity limit.

Domestic trades also prohibit matching resources (official 2025 rulebook p.7).
The UI now excludes them in both directions and on submission. Existing bot
candidate generators already exclude them. Historical domestic replay remains
unchanged: old saved logs can contain such offers, and rejecting them in the
shared replay mutation would block those saved games. Bank validation already
rejects overlap and now has explicit rate/compound/no-mutation regression tests.

`robber-overlay-red.xcresult` reproduces a hidden trade-popup flag suppressing
board interaction during a mandatory robber decision. Visibility and input
blocking now use the same predicate; superseded editor flags are cleared. The
normal seven/Knight flows passed on SE. This is a concrete related defect, not
proof that it is Alex's unspecified phone failure.
