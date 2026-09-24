import CatanEngine

/// The numeric policy of `PositionEvaluator`, in one value.
///
/// ## Why the weights are a value and not constants
/// `BotWeights` exists in this package for the same reason and its doc comment
/// has asked to be swept or trained since it was written; nobody ever could,
/// because the simulator had no way to vary weights without rebuilding. This
/// type is passed in, so one binary can play two weight sets and a sweep is a
/// loop rather than a build matrix.
///
/// ## Scale
/// Terms are in "roughly a victory point" units: `victoryPoint` is 1.0 by
/// definition and every other weight says what that feature is worth measured
/// against a point. That makes a weight readable on its own - `knight: 0.25`
/// says four played knights are worth about a point before the army bonus
/// lands - and it keeps a sweep's search space in a sane range.
///
/// The one deliberate exception is `winning`, which is not on that scale and is
/// not meant to be: a move that ends the game is not "worth some points", it is
/// the end of the comparison.
public struct EvaluationWeights: Sendable, Equatable, Codable {

    /// A public victory point already on the board.
    public var victoryPoint: Double
    /// Expected cards per own turn, summed over resources.
    public var production: Double
    /// Producing a resource at all, counted once per distinct resource. A seat
    /// that makes four cards a turn of one resource is poorer than the total
    /// suggests, because everything it wants to buy needs a mix.
    public var variety: Double
    /// The best single expansion available on the current road network, valued
    /// by the production it would add.
    public var expansion: Double
    /// The best site reachable by building more roads, discounted per road.
    /// Absent until the Expanded stall showed what its absence costs: see
    /// `BoardIndex.approachableSites`.
    public var approach: Double
    /// Legal settlement sites the seat can already reach. Room to grow, priced
    /// separately from any particular site, because a seat with nowhere to
    /// build is one bad block away from being finished.
    public var buildableSites: Double
    /// How close the hand is to the next settlement and the next city.
    public var handSynergy: Double
    /// A card in hand, for its option value, up to the discard threshold.
    public var handCard: Double
    /// A card in hand past the discard threshold. Equal to `handCard` in
    /// Classic and zero in Expanded; `PositionEvaluator.handTerms` has the
    /// measurements behind the split.
    public var handCardOverflow: Double
    /// Per card above the discard threshold. Negative.
    public var discardExposure: Double
    /// Per card this seat expects to lose to a seven before its next turn,
    /// counting the production it will collect in between. Negative, and
    /// **effectively off: the fitted value is -0.0081.**
    ///
    /// It was added because the Expert bot loses 9.0 cards a game to sevens
    /// against the shipping heuristic's 1.9, while ending its own turn over
    /// the threshold only 1.1% of the time - it ends on about five cards and
    /// collects the rest before someone rolls. Pricing the hand it will
    /// *have* makes it spend and bank-trade down before ending a turn.
    ///
    /// That is worse. Same 1,248 held-out games against `balanced`:
    /// 57.5% with this at zero, **39.0% at -0.20 and 36.1% at -0.40**. Getting
    /// under the threshold costs guaranteed cards - a 4:1 bank trade gives
    /// away three - to avoid a loss that needs a seven in the next few rolls,
    /// and it empties the hand this policy's trading edge runs on. Eating
    /// the occasional discard is the cheaper price. Kept as a weight rather
    /// than deleted so an Expanded sweep, where games are long enough for
    /// sevens to compound, can find out whether that answer changes.
    ///
    /// The 2026-09-17 no-trade sweep was the first that could move it and put
    /// it at **-0.0081**, twenty-five times smaller than the -0.20 measured
    /// above. Read that as the search confirming zero rather than finding a
    /// value: at this size the term changes a decision only when two moves are
    /// otherwise within a hundredth of a point.
    public var sevenLoss: Double
    /// The least a trade must improve this seat's position before it proposes
    /// or accepts one. Comparison is strict, so at zero a trade that leaves
    /// the seat exactly level is refused.
    ///
    /// **Near zero because a floor measurably loses.** At 0.10 the bot
    /// won 27.1% against the same 1,248 games it wins 57.5% of at zero. The
    /// median trade it accepts improves its position by 0.037, so a floor of
    /// 0.10 removed about nine trades in ten - and a stream of small gains is
    /// where this policy's strength comes from, which is also why stopping it
    /// re-asking a refused offer was worth eighteen points.
    ///
    /// The fitted value is **0.0073** - a fifth of the 0.037 median gain of an
    /// accepted trade, so it removes the trades that are level-ish and leaves
    /// the stream of small gains intact. It is not the 0.10 that lost thirty
    /// points; it is the smallest floor that is not zero.
    public var tradeMargin: Double
    /// Extra gain required per card handed over, under the `worthIt` trade
    /// model. Zero leaves every beneficial trade worth making; higher values
    /// mean only trades that pay for what they give away.
    ///
    /// **Near zero, measured.** At 0.04 with the same everything else,
    /// Expert offered 0.82 trades a turn against round three's 2.30 and lost
    /// 14.4 points. The bar is not what stops the bot overpaying - the
    /// evaluation already charges it for every card it hands over, and for
    /// what the counterparty gains. Kept as a weight so a sweep can test that
    /// again on the retrained policy - which it now has: the fitted value is
    /// **0.0061**, about a sixth of the 0.04 that cost 14.4 points.
    public var concessionPerCard: Double
    /// An unplayed development card.
    public var devCardHeld: Double
    /// A played knight, before the army bonus itself.
    public var knight: Double
    /// Each road in the longest chain, before the road bonus itself.
    public var roadLength: Double
    /// Holding a port, per port.
    public var port: Double

