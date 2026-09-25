import CatanAI
import CatanEngine
import Foundation

/// Teaches a person's ghost from one finished game.
///
/// Jake's rule (2026-09-25): "The only way the ghost gets updated is with user
/// gameplay." Only the human seat's decisions are extracted, so a ghost never
/// learns from its own moves, even in a game against its own person.
///
/// ## Incremental, with the previous ghost as the prior
/// The games a ghost learned from before are not on this phone (Jake's
/// bundled ghost was fitted on the Mac), so each game refits from that game
/// alone, pulled toward the previous ghost as stiffly as the decisions behind
/// it (`FitOptions.priorCenter`). Without that, every game would drag the
/// ghost back toward Expert.
///
/// ## Order of writes
/// The ghost's new version is written first, then the game's decision
/// records, and those records are the "already learned" marker. A crash
/// between the two re-teaches that one game next time, which is a small
/// double count. The opposite order would lose the game for good.
struct GhostTrainer: Sendable {
    /// Until a person's own lambda is calibrated on the Mac, a new ghost
    /// plays at the value calibrated for the first ghost (Jake's, 2026-09-25:
    /// 0.010 matched his 54% against Classic bots; at 0.25 his model won 15%).
    static let defaultLambda = 0.010

    let store: GhostStore
    var fit: @Sendable (_ decisions: [DecisionRecord], _ previous: GhostProfile) throws -> PersonModel = GhostTrainer.incrementalFit

    /// Lowercase letters and digits of the person's name: "Jake" -> "jake",
    /// which is also the bundled ghost's id, so Jake's phone continues it.
    static func ghostID(forPerson name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }.map(Character.init))
    }

    /// The new ghost, or `nil` if this match was already learned.
    func learn(match: UUID, game: LoggedGame, human: PlayerID, personName: String) throws -> GhostProfile? {
        let id = Self.ghostID(forPerson: personName)
        // A name with no Latin letters or digits has no usable id (final
        // review): an empty id would write a ghost at the store's root.
        guard !id.isEmpty else { return nil }
        let record = store.decisionsDirectory(for: id).appendingPathComponent("\(match.uuidString).jsonl")
        guard !FileManager.default.fileExists(atPath: record.path) else { return nil }
        let previous = store.ghost(id: id) ?? GhostProfile(
            id: id, name: "\(personName.trimmingCharacters(in: .whitespacesAndNewlines))'s Ghost",
            person: .anchored(at: .forMode(.classic)), lambda: Self.defaultLambda, gamesLearned: 0
        )
        let personOnly = LoggedGame(id: game.id, initialState: game.initialState, humanSeats: [human], events: game.events)
        let decisions = try DecisionExtractor.decisions(
            in: personOnly, anchor: EvaluationWeights(vector: previous.person.weights), humanTrading: true
        )
        // A game in which the person made no decision teaches nothing and must
        // not count toward the ghost's games (a QA forced win has no moves).
        guard !decisions.isEmpty else { return nil }
        var learned = previous
        learned.person = try fit(decisions, previous)
        learned.gamesLearned += 1
        learned.decisionsLearned += decisions.count
        try store.save(learned)
        try write(decisions, to: record)
        return learned
    }

    static func incrementalFit(_ decisions: [DecisionRecord], previous: GhostProfile) throws -> PersonModel {
        var options = FitOptions()
        options.iterations = 1000
        if previous.gamesLearned > 0 {
            options.priorCenter = previous.person
            options.priorEvidence = Double(previous.decisionsLearned)
        }
        return PersonFitter.fit(decisions, anchor: .forMode(.classic), start: previous.person, options: options)
    }

    private func write(_ decisions: [DecisionRecord], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        var data = Data()
        for decision in decisions {
            data.append(try encoder.encode(decision))
            data.append(0x0A)
        }
        try data.write(to: url, options: .atomic)
    }
}

/// A finished, rated game to (re)teach at launch.
struct CatchUpGame: Sendable {
    let match: UUID
    let game: LoggedGame
    let human: PlayerID
    let personName: String
}

/// One training at a time, for every ghost.
///
/// Final review: two trainings could overlap - the resume-time re-run of a
/// finished match while its first run was still going, or two games whose
/// trainings overlapped - and both would read version N and write N+1,
/// losing one game or counting one twice. An actor with no suspension point
/// inside `learn` runs each training to completion before the next starts.
actor GhostTrainingQueue {
    static let shared = GhostTrainingQueue()

    @discardableResult
    func learn(_ trainer: GhostTrainer, match: UUID, game: LoggedGame, human: PlayerID,
               personName: String) -> GhostProfile? {
        try? trainer.learn(match: match, game: game, human: human, personName: personName)
    }

    /// Teaches rated games whose training never finished (the app was killed
    /// during the minute it takes). Only games in the rating store qualify:
    /// they were played after ghosts existed, so the bundled ghost's own 24
    /// games, which were never rated here, cannot be taught twice. A game
    /// already taught is skipped by its decision record. Returns how many were taught.
    func catchUp(_ trainer: GhostTrainer, games: [CatchUpGame], ratedMatches: Set<UUID>) -> Int {
        games.filter { ratedMatches.contains($0.match) }.reduce(0) { taught, game in
            taught + (learn(trainer, match: game.match, game: game.game, human: game.human,
                            personName: game.personName) == nil ? 0 : 1)
        }
    }
}
