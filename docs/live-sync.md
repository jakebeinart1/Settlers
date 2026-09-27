# Online ladder (CloudKit live sync)

Every rated game, every Elo rating and every ghost, shared by all players.
Code: `Settlers/Sync/`. Tests: `SettlersTests/LiveSyncTests.swift`.

## How it works

- **Identity.** Each player's name is claimed by their Apple ID the first time
  they sync (`Player` record `name-<slug>`). CloudKit's public database only
  lets a record's creator change it, so the first Apple ID to claim "Jake"
  holds it for good. Another phone using "Jake" is told the name is taken, and
  none of its games are posted.
- **Games.** A finished rated game is uploaded as its opening position plus
  every move (`Match` record). No result is uploaded. Every phone that downloads
  the game replays it through the rules engine and computes the winner and
  stats itself, so a record claiming a win its moves don't produce is rejected.
  A game is also rejected if its human seat is not the uploader's own claimed
  name.
- **Elo.** Each phone recomputes every rating from all the games it holds,
  oldest first (`RatingStore.rebuild`). Elo depends on the order games are
  counted, and this fixed order is what makes every phone show the same ladder
  whatever order games arrived in.
- **Ghosts.** A player's phone trains their ghost after each game (unchanged)
  and uploads the new version (`Ghost` record). Other phones download a ghost
  when it has learned from more games than their copy. They accept it only from
  the Apple ID that holds the ghost's name, and rebuild its display name from
  that claim.
- **When it syncs** (Jake, 2026-09-26: "on a periodic basis that stays within
  limits of needed, otherwise it should just refresh once a game is
  completed"):
  - **When a game finishes:** at once, so the game uploads and Elo updates.
    Once more after the ghost trains, to send the ghost.
  - **Otherwise:** at most every 5 minutes while the app is open
    (`LiveSync.refreshInterval`), on launch, on returning to the app, and
    while the leaderboard is open. A pass is about seven CloudKit requests,
    so this is under two requests a minute per open app.
  - **No push-triggered syncs.** One push per game anyone finishes would wake
    every phone for every game, and that load grows with the square of the
    player count.

  Everything is idempotent: games wait locally until they upload, and an
  interrupted sync is finished by the next one.

## Turning it on (one-time, in Alex's developer account)

Sync is **off** unless a build names a container (`Settlers/Signing.xcconfig`).
Jake's builds, the simulator and every test run with it off.

A CloudKit container belongs to one Apple team. Every phone on the same ladder
must therefore run a build signed by that team, which today means the
TestFlight build (`com.alexchandler.empires`, team `HXB9F28LHR`).

1. **Container.** developer.apple.com → Certificates, IDs & Profiles →
   Identifiers → `+` → iCloud Containers → `iCloud.com.alexchandler.empires`.
2. **App ID capabilities.** On `com.alexchandler.empires`, enable **iCloud**
   (CloudKit, and assign the container above). No push capability is needed.
3. **Profile.** Regenerate the "Empires App Store" provisioning profile so it
   carries iCloud (the old one does not).
4. **Local override.** Add to the gitignored `Settlers/Signing.local.xcconfig`:
   ```
   SETTLERS_CLOUDKIT_CONTAINER = iCloud.com.alexchandler.empires
   SETTLERS_ENTITLEMENTS = Settlers/LiveSync.entitlements
   ```
5. **Schema.** Run a development build once while signed into iCloud and
   finish one game. CloudKit creates the `Player`, `Match` and `Ghost` record
   types on first save. Then, in the CloudKit Console
   (icloud.developer.apple.com) → the container → Schema → Indexes, add:
   - `Match`: `modificationDate` **Queryable**
   - `Ghost`: `modificationDate` **Queryable**
   - `Player`, `Match`, `Ghost`: `recordName` **Queryable** (lets the console list them)
6. **Security roles.** Check that the defaults are unchanged: World → Read,
   Authenticated → Create, Creator → Write. The name claim depends on
   "Creator → Write".
7. **Deploy to Production.** Console → Deploy Schema Changes. **TestFlight
   builds use the Production database.** A schema that was never deployed makes
   every TestFlight sync fail, and the leaderboard only says the ladder
   "could not be reached".

## Status line on the leaderboard

| Shown | Meaning |
|---|---|
| Online ladder · updated 3:41 PM | Last sync succeeded |
| Set your name in Settings… | No name set, so nothing to claim |
| "Jake" is taken online… | Another Apple ID holds the name. Games stay local |
| Sign in to iCloud… | No iCloud account on the device |
| Offline · … | No network, or CloudKit is busy. The next sync retries |

## What the ratings mean (Jake, 2026-09-26)

- **Beating the bots raises your Elo.** Classic is fixed at 1000. Expert
  starts at 1229 and moves with its results against people, so a player who
  keeps beating Expert climbs and pushes Expert down.
- **Expert must stay above the best human.** If a person's Elo passes
  Expert's, that is not a feature to celebrate but a signal: Expert has to be
  improved until it is rated above people again (`TODO.md`).

## Known limits

- **A fabricated game made only of legal moves is accepted.** Catching one
  means replaying every bot move against its policy on every phone, which is
  expensive. Build that when the ladder is actually abused.
- **Every phone downloads every ghost on each sync.** That's one small record
  per player, fine until there are thousands of players.
- **Games played under a name other than the claimed one stay local** (a guest
  on your phone). They still count on that phone's own ladder.
- **Not built yet: a Mac job that trains the shared AIs on every player's
  games.** The data is already there: every uploaded `Match` carries the full
  move log. The job needs a CloudKit server-to-server key from the same
  account.
