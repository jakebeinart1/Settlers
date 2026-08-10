import CatanEngine

/// Decides whether buying a dev card is a reasonable use of surplus
/// resources, and which dev card (if any) is worth playing right now.
public enum DevCardHeuristics {
    /// Same target list/order `TradeHeuristics` uses, so dev-card play
    /// reasons about "my current build plan" consistently with trading.
    private static func buildTargets(personality: BotPersonality) -> [[Resource: Int]] {
        let settlement = Building.settlementCost
        let city = Building.cityCost
        return personality.expansionBias >= 0.5
            ? [settlement, city, Building.roadCost]
            : [city, settlement, Building.roadCost]
    }

    private static func affordable(_ cost: [Resource: Int], holding: [Resource: Int]) -> Bool {
        cost.allSatisfy { resource, amount in (holding[resource] ?? 0) >= amount }
    }

    /// True whenever `player` can afford a dev card and the deck isn't
    /// empty - buying is close to always a reasonable use of spare
    /// ore/grain/wool, so this is a simple affordability gate; `Bot.decide`
    /// weighs *when* to actually spend the turn on it against other options.
    public static func shouldBuyDevCard(state: GameState, player: PlayerID) -> Bool {
        guard let me = state.players.first(where: { $0.id == player }) else { return false }
        guard !state.devCardDeck.isEmpty else { return false }
        return affordable(Building.devCardCost, holding: me.resources)
    }

    /// Picks the single best dev card play available right now, if any:
    /// - Knight: to shake the robber off one of our own tiles, or to claim
    ///   largest army (playing it would reach the 3-knight minimum and
    ///   nobody currently holds it, or we already lead).
    /// - Year of Plenty: when the two granted cards would fully cover the
    ///   remaining deficit on our nearest build target.
    /// - Monopoly: when opponents collectively hold a meaningful stash
    ///   (3+) of a resource we're short on for our nearest build target.
    ///
    /// Returns `nil` if no play is clearly worthwhile; callers must still
    /// match the result against `RulesEngine.legalMoves` before using it.
    /// `personality` decides target priority the same way `TradeHeuristics`
    /// does (settlement-first vs. city-first), so a `.cautious` bot's
    /// Year-of-Plenty/Monopoly reasoning actually reflects its own
    /// city-upgrade preference rather than always assuming `.balanced`.
    public static func choosePlay(state: GameState, player: PlayerID, personality: BotPersonality) -> GameMove? {
        guard let me = state.players.first(where: { $0.id == player }) else { return nil }

        if DevCards.canPlay(.knight, by: player, in: state) {
            let robberOnOwnTile = state.board.onBoardVertices.contains { vertex in
                vertex.touchingTiles.contains(state.board.robberTile)
                    && (me.settlements.contains(vertex) || me.cities.contains(vertex))
            }
            let claimsLargestArmy = me.playedKnights + 1 >= 3 && state.largestArmyPlayer != player
            if robberOnOwnTile || claimsLargestArmy {
                let (tile, victim) = RobberHeuristics.chooseRobberTarget(state: state, player: player)
                return .playKnight(moveRobberTo: tile, stealFrom: victim)
            }
        }

        let targets = buildTargets(personality: personality)
        // Individual missing resource units (a target needing 2 ore and
        // 1 grain contributes [.ore, .ore, .grain]) for whichever target has
        // the fewest, i.e. our nearest build.
        func missingUnits(_ cost: [Resource: Int]) -> [Resource] {
            cost.flatMap { resource, amount -> [Resource] in
                let deficit = max(0, amount - (me.resources[resource] ?? 0))
                return Array(repeating: resource, count: deficit)
            }
        }
        // Only targets we're actually still missing something for are
        // candidates - a target we can already afford outright isn't
        // "blocked" and shouldn't out-rank a genuinely blocked one just for
        // having a smaller (zero) deficit.
        let nearest = targets
            .filter { !missingUnits($0).isEmpty }
            .min { missingUnits($0).count < missingUnits($1).count }

        if DevCards.canPlay(.yearOfPlenty, by: player, in: state), let nearest {
            let missing = missingUnits(nearest)
            if (1...2).contains(missing.count) {
                let r1 = missing[0]
                let r2 = missing.count > 1 ? missing[1] : missing[0]
                return .playYearOfPlenty(r1, r2)
            }
        }

        if DevCards.canPlay(.monopoly, by: player, in: state), let nearest {
            let neededResources = Set(missingUnits(nearest))
            let bestTarget = neededResources.max { resource1, resource2 in
                opponentTotal(resource1, state: state, player: player) < opponentTotal(resource2, state: state, player: player)
            }
            if let bestTarget, opponentTotal(bestTarget, state: state, player: player) >= 3 {
                return .playMonopoly(bestTarget)
            }
        }

        return nil
    }

    private static func opponentTotal(_ resource: Resource, state: GameState, player: PlayerID) -> Int {
        state.players.filter { $0.id != player }.reduce(0) { $0 + ($1.resources[resource] ?? 0) }
    }
}
