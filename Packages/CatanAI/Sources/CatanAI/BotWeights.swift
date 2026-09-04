/// Every tuning constant the bot heuristics score with, in one value.
///
/// WHY THIS EXISTS. The weights used to be `private static let`s and bare
/// literals scattered across `PlacementHeuristics`, `ThreatAssessment`,
/// `BuildPlanner`, `TradeHeuristics`, `RobberHeuristics` and
/// `DevCardHeuristics`. You cannot sweep a constant you cannot name, and you
/// cannot serialise a configuration that does not exist as a value - so
/// tuning the opponent meant editing source and rebuilding, and comparing two
/// candidate bots meant comparing two git branches. Gathering them here makes
/// a bot's policy a piece of *data*: it can be varied per opponent, written to
/// disk by a training run, diffed, and replayed.
///
/// WHAT IS AND IS NOT IN HERE. Only *policy* - things a tuner is free to
/// change without the bot playing an illegal game. Values that are game
/// *rules* stay inline at their use site (a city producing double a
/// settlement, Longest Road's 5-segment minimum, Year of Plenty granting two
/// cards, the build costs in `Building`, the 7-card discard threshold). Those
/// belong to Catan, not to this bot, and a sweep that moved them would be
/// changing the game rather than the player.
///
/// DEFAULTS REPRODUCE TODAY'S BOT EXACTLY. Every default below is the literal
/// it replaced, so `BotWeights.default` is bit-for-bit the pre-extraction
/// policy. That property is what keeps the behaviour-fingerprint tests honest.
///
/// CODABLE CAVEAT. Encoding is complete, but Swift's synthesised
/// `init(from:)` does not fall back to a property's default value for a key
/// that is absent from the payload - so a decoded configuration file has to
/// carry *every* key, as one produced by encoding a `BotWeights` naturally
/// does. Hand-written partial override files are not supported.
///
/// Properties are `var` deliberately: a sweep reads as
/// `var w = BotWeights.default; w.tieMargin = 0.5`, which beats threading a
/// ~60-parameter initialiser through every call site.
public struct BotWeights: Codable, Sendable, Equatable {

    // MARK: - Placement scoring
    //
    // Consumed by `PlacementHeuristics.score`, which values a settlement spot.
    // Note that the pip counts themselves (6 and 8 being worth 5, and so on)
    // are NOT here: they are the dice probabilities, a fact about two six-sided
    // dice rather than an opinion about how to play.

    /// Extra value per pip sitting on a resource the player does not already
    /// cover, used for setup's second placement. Higher spreads a bot's
    /// opening across more resource types instead of stacking pips.
    public var newResourcePipBonus: Double = 0.3

    /// Value per distinct resource type a vertex touches. Higher favours
    /// three-different-tile corners over high-pip corners that double up.
    public var resourceDiversityBonus: Double = 0.5

    /// Value of sitting on a 3:1 any-resource port. Higher makes bots fight
    /// for port corners.
    public var genericPortBonus: Double = 0.5

    /// Value of sitting on a 2:1 resource-specific port. Higher still makes
    /// bots fight for port corners; it leads `genericPortBonus` because a 2:1
    /// rate is the better deal when it matches your production.
    public var resourcePortBonus: Double = 1.0

    // MARK: - Threat assessment
    //
    // Consumed by `ThreatAssessment`, the shared "how dangerous is this
    // player" model every other heuristic defers to instead of inventing its
    // own notion of the leader.

    /// Score per victory point a player holds. The dominant term by design -
    /// VP is the actual win condition. Higher makes bots track the scoreboard
    /// and ignore board position.
    public var victoryPointWeight: Double = 10.0

    /// Score per unplayed development card held. Higher makes bots more
    /// suspicious of a hand that could be hiding knights or VP cards.
    public var devCardWeight: Double = 1.5

