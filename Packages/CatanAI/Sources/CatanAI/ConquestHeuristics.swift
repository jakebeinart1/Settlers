import CatanEngine

/// When a bot buys Conquest army cards.
public enum ArmyBuying: Sendable {
    /// Only when no build is worth making (the shipped behaviour).
    case idle
    /// Ahead of building, whenever affordable and some hex is not yet ours.
    case bold
    /// Ahead of building, but only when one more card at mean strength would
    /// let the playable hand take a 5, 6, 8 or 9 it touches.
    case targeted
}

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
              Conquest.payment(for: owner.resources, price: state.armyPrice) != nil else { return false }
        return state.board.tiles.map(\.coordinate).sorted().contains {
            Conquest.canDeploy(to: $0, by: player, in: state) && state.garrisons[$0]?.owner != player
        }
    }

    static func shouldBuyAheadOfBuilding(_ buying: ArmyBuying, state: GameState, player: PlayerID) -> Bool {
        guard buying != .idle, shouldBuyArmyCard(state: state, player: player) else { return false }
        guard buying == .targeted else { return true }
        let reach = Double(Conquest.playableCards(for: player, in: state).reduce(0, +)) + expectedCardStrength
        return state.board.tiles.sorted(by: { $0.coordinate < $1.coordinate }).contains { tile in
            guard let token = tile.numberToken, DiceOdds.pips(for: token) >= goodHexPips,
                  Conquest.canDeploy(to: tile.coordinate, by: player, in: state),
                  state.garrisons[tile.coordinate]?.owner != player else { return false }
            return reach > Double(state.garrisons[tile.coordinate]?.strength ?? 0)
        }
    }

    /// 5, 6, 8 and 9: the hexes worth an army card.
    static let goodHexPips = 4

    /// A rival building silenced on the public leader's side counts this many
    /// times over: cutting off whoever is winning is what the takeover is for.
    static let leaderDenialWeight = 2.0

    /// Pips x (the +1 bonus, plus every rival building the takeover silences,
    /// the leader's weighted by `leaderDenialWeight`).
    static func hexValue(_ hex: HexCoordinate, for player: PlayerID, in state: GameState) -> Double {
        guard let token = state.board.tiles.first(where: { $0.coordinate == hex })?.numberToken else { return 0 }
        let corners = state.board.corners(of: hex)
        let leader = publicLeader(in: state)
        let silenced = state.players.filter { $0.id != player }.reduce(0.0) { total, rival in
            let buildings = corners.reduce(0) { $0 + (rival.cities.contains($1) ? 2 : rival.settlements.contains($1) ? 1 : 0) }
            return total + Double(buildings) * (rival.id == leader ? leaderDenialWeight : 1)
        }
        return Double(DiceOdds.pips(for: token)) * (1 + silenced)
    }

    /// The seat strictly ahead on public points, or nil on a tie.
    private static func publicLeader(in state: GameState) -> PlayerID? {
        let points = state.players.map { ($0.id, state.publicVictoryPoints(for: $0.id)) }
        guard let top = points.map(\.1).max(), points.filter({ $0.1 == top }).count == 1 else { return nil }
        return points.first { $0.1 == top }?.0
    }

    /// A rival touching `hex` whose visible hand, at expected strength, breaks it.
    private static func isThreatened(_ hex: HexCoordinate, garrison: Int, state: GameState, player: PlayerID) -> Bool {
        state.players.contains { rival in
            rival.id != player && Conquest.canDeploy(to: hex, by: rival.id, in: state)
                && Double(state.armyHands[rival.id, default: []].count) * expectedCardStrength >= Double(garrison)
        }
    }
}
