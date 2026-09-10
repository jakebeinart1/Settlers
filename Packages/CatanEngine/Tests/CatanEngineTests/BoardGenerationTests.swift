import Testing
@testable import CatanEngine

@Test func standardBoardHas19TilesAndOneDesert() {
    let board = BoardGenerator.standard()
    #expect(board.tiles.count == 19)
    #expect(board.tiles.filter { $0.kind == .desert }.count == 1)
}

@Test func standardBoardHasNoAdjacentSixOrEight() {
    let board = BoardGenerator.standard()
    let hot = board.tiles.filter { $0.numberToken == 6 || $0.numberToken == 8 }
    for tile in hot {
        for dir in 0..<6 {
            let n = tile.coordinate.neighbor(dir)
            if let neighborTile = board.tiles.first(where: { $0.coordinate == n }) {
                #expect(!(neighborTile.numberToken == 6 || neighborTile.numberToken == 8))
            }
        }
    }
}

@Test func randomizedBoardIsDeterministicForSameSeed() {
    let b1 = BoardGenerator.randomized(seed: 42)
    let b2 = BoardGenerator.randomized(seed: 42)
    #expect(b1.tiles.map(\.coordinate) == b2.tiles.map(\.coordinate))
    #expect(b1.tiles.map(\.numberToken) == b2.tiles.map(\.numberToken))
}

@Test func boardHas9Ports() {
    #expect(BoardGenerator.standard().ports.count == 9)
}

@Test func vertexCanonicalizationIsConsistentAcrossSharedTiles() {
    let board = BoardGenerator.standard()
    // Every on-board edge's two vertices must each be in onBoardVertices.
    for edge in board.onBoardEdges {
        #expect(board.onBoardVertices.contains(edge.a))
        #expect(board.onBoardVertices.contains(edge.b))
    }
}

// MARK: BoardShape

@Test func classicShapeReproducesTheStandardBoardExactly() {
    // Deliberately does NOT compare against `BoardGenerator.standard()` -
    // Step 5 rewrote that to literally BE `standard(BoardShape.classic)`, so
    // that comparison would assert a value against itself. This compares
    // against the underlying source constants instead, which is what
    // actually proves the composition path deals the authentic board.
    let board = BoardGenerator.standard(BoardShape.classic)
    #expect(board.tiles.map(\.coordinate) == BoardGenerator.tileCoordinates)
    #expect(board.tiles.map(\.kind) == BoardGenerator.standardResourceOrder)
    let expectedNumbers = BoardGenerator.standardResourceOrder.map { $0 == .desert }
    var tokenIterator = BoardGenerator.standardNumberOrder.makeIterator()
    let expectedTokens = expectedNumbers.map { isDesert in isDesert ? nil : tokenIterator.next() }
    #expect(board.tiles.map(\.numberToken) == expectedTokens)
    #expect(board.ports == BoardGenerator.standardPorts)
    let expectedRobberTile = BoardGenerator.tileCoordinates[
        BoardGenerator.standardResourceOrder.firstIndex(of: .desert)!
    ]
    #expect(board.robberTile == expectedRobberTile)
}

@Test func tileCountFollowsTheHexFormulaAtEveryRadius() {
    // 3r^2 + 3r + 1
    #expect(BoardShape.tileCount(radius: 0) == 1)
    #expect(BoardShape.tileCount(radius: 2) == 19)
    #expect(BoardShape.tileCount(radius: 3) == 37)
    #expect(BoardShape.tileCount(radius: 12) == 469)
    #expect(BoardShape.tileCount(radius: 18) == 1_027)
}

@Test func aCompositionExpandsToExactlyTheDeclaredCounts() {
    let shape = BoardShape(
        radius: 3,
        terrain: .counts([.desert: 1, .resource(.grain): 12, .resource(.ore): 24]),
        tokens: .counts([6: 18, 8: 18]),
        ports: .derived(kinds: [.generic, .generic])
    )
    let board = BoardGenerator.standard(shape)
    #expect(board.tiles.count == 37)
    #expect(board.tiles.filter { $0.kind == .desert }.count == 1)
    #expect(board.tiles.filter { $0.kind == .resource(.grain) }.count == 12)
    #expect(board.tiles.filter { $0.kind == .resource(.ore) }.count == 24)
    #expect(board.tiles.compactMap(\.numberToken).count == 36)
}

