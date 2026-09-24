/// The Conquest variant: tribes hold every producing hex, army cards take them.
///
/// One file so the whole variant can be read in one place; `RulesEngine`,
/// `SetupPhase` and `MainPhase` each call in at exactly one seam.
public enum Conquest {
    public static let armyCardCost: [Resource: Int] = [.brick: 1, .lumber: 1, .wool: 1, .grain: 1, .ore: 1]

    /// What `hand` pays for one army card at `price`, or nil if it cannot.
    /// For "any N" the engine chooses: biggest pile first, ties in
    /// `Resource.allCases` order, so the choice is the same in every process.
    /// ponytail: the buyer cannot choose which cards; add a payment payload to
    /// `.buyArmyCard` if players want to.
    public static func payment(for hand: [Resource: Int], price: ArmyPrice) -> [Resource: Int]? {
        guard let count = price.anyCount else {
            return armyCardCost.allSatisfy { (hand[$0.key] ?? 0) >= $0.value } ? armyCardCost : nil
        }
        var left = hand
        var paid: [Resource: Int] = [:]
        for _ in 0..<count {
            guard let biggest = Resource.allCases.max(by: { (left[$0] ?? 0) < (left[$1] ?? 0) }),
                  (left[biggest] ?? 0) > 0 else { return nil }
            left[biggest, default: 0] -= 1
            paid[biggest, default: 0] += 1
        }
        return paid
    }

    /// Every producing hex held by a tribe at its number's pip count. The
    /// desert gets no entry, which is what makes it un-deployable.
    public static func initialGarrisons(board: Board) -> [HexCoordinate: Garrison] {
        var garrisons: [HexCoordinate: Garrison] = [:]
        for tile in board.tiles {
            guard let token = tile.numberToken else { continue }
            garrisons[tile.coordinate] = Garrison(owner: nil, strength: DiceOdds.pips(for: token))
        }
        return garrisons
    }

    /// The unshuffled deck, ascending. Driven off sorted keys, never dictionary
    /// order, so a seeded shuffle deals the same deck in every process.
    public static func buildArmyDeck(_ counts: [Int: Int]) -> [Int] {
        counts.keys.sorted().flatMap { repeatElement($0, count: counts[$0, default: 0]) }
    }

    /// `player`'s army cards minus those bought this turn, ascending.
    public static func playableCards(for player: PlayerID, in state: GameState) -> [Int] {
        var hand = state.armyHands[player, default: []].sorted()
        for card in state.armyCardsBoughtThisTurn[player, default: []] {
            if let index = hand.firstIndex(of: card) { hand.remove(at: index) }
        }
        return hand
    }

    /// A producing hex one of `player`'s buildings touches, in a Conquest game.
    public static func canDeploy(to hex: HexCoordinate, by player: PlayerID, in state: GameState) -> Bool {
        guard state.variant == .conquest,
              state.board.tiles.contains(where: { $0.coordinate == hex && $0.numberToken != nil }),
              let owner = state.players.first(where: { $0.id == player }) else { return false }
        return HexGeometry.corners(of: hex).contains { owner.settlements.contains($0) || owner.cities.contains($0) }
    }

    /// The garrison after `total` strength from `player` lands on `current`.
    public static func outcome(of total: Int, against current: Garrison?, by player: PlayerID) -> Garrison? {
        if let current, current.owner == player {
            return Garrison(owner: player, strength: current.strength + total)
        }
        let remaining = (current?.strength ?? 0) - total
        if remaining > 0 { return Garrison(owner: current?.owner, strength: remaining) }
        if remaining == 0 { return nil }
        return Garrison(owner: player, strength: -remaining)
    }

    /// Returns what was paid; the drawn card stays private.
    @discardableResult
    static func buy(by player: PlayerID, state: inout GameState) throws -> [Resource: Int] {
        guard state.variant == .conquest else { throw MoveError.wrongPhase }
        guard let index = state.players.firstIndex(where: { $0.id == player }) else {
            throw MoveError.other("unknown player")
        }
        guard !state.armyDeck.isEmpty else { throw MoveError.other("The army deck is empty.") }
        guard let paid = payment(for: state.players[index].resources, price: state.armyPrice) else {
            throw MoveError.insufficientResources
        }
        try RulesEngine.deduct(paid, from: &state, playerIndex: index)
        let card = state.armyDeck.removeFirst()
        state.armyHands[player, default: []].append(card)
        state.armyCardsBoughtThisTurn[player, default: []].append(card)
        return paid
    }

