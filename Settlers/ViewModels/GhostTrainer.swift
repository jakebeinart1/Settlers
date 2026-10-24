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
    /// Replaying a game and scoring every candidate is the slow half (about a
    /// minute per game on a Mac); a test of the completion hook swaps it out.
    var extract: @Sendable (_ game: LoggedGame, _ anchor: EvaluationWeights) throws -> [DecisionRecord] = {
        try DecisionExtractor.decisions(in: $0, anchor: $1, humanTrading: true)
    }
    /// The same game read for the choice model (`ChoiceModel`), which is
    /// what a ghost with enough of its person's choices plays by.
    var extractChoices: @Sendable (_ game: LoggedGame) throws -> [ChoiceRecord] = { try ChoiceRecord.records(in: $0) }

    /// Lowercase letters and digits of a name: "Jake" -> "jake". The key a
    /// name is claimed under on the ladder, and the id ghosts had before they
    /// were filed under player ids (`PlayerDirectory.migrateLegacyNames`).
    static func ghostID(forPerson name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }.map(Character.init))
    }

    /// The new ghost, or `nil` if this match was already learned. The ghost is
    /// filed under its person's player id (`PlayerDirectory`), so a rename
    /// keeps training the same ghost; `personName` only names a new one.
    func learn(match: UUID, game: LoggedGame, human: PlayerID, personID: String, personName: String) throws -> GhostProfile? {
        // An empty id would write a ghost at the store's root.
        guard !personID.isEmpty else { return nil }
        let id = store.resolve(personID)
        let record = store.decisionsDirectory(for: id).appendingPathComponent("\(match.uuidString).jsonl")
        guard !FileManager.default.fileExists(atPath: record.path) else { return nil }
        // Paused (Jake, 2026-10-08: "pause training on a ghost if happy with
        // it"): the game is marked skipped for good, so catch-up never
        // teaches it later, including after training is switched back on.
        let skipped = Self.skippedMarker(for: match, ghost: id, store: store)
        guard !FileManager.default.fileExists(atPath: skipped.path) else { return nil }
        let stored = store.ghost(id: id, includingRemoved: true)
        if stored?.isTrainingPaused == true {
            try FileManager.default.createDirectory(at: skipped.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: skipped)
            return nil
        }
        let previous = store.ghost(id: id) ?? GhostProfile(
            id: id, name: "\(personName.trimmingCharacters(in: .whitespacesAndNewlines))'s Ghost",
            person: .anchored(at: .forMode(.classic)), lambda: Self.defaultLambda, gamesLearned: 0
        )
        let personOnly = LoggedGame(id: game.id, initialState: game.initialState, humanSeats: [human], events: game.events)
        let decisions = try extract(personOnly, EvaluationWeights(vector: previous.person.weights))
        // A game in which the person made no decision teaches nothing and must
        // not count toward the ghost's games (a QA forced win has no moves).
        guard !decisions.isEmpty else { return nil }
        var learned = previous
        learned.person = try fit(decisions, previous)
        try writeLines(try extractChoices(personOnly), to: store.choicesDirectory(for: id)
            .appendingPathComponent("\(match.uuidString).jsonl"))
        learned.choices = refitChoices(id)
        if !previous.isNameCustom {
            learned.name = "\(personName.trimmingCharacters(in: .whitespacesAndNewlines))'s Ghost"
        }
        learned.gamesLearned += 1
        // Every learned game is a new revision, or it would never sync.
        learned.revision = (stored?.revision ?? 0) + 1
        learned.decisionsLearned += decisions.count
        try store.save(learned)
        try writeLines(decisions, to: record)
        return learned
    }

    /// The choice model from every choice record on this phone, or `nil`
    /// below `ChoiceFitter.minimumDecisions`, where the ghost keeps playing
    /// by its person model. A refit from scratch: the records are small and
    /// the fit takes seconds, so no prior from an earlier fit is needed.
    func refitChoices(_ id: String) -> ChoiceModel? {
        let directory = store.choicesDirectory(for: id)
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let records = files.flatMap { file in
            ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n")
                .compactMap { try? JSONDecoder().decode(ChoiceRecord.self, from: Data($0.utf8)) }
        }
        return records.count < ChoiceFitter.minimumDecisions ? nil : ChoiceFitter.fit(records)
    }

    /// Once per ghost: choice records for the games it learned before choice
    /// models existed (2026-10-24), from the logs still on this phone, then
    /// one refit. Without it a ghost would wait for new games to play like
    /// its person. Returns the refitted ghost, or `nil` if nothing changed.
    func backfillChoices(_ games: [CatchUpGame], personID: String) throws -> GhostProfile? {
        let id = store.resolve(personID)
        let marker = store.choicesDirectory(for: id).appendingPathComponent(GhostStore.backfilledMarker)
        guard var ghost = store.ghost(id: id), !ghost.isTrainingPaused,
              !FileManager.default.fileExists(atPath: marker.path) else { return nil }
        for game in games where store.resolve(game.personID) == id {
            let learned = store.decisionsDirectory(for: id).appendingPathComponent("\(game.match.uuidString).jsonl")
            let choices = store.choicesDirectory(for: id).appendingPathComponent("\(game.match.uuidString).jsonl")
            guard FileManager.default.fileExists(atPath: learned.path),
                  !FileManager.default.fileExists(atPath: choices.path) else { continue }
            let personOnly = LoggedGame(id: game.game.id, initialState: game.game.initialState, humanSeats: [game.human],
                                        events: game.game.events)
            try writeLines(try extractChoices(personOnly), to: choices)
        }
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: marker)
        let choices = refitChoices(id)
        guard choices != ghost.choices else { return nil }
        ghost.choices = choices
        ghost.revision += 1
        try store.save(ghost)
        return ghost
    }

    static func skippedMarker(for match: UUID, ghost id: String, store: GhostStore) -> URL {
        store.localDirectory.appendingPathComponent(id).appendingPathComponent("skipped").appendingPathComponent(match.uuidString)
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

    private func writeLines<Record: Encodable>(_ records: [Record], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        var data = Data()
        for record in records {
            data.append(try encoder.encode(record))
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
    let personID: String
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

    /// The two awaits only publish status. `trainer.learn` itself has no
    /// suspension point, so each training still runs whole before the next
    /// reads the ghost - the guarantee this actor exists for.
    @discardableResult
    func learn(_ trainer: GhostTrainer, match: UUID, game: LoggedGame, human: PlayerID,
               personID: String, personName: String) async -> GhostProfile? {
        await MainActor.run { GhostTrainingStatus.shared.begin(personID) }
        let learned = try? trainer.learn(match: match, game: game, human: human, personID: personID, personName: personName)
        await MainActor.run { GhostTrainingStatus.shared.end(personID) }
        return learned
    }

    /// Teaches rated games whose training never finished (the app was killed
    /// during the minute it takes). Only games in the rating store qualify:
    /// they were played after ghosts existed, so the bundled ghost's own 24
    /// games, which were never rated here, cannot be taught twice. A game
    /// already taught is skipped by its decision record. Returns how many were taught.
    func catchUp(_ trainer: GhostTrainer, games: [CatchUpGame], ratedMatches: Set<UUID>) async -> Int {
        var taught = 0
        let rated = games.filter { ratedMatches.contains($0.match) }
        for game in rated {
            let learned = await learn(trainer, match: game.match, game: game.game, human: game.human,
                                      personID: game.personID, personName: game.personName)
            if learned != nil { taught += 1 }
        }
        for personID in Set(rated.map(\.personID)).sorted() {
            await MainActor.run { GhostTrainingStatus.shared.begin(personID) }
            _ = try? trainer.backfillChoices(rated, personID: personID)
            await MainActor.run { GhostTrainingStatus.shared.end(personID) }
        }
        return taught
    }
}
