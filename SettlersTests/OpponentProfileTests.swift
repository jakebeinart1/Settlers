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

    @Test func catalogContainsEveryMeasuredStrategicStyle() {
        #expect(Set(OpponentProfile.catalog.map(\.strategy))
                == Set(OpponentStrategy.allCases))
    }

    @Test func newCatalogRequestsTheExperimentalPolicy() {
        #expect(OpponentProfile.catalog.allSatisfy { $0.policy == .neuralR2 })
    }

    @Test(arguments: OpponentStrategy.allCases)
    func missingPolicyDecodesAsTheOriginalHeuristic(strategy: OpponentStrategy) throws {
        let profile = OpponentProfile(id: "saved-general", name: "Augustus", civilization: .rome, strategy: strategy)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        object.removeValue(forKey: "policy")
        let data = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(OpponentProfile.self, from: data)
        #expect(restored == profile)
        #expect(restored.policy == .heuristic)
    }

    @Test(arguments: OpponentPolicy.allCases)
    func selectedPolicySurvivesEncoding(policy: OpponentPolicy) throws {
        let profile = OpponentProfile.forCivilization(.rome).usingPolicy(policy)
        let restored = try JSONDecoder().decode(OpponentProfile.self, from: JSONEncoder().encode(profile))
        #expect(restored == profile)
    }

    @Test func unknownPolicyIsRejectedInsteadOfSubstitutingHeuristics() throws {
        let profile = OpponentProfile.forCivilization(.rome)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        object["policy"] = "future-network"
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(OpponentProfile.self, from: data) }
    }

    @Test func modeTextDescribesConfiguredPoliciesAndInformationAccess() {
        #expect(OpponentPolicy.modeDescription(for: []) == "Human players only.")
        #expect(OpponentPolicy.modeDescription(for: [.heuristic]) == "Heuristic AI • heuristic trading; all hands visible.")
        #expect(OpponentPolicy.modeDescription(for: [.neuralR2])
            == "Neural AI (experimental) • heuristic trading; all hands visible.")
        #expect(OpponentPolicy.modeDescription(for: [.neuralR2, .heuristic])
            == "Neural + heuristic AI (experimental) • heuristic trading; all hands visible.")
    }
}

@MainActor @Suite struct OpponentPolicyFactoryTests {
    @Test func heuristicAndHumanOnlyRostersNeverLoadANetwork() throws {
        var loads = 0
        let factory = OpponentPolicyFactory(loadNetwork: {
            loads += 1
            throw UpstreamNetwork.LoadingError.missingResource
        })
        let profiles = Dictionary(uniqueKeysWithValues: OpponentStrategy.allCases.enumerated().map { index, strategy in
            (PlayerID(index: index), OpponentProfile(id: "saved-\(index)", name: "Saved general",
                civilization: .rome, strategy: strategy, policy: .heuristic))
        })
        let policies = try GameViewModel.makePolicies(profiles, policyFactory: factory)
        #expect(policies.mapValues(\.id) == [PlayerID(index: 0): "heuristic-balanced",
            PlayerID(index: 1): "heuristic-aggressive", PlayerID(index: 2): "heuristic-cautious"])
        #expect(policies.values.allSatisfy { $0 is HeuristicPolicy })
        #expect(try GameViewModel.makePolicies([:], policyFactory: factory).isEmpty)
        #expect(loads == 0)
    }

    @Test func neuralSeatsAndSubsequentMatchesShareOneValidatedLoad() throws {
        var loads = 0
        let factory = OpponentPolicyFactory(loadNetwork: {
            loads += 1
            return try UpstreamNetwork.bundled()
        })
        let profiles = [PlayerID(index: 1): OpponentProfile.forCivilization(.rome),
                        PlayerID(index: 2): OpponentProfile.forCivilization(.egypt)]
        let first = try GameViewModel.makePolicies(profiles, policyFactory: factory)
        let second = try GameViewModel.makePolicies(profiles, policyFactory: factory)
        #expect(first.values.allSatisfy { $0 is UpstreamPolicy })
        #expect(first.mapValues(\.id) == second.mapValues(\.id))
        #expect(first[PlayerID(index: 1)]?.id
            == "upstream-r2-hybrid-greedy-swift-compounds-trade-scheduler-fallback-heuristic-aggressive")
        #expect(loads == 1)
    }

    @Test func neuralLoadFailureThrowsAndCanRetryWithoutReturningAFallback() throws {
        var loads = 0
        let factory = OpponentPolicyFactory(loadNetwork: {
            loads += 1
            if loads == 1 { throw UpstreamNetwork.LoadingError.missingResource }
            return try UpstreamNetwork.bundled()
        })
        let profiles = [PlayerID(index: 1): OpponentProfile.forCivilization(.rome)]
        #expect(throws: (any Error).self) { try GameViewModel.makePolicies(profiles, policyFactory: factory) }
        let retry = try GameViewModel.makePolicies(profiles, policyFactory: factory)
        #expect(retry[PlayerID(index: 1)] is UpstreamPolicy)
        #expect(loads == 2)
    }
}
