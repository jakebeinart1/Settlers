/// Development card rules: buying, playing each of the four playable
/// types (knight, road building, year of plenty, monopoly - victory point
/// cards are never "played", they just add to `Player.victoryPoints`), and
/// largest-army tracking.
public enum DevCards {
    /// Deducts `Building.devCardCost` (1 ore, 1 grain, 1 wool), draws the
    /// top card of `state.devCardDeck` into `player`'s hand, and records it
    /// as bought this turn (unplayable until next turn).
    public static func buy(by player: PlayerID, state: inout GameState) throws {
        guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else {
            throw MoveError.other("unknown player")
        }
        guard !state.devCardDeck.isEmpty else { throw MoveError.other("dev card deck is empty") }
        try RulesEngine.deduct(Building.devCardCost, from: &state, playerIndex: playerIndex)

        let card = state.devCardDeck.removeFirst()
        state.players[playerIndex].devCards.append(card)
        state.devCardsBoughtThisTurn[player, default: []].append(card)
    }

    /// Moves the robber and steals exactly like `Robber.apply`, then
    /// consumes the played knight and increments `player.playedKnights`,
    /// recomputing `largestArmyPlayer` (first to 3 knights; ties keep the
    /// current holder, matching longest-road tie handling).
    public static func playKnight(
        moveRobberTo: HexCoordinate,
        stealFrom: PlayerID?,
        by player: PlayerID,
        state: inout GameState
    ) throws {
        guard canPlay(.knight, by: player, in: state) else { throw MoveError.illegalPlacement }
        try Robber.apply(move: moveRobberTo, stealFrom: stealFrom, by: player, to: &state)
        consumeCard(.knight, from: player, state: &state)

        guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else {
            throw MoveError.other("unknown player")
        }
        state.players[playerIndex].playedKnights += 1
        state.largestArmyPlayer = computeLargestArmy(for: state)
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
        state.longestRoadPlayer = LongestRoad.compute(for: state)
    }

    /// Grants one card each of `r1` and `r2` from the bank, capped by
    /// whatever the bank actually has available (no throw on shortage).
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
        for resource in [r1, r2] where (state.bank[resource] ?? 0) > 0 {
            state.bank[resource, default: 0] -= 1
            state.players[playerIndex].resources[resource, default: 0] += 1
        }
        consumeCard(.yearOfPlenty, from: player, state: &state)
    }

    /// Every other player hands over all of their `resource` cards to
    /// `player`.
    public static func playMonopoly(_ resource: Resource, by player: PlayerID, state: inout GameState) throws {
        guard canPlay(.monopoly, by: player, in: state) else { throw MoveError.illegalPlacement }
        guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else {
            throw MoveError.other("unknown player")
        }
        for index in state.players.indices where state.players[index].id != player {
            let amount = state.players[index].resources[resource] ?? 0
            guard amount > 0 else { continue }
            state.players[index].resources[resource, default: 0] -= amount
            state.players[playerIndex].resources[resource, default: 0] += amount
        }
        consumeCard(.monopoly, from: player, state: &state)
    }

    /// Whether `player` holds a card of `type` that wasn't bought this
    /// turn. Used both by the play functions and by `RulesEngine.legalMoves`
    /// to decide which `.play*` moves to enumerate.
    public static func canPlay(_ type: DevCardType, by player: PlayerID, in state: GameState) -> Bool {
        guard let p = state.players.first(where: { $0.id == player }) else { return false }
        let owned = p.devCards.filter { $0 == type }.count
        let boughtThisTurn = (state.devCardsBoughtThisTurn[player] ?? []).filter { $0 == type }.count
        return owned - boughtThisTurn > 0
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
