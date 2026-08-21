---
name: run-settlers
description: Build, install, and launch the Settlers (Empires) iOS app on a real iPhone or the simulator, and how to screenshot it for visual QA. Use whenever asked to run/install/reinstall the app, put a build on the phone, or check how a change actually looks.
---

# Running Settlers (Empires)

This is an Xcode/SwiftUI iOS app (`Settlers.xcodeproj`, scheme `Settlers`,
bundle ID `com.jakebeinart.settlers`). Two targets: the Simulator (fast,
always available, good for screenshots) and Jake's real iPhone (what he
actually plays on - use this when he asks to "install"/"reinstall"/"put it
on my phone").

## Real device (preferred when Jake asks to install/reinstall)

**`xcrun xctrace list devices` often reports the iPhone as "offline" even
when it's perfectly reachable over Wi-Fi.** Don't trust that list on its
own - check `devicectl` instead, which is what actually matters for
build/install:

```bash
xcrun devicectl list devices
```

Look for a row like:

```
Name     Hostname                  Identifier                              State
iPhone   iPhone.coredevice.local   D32E3710-9D4C-529D-916B-9D3CBC4E9FD5    available (paired)
```

If it says `available (paired)`, it's installable - the `xctrace`
"offline" reading was a red herring. Use that `Identifier` (UDID) as the
build destination:

```bash
cd "/Users/jakeb/Documents/Catan Game"
xcodebuild -project Settlers.xcodeproj -scheme Settlers \
  -destination 'id=<UDID>' -configuration Debug build
```

`project.yml` already has automatic signing configured
(`DEVELOPMENT_TEAM: KDM65HE483`, `CODE_SIGN_STYLE: Automatic`) so this
builds and codesigns for the device without any extra setup. Then install:

```bash
xcrun devicectl device install app --device <UDID> \
  "/Users/jakeb/Library/Developer/Xcode/DerivedData/Settlers-*/Build/Products/Debug-iphoneos/Settlers.app"
```

(The exact `DerivedData/Settlers-<hash>` folder name varies by machine -
glob it or read it back from the `xcodebuild` output above.) That's it -
Jake opens it from the home screen himself; `devicectl` doesn't need a
separate launch step for a manual install like this.

If `devicectl list devices` ever shows the iPhone as genuinely
unreachable (not `available`), only then ask Jake to check the cable /
Wi-Fi / that the phone is unlocked - don't ask preemptively just because
`xctrace` said offline.

## Simulator (for visual QA / screenshots, no device needed)

```bash
xcrun simctl list devices available | grep iPhone   # pick a booted-or-bootable UDID
xcrun simctl boot <SIM_UDID>                         # harmless if already booted
open -a Simulator
xcodebuild -project Settlers.xcodeproj -scheme Settlers \
  -destination 'platform=iOS Simulator,id=<SIM_UDID>' -configuration Debug build
xcrun simctl install <SIM_UDID> \
  "/Users/jakeb/Library/Developer/Xcode/DerivedData/Settlers-*/Build/Products/Debug-iphonesimulator/Settlers.app"
xcrun simctl launch <SIM_UDID> com.jakebeinart.settlers
xcrun simctl io <SIM_UDID> screenshot /path/to/out.png
```

**Don't drive the simulator with blind mouse clicks** (`osascript ...
click at {x,y}`) - the Simulator window's screen coordinates don't map
cleanly onto the device's logical points, clicks can land on whatever
Mac window happens to be frontmost instead, and there's no accessible
element tree to click into by name (SwiftUI content shows up as one
opaque canvas to System Events). It's unreliable and, worse, it can
interact with the user's real desktop apps.

Instead, use the `-qaAutoStart` launch argument (added to
`ContentView.swift` for exactly this): it skips `MainMenuView` and lands
straight on the board, so a screenshot can be taken right after launch
with no simulated taps at all:

```bash
xcrun simctl launch <SIM_UDID> com.jakebeinart.settlers -qaAutoStart
```

This only fires when that literal argument is passed - it can never
affect a real player.

## Verifying a change actually rendered

After installing (device or simulator), take a screenshot and read it
back with the `Read` tool rather than assuming a build succeeding means
the visual change is correct - see `design-references/STATUS.md` for the
project's asset/UI conventions this app expects screenshots to match
against.
