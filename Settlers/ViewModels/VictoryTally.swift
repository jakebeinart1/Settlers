import CatanEngine

/// The winner's score, broken into the beats the victory cutscene counts:
/// every settlement and city on the board, then each bonus. Built from the
/// same sources `GameState.victoryPoints(for:)` sums, and
/// `VictoryTallyTests` holds the two equal - a beat this misses would make
/// the counter stop short of the score the results screen then shows.
struct VictoryTally: Equatable {
    enum Source: Equatable {
        case settlement(VertexID)
        case city(VertexID)
        case longestRoad(Set<EdgeID>)
        case largestArmy
        case victoryCards(Int)
        case colonies
    }

    struct Beat: Equatable {
        let source: Source
        let points: Int
    }

    let winner: PlayerID
    let beats: [Beat]

    var total: Int { beats.reduce(0) { $0 + $1.points } }

    init?(state: GameState) {
        guard case .gameOver(let winner) = state.phase,
              let player = state.players.first(where: { $0.id == winner }) else { return nil }
        let rules = state.rules
        // Sorted: `Set` order is per process, and the camera tour should be
        // the same tour every time this game is shown.
        var beats = player.settlements.sorted().map {
            Beat(source: .settlement($0), points: rules.victoryPoints(for: .settlement))
        }
        beats += player.cities.sorted().map { Beat(source: .city($0), points: rules.victoryPoints(for: .city)) }
        if state.longestRoadPlayer == winner {
            beats.append(Beat(source: .longestRoad(player.roads), points: rules.longestRoadBonus))
        }
        if state.largestArmyPlayer == winner {
            beats.append(Beat(source: .largestArmy, points: rules.largestArmyBonus))
        }
        let cards = player.devCards.filter { $0 == .victoryPoint }.count
        if cards > 0 { beats.append(Beat(source: .victoryCards(cards), points: cards)) }
        if let colonies = state.naval?.colonyPoints[winner], colonies > 0 {
            beats.append(Beat(source: .colonies, points: colonies))
        }
        self.winner = winner
        self.beats = beats.filter { $0.points > 0 }
    }
}