    /// Score added for being one move from taking Largest Army or Longest
    /// Road that the player does not already hold. Each is worth 2 real VP the
    /// instant it flips, so a player poised to grab one is more dangerous than
    /// their current VP total says. Higher makes bots pre-empt milestone
    /// swings rather than react to them.
    public var milestoneSwingBonus: Double = 2.5

    /// Played-knight count at which a player is treated as poised to take
    /// Largest Army (and the count at or below which the current holder is
    /// treated as catchable). Lower makes bots start worrying about the army
    /// race earlier.
    public var armyMilestoneWatchKnights: Int = 2

    /// Road length at which a player is treated as poised to take Longest
    /// Road, floor-compared against the current holder's length. Lower makes
    /// bots start worrying about the road race earlier.
    public var roadMilestoneWatchLength: Int = 4

    /// Lower clamp on `relativeWeight`, the ratio of one opponent's threat to
    /// the average opponent's. Bounds how far a *harmless* opponent can damp
    /// an effect. Raising it toward 1.0 flattens the model into treating all
    /// opponents alike.
    public var relativeWeightFloor: Double = 0.4

    /// Upper clamp on `relativeWeight`. Bounds how far a runaway leader can
    /// amplify an effect, so one early-game outlier - the very first
    /// settlement placed, say - cannot produce an extreme swing. Higher lets
    /// bots gang up harder on a leader.
    public var relativeWeightCeiling: Double = 3.0

    /// Lower clamp on `ownStanding`, the ratio of a bot's own threat score to
    /// the average opponent's. Bounds how desperate a losing bot is allowed to
    /// read as. Lower lets a bot that is far behind take worse deals to catch
    /// up.
    public var ownStandingFloor: Double = 0.2

    /// Upper clamp on `ownStanding`. Bounds how comfortable a leading bot
    /// reads as, and doubles as the value returned when the field has scored
    /// nothing at all but this bot has - the top of the scale is the honest
    /// answer there. Higher makes a leading bot more protective of its lead.
    public var ownStandingCeiling: Double = 3.0

    // MARK: - Build planning
    //
    // Consumed by `BuildPlanner`, which scores every legal build move and
    // returns the best one worth taking.

    /// Minimum score a build candidate must clear to beat simply ending the
    /// turn and banking resources. Higher makes bots hoard.
    public var worthItThreshold: Double = 1.5

    /// How close to the top score a candidate must be to count as a genuine
    /// toss-up. Only ties inside this margin are broken randomly; anything
    /// outside it is picked deterministically, so a clearly-best move is never
    /// affected. Higher makes play more varied and less optimal.
    public var tieMargin: Double = 0.35

    /// Flat value of planting a new settlement, before production. Higher
    /// makes bots settle over everything else.
    public var settlementBase: Double = 3.0

    /// Constant added to `expansionBias` to form the multiplier on a new
    /// settlement's production score. Higher raises settlement value for every
    /// personality, narrowing what `expansionBias` differentiates.
    public var settlementProductionBase: Double = 0.5

    /// Fraction of a vertex's production value credited for denying it to a
    /// threatening opponent, scaled by that opponent's relative threat. Below
    /// 1.0 because taking a spot for yourself beats merely denying it. Higher
    /// makes bots block more.
    public var settlementDenialScale: Double = 0.4

    /// Flat value of upgrading to a city, before production. Higher makes bots
    /// upgrade over expanding.
    public var cityBase: Double = 2.5

    /// Constant term in a city's production multiplier. Higher raises city
    /// value for every personality.
    public var cityProductionBase: Double = 0.4

    /// How strongly `expansionBias` feeds a city's production multiplier.
    /// Lower than the settlement equivalent so `expansionBias` swings
    /// settlements more than cities, which is what makes it read as an
    /// *expansion* knob at all.
    public var cityProductionExpansionScale: Double = 0.5

    /// Flat value of a road, before any bonus. Roads are cheap groundwork, so
    /// this sits well under the settlement and city bases. Higher makes bots
    /// build aimless roads.
    public var roadBase: Double = 0.5

