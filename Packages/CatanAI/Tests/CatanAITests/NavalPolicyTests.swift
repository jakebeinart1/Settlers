import Testing
import Foundation
import CatanEngine
@testable import CatanAI

@Suite struct NavalPolicyTests {
    private func position(fog: Bool = true) throws -> GameState {
        var state = try opening(tier: .traditional, fog: fog, coastalFirst: true)
        try #require(!Naval.launchSites(for: state.players[0].id, in: state).isEmpty,
                     "Ship-focused fixtures require an owned coastal harbor")
        state.phase = .mainTurn(playerIndex: 0)
        return state
    }

    /// Ship scenarios require an existing harbor. Constrain only this fixture's
    /// first setup mask; ordinary policies receive the complete legal opening.
    private func opening(tier: NavalPolicy.Tier, fog: Bool = true,
                         family: NavalMapFamily = .archipelago, coastalFirst: Bool = false) throws -> GameState {
        var state = Naval.newGame(seed: 700_019,
            options: NavalOptions(fogEnabled: fog, mapFamily: family))
        var rng = RandomSource(seed: 12)
        while state.phase.isSetup {
            let seat = state.players[state.phase.awaitingSeatIndex!].id
            let legal = RulesEngine.legalMoves(for: state, seat: seat).filter { move in
                guard coastalFirst, state.players[seat.index].settlements.isEmpty,
                      case .placeInitialSettlement(let vertex) = move else { return true }
                return Naval.isCoastal(vertex, in: state)
            }
            try #require(!legal.isEmpty)
            let move = NavalPolicy(tier: tier).decide(GameObservation(seat: seat, state: state, legalMoves: legal), rng: &rng)
            #expect(legal.contains(move))
            _ = try RulesEngine.apply(move, by: seat, to: &state)
        }
        return state
    }

    @Test(arguments: NavalPolicy.Tier.allCases, NavalMapFamily.allCases)
    func inlandOpeningChoicesCompleteOrdinaryUnfilteredSetup(tier: NavalPolicy.Tier, family: NavalMapFamily) throws {
        let state = try opening(tier: tier, family: family)
        #expect(state.phase == .rollDice(playerIndex: 0))
        #expect(state.players.allSatisfy { $0.settlements.count == 2 && $0.roads.count == 2 })
        #expect(state.players.contains { player in
            player.settlements.contains { !Naval.isCoastal($0, in: state) }
        }, "Real policy setup should exercise the available inland sites")
        #expect(Naval.validationProblem(in: state) == nil)
        let harborless = state.players.filter { Naval.launchSites(for: $0.id, in: state).isEmpty }.map(\.id.index)
        print("NAVAL UNFILTERED OPENING tier=\(tier.rawValue) family=\(family.rawValue) harborless=\(harborless)")
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func fundedInlandOpeningMakesUsefulRoadProgress(tier: NavalPolicy.Tier) throws {
        var state = try opening(tier: tier)
        let seat = state.players[0].id
        #expect(Naval.launchSites(for: seat, in: state).isEmpty)
        state.phase = .mainTurn(playerIndex: seat.index)
        state.players[seat.index].resources = Building.roadCost
        let before = BoardIndex(state: state).approachableSites(for: seat, in: state, limit: 4)
        let distances = Dictionary(uniqueKeysWithValues: before.map { ($0.vertex, $0.roads) })
        let move = choice(in: state, tier: tier)
        guard case .buildRoad = move else { Issue.record("A funded inland road chose \(move)"); return }
        try RulesEngine.apply(move, by: seat, to: &state)
        let after = BoardIndex(state: state).approachableSites(for: seat, in: state, limit: 4)
        #expect(after.contains { $0.roads < distances[$0.vertex, default: Int.max] }
            || before.contains { Building.canBuildSettlement($0.vertex, for: seat, in: state) },
            "The real policy must improve a reachable land settlement opportunity")
        let coastBefore = before.filter { Naval.isCoastal($0.vertex, in: state) }.map(\.roads).min()
        let coastAfter = after.filter { Naval.isCoastal($0.vertex, in: state) }.map(\.roads).min()
        print("NAVAL INLAND ROAD tier=\(tier.rawValue) coastDistanceBefore=\(String(describing: coastBefore)) coastDistanceAfter=\(String(describing: coastAfter))")
    }

    private func choice(in state: GameState, tier: NavalPolicy.Tier, legal: [GameMove]? = nil) -> GameMove {
        let seat = state.players[0].id
        let moves = legal ?? RulesEngine.legalMoves(for: state, seat: seat)
        var rng = RandomSource(seed: 71)
        return NavalPolicy(tier: tier).decide(GameObservation(seat: seat, state: state, legalMoves: moves), rng: &rng)
    }

    private func homeBuildings(_ count: Int, in state: inout GameState) -> [VertexID] {
        let seat = state.players[0].id
        for index in state.players.indices {
            state.players[index].settlements = []
            state.players[index].cities = []
            state.players[index].roads = []
        }
        var result: [VertexID] = []
        for _ in 0..<count {
            let site = Naval.potentialColonySites(for: seat, in: state).first {
                $0.touchingTiles.contains { Naval.isKnownLand($0, in: state) && $0.distance(to: HexCoordinate(q: 0, r: 0)) <= 2 }
            }!
            state.players[0].settlements.insert(site)
            result.append(site)
        }
        return result
    }

    private func highVictoryDrawPosition() throws -> GameState {
        var state = try position(fog: false)
        let sites = homeBuildings(6, in: &state)
        state.players[0].settlements = [sites[0]]
        state.players[0].cities = Set(sites.dropFirst())
        for index in state.players.indices { state.players[index].playedKnights = 7 }
        state.largestArmyPlayer = state.players[0].id
        state.players[0].devCards = [.roadBuilding, .roadBuilding, .roadBuilding, .roadBuilding,
                                   .yearOfPlenty, .yearOfPlenty, .yearOfPlenty, .yearOfPlenty,
                                   .monopoly, .monopoly, .monopoly]
        state.devCardDeck = Array(repeating: .victoryPoint, count: 10) + [.monopoly]
        state.players[0].resources = [.lumber: 3, .brick: 1, .wool: 2, .grain: 1, .ore: 2]
        return state
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func buysAFirstHullThenExplores(tier: NavalPolicy.Tier) throws {
        var state = try position()
        let seat = state.players[0].id
        state.players[0].resources = Naval.shipCost
        let buy = choice(in: state, tier: tier)
        guard case .buildShip = buy else { Issue.record("A funded first expedition chose \(buy)"); return }
        _ = try RulesEngine.apply(buy, by: seat, to: &state)
        let revealed = state.naval!.revealed.count
        let move = choice(in: state, tier: tier)
        guard case .sailShip = move else { Issue.record("A new ship chose \(move)"); return }
        _ = try RulesEngine.apply(move, by: seat, to: &state)
        #expect(state.naval!.revealed.count > revealed)
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func sailsTowardKnownLandingAndFundsAColony(tier: NavalPolicy.Tier) throws {
        var state = try position(fog: false)
        let seat = state.players[0].id
        let start = Naval.launchSites(for: seat, in: state)[0]
        state.naval!.ships = [Ship(id: 80, owner: seat, coordinate: start)]
        state.players[0].resources = [:]
        let move = choice(in: state, tier: tier)
        guard case .sailShip = move else { Issue.record("A known overseas coast should draw a voyage: \(move)"); return }
        _ = try RulesEngine.apply(move, by: seat, to: &state)

        let overseas = Naval.potentialColonySites(for: seat, in: state).first {
            $0.touchingTiles.contains { $0.distance(to: HexCoordinate(q: 0, r: 0)) >= 5 }
        }!
        let landing = overseas.touchingTiles.first { coordinate in
            state.board.tiles.contains { $0.coordinate == coordinate && $0.kind == .sea }
        }!
        state.naval!.ships[0].coordinate = landing
        state.naval!.ships[0].stepsRemaining = Naval.movementPerTurn(in: state)
        let waiting = choice(in: state, tier: tier)
        if case .sailShip(_, let destination) = waiting {
            #expect(Naval.potentialColonySites(for: seat, in: state).contains { $0.touchingTiles.contains(destination) },
                    "An unfunded landing may improve its coast, but must retain immediate colony access")
        } else { #expect(waiting == .endTurn) }
        state.players[0].resources = Building.settlementCost
        let colony = choice(in: state, tier: tier)
        guard case .buildSettlement(let vertex) = colony else { Issue.record("A funded landed expedition chose \(colony)"); return }
        #expect(vertex.touchingTiles.contains(landing))
        _ = try RulesEngine.apply(colony, by: seat, to: &state)
        #expect(Naval.colonyPoints(for: seat, in: state) == 1)
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func flexibleYieldFundsAShipAndRespectsScarceBank(tier: NavalPolicy.Tier) throws {
        var state = try position()
        state.players[0].resources = [.lumber: 2, .wool: 1, .ore: 1]
        state.phase = .choosingResource(playerIndex: 0)
        let preferred = choice(in: state, tier: tier, legal: Resource.allCases.map(GameMove.chooseResource))
        #expect(preferred == .chooseResource(.ore))
        state.bank[.ore] = 0
        let legal = Resource.allCases.filter { state.bank[$0, default: 0] > 0 }.map(GameMove.chooseResource)
        let scarce = choice(in: state, tier: tier, legal: legal)
        #expect(legal.contains(scarce))
        #expect(scarce != .chooseResource(.ore))
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func capturePrefersAnOverseasLanding(tier: NavalPolicy.Tier) throws {
        var state = try position(fog: false)
        let seat = state.players[0].id
        let rival = state.players[1].id
        let site = Naval.potentialColonySites(for: seat, in: state).first {
            $0.touchingTiles.contains { $0.distance(to: HexCoordinate(q: 0, r: 0)) >= 5 }
        }!
        let coast = site.touchingTiles.first { coordinate in state.board.tiles.contains { $0.coordinate == coordinate && $0.kind == .sea } }!
        let home = Naval.launchSites(for: seat, in: state)[0]
        state.naval!.ships = [Ship(id: 4, owner: rival, coordinate: home), Ship(id: 7, owner: rival, coordinate: coast)]
        state.phase = .capturingShip(playerIndex: 0)
        #expect(choice(in: state, tier: tier) == .captureShip(id: 7))
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func hiddenWorldHandsDeckAndFutureRNGCannotChangeDecision(tier: NavalPolicy.Tier) throws {
        var state = try position()
        state.players[0].resources = [.lumber: 2, .wool: 2, .ore: 2, .grain: 2, .brick: 1]
        state.players[1].resources = [.wool: 3]
        state.players[1].devCards = [.knight, .monopoly]
        var altered = state
        altered.rng = RandomSource(seed: 0xF00D)
        altered.devCardDeck.reverse()
        altered.players[1].resources = [.ore: 3]
        altered.players[1].devCards = [.victoryPoint, .yearOfPlenty]
        altered.naval!.islandByHex = [:]
        let terrain = altered.board.tiles.map { tile in
            altered.naval!.revealed.contains(tile.coordinate) ? tile
                : Tile(coordinate: tile.coordinate, kind: .resource(.ore), numberToken: 8)
        }
        altered.board = Board(tiles: terrain, ports: altered.board.ports,
            onBoardVertices: altered.board.onBoardVertices, onBoardEdges: altered.board.onBoardEdges,
            robberTile: altered.board.robberTile)
        let seat = state.players[0].id
        // Hidden topology changes cannot affect this home-only action mask.
        let legal = RulesEngine.legalMoves(for: state, seat: seat)
        let first = GameObservation(seat: seat, state: state, legalMoves: legal)
        let second = GameObservation(seat: seat, state: altered, legalMoves: legal)
        #expect(first == second)
        var rngA = RandomSource(seed: 2), rngB = RandomSource(seed: 2)
        let policy = NavalPolicy(tier: tier)
        #expect(policy.decide(first, rng: &rngA) == policy.decide(second, rng: &rngB))
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func responseOnlyMasksPreservePolicyRNG(tier: NavalPolicy.Tier) throws {
        var state = try position()
        let seat = state.players[0].id
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.ore: 1], want: [.wool: 1])
        state.pendingTradeOffers = [offer]
        state.players[0].resources = [.wool: 2]
        let observation = GameObservation(seat: seat, state: state,
            legalMoves: [.respondToTrade(offerID: offer.id, accept: true), .respondToTrade(offerID: offer.id, accept: false)])
        var rng = RandomSource(seed: 43)
        let before = rng
        _ = NavalPolicy(tier: tier).decide(observation, rng: &rng)
        #expect(rng == before)
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func exchangesOnlyTheSurplusToCompleteAShip(tier: NavalPolicy.Tier) throws {
        var state = try position()
        state.players[0].resources = [.lumber: 6, .wool: 1, .ore: 1]
        let move = choice(in: state, tier: tier)
        guard case .bankTrade(let give, let get) = move else { Issue.record("Missing ship ingredient chose \(move)"); return }
        #expect(get == [.ore: 1])
        #expect(give.keys.allSatisfy { $0 == .lumber })
        _ = try RulesEngine.apply(move, by: state.players[0].id, to: &state)
        #expect(state.players[0].resources[.lumber, default: 0] >= 2)
        guard case .buildShip = choice(in: state, tier: tier) else { Issue.record("Funded ship was not bought"); return }
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func aPermanentWinningUpgradeBeatsAnotherExpedition(tier: NavalPolicy.Tier) throws {
        var state = try position(fog: false)
        let seat = state.players[0].id
        let newHome = Naval.potentialColonySites(for: seat, in: state).first {
            $0.touchingTiles.contains { $0.distance(to: HexCoordinate(q: 0, r: 0)) <= 2 }
        }!
        state.players[0].settlements.insert(newHome)
        state.players[0].devCards = Array(repeating: .victoryPoint, count: 10)
        state.devCardDeck.removeAll { $0 == .victoryPoint }
        state.players[0].resources = [.ore: 3, .grain: 2, .lumber: 2, .wool: 1]
        #expect(state.victoryPoints(for: seat) == 13)
        let winning = choice(in: state, tier: tier)
        guard case .buildCity = winning else { Issue.record("Immediate win chose \(winning)"); return }
        _ = try RulesEngine.apply(winning, by: seat, to: &state)
        #expect(state.phase == .gameOver(winner: seat))
    }

    @Test func flexibleProductionIsAllocatedOnceAcrossRecipeDeficits() throws {
        let state = try position(fog: false)
        let seat = state.players[0].id
        let context = NavalDecisionContext(observation: GameObservation(seat: seat, state: state, legalMoves: [.endTurn]),
            ledger: PublicLedger.fromPositionAlone(state, observer: seat), tier: .expert, personality: .balanced)
        let zero = ProductionRate()
        let rolls = context.recipeRolls(Naval.shipCost, hand: [:], fixed: zero, flexible: 1)
        #expect(abs(rolls - 5) < 0.01, "One flexible card/roll must fund five cards in five rolls")
    }

    @Test func adaptersDeliberatelySelectNavalBrains() throws {
        var state = try position()
        state.players[0].resources = Naval.shipCost
        let seat = state.players[0].id
        let observation = GameObservation(seat: seat, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: seat))
        var rng = RandomSource(seed: 33)
        let traditional = NavalPolicy(tier: .traditional).decide(observation, rng: &rng)
        #expect(HeuristicPolicy(personality: .balanced, id: "adapter").decide(observation, rng: &rng) == traditional)
        let expert = NavalPolicy(tier: .expert).decide(observation, rng: &rng)
        #expect(EvaluationPolicy(revision: .navalV1).decide(observation, rng: &rng) == expert)
        #expect(ExpertRevision.navalV1.policyID == NavalPolicy(tier: .expert).id)
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func externalResponsesCannotLeaveAStaleDurableBotAnswer(tier: NavalPolicy.Tier) throws {
        var state = try position()
        let human = state.players[2].id
        let proposer = state.players[0].id
        state.players[0].resources = [.lumber: 2, .wool: 2, .ore: 3]
        state.players[1].resources = [.lumber: 2, .wool: 2]
        state.players[2].resources = [:]
        let policies = Dictionary(uniqueKeysWithValues: state.players.filter { $0.id != human }.map {
            ($0.id, NavalPolicy(tier: tier) as any Policy)
        })
        var session = GameSession(state: state, policies: policies, policySeed: 33)
        let offer = TradeOffer.enumerated(from: proposer, give: [.ore: 1], want: [.wool: 1])
        _ = try session.commit(seat: proposer, move: .proposeTrade(offer))
        try session.checkpoint.validate()
        _ = try session.applyExternal(.respondToTrade(offerID: offer.id, accept: false), by: human)
        try session.checkpoint.validate()
        let encoded = try JSONEncoder().encode(session.checkpoint)
        let decoded = try JSONDecoder().decode(GameSession.Checkpoint.self, from: encoded)
        let restored = try GameSession(checkpoint: decoded, policies: policies)
        #expect(restored.state.pendingTradeOffers.isEmpty)
        #expect(restored.nextActor() == .seat(proposer))
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func unscopedDirectCallsDoNotRepeatAnOutstandingNegotiation(tier: NavalPolicy.Tier) throws {
        var state = try position()
        let seat = state.players[0].id
        state.players[0].resources = [.lumber: 2]
        state.players[1].resources = [.brick: 3]
        let offer = TradeOffer.enumerated(from: seat, give: [.lumber: 1], want: [.brick: 1])
        state.pendingTradeOffers = [offer]
        let move = choice(in: state, tier: tier)
        if case .proposeTrade = move { Issue.record("Direct policy repeated an unresolved negotiation") }
        var rng = RandomSource(seed: 15)
        let observation = GameObservation(seat: seat, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: seat))
        let adapted = HeuristicPolicy(personality: .balanced, id: "qa-human").decide(observation, rng: &rng)
        if case .proposeTrade = adapted { Issue.record("Direct adapter repeated an unresolved negotiation") }
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func acceptsFundingButPreservesAnAlreadyFundedRecipe(tier: NavalPolicy.Tier) throws {
        var state = try position()
        let rival = state.players[1].id
        state.players[0].resources = [.lumber: 2, .wool: 2, .ore: 1]
        let helpful = TradeOffer.enumerated(from: rival, give: [.ore: 1], want: [.wool: 1])
        state.pendingTradeOffers = [helpful]
        let answers = [GameMove.respondToTrade(offerID: helpful.id, accept: true), .respondToTrade(offerID: helpful.id, accept: false)]
        #expect(choice(in: state, tier: tier, legal: answers) == .respondToTrade(offerID: helpful.id, accept: true))
        state.players[0].resources = Naval.shipCost
        let harmful = TradeOffer.enumerated(from: rival, give: [.wool: 1], want: [.lumber: 1])
        state.pendingTradeOffers = [harmful]
        let badAnswers = [GameMove.respondToTrade(offerID: harmful.id, accept: true), .respondToTrade(offerID: harmful.id, accept: false)]
        #expect(choice(in: state, tier: tier, legal: badAnswers) == .respondToTrade(offerID: harmful.id, accept: false))
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func yearOfPlentyFundsTheMissingExpeditionIngredients(tier: NavalPolicy.Tier) throws {
        var state = try position()
        let seat = state.players[0].id
        state.players[0].resources = [.lumber: 2, .wool: 1]
        state.players[0].devCards = [.yearOfPlenty]
        let card = choice(in: state, tier: tier)
        #expect(card == .playYearOfPlenty(.ore, .ore))
        _ = try RulesEngine.apply(card, by: seat, to: &state)
        guard case .buildShip = choice(in: state, tier: tier) else { Issue.record("The card funded an unused expedition"); return }
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func aWinningLargestArmyKnightClosesTheGame(tier: NavalPolicy.Tier) throws {
        var state = try position()
        let seat = state.players[0].id
        state.players[0].resources = Naval.shipCost
        state.players[0].devCards = [.knight] + Array(repeating: .victoryPoint, count: 10)
        state.players[0].playedKnights = 2
        #expect(state.victoryPoints(for: seat) == 12)
        let move = choice(in: state, tier: tier)
        guard case .playKnight = move else { Issue.record("A winning Largest Army chose \(move)"); return }
        _ = try RulesEngine.apply(move, by: seat, to: &state)
        #expect(state.phase == .gameOver(winner: seat))
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func discardsSurplusWithoutDismantlingAFundedVoyage(tier: NavalPolicy.Tier) throws {
        var state = try position()
        let seat = state.players[0].id
        state.players[0].resources = [.lumber: 2, .wool: 1, .ore: 2, .brick: 7]
        state.phase = .discarding(pending: [seat])
        let move = choice(in: state, tier: tier)
        guard case .discard = move else { Issue.record("Required discard chose \(move)"); return }
        _ = try RulesEngine.apply(move, by: seat, to: &state)
        #expect(Resource.allCases.allSatisfy { state.players[0].resources[$0, default: 0] >= Naval.shipCost[$0, default: 0] })
    }

    @Test func roadsCannotPromiseASiteWhoseCoastIsStillHidden() throws {
        var state = try position(fog: false)
        let seat = state.players[0].id
        let site = Naval.potentialColonySites(for: seat, in: state).first {
            $0.touchingTiles.contains { $0.distance(to: HexCoordinate(q: 0, r: 0)) >= 5 }
        }!
        let sea = site.touchingTiles.first { coordinate in state.board.tiles.contains { $0.coordinate == coordinate && $0.kind == .sea } }!
        let adjacent = state.board.adjacentVertices(of: site)
        let seed = adjacent.sorted().flatMap { state.board.adjacentVertices(of: $0).sorted() }.first {
            $0 != site && !adjacent.contains($0) && $0.touchingTiles.contains { Naval.isKnownLand($0, in: state) }
        }!
        for index in state.players.indices {
            state.players[index].settlements = index == 0 ? [seed] : []
            state.players[index].cities = []
            state.players[index].roads = []
        }
        #expect(BoardIndex(state: state).approachableSites(for: seat, in: state, limit: 4).contains { $0.vertex == site })
        state.naval!.revealed.remove(sea)
        #expect(!BoardIndex(state: state).approachableSites(for: seat, in: state, limit: 4).contains { $0.vertex == site })
        let road = state.board.edgesTouching(site).sorted().first!
        state.players[0].roads = [road]
        #expect(!Building.canBuildSettlement(site, for: seat, in: state))
        #expect(!BoardIndex(state: state).buildableSites(for: seat, in: state).contains(site))
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func aPubliclyCertainColonyWinBeatsAProductiveNonwinningCity(tier: NavalPolicy.Tier) throws {
        var state = try position(fog: false)
        let seat = state.players[0].id
        state.players[0].devCards = Array(repeating: .victoryPoint, count: 10)
        state.devCardDeck.removeAll { $0 == .victoryPoint }
        state.players[0].resources = [.lumber: 1, .brick: 1, .wool: 1, .grain: 3, .ore: 3]
        let observation = GameObservation(seat: seat, state: state, legalMoves: [.endTurn])
        let context = NavalDecisionContext(observation: observation, ledger: NavalPolicy.positionLedger(observation),
            tier: tier, personality: .balanced)
        let site = context.colonySites.min { context.siteValue($0) < context.siteValue($1) }!
        let coast = site.touchingTiles.first { coordinate in state.board.tiles.contains { $0.coordinate == coordinate && $0.kind == .sea } }!
        state.naval!.ships = [Ship(id: 80, owner: seat, coordinate: coast)]
        let city = state.players[0].settlements.sorted().max { context.siteValue($0) < context.siteValue($1) }!
        #expect(state.victoryPoints(for: seat) == 12)
        let winning = GameMove.buildSettlement(site)
        let candidates = [winning, .buildCity(city)]
        #expect(candidates.allSatisfy { RulesEngine.legalMoves(for: state, seat: seat).contains($0) })
        #expect(choice(in: state, tier: tier, legal: candidates) == winning)
        _ = try RulesEngine.apply(winning, by: seat, to: &state)
        #expect(state.phase == .gameOver(winner: seat))
    }

    @Test func unknownComponentConnectionsCannotPromiseAColonyPoint() throws {
        var state = try position(fog: false)
        let seat = state.players[0].id
        let site = Naval.potentialColonySites(for: seat, in: state).first {
            NavalNavigationDiagnostics.isOverseasSite($0, in: state)
        }!
        func guaranteedPoints(_ state: GameState) -> Int {
            let observation = GameObservation(seat: seat, state: state, legalMoves: [.endTurn])
            return NavalDecisionContext(observation: observation, ledger: NavalPolicy.positionLedger(observation),
                tier: .expert, personality: .balanced).colonyPoints(site)
        }
        #expect(guaranteedPoints(state) == 2)
        let border = state.board.tiles.first { tile in
            tile.kind == .sea && !site.touchingTiles.contains(tile.coordinate)
                && (0..<6).contains { Naval.isKnownLand(tile.coordinate.neighbor($0), in: state)
                    && tile.coordinate.neighbor($0).distance(to: HexCoordinate(q: 0, r: 0)) >= 5 }
        }!
        state.naval!.options.fogEnabled = true
        state.naval!.revealed.remove(border.coordinate)
        // Hide every other outside coast too: at least one of these unknown
        // cells borders this component, without hiding the legal landing itself.
        for tile in state.board.tiles where tile.kind == .sea && !site.touchingTiles.contains(tile.coordinate)
            && tile.coordinate.distance(to: HexCoordinate(q: 0, r: 0)) >= 4 {
            state.naval!.revealed.remove(tile.coordinate)
        }
        #expect(guaranteedPoints(state) == 1)
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func owningEveryVictoryCardRemovesTheFalseImmediateDrawPremium(tier: NavalPolicy.Tier) throws {
        var state = try position(fog: false)
        let seat = state.players[0].id
        let home = Naval.potentialColonySites(for: seat, in: state).first {
            $0.touchingTiles.contains { Naval.isKnownLand($0, in: state) && $0.distance(to: HexCoordinate(q: 0, r: 0)) <= 2 }
        }!
        state.players[0].settlements.insert(home)
        state.players[0].devCards = Array(repeating: .victoryPoint, count: 10)
        state.devCardDeck.removeAll { $0 == .victoryPoint }
        state.players[0].resources = [.lumber: 2, .wool: 1, .ore: 2, .grain: 1]
        #expect(state.victoryPoints(for: seat) == 13)
        let launch = Naval.launchSites(for: seat, in: state)[0]
        #expect(choice(in: state, tier: tier, legal: [.buyDevCard, .buildShip(at: launch), .endTurn]) != .buyDevCard)
        let observation = GameObservation(seat: seat, state: state, legalMoves: [.buyDevCard])
        let score = NavalPolicy(tier: tier).assess(observation)[0].score
        #expect(score < 1, "A provably absent victory card cannot carry the winning-draw premium")
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func anUnfundedVoyageCanImproveAPoorLandingWithoutGivingUpAccess(tier: NavalPolicy.Tier) throws {
        var state = try position(fog: false)
        let seat = state.players[0].id
        state.players[0].resources = [:]
        let sites = Naval.potentialColonySites(for: seat, in: state).filter { NavalNavigationDiagnostics.isOverseasSite($0, in: state) }
        func pips(at coordinate: HexCoordinate) -> Int? {
            sites.filter { $0.touchingTiles.contains(coordinate) }.map { site in
                state.board.tiles.filter { site.touchingTiles.contains($0.coordinate) }.reduce(0) { $0 + ($1.numberToken.map(DiceOdds.pips) ?? 0) }
            }.max()
        }
        let seas = state.board.tiles.filter { $0.kind == .sea }.map(\.coordinate).sorted()
        let pair = seas.compactMap { origin -> (HexCoordinate, HexCoordinate)? in
            guard let old = pips(at: origin), old <= 3 else { return nil }
            for direction in 0..<6 {
                let next = origin.neighbor(direction)
                if seas.contains(next), let fresh = pips(at: next), fresh >= 6 { return (origin, next) }
            }
            return nil
        }.first!
        state.naval!.ships = [Ship(id: 80, owner: seat, coordinate: pair.0)]
        let move = choice(in: state, tier: tier, legal: [.endTurn, .sailShip(id: 80, to: pair.1)])
        #expect(move == .sailShip(id: 80, to: pair.1))
        _ = try RulesEngine.apply(move, by: seat, to: &state)
        #expect(choice(in: state, tier: tier, legal: [.endTurn, .sailShip(id: 80, to: pair.0)]) == .endTurn)
    }

    @Test func expertFundsTheSameFinishingDrawThatItValuesWhenAvailable() throws {
        var state = try position(fog: false)
        let seat = state.players[0].id
        // A public Largest Army plus our own cards establishes 13 points without
        // learning any opponent card or the future deck's order.
        state.players[0].playedKnights = 3
        state.largestArmyPlayer = seat
        state.players[0].devCards = Array(repeating: .victoryPoint, count: 9)
        for _ in 0..<9 { state.devCardDeck.remove(at: state.devCardDeck.firstIndex(of: .victoryPoint)!) }
        state.players[0].resources = [.lumber: 4, .ore: 1, .wool: 1]
        #expect(state.victoryPoints(for: seat) == 13)
        let trade = GameMove.bankTrade(give: [.lumber: Trading.bestRate(for: .lumber, player: seat, state: state)], get: [.grain: 1])
        #expect(RulesEngine.legalMoves(for: state, seat: seat).contains(trade))
        #expect(choice(in: state, tier: .expert, legal: [trade, .endTurn]) == trade)
        _ = try RulesEngine.apply(trade, by: seat, to: &state)
        #expect(choice(in: state, tier: .expert, legal: [.buyDevCard, .endTurn]) == .buyDevCard)
    }

    @Test func expertReplacementHullDoesNotRenewTheFirstExpeditionPremium() throws {
        var state = try position(fog: false)
        let seat = state.players[0].id
        state.players[0].resources = Naval.shipCost
        let launch = Naval.launchSites(for: seat, in: state)[0]
        func score(_ state: GameState, _ tier: NavalPolicy.Tier) -> Double {
            let observation = GameObservation(seat: seat, state: state, legalMoves: [.buildShip(at: launch)])
            return NavalPolicy(tier: tier).assess(observation)[0].score
        }
        let firstExpert = score(state, .expert), firstTraditional = score(state, .traditional)
        state.naval!.hullsBuilt[seat] = 1
        #expect(score(state, .expert) < firstExpert)
        #expect(score(state, .traditional) == firstTraditional, "Frozen Traditional keeps its original fleet-count rule")
    }

    @Test func expertDiscountsAnUnfundedVoyageExposedToCapture() throws {
        var state = try position(fog: false)
        let seat = state.players[0].id
        let launch = Naval.launchSites(for: seat, in: state)[0]
        func retention(_ state: GameState) -> Double {
            let observation = GameObservation(seat: seat, state: state, legalMoves: [.endTurn])
            return NavalDecisionContext(observation: observation, ledger: NavalPolicy.positionLedger(observation),
                tier: .expert, personality: .balanced).expeditionRetention(from: launch)
        }
        state.players[0].resources = Naval.shipCost
        let unfunded = retention(state)
        for resource in Resource.allCases { state.players[0].resources[resource, default: 0] += Building.settlementCost[resource, default: 0] }
        #expect(retention(state) > unfunded)
        #expect(unfunded > 0 && unfunded < 1)
    }

    @Test func expertLaunchPlansAProvableWinningColonyWithinThisTurn() throws {
        var state = try position(fog: false)
        let seat = state.players[0].id
        state.players[0].devCards = Array(repeating: .victoryPoint, count: 10)
        state.devCardDeck.removeAll { $0 == .victoryPoint }
        state.players[0].resources = [.lumber: 3, .brick: 1, .wool: 2, .grain: 3, .ore: 5]
        #expect(state.victoryPoints(for: seat) == 12)
        let launch = choice(in: state, tier: .expert)
        guard case .buildShip = launch else { Issue.record("A provable same-turn winning voyage chose \(launch)"); return }
        _ = try RulesEngine.apply(launch, by: seat, to: &state)
        for _ in 0..<4 where state.phase != .gameOver(winner: seat) {
            let move = choice(in: state, tier: .expert)
            switch move {
            case .sailShip, .buildSettlement: break
            default: Issue.record("Winning public voyage abandoned for \(move)"); return
            }
            _ = try RulesEngine.apply(move, by: seat, to: &state)
        }
        #expect(state.phase == .gameOver(winner: seat))
    }

    @Test func expertDoesNotBuyDuplicateAccessWhileAnExistingHullCanDoTheJob() throws {
        var state = try position(fog: false)
        let seat = state.players[0].id
        let launch = Naval.launchSites(for: seat, in: state)[0]
        state.naval!.ships = [Ship(id: 80, owner: seat, coordinate: launch)]
        state.naval!.hullsBuilt[seat] = 1
        state.players[0].resources = Naval.shipCost
        #expect(choice(in: state, tier: .expert, legal: [.buildShip(at: launch), .endTurn]) == .endTurn)
    }

    @Test func aCertainSailingWinBeatsEvenANinetyOnePercentFinishingDraw() throws {
        var state = try highVictoryDrawPosition()
        let seat = state.players[0].id
        #expect(state.victoryPoints(for: seat) == 13)
        let observation = GameObservation(seat: seat, state: state, legalMoves: [.endTurn])
        let context = NavalDecisionContext(observation: observation, ledger: NavalPolicy.positionLedger(observation),
            tier: .expert, personality: .balanced)
        #expect(abs(context.victoryDrawChance - 10.0 / 11) < 0.0001)
        let launch = Naval.launchSites(for: seat, in: state).first { context.winningLaunch(at: $0) }!
        state.naval!.ships = [Ship(id: 80, owner: seat, coordinate: launch)]
        let step = RulesEngine.legalMoves(for: state, seat: seat).filter { if case .sailShip = $0 { true } else { false } }
        let move = choice(in: state, tier: .expert, legal: [.buyDevCard] + step)
        guard case .sailShip = move else { Issue.record("A guaranteed voyage preferred \(move)"); return }
        _ = try RulesEngine.apply(move, by: seat, to: &state)
        for _ in 0..<3 where state.phase != .gameOver(winner: seat) {
            _ = try RulesEngine.apply(choice(in: state, tier: .expert), by: seat, to: &state)
        }
        #expect(state.phase == .gameOver(winner: seat))
    }

    @Test func aCertainPurchaseAndLandingWinBeatsAHigherThanNinetyPercentDraw() throws {
        let state = try highVictoryDrawPosition()
        let seat = state.players[0].id
        let observation = GameObservation(seat: seat, state: state, legalMoves: [.endTurn])
        let context = NavalDecisionContext(observation: observation, ledger: NavalPolicy.positionLedger(observation),
            tier: .expert, personality: .balanced)
        let launch = Naval.launchSites(for: seat, in: state).first { context.winningLaunch(at: $0) }!
        #expect(choice(in: state, tier: .expert, legal: [.buyDevCard, .buildShip(at: launch)]) == .buildShip(at: launch))
    }

    @Test func expertFundsAWinnableRoadEvenWithNoSettlementSupplyOrApproach() throws {
        var state = try position(fog: false)
        let seat = state.players[0].id
        _ = homeBuildings(6, in: &state)
        state.players[0].devCards = Array(repeating: .victoryPoint, count: 6)
        for _ in 0..<6 { state.devCardDeck.remove(at: state.devCardDeck.firstIndex(of: .victoryPoint)!) }
        for length in 1...4 {
            let edge = state.board.onBoardEdges.sorted().first { edge in
                guard Building.canBuildRoad(edge, for: seat, in: state) else { return false }
                var next = state
                next.players[0].roads.insert(edge)
                return LongestRoad.length(for: next.players[0], in: next) == length
            }!
            state.players[0].roads.insert(edge)
        }
        #expect(BoardIndex(state: state).approachableSites(for: seat, in: state, limit: 4).isEmpty)
        #expect(state.victoryPoints(for: seat) == 12)
        state.players[0].resources = [.lumber: 1, .ore: 1, .grain: 1, .wool: 4]
        let trade = GameMove.bankTrade(give: [.wool: Trading.bestRate(for: .wool, player: seat, state: state)], get: [.brick: 1])
        #expect(choice(in: state, tier: .expert, legal: [trade, .endTurn]) == trade)
        #expect(choice(in: state, tier: .expert, legal: [.chooseResource(.brick), .chooseResource(.ore)]) == .chooseResource(.brick))
        _ = try RulesEngine.apply(trade, by: seat, to: &state)
        let win = choice(in: state, tier: .expert)
        guard case .buildRoad = win else { Issue.record("A funded Longest Road finish chose \(win)"); return }
        _ = try RulesEngine.apply(win, by: seat, to: &state)
        #expect(state.phase == .gameOver(winner: seat))
    }
}
