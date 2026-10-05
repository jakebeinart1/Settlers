import Foundation
import Testing
@testable import CatanEngine

/// A one-card victim cannot distinguish theft of one card from theft of a
/// whole hand. Mixed, multi-card hands make that regression observable.
@Suite struct DevCardConservationTests {
    @Test(arguments: EngineFairnessCase.all)
    func knightTakesExactlyOneCardFromOnlyTheChosenVictim(fixture: EngineFairnessCase) throws {
        for seed: UInt64 in 0..<12 {
            for beforeRoll in [false, true] {
                var state = fixture.state(seed: seed, beforeRoll: beforeRoll)
                state.players[fixture.seat].devCards = [.knight, .monopoly]
                let before = state
                let events = try RulesEngine.apply(
                    .playKnight(moveRobberTo: fixture.target(in: state), stealFrom: fixture.victim),
                    by: fixture.actor, to: &state)
                #expect(total(state.players[fixture.victim.index]) == 8)
                #expect(total(state.players[fixture.seat]) == 10)
                #expect(state.players[fixture.bystander.index] == before.players[fixture.bystander.index])
                #expect(state.players[(fixture.seat + 3) % 4] == before.players[(fixture.seat + 3) % 4])
                #expect(state.bank == before.bank)
                #expect(state.garrisons == before.garrisons)
                #expect(state.phase == before.phase, "Knight never triggers discards or skips the roll")
                #expect(state.players[fixture.seat].devCards == [.monopoly])
                #expect(state.players[fixture.seat].playedKnights == 1)
                assertKnightEvent(events, fixture: fixture, before: before, after: state)
            }
        }
    }

    @Test(arguments: EngineFairnessCase.all)
    func knightWithoutAResourceHoldingNeighbourConsumesOneCardWithoutTheft(fixture: EngineFairnessCase) throws {
        var state = fixture.state()
        state.players[fixture.victim.index].resources = [:]
        state.players[fixture.bystander.index].resources = [:]
        state.players[fixture.seat].devCards = [.knight]
        let before = state
        let events = try RulesEngine.apply(.playKnight(moveRobberTo: fixture.target(in: state), stealFrom: nil),
                                          by: fixture.actor, to: &state)
        #expect(events == [.playedKnight(fixture.actor, from: nil, stealing: nil)])
        #expect(state.players.map(\.resources) == before.players.map(\.resources))
        #expect(state.players[fixture.seat].devCards.isEmpty)
        #expect(state.rng == before.rng)
    }