    /// How much of the best newly-reachable vertex's production score a road
    /// earns. Higher makes bots road toward good spots.
    public var roadReachableScale: Double = 0.2

    /// Value of a road that denies a threatening opponent a vertex they could
    /// reach next, scaled by that opponent's relative threat. Higher makes
    /// bots race opponents for contested spots.
    public var roadBlockingBonus: Double = 1.0

    /// Value of the exact road that would claim Longest Road right now,
    /// further scaled by the current holder's threat when there is one.
    /// Higher makes bots grab the bonus the moment it is available.
    public var longestRoadClaimBonus: Double = 2.5

    /// Flat bonus for a road that bridges two of the player's own currently
    /// disconnected road pieces (a settlement/stub each) into one - added on
    /// top of, not instead of, whatever the length-based claim/pursuit/
    /// defense bonus above already computes for the resulting chain.
    ///
    /// A bridging edge has both endpoints already inside the player's own
    /// network by definition, so it structurally can never earn
    /// `roadReachableScale`'s bestReachable term (nothing newly reachable)
    /// or `committedPathScale`'s path term (already at distance 0 to
    /// wherever `expansionTarget` picked, either way) the way a same-
    /// position simple extension into open territory can - so without this,
    /// a merge landing short of the 5-edge minimum reliably lost the scoring
    /// competition to a mundane extension of whichever stub looked
    /// marginally better that turn, and a bot could sit on two disconnected
    /// pieces indefinitely. Confirmed as a real, reproducible defect by a
    /// 90-game sim audit (2026-09-04): 53 player-instances ended the game
    /// with enough total road segments (9-13) to clear Longest Road, split
    /// across pieces whose longest single connected chain topped out at 3-4;
    /// separately reproduced in a real played game the same day (bot
    /// "Ragnar") where a comfortable existing lead made every road - bridge
    /// included - score identically to a pointless filler. Sized in the same
    /// range as `roadReachableScale`'s typical contribution, so a bridge is
    /// no longer structurally disadvantaged against an extension purely for
    /// lacking a term it can never earn. Higher makes bots merge fragmented
    /// networks more readily.
    public var longestRoadBridgeBonus: Double = 0.8

    /// Chain length (after the candidate road) at which a bot is treated as
    /// seriously pursuing Longest Road, and starts paying for the connective
    /// roads leading up to a claim rather than only the one that completes it.
    /// Lower makes bots commit to the road game earlier.
    ///
    /// A 2026-09-04 review flagged this gate as a theoretical source of
    /// "first two pursuit roads score too low to build" - left unchanged
    /// pending a confirmed repro, per the same empirical audit noted at
    /// `buildDevCardBase`. The confirmed defect this session actually found
    /// (bots ending with disconnected road fragments despite having enough
    /// total segments for Longest Road, sim-audited 2026-09-04: 53 cases
    /// across 90 games) is addressed directly by `bridgesOwnFragments`
    /// instead, which doesn't depend on this gate at all.
    public var longestRoadPursuitMinLength: Int = 3

    /// Chain length at which the pursuit ramp is worth zero; the bonus is
    /// `longestRoadPursuitScale * (lengthAfter - this)`. Kept separate from
    /// `longestRoadPursuitMinLength` so the gate and the ramp's shape can be
    /// swept independently. Higher flattens the ramp.
    public var longestRoadPursuitZeroLength: Int = 2

    /// Value per segment of the Longest Road pursuit ramp above
    /// `longestRoadPursuitZeroLength`. Higher makes bots chase the bonus
    /// harder as they approach it.
    public var longestRoadPursuitScale: Double = 0.3

    /// How far ahead of the closest rival a Longest Road holder can be and
    /// still bother defending. Longest Road only counts if held at game end,
    /// so defending a contested lead is real value while reinforcing an
    /// uncontested one is a wasted road. Higher makes bots defend leads nobody
    /// is threatening.
    public var longestRoadDefenseLeadGap: Int = 1

