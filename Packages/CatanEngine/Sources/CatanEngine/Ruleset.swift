/// Classic's per-piece and per-resource supplies, as plain constants rather
/// than a call into `Ruleset.forMode(.classic)`.
///
/// `PieceAllowance.limit` and `BankAllowance.perResource` read these directly
/// for their `.scaledFromBoard` case. Routing that through `forMode(.classic)`
/// instead would work only by accident - it would depend on Classic's own
/// `pieceLimits`/`bank` staying `.explicit` forever, and the moment Classic's
/// allowance became `.scaledFromBoard` itself, resolving it would call back
/// into `forMode(.classic)`, which resolves it, forever. Reading a constant
/// instead makes that recursion unrepresentable rather than merely avoided.
private enum ClassicBaseline {
    static let pieceLimits: [BuildingKind: Int] = [.settlement: 5, .city: 4]
    static let bankPerResource = 19
}

/// How many of each piece a player owns.
public enum PieceAllowance: Sendable, Equatable {
    case explicit([BuildingKind: Int])
    /// Scaled from the board's tile count against classic's ratio, for a mode
    /// that wants supplies proportional to its map without hand-computing them.
    case scaledFromBoard

    func limit(for kind: BuildingKind, board: BoardShape) -> Int {
        switch self {
        case .explicit(let limits):
            return limits[kind, default: 0]
        case .scaledFromBoard:
            let classicLimit = ClassicBaseline.pieceLimits[kind, default: 0]
            let ratio = Double(board.tileCount) / Double(BoardShape.classic.tileCount)
            return Int((Double(classicLimit) * ratio).rounded())
        }
    }
}

/// How many cards of each resource the bank starts with.
public enum BankAllowance: Sendable, Equatable {
    case explicit(Int)
    case scaledFromBoard

    func perResource(board: BoardShape) -> Int {
        switch self {
        case .explicit(let count):
            return count
        case .scaledFromBoard:
            let ratio = Double(board.tileCount) / Double(BoardShape.classic.tileCount)
            return Int((Double(ClassicBaseline.bankPerResource) * ratio).rounded())
        }
    }
}

/// Every quantity the rules need, for one mode.
///
/// ## Why one value rather than constants per rule
/// These numbers were literals scattered across `Building`, `LongestRoad`,
/// `DevCards`, `Robber`, `WinCondition` and `GameSetup`. Adding a second rule
/// set that way means finding all of them; adding a third means finding them
/// again. Here a new mode is one case in `forMode(_:)`, and the switch is
/// exhaustive, so the compiler names anything left out.
///
/// ## Keyed by building KIND, not by named field
/// `pieceLimits` and `victoryPointsPerBuilding` are dictionaries because a
/// third building tier is planned (a "double city" worth 4). As three flat
/// fields, adding it would edit every limit check and both victory-point
/// formulas; as dictionary entries it edits neither.
///
/// ## Where the boundary is
/// This covers quantities and board shape. A mode that changes the *shape* of a
/// move — a new development card, a build action, a trade type — is a change to
/// `GameMove` and `RulesEngine`, not a field here. Adding a field with a
/// classic-valued default is the supported way to grow this; every other mode
/// keeps compiling.
public struct Ruleset: Sendable, Equatable {
    public let board: BoardShape
    public let victoryPointTargets: ClosedRange<Int>
    public let defaultVictoryPointTarget: Int
    public let longestRoadBonus: Int
    public let largestArmyBonus: Int
    /// Shortest road that can claim the bonus.
    public let longestRoadMinimum: Int
    /// Fewest played knights that can claim the bonus.
    public let largestArmyMinimum: Int
    public let pieceLimits: PieceAllowance
    public let victoryPointsPerBuilding: [BuildingKind: Int]
    public let maxRoadsPerPlayer: Int
    public let bank: BankAllowance
    public let devCardDeck: [DevCardType: Int]
    /// A player holding MORE than this many resource cards discards on a 7.
    public let discardThreshold: Int

