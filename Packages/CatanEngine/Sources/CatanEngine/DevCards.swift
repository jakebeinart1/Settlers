/// Development card rules: buying, playing each of the four playable
/// types (knight, road building, year of plenty, monopoly - victory point
/// cards are never "played", they just add to `Player.victoryPoints`), and
/// largest-army tracking.
public enum DevCards {
    /// Deducts `Building.devCardCost` (1 ore, 1 grain, 1 wool), draws the
    /// top card of `state.devCardDeck` into `player`'s hand, and records it
    /// as bought this turn (unplayable until next turn).
    @discardableResult
    public static func buy(by player: PlayerID, state: inout GameState) throws -> DevCardType {
        guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else {
            throw MoveError.other("unknown player")
        }
        guard !state.devCardDeck.isEmpty else { throw MoveError.other("dev card deck is empty") }
        try RulesEngine.deduct(Building.devCardCost, from: &state, playerIndex: playerIndex)

        let card = state.devCardDeck.removeFirst()
        state.players[playerIndex].devCards.append(card)
        state.devCardsBoughtThisTurn[player, default: []].append(card)
        return card
    }

    /// Moves the robber and steals exactly like `Robber.apply`, then
    /// consumes the played knight and increments `player.playedKnights`,
    /// recomputing `largestArmyPlayer` (first to 3 knights; ties keep the
    /// current holder, matching longest-road tie handling).
    @discardableResult
    public static func playKnight(
        moveRobberTo: HexCoordinate,
        stealFrom: PlayerID?,
        by player: PlayerID,
        state: inout GameState
    ) throws -> Resource? {
        guard canPlay(.knight, by: player, in: state) else { throw MoveError.illegalPlacement }
        let stolen = try Robber.apply(move: moveRobberTo, stealFrom: stealFrom, by: player, to: &state)
        consumeCard(.knight, from: player, state: &state)
        state.devCardPlayedThisTurn = player

        guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else {
            throw MoveError.other("unknown player")
        }
        state.players[playerIndex].playedKnights += 1
        state.largestArmyPlayer = computeLargestArmy(for: state)
        return stolen
    }

    /// Builds `e1` then `e2` for free (skips resource cost, but each edge
    /// must still be a legal road placement via `Building.canBuildRoad`,
    /// checked in order so `e2` may connect off the just-built `e1`).
    /// Throws without mutating `state` if `e1` is illegal; rolls back `e1`
    /// and throws if `e2` is illegal.
    public static func playRoadBuilding(
        _ e1: EdgeID,
        _ e2: EdgeID,
        by player: PlayerID,
        state: inout GameState
    ) throws {
        guard canPlay(.roadBuilding, by: player, in: state) else { throw MoveError.illegalPlacement }
        guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else {
            throw MoveError.other("unknown player")
        }
        guard Building.canBuildRoad(e1, for: player, in: state) else { throw MoveError.illegalPlacement }
        state.players[playerIndex].roads.insert(e1)

        guard Building.canBuildRoad(e2, for: player, in: state) else {
            state.players[playerIndex].roads.remove(e1)
            throw MoveError.illegalPlacement
        }
        state.players[playerIndex].roads.insert(e2)

        consumeCard(.roadBuilding, from: player, state: &state)
        state.devCardPlayedThisTurn = player
        state.longestRoadPlayer = LongestRoad.compute(for: state)
    }

    /// Grants exactly one card each of `r1` and `r2` from the bank.
    ///
    /// Availability is checked as one transaction before either card moves.
    /// Silently granting only one made the chooser promise "choose 2" while the
    /// rules delivered less and still consumed the development card.
    public static func playYearOfPlenty(
        _ r1: Resource,
        _ r2: Resource,
        by player: PlayerID,
        state: inout GameState
    ) throws {
        guard canPlay(.yearOfPlenty, by: player, in: state) else { throw MoveError.illegalPlacement }
        guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else {
            throw MoveError.other("unknown player")
        }
        var requested: [Resource: Int] = [:]
        requested[r1, default: 0] += 1
        requested[r2, default: 0] += 1
        for resource in Resource.allCases where (state.bank[resource] ?? 0) < (requested[resource] ?? 0) {
            throw MoveError.bankCannotSupply(resource)
        }
        for resource in Resource.allCases where (requested[resource] ?? 0) > 0 {
            let count = requested[resource] ?? 0
            state.bank[resource, default: 0] -= count
            state.players[playerIndex].resources[resource, default: 0] += count
        }
        consumeCard(.yearOfPlenty, from: player, state: &state)
        state.devCardPlayedThisTurn = player
    }

