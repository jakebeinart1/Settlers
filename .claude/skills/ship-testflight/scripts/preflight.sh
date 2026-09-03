#!/bin/bash
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
local_signing="$repo/Settlers/Signing.local.xcconfig"
private_key="/Users/alex/.appstoreconnect/private_keys/AuthKey_R7AQ2QHN3X.p8"
profile="/Users/alex/Library/Developer/Xcode/UserData/Provisioning Profiles/SKS4Q6NL6V.mobileprovision"

failures=0

require_file() {
    if [[ ! -f "$1" ]]; then
        echo "FAIL  $2: missing $1"
        failures=$((failures + 1))
    else
        echo "PASS  $2"
    fi
}

require_file "$local_signing" "Alex signing override"
require_file "$private_key" "App Store Connect private key"
require_file "$profile" "Empires App Store provisioning profile"

if [[ -f "$local_signing" ]] \
    && grep -q '^SETTLERS_DEVELOPMENT_TEAM = HXB9F28LHR$' "$local_signing" \
    && grep -q '^SETTLERS_BUNDLE_ID = com.alexchandler.empires$' "$local_signing"; then
    echo "PASS  signing override identity"
else
    echo "FAIL  signing override must name HXB9F28LHR and com.alexchandler.empires"
    failures=$((failures + 1))
fi

if security find-identity -v -p codesigning \
    | grep -q 'iPhone Distribution: Alex Chandler (HXB9F28LHR)'; then
    echo "PASS  existing distribution identity"
else
    echo "FAIL  no existing Alex distribution identity; do not create or revoke one"
    failures=$((failures + 1))
fi

if [[ "$failures" -ne 0 ]]; then
    exit 1
fi

node "$repo/.claude/skills/ship-testflight/scripts/read-asc-status.mjs"
