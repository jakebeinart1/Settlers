import Foundation
import Testing
@testable import CatanEngine

/// Actual dice application must create the discard obligation before the robber
/// can move. Directly seeded discard fixtures cannot detect a wrong mode threshold.
struct NavalSevenTests {
    @Test func rolledSevenDiscardsTheReportedEightCardHandBeforeMovingTheRobber() throws {
        let owner = PlayerID(index: 0)
        var state = try position(holding: [.brick: 1, .lumber: 4, .ore: 1, .wool: 2], seat: owner)
        let knight = try #require(state.devCardDeck.firstIndex(of: .knight))
        state.players[owner.index].devCards = [state.devCardDeck.remove(at: knight)]
        let bank = state.bank

        let events = try NavalTestSupport.roll(7, player: owner.index, state: &state)

        #expect(events == [.rolled(owner, total: 7)])
        #expect(state.phase == .discarding(pending: [owner]))
        #expect(state.robberMoverIndex == owner.index)
        #expect(state.bank == bank)
        #expect(state.players[owner.index].devCards == [.knight])
        #expect(Robber.discardCount(for: state.players[owner.index]) == 4)
        #expect(RulesEngine.legalMoves(for: state, seat: owner).allSatisfy {
            if case .discard = $0 { return true }
            return false
        })
    }

    @Test(arguments: [7, 8, 9, 10, 11])
    func thresholdIsStrictAndTheRequiredDiscardRoundsDown(cards: Int) throws {
        let owner = PlayerID(index: 1)
        var state = try position(holding: [.lumber: cards], seat: owner)
        #expect(state.rules.discardThreshold == 7)
        try NavalTestSupport.roll(7, player: owner.index, state: &state)
        if cards == 7 {
            #expect(state.phase == .movingRobber(playerIndex: owner.index))
            return
        }
        #expect(state.phase == .discarding(pending: [owner]))
        let bank = state.bank[.lumber, default: 0]
        let discarded = cards / 2
        let events = try RulesEngine.apply(.discard([.lumber: discarded]), by: owner, to: &state)
        #expect(events == [.discarded(owner, count: discarded)])
        #expect(state.players[owner.index].resources[.lumber] == cards - discarded)
        #expect(state.bank[.lumber] == bank + discarded)
        #expect(state.phase == .movingRobber(playerIndex: owner.index))
        #expect(state.robberMoverIndex == nil)
    }

    @Test(arguments: [3, 4])
    func anotherPlayersSevenResolvesEveryDiscardBeforeReturningToItsRoller(table: Int) throws {
        let roller = PlayerID(index: table - 1)
        var state = try position(holding: [:], seat: roller, playerCount: table)
        NavalTestSupport.fund([.lumber: 8], player: 0, in: &state)
        NavalTestSupport.fund([.lumber: 9], player: 1, in: &state)
        NavalTestSupport.fund([.lumber: 7], player: roller.index, in: &state)
        let pending: Set<PlayerID> = [PlayerID(index: 0), PlayerID(index: 1)]
        let bank = state.bank[.lumber, default: 0]
        try NavalTestSupport.roll(7, player: roller.index, state: &state)
        #expect(state.phase == .discarding(pending: pending))
        try RulesEngine.apply(.discard([.lumber: 4]), by: state.players[1].id, to: &state)
        #expect(state.phase == .discarding(pending: [state.players[0].id]))
        try RulesEngine.apply(.discard([.lumber: 4]), by: state.players[0].id, to: &state)
        #expect(state.phase == .movingRobber(playerIndex: roller.index))
        #expect(state.bank[.lumber] == bank + 8)
        #expect(state.players[roller.index].resources[.lumber] == 7)
        #expect(state.naval?.pendingResourceChoices.isEmpty == true)
        #expect(state.naval?.productionRollerIndex == nil)
        #expect(state.naval?.capturePending == false)
    }

    @Test func developmentCardsNeverCountTowardTheSevenResourceThreshold() throws {
        let owner = PlayerID(index: 1)
        var state = try position(holding: [.lumber: 7], seat: owner)
        for type in [DevCardType.knight, .roadBuilding, .monopoly] {
            let index = try #require(state.devCardDeck.firstIndex(of: type))
            state.players[owner.index].devCards.append(state.devCardDeck.remove(at: index))
        }
        try NavalTestSupport.roll(7, player: owner.index, state: &state)
        #expect(state.phase == .movingRobber(playerIndex: owner.index))
        #expect(state.players[owner.index].resources[.lumber] == 7)
        #expect(state.players[owner.index].devCards.count == 3)
    }

    @Test func playingAKnightDoesNotDiscardButTheFollowingSevenDoes() throws {
        let owner = PlayerID(index: 1)
        var state = try position(holding: [.lumber: 8], seat: owner)
        let knight = try #require(state.devCardDeck.firstIndex(of: .knight))
        state.players[owner.index].devCards = [state.devCardDeck.remove(at: knight)]
        state.phase = .rollDice(playerIndex: owner.index)
        let move = try #require(RulesEngine.legalMoves(for: state, seat: owner).first {
            if case .playKnight = $0 { return true }
            return false
        })
        try RulesEngine.apply(move, by: owner, to: &state)
        #expect(state.phase == .rollDice(playerIndex: owner.index))
        #expect(state.players[owner.index].resources[.lumber] == 8)
        #expect(state.players[owner.index].playedKnights == 1)
        try NavalTestSupport.roll(7, player: owner.index, state: &state)
        #expect(state.phase == .discarding(pending: [owner]))
    }

    @Test func robberMovementAndWrongDiscardCountsCannotBypassTheObligation() throws {
        let owner = PlayerID(index: 0)
        var state = try position(holding: [.lumber: 8], seat: owner)
        try NavalTestSupport.roll(7, player: owner.index, state: &state)
        let target = try #require(state.board.tiles.first {
            $0.kind.isLand && $0.coordinate != state.board.robberTile
        }?.coordinate)
        let before = state
        #expect(throws: MoveError.wrongPhase) {
            try RulesEngine.apply(.moveRobber(target, stealFrom: nil), by: owner, to: &state)
        }
        #expect(state == before)
        #expect(throws: MoveError.illegalPlacement) {
            try RulesEngine.apply(.discard([.lumber: 3]), by: owner, to: &state)
        }
        #expect(state == before)
        #expect(throws: MoveError.notYourTurn) {
            try RulesEngine.apply(.discard([.lumber: 4]), by: state.players[1].id, to: &state)
        }
        #expect(state == before)
    }

    @Test(arguments: [1, 2, 3, 4], [8, 9, 10, 11])
    func legacyRollsRetainTheirTenCardThresholdAndExactReplay(version: Int, cards: Int) throws {
        let owner = PlayerID(index: 1)
        var state = try position(holding: [.lumber: cards], seat: owner, version: version)
        #expect(state.rules.discardThreshold == 10)
        try NavalTestSupport.prepareRoll(7, player: owner.index, state: &state)
        var played = state
        let events = try RulesEngine.apply(.rollDice, by: owner, to: &played)
        #expect(played.phase == (cards > 10 ? .discarding(pending: [owner]) : .movingRobber(playerIndex: owner.index)))
        let restored = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state))
        for engineVersion in RulesEngine.oldestSupportedRulesVersion...RulesEngine.currentRulesVersion {
            var replay = restored
            #expect(try RulesEngine.replay(.rollDice, by: owner, rulesVersion: engineVersion, to: &replay) == events)
            #expect(replay == played)
            #expect(replay.rules.discardThreshold == 10)
        }
    }

    @Test func coldCheckpointRetainsTheActualSevenAndItsOutstandingDiscard() throws {
        let owner = PlayerID(index: 1)
        var state = try position(holding: [.lumber: 8], seat: owner)
        try NavalTestSupport.roll(7, player: 2, state: &state)
        var original = GameSession(state: state, policies: [:], policySeed: 7)
        let decoded = try JSONDecoder().decode(GameSession.Checkpoint.self, from: JSONEncoder().encode(original.checkpoint))
        try decoded.validate()
        var resumed = try GameSession(checkpoint: decoded, policies: [:])
        #expect(resumed.nextActor() == .awaitingExternalSeat(owner))
        #expect(resumed.state.phase == .discarding(pending: [owner]))
        #expect(resumed.state.rules.discardThreshold == 7)
        let move = GameMove.discard([.lumber: 4])
        let first = try original.applyExternal(move, by: owner)
        let second = try resumed.applyExternal(move, by: owner)
        #expect(first.actor == second.actor && first.move == second.move && first.events == second.events)
        #expect(original.checkpoint == resumed.checkpoint)
        #expect(resumed.state.phase == .movingRobber(playerIndex: 2))
    }

    private func position(holding: [Resource: Int], seat: PlayerID,
                          playerCount: Int = 4, version: Int? = nil) throws -> GameState {
        var state = try NavalTestSupport.ready(playerCount: playerCount, rulesVersion: version)
        for index in state.players.indices {
            for resource in Resource.allCases {
                state.bank[resource, default: 0] += state.players[index].resources[resource, default: 0]
            }
            state.players[index].resources = [:]
        }
        NavalTestSupport.fund(holding, player: seat.index, in: &state)
        return state
    }
}