@Test func aCompositionThatDoesNotFillTheBoardIsRejected() {
    // 10 tiles declared for a 37-tile radius. Trapping here beats dealing a
    // board with silent holes in it.
    #expect(BoardShape(radius: 3, terrain: .counts([.desert: 10]),
                       tokens: .counts([:]), ports: .derived(kinds: []))
        .compositionProblem != nil)
}

@Test func aCountedCompositionExpandsToOnePinnedInterleavedOrder() {
    // Pinned, not merely "some permutation": `counts` is a dictionary, and
    // Swift seeds dictionary iteration order per process, so an expansion that
    // let that order through would deal a different board every launch of the
    // same seed. Each test process gets a fresh hash seed, so this literal
    // fails such a regression rather than flaking on it.
    let terrain = TerrainComposition.counts(
        [.desert: 1, .resource(.brick): 2, .resource(.grain): 3]
    )
    #expect(terrain.expanded(tileCount: 6) == [
        .resource(.grain), .resource(.brick), .desert,
        .resource(.grain), .resource(.brick), .resource(.grain),
    ])
    #expect(TokenComposition.counts([6: 3, 8: 3]).expanded(count: 6) == [6, 8, 6, 8, 6, 8])
}

@Test func aTokenCountThatMissesTheProducingTilesIsRejected() {
    let shape = BoardShape(
        radius: 2,
        terrain: .counts([.desert: 1, .resource(.grain): 18]),
        tokens: .counts([6: 3]),
        ports: .derived(kinds: [])
    )
    #expect(shape.compositionProblem != nil)
}

@Test func aNegativeRadiusIsRejected() {
    // Without this guard, `tileCount` (3r^2 + 3r + 1) stays positive for a
    // negative radius while `spiralCoordinates` collapses to a 1-tile board,
    // and a `.counts` expansion sized to the mismatched `tileCount` would
    // zip silently down to whichever is shorter - the exact silent-holes
    // failure `compositionProblem` exists to catch.
    let shape = BoardShape(radius: -1, terrain: .counts([:]), tokens: .counts([:]),
                            ports: .derived(kinds: []))
    #expect(shape.compositionProblem != nil)
}

@Test func randomizedTerminatesForAFeasibleCountedShape() {
    // A sparse mix of 6s and 8s (2 of each on 36 producing tiles) is easy to
    // arrange without an adjacency - this proves the bounded shuffle loop
    // actually terminates on a real, non-trivial composition rather than
    // relying on the attempt cap. Verified against six seeds before pinning
    // this one. `aCompositionExpandsToExactlyTheDeclaredCounts` deliberately
    // packs the board solid with 6s and 8s and is never passed through
    // `randomized`, which is precisely what would exhaust the cap.
    let shape = BoardShape(
        radius: 3,
        terrain: .counts([
            .desert: 1, .resource(.grain): 12, .resource(.ore): 12, .resource(.wool): 12,
        ]),
        tokens: .counts([
            2: 4, 3: 4, 4: 4, 5: 4, 6: 2, 8: 2, 9: 4, 10: 4, 11: 4, 12: 4,
        ]),
        ports: .derived(kinds: [.generic, .generic])
    )
    let board = BoardGenerator.randomized(seed: 7, shape: shape)
    #expect(board.tiles.count == 37)
}

@Test func derivedPortsSitOnDistinctCoastalEdgesOfTheBoard() {
    let shape = BoardShape(
        radius: 2,
        terrain: .counts([.desert: 1, .resource(.grain): 18]),
        tokens: .counts([6: 18]),
        ports: .derived(kinds: [.generic, .resource(.ore), .generic, .resource(.wool)])
    )
    let board = BoardGenerator.standard(shape)
    #expect(board.ports.count == 4)
    #expect(board.ports.map(\.kind) == [.generic, .resource(.ore), .generic, .resource(.wool)])
    let edges = board.ports.map { EdgeID($0.vertexA, $0.vertexB) }
    #expect(Set(edges).count == 4)
    for edge in edges {
        #expect(board.onBoardEdges.contains(edge))
    }
}

