# App Store IP review: trademarks, rules text, naming (2026-09-28)

Asked by Jake alongside the How to Play screen: "are we good to go" to publish on the App
Store without crossing any legal line. This is research, not legal advice. Before a paid
launch, an hour with an IP lawyer is cheap next to a takedown.

## Verdict

**Mostly yes, with one thing fixed in code and four things to decide before submitting.**
The game itself (its rules and mechanics) is free to use. The risk sits in *names* and
*look*, and the app is already mostly clean on both.

## What the law protects, and what it does not

| Thing | Protected? | Source |
|---|---|---|
| Rules, mechanics, "how to play" | **No.** Copyright "does not protect the idea for a game, its name or title, or the method or methods for playing it." | US Copyright Office circular FL-108 |
| The *text* of a rulebook | **Yes.** The wording is protected; the rules it describes are not. | FL-108 |
| Board, card and box artwork | **Yes.** | FL-108; CATAN GmbH's IP guidelines |
| A game's overall look and feel, when copied closely | **Can be.** *Tetris Holding v. Xio* (D.N.J. 2012): mechanics unprotected, but a clone copying the pieces' look, colours and board layout infringed. | Tetris v. Xio |
| "CATAN" and "Settlers of Catan" | **Yes, registered trademarks.** They cannot be used to name or promote a product. | CATAN GmbH guidelines; USPTO |
| App name / icon using another company's brand | **App Store rejection.** Guideline 4.1(c) (added Nov 2025) and 5.2.1. | Apple App Review Guidelines |

**The practical risk is bigger than the legal one.** In 2011 CATAN GmbH's lawyers got
"Island Settlers" pulled from Android with a cease-and-desist letter that commentators
(Public Knowledge, Techdirt) judged legally weak. The store acted on the complaint anyway.
The defence is to give them nothing to complain about.

## Where Empires stands

- **Name: "Empires".** No Catan mark in it. ✅
- **Art: original.** Tiles, pieces and screens were generated for this project
  (`design-references/STATUS.md`); none is CATAN artwork. ✅ Resource-card art was
  "supplied by Jake", so check its source yourself.
- **Rules text: original.** The new How to Play copy (`HowToPlayContent.swift`) was
  written for this app in its own words (Army cards, Vast, Conquest, civilizations), not
  paraphrased from a rulebook. ✅
- **User-facing "Catan": one hit, fixed.** New Game's Board help said "the classic fixed
  layout every game of Catan opens on". It now says "the same fixed layout every game".
  A grep of every Swift string literal found no other user-facing use.
- **Mechanic names** (Knight, Road Building, Year of Plenty, Monopoly, Longest Road,
  Largest Army, Victory Point, robber, port). Short names and phrases are not
  copyrightable, and colonist.io, which is unlicensed, has used these same names for years.
  Low risk. The exception is **"Monopoly"**, which is Hasbro's trademark for a board game.
  Using it as the name of a card effect is descriptive use and probably fine, but renaming
  it (to "Tribute", say) removes the question.

## To decide before submitting (not changed here: each one is Jake's call)

1. **Store listing.** Keep "Catan" and "Settlers of Catan" out of the name, subtitle,
   keywords, screenshots and description. That includes "Catan-like" and "like Settlers".
   Keywords are where people slip.
2. **Bundle ID `com.jakebeinart.settlers`.** Users never see it, but it **cannot be
   changed after the first upload.** Separately, "The Settlers" is Ubisoft's
   video-game trademark. Consider `com.jakebeinart.empires` before the first submission.
   Alex's TestFlight path already uses `com.alexchandler.empires`. Module and type names
   (`CatanEngine`, `CatanTheme`, `Settlers.xcodeproj`, `catan_save.json`) never reach the
   store listing or the UI, so renaming them is housekeeping, not compliance.
3. **"Empires" itself.** Generic, but crowded: "Age of Empires" (Microsoft), "Forge of
   Empires", "Empires & Puzzles". App Store names must be unique, so a bare "Empires" is
   likely taken. Search USPTO and App Store Connect and plan a distinctive full name.
4. **The Standard board.** It is the classic fixed opening layout. A tile arrangement is
   very likely unprotectable (it is functional, and a fact about a game), but it is the one
   place the app reproduces a specific CATAN arrangement rather than a mechanic. To be
   fully conservative, alter a few tiles or make Randomized the default.

## Sources

- US Copyright Office, FL-108 "Games": https://www.copyright.gov/register/tx-games.html
- CATAN GmbH, IP guidelines: https://www.catan.com/guidelines-dealing-intellectual-property-catan
- Public Knowledge on the Island Settlers takedown: https://publicknowledge.org/settlers-of-catan-makes-legal-threats-can-it-back-them-up-hint-no/
- Techdirt, same incident: https://www.techdirt.com/2011/02/22/how-lawyers-settlers-catan-abuse-ip-law-to-take-down-perfectly-legal-competitors/
- Tetris Holding v. Xio Interactive: https://en.wikipedia.org/wiki/Tetris_Holding,_LLC_v._Xio_Interactive,_Inc.
- Apple App Review Guidelines (4.1, 5.2.1): https://developer.apple.com/app-store/review/guidelines/
- 9to5Mac on guideline 4.1(c): https://9to5mac.com/2025/11/13/apple-tightens-app-review-guidelines-to-crack-down-on-copycat-apps/
- ABA Landslide, why videogame rules aren't copyrightable: https://www.americanbar.org/groups/intellectual_property_law/resources/landslide/archive/why-videogame-rules-are-not-expression-protected-copyright-law/