    /// Exact version-1 behavior for persisted-history replay. The original
    /// rule silently supplied whichever requested cards happened to remain in
    /// the bank and still consumed the card. Version 2 made the choice atomic;
    /// old recordings retain their historical outcome instead of becoming
    /// unreadable after an app upgrade.
    static func playYearOfPlentyRulesVersionOne(
        _ first: Resource,
        _ second: Resource,
        by player: PlayerID,
        state: inout GameState
    ) throws {
        guard canPlay(.yearOfPlenty, by: player, in: state),
              let playerIndex = state.players.firstIndex(where: { $0.id == player }) else {
            throw MoveError.illegalPlacement
        }
        for resource in [first, second] where (state.bank[resource] ?? 0) > 0 {
            state.bank[resource, default: 0] -= 1
            state.players[playerIndex].resources[resource, default: 0] += 1
        }
        consumeCard(.yearOfPlenty, from: player, state: &state)
        state.devCardPlayedThisTurn = player
    }

    /// Version-1 Knight wrapper paired with the replay-only robber semantics.
    static func playKnightRulesVersionOne(
        moveRobberTo tile: HexCoordinate,
        stealFrom victim: PlayerID?,
        by player: PlayerID,
        state: inout GameState
    ) throws -> Resource? {
        guard canPlay(.knight, by: player, in: state) else { throw MoveError.illegalPlacement }
        let stolen = try Robber.applyRulesVersionOne(
            move: tile, stealFrom: victim, by: player, to: &state)
        consumeCard(.knight, from: player, state: &state)
        state.devCardPlayedThisTurn = player
        guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else {
            throw MoveError.other("unknown player")
        }
        state.players[playerIndex].playedKnights += 1
        state.largestArmyPlayer = computeLargestArmy(for: state)
        return stolen
    }

    /// Every other player hands over all of their `resource` cards to
    /// `player`. Returns how many were collected.
    @discardableResult
    public static func playMonopoly(_ resource: Resource, by player: PlayerID, state: inout GameState) throws -> Int {
        guard canPlay(.monopoly, by: player, in: state) else { throw MoveError.illegalPlacement }
        guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else {
            throw MoveError.other("unknown player")
        }
        var collected = 0
        for index in state.players.indices where state.players[index].id != player {
            let amount = state.players[index].resources[resource] ?? 0
            guard amount > 0 else { continue }
            state.players[index].resources[resource, default: 0] -= amount
            state.players[playerIndex].resources[resource, default: 0] += amount
            collected += amount
        }
        consumeCard(.monopoly, from: player, state: &state)
        state.devCardPlayedThisTurn = player
        return collected
    }

    /// Whether `player` holds a card of `type` that wasn't bought this turn,
    /// and `player` hasn't already played a development card this turn
    /// (standard rule: at most one per turn - a knight played before rolling
    /// counts against the same turn's limit, since `devCardPlayedThisTurn`
    /// only clears on `.endTurn`). Used both by the play functions and by
    /// `RulesEngine.legalMoves` to decide which `.play*` moves to enumerate.
    public static func canPlay(_ type: DevCardType, by player: PlayerID, in state: GameState) -> Bool {
        guard state.devCardPlayedThisTurn == nil else { return false }
        guard let p = state.players.first(where: { $0.id == player }) else { return false }
        let owned = p.devCards.filter { $0 == type }.count
        let boughtThisTurn = (state.devCardsBoughtThisTurn[player] ?? []).filter { $0 == type }.count
        return owned - boughtThisTurn > 0
    }

