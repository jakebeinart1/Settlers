import Foundation
import Testing
import CatanEngine
@testable import Settlers

struct ResourceProductionFeedbackTests {
    private let human = PlayerID(index: 2)
    private let roller = PlayerID(index: 0)
    private let oreHex = HexCoordinate(q: 0, r: 0)
    private let grainHex = HexCoordinate(q: 3, r: 0)
    private let otherOreHex = HexCoordinate(q: 0, r: 3)
    private let now = Date(timeIntervalSince1970: 10_000)

    @Test func cityAndSettlementReceiptsNameTheirActualHexesAndAmounts() throws {
        let receipt = try #require(self.receipt(for: fixture()))

        #expect(receipt.owner == human, "the recipient need not be the roller or seat zero")
        #expect(receipt.amount(for: .ore) == 2)
        #expect(receipt.amount(for: .grain) == 1)
        #expect(receipt.amount(for: .wool) == 0)
        #expect(receipt.sourceTiles == [oreHex, grainHex])
        #expect(receipt.summary == "6 rolled · City +2 ore, Settlement +1 grain")
        #expect(receipt.sourceSummary == "6 · City +2 · Settlement +1")
        #expect(receipt.compactSummary == "6 rolled · +3 cards")
        #expect(receipt.accessibilitySummary.contains("City, +2, on a 6 hex"))
        #expect(receipt.gains.map(\.resource) == [.ore, .grain])
    }

    @Test func botOnlyProductionHasNoPrivateReceipt() {
        var before = fixture()
        before.players[human.index].cities = []
        before.players[human.index].settlements = []
        before.players[roller.index].cities = [before.board.corners(of: oreHex)[0]]

        #expect(receipt(for: before) == nil)
    }

    @Test func robberAndEmptyBankNeverLightTheirResource() throws {
        var before = fixture()
        before.board.robberTile = oreHex
        let robbed = try #require(receipt(for: before))
        #expect(robbed.amount(for: .ore) == 0)
        #expect(robbed.sourceTiles == [grainHex])

        before.bank[.grain] = 0
        #expect(receipt(for: before) == nil)
    }

    @Test func aSevenAndANonMatchingRollHaveNoReceipt() {
        #expect(receipt(for: fixture(), roll: 7) == nil)
        #expect(receipt(for: fixture(), roll: 5) == nil)
    }

    @Test func bankShortageShowsOnlyWhatArrived() throws {
        var before = fixture()
        before.bank[.ore] = 1
        let receipt = try #require(self.receipt(for: before))

        #expect(receipt.amount(for: .ore) == 1)
        #expect(receipt.gains.first?.sources.first?.amount == 1)
        #expect(receipt.summary.contains("City +1 ore"))
        #expect(!receipt.summary.contains("+2 ore"))
    }

    @Test func contestedShortageDoesNotPretendMatchingHexPaid() throws {
        var before = fixture()
        before.players[1].settlements = [before.board.corners(of: oreHex)[3]]
        before.bank[.ore] = 2
        let receipt = try #require(self.receipt(for: before))

        #expect(receipt.amount(for: .ore) == 0)
        #expect(receipt.sourceTiles == [grainHex])
    }

    @Test func partialPaymentAcrossTwoHexesDoesNotInventAnAllocation() throws {
        var before = fixture()
        before.players[human.index].settlements.insert(before.board.corners(of: otherOreHex)[0])
        before.bank[.ore] = 2
        let receipt = try #require(self.receipt(for: before))

        #expect(receipt.amount(for: .ore) == 2)
        #expect(receipt.gains.first?.sources.isEmpty == true)
        #expect(receipt.sourceTiles == [grainHex])
        #expect(receipt.summary == "6 rolled · +2 ore, Settlement +1 grain")
        #expect(receipt.sourceSummary == nil)
    }

    @Test func fullyPaidSameResourceRetainsBothBuildingSources() throws {
        var before = fixture()
        before.players[human.index].settlements.insert(before.board.corners(of: otherOreHex)[0])
        let receipt = try #require(self.receipt(for: before))
        let ore = try #require(receipt.gains.first { $0.resource == .ore })

        #expect(ore.amount == 3)
        #expect(ore.sources.map(\.hex) == [oreHex, otherOreHex])
        #expect(ore.sources.map(\.amount) == [2, 1])
        #expect(ore.sources.map(\.origin) == ["City", "Settlement"])
    }

    @Test func conquestUsesEngineOccupationAndDoesNotCallBonusASettlement() throws {
        var before = fixture()
        before.variant = .conquest
        before.garrisons[oreHex] = Garrison(owner: human, strength: 3)
        let occupied = try #require(receipt(for: before))
        #expect(occupied.amount(for: .ore) == 3)
        #expect(occupied.gains.first?.sources.first?.origin == "City + occupation")

        before.players[human.index].cities = []
        let bonusOnly = try #require(receipt(for: before))
        #expect(bonusOnly.amount(for: .ore) == 1)
        #expect(bonusOnly.gains.first?.sources.first?.origin == "Occupation")

        before.garrisons[oreHex] = Garrison(owner: roller, strength: 3)
        #expect(receipt(for: before)?.amount(for: .ore) == 0)
    }

