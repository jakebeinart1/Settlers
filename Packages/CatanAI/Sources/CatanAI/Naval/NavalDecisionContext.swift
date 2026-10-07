import CatanEngine
import Foundation

/// Memoized public facts for one decision. No cache survives a state transition.
/// Sorted coordinates and resource cases keep numeric reductions process-stable.
final class NavalDecisionContext {
    let observation: GameObservation
    let ledger: PublicLedger
    let tier: NavalPolicy.Tier
    let personality: BotPersonality
    let state: GameState
    let seat: PlayerID
    let me: Player
    let tiles: [HexCoordinate: Tile]
    let boardIndex: BoardIndex
    let voyagesEnabled: Bool

    init(observation: GameObservation, ledger: PublicLedger,
         tier: NavalPolicy.Tier, personality: BotPersonality, voyagesEnabled: Bool = true) {
        self.observation = observation
        self.ledger = ledger
        self.tier = tier
        self.personality = personality
        self.voyagesEnabled = voyagesEnabled
        self.state = observation.state
        self.seat = observation.seat
        guard let me = observation.state.players.first(where: { $0.id == observation.seat }) else {
            preconditionFailure("Naval observation names an absent seat")
        }
        self.me = me
        self.tiles = ProductionModel.tileIndex(of: observation.state.board)
        self.boardIndex = BoardIndex(state: observation.state)
    }

    lazy var colonySites = voyagesEnabled ? Naval.potentialColonySites(for: seat, in: state).filter { vertex in
        vertex.touchingTiles.contains { max(abs($0.q), abs($0.r), abs($0.q + $0.r)) >= 5 }
    } : []
    lazy var ownedShips = voyagesEnabled ? state.naval?.ships.filter { $0.owner == seat }.sorted { $0.id < $1.id } ?? [] : []
    lazy var fixedProduction = ProductionModel.rate(for: seat, in: state, tiles: tiles)
    lazy var roadApproaches = boardIndex.approachableSites(for: seat, in: state, limit: 4)
    lazy var purchaseTargets = makePurchaseTargets()
    lazy var bankRates = Dictionary(uniqueKeysWithValues: Resource.allCases.map {
        ($0, Trading.bestRate(for: $0, player: seat, state: state))
    })
    var cachedSeaDistances: [HexCoordinate: [HexCoordinate: Int]] = [:]
    var cachedDiscoveryCounts: [HexCoordinate: Int] = [:]
    var cachedSettlementValues: [VertexID: Double] = [:]
    var cachedInventoryValues: [[Int]: Double] = [:]
    var cachedRoadGains: [EdgeID: Double] = [:]
    var cachedRoadPoints: [EdgeID: Int] = [:]
    var cachedColonyPoints: [VertexID: Int] = [:]

    func assessment(of move: GameMove) -> NavalMoveAssessment {
        let result = score(move)
        precondition(result.score.isFinite, "Naval action valuation must remain finite")
        return NavalMoveAssessment(move: move, score: result.score, reason: result.reason)
    }

