# Empires online server

This package runs the shared Swift match authority behind HTTP. The iOS client
depends on the portable online package and does not link Vapor or APNs.

## Run locally

From the repository root with Swift 6.1 or later:

```sh
online_data="$(mktemp -d)"
EMPIRES_ONLINE_DATA_DIRECTORY="$online_data" \
  swift run --package-path Packages/EmpiresOnlineServer --force-resolved-versions empires-online-server
```

`GET http://127.0.0.1:8080/health` reports readiness. The iOS transport uses
`POST /v1/online` with a JSON request, bearer authorization and ISO 8601 dates.
Responses and typed errors are JSON. A newly created account receives its
recovery credential once in the response body. Keep real credentials off the
command line and out of logs.

```sh
swift test --package-path Packages/EmpiresOnlineServer --force-resolved-versions
```

## Deploy

Build the Linux image from the repository root. The Dockerfile-specific ignore
file excludes local Swift products, secret keys and authority data.

```sh
docker build -f Packages/EmpiresOnlineServer/Dockerfile -t empires-online-server .
```

Run one always-on instance behind a trusted HTTPS ingress. Bind the container
only to its private ingress network and apply per-client rate limits at the
edge. The authority limits anonymous account creation to 20 per direct peer
and 120 globally per hour, with a maximum of 1,000 stored accounts. Behind
one proxy, that peer limit covers all requests arriving from the proxy.
Attach a persistent volume at
`/var/lib/empires-online` or set `EMPIRES_ONLINE_DATA_DIRECTORY` to a different
absolute mount path. The directory must be writable by UID and GID 10001 and
private to the server. Deployments should replace the old instance before
bringing up a second writer. The authority rejects a second process on the same
volume. Avoid automatic sleep because the same process advances AI, expires live
turns and dispatches alerts without a foreground player.

Configure `/health` as the readiness probe. A failed snapshot write before
replacement makes the service unready until its next durable save. If
replacement succeeded but the directory sync failed, restart the single
writer so it loads the authoritative snapshot again. Preserve the state directory across
restarts and keep private, access-controlled volume backups. Exercise restoration
into an isolated volume before production. Recovery must restore the entire
authority snapshot, including command receipts, active rooms and the push outbox.
Before changing the rules or AI policy versions, start the proposed executable
against a copy of the complete production snapshot and verify readiness and
representative active rooms. If any checkpoint cannot load, keep the previous
binary and prepare a verified migration before updating the volume. Treat
finished room retention as part of that preflight too.

## Enable notifications

Use the Push Notifications capability and an app provisioning profile with
`aps-environment` for the exact signed iOS bundle. TestFlight uses production APNs.
Use a different deployment and data directory for development tests.

Provide these values through the hosting environment. Mount the provider key
file read-only and keep it out of source, build arguments and the client app.

| Setting | Value |
| --- | --- |
| `EMPIRES_APNS_KEY_ID` | APNs provider key identifier |
| `EMPIRES_APNS_TEAM_ID` | Apple Developer team identifier |
| `EMPIRES_APNS_TOPIC` | Exact bundle identifier of the signed app |
| `EMPIRES_APNS_KEY_FILE` | Absolute path to the private APNs `.p8` file |
| `EMPIRES_APNS_ENVIRONMENT` | `production` or `development` |

With no APNs settings the service runs for local development. Pending actions
still appear in Your Games. Partial configuration fails startup so a broken
credential setup is visible. Production acceptance requires a real notification
on a locked phone, opening its current authorized match after a cold launch.

The app shows Online Play only when the signed build supplies
`SETTLERS_ONLINE_SERVER_URL` with an HTTPS origin. In the ignored local
signing override, escape the URL's double slash with
`https:/$()/your-host.example`. For TestFlight set
`SETTLERS_ONLINE_PUSH_ENVIRONMENT = production` and choose
`Settlers/OnlinePushAndLiveSync.entitlements` when the build uses the
CloudKit ladder, or `Settlers/OnlinePush.entitlements` for push alone.
Leave the shared signing defaults as committed.

[Apple push capability and device registration](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns) · [Apple provider authentication](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns)
