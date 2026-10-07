import Foundation

enum NavalPorts {
    static func make(in board: Board, islandByHex: [HexCoordinate: Int], rng: inout RandomSource) -> [Port] {
        var used = Set<VertexID>()
        var ports: [Port] = []
        let homeKinds: [PortKind] = [.generic, .generic, .resource(.grain), .resource(.wool)]
        let overseasKinds: [PortKind] = [.generic, .generic, .resource(.lumber), .resource(.brick), .resource(.ore)]
        let home = coastEdges(in: board, islandByHex: islandByHex, island: 0).shuffled(using: &rng)
        for kind in homeKinds { append(kind, candidates: home, used: &used, ports: &ports) }
        let counts: [(island: Int, count: Int)] = (1...4).map { island in
            (island: island, count: islandByHex.values.filter { $0 == island }.count)
        }
        let sizes = counts.sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs.island < rhs.island : lhs.count > rhs.count
        }
        for (index, kind) in overseasKinds.enumerated() {
            let island = sizes[index % sizes.count].island
            let candidates = coastEdges(in: board, islandByHex: islandByHex, island: island).shuffled(using: &rng)
            append(kind, candidates: candidates, used: &used, ports: &ports)
        }
        return ports
    }

    static func coastEdges(in board: Board, islandByHex: [HexCoordinate: Int], island: Int) -> [EdgeID] {
        let kinds = Dictionary(uniqueKeysWithValues: board.tiles.map { ($0.coordinate, $0.kind) })
        return board.onBoardEdges.filter { edge in
            let touching = Set(edge.a.touchingTiles).intersection(edge.b.touchingTiles)
            return touching.contains { islandByHex[$0] == island }
                && touching.contains { kinds[$0] == .sea }
        }.sorted()
    }

    private static func append(_ kind: PortKind, candidates: [EdgeID],
                               used: inout Set<VertexID>, ports: inout [Port]) {
        guard let edge = candidates.first(where: { !used.contains($0.a) && !used.contains($0.b) }) else { return }
        ports.append(Port(vertexA: edge.a, vertexB: edge.b, kind: kind))
        used.formUnion([edge.a, edge.b])
    }
}
