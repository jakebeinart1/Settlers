import Foundation
import Testing
@testable import CatanAI
@testable import CatanEngine
@testable import Settlers

@Suite struct OpponentProfileCatalogTests {
    @Test func everyCivilizationHasExactlyOneStableProfile() {
        #expect(Set(OpponentProfile.catalog.map(\.civilization)) == Set(Civilization.allCases))
        #expect(Set(OpponentProfile.catalog.map(\.id)).count == Civilization.allCases.count)

        for civilization in Civilization.allCases {
            let profile = OpponentProfile.forCivilization(civilization)
            #expect(!profile.id.isEmpty)
            #expect(profile.name == civilization.generalName)
            #expect(profile.dialogueVoice == civilization.tradeMessagesEmpire)
        }
    }

    @Test func newCatalogUsesOnlyBalanced() {
        #expect(OpponentProfile.catalog.allSatisfy { $0.strategy == .balanced })
    }

    @Test(arguments: OpponentStrategy.allCases)
    func savedStrategiesRoundTripWithoutAddingPolicy(strategy: OpponentStrategy) throws {
        let profile = OpponentProfile(id: "saved", name: "Saved general", civilization: .rome, strategy: strategy)
        let encoded = try JSONEncoder().encode(profile)
        #expect(try JSONDecoder().decode(OpponentProfile.self, from: encoded) == profile)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(object.keys) == ["id", "name", "civilization", "strategy"])
        object["policy"] = "heuristic"
        let explicit = try JSONDecoder().decode(OpponentProfile.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(explicit == profile)
        let rewritten = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(explicit)) as? [String: Any])
        #expect(rewritten["policy"] == nil)
    }

    @Test func unsupportedOrMalformedPolicyIsRejectedRatherThanDowngraded() throws {
        let encoded = try JSONEncoder().encode(OpponentProfile.forCivilization(.rome))
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let policies: [Any] = ["neuralR2", "future-policy", "", NSNull(), true, 1]
        for policy in policies {
            var changed = object
            changed["policy"] = policy
            let data = try JSONSerialization.data(withJSONObject: changed)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(OpponentProfile.self, from: data) }
        }
    }
}
