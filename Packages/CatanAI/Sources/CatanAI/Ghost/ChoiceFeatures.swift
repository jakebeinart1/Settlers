import CatanEngine
import Foundation

/// What a person can see when they choose, named so a fitted weight reads as a
/// habit ("plays a knight when it takes Largest Army", "robs a 6 or 8").
///
/// Picked by `ghost fidelity` on Jake's 25 games, scored on games left out of
/// the fit (2026-10-24). Each family exists because a test failed without it:
/// Expert put the robber where Jake did 11% of the time; robbing the hexes
/// with the most pips, not the most buildings, is most of the gap. A
/// feature that did not move a held-out score was cut (what the person did
/// earlier in the turn, what the hand can afford).
///
/// Every value is what the move *is*, read off the board; goodness stays in
/// the `expert` feature, which is Expert's score less the best on offer.
public enum ChoiceFeatures {

    /// Plain move kind: the case name, with a trade reply split by its answer.
    public static func kind(_ move: GameMove) -> String {
        if case .respondToTrade(_, let accept) = move { return accept ? "accept" : "reject" }
        return String(String(describing: move).prefix { $0 != "(" })
    }

    /// Moves chosen among by the same features: a knight is a robber move.
    public static func family(_ kind: String) -> String {
        switch kind {
        case "moveRobber", "playKnight": "robber"
        case "placeInitialSettlement", "buildSettlement": "vertex"
        case "placeInitialRoad", "buildRoad", "playRoadBuilding": "road"
        default: kind
        }
    }

    /// Kinds whose appeal depends on the seat's situation.
    static let situational: Set<String> = [
        "rollDice", "playKnight", "endTurn", "buildRoad", "buildSettlement", "buildCity",
        "buyDevCard", "bankTrade", "proposeTrade",
    ]

    /// One row per kind on offer, in first-offered order: the best Expert
    /// score in it, which kind, how many, and kind x situation.
    ///
    /// `person`, when given, is the person model's value per move
    /// (`GhostPolicy.personScores`), added as the `person` feature.
    public static func kindRows(_ options: [ScoredCandidate], seat: PlayerID, state: GameState,
                                person: [GameMove: Double]? = nil) -> (kinds: [String], rows: [[String: Double]]) {
        let top = options.map(\.score).max() ?? 0
        let personTop = person.map { scores in options.compactMap { scores[$0.move] }.max() ?? 0 }
        var kinds: [String] = []
        var best: [String: Double] = [:]
        var personBest: [String: Double] = [:]
        var count: [String: Int] = [:]
        for option in options {
            let kind = kind(option.move)
            if best[kind] == nil { kinds.append(kind) }
            best[kind] = max(best[kind] ?? -.greatestFiniteMagnitude, option.score)
            if let value = person?[option.move] { personBest[kind] = max(personBest[kind] ?? value, value) }
            count[kind, default: 0] += 1
        }
        let situation = Situation(seat: seat, state: state)
        let rows = kinds.map { kind -> [String: Double] in
            var row = ["expert": best[kind]! - top, "k_" + kind: 1, "n_" + kind: log(Double(count[kind]!))]
            if let personTop, let value = personBest[kind] { row["person"] = value - personTop }
            if situational.contains(kind) {
                for (name, value) in situation.values { row[kind + "*" + name] = value }
            }
            return row
        }
        return (kinds, rows)
    }

