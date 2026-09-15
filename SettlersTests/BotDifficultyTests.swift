import Testing
import Foundation
import CatanEngine
import CatanAI
@testable import Settlers

/// Difficulty is the first setting in this app that reaches a *decision*
/// rather than a delay, so the things worth pinning are about where it is
/// allowed to take effect, not about how it looks.
@MainActor @Suite struct BotDifficultyTests {

    /// Each tier seats the policy it names. The whole control is a lie
    /// otherwise.
    @Test func eachTierSeatsItsOwnPolicy() {
        let profile = OpponentProfile(
            id: "charlemagne", name: "Charlemagne", civilization: .medieval, strategy: .cautious
        )
        #expect(BotDifficulty.classic.policy(for: profile).id == "heuristic-cautious")
        #expect(BotDifficulty.expert.policy(for: profile).id == "evaluation-v1")
    }

    /// A game in progress must not have its opponents replaced by stronger
    /// ones because an update shipped. Every setup written before this control
    /// existed decodes to Classic, which is what those games were played
    /// against.
    @Test func aSetupSavedBeforeDifficultyExistedResumesOnClassic() throws {
        let legacy = """
        {"seats":[{"index":0,"isHuman":true,"name":"Jake"},
                  {"index":1,"isHuman":false,"name":""},
                  {"index":2,"isHuman":false,"name":""},
                  {"index":3,"isHuman":false,"name":""}],
         "victoryPointTarget":10,"randomizedBoard":false,"randomizeSeatOrder":false}
        """
        let setup = try JSONDecoder().decode(MatchSetup.self, from: Data(legacy.utf8))
        #expect(setup.difficulty == .classic, "an older save must not silently gain stronger bots")
    }

    /// And the chosen tier has to survive the round trip, or a resumed match
    /// quietly changes difficulty at the first relaunch.
    @Test func theChosenTierSurvivesASaveAndReload() throws {
        var setup = MatchSetup.default(preferredName: "Jake", preferredCivilization: .medieval)
        setup.difficulty = .expert
        let reloaded = try JSONDecoder().decode(
            MatchSetup.self, from: try JSONEncoder().encode(setup)
        )
        #expect(reloaded.difficulty == .expert)
    }

    /// Difficulty selects the brain; it must not touch the opponent's
    /// identity or voice. `OpponentProfile`'s own doc comment asks for exactly
    /// this - difficulty "composed alongside this profile without changing the
    /// opponent's identity or voice".
    @Test func difficultyLeavesIdentityAndVoiceAlone() {
        let profile = OpponentProfile(
            id: "alexander", name: "Alexander", civilization: .greece, strategy: .aggressive
        )
        for tier in BotDifficulty.allCases {
            _ = tier.policy(for: profile)
            #expect(profile.name == "Alexander")
            #expect(profile.dialogueVoice == Civilization.greece.tradeMessagesEmpire)
        }
    }

    /// Every seat at the table plays the tier the match was started under.
    @Test func everySeatGetsTheChosenTier() {
        let profiles = [
            PlayerID(index: 1): OpponentProfile(id: "a", name: "A", civilization: .greece, strategy: .balanced),
            PlayerID(index: 2): OpponentProfile(id: "b", name: "B", civilization: .egypt, strategy: .cautious),
        ]
        let expert = GameViewModel.makePolicies(profiles, difficulty: .expert)
        #expect(expert.count == 2)
        #expect(expert.values.allSatisfy { $0.id == "evaluation-v1" })

        let classic = GameViewModel.makePolicies(profiles, difficulty: .classic)
        #expect(classic.values.allSatisfy { $0.id.hasPrefix("heuristic-") })
    }

    /// The bug this control shipped with, for about an hour.
    ///
    /// Starting an Expert match failed with "The new game could not be saved"
    /// - not a wrong setting, a refusal. `realisedMatch` rebuilt `MatchSetup`
    /// field by field and did not list `difficulty`, so the session was built
    /// with `EvaluationPolicy` while the realized record claimed Classic.
    /// `installCheckpointMatch` restores through `makePolicies` to check its
    /// own work, the policy IDs disagreed, and `GameSession.init(checkpoint:)`
    /// threw `incompatibleCheckpoint`.
    ///
    /// Every tier is started here rather than just Expert, because Classic
    /// passed throughout - a test that only covered the default would have
    /// stayed green through the whole outage.
    @Test(arguments: BotDifficulty.allCases)
    func aMatchStartsAndSavesAtEveryTier(_ tier: BotDifficulty) throws {
        let model = GameViewModel()
        var setup = model.newGameSetupLoadResult.value
            ?? MatchSetup.default(preferredName: "Jake", preferredCivilization: .medieval)
        setup.difficulty = tier
        try #require(setup.isStartable, "fixture is not startable: \(setup.validationProblem ?? "")")

        model.startNewGame(setup: setup)

        #expect(
            model.persistenceErrorMessage == nil,
            "starting a \(tier.displayName) match failed: \(model.persistenceErrorMessage ?? "")"
        )
    }

    /// The structural half of the same bug: realizing the chairs must not drop
    /// anything else about the match. Asserted on the whole value rather than
    /// on `difficulty` alone, so the next field added to `MatchSetup` is
    /// covered by this test without anyone editing it.
    @Test func realizingTheChairsChangesOnlyTheSeats() {
        var setup = MatchSetup.default(preferredName: "Jake", preferredCivilization: .medieval)
        setup.difficulty = .expert
        setup.randomizedBoard = true
        setup.victoryPointTarget = 8

        let realized = GameViewModel.realisedMatch(
            chairs: setup.seats,
            civilizations: Array(Civilization.allCases.prefix(setup.seats.count)),
            opponentProfiles: [:],
            from: setup
        )

        var expected = setup
        expected.seats = realized.seats
        #expect(realized == expected, "realizing the chairs changed something other than the seats")
    }
}
