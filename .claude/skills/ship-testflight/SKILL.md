---
name: ship-testflight
description: Build, upload, and verify an Empires iOS build in TestFlight. Use when asked to ship, upload to TestFlight, cut a build, put the latest build on a real phone, or diagnose why TestFlight still shows an older build. This is the Alex-owned com.alexchandler.empires distribution path; it must never change Jake's committed signing defaults.
---

# Ship Empires to TestFlight

The outcome is not “archive succeeded.” A ship is complete only after the
Release gate passes, the build number is unique, Apple accepts the upload, the
build reaches VALID, and the intended tester can see it.

## Verified account and artifact state

On 2026-09-02 the workflow registered bundle identifier 7DD387DC4H, created
active profile SKS4Q6NL6V (“Empires App Store”) against the already-existing
HRFB9B4356 distribution certificate, archived Release successfully, and
exported /tmp/empires-release/export/Settlers.ipa. Inspection proved
beta-reports-active=true, get-task-allow=false, no ProvisionedDevices, and a
valid strict code signature. The App Store Connect app record remained absent,
so nothing was uploaded or described as shipped.

## Ownership boundary

Jake's committed defaults remain in Settlers/Signing.xcconfig. Alex's team
HXB9F28LHR and bundle id com.alexchandler.empires belong only in the
gitignored Settlers/Signing.local.xcconfig. Never edit Jake's defaults to ship
Alex's build.

Run the read-only preflight first:

    .claude/skills/ship-testflight/scripts/preflight.sh

If it reports that the App Store Connect app record is absent, stop. Creating
that record is the only founder action this workflow cannot perform. In App
Store Connect choose Apps → + → New App and use:

- Platform: iOS
- Name: Empires
- Primary language: English (U.S.)
- Bundle ID: com.alexchandler.empires
- SKU: empires-ios
- User access: Full Access

Do not select or reuse another app's bundle id. After the record exists, rerun
preflight and use the numeric app id it prints.

## Release ladder

1. Run scripts/gate.sh --debug-app.
2. Run all native UI flows on a fresh simulator install. A green package suite
   does not prove New Game, setup placement, hot-seat handoff, or settings.
3. Inspect current crash reports before and after a Release launch. A new report
   is a failed release.
4. Read the latest build number from App Store Connect. Increment
   CURRENT_PROJECT_VERSION in project.yml; never edit the generated pbxproj.
5. Commit the version bump on a branch and regenerate with xcodegen generate.
6. Archive for generic/platform=iOS with manual signing, profile
   “Empires App Store,” and the existing distribution identity. Never use a
   command that creates or revokes a distribution certificate.
7. Export with ExportOptions.plist. Inspect the embedded profile:
   beta-reports-active must be true, get-task-allow false, and
   ProvisionedDevices absent.
8. Upload by exporting a fresh copy of the options plist with
   destination=upload, supplying the existing App Store Connect API key.
   Never copy the private key into this repository.
9. Poll App Store Connect until the exact version/build is VALID or a terminal
   failure. Silence is not success.
10. Confirm an internal group with hasAccessToAllBuilds=true exists and report
    which tester Apple says can access the build.

The API key currently available on this machine is team-scoped and may be
reused; its id and issuer are non-secret metadata in the preflight script. The
private key remains outside this repository.

## Stop conditions

- No App Store Connect record: provide the exact form above.
- No existing distribution identity: stop; do not mint or revoke one.
- No App Store provisioning profile: create Empires App Store through Apple's
  Profiles API using the existing HRFB9B4356 certificate. Never use automatic
  signing as a workaround because it may create another certificate.
- Reused build number: bump project.yml before archiving.
- Upload accepted but processing not VALID: keep polling; do not call it
  shipped.
