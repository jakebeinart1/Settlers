import Foundation
import Testing
import CatanEngine
@testable import CatanAI

@Suite struct GhostProfileTests {

    private var sample: GhostProfile {
        GhostProfile(id: "jake", name: "Jake's Ghost", person: .anchored(at: .forMode(.classic)),
                     lambda: 0.5, gamesLearned: 24, civilization: "greece")
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(sample)
        #expect(try JSONDecoder().decode(GhostProfile.self, from: data) == sample)
    }

    /// A ghost written before `civilization` existed must still load; a
    /// ghost that fails to decode vanishes from the picker without a word.
    @Test func decodesWithoutACivilization() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as? [String: Any])
        object.removeValue(forKey: "civilization")
        object.removeValue(forKey: "decisionsLearned")
        let decoded = try JSONDecoder().decode(GhostProfile.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.civilization == nil)
        #expect(decoded.decisionsLearned == 0)
        #expect(decoded.gamesLearned == 24)
    }

    /// Every ghost on disk and on the server today has no revision; it must
    /// start at the number the server already compares (`gamesLearned`).
    @Test func anOldGhostDecodesWithRevisionEqualToGamesLearned() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as? [String: Any])
        for key in ["revision", "isNameCustom", "isTrainingPaused", "isRemoved"] { object.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(GhostProfile.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.revision == 24)
        #expect(!decoded.isNameCustom && !decoded.isTrainingPaused && !decoded.isRemoved)
    }

    @Test func managementFieldsRoundTrip() throws {
        var ghost = sample
        ghost.revision = 31
        ghost.isNameCustom = true
        ghost.isTrainingPaused = true
        ghost.isRemoved = true
        #expect(try JSONDecoder().decode(GhostProfile.self, from: JSONEncoder().encode(ghost)) == ghost)
    }

    /// A person model written before the lapse rate existed decodes with the default.
    @Test func aPersonModelWithoutALapseDecodes() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(sample.person)) as? [String: Any])
        object.removeValue(forKey: "lapse")
        let decoded = try JSONDecoder().decode(PersonModel.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.lapse == PersonModel.defaultLapse)
    }
}
