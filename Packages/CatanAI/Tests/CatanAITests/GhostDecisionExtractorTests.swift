import Testing
import CatanEngine
@testable import CatanAI

@Suite struct GhostDecisionExtractorTests {

    /// A short real game: every seat Expert, first `moves` moves, seat 0 treated as the human.
    private func loggedGame(seed: UInt64 = 91, moves: Int = 120) throws -> LoggedGame {
        let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        var policies: [PlayerID: any Policy] = [:]
        for player in initial.players { policies[player.id] = EvaluationPolicy() }
        var session = GameSession(state: initial, policies: policies, policySeed: seed)
        var events: [LoggedMove] = []
        while events.count < moves, let step = try session.step() {
            events.append(LoggedMove(player: step.actor, move: step.move))
        }
        return LoggedGame(id: "g\(seed)", initialState: initial, humanSeats: [initial.players[0].id], events: events)
    }

    @Test func everyRecordNamesAChosenCandidateAndHasFullVectors() throws {
        let records = try DecisionExtractor.decisions(in: loggedGame(), anchor: .forMode(.classic))
        #expect(!records.isEmpty)
        for record in records {
            #expect(record.candidates.indices.contains(record.chosen))
            #expect(record.candidates.count > 1)
            #expect(record.candidates.allSatisfy {
                $0.gradient.count == EvaluationWeights.vectorLabels.count && $0.style.count == StyleFeatures.labels.count
            })
        }
        #expect(records.contains { $0.facet == .opening })
        #expect(records.contains { $0.facet == .turn })
    }

    /// The linearisation must predict a real re-score for a small weight change.
    @Test func gradientPredictsARescore() throws {
        let game = try loggedGame(moves: 40)
        let anchor = EvaluationWeights.forMode(.classic)
        let record = try #require(DecisionExtractor.decisions(in: game, anchor: anchor).last)
        var shifted = anchor.vector
        shifted[1] += 0.02
        let rescored = try #require(DecisionExtractor.decisions(in: game, anchor: EvaluationWeights(vector: shifted)).last)
        #expect(record.candidates.count == rescored.candidates.count)
        for (a, b) in zip(record.candidates, rescored.candidates) {
            #expect(abs(a.score + a.gradient[1] * 0.02 - b.score) < 1e-3, "\(a.move)")
        }
    }

    @Test func frozenWeightsHaveZeroGradient() throws {
        let records = try DecisionExtractor.decisions(in: loggedGame(moves: 40), anchor: .forMode(.classic))
        for record in records {
            for candidate in record.candidates {
                for slot in DecisionExtractor.frozen.sorted() { #expect(candidate.gradient[slot] == 0) }
            }
        }
    }

    /// Review Focus 1: a log that stops replaying fails loudly, naming where.
    @Test func aMoveThatDoesNotReplayThrowsWithItsIndex() throws {
        let game = try loggedGame(moves: 20)
        var events = game.events
        events[12] = LoggedMove(player: events[12].player, move: .buildCity(VertexID(touchingTiles: [])))
        let broken = LoggedGame(id: game.id, initialState: game.initialState, humanSeats: game.humanSeats, events: events)
        #expect {
            try DecisionExtractor.decisions(in: broken, anchor: .forMode(.classic))
        } throws: { error in
            guard case ExtractionError.divergedAt(_, let index, _) = error else { return false }
            return index == 12
        }
    }
}
