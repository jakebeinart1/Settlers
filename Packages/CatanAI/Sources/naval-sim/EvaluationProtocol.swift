import Foundation

/// Preregistered before the first naval measurement, 2026-10-04.
///
/// Twelve cells: NavalMapFamily.allCases order × fog [true,false] × wild
/// [true,false]. For cell c, development seeds are 700000 + c*100 ..< +100.
/// Held-out seeds are 800000 + c*1000 ..< +11 at three players and ..< +7 at
/// four. Every held-out seed has every occupied focal chair in both arms:
/// Expert versus otherwise-identical naval Traditional opponents; all
/// Traditional control. Balanced personalities throughout. This yields
/// 396/arm at three and 336/arm at four, exceeding the conservative two-arm
/// 80%-power planning counts for a 10-percentage-point difference. Never pool
/// table sizes. Report Wilson win intervals and seed-cluster paired difference
/// intervals, cell results, all-chair coverage, and decisive rates. A strength
/// claim requires >=10pp improvement and a difference interval excluding zero
/// at BOTH table sizes; cells are diagnostic, not individually powered.
///
/// Before development measurement: commit all engine/policy sources, build
/// Release once, copy naval-sim to a retained artifact, and record source and
/// SHA256 artifact hashes. That fully naval-capable Traditional anchor is
/// frozen thereafter. Any revised opponent invalidates its comparisons.
/// Candidate hashes are recorded separately. No legacy Expert strength claim.
///
/// Functional rejection: any illegal action, hidden-information invariance
/// failure, response RNG consumption, forced action-cap termination, or a
/// within-turn idle sailing/trading cycle or duplicate proposal rejects the build.
/// Trading cycle means returning to an earlier exact hand before any public
/// production/building/card/fleet opportunity changes. Observed match completion
/// must be >=99% within 6000 committed actions across ALL family/toggle/table
/// cells, with every incomplete trajectory inspected. Complete games alone
/// determine wins; null winners are never scored using VP margins. Purposeful
/// fixtures must cover both tiers buying/sailing/revealing/founding, scarce
/// bank choice, capture, trade funding, cards, discard, and immediate victory.
///
/// Host Release decision budget: p95 <=50ms and p99 <=150ms. These bounds keep
/// policy computation comfortably below presentation pacing; they do not
/// certify physical-phone latency. Full app native gameplay, resumed matches,
/// screenshots, and phone measurements are separate product acceptance.
/// Aggregate per-decision counts above 50/150ms determine the percentiles;
/// also retain per-game tails so a rare slow phase cannot disappear silently.
///
/// Additional product hypothesis, before its first run: at seed 700003+c*100
/// rotate one fully funded land-only Traditional through all 3/4 chairs against
/// naval Traditional. Report its win/decisive intervals separately by table
/// size and compare expedition adoption in naval controls. This 36/48-game
/// development probe is diagnostic, not a powered 10pp strength confirmation.
///
/// Version 3, revised BEFORE any held-out run: a strict sailing revisit is
/// retained as raw evidence, while an idle revisit requires no intervening
/// revealed terrain, fresh building access or fleet ownership/purchase change.
/// Coordinates, steps, resources, logs and counters never reset this detector;
/// city upgrades retain the building total. Independent destination progress
/// counts newly revealed terrain or a shorter public sea route to an available
/// overseas settlement site. The motivating DEVELOPMENT trace is seed700000,
/// 3-seat all-Expert archipelago/fog-on/wild-on, actions610–620: ship0 sails
/// (2,2)→(2,3), founds a colony at action613, then returns (2,2) toward the next
/// opportunity. Forbidding that useful backtracking would punish completing an
/// expedition. Earlier returns without a colony/discovery remain rejected.
/// Schema3 also corrects colony telemetry: it requires overseas revealed LAND
/// at radius>=5, excluding ordinary home coasts touching ring-three ocean.
///
/// Corrected anchor, frozen before Expert-only refinement and before ANY held-out
/// observation: source a316139bb2daa22d7224c19953f4a2e32c699c2f, Release SHA256
/// 1b0117a4d44fbe4888ab4868f7c4cb0a22001213766ea284bc4b9c4afa9bd582.
/// Earlier development artifacts remain retained, but their known-colony-win,
/// dominant-landing and known-VP-prior bugs disqualify them as final opponents.
/// The control arm runs this retained binary; the candidate artifact's manifest
/// separately pins its committed source and binary hash BEFORE confirmation.
/// Traditional trajectories must match the anchor across all twelve development
/// cells at both table sizes before an Expert candidate reaches confirmation.
///
/// Expert development refinement addresses observed conversion gaps, not extra
/// exploration rewards: seed700901/chair3 buys a third hull at action737 at11VP
/// despite two ready ships; action847 at13VP fails to fund the card draw that its
/// direct purchase valuation treats as urgent. Recipe values now include proven
/// finishing points/draw chances and public race urgency; extra hulls price only
/// marginal public access, retain no renewed first-purchase bonus after capture,
/// and discount capture exposure until a funded landing. A bounded public sea
/// path also identifies guaranteed same-turn colony wins without sampling fog,
/// future dice or decks. Traditional rules and the10pp/CI gates remain frozen.
enum EvaluationProtocol {
    static let version = 3
    static let actionLimit = 6000
    static let developmentBase: UInt64 = 700_000
    static let heldOutBase: UInt64 = 800_000
}