    /// How heavily the strongest rival's standing is subtracted.
    ///
    /// This is the differential objective as a single number. At 1.0 the seat
    /// plays pure relative position - a point for both seats is worth nothing;
    /// at 0.0 it plays its own score and ignores the table. Jake's rule ("if
    /// you both gain a point from a transaction, it's better to have a higher
    /// net point total") is this term being nonzero.
    public var rival: Double

    /// Reaching the victory target. Dominates every other term by construction.
    public var winning: Double

    /// Conquest: per point of army-card strength held. Own hand exactly; a
    /// rival's as card count x the deck's mean, never the hidden faces. Zero
    /// outside Conquest, where nobody holds army cards.
    public var armyStrength: Double
    /// Conquest: per point of garrison strength on hexes this seat holds - what
    /// it costs a rival to take them back.
    public var garrisonStrength: Double
    /// Conquest: the production swing of the best hex this seat's hand can take
    /// right now. What makes saving up for a 6 or 8 worth something before the
    /// cards are spent, which strength-per-card alone never priced.
    public var captureThreat: Double
    /// Conquest: production on hexes this seat holds that a rival touching them
    /// could break with the cards they hold. Negative: an exposed hex is a loss
    /// waiting to happen, so reinforcing it has a reason.
    public var garrisonExposure: Double
    /// Conquest: summed swing of the contested hexes this seat has a building
    /// on but does not hold - how many rival buildings a takeover there would
    /// silence. What makes settling onto a crowded 6 or 8 worth it before the
    /// cards to take it are in hand; captureThreat only sees hexes the hand can
    /// take now.
    public var takeoverFoothold: Double

    public init(
        victoryPoint: Double = 1.0,
        production: Double = 0.4601,
        variety: Double = 0.1281,
        expansion: Double = 0.3070,
        approach: Double = 0.2925,
        buildableSites: Double = 0.0680,
        handSynergy: Double = 0.1845,
        handCard: Double = 0.0623,
        handCardOverflow: Double = 0.0573,
        discardExposure: Double = -0.0524,
        sevenLoss: Double = -0.0081,
        devCardHeld: Double = 0.2560,
        knight: Double = 0.2611,
        roadLength: Double = 0.0888,
        port: Double = 0.0978,
        rival: Double = 0.8039,
        tradeMargin: Double = 0.0073,
        concessionPerCard: Double = 0.0061,
        winning: Double = 1000.0,
        armyStrength: Double = 0,
        garrisonStrength: Double = 0,
        captureThreat: Double = 0,
        garrisonExposure: Double = 0,
        takeoverFoothold: Double = 0
    ) {
        self.victoryPoint = victoryPoint
        self.production = production
        self.variety = variety
        self.expansion = expansion
        self.approach = approach
        self.buildableSites = buildableSites
        self.handSynergy = handSynergy
        self.handCard = handCard
        self.handCardOverflow = handCardOverflow
        self.discardExposure = discardExposure
        self.sevenLoss = sevenLoss
        self.devCardHeld = devCardHeld
        self.knight = knight
        self.roadLength = roadLength
        self.port = port
        self.rival = rival
        self.tradeMargin = tradeMargin
        self.concessionPerCard = concessionPerCard
        self.winning = winning
        self.armyStrength = armyStrength
        self.garrisonStrength = garrisonStrength
        self.captureThreat = captureThreat
        self.garrisonExposure = garrisonExposure
        self.takeoverFoothold = takeoverFoothold
    }