    @Test(arguments: EngineFairnessCase.all)
    func invalidKnightVictimCannotConsumeOrPartiallyApply(fixture: EngineFairnessCase) throws {
        var state = fixture.state()
        state.players[fixture.seat].devCards = [.knight]
        let before = state
        for victim in [Optional<PlayerID>.none, fixture.actor, PlayerID(index: (fixture.seat + 3) % 4)] {
            #expect(throws: MoveError.illegalPlacement) {
                try RulesEngine.apply(.playKnight(moveRobberTo: fixture.target(in: state), stealFrom: victim),
                                      by: fixture.actor, to: &state)
            }
            #expect(state == before)
        }
    }

    @Test(arguments: EngineFairnessCase.all)
    func monopolyTransfersOneResourceAndCannotBeReusedAfterResume(fixture: EngineFairnessCase) throws {
        var state = fixture.state()
        state.players[fixture.seat].devCards = [.monopoly, .victoryPoint]
        let before = state
        let events = try RulesEngine.apply(.playMonopoly(.ore), by: fixture.actor, to: &state)
        #expect(events == [.playedMonopoly(fixture.actor, resource: .ore, gained: 5)])
        #expect(state.players[fixture.seat].resources[.ore] == 7)
        #expect(state.players[fixture.victim.index].resources[.ore] == 0)
        #expect(state.players[fixture.bystander.index].resources[.ore] == 0)
        for player in state.players {
            for resource in Resource.allCases where resource != .ore {
                #expect(player.resources[resource] == before.players[player.id.index].resources[resource])
            }
        }
        #expect(state.bank == before.bank)
        #expect(state.rng == before.rng)
        #expect(state.players[fixture.seat].devCards == [.victoryPoint])
        try assertMonopolyRejectedWithoutMutation(state: &state, actor: fixture.actor)
        state = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state))
        try returnToNextTurn(state: &state, actor: fixture.actor)
        try assertMonopolyRejectedWithoutMutation(state: &state, actor: fixture.actor)
    }

    @Test(arguments: EngineFairnessCase.all)
    func aSecondMatureMonopolyNeedsAnotherTurnAndAZeroGainStillConsumes(fixture: EngineFairnessCase) throws {
        var state = fixture.state(beforeRoll: true)
        state.players[fixture.seat].devCards = [.monopoly, .monopoly]
        let events = try RulesEngine.apply(.playMonopoly(.lumber), by: fixture.actor, to: &state)
        #expect(events == [.playedMonopoly(fixture.actor, resource: .lumber, gained: 0)])
        #expect(state.players[fixture.seat].devCards == [.monopoly])
        state.phase = .mainTurn(playerIndex: fixture.seat)
        try assertMonopolyRejectedWithoutMutation(state: &state, actor: fixture.actor)
        try returnToNextTurn(state: &state, actor: fixture.actor)
        try RulesEngine.apply(.playMonopoly(.ore), by: fixture.actor, to: &state)
        #expect(state.players[fixture.seat].devCards.isEmpty)
        #expect(state.players[fixture.seat].resources[.ore] == 7)
    }

    @Test(arguments: EngineFairnessCase.all)
    func olderCopyCanBePlayedButNewCopyWaitsUntilNextTurn(fixture: EngineFairnessCase) throws {
        var state = fixture.state()
        state.players[fixture.seat].devCards = [.monopoly, .monopoly]
        state.devCardsBoughtThisTurn[fixture.actor] = [.monopoly]
        try RulesEngine.apply(.playMonopoly(.ore), by: fixture.actor, to: &state)
        #expect(state.players[fixture.seat].devCards == [.monopoly])
        #expect(DevCards.playStatus(.monopoly, by: fixture.actor, in: state) == .boughtThisTurn)
        try assertMonopolyRejectedWithoutMutation(state: &state, actor: fixture.actor)
        try returnToNextTurn(state: &state, actor: fixture.actor)
        #expect(DevCards.playStatus(.monopoly, by: fixture.actor, in: state) == .playable)
        try RulesEngine.apply(.playMonopoly(.ore), by: fixture.actor, to: &state)
        #expect(state.players[fixture.seat].devCards.isEmpty)
    }

    private func assertKnightEvent(_ events: [GameEvent], fixture: EngineFairnessCase,
                                   before: GameState, after: GameState) {
        guard case .playedKnight(let actor, let victim, let stolen) = events.first,
              let stolen else { Issue.record("Knight must report its one stolen card"); return }
        #expect(actor == fixture.actor && victim == fixture.victim)
        for resource in Resource.allCases {
            let delta = resource == stolen ? 1 : 0
            #expect(after.players[actor.index].resources[resource, default: 0]
                    == before.players[actor.index].resources[resource, default: 0] + delta)
            #expect(after.players[fixture.victim.index].resources[resource, default: 0]
                    == before.players[fixture.victim.index].resources[resource, default: 0] - delta)
        }
    }

    private func assertMonopolyRejectedWithoutMutation(state: inout GameState, actor: PlayerID) throws {
        let before = state
        #expect(throws: MoveError.illegalPlacement) {
            try RulesEngine.apply(.playMonopoly(.ore), by: actor, to: &state)
        }
        #expect(state == before)
        #expect(!RulesEngine.legalMoves(for: state, seat: actor).contains(.playMonopoly(.ore)))
    }

    /// Rotate real end-turn moves; intervening rolls are irrelevant to this
    /// card-lifetime property, so advance those phases directly in the fixture.
    private func returnToNextTurn(state: inout GameState, actor: PlayerID) throws {
        for offset in 0..<state.players.count {
            let seat = PlayerID(index: (actor.index + offset) % state.players.count)
            state.phase = .mainTurn(playerIndex: seat.index)
            try RulesEngine.apply(.endTurn, by: seat, to: &state)
        }
        #expect(state.phase == .rollDice(playerIndex: actor.index))
    }

    private func total(_ player: Player) -> Int { player.resources.values.reduce(0, +) }
}