    @Test func onlyTheClaimedOwnerCanSeeAnUnexpiredReceipt() throws {
        let before = fixture()
        let after = rolled(before)
        let receipt = try #require(self.receipt(for: before))

        #expect(receipt.visible(to: human, at: now) == receipt)
        #expect(receipt.visible(to: roller, at: now) == nil)
        #expect(receipt.visible(to: nil, at: now) == nil)
        #expect(receipt.visible(to: human, at: now.addingTimeInterval(-1)) == nil)
        #expect(receipt.visible(to: human, at: receipt.expiresAt) == nil)
        #expect(ResourceProductionFeedback(events: [.rolled(roller, total: 6)],
                                           before: before, after: after, viewer: nil) == nil)
    }

    @Test func repeatedEqualRollsHaveIndependentIdentitiesAndDeadlines() throws {
        let first = try #require(receipt(for: fixture()))
        let later = now.addingTimeInterval(1)
        let second = try #require(ResourceProductionFeedback(events: [.rolled(roller, total: 6)],
            before: fixture(), after: rolled(fixture()), viewer: human, occurredAt: later))

        #expect(first.id != second.id)
        #expect(first.gains == second.gains)
        #expect(first.visible(to: human, at: first.expiresAt) == nil)
        #expect(second.visible(to: human, at: first.expiresAt) == second)
    }

    @Test func nonRollAndBatchedEventsNeverMasqueradeAsProduction() {
        let before = fixture()
        let after = rolled(before)
        let roll = GameEvent.rolled(roller, total: 6)
        let otherEvents: [[GameEvent]] = [
            [], [.placedInitialRoad(human)], [.playedYearOfPlenty(human, taken: [.ore: 2, .grain: 1])],
            [.tradedWithBank(human, gave: [.brick: 4], got: [.ore: 1])],
            [roll, .endedTurn(roller)], [roll, roll], [.rolled(human, total: 6)]
        ]
        for events in otherEvents {
            #expect(ResourceProductionFeedback(events: events, before: before, after: after, viewer: human) == nil)
        }
    }

    @Test func realRulesEngineRollProducesTheReceiptWithoutChangingEitherState() throws {
        for seed in UInt64(0)..<32 {
            var before = fixture()
            before.rng = RandomSource(seed: seed)
            var after = before
            let events = try RulesEngine.apply(.rollDice, by: roller, to: &after)
            guard after.lastDiceRoll == 6 else { continue }
            let committed = after
            let receipt = try #require(ResourceProductionFeedback(events: events, before: before,
                                                                   after: after, viewer: human))
            #expect(receipt.amount(for: .ore) == 2)
            #expect(receipt.amount(for: .grain) == 1)
            #expect(after == committed)
            #expect(before.players[human.index].resources.values.reduce(0, +) == 0)
            return
        }
        Issue.record("Expected a seeded roll of six in this deterministic fixture search")
    }

    @Test func unchangedOrMismatchedCommittedHandsNeverShowProjectedPayout() {
        let before = fixture()
        var after = rolled(before)
        after.players[human.index].resources[.ore] = 9
        let events = [GameEvent.rolled(roller, total: 6)]

        #expect(ResourceProductionFeedback(events: events, before: before, after: before, viewer: human) == nil)
        #expect(ResourceProductionFeedback(events: events, before: before, after: after, viewer: human) == nil)
    }

    private func fixture() -> GameState {
        let desert = HexCoordinate(q: 6, r: 0)
        let tiles = [
            Tile(coordinate: oreHex, kind: .resource(.ore), numberToken: 6),
            Tile(coordinate: grainHex, kind: .resource(.grain), numberToken: 6),
            Tile(coordinate: otherOreHex, kind: .resource(.ore), numberToken: 6),
            Tile(coordinate: desert, kind: .desert, numberToken: nil)
        ]
        let geometry = BoardGenerator.standard()
        let vertices = Set(tiles.flatMap { geometry.corners(of: $0.coordinate) })
        let board = Board(tiles: tiles, ports: [], onBoardVertices: vertices, onBoardEdges: [], robberTile: desert)
        var state = GameSetup.newGame(board: board, seed: 27)
        state.phase = .rollDice(playerIndex: roller.index)
        state.players[human.index].cities = [board.corners(of: oreHex)[0]]
        state.players[human.index].settlements = [board.corners(of: grainHex)[0]]
        return state
    }

    private func rolled(_ state: GameState, roll: Int = 6) -> GameState {
        var result = state
        MainPhase.rollDice(state: &result, roll: roll)
        return result
    }

    private func receipt(for state: GameState, roll: Int = 6) -> ResourceProductionFeedback? {
        ResourceProductionFeedback(events: [.rolled(roller, total: roll)], before: state,
                                   after: rolled(state, roll: roll), viewer: human, occurredAt: now)
    }
}
