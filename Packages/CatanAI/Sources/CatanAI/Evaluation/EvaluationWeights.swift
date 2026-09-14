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
        production: Double = 0.55,
        variety: Double = 0.12,
        expansion: Double = 0.30,
        buildableSites: Double = 0.06,
        handSynergy: Double = 0.18,
        handCard: Double = 0.02,
        discardExposure: Double = -0.12,
        devCardHeld: Double = 0.30,
        knight: Double = 0.25,
        roadLength: Double = 0.08,
        port: Double = 0.10,
        rival: Double = 0.85,
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

    /// The starting point, hand-set from the game's own arithmetic rather than
    /// fitted. A sweep starts here; it does not have to end here.
    public static let `default` = EvaluationWeights()

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
