import CatanEngine
import Foundation
import Testing
@testable import Settlers

/// Copy is a product contract: the active board's numbers and the three kinds
/// of resource loss must remain distinct even when screen layout changes.
@Suite struct RulebookContentTests {
    @Test func menuGuideKeepsClassicDefaultsAndTheExistingWalkthrough() throws {
        #expect(HowToPlayContent.steps.count == 10)
        #expect(HowToPlayContent.steps.first?.line.contains("10 victory points") == true)
        #expect(HowToPlayContent.modes.map(\.id) == ["classic", "vast", "conquest", "voyages"])
        #expect(HowToPlayContent.introduction.contains("rules of Empires"))
        #expect(HowToPlayContent.introduction.contains("not the official CATAN rulebook"))
        let losses = try section("resource-loss", in: HowToPlayContent.rules).resourceLosses
        #expect(losses.map(\.id) == ["knight", "monopoly", "seven"])
    }

    @Test func vastGuideUsesItsTargetSuppliesAndDiscardThreshold() throws {
        let context = makeContext(mode: .vast)
        let rules = HowToPlayContent.rules(for: context)
        #expect(try section("goal", in: rules).summary.contains("26 victory points"))
        let building = try section("build", in: rules).details.joined(separator: " ")
        #expect(building.contains("14 settlements, 12 cities and 38 roads"))
        #expect(try section("robber", in: rules).details.joined().contains("more than 12"))
        let bonuses = try section("bonuses", in: rules)
        #expect(bonuses.summary.contains("Longest Road adds 4 points; Largest Army adds 4"))
        let vast = try section("vast", in: HowToPlayContent.modes(for: context))
        #expect(vast.summary.contains("61-hex"))
        #expect(vast.details.joined().contains("60 cards of each resource and 82 development cards"))
        #expect(vast.details.joined().contains("6 Monopoly cards"))
        #expect(HowToPlayContent.steps(for: context).first?.line.contains("26 victory points") == true)
    }

    @Test func savedClassicTargetIsNotReplacedWithTheNewGameDefault() throws {
        let context = makeContext(mode: .classic, target: 12)
        #expect(try section("goal", in: HowToPlayContent.rules(for: context)).summary.contains("12 victory points"))
        #expect(context.title == "Classic · Standard · 12 points")
    }

