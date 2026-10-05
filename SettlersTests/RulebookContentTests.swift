import CatanEngine
import Testing
@testable import Settlers

/// Copy is a product contract: the active board's numbers and the three kinds
/// of resource loss must remain distinct even when screen layout changes.
@Suite struct RulebookContentTests {
    @Test func menuGuideKeepsClassicDefaultsAndTheExistingWalkthrough() throws {
        #expect(HowToPlayContent.steps.count == 10)
        #expect(HowToPlayContent.steps.first?.line.contains("10 victory points") == true)
        #expect(HowToPlayContent.modes.map(\.id) == ["classic", "vast", "conquest"])
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

    private func section(_ id: String, in sections: [HowToPlayContent.Section]) throws -> HowToPlayContent.Section {
        try #require(sections.first { $0.id == id })
    }

    private func makeContext(mode: GameMode, variant: GameVariant = .standard,
                             target: Int? = nil, price: ArmyPrice = .anyThree) -> HowToPlayContent.Context {
        var state = GameSetup.newGame(board: BoardGenerator.standard(Ruleset.forMode(mode).board), seed: 7,
                                      victoryPointTarget: target, mode: mode, variant: variant)
        state.armyPrice = price
        return HowToPlayContent.Context(state: state)
    }
}
