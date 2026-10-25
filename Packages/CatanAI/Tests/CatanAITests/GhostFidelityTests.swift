import Testing
import CatanEngine
@testable import CatanAI

@Suite struct GhostFidelityTests {

    /// The first `moves` of an Expert game with every seat as "the person": every situation,
    /// every option family, and a known answer at each decision.
    private func expertGame(seed: UInt64 = 57, moves: Int = 300) throws -> LoggedGame {
        let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        var policies: [PlayerID: any Policy] = [:]
        for player in initial.players { policies[player.id] = EvaluationPolicy() }
        var session = GameSession(state: initial, policies: policies, policySeed: seed)
        var events: [LoggedMove] = []
        while events.count < moves, let step = try session.step() {
            events.append(LoggedMove(player: step.actor, move: step.move))
        }
        return LoggedGame(id: "expert\(seed)", initialState: initial,
                          humanSeats: Set(initial.players.map(\.id)), events: events)
    }

    /// A choice model fitted on a person's games makes that person's moves
    /// back, judged the way `ghost fidelity` judges a real person.
    @Test func aChoiceGhostFittedOnAPersonAgreesWithThem() throws {
        let game = try expertGame()
        let records = try ChoiceRecord.records(in: game)
        #expect(records.count >= ChoiceFitter.minimumDecisions)
        let ghost = GhostPolicy(person: .anchored(at: .forMode(.classic)), lambda: 0, choices: ChoiceFitter.fit(records))
        let moments = try GhostFidelity.moments(in: game, policy: ghost)
        let situations = Set(moments.flatMap(\.situations))
        #expect(situations.isSuperset(of: [.openingSettlement, .openingRoad, .turnOther]), "\(situations)")
        let exact = moments.filter(\.exact).count, kind = moments.filter(\.sameKind).count
        #expect(Double(exact) >= 0.5 * Double(moments.count), "exact \(exact)/\(moments.count)")
        #expect(kind >= exact)
    }

    /// The person model's own scores can ride along as a feature.
    @Test func personScoresJoinTheRecordsWhenAPersonModelIsGiven() throws {
        let records = try ChoiceRecord.records(in: expertGame(seed: 58, moves: 120), person: .anchored(at: .forMode(.classic)))
        let model = ChoiceFitter.fit(records)
        #expect(model.needsPerson)
    }
}