    func score(_ move: GameMove) -> (score: Double, reason: String) {
        switch move {
        case .placeInitialSettlement(let vertex):
            return (siteValue(vertex) + setupVariety(at: vertex) + productionImprovement(at: vertex),
                    "Establish productive, complementary home access and fund future recipes")
        case .placeInitialRoad(let edge):
            return (roadGain(edge), "Point the opening road toward a viable settlement")
        case .rollDice: return (100, "Resolve production before voluntary actions")
        case .buildSettlement(let vertex):
            return (purchaseScore(value: settlementValue(vertex) + productionImprovement(at: vertex),
                                  cost: Building.settlementCost, points: colonyPoints(vertex)),
                    "Establish production and a lasting colony")
        case .buildCity(let vertex):
            return (purchaseScore(value: 1.5 + siteValue(vertex) + productionImprovement(at: vertex),
                                  cost: Building.cityCost, points: 1),
                    "Upgrade productive land and advance toward victory")
        case .buildRoad(let edge):
            return (purchaseScore(value: roadGain(edge), cost: Building.roadCost, points: roadPoints(edge)),
                    "Improve reachable settlement opportunities or Longest Road")
        case .buildShip(let coordinate):
            let score = winningLaunch(at: coordinate) ? 19_000 : purchaseScore(value: shipValue(at: coordinate), cost: Self.shipCost, points: 0)
            return (score,
                    "Fund a vessel where an expedition can start")
        case .sailShip(let id, let coordinate):
            return (sailingGain(shipID: id, to: coordinate), "Approach a viable colony or reveal a public frontier")
        case .captureShip(let id): return (captureValue(id), "Acquire expedition access and reduce a rival's fleet")
        case .skipShipCapture: return (0, "Decline a capture if no useful target exists")
        case .chooseResource(let resource):
            return (addingValue([resource: 1]), "Allocate this single yield toward the best funded purchase")
        case .bankTrade(let give, let get):
            return (tradeGain(give: give, get: get), "Convert surplus into useful purchase funding")
        case .proposeTrade(let offer): return (proposalValue(offer), "Offer a beneficial exchange that funds a concrete plan")
        case .respondToTrade(let id, let accept):
            return (accept ? acceptanceValue(id) : 0, accept ? "Accept a gain after pricing the counterparty" : "Preserve resources")
        case .discard(let amounts): return (discardValue(amounts), "Preserve the most useful post-discard purchase funding")
        case .moveRobber(let coordinate, let victim):
            return (robberValue(at: coordinate, victim: victim), "Block public production and steal from an eligible rival")
        case .playKnight(let coordinate, let victim):
            return (knightValue(at: coordinate, victim: victim), "Use a Knight for disruption or Largest Army")
        case .playRoadBuilding(let first, let second):
            return (roadBuildingValue(first, second), "Advance two useful roads without paying resource costs")
        case .playYearOfPlenty(let first, let second):
            return (addingValue(Resource.allCases.reduce(into: [:]) {
                $0[$1] = ($1 == first ? 1 : 0) + ($1 == second ? 1 : 0)
            }) + 0.04, "Choose resources that advance a concrete purchase")
        case .playMonopoly(let resource): return (monopolyValue(resource), "Use counted public beliefs to choose a resource")
        case .buyDevCard: return (devCardValue(), "Invest in a card's public expected value, never its hidden face")
        case .endTurn: return (0, "End when no considered action offers a positive gain")
        case .buyArmyCard, .deployArmy:
            preconditionFailure("Conquest actions cannot enter a Voyages action mask")
        }
    }

    static let shipCost: [Resource: Int] = [.lumber: 2, .wool: 1, .ore: 2]
    static let negativeScore = -Double.greatestFiniteMagnitude
    var sureWinScore: Double { tier == .expert ? 20_000 : 10_000 }

    func purchaseScore(value: Double, cost: [Resource: Int], points: Int) -> Double {
        if state.victoryPoints(for: seat) + points >= state.victoryPointTarget { return sureWinScore + value }
        let after = spending(cost, from: me.resources)
        let opportunity = inventoryValue(after) - inventoryValue(me.resources)
        return value + pointPremium(points) + (tier == .expert ? 0.65 : 0.32) * opportunity
    }

    /// Permanent points become more urgent as either public rival progress or
    /// our private score shortens the race. Funding a provable finishing recipe
    /// receives a further premium; this affects trades before a build is legal.
    func pointPremium(_ points: Int) -> Double {
        guard tier == .expert, points > 0 else { return 0 }
        let own = state.victoryPoints(for: seat)
        let leader = state.players.filter { $0.id != seat }.map { state.publicVictoryPoints(for: $0.id) }.max() ?? 0
        let race = Double(max(own, leader)) / Double(state.victoryPointTarget)
        let closing = own + points >= state.victoryPointTarget ? sureWinScore : 0
        return Double(points) * max(0, race - 0.5) * 3 + closing
    }

    func spending(_ cost: [Resource: Int], from hand: [Resource: Int]) -> [Resource: Int] {
        var after = hand
        for resource in Resource.allCases { after[resource, default: 0] -= cost[resource] ?? 0 }
        return after
    }

    func setupVariety(at vertex: VertexID) -> Double {
        let missing = Resource.allCases.filter { fixedProduction[$0] == 0 }
        return state.board.neighborTiles(of: vertex).sorted().reduce(0.0) { sum, coordinate in
            guard let tile = tiles[coordinate], case .resource(let resource) = tile.kind,
                  missing.contains(resource) else { return sum }
            return sum + 0.12
        }
    }
}
