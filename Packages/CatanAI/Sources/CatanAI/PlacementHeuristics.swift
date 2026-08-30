import CatanEngine

/// Scores candidate settlement vertices for setup and later expansion.
public enum PlacementHeuristics {
    /// Pip-count-weighted production value of `vertex`, summed across its
    /// up-to-3 adjacent tiles, plus a resource-diversity bonus (rewards
    /// touching more distinct resource types), a port-access bonus (rewards
    /// sitting on a trading port, more so a resource-specific one), and - if
    /// `alreadyCovered` is non-empty - a further bonus per pip on a resource
    /// not already in that set. Passing the player's first settlement's
    /// resources as `alreadyCovered` when scoring their second (setup's
    /// snake-draft second placement) pushes the bot toward covering new
    /// resource types instead of just re-maximizing raw pips on ones it's
    /// already got - a real placement priority `alreadyCovered: []`'s
    /// default (used for the first placement, and any other single-vertex
    /// scoring elsewhere) doesn't capture at all.
    public static func score(
        vertex: VertexID,
        board: Board,
        alreadyCovered: Set<Resource> = [],
        weights: BotWeights = .default
    ) -> Double {
        let coordinates = board.neighborTiles(of: vertex)
        let tiles = coordinates.compactMap { coordinate in
            board.tiles.first { $0.coordinate == coordinate }
        }

        var production = 0.0
        var resources = Set<Resource>()
        var newResourceBonus = 0.0
        for tile in tiles {
            guard let number = tile.numberToken else { continue }
            let pips = Double(DiceOdds.pips(for: number))
            production += pips
            if case .resource(let resource) = tile.kind {
                resources.insert(resource)
                if !alreadyCovered.isEmpty, !alreadyCovered.contains(resource) {
                    newResourceBonus += pips * weights.newResourcePipBonus
                }
            }
        }

        let diversityBonus = Double(resources.count) * weights.resourceDiversityBonus

        let portBonus: Double
        if let port = board.ports.first(where: { $0.vertexA == vertex || $0.vertexB == vertex }) {
            switch port.kind {
            case .generic: portBonus = weights.genericPortBonus
            case .resource: portBonus = weights.resourcePortBonus
            }
        } else {
            portBonus = 0
        }

        return production + diversityBonus + portBonus + newResourceBonus
    }
}
