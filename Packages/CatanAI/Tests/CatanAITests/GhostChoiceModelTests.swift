import Foundation
import Testing
import CatanEngine
@testable import CatanAI

@Suite struct GhostChoiceModelTests {

    // MARK: - Situational recovery

    /// A person with one firm habit: the robber goes on the highest-pip hex
    /// that spares their own buildings, then the one with most rival
    /// buildings, robbing whoever holds most cards. Expert rarely does this;
    /// the ghost must, at robber moments it never trained on. This is the
    /// situational test `ghost fidelity` runs on real games, with a person
    /// whose answer is known.
    @Test func aRobberHabitIsLearnedAndReplayedOnUnseenBoards() {
        let training = robberMoments(seeds: 300..<304)
        let unseen = robberMoments(seeds: 400..<403)
        #expect(training.count >= 20 && unseen.count >= 12, "too few robber moments: \(training.count), \(unseen.count)")
        let records = training.map { ChoiceRecord(options: $0.options, person: $0.habit, seat: $0.seat, state: $0.state) }
        let model = ChoiceFitter.fit(records)
        let ghost = unseen.filter { $0.equallyGood.contains(model.choose($0.options, seat: $0.seat, state: $0.state)) }.count
        let expert = unseen.filter { moment in moment.equallyGood.contains(moment.options.max { $0.score < $1.score }!.move) }.count
        #expect(Double(ghost) >= 0.8 * Double(unseen.count), "ghost matched \(ghost)/\(unseen.count), Expert \(expert)")
        #expect(ghost > expert)
    }

    private struct Moment {
        let state: GameState
        let seat: PlayerID
        let options: [ScoredCandidate]
        let habit: GameMove
        /// Every move the habit rates as highly: two hexes alike in pips,
        /// buildings and victim are the same decision to this person.
        let equallyGood: Set<GameMove>
    }