    /// Value of a road that actually extends a threatened Longest Road lead.
    /// Higher makes bots prioritise holding the bonus they already have.
    public var longestRoadDefenseBonus: Double = 1.2

    /// How many roads out `expansionTarget` searches for the single spot a
    /// bot aims its network at. Higher lets bots commit to more distant
    /// targets, at more search cost.
    public var expansionTargetMaxHops: Int = 4

    /// Production discount per hop of distance when choosing that target, so a
    /// mediocre-but-close spot can beat a great-but-far one. Higher makes bots
    /// aim closer.
    public var expansionTargetHopPenalty: Double = 0.5

    /// Numerator of the committed-path bonus, which pays `this / (distance +
    /// 1)` for a road that measurably closes the gap to the chosen expansion
    /// target. Higher makes road-building read as more purposeful and less
    /// opportunistic.
    public var committedPathScale: Double = 1.0

    /// Bonus per already-built road already leading toward a candidate
    /// `expansionTarget`, so a branch the bot has already invested in beats
    /// a marginally-better-scoring branch it hasn't started - real Catan
    /// strategy (and the JSettlers literature: Guhe & Lascarides 2014 names
    /// "frequently switching the high-level strategy" as a known defect of
    /// a from-scratch-every-turn planner) commits to one direction rather
    /// than re-optimizing from zero each turn. Confirmed via a real played
    /// game (12-point win, 2026-09-03): bots' road networks averaged 3
    /// branch junctions and 8-9 dead-end tips across only 13 roads each -
    /// a target with no memory of the previous turn's choice, recomputed
    /// symmetrically outward from every network vertex, has no reason to
    /// prefer extending an already-invested branch over starting a fresh
    /// one that happens to score a fraction higher. Higher makes bots more
    /// stubborn about a direction once they've started it; `0` restores the
    /// old memoryless behavior.
    public var expansionContinuityScale: Double = 0.4

    /// Flat value of buying a development card, as a *build* candidate.
    /// Higher makes bots spend spare ore/grain/wool on cards.
    ///
    /// A 2026-09-04 review flagged this as a theoretical suspect for
    /// crowding out Longest-Road connector roads (worked arithmetic showed
    /// `buyDevCard` outscoring one at several personality/length
    /// combinations) - but a 90-game empirical instrumented-harness audit
    /// specifically checking for that scenario found ZERO cases of
    /// `buyDevCard` actually displacing an available longest-road-clearing
    /// road, and a separate sim-harness audit found `buyDevCard` beating a
    /// legal build 0/100 times overall. Left at its original value on that
    /// evidence: the theoretical concern didn't manifest in play, so cutting
    /// it would move fingerprints to fix a problem that isn't observed.
    /// (The real, confirmed fragmentation defect is addressed instead via
    /// `BuildPlanner.bridgesOwnFragments` - see its doc comment.)
    public var buildDevCardBase: Double = 1.6

    /// How strongly `aggressiveness` raises that value - aggressive bots want
    /// knights. Higher widens the gap between personalities.
    public var buildDevCardAggressionScale: Double = 0.5

    /// Aggression level at which a bot treats an otherwise-uncommitted
    /// playable knight as worthwhile proactive pressure. Kept above the
    /// Balanced preset so this is a recognizable style choice, not a global
    /// strength change disguised as personality.
    public var proactiveKnightAggressivenessThreshold: Double = 0.85

    /// Penalty per unplayed *playable* card already in hand (VP cards excluded
    /// - they never compete for the one-card-per-turn slot). Only one card can
    /// be played a turn, so hoarding has real diminishing returns. Higher
    /// makes bots stop buying sooner.
    public var devCardHoardingPenalty: Double = 0.35

    /// Bonus when one more knight would actually reach *and* beat the current
    /// Largest Army holder's count. Higher makes bots buy into the army race
    /// deliberately rather than only reacting to knights they happen to draw.
    public var buildDevCardLargestArmyBonus: Double = 1.0

