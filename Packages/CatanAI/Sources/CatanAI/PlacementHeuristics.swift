import CatanEngine

/// Scores candidate settlement vertices for setup and later expansion.
public enum PlacementHeuristics {
    /// Pip count (number of ways to roll each number token) - the standard
    /// Catan production-value weighting.
    private static let pipsByNumber: [Int: Double] = [
        6: 5, 8: 5,
        5: 4, 9: 4,
        4: 3, 10: 3,
        3: 2, 11: 2,
        2: 1, 12: 1,
    ]

    /// Pip-count-weighted production value of `vertex`, summed across its
    /// up-to-3 adjacent tiles, plus a resource-diversity bonus (rewards
    /// touching more distinct resource types) and a port-access bonus
    /// (rewards sitting on a trading port, more so a resource-specific one).
    public static func score(vertex: VertexID, board: Board) -> Double {
        let coordinates = board.neighborTiles(of: vertex)
        let tiles = coordinates.compactMap { coordinate in
            board.tiles.first { $0.coordinate == coordinate }
        }

        var production = 0.0
        var resources = Set<Resource>()
        for tile in tiles {
            guard let number = tile.numberToken else { continue }
            production += pipsByNumber[number] ?? 0
            if case .resource(let resource) = tile.kind {
                resources.insert(resource)
            }
        }

        let diversityBonus = Double(resources.count) * 0.5

        let portBonus: Double
        if let port = board.ports.first(where: { $0.vertexA == vertex || $0.vertexB == vertex }) {
            switch port.kind {
            case .generic: portBonus = 0.5
            case .resource: portBonus = 1.0
            }
        } else {
            portBonus = 0
        }

        return production + diversityBonus + portBonus
    }
}
