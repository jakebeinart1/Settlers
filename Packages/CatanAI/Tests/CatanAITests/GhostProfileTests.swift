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

    /// A person model written before the lapse rate existed decodes with the default.
    @Test func aPersonModelWithoutALapseDecodes() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(sample.person)) as? [String: Any])
        object.removeValue(forKey: "lapse")
        let decoded = try JSONDecoder().decode(PersonModel.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.lapse == PersonModel.defaultLapse)
    }
}
