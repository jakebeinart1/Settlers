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
    /// Legal settlement sites the seat can already reach. Room to grow, priced
    /// separately from any particular site, because a seat with nowhere to
    /// build is one bad block away from being finished.
    public var buildableSites: Double
    /// How close the hand is to the next settlement and the next city.
    public var handSynergy: Double
    /// A card in hand, for its option value.
    public var handCard: Double
    /// Per card above the discard threshold. Negative.
    public var discardExposure: Double
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
        buildableSites: Double = 0.0608,
        handSynergy: Double = 0.2240,
        handCard: Double = 0.0646,
        discardExposure: Double = -0.0568,
        devCardHeld: Double = 0.2681,
        knight: Double = 0.2746,
        roadLength: Double = 0.0923,
        port: Double = 0.0986,
        rival: Double = 0.9207,
        winning: Double = 1000.0
    ) {
        self.victoryPoint = victoryPoint
        self.production = production
        self.variety = variety
        self.expansion = expansion
        self.buildableSites = buildableSites
        self.handSynergy = handSynergy
        self.handCard = handCard
        self.discardExposure = discardExposure
        self.devCardHeld = devCardHeld
        self.knight = knight
        self.roadLength = roadLength
        self.port = port
        self.rival = rival
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

    /// The hand-set weights these replaced, kept as a comparison arm rather
    /// than as history. A future sweep needs something to beat, and "the
    /// numbers a person wrote down from the game's own arithmetic" is the
    /// most honest baseline available.
    public static let handSet = EvaluationWeights(
        production: 0.55, variety: 0.12, expansion: 0.30, buildableSites: 0.06,
        handSynergy: 0.18, handCard: 0.02, discardExposure: -0.12, devCardHeld: 0.30,
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
            victoryPoint, production, variety, expansion, buildableSites,
            handSynergy, handCard, discardExposure, devCardHeld, knight,
            roadLength, port, rival, winning,
        ]
    }

    /// The names of `vector`'s slots, in the same order.
    public static let vectorLabels = [
        "victoryPoint", "production", "variety", "expansion", "buildableSites",
        "handSynergy", "handCard", "discardExposure", "devCardHeld", "knight",
        "roadLength", "port", "rival", "winning",
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
            expansion: vector[3], buildableSites: vector[4], handSynergy: vector[5],
            handCard: vector[6], discardExposure: vector[7], devCardHeld: vector[8],
            knight: vector[9], roadLength: vector[10], port: vector[11],
            rival: vector[12], winning: vector[13]
        )
    }
}