@Test func expandedBoardHasThirtySevenTilesAndOneDesert() {
    let board = BoardGenerator.standard(BoardShape.expanded)
    #expect(board.tiles.count == 37)
    #expect(board.tiles.filter { $0.kind == .desert }.count == 1)
}

@Test func expandedTerrainIsExactlyTwiceClassic() {
    let board = BoardGenerator.standard(BoardShape.expanded)
    func count(_ resource: Resource) -> Int {
        board.tiles.filter { $0.kind == .resource(resource) }.count
    }
    #expect(count(.grain) == 8)
    #expect(count(.wool) == 8)
    #expect(count(.lumber) == 8)
    #expect(count(.brick) == 6)
    #expect(count(.ore) == 6)
}

@Test func expandedTokenMultisetIsExactlyTwiceClassic() {
    let board = BoardGenerator.standard(BoardShape.expanded)
    let expanded = board.tiles.compactMap(\.numberToken).sorted()
    let doubledClassic = (BoardGenerator.standardNumberOrder
                          + BoardGenerator.standardNumberOrder).sorted()
    #expect(expanded == doubledClassic)
    #expect(expanded.count == 36)
}

@Test func expandedHasFourteenPortsOnDistinctCoastalEdges() {
    let board = BoardGenerator.standard(BoardShape.expanded)
    #expect(board.ports.count == 14)
    #expect(Set(board.ports.map { EdgeID($0.vertexA, $0.vertexB) }).count == 14)
    for port in board.ports {
        #expect(board.onBoardVertices.contains(port.vertexA))
        #expect(board.onBoardVertices.contains(port.vertexB))
    }
    #expect(board.ports.filter { $0.kind == .generic }.count == 4)
    for resource in Resource.allCases {
        #expect(board.ports.filter { $0.kind == .resource(resource) }.count == 2)
    }
}

@Test func expandedRandomizedBoardNeverAdjoinsSixAndEight() {
    for seed in UInt64(1)...50 {
        let board = BoardGenerator.randomized(seed: seed, shape: .expanded)
        let tokens = Dictionary(uniqueKeysWithValues: board.tiles.map { ($0.coordinate, $0.numberToken) })
        for tile in board.tiles where tile.numberToken == 6 || tile.numberToken == 8 {
            for direction in 0..<6 {
                if let neighbor = tokens[tile.coordinate.neighbor(direction)] ?? nil {
                    #expect(!(neighbor == 6 || neighbor == 8), "seed \(seed)")
                }
            }
        }
    }
}

@Test func expandedRandomizedBoardIsReproducibleFromItsSeed() {
    let first = BoardGenerator.randomized(seed: 99, shape: .expanded)
    let second = BoardGenerator.randomized(seed: 99, shape: .expanded)
    #expect(first.tiles == second.tiles)
    #expect(first.ports == second.ports)
}

@Test func aShapeNoShuffleCanSatisfyIsRepairedRatherThanRefused() {
    // Every token hot. No shuffle can ever satisfy the no-adjacent-6/8 rule,
    // so Task 3's bound would exhaust and crash. The repair must deal a board
    // instead - and the rule is unsatisfiable here, so what it must NOT do is
    // loop, crash, or silently drop tokens.
    let shape = BoardShape(
        radius: 2,
        terrain: .counts([.desert: 1, .resource(.grain): 9, .resource(.ore): 9]),
        tokens: .counts([6: 9, 8: 9]),
        ports: .derived(kinds: [.generic])
    )
    let board = BoardGenerator.randomized(seed: 7, shape: shape)
    #expect(board.tiles.count == 19)
    #expect(board.tiles.compactMap(\.numberToken).count == 18)
    // Reproducible despite going through the repair path.
    #expect(BoardGenerator.randomized(seed: 7, shape: shape).tiles == board.tiles)
}
