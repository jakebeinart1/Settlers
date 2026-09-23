import CatanEngine

/// Conquest decisions for `Bot`. Heuristic, untrained: this exists to make the
/// variant playable and measurable, not to be strong.
enum ConquestHeuristics {
    /// Mean strength of the Classic deck, used as a rival card's expected value.
    /// ponytail: ignores cards already seen; count spent cards via `PublicLedger` if bots over-reinforce.
    static let expectedCardStrength = 4.0

    /// The best legal deploy that takes a hex, else a reinforcement of a held hex
    /// a rival could plausibly break next turn, else nil. Never a losing attack.
    static func chooseDeploy(state: GameState, player: PlayerID, legal: [GameMove]) -> GameMove? {
        var best: (move: GameMove, score: Double)?
        for move in legal {
            guard case .deployArmy(let hex, let strengths) = move else { continue }
            let total = strengths.reduce(0, +)
            let current = state.garrisons[hex]
            let score: Double
            if current?.owner == player {
                guard isThreatened(hex, garrison: current!.strength, state: state, player: player),
                      strengths.count == 1 else { continue }
                score = hexValue(hex, for: player, in: state) * 0.5 / Double(total)
            } else {
                guard Conquest.outcome(of: total, against: current, by: player)?.owner == player else { continue }
                score = hexValue(hex, for: player, in: state) / Double(total)
            }
            if best == nil || score > best!.score { best = (move, score) }
        }
        return best?.move
    }

    /// Buy only in Conquest, only when affordable, and only if some reachable
    /// hex is still not ours - otherwise the card has nothing to do.
    static func shouldBuyArmyCard(state: GameState, player: PlayerID) -> Bool {
        guard state.variant == .conquest, !state.armyDeck.isEmpty,
              let owner = state.players.first(where: { $0.id == player }),
              RulesEngine.canAfford(Conquest.armyCardCost, player: owner) else { return false }
        return state.board.tiles.map(\.coordinate).sorted().contains {
            Conquest.canDeploy(to: $0, by: player, in: state) && state.garrisons[$0]?.owner != player
        }
    }

    /// Pips x (the +1 bonus, plus every rival building the takeover silences).
    private static func hexValue(_ hex: HexCoordinate, for player: PlayerID, in state: GameState) -> Double {
        guard let token = state.board.tiles.first(where: { $0.coordinate == hex })?.numberToken else { return 0 }
        let corners = HexGeometry.corners(of: hex)
        let silenced = state.players.filter { $0.id != player }.reduce(0) { total, rival in
            total + corners.reduce(0) { $0 + (rival.cities.contains($1) ? 2 : rival.settlements.contains($1) ? 1 : 0) }
        }
        return Double(DiceOdds.pips(for: token)) * Double(1 + silenced)
    }

    /// A rival touching `hex` whose visible hand, at expected strength, breaks it.
    private static func isThreatened(_ hex: HexCoordinate, garrison: Int, state: GameState, player: PlayerID) -> Bool {
        state.players.contains { rival in
            rival.id != player && Conquest.canDeploy(to: hex, by: rival.id, in: state)
                && Double(state.armyHands[rival.id, default: []].count) * expectedCardStrength >= Double(garrison)
        }
    }
}
