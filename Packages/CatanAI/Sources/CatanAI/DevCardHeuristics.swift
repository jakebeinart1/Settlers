import CatanEngine

/// Decides whether buying a dev card is a reasonable use of surplus
/// resources, and which dev card (if any) is worth playing right now.
public enum DevCardHeuristics {
    /// Same target list/order `TradeHeuristics` uses, so dev-card play
    /// reasons about "my current build plan" consistently with trading.
    private static func buildTargets(personality: BotPersonality, weights: BotWeights) -> [[Resource: Int]] {
        let settlement = Building.settlementCost
        let city = Building.cityCost
        return personality.expansionBias >= weights.cityFirstExpansionBiasPivot
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
    ///   largest army (playing it would reach `largestArmyKnightThreshold`
    ///   and nobody currently holds it, or we already lead).
    /// - Year of Plenty: when the two granted cards would fully cover the
    ///   remaining deficit on our nearest build target.
    /// - Monopoly: when opponents collectively hold at least
    ///   `monopolyMinimumStash` (threat-weighted) of a resource we're short
    ///   on for our nearest build target.
    ///
    /// Returns `nil` if no play is clearly worthwhile; callers must still
    /// match the result against `RulesEngine.legalMoves` before using it.
    /// `personality` decides target priority the same way `TradeHeuristics`
    /// does (settlement-first vs. city-first), so a `.cautious` bot's
    /// Year-of-Plenty/Monopoly reasoning actually reflects its own
    /// city-upgrade preference rather than always assuming `.balanced`.
    public static func choosePlay(
        state: GameState,
        player: PlayerID,
        personality: BotPersonality,
        weights: BotWeights = .default
    ) -> GameMove? {
        guard let me = state.players.first(where: { $0.id == player }) else { return nil }

        if DevCards.canPlay(.knight, by: player, in: state) {
            let robberOnOwnTile = state.board.onBoardVertices.contains { vertex in
                vertex.touchingTiles.contains(state.board.robberTile)
                    && (me.settlements.contains(vertex) || me.cities.contains(vertex))
            }
            let claimsLargestArmy = me.playedKnights + 1 >= weights.largestArmyKnightThreshold
                && state.largestArmyPlayer != player
            let pursuing = pursuingLargestArmy(state: state, player: player, me: me, weights: weights)
            if robberOnOwnTile || claimsLargestArmy || pursuing {
                let (tile, victim) = RobberHeuristics.chooseRobberTarget(
                    state: state, player: player, personality: personality, weights: weights
                )
                return .playKnight(moveRobberTo: tile, stealFrom: victim)
            }
        }

        let targets = buildTargets(personality: personality, weights: weights)
        // Individual missing resource units (a target needing 2 ore and
        // 1 grain contributes [.ore, .ore, .grain]) for whichever target has
        // the fewest, i.e. our nearest build.
        // Driven off `Resource.allCases`, not the cost dictionary. The caller
        // takes `missing[0]` and `missing[1]` for Year of Plenty's two cards,
        // and a dictionary yields its pairs in a per-process order - so the
        // same position asked for the same two resources in a different order
        // on a different launch. Both orderings are legal and grant the same
        // cards, so this never changed the game, but it did make the recorded
        // move sequence differ run to run.
        func missingUnits(_ cost: [Resource: Int]) -> [Resource] {
            Resource.allCases.flatMap { resource -> [Resource] in
                let deficit = max(0, (cost[resource] ?? 0) - (me.resources[resource] ?? 0))
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
            // Walked in `Resource.allCases` order rather than as a `Set`:
            // `max(by:)` keeps the first of equal elements, so a tie between
            // two equally-stocked resources was decided by Swift's
            // per-process hash seed.
            let needed = Set(missingUnits(nearest))
            let neededResources = Resource.allCases.filter { needed.contains($0) }
            let bestTarget = neededResources.max { resource1, resource2 in
                opponentTotal(resource1, state: state, player: player, weights: weights)
                    < opponentTotal(resource2, state: state, player: player, weights: weights)
            }
            if let bestTarget,
               opponentTotal(bestTarget, state: state, player: player, weights: weights) >= weights.monopolyMinimumStash {
                return .playMonopoly(bestTarget)
            }
        }

        return nil
    }

    /// Whether `player` should spend this turn's one dev-card play on a
    /// knight purely to build toward Largest Army - not because the robber
    /// happens to sit on our own tile, and not because this exact play
    /// would already claim it (`claimsLargestArmy` in `choosePlay` covers
    /// that). Largest Army is a bonus you have to hold *at game end*, not a
    /// one-off event, so a bot sitting on unplayed knights with a real shot
    /// needs to actually spend them down over several turns rather than
    /// only ever playing one reactively when robbed onto its own tile -
    /// otherwise it can stockpile knights all game and never seriously
    /// contest the bonus.
    ///
    /// "A real shot" means our maximum reachable knight count (already
    /// played, plus every knight currently in hand - including ones bought
    /// this turn that aren't playable yet, since they will be by the time
    /// we'd need them) could plausibly reach or pass whoever's ahead of us
    /// in the race: the current holder if there is one, otherwise the
    /// furthest-along opponent. Once the deck is nearly out, there's no more
    /// runway to grow that ceiling further, so any real contender should
    /// stop sitting on knights and start spending them - last call before
    /// the game can't hand out any more of them.
    private static func pursuingLargestArmy(
        state: GameState,
        player: PlayerID,
        me: Player,
        weights: BotWeights
    ) -> Bool {
        guard state.largestArmyPlayer != player else { return false } // already holding it - nothing to pursue
        let myCeiling = me.playedKnights + me.devCards.filter { $0 == .knight }.count
        // Not a real contender either way.
        guard myCeiling >= weights.largestArmyKnightThreshold else { return false }

        let aheadOfUs = state.largestArmyPlayer
            .flatMap { holder in state.players.first(where: { $0.id == holder })?.playedKnights }
            ?? (state.players.filter { $0.id != player }.map(\.playedKnights).max() ?? 0)

        let deckNearlyOut = state.devCardDeck.count <= weights.devDeckNearlyOutCount
        return myCeiling > aheadOfUs || deckNearlyOut
    }

    /// Total holdings of `resource` across every opponent, weighted by how
    /// threatening each holder is relative to the average opponent (see
    /// `ThreatAssessment`) - so Monopoly is picked to hurt whoever's most
    /// dangerous, not just whoever happens to be sitting on the biggest
    /// raw pile.
    private static func opponentTotal(
        _ resource: Resource,
        state: GameState,
        player: PlayerID,
        weights: BotWeights
    ) -> Double {
        state.players.filter { $0.id != player }.reduce(0.0) { partial, opponent in
            let threat = ThreatAssessment.relativeWeight(for: opponent.id, excluding: player, in: state, weights: weights)
            return partial + Double(opponent.resources[resource] ?? 0) * threat
        }
    }
}
