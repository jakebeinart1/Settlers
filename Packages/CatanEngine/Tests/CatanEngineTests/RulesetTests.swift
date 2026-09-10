import Testing
@testable import CatanEngine

@Test func classicRulesetMatchesTheValuesTheEngineShippedWith() {
    let rules = Ruleset.forMode(.classic)
    #expect(rules.victoryPointTargets == 8...12)
    #expect(rules.defaultVictoryPointTarget == 10)
    #expect(rules.longestRoadBonus == 2)
    #expect(rules.largestArmyBonus == 2)
    #expect(rules.longestRoadMinimum == 5)
    #expect(rules.largestArmyMinimum == 3)
    #expect(rules.maxRoadsPerPlayer == 15)
    #expect(rules.pieceLimit(for: .settlement) == 5)
    #expect(rules.pieceLimit(for: .city) == 4)
    #expect(rules.victoryPoints(for: .settlement) == 1)
    #expect(rules.victoryPoints(for: .city) == 2)
    #expect(rules.bankPerResource == 19)
    #expect(rules.discardThreshold == 7)
    #expect(rules.devCardDeckSize == 25)
    #expect(rules.board == BoardShape.classic)
}

@Test func expandedRulesetMatchesTheSpec() {
    let rules = Ruleset.forMode(.expanded)
    #expect(rules.victoryPointTargets == 25...25)
    #expect(rules.defaultVictoryPointTarget == 25)
    #expect(rules.longestRoadBonus == 4)
    #expect(rules.largestArmyBonus == 4)
    #expect(rules.longestRoadMinimum == 5)
    #expect(rules.largestArmyMinimum == 3)
    #expect(rules.maxRoadsPerPlayer == 30)
    #expect(rules.pieceLimit(for: .settlement) == 10)
    #expect(rules.pieceLimit(for: .city) == 8)
    #expect(rules.victoryPoints(for: .settlement) == 1)
    #expect(rules.victoryPoints(for: .city) == 2)
    #expect(rules.bankPerResource == 38)
    #expect(rules.discardThreshold == 10)
    #expect(rules.devCardDeckSize == 50)
    #expect(rules.board == BoardShape.expanded)
}

@Test func expandedDeckIsExactlyTwiceClassic() {
    let classic = Ruleset.forMode(.classic).devCardDeck
    let expanded = Ruleset.forMode(.expanded).devCardDeck
    for type in DevCardType.allCases {
        #expect(expanded[type, default: 0] == classic[type, default: 0] * 2)
    }
}

@Test func everyModeIsCoherentAndReachable() {
    for mode in GameMode.allCases {
        let rules = Ruleset.forMode(mode)
        #expect(rules.validationProblem == nil, "\(mode): \(rules.validationProblem ?? "")")
        // Buildings are the only source of points a player can grow without
        // limit in time; a target above their ceiling is a game that cannot end.
        let ceiling = BuildingKind.allCases.reduce(0) {
            $0 + rules.pieceLimit(for: $1) * rules.victoryPoints(for: $1)
        }
        #expect(ceiling >= rules.victoryPointTargets.upperBound,
                "\(mode) targets \(rules.victoryPointTargets.upperBound) with a \(ceiling)-point ceiling")
        #expect(!mode.displayName.isEmpty)
        #expect(!mode.summary.isEmpty)
    }
}

/// A synthetic board of `radius`, valid only insofar as `PieceAllowance` and
/// `BankAllowance` need it: they read `tileCount` alone. Content is empty
/// since `compositionProblem` is not exercised by these tests.
private func syntheticBoard(radius: Int) -> BoardShape {
    BoardShape(radius: radius, terrain: .counts([:]), tokens: .counts([:]), ports: .derived(kinds: []))
}

@Test func scaledFromBoardReproducesClassicOnAClassicSizedBoard() {
    // radius 2 = 19 tiles = Classic's own board, ratio exactly 1 - the
    // property that makes trusting this seam for other sizes reasonable.
    let board = syntheticBoard(radius: 2)
    #expect(board.tileCount == 19)
    #expect(PieceAllowance.scaledFromBoard.limit(for: .settlement, board: board) == 5)
    #expect(PieceAllowance.scaledFromBoard.limit(for: .city, board: board) == 4)
    #expect(BankAllowance.scaledFromBoard.perResource(board: board) == 19)
}

@Test func scaledFromBoardOnAnExpandedSizedBoardRoundsAwayFromZero() {
    // radius 3 = 37 tiles, ratio 37/19 = 1.947368... - both piece counts land
    // on a genuine fraction, so this also pins the rounding rule: `.rounded()`
    // is round-half-away-from-zero, and 5*ratio=9.7368 and 4*ratio=7.7895
    // both round UP. (An exact x.5 tie is unreachable here: the ratio's
    // denominator is 19, which is odd, so 5*tileCount/19 and 4*tileCount/19
    // can never land exactly on a half-integer.)
    let board = syntheticBoard(radius: 3)
    #expect(board.tileCount == 37)
    #expect(PieceAllowance.scaledFromBoard.limit(for: .settlement, board: board) == 10)
    #expect(PieceAllowance.scaledFromBoard.limit(for: .city, board: board) == 8)
    // Bank scales exactly: 19 * (37/19) == 37 with no fractional part to round.
    #expect(BankAllowance.scaledFromBoard.perResource(board: board) == 37)
}

@Test func scaledFromBoardOnAMuchLargerBoardRoundsDownWhenTheFractionIsBelowHalf() {
    // radius 10 = 331 tiles, ratio 331/19 = 17.42105... - the opposite
    // rounding direction from the radius-3 case (5*ratio=87.105 rounds DOWN
    // to 87, 4*ratio=69.684 rounds DOWN to 70), so both directions of
    // `.rounded()` are pinned by this pair of tests, not just one.
    let board = syntheticBoard(radius: 10)
    #expect(board.tileCount == 331)
    #expect(PieceAllowance.scaledFromBoard.limit(for: .settlement, board: board) == 87)
    #expect(PieceAllowance.scaledFromBoard.limit(for: .city, board: board) == 70)
    #expect(BankAllowance.scaledFromBoard.perResource(board: board) == 331)
}

@Test func aModeWhoseRoadLimitOutrunsTheSearchIsRefused() {
    // The tripwire: a future mode must fail at construction, not by freezing
    // the game on a road placement.
    let reckless = Ruleset(
        board: .expanded, victoryPointTargets: 25...25, defaultVictoryPointTarget: 25,
        longestRoadBonus: 4, largestArmyBonus: 4, longestRoadMinimum: 5, largestArmyMinimum: 3,
        pieceLimits: .explicit([.settlement: 10, .city: 8]),
        victoryPointsPerBuilding: [.settlement: 1, .city: 2],
        maxRoadsPerPlayer: LongestRoad.supportedRoadLimit + 1,
        bank: .explicit(38),
        devCardDeck: [.knight: 28, .victoryPoint: 10, .roadBuilding: 4, .yearOfPlenty: 4, .monopoly: 4],
        discardThreshold: 10
    )
    #expect(reckless.validationProblem != nil)
}
