# Reading the ladder's games on a Mac (CloudKit server-to-server key)

Every ranked game is already in CloudKit with every move (`Match` records,
`docs/live-sync.md`). Phones replay a downloaded game for its result and keep no
moves, so the only way to study or train on *everyone's* games is to read
CloudKit from a Mac. `scripts/cloudkit-games.py` does that with a
**server-to-server key**. Only the container's owner can create one: the
container `iCloud.com.alexchandler.empires` is on Alex's team (`HXB9F28LHR`).

Jake, 2026-10-24: ghosts must play like their person ("playing ghosts like
playing humans"), and judging that needs each person's own games. Kbeast
(Kyle) beats Expert 8 games in 10, and his moves exist only in CloudKit and on
his phone.

## For Alex's agent: "deploy and make sure it's ready for the latest commit"

Do these in order and report each result. Never commit a key, and never paste
the private key into a chat, PR or issue.

1. **Ship the build.** Run the `ship-testflight` skill for the latest `main`.
   It is the Alex-owned distribution path and never changes Jake's signing
   defaults.
2. **Check the Production schema.** Open the CloudKit Console
   (icloud.developer.apple.com) → `iCloud.com.alexchandler.empires` →
   **Production** → Schema → Indexes. Confirm these:
   - `Match`: `recordName` **Queryable**. The script lists games with a query that has no filter, and CloudKit refuses that without this index.
   - `Match`: `modificationDate` **Queryable**.
   - `Player`: `recordName` **Queryable**.

   If one is missing, add it in Development, then Deploy Schema Changes to
   Production. The setup steps are in `docs/live-sync.md`, "Turning it on".
3. **Create the server-to-server key**, unless Jake already has one. On the
   Mac:
   ```bash
   mkdir -p ~/.config/empires/cloudkit && chmod 700 ~/.config/empires/cloudkit
   openssl ecparam -name prime256v1 -genkey -noout -out ~/.config/empires/cloudkit/key.pem
   chmod 600 ~/.config/empires/cloudkit/key.pem
   openssl ec -in ~/.config/empires/cloudkit/key.pem -pubout   # paste this public key into the console
   ```
   Console → the container → **Tokens & Keys** (API Access) → Server-to-Server
   Keys → `+`. Name it "Empires ghost data (Jake's Mac)", paste the public key,
   and save. Copy the **Key ID** into `~/.config/empires/cloudkit/key-id`.
   Server-to-server keys read the **public** database, and that database is
   where all ladder data lives.
4. **Get the key to Jake's Mac.** Either:
   - Jake creates the key pair on his own Mac (step 3), and Alex only pastes Jake's public key into the console and sends back the Key ID; or
   - Alex sends `key.pem` and the Key ID over a private channel (AirDrop or a password manager), and Jake places them at `~/.config/empires/cloudkit/{key.pem,key-id}`.

   The first way never moves the private key, so prefer it.
5. **Verify** on the Mac that has the key:
   ```bash
   scripts/cloudkit-games.py fetch
   ```
   It prints how many ranked games are on CloudKit and how many are new, then a
   count per player. A count of 0, or an HTTP 401/403, means the key or Key ID
   is wrong. An HTTP 400 that mentions an index means step 2 is not done.

## Using the games

```bash
scripts/cloudkit-games.py fetch                      # ~/Library/Caches/empires-cloud-games/<match>.json
scripts/cloudkit-games.py players                    # games per player
swift build -c release --package-path Packages/CatanAI --product ghost
GHOST=Packages/CatanAI/.build/release/ghost
grep -l '"ownerName": "Kbeast"' ~/Library/Caches/empires-cloud-games/*.json | xargs $GHOST fidelity --cv 4 --detail
```

`ghost` reads these files directly. The person seat (`person:` in the game's
`seats`) is the uploader's, so a file holds that player's decisions. Games
uploaded after 2026-10-24 also mark moves the app made for the person, such as
Auto Robber. Older games read those as the person's own.

## Limits

- **Ranked games only:** Classic standard with one human, uploaded once the player chose a ladder name. Unranked games never leave the phone.
- **Development and Production are separate databases.** TestFlight writes to Production, the default here.