    static func deploy(_ strengths: [Int], to hex: HexCoordinate, by player: PlayerID,
                       state: inout GameState) throws -> Garrison? {
        guard !strengths.isEmpty, canDeploy(to: hex, by: player, in: state) else {
            throw MoveError.illegalPlacement
        }
        var playable = playableCards(for: player, in: state)
        for card in strengths {
            guard let index = playable.firstIndex(of: card) else {
                throw MoveError.other("You don't hold those army cards.")
            }
            playable.remove(at: index)
        }
        for card in strengths {
            let index = state.armyHands[player, default: []].firstIndex(of: card)!
            state.armyHands[player]!.remove(at: index)
        }
        let result = outcome(of: strengths.reduce(0, +), against: state.garrisons[hex], by: player)
        state.garrisons[hex] = result
        return result
    }

    /// One card to every seat, in seat order, when setup ends. A no-op outside
    /// Conquest. Not recorded as bought, so each is playable on turn one.
    static func dealStartingCards(_ state: inout GameState) {
        guard state.variant == .conquest else { return }
        for player in state.players where !state.armyDeck.isEmpty {
            state.armyHands[player.id, default: []].append(state.armyDeck.removeFirst())
        }
    }

    /// Buy, plus per deployable hex: each distinct playable card alone, and -
    /// for a hex held by someone else - the cheapest set that takes it.
    /// Bounded: listing every subset would grow as 2^n on the rendering path.
    /// `apply` still accepts any held subset.
    static func moves(for player: Player, in state: GameState) -> [GameMove] {
        guard state.variant == .conquest else { return [] }
        var moves: [GameMove] = []
        if payment(for: player.resources, price: state.armyPrice) != nil, !state.armyDeck.isEmpty {
            moves.append(.buyArmyCard)
        }
        let playable = playableCards(for: player.id, in: state)
        guard !playable.isEmpty else { return moves }
        let hexes = state.board.tiles.map(\.coordinate).sorted().filter { canDeploy(to: $0, by: player.id, in: state) }
        for hex in hexes {
            let singles = Array(Set(playable)).sorted().map { [$0] }
            var candidates = singles
            let garrison = state.garrisons[hex]
            if garrison?.owner != player.id,
               let cheapest = cheapestSet(exceeding: garrison?.strength ?? 0, from: playable),
               !singles.contains(cheapest) {
                candidates.append(cheapest)
            }
            moves += candidates.map { .deployArmy(to: hex, strengths: $0) }
        }
        return moves
    }

    /// Every deploy `player` could make now: each reachable hex x every distinct
    /// set of its playable cards. `legalMoves` lists a bounded few; a UI that lets
    /// the player pick any set asks here, so the engine stays the authority on
    /// what may be committed. ponytail: 2^n in distinct cards held - fine for
    /// real hands; cap it if hands ever reach the dozens.
    public static func deployMoves(for player: PlayerID, in state: GameState) -> [GameMove] {
        let counts = Dictionary(grouping: playableCards(for: player, in: state), by: { $0 }).mapValues(\.count)
        var sets: [[Int]] = [[]]
        for strength in counts.keys.sorted() {
            sets = sets.flatMap { base in (0...counts[strength]!).map { base + Array(repeating: strength, count: $0) } }
        }
        let chosen = sets.filter { !$0.isEmpty }
        return state.board.tiles.map(\.coordinate).sorted()
            .filter { canDeploy(to: $0, by: player, in: state) }
            .flatMap { hex in chosen.map { GameMove.deployArmy(to: hex, strengths: $0) } }
    }

    /// The subset of `cards` with the smallest total strictly above `target`,
    /// ascending; ties go to the first found in ascending-card order. `nil` if
    /// the whole hand cannot beat it. Subset-sum over at most 9 x deck-size.
    static func cheapestSet(exceeding target: Int, from cards: [Int]) -> [Int]? {
        var best: [Int: [Int]] = [0: []]
        for card in cards.sorted() {
            for (sum, set) in best.sorted(by: { $0.key > $1.key }) where best[sum + card] == nil {
                best[sum + card] = set + [card]
            }
        }
        return best.keys.sorted().first { $0 > target }.flatMap { best[$0] }
    }
}

/// What an army card costs. `String`-raw so saves survive reordering.
public enum ArmyPrice: String, Codable, CaseIterable, Sendable {
    /// One brick, lumber, wool, grain and ore.
    case oneOfEach
    /// Any three resource cards, like a 3:1 port.
    case anyThree
    /// Any single resource card.
    case anyOne

    var anyCount: Int? {
        switch self {
        case .oneOfEach: return nil
        case .anyThree: return 3
        case .anyOne: return 1
        }
    }
}

/// Who holds a hex and how strongly. `owner == nil` is a tribe.
public struct Garrison: Codable, Sendable, Hashable {
    public var owner: PlayerID?
    public var strength: Int

    public init(owner: PlayerID?, strength: Int) {
        self.owner = owner
        self.strength = strength
    }
}
