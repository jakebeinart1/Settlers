# Online multiplayer

## Product contract

Empires supports private online friend matches in two paces. Each match uses an
existing three- or four-seat table with at least two humans. Classic or Expert
AI can fill other seats. Classic, Vast and Voyages use the existing rules
engine. Conquest is available with Classic and Vast. Online matches are casual
and appear in the participant's Your Games history.

| Surface | Behavior |
| --- | --- |
| Online Play | Create an online identity or recover it on another device. Create a room, join by code or invite link, and resume any game from Your Games. |
| Lobby | Show humans, open seats, AI, civilizations, board, rules and pace. Reserve seats atomically. A roster or settings change clears readiness. Start requires the latest configuration and every human to be ready. The next remaining human becomes host if the original host leaves. |
| Match | Show the committed board, scores, public inventory counts, and the viewer's private hand. Name whose turn it is and highlight when a different player must respond. Confirm board actions through the existing placement affordance. Show sending and reconnecting status. |
| Your Games | Show ongoing and finished games, turn owner and whether the signed-in player owes an action. Open the latest committed revision. Closing the game is safe. Resignation explicitly converts that seat to Classic AI while a human remains. |
| Identity | The service generates a high-entropy key. The phone stores it in Keychain, and the service stores its digest. The player can deliberately copy the key to recover the same identity. Account deletion removes the account and its device bindings and anonymizes that seat in other players' games. |

## Paces and clocks

**Async.** Required actions wait for the responsible player. A directed trade
offer has one recipient and expires after 12 hours. A decline or expiry
returns play to the proposing seat. Optional trade requests appear in Your
Games without sending a system alert. AI turns run on the authority, including
when every phone is offline.

**Timed Live.** Each opening placement has 60 seconds. The ordinary turn
has 90 seconds including the dice roll. Required interruptions such as a
discard, robber decision or harvest have 45 seconds. A directed trade response
has 30 seconds. The ordinary turn clock pauses during these interruptions and
resumes with the remaining time. Making another ordinary move does not add
time. At a deadline the service resolves an outstanding mandatory choice with
a legal fallback. It declines an expired trade and ends an expired ordinary
turn after resolving the required dice roll and any resulting choices. A
command reaching the authority at the deadline loses the race to expiry.
Both clients display a countdown based on the same server deadline.

The clock survives restarts. A service gap longer than 20 seconds pauses
active live deadlines by the persisted gap. Async trade expiry follows wall
time. A local phone clock change cannot extend a server deadline.

## Match integrity and privacy

One authority owns roster, randomness, legal moves, timers and results for
both paces. It applies the real rules engine to each authorized move and
persists the new revision, receipt and notification state before accepting it.
A duplicate command with the same actor and payload confirms the original
acceptance without moving twice. A reused identifier with different content
is rejected. Independent discards can commit against the same decision even
when another player has already responded.

Network views contain public board data and only the authenticated seat's
private hand, hidden points and authorized choices. The service retains the
deck, random state, opponent hands and undiscovered terrain. Invite codes locate
rooms. Membership still controls access. The phone uses private projections
for drawing and never runs the rules engine on a reconstructed hidden state.
The viewer receives bank trade availability for their current actions. The
authority keeps stock counts and validates the complete trade at submission.

## Turn notifications

When a committed revision makes a required action available to a human, the
same save records the pending action and an alert outbox entry for eligible
devices. Registered devices get a visible APNs alert with generic lock-screen
text and an opaque match identifier. Opening it reauthenticates, loads the
current game and shows the current obligation. Stale alerts open the current
match safely. The alert itself never applies a move.

Permission is optional and can be requested from the online experience.
Per-game mute suppresses alerts. Your Games still lists actionable matches
when permission is denied, push is delayed, or the phone is offline. A
foreground alert for the match already on screen is suppressed. Invalid
registrations are removed, transient delivery failures retry, and the outbox
does not send resolved or expired actions. [Apple APNs delivery](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)

## Acceptance

- Exercise room joins and concurrent readiness, cross-account access denial,
  duplicate and stale commands, parallel choices, private projections,
  restart recovery, and server-owned deadline races.
- Run two authenticated clients through the HTTP interface. Verify the same
  committed board and countdown and show that the scheduler works when
  neither client is polling.
- On two physical phones with a configured TestFlight build, complete an
  asynchronous match and a timed live match. Observe a turn alert with the
  recipient's app terminated and phone locked, open to the owed action, and
  repeat with notifications disabled using Your Games. Exercise an off-turn
  discard, AI fill, reconnect, timer expiry, and an already-answered alert.
- Record the lobby, inbox, private board controls, timer, and result. Keep
  deployment disabled in unconfigured builds. Preserve solo and Pass & Play.

[Original planning draft](https://github.com/jakebeinart1/Settlers/pull/72) ·
[Server configuration and operation](../../../Packages/EmpiresOnlineServer/README.md)
