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
    /// plays at the value calibrated for the first ghost (Jake's).
    static let defaultLambda = 0.5

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
