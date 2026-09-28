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
  Incoming accepted offers use the same receipt. During a bot turn, only Close
  is offered; another queued offer's countdown is held behind the receipt.
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

`trade-green.xcresult`, `small-screen.xcresult`, `final-small.xcresult`,
`player-trade.xcresult`, and `receipt-review.xcresult` passed native tap-driven
bank/player/incoming trade checks. The 375-point SE screenshots were inspected:
quantity controls, success receipt and pinned footer fit. `queued-receipt.xcresult`
waits beyond the offer timeout during a bot turn, closes the receipt, and proves
the next offer remains answerable. Standards and Spec reviews found engine-query
duplication, missing incoming receipts and hidden countdown progression; the
follow-up resolves these rather than accepting them as release caveats.

`final-small.xcresult` also passed the actual-roll production receipt: city +2,
settlement +1, readable badges, unchanged board frame and three-second expiry.
The first implementation's TimelineView did not remove the receipt reliably;
the failing UI check led to a receipt-ID-keyed dismissal task. Counts update in
the committed game state immediately; only the temporary explanation fades.

## Crash-dialog incident during verification

The initial production unit-test fixture incorrectly called Classic new-game
setup with a four-tile board. Its required 19-tile precondition crashed the test
host, and Xcode retried it, generating repeated macOS crash alerts around
22:48–22:49 local time. The process was stopped, and the fixture now creates a
valid game before replacing its board for isolated payout tests. The corrected
unit suite and native UI runs passed; no new report followed those runs. Existing
local reports are retained (latest at 22:49:19), not submitted to Apple. This
was a test-fixture failure, not evidence of a production crash fix. The old
`production-robber-green` artifact name is misleading: that run was terminated,
not green. The second run failed the expiry assertion; `final-small` is the
passing verification after that fix.
