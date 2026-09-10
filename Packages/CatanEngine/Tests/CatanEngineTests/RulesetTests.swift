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