    /// Fitted, not hand-set - and refitted once the opponent pool could refuse.
    ///
    /// ## Why these replaced the first fitted set
    /// Every earlier number this policy had was earned at a table that accepts
    /// trades, because nothing in the pool could refuse until
    /// `TradeRefusingPolicy` existed. Measured against three seats that accept
    /// nothing, Expert won 38.7% against the shipping heuristic's 39.3% - the
    /// whole advantage was contingent on opponents saying yes, which is not
    /// what a person does. `docs/AI_summaries/2026-09-16-expert-trade-reliance.md`
    /// has that finding; these weights are the answer to it.
    ///
    /// Forty sign-SPSA iterations against a pool of THREE cells - a refusing
    /// table, a trading table, and the shipped weights head to head - then
    /// validated on two independent held-out blocks of 1,248 rotated games per
    /// arm, all decisive:
    ///
    /// | cell | shipped | these | diff |
    /// |---|---:|---:|---:|
    /// | vs 3x `refuses-balanced` | 40.8% | **44.2%** | **+4.3** (p = 0.019, 0.003) |
    /// | vs 3x `balanced` | 80.3% | 78.8% | -1.5 (p = 0.227, 0.448) |
    /// | vs 3x shipped weights | 25.0% by symmetry | **27.2%** | +2.2 (z = +2.5) |
    ///
    /// ## The objective is the result, and it is the part to keep
    /// A first sweep summed only the first two cells and was **rejected**: it
    /// bought +5.0 at the refusing table with -3.0 at the trading one and lost
    /// head to head, 19.6% against a known 25.0% null. Nothing was wrong with
    /// the optimiser - the objective let it sell general strength for the cell
    /// it was being scored on, which is the same "learned the table, not the
    /// game" failure the refusing opponent was built to expose, pointed the
    /// other way. **Putting the head-to-head arm inside the objective is what
    /// made the second sweep adoptable.** A sweep can only refuse a trade its
    /// objective can see.
    ///
    /// ## What moved, and what it means
    /// `handSynergy` -17.6%, `production` -9.0%, `rival` -12.7%,
    /// `handCardOverflow` -11.3%, `buildableSites` +11.8%, `expansion` +4.2%.
    /// The direction is consistent: value moves off *the hand* - which is only
    /// worth what someone will give you for it - and onto *the board*, which
    /// pays whether or not anybody trades.
    ///
    /// ## Read this next to the honest caution
    /// The trading cell is down 1.1 and 1.8 points on the two blocks. Neither
    /// is significant and the pooled -1.5 is inside its interval, but the sign
    /// is the same both times, so this is a small real cost paid for a larger
    /// real gain rather than a free lunch. And two SPSA runs on this objective
    /// disagreed on the DIRECTION of most weights, which says the surface is
    /// flat relative to the noise: do not read any single weight's move here
    /// as a fact about Catan.
    public static let `default` = EvaluationWeights()

    /// The weights validated for `mode`.
    ///
    /// ## Why the modes do not share one set
    /// The fitted weights came from Classic 10-point games and were only ever
    /// validated there. In 25-point Expanded games they stalled: four Expert
    /// bots failed to finish 2 of 40 seeded games, where the shipping heuristic
    /// finished all 40, and the hand-set weights - crediting nothing for cards
    /// past the discard threshold - also finished all 40. A game four times
    /// as long rewards different things; `handCard` and `discardExposure` in
    /// particular were tuned in games that end before hands grow large.
    ///
    /// Expanded therefore plays the hand-set weights until it has a sweep of
    /// its own. That sweep has to count a game that never finishes as a loss
    /// for every seat: decisive-only scoring is right for *measuring* a policy,
    /// and inside an optimiser it rewards learning to stall.
    public static func forMode(_ mode: GameMode) -> EvaluationWeights {
        switch mode {
        case .classic: return .default
        case .expanded: return .handSet
        // Vast inherited Expanded's hand-set answer as an untested placeholder,
        // on the reasoning that a longer game rewards different things. It was
        // measured on 2026-09-17 and the reasoning was wrong: one seat on the
        // fitted set beats three on the hand-set one **81.7%** of the time on
        // this board (480 rotated games, 25.0% null, z = +28.7), and wins 85.2%
        // against three `balanced` where the hand-set weights win 67.7%.
        //
        // The caution that put it here was specific and has been checked rather
        // than argued away: fitted Classic weights once stalled in Expanded,
        // failing to finish 2 of 40 games with four Expert seats. Four seats on
        // THIS set finish **40/40** in Vast, as does the hand-set arm, and every
        // cell measured for this decision was 100% decisive over 1,248 games.
        //
        // Against three seats that refuse every trade the fitted set is 1.4
        // points behind (59.3% against 60.7%, p = 0.40 over 1,248 games). A
        // 480-game run had that at -5.2 with p = 0.055; the full-power number is
        // what the interval was always saying. It is recorded because it is the
        // one cell that does not favour this change, not because it decided it.
        case .vast: return .default
        }
    }

