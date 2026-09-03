#!/usr/bin/env bash
# Kill a dedicated simulator app inside checkpoint and export boundaries, then
# inspect durable state from a different process. Probe data is isolated from
# player saves and every launch PID must differ from the interrupted writer.
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
  xcrun simctl launch "$simulator" "$bundle" -checkpoint-process-probe "$1" "$2" "$3"
}

run_interruption() {
  local scenario="$1" boundary="$2" expected="$3"
  local probe_id directory interrupted recovered actual
  probe_id="$(uuidgen)"
  directory="$container/Library/Application Support/CheckpointProcessProbes/$probe_id"
  launch_probe initialize "$scenario" "$probe_id" >/dev/null
  await_file "$directory/initialized"
  xcrun simctl terminate "$simulator" "$bundle"
  interrupted="$(launch_probe "$boundary" "$scenario" "$probe_id")"
  await_file "$directory/ready"
  xcrun simctl terminate "$simulator" "$bundle"
  recovered="$(launch_probe read "$scenario" "$probe_id")"
  [[ "$interrupted" != "$recovered" ]] || { echo "Recovery reused the interrupted process"; exit 1; }
  await_file "$directory/result"
  actual="$(< "$directory/result")"
  [[ "$actual" == "$expected" ]] || {
    echo "FAIL $scenario/$boundary: $actual != $expected" >&2
    exit 1
  }
  echo "PASS $scenario/$boundary: revision,moves,settlements,offers,pendingExports,logs,logMoves=$actual"
  xcrun simctl terminate "$simulator" "$bundle"
}

xcrun simctl terminate "$simulator" "$bundle" 2>/dev/null || true
for scenario in human bot; do
  run_interruption "$scenario" before "0,0,0,0,0,0,0"
  run_interruption "$scenario" after "1,1,1,0,0,0,0"
done
run_interruption automaticTrade before "0,1,0,1,0,0,0"
run_interruption automaticTrade after "1,2,0,0,0,0,0"
run_interruption export exported "1,0,0,0,1,1,0"
run_interruption export before "1,0,0,0,1,1,0"
run_interruption export after "2,0,0,0,0,1,0"