    public init(
        board: BoardShape,
        victoryPointTargets: ClosedRange<Int>,
        defaultVictoryPointTarget: Int,
        longestRoadBonus: Int,
        largestArmyBonus: Int,
        longestRoadMinimum: Int,
        largestArmyMinimum: Int,
        pieceLimits: PieceAllowance,
        victoryPointsPerBuilding: [BuildingKind: Int],
        maxRoadsPerPlayer: Int,
        bank: BankAllowance,
        devCardDeck: [DevCardType: Int],
        discardThreshold: Int
    ) {
        self.board = board
        self.victoryPointTargets = victoryPointTargets
        self.defaultVictoryPointTarget = defaultVictoryPointTarget
        self.longestRoadBonus = longestRoadBonus
        self.largestArmyBonus = largestArmyBonus
        self.longestRoadMinimum = longestRoadMinimum
        self.largestArmyMinimum = largestArmyMinimum
        self.pieceLimits = pieceLimits
        self.victoryPointsPerBuilding = victoryPointsPerBuilding
        self.maxRoadsPerPlayer = maxRoadsPerPlayer
        self.bank = bank
        self.devCardDeck = devCardDeck
        self.discardThreshold = discardThreshold
    }

    public func pieceLimit(for kind: BuildingKind) -> Int {
        pieceLimits.limit(for: kind, board: board)
    }
    public func victoryPoints(for kind: BuildingKind) -> Int {
        victoryPointsPerBuilding[kind, default: 0]
    }
    /// Starting stock of each resource. Named apart from the stored `bank`
    /// allowance it resolves, because Swift will not take a property and a
    /// computed property of the same name.
    public var bankPerResource: Int { bank.perResource(board: board) }
    public var devCardDeckSize: Int { devCardDeck.values.reduce(0, +) }

    /// Why this rule set cannot be played, or `nil` if it can.
    ///
    /// The road limit is checked against what the longest-road search can
    /// actually serve. A mode that exceeds it must fail here, at construction,
    /// rather than by freezing the game on a road placement — which is what the
    /// old exhaustive search did past roughly 40 roads.
    public var validationProblem: String? {
        if let boardProblem = board.compositionProblem { return boardProblem }
        guard maxRoadsPerPlayer <= LongestRoad.supportedRoadLimit else {
            return "\(maxRoadsPerPlayer) roads exceeds the \(LongestRoad.supportedRoadLimit) "
                + "the longest-road search is measured to support"
        }
        guard victoryPointTargets.contains(defaultVictoryPointTarget) else {
            return "default target \(defaultVictoryPointTarget) is outside \(victoryPointTargets)"
        }
        for kind in BuildingKind.allCases where victoryPointsPerBuilding[kind] == nil {
            return "\(kind) has no victory-point value"
        }
        return nil
    }

    /// The rules for `mode`. Exhaustive on purpose: a new `GameMode` case fails
    /// to compile until it is given values here, which is the point of the tag.
    public static func forMode(_ mode: GameMode) -> Ruleset {
        switch mode {
        case .classic:
            return Ruleset(
                board: .classic,
                victoryPointTargets: 8...12,
                defaultVictoryPointTarget: 10,
                longestRoadBonus: 2,
                largestArmyBonus: 2,
                longestRoadMinimum: 5,
                largestArmyMinimum: 3,
                pieceLimits: .explicit(ClassicBaseline.pieceLimits),
                victoryPointsPerBuilding: [.settlement: 1, .city: 2],
                maxRoadsPerPlayer: 15,
                bank: .explicit(ClassicBaseline.bankPerResource),
                devCardDeck: [
                    .knight: 14, .victoryPoint: 5, .roadBuilding: 2,
                    .yearOfPlenty: 2, .monopoly: 2,
                ],
                discardThreshold: 7
            )
        case .expanded:
            return Ruleset(
                board: .expanded,
                victoryPointTargets: 25...25,
                defaultVictoryPointTarget: 25,
                // Pieces double because classic's limits cap buildings at
                // 5*1 + 4*2 = 13 VP; reaching 25 would otherwise need nearly
                // every victory-point development card in the deck.
                longestRoadBonus: 4,
                largestArmyBonus: 4,
                // The two bonus minimums deliberately do not move
                // (Jake, 2026-09-10): a 5-road / 3-knight bar is still a real
                // commitment on a board with twice the pieces to spread across.
                longestRoadMinimum: 5,
                largestArmyMinimum: 3,
                pieceLimits: .explicit([.settlement: 10, .city: 8]),
                victoryPointsPerBuilding: [.settlement: 1, .city: 2],
                maxRoadsPerPlayer: 30,
                bank: .explicit(38),
                // Deck doubled along with everything else it feeds.
                devCardDeck: [
                    .knight: 28, .victoryPoint: 10, .roadBuilding: 4,
                    .yearOfPlenty: 4, .monopoly: 4,
                ],
                // Raised because doubled income would trigger classic's fixed
                // 7 for most players on most sevens, turning every roll into a
                // discard event instead of an occasional one.
                discardThreshold: 10
            )
        }
    }
}
