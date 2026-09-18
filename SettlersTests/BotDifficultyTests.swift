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
        setup.victoryPointTarget = 10

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

/// Human proposals must reach the same policy as automated negotiations.
/// Isolated checkpoint stores exercise cold restoration without sharing saves.
@MainActor @Suite(.serialized) struct HumanTradePolicyTests {
    @Test(arguments: BotDifficulty.allCases, [false, true])
    func newHumanOfferUsesConfiguredPolicy(tier: BotDifficulty, generous: Bool) throws {
        let fixture = try CheckpointModelFixture()
        let model = try makeTradeModel(fixture, tier: tier)
        let offer = makeOffer(generous: generous)
        var proposed = model.session
        try proposed.applyExternal(.proposeTrade(offer), by: model.humanPlayer)
        let expected = try policyAnswers(in: proposed, offer: offer)
        try requireDiscriminatingAnswers(expected, tier: tier, generous: generous)
        let cursor = model.session.policyRNG

        try model.apply(.proposeTrade(offer))

        let decisions = try #require(model.pendingTradeConfirmation?.decisions ?? model.lastTradeOutcome?.decisions)
        #expect(Dictionary(uniqueKeysWithValues: decisions.map { ($0.bot, $0.accepted) }) == expected)
        #expect(model.session.policyRNG == cursor)
        #expect(model.persistenceErrorMessage == nil)
    }

    @Test(arguments: BotDifficulty.allCases, [false, true])
    func coldRestoredHumanOfferUsesConfiguredPolicy(tier: BotDifficulty, generous: Bool) throws {
        let fixture = try CheckpointModelFixture()
        let model = try makeTradeModel(fixture, tier: tier)
        let offer = makeOffer(generous: generous)
        // Persist the proposal before presentation, as if the app exited at
        // that boundary. Resume must reconstruct policy-correct answers.
        var candidate = model.session
        let step = try candidate.applyExternal(.proposeTrade(offer), by: model.humanPlayer)
        let document = try #require(model.checkpointDocument)
        try model.commitDocument(document.recording(step, session: candidate.checkpoint,
                                                    elapsedSeconds: model.currentGameDuration))
        model.session = candidate
        let expected = try policyAnswers(in: model.session, offer: offer)
        try requireDiscriminatingAnswers(expected, tier: tier, generous: generous)
        let checkpoint = model.session.checkpoint

        let restored = fixture.makeModel()

        #expect(restored.savedGameAvailability.canResume)
        for (seat, accepted) in expected {
            let actual = restored.pendingTradeConfirmation?.decisions.first { $0.bot == seat }?.accepted ?? false
            #expect(actual == accepted, "cold resume bypassed the configured policy for \(seat)")
        }
        #expect(restored.session.checkpoint == checkpoint, "presenting a restored answer must not consume policy RNG")
        restored.restorePendingNegotiation()
        #expect(restored.session.checkpoint == checkpoint, "reconstructing presentation must be idempotent")
    }

    private func makeTradeModel(_ fixture: CheckpointModelFixture, tier: BotDifficulty) throws -> GameViewModel {
        let model = fixture.makeModel()
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 33, playerCount: 3)
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].resources = [.grain: 6]
        state.players[1].resources = [.brick: 2]
        state.bank[.grain] = 13
        state.bank[.brick] = 17
        model.replaceStateForTesting(state, humanSeat: PlayerID(index: 0))
        var setup = try #require(model.checkpointDocument?.activeMatch?.setup)
        setup.difficulty = tier
        let session = GameViewModel.makeSession(
            state: state, opponentProfiles: model.opponentProfiles, difficulty: tier
        )
        try model.replaceActiveMatch(state: state, setup: setup, session: session)
        try model.installCheckpointMatch()
        model.isBlockingSurfaceOpen = true
        return model
    }

    private func makeOffer(generous: Bool) -> TradeOffer {
        TradeOffer.enumerated(from: PlayerID(index: 0),
                              give: [.grain: generous ? 4 : 1], want: [.brick: generous ? 1 : 2])
    }

    /// Use the actual seated policy and counted ledger, never duplicate either
    /// tier's valuation formula. A local RNG copy keeps this oracle read-only.
    private func policyAnswers(in session: GameSession, offer: TradeOffer) throws -> [PlayerID: Bool] {
        var answers: [PlayerID: Bool] = [:]
        var rng = session.policyRNG
        for seat in session.policies.keys.sorted() {
            let policy = try #require(session.policies[seat])
            var legal: [GameMove] = [.respondToTrade(offerID: offer.id, accept: false)]
            if Trading.bothSidesCanHonour(offer, responder: seat, state: session.state) {
                legal.insert(.respondToTrade(offerID: offer.id, accept: true), at: 0)
            }
            let observation = GameObservation(seat: seat, state: session.state, legalMoves: legal)
            let move: GameMove
            if let aware = policy as? any LedgerAwarePolicy {
                move = aware.decide(observation, ledger: session.ledger(for: seat), rng: &rng)
            } else {
                move = policy.decide(observation, rng: &rng)
            }
            answers[seat] = move == .respondToTrade(offerID: offer.id, accept: true)
        }
        return answers
    }

    private func requireDiscriminatingAnswers(
        _ answers: [PlayerID: Bool], tier: BotDifficulty, generous: Bool
    ) throws {
        try #require(answers[PlayerID(index: 1)] == (generous || tier == .classic),
                     "fixture must distinguish Expert from Classic on the two-brick offer")
        try #require(answers[PlayerID(index: 2)] == false, "an empty-handed bot cannot accept")
    }
}
