# Transport and authority research for shared-device, live and asynchronous play

Research date: November 6, 2026. Planning only: no service, account, capability, build or native test was created.

## Provisional conclusion

Both live and asynchronous online play should use one match authority and one game protocol. The current evidence favors a durable authoritative service if Empires must preserve hidden information against modified clients and continue when the initiating phone leaves. A trusted-friends GameKit design remains a legitimate alternative if its trust and availability limitations are accepted explicitly. This recommendation is an architectural inference, not an Apple requirement.

Pass-and-play is a separate local controller arrangement over the same rules. It needs actor handoffs and concealed private views, not a network dependency.

## What Apple currently supports

| Capability | Verified fact and consequence |
| --- | --- |
| Live transport | `GKMatch` exchanges application-defined data with selected players or everyone. Reliable mode provides ordered delivery. GameKit supplies peer networking; the app supplies its protocol. Apple also describes selecting a player host for a client/server topology. That selection measures network suitability, not trust or durable authority. [Real-time data exchange](https://developer.apple.com/documentation/gamekit/exchanging-data-between-players-in-real-time-games) |
| Durable turn-based matches | Game Center stores and forwards turn-based match data, preserves existing matches, and exposes current-participant and participant status. A current participant can save without ending the turn. This is a real async substrate rather than merely a live socket. [Starting and resuming turn-based matches](https://developer.apple.com/documentation/gamekit/starting-turn-based-matches-and-passing-turns-between-players) |
| Out-of-turn actions | Any participant may initiate an exchange, and recipients can reply while it is not their normal turn. Only the current participant can merge completed exchanges into match data. Exchanges support response deadlines, cancellation and completion events. Therefore trade responses and discard requests are not categorically impossible in GameKit turn-based play; their validation, merging, ordering and liveness still need design. [Turn-based exchanges](https://developer.apple.com/documentation/gamekit/exchanging-data-between-players-in-turn-based-games) |
| Shared opaque state | `matchData` is application-defined data passed between participants. These APIs do not provide an application-level per-field secrecy policy. Putting the complete Empires state in that payload would be our decision and would disclose its contents to receiving clients. [Match data](https://developer.apple.com/documentation/gamekit/gkturnbasedmatch/matchdata) |
| Hosted alternative | Game Center can provide matchmaking for custom server-hosted games. The app then connects to its own service, which supplies networking, participant routing and game-specific behavior. Social discovery and server authority need not be mutually exclusive choices. [Custom server-hosted games](https://developer.apple.com/documentation/gamekit/finding-players-for-custom-server-based-games) |
| Limits | Query the relevant SDK properties, including `matchDataMaximumSize`, `exchangeDataMaximumSize`, `exchangeMaxInitiatedExchangesPerPlayer` and match-type player limits. Do not embed historical numeric limits in the design. Prototype actual mode snapshots and command/history payloads. [Match-data limit](https://developer.apple.com/documentation/gamekit/gkturnbasedmatch/matchdatamaximumsize), [exchange-data limit](https://developer.apple.com/documentation/gamekit/gkturnbasedmatch/exchangedatamaximumsize), [matchmaking](https://developer.apple.com/documentation/gamekit/finding-multiple-players-for-a-game) |

A phone is not a continuously available server: UIKit may suspend a background app, and background execution extensions are bounded. Notification delivery also cannot be the only source of correctness. The durable record must be readable on reconnect or manual refresh; notifications should invite the client to fetch it. [Background execution](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time), [background notification delivery](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)

## Identity requires a deliberate bridge

Game Center initialization verifies the local account and exposes multiplayer and communication restrictions. A declined or unavailable Game Center account must have a clear product path; local pass-and-play should remain independently available. [Authenticating a player](https://developer.apple.com/documentation/gamekit/authenticating-a-player)

Use verified stable identity rather than display names. Apple recommends scoped player identifiers and warns that remote identifiers may be scoped to individual match/leaderboard objects; persistence also depends on successful initialization. A client seeing a remote `GKPlayer` is not, by itself, proof of a global account suitable for importing an Elo history. [Scoped identifier behavior](https://developer.apple.com/documentation/gamekit/protecting-the-player-s-privacy-using-scoped-identifiers)

For an own-server path, Apple's current identity-signature API describes server verification of Apple-issued signature material and freshness. Its documented signed identifier is `teamPlayerID` for ordinary apps, with `gamePlayerID` used instead for Apple Arcade. Trust only signed fields. The team-scoped identifier also has privacy and app-transfer implications, so implementation must follow the then-current documentation rather than copying an older verifier. [Server identity verification](https://developer.apple.com/documentation/gamekit/gklocalplayer/fetchitems(foridentityverificationsignature:)), [teamPlayerID](https://developer.apple.com/documentation/gamekit/gkplayer/teamplayerid)

Empires currently identifies its online ladder through CloudKit user IDs. No source establishes that a CloudKit ID and Game Center ID are interchangeable. Linking requires a separately verified flow and migration policy. Do not merge Alex, Jake or Kyle by matching names, and do not attribute all pass-and-play guests to the phone owner's account.

## Current-code constraints

The following are local source observations, not runtime verification:

- [LiveSync](../../../Settlers/Sync/LiveSync.swift) synchronizes post-game records, ghosts and names and validates downloaded match trajectories. It is not an active-match command authority.
- [GameState](../../../Packages/CatanEngine/Sources/CatanEngine/Models/GameState.swift) serializes RNG state, full players, development deck, Conquest deck/hands and Naval state. An ordinary save or full replay is not a safe live client projection.
- [RandomSource](../../../Packages/CatanEngine/Sources/CatanEngine/Models/RandomSource.swift) uses serialized SplitMix64 for reproducibility. Do not treat that replay contract as cryptographic protection. Seeding clients identically would expose future private outcomes; server randomness and any audit/commitment scheme need their own review.
- [RulesEngine](../../../Packages/CatanEngine/Sources/CatanEngine/RulesEngine.swift) permits pending players to discard and permits trade responses outside the ordinary turn owner's action. Required actor and ordinary turn owner are different concepts. The current `legalMoves(for:seat:)` specializes discards but otherwise delegates to the phase move list; a network API must not blindly send that list to every seat.
- [CatanEngine's package](../../../Packages/CatanEngine/Package.swift) and [existing Linux CI](../../../.github/workflows/ci.yml) provide a plausible Swift-server reuse seam. No new Linux/server execution was performed for this research.

## Architecture alternatives and critique

| Option | Strength | Remaining obligation |
| --- | --- | --- |
| GameKit live + GameKit turn-based | Apple-native invitations, peer communication, durable turn storage and out-of-turn exchanges | Avoid separate competing authorities. Map ordinary turns and reactions, handle offline current participants, reconcile live messages with stored state, and decide who holds secrets. A player host remains a trusted client. |
| Durable service + foreground delivery + async fetch/notifications | One authority can validate every actor, persist reactions and deadlines, issue private views, and survive phone departure | Adds deployment, database durability, monitoring, recovery and security work. No hosting vendor, framework, cost or availability promise is selected here. |
| Game Center discovery/identity + durable service | Retains supported Game Center social flows while the service owns the match | Requires identity verification and explicit links to existing CloudKit records. GameKit does not implement the custom server protocol for us. |

The second or third option is the provisional direction for the complete feature. The first remains worth a focused prototype if the product accepts friendly host trust and current-participant-dependent progression. Ordinary transport encryption does not prevent a recipient or authoritative player host from inspecting a full state it legitimately receives. Hiding cards or fog in SwiftUI alone provides presentation privacy, not secrecy against modified clients.

## Implications for the planning document

These are proposed requirements and inferences, not implemented features:

- Keep ordinary turn ownership separate from the person required to answer a discard, trade or harvest decision. Give reactions stable IDs, authorized responders and explicit cancellation/expiry.
- Authenticate a controller before permitting its seat to act. Serialize accepted commands with revisions and durable idempotency receipts. A lost acknowledgement must not reroll dice, duplicate a payment or accept a trade twice.
- Use one authoritative history for live and async delivery. Whether a running match can change pacing is a separate product decision. Reconnect and manual refresh must recover the latest accepted revision without depending on push delivery.
- Define per-recipient views for hands, cards, decks/RNG, unknown Naval tiles, logs, errors and reconnect history. Test serialized bytes, not just whether the UI draws a fog overlay.
- Keep pass-and-play guests, online identities and current AI rating pools separate until attribution and verified account linking are specified.
- Decide acceptable host trust, deadline/forfeit/AI-substitution behavior, client-version compatibility and operational ownership before selecting a transport.

## Evidence still required

A focused prototype should prove a live two-phone journey and async continuation; out-of-turn exchanges; multiple required discards; duplicate/reordered requests and lost acknowledgements; host/current-participant departure; authority restart; stale-client recovery; and private-view leakage checks. Measure actual payloads and service load before making capacity or cost promises.

No prototype, service, native build or multi-phone test was performed for this research.

