import Testing
@testable import CatanEngine

/// The information contract.
///
/// A bot that reads opponents' hands is not stronger, it is better informed,
/// and a strength number measured against it is partly a measurement of the
/// leak. These tests are what makes "public information only" a property of
/// the code rather than an intention in a doc comment.
@Suite struct PublicLedgerTests {

    private func newGame(seed: UInt64 = 3) -> GameState {
        GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
    }

    @Test func aStealHidesTheResourceFromEveryoneButThiefAndVictim() {
        let thief = PlayerID(index: 0)
        let victim = PlayerID(index: 1)
        let bystander = PlayerID(index: 2)
        let event = GameEvent.movedRobber(thief, from: victim, stealing: .ore)

        #expect(event.masked(for: thief) == event, "the thief takes the card and sees it")
        #expect(event.masked(for: victim) == event, "the victim watches it leave their hand")
        #expect(
            event.masked(for: bystander) == .movedRobber(thief, from: victim, stealing: nil),
            "everyone else sees a card move, not which card"
        )
    }

    @Test func aKnightStealIsMaskedTheSameWay() {
        let thief = PlayerID(index: 2)
        let victim = PlayerID(index: 3)
        let event = GameEvent.playedKnight(thief, from: victim, stealing: .wool)
        #expect(event.masked(for: PlayerID(index: 0)) == .playedKnight(thief, from: victim, stealing: nil))
        #expect(event.masked(for: victim) == event)
    }

    /// The mask must cover every case that carries a private detail. A new
    /// event with a hidden payload should fail here rather than silently leak.
    @Test func everyEventCarryingAPrivateDetailIsMaskedForABystander() {
        let events: [GameEvent] = [
            .movedRobber(PlayerID(index: 0), from: PlayerID(index: 1), stealing: .brick),
            .playedKnight(PlayerID(index: 0), from: PlayerID(index: 1), stealing: .grain),
            .rolled(PlayerID(index: 0), total: 8),
            .builtCity(PlayerID(index: 0)),
            .boughtDevCard(PlayerID(index: 0)),
            .discarded(PlayerID(index: 1), count: 4)
        ]
        let bystander = PlayerID(index: 3)
        for event in events where event.carriesPrivateDetail {
            #expect(
                !event.masked(for: bystander).carriesPrivateDetail,
                "\(event) still carries a private detail after masking"
            )
        }
    }

    @Test func aRollPayoutIsCountedExactly() {
        var state = newGame()
        // Give seat 0 a settlement on a known producing tile.
        let tile = state.board.tiles.first { tile in
            tile.numberToken != nil && tile.kind != .desert && tile.coordinate != state.board.robberTile
        }!
        guard case .resource(let resource) = tile.kind else { return }
        let vertex = state.board.onBoardVertices.sorted().first {
            state.board.neighborTiles(of: $0).contains(tile.coordinate)
        }!
        state.players[0].settlements.insert(vertex)

        var ledger = PublicLedger.fromPositionAlone(state, observer: PlayerID(index: 1))
        ledger.apply(.rolled(PlayerID(index: 0), total: tile.numberToken!), stateBefore: state)

        #expect(
            ledger.belief(of: PlayerID(index: 0)).known[resource] == 1,
            "a roll payout is public - everyone at the table sees it land"
        )
    }

    @Test func aBuildSpendsExactlyWhatItCosts() {
        let state = newGame()
        let builder = PlayerID(index: 0)
        var ledger = PublicLedger(observer: PlayerID(index: 1))
        ledger.apply(.tradedWithBank(builder, gave: [:], got: Building.settlementCost), stateBefore: state)
        #expect(ledger.belief(of: builder).knownTotal == 4)

        ledger.apply(.builtSettlement(builder), stateBefore: state)
        #expect(ledger.belief(of: builder).knownTotal == 0, "the cost is known, so the spend is exact")
        #expect(ledger.belief(of: builder).maxTotal == 0)
    }

    @Test func aStealLeavesTheVictimsCompositionUncertainButTheCountExact() {
        let state = newGame()
        let victim = PlayerID(index: 0)
        let thief = PlayerID(index: 1)
        var ledger = PublicLedger(observer: PlayerID(index: 2))
        ledger.apply(.tradedWithBank(victim, gave: [:], got: [.ore: 3]), stateBefore: state)

        ledger.apply(.movedRobber(thief, from: victim, stealing: nil), stateBefore: state)

        let belief = ledger.belief(of: victim)
        #expect(belief.maxTotal == 2, "hand size is public even when the card is not")
        #expect(belief.knownTotal <= belief.maxTotal, "the floor may never exceed the ceiling")
        #expect(ledger.belief(of: thief).maxTotal == 1)
        #expect(ledger.belief(of: thief).knownTotal == 0, "the thief's new card is unknown to a bystander")
    }

    @Test func monopolyEmptiesEveryOtherHandOfThatResource() {
        let state = newGame()
        let caster = PlayerID(index: 0)
        let other = PlayerID(index: 1)
        var ledger = PublicLedger(observer: PlayerID(index: 2))
        ledger.apply(.tradedWithBank(other, gave: [:], got: [.wool: 2]), stateBefore: state)
        ledger.apply(.playedMonopoly(caster, resource: .wool, gained: 2), stateBefore: state)

        #expect(ledger.belief(of: other).known[.wool, default: 0] == 0)
        #expect(ledger.belief(of: caster).known[.wool] == 2)
    }

    @Test func theObserverAlwaysKnowsItsOwnHandExactly() {
        var state = newGame()
        state.players[2].resources = [.ore: 2, .grain: 1]
        var ledger = PublicLedger(observer: PlayerID(index: 2))
        ledger.reconcileObserverHand(from: state)

        #expect(ledger.belief(of: PlayerID(index: 2)).known == [.ore: 2, .grain: 1])
        #expect(ledger.belief(of: PlayerID(index: 2)).uncertain == 0)
    }

    /// The property that matters most: the ledger never claims a seat holds
    /// something it does not. A floor that overstates would let the planner
    /// price a trade against cards that are not there.
    @Test func theKnownFloorNeverExceedsTheTruth() throws {
        let state = newGame(seed: 11)
        var policies: [PlayerID: any Policy] = [:]
        for player in state.players { policies[player.id] = LedgerProbePolicy() }
        var session = GameSession(state: state, policies: policies, policySeed: 99)

        for _ in 0..<400 {
            guard (try? session.step()) != nil else { break }
            if case .gameOver = session.state.phase { break }
            for observer in session.state.players.map(\.id) {
                let ledger = session.ledger(for: observer)
                for player in session.state.players {
                    let belief = ledger.belief(of: player.id)
                    for resource in Resource.allCases {
                        let claimed = belief.known[resource, default: 0]
                        let actual = player.resources[resource, default: 0]
                        #expect(
                            claimed <= actual,
                            "seat \(player.id.index): ledger claimed \(claimed) \(resource), holds \(actual)"
                        )
                    }
                    #expect(
                        belief.maxTotal >= player.resources.values.reduce(0, +),
                        "the ceiling must never fall below the real hand size"
                    )
                }
            }
        }
    }
}

/// Plays any legal move, seeded, so the ledger is exercised over a long and
/// varied sequence rather than a hand-built one.
private struct LedgerProbePolicy: Policy {
    let id = "ledger-probe"
    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        observation.legalMoves[Int(rng.next() % UInt64(observation.legalMoves.count))]
    }
}
