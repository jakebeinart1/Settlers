# Development-card audit and integration contract

Base: `38f7885` (Build 16, per assignment). Worktree: `human-review-cards`.
Main owns compilation, project regeneration, simulator captures and gameplay taps.

## Source-backed cause

- `IMG_1702.PNG` and `IMG_1703.PNG` in Alex's Downloads show the same Year of
  Plenty changing NEW → READY. Its bright green rounded tile and tiny sparkle
  clash with the painted coastal scene, civilization colors and engraved gold.
- `Settlers/Theme/DevCardStyle.swift` maps Plenty to `.green` and `sparkles`.
  `PlayerHUDView.DevCardHUDTile`, `DevCardPopupView.DevCardHandTile`, and
  `DevCardArtwork` independently build colored rounded tiles around SF Symbols.
  There is shared metadata but no shared card face or emblem.
- Inventory's `ready` means held minus purchased, not playable now
  (`DevelopmentCardPresentationState.swift`). Both tile implementations infer
  READY from that number and ignore `status`. `DevCards.playStatus` also checks
  turn, prior card play, mandatory actions and legal choices. An older blocked
  card can therefore be advertised as READY.
- `DevelopmentCardOverlay` already owns persistent reveal acknowledgement,
  legal resource selection and a hugging/scrolling layout with pinned actions.
  Preserve those contracts. `PopupCard` is used by Trade and other popups;
  its implementation must remain unchanged.
- `design-references/STATUS.md` establishes texture plus native gold borders,
  strong silhouettes and scarce internal detail. The live asset catalog has
  commodity hex art and borderless painted textures, but no dedicated paintings
  for these five development cards.

## Design before implementation

Palette: coastal ink `#102238`, ivory `#F7E8C9`, engraved gold `#E3B95F`,
shield red `#843F38`, harvest pine `#31543D`, tribute violet `#594268`.
Road and VP use muted ochre, never readiness green. Existing civilization colors
continue to identify players; card colors identify effects within the private hand.
Type: New York/system serif for full titles and rules; scalable body/caption text
for inventory. Fixed small serif text only for the existing fixed-height HUD.

```
Inventory charter                 Detail / purchase charter
[emblem] Full card name   ×count   [large effect emblem in painted gold frame]
         effect summary           Full title
         READY / NEW / reason     Exact effect + typed restriction
                                 Resource choices where required
                                 [pinned Play / Continue / Close]
```

One reusable emblem and chrome family across inventory, purchase, play detail,
result and the additive HUD badge. The emphasis is the illustrated emblem:
native bold shield and twin roads, approved grain/wool harvest art, commodity
tribute around a gold coffer, and a civic monument. Avoid concentric circles,
generic sparkles, neon colors and a wall of miniature rounded tiles.
Review against brief: use the established coastal texture and engraved frame,
not a new parchment UI or ornamental fantasy font. Keep rules readable outside
the illustration and keep disabled cards inspectable at full contrast.

## Acceptance (main must run)

1. All five cards have a readable full title, exact effect, count and distinct
   coherent emblem. Purchase/detail/result reuse the same emblem and chrome.
2. Mixed older/new stacks show both counts. READY is reserved for `.playable`;
   blocked entries expose the canonical reason and new count. VP says passive
   and never offers Play. A fresh reveal still says new even with an older copy.
3. Existing purchase persistence and acknowledgement tests remain valid.
   Knight retains cancel/confirm and theft; Road Building retains undo/clear and
   commits both roads together; Monopoly includes zero-card results; Plenty
   still requires exactly two available cards and permits two of one resource.
4. At 375×667 and accessibility text size, full titles/reasons wrap, inventory
   scrolls, and Close/Continue/Play remain reachable. Outside taps cannot consume
   a reveal. No board or below-board frame changes.
5. HUD replacement stays exactly 54×44. Preserve its action and existing
   accessibility identifier. Disabled means disabled for play, not inspection.
6. Main runs `DevelopmentCardDisplayTests`, `DevelopmentCardJourneyTests`,
   `DevelopmentCardFlowTests`, `DevelopmentCardAppearanceTests`, and viewport
   invariance suites, then captures all five detail/reveal states and taps flows.
   Palette tests reject old neon Plenty; UI status/value tests fail against the
   old inventory's missing typed accessibility value and misleading READY label.

## Artwork and verification limits

No new raster generation is necessary for this implementation. Dedicated painted
Knight/Road/Monopoly/VP paintings remain optional art work, not an assumed asset.
If commissioned, prompt: “Four separate square transparent game emblems: bold
ivory shield with red banner; two connected ochre stone roads; gold tribute coffer
with resource hex tokens; ivory civic monument with gold laurel. Match Empires'
approved painted coastal resource art, heavy dark outlines, broad clean shaded
color masses, minimal internal detail. No text, sparkle, UI frame or background.”
Use the available image_gen tool and imagegen skill only.

Builds/tests/screenshots are intentionally deferred by the serialized-slot
instruction. Local lint is not gameplay verification.

## Exact integration for main

Cherry-pick this scoped commit, then regenerate the project in main's reserved
checkout so Xcode sees the four new view/theme files and dedicated tests.
There are no changes to `project.yml` or `project.pbxproj` in this branch.

In `Settlers/Views/PlayerHUDView.swift`, in `HumanPlayerPanel`'s
`ForEach(devCardRows)` (base line 264), replace only the view name:

```swift
DevCardHandBadge(item: row) {
    onOpenDevCards(row.type)
}
```

Remove the now-unused private `DevCardHUDTile` declaration (base lines 346–390).
Keep `HUDCardStyle`: `ArmyHUDTile` still uses it. The new badge owns the same
54×44 layout, action and `dev-cards.tile.<type>` identifier. Single stacks show
READY/NEW/VP/WAIT/USED; mixed stacks use `1R · 1N` or `1H · 1N` to keep both
counts legible, with full words and the exact disabled reason in accessibility.
No GameView, GameViewModel, ContentView, ResourceChip, TradePopup or HUD layout
edits are needed. Existing overlay initializer/callbacks remain compatible.

Implementation files: `DevCardArt.swift` (emblem/face/chrome),
`DevCardInventoryView.swift` (inventory and additive hand badge),
`DevCardResourceChoice.swift` (approved commodity art in the card chooser),
`DevCardDisplay.swift` (typed status copy), `DevCardStyle.swift` (palette), and
`DevCardPopupView.swift` (wiring and scrolling result acknowledgement).
`PopupCard`'s declaration and implementation remain byte-for-byte unchanged.

New app tests: `DevelopmentCardDisplayTests`. New UI tests:
`DevelopmentCardAppearanceTests`. The existing blocked mixed-stack assertion
in `DevelopmentCardFlowTests` now checks the exact typed value instead of READY.
Run these alongside the existing journey/flow and viewport suites. Inspect
375×667 and accessibility-size layouts: the larger inventory uses horizontal
scrolling and the detail uses the existing vertical fallback. Capture empty
hand, mixed/new/blocked/VP stacks and each reveal/detail/result. Taps, not lint,
are required before claiming gameplay acceptance.

Static verification: changed-file SwiftLint passed with zero violations; diff
whitespace check passed. A source comparison against `38f7885` confirmed the
shared `PopupCard` implementation is unchanged. The chooser retains all five
bank/selected counts and callbacks while using painted commodity art. New
selected-choice identifiers (`dev-cards.selected.<resource>`) support the UI
regression for removing and reselecting a duplicate Plenty resource. No build,
Swift tests, cache work or simulator operations were run in this worktree.
