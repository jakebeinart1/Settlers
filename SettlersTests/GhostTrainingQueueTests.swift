import CatanAI
import CatanEngine
import Foundation
import Testing
@testable import Settlers

/// Final review findings on retraining (2026-09-25).
@Suite(.serialized) struct GhostTrainingQueueTests {

    private func game(seed: UInt64 = 63, moves: Int = 40) throws -> (LoggedGame, PlayerID) {
        let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        var policies: [PlayerID: any Policy] = [:]
        for player in initial.players { policies[player.id] = EvaluationPolicy() }
        var session = GameSession(state: initial, policies: policies, policySeed: seed)
        var events: [LoggedMove] = []
        while events.count < moves, let step = try session.step() {
            events.append(LoggedMove(player: step.actor, move: step.move))
        }
        return (LoggedGame(id: "q\(seed)", initialState: initial, humanSeats: [initial.players[0].id], events: events),
                initial.players[0].id)
    }

    private func store() -> (GhostStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GhostTrainingQueueTests.\(UUID().uuidString)")
        return (GhostStore(localDirectory: root, bundledGhosts: []), root)
    }

    /// I2: two trainings of the same match at once must teach it once.
    @Test func concurrentTrainingOfOneMatchTeachesOnce() async throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        let match = UUID()
        let queue = GhostTrainingQueue()
        let trainer = GhostTrainer(store: ghosts)
        async let first = queue.learn(trainer, match: match, game: logged, human: human, personName: "Sam")
        async let second = queue.learn(trainer, match: match, game: logged, human: human, personName: "Sam")
        _ = await (first, second)
        #expect(ghosts.ghost(id: "sam")?.gamesLearned == 1)
        #expect(ghosts.versions(of: "sam").count == 1)
    }

    /// I3: a game with no decisions by the human teaches nothing and does not
    /// count toward the ghost's games.
    @Test func aGameWithoutHumanDecisionsTeachesNothing() throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game(moves: 0)
        #expect(try GhostTrainer(store: ghosts).learn(match: UUID(), game: logged, human: human, personName: "Sam") == nil)
        #expect(ghosts.ghost(id: "sam") == nil)
    }

    /// M3: a name with no Latin letters or digits has no usable id; nothing is
    /// written, rather than a ghost at the store's root.
    @Test func aNameWithoutAnIDTeachesNothing() throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        #expect(try GhostTrainer(store: ghosts).learn(match: UUID(), game: logged, human: human, personName: "李明") == nil)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    /// I1: a rated game whose training never finished (the app was killed) is
    /// taught at the next launch from its kept log. A game rated before ghosts
    /// existed - not in the rating store - is never touched, so the bundled
    /// ghost's 24 games cannot be taught twice.
    @Test func aRatedButUntaughtGameIsCaughtUp() async throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        let rated = UUID()
        let unrated = UUID()
        let games = [CatchUpGame(match: rated, game: logged, human: human, personName: "Sam"),
                     CatchUpGame(match: unrated, game: logged, human: human, personName: "Sam")]
        let taught = await GhostTrainingQueue().catchUp(GhostTrainer(store: ghosts), games: games, ratedMatches: [rated])
        #expect(taught == 1)
        #expect(ghosts.ghost(id: "sam")?.gamesLearned == 1)
        #expect(FileManager.default.fileExists(atPath: ghosts.decisionsDirectory(for: "sam")
            .appendingPathComponent("\(rated.uuidString).jsonl").path))
    }

    /// M1: Classic's game count moves even though its rating is fixed.
    @Test func classicsGamesAreCounted() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ClassicCount.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = RatingStore(directory: dir)
        try store.record(match: UUID(), seats: [.person("Jake"), .classic, .classic, .classic], winner: 0)
        #expect(store.load().games["classic"] == 1)
        #expect(store.load().ratings["classic"] == nil)
    }
}
