import CatanAI
import CatanEngine
import Foundation
import Testing
@testable import Settlers

@Suite(.serialized) struct GhostTrainerTests {

    /// A short real game: every seat Expert, seat 0 labelled the human.
    private func game(seed: UInt64 = 61, moves: Int = 60) throws -> (LoggedGame, PlayerID) {
        let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        var policies: [PlayerID: any Policy] = [:]
        for player in initial.players { policies[player.id] = EvaluationPolicy() }
        var session = GameSession(state: initial, policies: policies, policySeed: seed)
        var events: [LoggedMove] = []
        while events.count < moves, let step = try session.step() {
            events.append(LoggedMove(player: step.actor, move: step.move))
        }
        let human = initial.players[0].id
        return (LoggedGame(id: "t\(seed)", initialState: initial, humanSeats: [human], events: events), human)
    }

    private func store() -> (GhostStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GhostTrainerTests.\(UUID().uuidString)")
        return (GhostStore(localDirectory: root, bundledGhosts: []), root)
    }

    @Test func aFinishedGameTeachesItsPersonsGhost() throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        let match = UUID()
        let learned = try #require(try GhostTrainer(store: ghosts).learn(match: match, game: logged, human: human, personName: "Sam"))
        #expect(learned.id == "sam")
        #expect(learned.name == "Sam's Ghost")
        #expect(learned.gamesLearned == 1)
        #expect(learned.decisionsLearned > 0)
        #expect(ghosts.ghost(id: "sam") == learned)
        #expect(FileManager.default.fileExists(atPath: ghosts.decisionsDirectory(for: "sam")
            .appendingPathComponent("\(match.uuidString).jsonl").path))
    }

    /// Review Focus 3b's twin: the same match cannot teach twice.
    @Test func theSameMatchTeachesOnce() throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        let match = UUID()
        let trainer = GhostTrainer(store: ghosts)
        _ = try trainer.learn(match: match, game: logged, human: human, personName: "Sam")
        #expect(try trainer.learn(match: match, game: logged, human: human, personName: "Sam") == nil)
        #expect(ghosts.ghost(id: "sam")?.gamesLearned == 1)
    }

    /// Review Focus 4: a fit that fails leaves the previous ghost exactly as it was.
    @Test func aFailedFitLeavesThePreviousGhostIntact() throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        _ = try GhostTrainer(store: ghosts).learn(match: UUID(), game: logged, human: human, personName: "Sam")
        let before = try Data(contentsOf: try #require(ghosts.versions(of: "sam").last?.url))
        struct Boom: Error {}
        var failing = GhostTrainer(store: ghosts)
        failing.fit = { _, _ in throw Boom() }
        #expect(throws: Boom.self) { try failing.learn(match: UUID(), game: logged, human: human, personName: "Sam") }
        #expect(ghosts.versions(of: "sam").count == 1)
        #expect(try Data(contentsOf: try #require(ghosts.versions(of: "sam").last?.url)) == before)
    }

    /// Jake's rule: only the person's own play trains their ghost - never a
    /// ghost's moves, even in a game against its own person.
    @Test func onlyTheHumanSeatsDecisionsAreLearned() throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        let match = UUID()
        _ = try GhostTrainer(store: ghosts).learn(match: match, game: logged, human: human, personName: "Sam")
        let text = try String(contentsOf: ghosts.decisionsDirectory(for: "sam").appendingPathComponent("\(match.uuidString).jsonl"),
                              encoding: .utf8)
        let records = try text.split(separator: "\n").map { try JSONDecoder().decode(DecisionRecord.self, from: Data($0.utf8)) }
        let humanDecisions = try DecisionExtractor.decisions(in: logged, anchor: .forMode(.classic)).count
        #expect(records.count == humanDecisions)
        #expect(!records.isEmpty)
    }

    @Test func personNamesBecomeStableIDs() {
        #expect(GhostTrainer.ghostID(forPerson: "Jake") == "jake")
        #expect(GhostTrainer.ghostID(forPerson: " Mary Jo! ") == "maryjo")
    }
}