    // MARK: - Trade

    /// How many of a resource a bot must hold before it will offer two of them
    /// for one of something else. Below this it offers one for one: a bot down
    /// to its last spare card offering two is not being generous, it is
    /// handing over the better half of a deal it needed.
    public var generousOfferSurplusThreshold = 3

    //
    // Consumed by `TradeHeuristics`, which values each resource against the
    // receiving player's nearest build target rather than treating all
    // resources alike.

    /// The `expansionBias` at or above which a bot prioritises new
    /// settlements, and below which it prioritises city upgrades. Shared with
    /// `DevCardHeuristics` so Year of Plenty and Monopoly reason about "my
    /// current build plan" consistently with trading. Higher pushes more
    /// personalities toward the city-first ordering.
    public var cityFirstExpansionBiasPivot: Double = 0.5

    /// Weight of a settlement as a trade target. The highest, because it is
    /// the most valuable thing a trade can unblock.
    public var tradeTargetSettlementWeight: Double = 3.0

    /// Weight of a city upgrade as a trade target.
    public var tradeTargetCityWeight: Double = 2.5

    /// Weight of a development card as a trade target.
    public var tradeTargetDevCardWeight: Double = 1.5

    /// Weight of a road as a trade target. The lowest - a road is rarely worth
    /// trading for.
    public var tradeTargetRoadWeight: Double = 1.0

    /// Hard floor on the accept threshold, below which no personality's trade
    /// willingness can push it. Without a floor, any bot with
    /// `tradeWillingness >= acceptThresholdBase / acceptThresholdWillingnessScale`
    /// collapsed the bar to zero and accepted literally any net-positive deal,
    /// however thin - which is what "bots accept trades too easily" was.
    /// Higher makes every bot pickier.
    public var acceptThresholdFloor: Double = 0.4

    /// Accept threshold before trade willingness is subtracted. Higher makes
    /// every bot pickier.
    public var acceptThresholdBase: Double = 0.7

    /// How strongly `tradeWillingness` lowers the accept threshold. Higher
    /// widens the gap between an eager and a reluctant trader.
    public var acceptThresholdWillingnessScale: Double = 0.6

    /// How strongly the proposer's relative threat raises the bar - accepting
    /// hands them resources, so an above-average threat has to offer a better
    /// deal. Higher makes bots refuse to feed the leader.
    public var acceptThreatShiftScale: Double = 0.5

    /// How strongly the receiver's own standing shifts the bar: a bot that is
    /// behind drops it to catch up, a bot that is ahead raises it because
    /// helping anyone catch up costs more than a merely-fair trade is worth.
    /// Higher makes bots play the scoreboard rather than the deal.
    public var acceptStandingShiftScale: Double = 0.25

    /// How much each trade the proposer has *already* landed this turn raises
    /// the bar - a real opponent notices a partner working the table. Resets
    /// every turn, so it never carries a grudge. Higher makes bots shut down a
    /// trading run faster.
    public var acceptSuspicionShiftPerTrade: Double = 0.35

    /// Extra bar applied when accepting would hand the proposer an immediate
    /// settlement or city. Stops a proposer one card short of a build
    /// completing it through a string of individually-plausible one-for-one
    /// trades. Higher makes bots guard the win condition harder.
    public var acceptUnlockShift: Double = 0.6

    // MARK: - Robber
    //
    // Consumed by `RobberHeuristics.chooseRobberTarget`. The disruption value
    // of a city versus a settlement is NOT here: 2-to-1 is the production
    // ratio the rules set, not an opinion.

    /// How strongly an occupant's relative threat and this bot's
    /// `aggressiveness` amplify a tile's disruption score, over a neutral base
    /// of 1.0. Higher makes robber placement track the leader instead of raw
    /// building count.
    public var robberThreatWeightScale: Double = 2.0

