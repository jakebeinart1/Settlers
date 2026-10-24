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
        let learned = try #require(try GhostTrainer(store: ghosts).learn(match: match, game: logged, human: human, personID: "sam", personName: "Sam"))
        #expect(learned.id == "sam")
        #expect(learned.name == "Sam's Ghost")
        #expect(learned.gamesLearned == 1)
        #expect(learned.decisionsLearned > 0)
        #expect(ghosts.ghost(id: "sam") == learned)
        #expect(FileManager.default.fileExists(atPath: ghosts.decisionsDirectory(for: "sam")
            .appendingPathComponent("\(match.uuidString).jsonl").path))
    }

    /// After Jake renamed himself "Bein" (2026-09-28), his next game must
    /// teach the ghost that already learned from him, not start a blank one:
    /// the ghost is filed under his player id, which a rename does not touch.
    @Test func aRenamedPersonTeachesTheGhostTheyAlreadyHave() throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        try ghosts.save(GhostProfile(id: "player-1", name: "Jake's Ghost", person: .anchored(at: .forMode(.classic)),
                                     lambda: 0.01, gamesLearned: 25, decisionsLearned: 2731))
        let (logged, human) = try game()
        var trainer = GhostTrainer(store: ghosts)
        trainer.fit = { _, previous in previous.person }
        let learned = try #require(try trainer.learn(match: UUID(), game: logged, human: human,
                                                     personID: "player-1", personName: "Bein"))
        #expect(learned.id == "player-1")
        #expect(learned.gamesLearned == 26)
        #expect(learned.name == "Bein's Ghost")
        #expect(ghosts.all().map(\.id) == ["player-1"], "no second ghost")
    }

    /// Review Focus 3b's twin: the same match cannot teach twice.
    @Test func theSameMatchTeachesOnce() throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        let match = UUID()
        let trainer = GhostTrainer(store: ghosts)
        _ = try trainer.learn(match: match, game: logged, human: human, personID: "sam", personName: "Sam")
        #expect(try trainer.learn(match: match, game: logged, human: human, personID: "sam", personName: "Sam") == nil)
        #expect(ghosts.ghost(id: "sam")?.gamesLearned == 1)
    }

    /// Review Focus 4: a fit that fails leaves the previous ghost exactly as it was.
    @Test func aFailedFitLeavesThePreviousGhostIntact() throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        _ = try GhostTrainer(store: ghosts).learn(match: UUID(), game: logged, human: human, personID: "sam", personName: "Sam")
        let before = try Data(contentsOf: try #require(ghosts.versions(of: "sam").last?.url))
        struct Boom: Error {}
        var failing = GhostTrainer(store: ghosts)
        failing.fit = { _, _ in throw Boom() }
        #expect(throws: Boom.self) { try failing.learn(match: UUID(), game: logged, human: human, personID: "sam", personName: "Sam") }
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
        _ = try GhostTrainer(store: ghosts).learn(match: match, game: logged, human: human, personID: "sam", personName: "Sam")
        let text = try String(contentsOf: ghosts.decisionsDirectory(for: "sam").appendingPathComponent("\(match.uuidString).jsonl"),
                              encoding: .utf8)
        let records = try text.split(separator: "\n").map { try JSONDecoder().decode(DecisionRecord.self, from: Data($0.utf8)) }
        let humanDecisions = try DecisionExtractor.decisions(in: logged, anchor: .forMode(.classic)).count
        #expect(records.count == humanDecisions)
        #expect(!records.isEmpty)
    }

    /// Jake: pause when happy. A game played while paused is never taught,
    /// not even by launch catch-up after training is switched back on.
    @Test func aGamePlayedWhilePausedIsNeverTaught() throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        let trainer = GhostTrainer(store: ghosts)
        _ = try trainer.learn(match: UUID(), game: logged, human: human, personID: "sam", personName: "Sam")
        try ghosts.setTrainingPaused("sam", true)
        let paused = UUID()
        #expect(try trainer.learn(match: paused, game: logged, human: human, personID: "sam", personName: "Sam") == nil)
        try ghosts.setTrainingPaused("sam", false)
        #expect(try trainer.learn(match: paused, game: logged, human: human, personID: "sam", personName: "Sam") == nil)
        #expect(ghosts.ghost(id: "sam")?.gamesLearned == 1)
    }

    /// A learned game must raise the revision, or it never syncs.
    @Test func learningBumpsRevisionAndKeepsACustomName() throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        let trainer = GhostTrainer(store: ghosts)
        _ = try trainer.learn(match: UUID(), game: logged, human: human, personID: "sam", personName: "Sam")
        try ghosts.rename("sam", to: "The Wall")
        let learned = try #require(try trainer.learn(match: UUID(), game: logged, human: human, personID: "sam", personName: "Sam"))
        #expect(learned.revision == 3)
        #expect(learned.name == "The Wall")
    }

    // MARK: - Choice model (2026-10-24)

    /// Enough choices to fit: the short test game's own, repeated past the minimum.
    private func plentiful(_ trainer: inout GhostTrainer) {
        trainer.extractChoices = { game in
            let records = try ChoiceRecord.records(in: game)
            return Array(repeating: records, count: ChoiceFitter.minimumDecisions / max(records.count, 1) + 1).flatMap { $0 }
        }
    }

    /// Each game leaves its choice records, and enough of them make the
    /// ghost play by its person's own choices.
    @Test func aLearnedGameRecordsChoicesAndFitsTheChoiceModel() throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        let match = UUID()
        var trainer = GhostTrainer(store: ghosts)
        plentiful(&trainer)
        let learned = try #require(try trainer.learn(match: match, game: logged, human: human, personID: "sam", personName: "Sam"))
        #expect(FileManager.default.fileExists(atPath: ghosts.choicesDirectory(for: "sam")
            .appendingPathComponent("\(match.uuidString).jsonl").path))
        #expect(try #require(learned.choices).decisions >= ChoiceFitter.minimumDecisions)
        #expect(ghosts.ghost(id: "sam")?.choices == learned.choices)
    }

    /// One short game is too few choices: the ghost keeps its person model.
    @Test func tooFewChoicesLeaveTheGhostOnItsPersonModel() throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        let learned = try #require(try GhostTrainer(store: ghosts).learn(match: UUID(), game: logged, human: human,
                                                                         personID: "sam", personName: "Sam"))
        #expect(learned.choices == nil)
    }

    /// A ghost that learned its games before choice models reads them once
    /// from the logs on the phone, and syncs the result as a new revision.
    @Test func gamesLearnedBeforeChoiceModelsAreReadOnce() throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        var trainer = GhostTrainer(store: ghosts)
        trainer.extractChoices = { _ in [] }
        let match = UUID()
        _ = try trainer.learn(match: match, game: logged, human: human, personID: "sam", personName: "Sam")
        try FileManager.default.removeItem(at: ghosts.choicesDirectory(for: "sam"))
        let before = try #require(ghosts.ghost(id: "sam"))
        plentiful(&trainer)
        let games = [CatchUpGame(match: match, game: logged, human: human, personID: "sam", personName: "Sam"),
                     CatchUpGame(match: UUID(), game: logged, human: human, personID: "sam", personName: "Sam")]
        let backfilled = try #require(try trainer.backfillChoices(games, personID: "sam"))
        #expect(backfilled.choices != nil)
        #expect(backfilled.revision == before.revision + 1)
        #expect(backfilled.gamesLearned == before.gamesLearned, "reading old games again is not learning new ones")
        let files = try FileManager.default.contentsOfDirectory(atPath: ghosts.choicesDirectory(for: "sam").path)
        #expect(files.filter { $0.hasSuffix(".jsonl") } == ["\(match.uuidString).jsonl"], "only games already learned")
        #expect(try trainer.backfillChoices(games, personID: "sam") == nil)
    }

    /// A reset ghost starts over: old games are not read back into it.
    @Test func aResetGhostIsNotBackfilledFromBeforeTheReset() throws {
        let (ghosts, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let (logged, human) = try game()
        var trainer = GhostTrainer(store: ghosts)
        plentiful(&trainer)
        let match = UUID()
        _ = try trainer.learn(match: match, game: logged, human: human, personID: "sam", personName: "Sam")
        let fresh = try ghosts.reset("sam", keepingOld: true)
        #expect(fresh.choices == nil)
        #expect(ghosts.oldGhosts(of: "sam").first?.choices != nil, "the kept generation keeps its choices")
        let games = [CatchUpGame(match: match, game: logged, human: human, personID: "sam", personName: "Sam")]
        #expect(try trainer.backfillChoices(games, personID: "sam") == nil)
        #expect(trainer.refitChoices("sam") == nil)
    }

    @Test func personNamesBecomeStableIDs() {
        #expect(GhostTrainer.ghostID(forPerson: "Jake") == "jake")
        #expect(GhostTrainer.ghostID(forPerson: " Mary Jo! ") == "maryjo")
    }
}
