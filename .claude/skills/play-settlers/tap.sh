#!/usr/bin/env bash
# Tap the iPhone 17 Pro simulator at a coordinate given in DEVICE PIXELS, as
# read off a `simctl io screenshot` (1206x2622 on this device).
#
# The device screen's rect on the desktop is measured from the accessibility
# tree rather than assumed: a hardcoded bezel offset breaks the moment the
# window moves. The window is named EXACTLY - three simulators are booted and
# "window 1" was resolving to an iPhone 17 Pro *Max*, so every tap landed on
# the wrong control of a device we were not screenshotting.
set -euo pipefail
WINDOW="iPhone 17 Pro – iOS 26.5"   # note: en dash, as Simulator writes it
PX=$1; PY=$2
read -r SX SY SW SH <<<"$(osascript <<AS
tell application "System Events" to tell process "Simulator"
  set w to window "$WINDOW"
  perform action "AXRaise" of w
  set img to image 1 of group 1 of group 1 of group 1 of group 1 of group 1 of group 1 of w
  set p to position of img
  set s to size of img
  return ((item 1 of p) as string) & " " & ((item 2 of p) as string) & " " & ((item 1 of s) as string) & " " & ((item 2 of s) as string)
end tell
AS
)"
X=$(python3 -c "print(int($SX + $PX * $SW / 1206.0))")
Y=$(python3 -c "print(int($SY + $PY * $SH / 2622.0))")
cliclick "c:$X,$Y"
