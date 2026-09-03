#!/usr/bin/env bash
# Kill a dedicated simulator app at both atomic-save boundaries, then verify
# recovery in a different process. Probe data never shares the player's save.
set -euo pipefail

simulator="${1:?pass the dedicated QA simulator UDID}"
app="${2:?pass the freshly built Debug Settlers.app}"
device_name="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = [device for group in json.load(sys.stdin)["devices"].values() for device in group]
print(next(device["name"] for device in devices if device["udid"] == sys.argv[1]))' "$simulator")"
[[ "$device_name" == Empires*QA ]] || { echo "Refusing a non-QA simulator: $device_name"; exit 1; }
bundle="$(plutil -extract CFBundleIdentifier raw "$app/Info.plist")"
xcrun simctl boot "$simulator" 2>/dev/null || true
xcrun simctl bootstatus "$simulator" -b
xcrun simctl install "$simulator" "$app"
container="$(xcrun simctl get_app_container "$simulator" "$bundle" data)"

await_file() {
  local file="$1"
  for ((attempt = 0; attempt < 200; attempt++)); do
    [[ -f "$file" ]] && return 0
    sleep 0.1
  done
  echo "Timed out waiting for probe marker: $file" >&2
  return 1
}

launch_probe() {
  xcrun simctl launch "$simulator" "$bundle" -checkpoint-process-probe "$1" "$2"
}

# An absent running process is expected before the first probe.
xcrun simctl terminate "$simulator" "$bundle" 2>/dev/null || true
for boundary in before after; do
  probe_id="$(uuidgen)"
  directory="$container/Library/Application Support/CheckpointProcessProbes/$probe_id"
  launch_probe initialize "$probe_id"
  await_file "$directory/initialized"
  xcrun simctl terminate "$simulator" "$bundle"
  interrupted="$(launch_probe "$boundary" "$probe_id")"
  await_file "$directory/ready"
  xcrun simctl terminate "$simulator" "$bundle"
  recovered="$(launch_probe read "$probe_id")"
  [[ "$interrupted" != "$recovered" ]] || { echo "Recovery reused the interrupted process"; exit 1; }
  await_file "$directory/result"
  expected="0,0,0"
  [[ "$boundary" == before ]] || expected="1,1,1"
  actual="$(< "$directory/result")"
  [[ "$actual" == "$expected" ]] || { echo "FAIL $boundary: $actual != $expected"; exit 1; }
  echo "PASS $boundary replacement: revision,moves,settlements=$actual ($interrupted -> $recovered)"
  xcrun simctl terminate "$simulator" "$bundle"
done
