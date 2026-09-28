import Testing
import CatanEngine
@testable import Settlers

struct TradeReceiptTests {
    private let human = PlayerID(index: 2)
    private let bot = PlayerID(index: 0)

    @Test func bankReceiptUsesExactCommittedCounts() throws {
        let receipt = try #require(TradeReceipt(event: .tradedWithBank(human, gave: [.grain: 6], got: [.ore: 3]), player: human))
        #expect(receipt.partner == nil)
        #expect(receipt.gave == [.grain: 6])
        #expect(receipt.received == [.ore: 3])
    }

    @Test func confirmedProposalReversesAcceptingBotsPerspective() throws {
        let event = GameEvent.acceptedTrade(bot, from: human, gave: [.ore: 3], got: [.grain: 6])
        let receipt = try #require(TradeReceipt(event: event, player: human))
        #expect(receipt.partner == bot)
        #expect(receipt.gave == [.grain: 6])
        #expect(receipt.received == [.ore: 3])
    }

    @Test func receivingPlayersPerspectiveIsNotReversed() throws {
        let event = GameEvent.acceptedTrade(human, from: bot, gave: [.ore: 3], got: [.grain: 6])
        let receipt = try #require(TradeReceipt(event: event, player: human))
        #expect(receipt.partner == bot)
        #expect(receipt.gave == [.ore: 3])
        #expect(receipt.received == [.grain: 6])
    }

    @Test func willingnessRejectionAndOtherPlayersTradesAreNotReceipts() {
        let events: [GameEvent] = [
            .proposedTrade(human, give: [.grain: 6], want: [.ore: 3]),
            .rejectedTrade(bot, from: human),
            .tradedWithBank(bot, gave: [.grain: 6], got: [.ore: 3]),
            .acceptedTrade(bot, from: PlayerID(index: 1), gave: [.ore: 3], got: [.grain: 6])
        ]
        #expect(events.allSatisfy { TradeReceipt(event: $0, player: human) == nil })
    }
}
