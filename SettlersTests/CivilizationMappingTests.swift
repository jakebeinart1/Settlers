import Testing
import CatanAI
import CatanEngine
@testable import Settlers

/// Pins the bridge between a civilization and the voice its bot speaks in.
///
/// `Civilization` (app) and `TradeMessages.Empire` (CatanAI) are separate enums
/// in separate modules, edited independently. The mapping used to be
/// `Empire(rawValue: rawValue)!` - a force-unwrap that turned "somebody renamed
/// a case in the AI package" into a crash at the moment a bot tries to speak:
/// mid-game, on a device, with nothing failing at build time.
///
/// It is an exhaustive `switch` now, so that particular break is a compile
/// error. This test covers what the compiler still cannot see - that every
/// civilization resolves to a pool with lines actually in it.

@Test func everyCivilizationSpeaksFromANonEmptyPool() {
    for civilization in Civilization.allCases {
        let empire = civilization.tradeMessagesEmpire
        let offer = TradeOfferFixture.any
        let pitch = TradeMessages.pitch(offer: offer, empire: empire)
        let accepted = TradeMessages.response(offer: offer, empire: empire, accepted: true)
        let declined = TradeMessages.response(offer: offer, empire: empire, accepted: false)

        #expect(!pitch.isEmpty, "\(civilization.displayName) has no pitch line")
        #expect(!accepted.isEmpty, "\(civilization.displayName) has no acceptance line")
        #expect(!declined.isEmpty, "\(civilization.displayName) has no rejection line")
    }
}

@Test func everyCivilizationMapsToADistinctEmpire() {
    // Two civilizations sharing a voice would make the table sound like the
    // same person twice, and would hide a mis-mapped case from the test above.
    let empires = Civilization.allCases.map(\.tradeMessagesEmpire)
    #expect(Set(empires.map(\.rawValue)).count == Civilization.allCases.count,
            "two civilizations share a TradeMessages voice")
}

private enum TradeOfferFixture {
    /// Content-derived id, so the line each pool returns is stable.
    static let any = TradeOffer.enumerated(from: PlayerID(index: 1),
                                           give: [.brick: 1], want: [.ore: 1])
}