    /// Full, phase-aware play status for a card in a player's hand.
    ///
    /// `canPlay` remains the low-level ownership/turn-limit predicate used by
    /// the individual rule functions. This is the public UI/policy contract:
    /// it also owns timing and whether the card has any legal choices.
    public static func playStatus(
        _ type: DevCardType,
        by player: PlayerID,
        in state: GameState
    ) -> DevCardPlayStatus {
        guard let heldByPlayer = state.players.first(where: { $0.id == player }) else { return .notOwned }
        let held = heldByPlayer.devCards.filter { $0 == type }.count
        guard held > 0 else { return .notOwned }
        if type == .victoryPoint { return .passiveVictoryPoint }

        let bought = (state.devCardsBoughtThisTurn[player] ?? []).filter { $0 == type }.count
        guard held > bought else { return .boughtThisTurn }
        guard state.devCardPlayedThisTurn == nil else { return .alreadyPlayedThisTurn }

        switch state.phase {
        case .rollDice(let seat) where seat == player.index:
            break
        case .mainTurn(let seat) where seat == player.index:
            break
        case .gameOver:
            return .gameOver
        case .discarding(let pending) where pending.contains(player):
            return .resolveRequiredAction
        case .movingRobber(let seat) where seat == player.index,
             .setupForward(let seat) where seat == player.index,
             .setupBackward(let seat) where seat == player.index:
            return .resolveRequiredAction
        default:
            return .waitingForYourTurn
        }

        switch type {
        case .roadBuilding where legalRoadBuildingPairs(by: player, in: state).isEmpty:
            return .noLegalChoices
        case .yearOfPlenty where availableBankCardCount(in: state) < 2:
            return .noLegalChoices
        default:
            return .playable
        }
    }

    /// Ordered legal road pairs for Road Building. The second edge is tested
    /// against a probe containing the first; the real state is never changed.
    public static func legalRoadBuildingPairs(
        by player: PlayerID,
        in state: GameState
    ) -> [(first: EdgeID, second: EdgeID)] {
        guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else { return [] }
        let firstEdges = state.board.onBoardEdges
            .filter { Building.canBuildRoad($0, for: player, in: state) }
            .sorted()
        let allEdges = state.board.onBoardEdges.sorted()
        var probe = state
        var pairs: [(EdgeID, EdgeID)] = []
        for first in firstEdges {
            probe.players[playerIndex].roads.insert(first)
            for second in allEdges where second != first && Building.canBuildRoad(second, for: player, in: probe) {
                pairs.append((first, second))
            }
            probe.players[playerIndex].roads.remove(first)
        }
        return pairs
    }

    /// Whether the bank can supply this exact two-card Year of Plenty choice.
    public static func canTakeForYearOfPlenty(
        _ first: Resource,
        _ second: Resource,
        from state: GameState
    ) -> Bool {
        if first == second { return (state.bank[first] ?? 0) >= 2 }
        return (state.bank[first] ?? 0) >= 1 && (state.bank[second] ?? 0) >= 1
    }

    private static func availableBankCardCount(in state: GameState) -> Int {
        Resource.allCases.reduce(0) { $0 + max(state.bank[$1] ?? 0, 0) }
    }

    /// Removes one instance of `type` from `player`'s hand (played cards
    /// are set aside, not kept). Cards of a given type are fungible, so it
    /// doesn't matter which instance is removed.
    private static func consumeCard(_ type: DevCardType, from player: PlayerID, state: inout GameState) {
        guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else { return }
        if let index = state.players[playerIndex].devCards.firstIndex(of: type) {
            state.players[playerIndex].devCards.remove(at: index)
        }
    }

    /// Mirrors `LongestRoad.compute`: first player to reach the minimum
    /// (3 knights played) leads; a tie keeps the current holder; a tie with
    /// no current holder awards no one.
    private static func computeLargestArmy(for state: GameState) -> PlayerID? {
        let counts = state.players.map { ($0.id, $0.playedKnights) }
        guard let maxCount = counts.map(\.1).max(), maxCount >= 3 else { return nil }

        let leaders = counts.filter { $0.1 == maxCount }.map { $0.0 }
        if leaders.count == 1 { return leaders[0] }
        if let holder = state.largestArmyPlayer, leaders.contains(holder) { return holder }
        return nil
    }
}
