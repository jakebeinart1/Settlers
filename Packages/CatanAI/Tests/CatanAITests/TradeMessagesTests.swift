import Testing
import Foundation
import CatanEngine
@testable import CatanAI

@Test func pitchIsDeterministicForTheSameOfferID() {
    let id = UUID()
    let offer = TradeOffer(id: id, from: PlayerID(index: 1), give: [.wool: 1], want: [.ore: 1])
    let first = TradeMessages.pitch(offer: offer, empire: .rome)
    let second = TradeMessages.pitch(offer: offer, empire: .rome)
    #expect(first == second)
}

@Test func responseIsDeterministicForTheSameOfferID() {
    let id = UUID()
    let offer = TradeOffer(id: id, from: PlayerID(index: 1), give: [.wool: 1], want: [.ore: 1])
    let first = TradeMessages.response(offer: offer, empire: .norse, accepted: true)
    let second = TradeMessages.response(offer: offer, empire: .norse, accepted: true)
    #expect(first == second)
}

@Test func acceptedAndRejectedResponsesDrawFromDisjointPools() {
    let offer = TradeOffer(from: PlayerID(index: 1), give: [.wool: 1], want: [.ore: 1])
    let acceptPool = Set(TradeMessages.responsePool(for: .aztec, accepted: true))
    let rejectPool = Set(TradeMessages.responsePool(for: .aztec, accepted: false))
    #expect(acceptPool.isDisjoint(with: rejectPool))
    _ = offer
}

/// Every empire needs a real library, not a token line or two - a thin pool
/// would make the "regardless" message feel repetitive within a single
/// game. 8 is the floor we're committing to per bucket.
@Test func everyEmpireHasALargePitchAndResponsePool() {
    for empire in TradeMessages.Empire.allCases {
        #expect(TradeMessages.pitchPool(for: empire).count >= 8, "\(empire) pitch pool too small")
        #expect(TradeMessages.responsePool(for: empire, accepted: true).count >= 8, "\(empire) accept pool too small")
        #expect(TradeMessages.responsePool(for: empire, accepted: false).count >= 8, "\(empire) reject pool too small")
    }
}

/// No blank/duplicate lines slipped into a pool - a straightforward typo
/// hazard once every empire has ~10 lines across three pools.
@Test func noPoolHasBlankOrDuplicateLines() {
    for empire in TradeMessages.Empire.allCases {
        let pools = [
            TradeMessages.pitchPool(for: empire),
            TradeMessages.responsePool(for: empire, accepted: true),
            TradeMessages.responsePool(for: empire, accepted: false),
        ]
        for pool in pools {
            #expect(pool.allSatisfy { !$0.isEmpty })
            #expect(Set(pool).count == pool.count, "\(empire) has a duplicate line")
        }
    }
}

/// Every line has to fit on the incoming-trade card at full, readable size -
/// no `minimumScaleFactor` shrink, no truncation - so the pool itself has to
/// stay short rather than relying on the view to make room for it. 38 is the
/// measured budget for that card's tightest layout (see
/// `IncomingTradeCardView`'s doc comment).
@Test func everyLineFitsTheIncomingCardsCharacterBudget() {
    let maxLength = 38
    for empire in TradeMessages.Empire.allCases {
        let pools = [
            TradeMessages.pitchPool(for: empire),
            TradeMessages.responsePool(for: empire, accepted: true),
            TradeMessages.responsePool(for: empire, accepted: false),
        ]
        for pool in pools {
            for line in pool {
                #expect(line.count <= maxLength, "\(empire): \"\(line)\" is \(line.count) chars, over the \(maxLength) budget")
            }
        }
    }
}

/// Sampling many distinct offer IDs against one empire/bucket should surface
/// more than one distinct line - proves `pitch`/`response` actually vary
/// across offers instead of always landing on the pool's first entry.
@Test func differentOffersCanSampleDifferentLinesFromThePool() {
    let messages = Set((0..<40).map { _ in
        TradeMessages.pitch(offer: TradeOffer(from: PlayerID(index: 1), give: [.wool: 1], want: [.ore: 1]), empire: .greece)
    })
    #expect(messages.count > 1)
}