    /// One option against the others of its kind.
    public static func optionRow(_ option: ScoredCandidate, top: Double, seat: PlayerID, state: GameState,
                                 person: Double? = nil) -> [String: Double] {
        var row = ["expert": option.score - top, "top": option.score == top ? 1 : 0]
        if let person { row["person"] = person }
        let board = Geometry(seat: seat, state: state)
        switch option.move {
        case .moveRobber(let hex, let victim), .playKnight(let hex, let victim):
            row.merge(board.robber(hex, victim: victim)) { $1 }
        case .placeInitialSettlement(let vertex):
            let spot = board.vertex(vertex)
            row.merge(spot) { $1 }
            if state.players[seat.index].settlements.count == 1 { row["v_second*pips"] = spot["v_pips"] }
        case .buildSettlement(let vertex):
            row.merge(board.vertex(vertex)) { $1 }
        case .placeInitialRoad(let edge), .buildRoad(let edge):
            row.merge(board.road(edge)) { $1 }
        case .bankTrade(let give, let get):
            row.merge(bank(give: give, get: get, hand: state.players[seat.index].resources)) { $1 }
        case .proposeTrade(let offer):
            row["p_give"] = Double(offer.give.values.reduce(0, +))
            row["p_want"] = Double(offer.want.values.reduce(0, +))
        case .discard(let cards):
            let hand = state.players[seat.index].resources
            let biggest = hand.values.max() ?? 0
            let total = cards.values.reduce(0, +)
            row["d_fromMax"] = Double(cards.filter { hand[$0.key, default: 0] == biggest }.values.reduce(0, +))
                / Double(max(total, 1))
            row["d_types"] = Double(cards.filter { $0.value > 0 }.count)
        default: break
        }
        return row
    }

    static func bank(give: [Resource: Int], get: [Resource: Int], hand: [Resource: Int]) -> [String: Double] {
        var after = hand
        for (resource, count) in give { after[resource, default: 0] -= count }
        for (resource, count) in get { after[resource, default: 0] += count }
        let most = hand.values.max() ?? 0
        var row = ["b_give": Double(give.values.reduce(0, +)),
                   "b_giveMost": give.keys.contains { hand[$0, default: 0] == most } ? 1 : 0,
                   "b_getMissing": get.keys.allSatisfy { hand[$0, default: 0] == 0 } ? 1 : 0]
        let before = Purchase.affordable(hand), now = Purchase.affordable(after)
        for purchase in Purchase.allCases {
            row["b_opens_" + purchase.rawValue] = now.contains(purchase) && !before.contains(purchase) ? 1 : 0
        }
        for resource in Resource.allCases { row["b_get_" + resource.rawValue] = Double(get[resource, default: 0]) }
        return row
    }

    enum Purchase: String, CaseIterable {
        case city, settlement, dev, road
        static func affordable(_ hand: [Resource: Int]) -> Set<Purchase> {
            func has(_ cost: [Resource: Int]) -> Bool { cost.allSatisfy { hand[$0.key, default: 0] >= $0.value } }
            var result: Set<Purchase> = []
            if has([.ore: 3, .grain: 2]) { result.insert(.city) }
            if has([.brick: 1, .lumber: 1, .grain: 1, .wool: 1]) { result.insert(.settlement) }
            if has([.ore: 1, .grain: 1, .wool: 1]) { result.insert(.dev) }
            if has([.brick: 1, .lumber: 1]) { result.insert(.road) }
            return result
        }
    }

    /// The seat's standing, which the kind choice is read against.
    struct Situation {
        let values: [(String, Double)]

        /// Total buildings below which the game is "early".
        static let earlyBuildings = 12
        /// Knights that first qualify for Largest Army.
        static let armyMinimum = 3

        init(seat: PlayerID, state: GameState) {
            let me = state.players[seat.index]
            let rivals = state.players.filter { $0.id != seat }
            let hand = me.resources.values.reduce(0, +)
            let rivalVP = rivals.map { state.publicVictoryPoints(for: $0.id) }.max() ?? 0
            let rivalKnights = rivals.map(\.playedKnights).max() ?? 0
            let buildings = state.players.reduce(0) { $0 + $1.settlements.count + $1.cities.count }
            let blocked = me.settlements.union(me.cities).contains { $0.touchingTiles.contains(state.board.robberTile) }
            let takesArmy = state.largestArmyPlayer != seat && me.playedKnights + 1 >= Self.armyMinimum
                && me.playedKnights + 1 > rivalKnights
            values = [
                ("hand", Double(hand)), ("over7", hand > state.rules.discardThreshold ? 1 : 0),
                ("vpLead", Double(state.publicVictoryPoints(for: seat) - rivalVP)),
                ("myVP", Double(state.publicVictoryPoints(for: seat))),
                ("kLead", Double(me.playedKnights - rivalKnights)), ("robOnMe", blocked ? 1 : 0),
                ("early", buildings < Self.earlyBuildings ? 1 : 0),
                ("maxSame", Double(me.resources.values.max() ?? 0)), ("takesLA", takesArmy ? 1 : 0),
            ]
        }
    }

