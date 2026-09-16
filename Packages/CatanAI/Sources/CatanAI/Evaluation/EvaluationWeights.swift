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
    /// **zero by default because turning it on measurably loses.**
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
    public var sevenLoss: Double
    /// The least a trade must improve this seat's position before it proposes
    /// or accepts one. Comparison is strict, so at zero a trade that leaves
    /// the seat exactly level is refused.
    ///
    /// **Zero by default because a floor measurably loses.** At 0.10 the bot
    /// won 27.1% against the same 1,248 games it wins 57.5% of at zero. The
    /// median trade it accepts improves its position by 0.037, so a floor of
    /// 0.10 removed about nine trades in ten - and a stream of small gains is
    /// where this policy's strength comes from, which is also why stopping it
    /// re-asking a refused offer was worth eighteen points.
    public var tradeMargin: Double
    /// Extra gain required per card handed over, under the `worthIt` trade
    /// model. Zero leaves every beneficial trade worth making; higher values
    /// mean only trades that pay for what they give away.
    ///
    /// **Zero by default, measured.** At 0.04 with the same everything else,
    /// Expert offered 0.82 trades a turn against round three's 2.30 and lost
    /// 14.4 points. The bar is not what stops the bot overpaying - the
    /// evaluation already charges it for every card it hands over, and for
    /// what the counterparty gains. Kept as a weight so a sweep can test that
    /// again on the retrained policy.
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

    public init(
        victoryPoint: Double = 1.0,
        production: Double = 0.5058,
        variety: Double = 0.1263,
        expansion: Double = 0.2945,
        approach: Double = 0.2945,
        buildableSites: Double = 0.0608,
        handSynergy: Double = 0.2240,
        handCard: Double = 0.0646,
        handCardOverflow: Double = 0.0646,
        discardExposure: Double = -0.0568,
        sevenLoss: Double = 0,
        devCardHeld: Double = 0.2681,
        knight: Double = 0.2746,
        roadLength: Double = 0.0923,
        port: Double = 0.0986,
        rival: Double = 0.9207,
        tradeMargin: Double = 0,
        concessionPerCard: Double = 0.0,
        winning: Double = 1000.0
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
    }

    /// Fitted, not hand-set.
    ///
    /// These come from a 50-iteration SPSA sweep against frozen `eval` on
    /// training seeds, validated on held-out seeds against `balanced` - an
    /// opponent the sweep never played. Paired over 1,248 rotated games they
    /// beat the hand-set weights by **+4.7 points (95% CI +1.2 to +8.3,
    /// McNemar p = 0.010)**.
    ///
    /// ## Read the two numbers together, because they disagree
    /// Against the training opponent the sweep went from 25.0% to **67.2%**.
    /// Against `balanced` it went from 42.5% to **47.3%**. A policy that had
    /// genuinely become much stronger would have moved both; most of that
    /// 67.2% is this weight set learning `eval`'s particular blind spots. The
    /// honest figure is the smaller one, and the gap is the reason the
    /// held-out arm is not optional.
    ///
    /// ## What the sweep actually found
    /// One correction dominates and the rest barely moved. `handCard` more
    /// than tripled and `discardExposure` halved - together, "a card in hand
    /// is worth far more than the risk of holding it through a seven". The
    /// hand-set values had the bot spending and bank-trading to duck the
    /// discard threshold, which costs more than the robber does at six rolls
    /// in thirty-six. Every structural weight - `expansion`, `variety`,
    /// `port`, `buildableSites` - moved less than 5%, so the shape of the
    /// evaluation was about right and the error was concentrated in one place.
    ///
    /// `rival` rose 8% and stayed firmly nonzero across all fifty iterations,
    /// which is the closest thing to independent support the differential
    /// objective has: the search could have driven it to zero and did not.
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
        }
    }

    /// The hand-set weights these replaced, kept as a comparison arm rather
    /// than as history. A future sweep needs something to beat, and "the
    /// numbers a person wrote down from the game's own arithmetic" is the
    /// most honest baseline available.
    public static let handSet = EvaluationWeights(
        production: 0.55, variety: 0.12, expansion: 0.30, approach: 0.30, buildableSites: 0.06,
        handSynergy: 0.18, handCard: 0.02, handCardOverflow: 0, discardExposure: -0.12, devCardHeld: 0.30,
        knight: 0.25, roadLength: 0.08, port: 0.10, rival: 0.85
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
        ]
    }

    /// The names of `vector`'s slots, in the same order.
    public static let vectorLabels = [
        "victoryPoint", "production", "variety", "expansion", "approach", "buildableSites",
        "handSynergy", "handCard", "handCardOverflow", "discardExposure", "sevenLoss", "devCardHeld", "knight",
        "roadLength", "port", "rival", "tradeMargin", "concessionPerCard", "winning",
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
            tradeMargin: vector[16], concessionPerCard: vector[17], winning: vector[18]
        )
    }
}
