---
name: play-settlers
description: Actually play the Settlers ("Empires") app in the simulator by tapping controls, not just screenshotting it. Use when asked to "play a turn", "play a game", "end the turn", "accept the trade", "click through it", "does the game actually work end-to-end", "is it AI or human players", or when a change needs proving through the UI rather than through a test. Also use before claiming any gameplay behaviour works, since a green build and a correct-looking screenshot both survive a game that cannot be played. Complements run-settlers, which builds and launches but never taps.
---

# Playing Empires through the simulator

`run-settlers` gets the app onto a screen. This drives it.

The distinction matters more than it sounds. A screenshot proves a frame
rendered; it does not prove the turn advances, the bots move, a trade can be
accepted, or that control comes back to the player afterwards. Those are the
things that break, and only tapping finds them.

## What the game actually is

Empires supports three- or four-seat tables and one or more local hot-seat human
players; remaining seats use heuristic bots. Do not assume seat 0 is human.

The bots have personalities and speak in character - an Aztec bot opens a trade
with *"The sun god demands this trade."* A bot round takes roughly 20-30 seconds
of wall clock, because pacing (600ms between bot moves, a pause before a bot
answers an offer) lives in the view model on purpose. Budget for that: a tap
that ends a turn will not show a result for half a minute.

## Setup

Use the native `SettlersUITests` target for repeatable setup, settings, placement,
and cold-resume interaction. Build, install, and launch with `run-settlers` for
manual exploratory play.

## Automated interaction

Run a focused UI flow without inheriting simulator state:

```bash
xcodebuild test -project Settlers.xcodeproj -scheme Settlers \
  -destination 'platform=iOS Simulator,id=<SIM_UDID>' \
  -only-testing:SettlersUITests/MainMenuFlowTests
```

Independent tests launch with `-ui-testing-reset`; a cold-resume relaunch uses
`-ui-testing` alone so the first process's save survives. Stable identifiers are
defined in `Settlers/Testing/AccessibilityID.swift`.

## Manual tapping

Use the visible Simulator window for exploratory play. Do not use `cliclick`,
AppleScript coordinates, or a hardcoded bezel offset: those can target a
different simulator or another desktop app. Capture and inspect a screenshot
after the interaction whenever the visual result matters.

## Reading a game state from a screenshot

- Top row: the three bot cards, each with victory points, card count, dev cards,
  longest road and knights.
- Left of the board: the last roll, with recent rolls faint underneath.
- Right: bank stock per resource, then the dev deck count.
- Bottom purple panel: your own holdings. **The five resource counts are bare
  coloured squares with no labels** - brick, lumber, ore, grain, wool in that
  order. This is a known UI complaint, not a rendering fault.

## What this cannot do

Native UI coverage is intentionally focused; it does not yet play a complete
match, exercise every trade/robber/discard branch, or replace human visual
judgment. Device signing details live in `run-settlers`.
