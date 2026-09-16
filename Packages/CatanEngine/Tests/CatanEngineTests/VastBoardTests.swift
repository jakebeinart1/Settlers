import Testing
@testable import CatanEngine

/// The 61-tile board, and the arithmetic the mode's 26-point target rests on.
///
/// The target is a hypothesis about how much of the map a player can claim, so
/// these pin the quantities that hypothesis is built from. If one of them moves,
/// the target needs re-deriving rather than adjusting.
@Suite struct VastBoardTests {

    @Test func theRulesetIsPlayable() {
        #expect(Ruleset.forMode(.vast).validationProblem == nil)
    }

    /// 3r^2 + 3r + 1 at radius 4, and the composition has to fill it exactly -
    /// a short composition deals a board with holes.
    @Test func theBoardIsSixtyOneTilesWithThreeDeserts() {
        let board = BoardGenerator.randomized(seed: 7, shape: .vast)
        #expect(board.tiles.count == 61)
        #expect(board.tiles.filter { $0.kind == .desert }.count == 3)
        #expect(board.tiles.filter { $0.numberToken != nil }.count == 58)
    }

    /// The whole reason for a fourth ring: vertices, which is what ran out on
    /// the 37-tile board. 6(r+1)^2 - 54 at classic, 96 at expanded, 150 here.
    @Test func theBoardHasOneHundredFiftyVertices() {
        let board = BoardGenerator.randomized(seed: 7, shape: .vast)
        #expect(board.onBoardVertices.count == 150)
        #expect(board.onBoardEdges.count == 210)
    }

    /// Brick and ore stay the scarce pair. Flattening the mix would change what
    /// a good position is, quietly, everywhere in the evaluator.
    @Test func brickAndOreStayScarcerThanTheOtherThree() {
        let board = BoardGenerator.randomized(seed: 7, shape: .vast)
        func count(_ resource: Resource) -> Int {
            board.tiles.filter { $0.kind == .resource(resource) }.count
        }
        for scarce in [Resource.brick, .ore] {
            for common in [Resource.grain, .wool, .lumber] {
                #expect(count(scarce) < count(common),
                        "\(scarce) (\(count(scarce))) should be scarcer than \(common) (\(count(common)))")
            }
        }
    }

    /// Symmetric about 7, exactly as the physical board is, so pip intuition
    /// carries across all three modes.
    @Test func theTokenSpreadIsSymmetricAboutSeven() {
        let board = BoardGenerator.randomized(seed: 7, shape: .vast)
        var tally: [Int: Int] = [:]
        for token in board.tiles.compactMap(\.numberToken) { tally[token, default: 0] += 1 }
        for token in 2...6 {
            #expect(tally[token] == tally[14 - token],
                    "\(token) appears \(tally[token] ?? 0) times, \(14 - token) \(tally[14 - token] ?? 0)")
        }
        #expect(tally[7] == nil)
    }

    @Test func thePortsCoverThreeGenericsPerFiveAndEveryResourceTwice() {
        let board = BoardGenerator.randomized(seed: 7, shape: .vast)
        #expect(board.ports.count == 15)
        #expect(board.ports.filter { $0.kind == .generic }.count == 5)
        for resource in Resource.allCases {
            #expect(board.ports.filter { $0.kind == .resource(resource) }.count == 2)
        }
    }

    /// The target has to be reachable by building. A player who claims `spots`
    /// vertices and upgrades every one scores `2 * spots`; the measured claim on
    /// the 37-tile board was 8-9 vertices, which caps that mode at ~17 against
    /// its 25 - the defect this board exists to fix. Here the piece limits must
    /// not be what stops a player short of 26.
    @Test func thePieceLimitsAloneCanReachTheTarget() {
        let rules = Ruleset.forMode(.vast)
        let fromBuildings = rules.pieceLimit(for: .city) * rules.victoryPoints(for: .city)
            + rules.pieceLimit(for: .settlement) * rules.victoryPoints(for: .settlement)
        #expect(fromBuildings >= rules.defaultVictoryPointTarget,
                "pieces cap a player at \(fromBuildings) against a \(rules.defaultVictoryPointTarget) target")
    }

    /// Guards the trap this mode was built to escape: the deck must not be the
    /// only route to the target. A player on the cities alone should get there
    /// without a single victory-point card.
    @Test func theDeckIsNotRequiredToReachTheTarget() {
        let rules = Ruleset.forMode(.vast)
        let cityPoints = rules.pieceLimit(for: .city) * rules.victoryPoints(for: .city)
        #expect(cityPoints + rules.longestRoadBonus >= rules.defaultVictoryPointTarget,
                "cities (\(cityPoints)) plus one bonus cannot reach \(rules.defaultVictoryPointTarget)")
    }

    @Test func boardsAreDeterministicForOneSeed() {
        let first = BoardGenerator.randomized(seed: 99, shape: .vast)
        let second = BoardGenerator.randomized(seed: 99, shape: .vast)
        #expect(first.tiles.map(\.coordinate) == second.tiles.map(\.coordinate))
        #expect(first.tiles.map(\.numberToken) == second.tiles.map(\.numberToken))
        #expect(first.ports.map(\.kind) == second.ports.map(\.kind))
    }
}
