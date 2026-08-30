#!/usr/bin/env bash
# Tap the simulator at a coordinate given in DEVICE PIXELS, as read off a
# `simctl io screenshot` (1206x2622 on an iPhone 17 Pro).
#
# The device screen's rect on the desktop is measured from the accessibility
# tree rather than assumed: a hardcoded bezel offset breaks the moment the
# window moves.
#
# The target window is resolved by INDEX, found by prefix match, rather than by
# its full name. Two reasons, both hit in practice:
#   - Several simulators are usually booted, and `window 1` is whichever the
#     Simulator app feels like. It resolved to an iPhone 17 Pro *Max* while
#     every screenshot came from the iPhone 17 Pro, so taps landed on the wrong
#     control of a device nobody was looking at - and the symptom was not an
#     error, it was End Turn opening the Trade sheet.
#   - Matching the full name is fragile: Simulator writes it with an EN DASH
#     ("iPhone 17 Pro – iOS 26.5"), and `window "..."` fails with -1728 if that
#     character does not survive the shell round-trip intact.
#
# DEVICE may be overridden. It is matched as "<DEVICE> " followed by a
# NON-LETTER, which is what stops "iPhone 17 Pro" from also matching
# "iPhone 17 Pro Max" - a plain prefix test matches both, and picking the Max
# is exactly the silent-wrong-device failure above.
set -euo pipefail
DEVICE="${DEVICE:-iPhone 17 Pro}"
PX=$1; PY=$2

read -r SX SY SW SH <<<"$(osascript <<AS
tell application "System Events" to tell process "Simulator"
  set target to 0
  repeat with i from 1 to (count of windows)
    set n to name of window i
    if n starts with "$DEVICE " and (count of n) > ((count of "$DEVICE") + 1) then
      set nextChar to character ((count of "$DEVICE") + 2) of n
      if nextChar is not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" then set target to i
    end if
  end repeat
  if target is 0 then error "no Simulator window for $DEVICE - see the skill's recovery note"
  set w to window target
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
