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

Confirmed by playing it, not by reading the code: **one human seat and three
heuristic bots.** `GameViewModel.makeSession` gives a `HeuristicPolicy` to every
seat except `humanPlayer`, so `GameSession.step()` stops and hands control back
on the human's turn. With "Randomize Seat" on (the default) the human is a
random one of the four seats, so do not assume seat 0.

The bots have personalities and speak in character - an Aztec bot opens a trade
with *"The sun god demands this trade."* A bot round takes roughly 20-30 seconds
of wall clock, because pacing (600ms between bot moves, a pause before a bot
answers an offer) lives in the view model on purpose. Budget for that: a tap
that ends a turn will not show a result for half a minute.

## Setup

There is no `idb` and no XCUITest target in this repo. Taps go through
`cliclick` against the Simulator window, which is why coordinates need care.

```bash
brew install cliclick     # if missing
```

Build, install and launch with the `run-settlers` skill first.

## Tapping

`tap.sh` beside this file takes **device pixel** coordinates - the numbers you
read straight off a `simctl io screenshot`, which is 1206x2622 on an iPhone 17
Pro. It measures where the device screen sits on the desktop from the
accessibility tree and converts.

```bash
.claude/skills/play-settlers/tap.sh 976 2391    # End Turn
xcrun simctl io <UDID> screenshot --type=png /tmp/after.png
```

Read the screenshot back. Always. The tap is the cheap part.

### Two traps that cost real time here

**Name the window exactly.** Several simulators are usually booted, and
`window 1` is whichever the Simulator app feels like. It resolved to an *iPhone
17 Pro Max* while every screenshot came from the *iPhone 17 Pro*, so taps landed
on the wrong control of a device nobody was looking at - and the symptom was not
an error, it was End Turn opening the Trade sheet. `tap.sh` names the window and
raises it first. The name uses an en dash (`iPhone 17 Pro – iOS 26.5`), not a
hyphen.

**Never hardcode the bezel offset.** The device screen's rect is read from the
accessibility tree every tap. A constant works until the window moves.

## Coordinates that stay put

Device pixels on iPhone 17 Pro, from the main game screen:

| Control | x | y |
|---|---:|---:|
| Trade / Build / End Turn (or Roll Dice) | 225 / 603 / 976 | 2391 |
| Accept an inline trade offer (green tick) | 1083 | 2384 |
| Decline an inline trade offer (red cross) | 973 | 2384 |
| Menu (hamburger) | 1120 | 723 |

The bottom row's third button changes label - **Roll Dice** before the roll,
**End Turn** after - but not position. Trade greys out until the dice are
rolled, which is correct and not a bug.

## Reading a game state from a screenshot

- Top row: the three bot cards, each with victory points, card count, dev cards,
  longest road and knights.
- Left of the board: the last roll, with recent rolls faint underneath.
- Right: bank stock per resource, then the dev deck count.
- Bottom purple panel: your own holdings. **The five resource counts are bare
  coloured squares with no labels** - brick, lumber, ore, grain, wool in that
  order. This is a known UI complaint, not a rendering fault.

## What this cannot do

It drives the simulator only. Getting onto a real iPhone is blocked on signing -
see `run-settlers` for why. Playing a full game to a win is ~476 moves and
several minutes of bot pacing; prove a specific behaviour instead of grinding to
a winner, unless the ask really is a full playthrough.
