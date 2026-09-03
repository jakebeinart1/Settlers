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
}
