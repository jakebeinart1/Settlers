import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@MainActor
@Suite(.serialized)
struct PolicyTracePersistenceTests {
    @Test func actualNeuralMovesSurviveCheckpointResumeAndExport() async throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        var setup = fixture.setup
        setup.seats[0].isHuman = false
        setup.seats[0].name = ""
        setup.seats[1].isHuman = true
        setup.seats[1].name = "Alex"
        model.startNewGame(setup: setup)
        await model.runBotTurnIfNeeded()

        let match = try #require(model.checkpointDocument?.activeMatch)
        #expect(match.moves.count == 2, "the bot must actually place its settlement and road")
        for record in match.moves {
            let trace = try #require(record.policyTrace)
            #expect(trace.policyID.hasPrefix("upstream-r2-hybrid-"))
            #expect(trace.selection.source == "neural")
            #expect(trace.selection.fallbackReason == nil)
            #expect(trace.selection.move == record.move)
        }
        let resumed = fixture.makeModel()
        #expect(resumed.checkpointDocument?.activeMatch?.moves == match.moves)
        #expect(resumed.session.checkpoint == model.session.checkpoint)
        let summary = try #require(fixture.logStore.summaries().first)
        let detail = try fixture.logStore.detail(for: summary)
        #expect(detail.events.map(\.policyTrace) == match.moves.map(\.policyTrace))
    }

    @Test func oldRecordedMoveDoesNotInventNeuralProvenance() throws {
        let record = MatchCheckpoint.RecordedMove(actor: PlayerID(index: 0), move: .rollDice,
                                                  timestamp: Date(timeIntervalSince1970: 0))
        let wire = try JSONEncoder().encode(record)
        let object = try #require(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        #expect(object["policyTrace"] == nil)
        #expect(try JSONDecoder().decode(MatchCheckpoint.RecordedMove.self, from: wire).policyTrace == nil)
    }
}
