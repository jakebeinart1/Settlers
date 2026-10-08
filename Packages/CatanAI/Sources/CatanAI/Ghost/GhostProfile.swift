import CatanEngine

/// One person's ghost as it is stored, bundled and seated: the fitted person
/// model plus the lambda it plays at.
///
/// Shared by the `ghost` CLI (which writes the bundled ghost) and the app
/// (which stores, retrains and seats ghosts), so the two cannot disagree about
/// the file. `civilization` is a `Civilization.rawValue`, because that type
/// belongs to the app and this package must not import it.
public struct GhostProfile: Codable, Sendable, Equatable, Identifiable {
    /// Its person's player id (the app's `PlayerDirectory`), or for a ghost
    /// made before 2026-09-29 a slug of their name ("jake").
    public let id: String
    /// Shown in the picker and on the leaderboard: "Jake's Ghost".
    public var name: String
    public var person: PersonModel
    public var lambda: Double
    /// How many of its person's finished games it has learned from.
    public var gamesLearned: Int
    /// How many of its person's decisions it has learned from: how stiff it is
    /// as the prior for its next retraining (`FitOptions.priorEvidence`).
    public var decisionsLearned: Int
    public var civilization: String?
    /// Bumped by every learned game, rename, reset, remove and pause toggle.
    /// The ladder accepts a ghost only when this goes up; it rides in the
    /// CloudKit record field still named `gamesLearned`, so no schema change.
    public var revision: Int
    /// Set by the owner's rename; `LiveSync.refreshNames` then leaves `name` alone.
    public var isNameCustom: Bool
    /// The owner stopped training: finished games are skipped, never taught later.
    public var isTrainingPaused: Bool
    /// A tombstone: the owner removed this ghost. Kept so the removal syncs.
    public var isRemoved: Bool

    public init(id: String, name: String, person: PersonModel, lambda: Double,
                gamesLearned: Int, decisionsLearned: Int = 0, civilization: String? = nil,
                revision: Int? = nil, isNameCustom: Bool = false,
                isTrainingPaused: Bool = false, isRemoved: Bool = false) {
        self.id = id
        self.name = name
        self.person = person
        self.lambda = lambda
        self.gamesLearned = gamesLearned
        self.decisionsLearned = decisionsLearned
        self.civilization = civilization
        self.revision = revision ?? gamesLearned
        self.isNameCustom = isNameCustom
        self.isTrainingPaused = isTrainingPaused
        self.isRemoved = isRemoved
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, person, lambda, gamesLearned, decisionsLearned, civilization
        case revision, isNameCustom, isTrainingPaused, isRemoved
    }

    /// Hand-written so a field added later cannot make an older ghost vanish:
    /// a ghost that fails to decode drops out of the picker without a word.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        person = try values.decode(PersonModel.self, forKey: .person)
        lambda = try values.decode(Double.self, forKey: .lambda)
        gamesLearned = try values.decodeIfPresent(Int.self, forKey: .gamesLearned) ?? 0
        decisionsLearned = try values.decodeIfPresent(Int.self, forKey: .decisionsLearned) ?? 0
        civilization = try values.decodeIfPresent(String.self, forKey: .civilization)
        revision = try values.decodeIfPresent(Int.self, forKey: .revision) ?? gamesLearned
        isNameCustom = try values.decodeIfPresent(Bool.self, forKey: .isNameCustom) ?? false
        isTrainingPaused = try values.decodeIfPresent(Bool.self, forKey: .isTrainingPaused) ?? false
        isRemoved = try values.decodeIfPresent(Bool.self, forKey: .isRemoved) ?? false
    }
}
