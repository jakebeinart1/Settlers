import CatanEngine

/// One person's ghost as it is stored, bundled and seated: the fitted person
/// model plus the lambda it plays at.
///
/// Shared by the `ghost` CLI (which writes the bundled ghost) and the app
/// (which stores, retrains and seats ghosts), so the two cannot disagree about
/// the file. `civilization` is a `Civilization.rawValue`, because that type
/// belongs to the app and this package must not import it.
public struct GhostProfile: Codable, Sendable, Equatable, Identifiable {
    /// A stable slug: "jake".
    public let id: String
    /// Shown in the picker and on the leaderboard: "Jake's Ghost".
    public var name: String
    public var person: PersonModel
    public var lambda: Double
    /// How many of its person's finished games it has learned from.
    public var gamesLearned: Int
    public var civilization: String?

    public init(id: String, name: String, person: PersonModel, lambda: Double,
                gamesLearned: Int, civilization: String? = nil) {
        self.id = id
        self.name = name
        self.person = person
        self.lambda = lambda
        self.gamesLearned = gamesLearned
        self.civilization = civilization
    }

    private enum CodingKeys: String, CodingKey { case id, name, person, lambda, gamesLearned, civilization }

    /// Hand-written so a field added later cannot make an older ghost vanish:
    /// a ghost that fails to decode drops out of the picker without a word.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        person = try values.decode(PersonModel.self, forKey: .person)
        lambda = try values.decode(Double.self, forKey: .lambda)
        gamesLearned = try values.decodeIfPresent(Int.self, forKey: .gamesLearned) ?? 0
        civilization = try values.decodeIfPresent(String.self, forKey: .civilization)
    }
}