    @Test(arguments: [8, 10, 12])
    func resumedVictoryPresentationUsesTheSavedTarget(target: Int) throws {
        let original = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7, victoryPointTarget: target)
        let restored = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(original))
        #expect(VictoryTargetText.goal(restored.victoryPointTarget) == "First to \(target) victory points wins.")
        #expect(VictoryTargetText.compactGoal(restored.victoryPointTarget) == "Win at \(target) VP")
        #expect(VictoryTargetText.score(2, target: restored.victoryPointTarget) == "2 / \(target) VP")
        #expect(VictoryTargetText.spokenScore(2, target: restored.victoryPointTarget).contains("\(target) needed to win"))
    }

    @Test func harvestRulebookExplainsTheNumberAndBothBuildingYields() throws {
        let state = Naval.newGame(seed: 7501)
        let voyages = try section("voyages", in: HowToPlayContent.rules(for: HowToPlayContent.Context(state: state)))
        let copy = voyages.details.joined(separator: " ")
        #expect(copy.contains("harvest field's number rolls"))
        #expect(copy.contains("settlement chooses 1 resource"))
        #expect(copy.contains("city chooses 2 resources"))
        #expect(copy.contains("same resource twice is allowed"))
    }

    @Test(arguments: ArmyPrice.allCases)
    func conquestDescribesTheSavedArmyPriceAndItsSeparateCardRules(price: ArmyPrice) throws {
        let context = makeContext(mode: .vast, variant: .conquest, price: price)
        let conquest = try section("conquest", in: HowToPlayContent.rules(for: context))
        let text = conquest.details.joined(separator: " ")
        #expect(text.contains("Army cards cost \(price.label)"))
        #expect(text.contains("not Knight development cards"))
        #expect(text.contains("do not count toward Largest Army"))
        #expect(text.contains("not the dice or how many cards a Knight steals"))
        #expect(!HowToPlayContent.rules.contains { $0.id == "conquest" })
    }

    @Test func lossesExplainOneCardOneTypeAndDiscardToTheBank() throws {
        let losses = HowToPlayContent.resourceLosses(for: makeContext(mode: .vast))
        let knight = try #require(losses.first { $0.id == "knight" })
        let monopoly = try #require(losses.first { $0.id == "monopoly" })
        let seven = try #require(losses.first { $0.id == "seven" })
        #expect(knight.explanation.contains("one random resource card from one rival"))
        #expect(knight.example.contains("9 cards keeps 8"))
        #expect(monopoly.example.contains("gives 4 Ore and keeps 3 Grain"))
        #expect(seven.explanation.contains("Above 12 resources"))
        #expect(seven.explanation.contains("to the bank"))
        #expect(seven.example.contains("14 cards, discard 7"))
    }

    @Test func cardTimingConsumptionAndEmpiresPlacementLimitsAreExplicit() throws {
        let cards = try section("cards", in: HowToPlayContent.rules).details.joined(separator: " ")
        #expect(cards.contains("another mature copy"))
        #expect(cards.contains("collects nothing still spends the card"))
        #expect(cards.contains("before or after rolling"))
        #expect(cards.contains("Empires requires a legal pair"))
        #expect(cards.contains("Victory Point card counts immediately"))
    }

    @Test func expandedAppearsOnlyForAnExistingExpandedMatch() throws {
        let context = makeContext(mode: .expanded)
        let expanded = try section("expanded", in: HowToPlayContent.modes(for: context))
        #expect(expanded.summary.contains("37-hex game continues to 25"))
        #expect(!HowToPlayContent.modes.contains { $0.id == "expanded" })
    }

    @Test func navalGuideUsesSavedFogAndResourceOptionsAndColonizationRules() throws {
        let state = Naval.newGame(seed: 7501, options: NavalOptions(fogEnabled: false,
            resourceChoiceEnabled: false, mapFamily: .twinIslands))
        let context = HowToPlayContent.Context(state: state)
        let rules = HowToPlayContent.rules(for: context)
        let voyages = try section("voyages", in: rules)
        let text = voyages.details.joined(separator: " ")
        #expect(try section("goal", in: rules).summary.contains("14 victory points"))
        #expect(text.contains("Fog is off for this match"))
        #expect(text.contains("Resource-choice islands are off for this match"))
        #expect(text.contains("Establish your own settlement before building roads"))
        #expect(text.contains("first two overseas islands"))
        #expect(text.contains("Ship stealing is off by default"))
        #expect(text.contains("38 cards of each resource and 50 development cards"))
        #expect(text.contains("local and unrated"))
        #expect(text.contains("six hulls"))
        #expect(text.contains("Both starting settlements may be inland or coastal on the home island"))
        #expect(text.contains("then expand inland along your roads"))
        #expect(try section("setup", in: rules).details.joined().contains("including inland corners"))
        #expect(try section("build", in: rules).details.joined().contains("a ship beside a legal coastal corner"))
        #expect(try section("robber", in: rules).details.joined().contains("discovered land hex"))
    }

    @Test func navalCaptureGuideReflectsTheActualMatchOption() throws {
        let state = Naval.newGame(seed: 7501, options: NavalOptions(shipStealingEnabled: true))
        let voyages = try section("voyages", in: HowToPlayContent.rules(for: .init(state: state)))
        let text = voyages.details.joined(separator: " ")
        #expect(text.contains("Ship stealing is on for this match"))
        #expect(text.contains("On an 11, collect resources"))
        #expect(text.contains("acknowledge the ownership notice"))
        #expect(!text.contains("Ship stealing is off by default"))
    }

    private func section(_ id: String, in sections: [HowToPlayContent.Section]) throws -> HowToPlayContent.Section {
        try #require(sections.first { $0.id == id })
    }

    @Test(arguments: [1, 2, 3, 4, 5])
    func navalTravelGuideMatchesTheSavedRuleVersion(_ version: Int) throws {
        var state = Naval.newGame(seed: 7501)
        state.naval?.rulesVersion = version
        let context = HowToPlayContent.Context(state: state)
        let voyages = try section("voyages", in: HowToPlayContent.rules(for: context))
        let text = voyages.details.joined(separator: " ")
        if version >= Naval.blockadeRulesVersion {
            #expect(text.contains("Your own ships may share water"))
            #expect(text.contains("Opposing ships block entry, passage and launches"))
        } else {
            #expect(text.contains("Ships sail independently and may share water"))
            #expect(!text.contains("Opposing ships block entry"))
        }
        if version < Naval.destinationSailingRulesVersion {
            #expect(text.contains("three hexes per turn, sailed one adjacent sea hex at a time"))
            #expect(!text.contains("up to two sea hexes"))
        } else {
            #expect(text.contains("up to two sea hexes"))
            #expect(text.contains("Choose any highlighted destination"))
            #expect(!text.contains("three hexes per turn"))
        }
    }

    @Test(arguments: [1, 2, 3, 4, 5])
    func navalDiscardGuideUsesTheSavedThresholdEverywhere(_ version: Int) throws {
        var state = Naval.newGame(seed: 7501)
        state.naval?.rulesVersion = version
        let context = HowToPlayContent.Context(state: state)
        let threshold = version < Naval.sevenRulesVersion ? 10 : 7
        let rules = HowToPlayContent.rules(for: context)
        #expect(context.ruleset == state.rules)
        #expect(try section("robber", in: rules).details.joined().contains("more than \(threshold)"))
        let seven = try #require(HowToPlayContent.resourceLosses(for: context).first { $0.id == "seven" })
        #expect(seven.explanation.contains("Above \(threshold) resources"))
        #expect(try section("voyages", in: rules).details.joined().contains("above \(threshold) cards"))
        #expect(try section("voyages", in: HowToPlayContent.modes(for: context)).details.joined().contains("above \(threshold) cards"))
    }

    private func makeContext(mode: GameMode, variant: GameVariant = .standard,
                             target: Int? = nil, price: ArmyPrice = .anyThree) -> HowToPlayContent.Context {
        var state = GameSetup.newGame(board: BoardGenerator.standard(Ruleset.forMode(mode).board), seed: 7,
                                      victoryPointTarget: target, mode: mode, variant: variant)
        state.armyPrice = price
        return HowToPlayContent.Context(state: state)
    }
}