    /// Every robber placement in Greedy self-play, with the habit's answer.
    private func robberMoments(seeds: Range<UInt64>) -> [Moment] {
        let ghost = GhostPolicy(person: .anchored(at: .forMode(.classic)), lambda: 0)
        var result: [Moment] = []
        for seed in seeds {
            let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
            var policies: [PlayerID: any Policy] = [:]
            for player in initial.players { policies[player.id] = GreedyPolicy() }
            var session = GameSession(state: initial, policies: policies, policySeed: seed)
            var steps = 0
            while steps < 600, let step = try? session.step() {
                steps += 1
                guard case .movingRobber = session.state.phase, case .seat(let seat) = session.nextActor() else { _ = step; continue }
                let state = session.state
                let observation = GameObservation(seat: seat, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: seat))
                let options = ghost.expertOptions(observation, ledger: .fromPositionAlone(state, observer: seat))
                let moves = options.map(\.move)
                guard options.count > 1, let habit = robberHabit(moves, seat: seat, state: state) else { continue }
                let best = habitKey(habit, seat: seat, state: state)
                result.append(Moment(state: state, seat: seat, options: options, habit: habit,
                                     equallyGood: Set(moves.filter { habitKey($0, seat: seat, state: state) == best })))
            }
        }
        return result
    }

    private func robberHabit(_ moves: [GameMove], seat: PlayerID, state: GameState) -> GameMove? {
        moves.max { habitKey($0, seat: seat, state: state).lexicographicallyPrecedes(habitKey($1, seat: seat, state: state)) }
    }

    private func habitKey(_ move: GameMove, seat: PlayerID, state: GameState) -> [Double] {
        guard case .moveRobber(let hex, let victim) = move else { return [-1] }
        let row = ChoiceFeatures.Geometry(seat: seat, state: state).robber(hex, victim: victim)
        return row["r_mine"] == 1 ? [-1] : [row["r_pips"]!, row["r_oppB"]!, row["r_vHand"]!]
    }

    // MARK: - The two steps

    private func midGame(seed: UInt64 = 83) -> (GameState, PlayerID) {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        playOpeningPlacements(in: &state, seed: seed)
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].resources = [.brick: 2, .lumber: 2, .ore: 1, .grain: 1, .wool: 1]
        return (state, state.players[0].id)
    }

    /// The kind is chosen first: a strong "end the turn" habit ends it
    /// whatever Expert thinks of the builds on offer.
    @Test func theKindIsChosenBeforeTheOption() {
        let (state, seat) = midGame()
        let observation = GameObservation(seat: seat, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: seat))
        let options = GhostPolicy(person: .anchored(at: .forMode(.classic)), lambda: 0)
            .expertOptions(observation, ledger: .fromPositionAlone(state, observer: seat))
        let ender = ChoiceModel(kinds: ["k_endTurn": 10], families: [:], decisions: 1)
        #expect(ender.choose(options, seat: seat, state: state) == .endTurn)
        let builder = ChoiceModel(kinds: ["k_buildRoad": 10], families: ["road": ["expert": 1]], decisions: 1)
        let roads = options.filter { if case .buildRoad = $0.move { true } else { false } }
        #expect(builder.choose(options, seat: seat, state: state) == roads.max { $0.score < $1.score }?.move)
    }

    /// A seeded game replays move for move only if a fit is the same on every
    /// launch, whatever order its dictionaries iterate in.
    @Test func fittingIsDeterministic() {
        let records = robberMoments(seeds: 300..<301).map {
            ChoiceRecord(options: $0.options, person: $0.habit, seat: $0.seat, state: $0.state)
        }
        #expect(ChoiceFitter.fit(records) == ChoiceFitter.fit(records.reversed().reversed()))
    }

    // MARK: - Ghost seat

    /// With a choice model the ghost still rolls first: Jake's 8 knights before
    /// the dice in 136 chances followed no situation a fit could find.
    @Test func aChoiceGhostRollsBeforeAnythingElse() {
        var (state, seat) = midGame()
        state.phase = .rollDice(playerIndex: 0)
        state.players[0].devCards = [.knight]
        let legal = RulesEngine.legalMoves(for: state, seat: seat)
        #expect(legal.contains { if case .playKnight = $0 { true } else { false } })
        var rng = RandomSource(seed: 1)
        let ghost = GhostPolicy(person: .anchored(at: .forMode(.classic)), lambda: 0,
                                choices: ChoiceModel(kinds: ["k_playKnight": 100], families: [:], decisions: 1))
        #expect(ghost.decide(GameObservation(seat: seat, state: state, legalMoves: legal), rng: &rng) == .rollDice)
    }

    /// "Six wool for a grain and two ore" is one move in the app and three
    /// for a bot; the ghost's first swap of it is the same decision.
    @Test func aSwapOfTheBankTradeThePersonMadeMatches() {
        let person = GameMove.bankTrade(give: [.wool: 6], get: [.grain: 1, .ore: 2])
        #expect(GhostFidelity.matches(.bankTrade(give: [.wool: 2], get: [.ore: 1]), person))
        #expect(!GhostFidelity.matches(.bankTrade(give: [.wool: 2], get: [.brick: 1]), person))
        #expect(!GhostFidelity.matches(.bankTrade(give: [.grain: 2], get: [.ore: 1]), person))
    }

    /// A ghost saved before choice models decodes without one, and keeps playing.
    @Test func aGhostSavedBeforeChoiceModelsDecodes() throws {
        let old = GhostProfile(id: "jake", name: "Jake's Ghost", person: .anchored(at: .forMode(.classic)),
                               lambda: 0.01, gamesLearned: 3)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "choices")
        let decoded = try JSONDecoder().decode(GhostProfile.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.choices == nil)
        var learned = old
        learned.choices = ChoiceModel(kinds: ["expert": 1], families: [:], decisions: 120)
        #expect(try JSONDecoder().decode(GhostProfile.self, from: JSONEncoder().encode(learned)) == learned)
    }
}