    /// The hand-set weights these replaced, kept as a comparison arm rather
    /// than as history. A future sweep needs something to beat, and "the
    /// numbers a person wrote down from the game's own arithmetic" is the
    /// most honest baseline available.
    ///
    /// `sevenLoss`, `tradeMargin` and `concessionPerCard` are spelled out as
    /// zero rather than left to the initialiser's defaults, which is not
    /// decoration: those defaults are the *fitted Classic* values and they are
    /// now nonzero. Inheriting them would have moved Vast - which ships this
    /// set - on a Classic sweep nobody ran on that board.
    /// The Conquest fork: the board's fitted set plus the two army terms.
    ///
    /// Starting values, before any Conquest fit, are EQUAL on purpose. Strength
    /// moved from hand to garrison then keeps its value, so a deploy is judged
    /// only by the strength the defender burns against what the hex pays. At
    /// 0.05 held against 0.02 garrisoned, holding a 9 outscored taking a shared
    /// 6 with it and the bot sat on its free card (pinned by
    /// `expertSpendsItsFreeCardTakingAHex`).
    public static func conquest(_ mode: GameMode) -> EvaluationWeights {
        var weights = forMode(mode)
        weights.armyStrength = 0.015
        weights.garrisonStrength = 0.015
        // Starting points for a fit, on the production term's own scale.
        weights.captureThreat = 0.4
        weights.garrisonExposure = -0.3
        weights.takeoverFoothold = 0.15
        return weights
    }

    public static let handSet = EvaluationWeights(
        production: 0.55, variety: 0.12, expansion: 0.30, approach: 0.30, buildableSites: 0.06,
        handSynergy: 0.18, handCard: 0.02, handCardOverflow: 0, discardExposure: -0.12,
        sevenLoss: 0, devCardHeld: 0.30,
        knight: 0.25, roadLength: 0.08, port: 0.10, rival: 0.85,
        tradeMargin: 0, concessionPerCard: 0
    )

    // MARK: - Sweeping
    //
    // A sweep needs to read and write weights positionally without knowing
    // their names, and needs the order to be fixed. These two are that seam,
    // and the round-trip is pinned by a test.

    /// Every weight, in a fixed order.
    public var vector: [Double] {
        [
            victoryPoint, production, variety, expansion, approach, buildableSites,
            handSynergy, handCard, handCardOverflow, discardExposure, sevenLoss, devCardHeld, knight,
            roadLength, port, rival, tradeMargin, concessionPerCard, winning,
            armyStrength, garrisonStrength, captureThreat, garrisonExposure, takeoverFoothold,
        ]
    }

    /// The names of `vector`'s slots, in the same order.
    public static let vectorLabels = [
        "victoryPoint", "production", "variety", "expansion", "approach", "buildableSites",
        "handSynergy", "handCard", "handCardOverflow", "discardExposure", "sevenLoss", "devCardHeld", "knight",
        "roadLength", "port", "rival", "tradeMargin", "concessionPerCard", "winning",
        "armyStrength", "garrisonStrength", "captureThreat", "garrisonExposure", "takeoverFoothold",
    ]

    /// Rebuilds weights from `vector`'s layout. Fails fast on the wrong count:
    /// a sweep that silently dropped a weight would report a strength number
    /// for a policy nobody can reconstruct.
    public init(vector: [Double]) {
        precondition(
            vector.count == EvaluationWeights.vectorLabels.count,
            "expected \(EvaluationWeights.vectorLabels.count) weights, got \(vector.count)"
        )
        self.init(
            victoryPoint: vector[0], production: vector[1], variety: vector[2],
            expansion: vector[3], approach: vector[4], buildableSites: vector[5],
            handSynergy: vector[6], handCard: vector[7], handCardOverflow: vector[8],
            discardExposure: vector[9], sevenLoss: vector[10], devCardHeld: vector[11],
            knight: vector[12], roadLength: vector[13], port: vector[14], rival: vector[15],
            tradeMargin: vector[16], concessionPerCard: vector[17], winning: vector[18],
            armyStrength: vector[19], garrisonStrength: vector[20],
            captureThreat: vector[21], garrisonExposure: vector[22], takeoverFoothold: vector[23]
        )
    }
}