    /// Pips, buildings and ports around a hex, corner or edge.
    struct Geometry {
        let seat: PlayerID
        let state: GameState

        func pips(_ hex: HexCoordinate) -> Int {
            state.board.tiles.first { $0.coordinate == hex }?.numberToken.map(DiceOdds.pips(for:)) ?? 0
        }

        /// Settlement 1, city 2, for `owner`'s buildings on `hex`.
        func weight(of owner: Player, on hex: HexCoordinate) -> Int {
            owner.settlements.filter { $0.touchingTiles.contains(hex) }.count
                + 2 * owner.cities.filter { $0.touchingTiles.contains(hex) }.count
        }

        var leader: PlayerID? {
            state.players.filter { $0.id != seat }
                .max { (state.publicVictoryPoints(for: $0.id), -$0.id.index) < (state.publicVictoryPoints(for: $1.id), -$1.id.index) }?.id
        }

        func hand(_ id: PlayerID) -> Int { state.players[id.index].resources.values.reduce(0, +) }

        func robber(_ hex: HexCoordinate, victim: PlayerID?) -> [String: Double] {
            let pips = pips(hex)
            let rivals = state.players.filter { $0.id != seat }
            let onHex = rivals.reduce(0) { $0 + weight(of: $1, on: hex) }
            let leaderOn = leader.map { weight(of: state.players[$0.index], on: hex) } ?? 0
            let biggest = rivals.map { hand($0.id) }.max() ?? 0
            return [
                "r_pips": Double(pips), "r_is68": pips == 5 ? 1 : 0, "r_oppB": Double(onHex * pips),
                "r_oppN": Double(onHex), "r_leaderB": Double(leaderOn * pips),
                "r_mine": weight(of: state.players[seat.index], on: hex) > 0 ? 1 : 0,
                "r_vHand": Double(victim.map(hand) ?? 0), "r_vLeader": victim != nil && victim == leader ? 1 : 0,
                "r_noVictim": victim == nil ? 1 : 0, "r_vMaxHand": victim.map { hand($0) == biggest } == true ? 1 : 0,
            ]
        }

        func vertex(_ vertex: VertexID) -> [String: Double] {
            var row: [String: Double] = [:]
            var total = 0, most = 0
            var kinds: Set<Resource> = []
            for hex in vertex.touchingTiles {
                let pips = pips(hex)
                total += pips
                most = max(most, pips)
                if case .resource(let resource)? = state.board.tiles.first(where: { $0.coordinate == hex })?.kind {
                    kinds.insert(resource)
                    row["v_" + resource.rawValue, default: 0] += Double(pips)
                }
            }
            row["v_pips"] = Double(total)
            row["v_max"] = Double(most)
            row["v_distinct"] = Double(kinds.count)
            row["v_port"] = state.board.ports.contains { $0.vertexA == vertex || $0.vertexB == vertex } ? 1 : 0
            return row
        }

        /// The edge's far end - away from the seat's own pieces - and the best
        /// open corner one step past it.
        func road(_ edge: EdgeID) -> [String: Double] {
            let me = state.players[seat.index]
            let reached = me.settlements.union(me.cities).union(me.roads.flatMap { [$0.a, $0.b] })
            let far = reached.contains(edge.a) ? edge.b : edge.a
            let taken = Set(state.players.flatMap { $0.settlements.union($0.cities) })
            func open(_ vertex: VertexID) -> Bool {
                !taken.contains(vertex) && !state.board.adjacentVertices(of: vertex).contains(where: taken.contains)
            }
            func pips(_ vertex: VertexID) -> Int { vertex.touchingTiles.reduce(0) { $0 + self.pips($1) } }
            let next = state.board.adjacentVertices(of: far).filter(open).map(pips).max() ?? 0
            let free = open(far)
            return ["rd_farPips": Double(pips(far)), "rd_farFree": free ? 1 : 0,
                    "rd_farFreePips": free ? Double(pips(far)) : 0, "rd_next": Double(next)]
        }
    }
}