    // MARK: - Dev cards
    //
    // Consumed by `DevCardHeuristics`. Year of Plenty granting exactly two
    // cards is a rule, not a weight, so it stays inline.

    /// Played knights needed to be a genuine Largest Army contender - used
    /// both to decide a knight play would claim it and to decide the race is
    /// worth entering at all. Shared with `BuildPlanner`'s buy decision.
    /// Catan's own minimum is 3; lower this only to model a bot that
    /// misjudges the race.
    public var largestArmyKnightThreshold: Int = 3

    /// Threat-weighted total of a resource that opponents must collectively
    /// hold before Monopoly is worth playing on it. Higher makes bots hold
    /// Monopoly for a bigger haul.
    public var monopolyMinimumStash: Double = 3.0

    /// Development cards left in the deck at or below which a Largest Army
    /// contender stops sitting on knights and starts spending them - there is
    /// no runway left to raise its ceiling further. Higher makes bots cash in
    /// earlier.
    public var devDeckNearlyOutCount: Int = 5

    // MARK: - Move-category priority
    //
    // Consumed by `Bot.decideMainTurn`. These do not score a move's quality -
    // the heuristics above already did that - they decide which *category*
    // wins when several have something to offer, so they are only meaningful
    // relative to each other.

    /// Priority of accepting a pending trade the heuristics already approved.
    public var acceptTradeMoveBase: Double = 2.0

    /// How strongly `tradeWillingness` raises that priority. The largest
    /// personality swing of any category, which is what lets a trade-happy bot
    /// out-prioritise its own build.
    public var acceptTradeMoveWillingnessScale: Double = 3.0

    /// Priority of playing an owned development card. Sits above trading
    /// because a dev-card play never competes for the same resources as a
    /// build.
    public var playDevCardMoveBase: Double = 2.5

    /// How strongly `aggressiveness` raises that priority, mostly via knights.
    public var playDevCardMoveAggressionScale: Double = 2.0

    /// Priority of building. The reference point every other category is
    /// tuned against; a build beats everything unless a personality term
    /// pushes another category past it.
    public var buildMoveScore: Double = 3.0

    /// Priority of buying a development card, considered only when no build
    /// was worth taking. Distinct from `buildDevCardBase`, which scores the
    /// same purchase as a *build candidate* - these two happen to share a
    /// value today but answer different questions and should sweep
    /// independently.
    public var buyDevCardMoveBase: Double = 1.6

    /// How strongly `aggressiveness` raises that priority.
    public var buyDevCardMoveAggressionScale: Double = 0.5

    /// Priority of falling back to a bank or port trade. Above proposing a
    /// trade because the bank always says yes. Higher makes bots convert
    /// surplus rather than stall.
    public var bankTradeMoveBase: Double = 1.9

    /// How strongly `expansionBias` raises the bank-trade priority.
    public var bankTradeMoveExpansionScale: Double = 0.3

    /// Priority of proposing a trade to other players, which `tradeWillingness`
    /// scales below. The base alone remains below a guaranteed bank trade.
    public var proposeTradeMoveBase: Double = 1.0

    /// Makes the Cautious preset ask another player before paying the bank's
    /// poor rate, while Balanced and Aggressive still prefer certainty.
    public var proposeTradeMoveWillingnessScale: Double = 1.5

    /// Priority of explicitly declining an unwanted pending offer. Deliberately
    /// the lowest of any category: it is housekeeping, done only when nothing
    /// better exists, because nothing but an explicit response ever clears an
    /// offer out of `pendingTradeOffers`.
    public var declineTradeMoveScore: Double = 0.1

    /// Memberwise construction is deliberately not offered - a ~60-parameter
    /// initialiser is unusable and unreadable at a call site. Build from the
    /// defaults and assign the handful of knobs a sweep actually varies.
    public init() {}

    /// The policy every `Bot` uses unless told otherwise, and the exact
    /// behaviour this type was extracted from.
    public static let `default` = BotWeights()
}
