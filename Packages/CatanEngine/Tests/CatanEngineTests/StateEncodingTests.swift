import Testing
import Foundation
@testable import CatanEngine

// Guards the four properties that make `StateEncoding` usable by something
// that learns: a fixed width, a bounded range, an egocentric frame, and a
// stable board ordering.
//
// Every one of them fails silently if broken. A vector of the wrong width
// throws nothing when it is padded or truncated into a model; a feature
// outside `0...1` merely skews a gradient; a non-egocentric frame trains
// fine and plays badly from three seats out of four; and a board order that
// depends on `Set` iteration is correct for the whole of the process that
// wrote it and wrong for every process that reads it back. None of these
// surfaces as an error - they surface as "the bots got worse", which is the
// single most expensive symptom in this repo to chase.

// MARK: - Position fixtures

/// Plays `moves` uniformly-at-random moves from a seeded start and returns the
/// position reached, so the suite covers real mid-game states rather than a
/// hand-built one that happens to avoid every interesting branch.
///
/// Uses `RandomSource` for selection rather than `randomElement()` so the
/// fixture itself is reproducible - a failure here has to be re-runnable, and
/// a driver seeded from the system RNG produces a different position on every
/// launch.
private func position(boardSeed: UInt64, driverSeed: UInt64, moves: Int) -> GameState {
    var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: boardSeed), seed: boardSeed)
    var driver = RandomSource(seed: driverSeed)

    for _ in 0..<moves {
        if case .gameOver = state.phase { break }
        guard let actor = actingPlayer(state) else { break }
        let legal = RulesEngine.legalMoves(for: state, seat: actor)
        guard let move = legal.randomElement(using: &driver) else { break }
        do { try RulesEngine.apply(move, by: actor, to: &state) } catch { break }
    }
    return state
}

/// The observation `seat` would be handed in `state`.
private func observe(_ state: GameState, as seat: PlayerID) -> GameObservation {
    GameObservation(seat: seat, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: seat))
}

/// A spread of positions covering the opening, the setup-to-play transition,
/// mid-game and late-game, over several boards.
private func sampledPositions() -> [GameState] {
    var states: [GameState] = []
    for seed: UInt64 in [1, 42, 1234] {
        for moves in [0, 4, 8, 16, 60, 150, 400, 900] {
            states.append(position(boardSeed: seed, driverSeed: seed &* 31, moves: moves))
        }
    }
    return states
}

// MARK: - Width

@Test func everyVectorIsExactlyTheAdvertisedWidth() {
    for state in sampledPositions() {
        for index in 0..<StateEncoding.seatCount {
            let vector = StateEncoding.features(observe(state, as: PlayerID(index: index)))
            #expect(vector.count == StateEncoding.featureCount,
                    "phase \(StateEncoding.phaseLabel(state.phase)) seat \(index): got \(vector.count)")
        }
    }
}

@Test func theAdvertisedWidthIsTheSumOfItsBlocks() {
    // Guards the constant against being edited without its decomposition, which
    // is what a consumer reads to find a block offset.
    let expected = StateEncoding.globalFeatureCount
        + StateEncoding.seatCount * StateEncoding.perPlayerFeatureCount
        + StateEncoding.tileCount * StateEncoding.perTileFeatureCount
        + StateEncoding.vertexCount * StateEncoding.perVertexFeatureCount
        + StateEncoding.edgeCount * StateEncoding.perEdgeFeatureCount
    #expect(StateEncoding.featureCount == expected)
    #expect(StateEncoding.featureCount == 1012, "featureCount changed - did layoutVersion?")
}

@Test func hidingOpponentHandsDoesNotChangeTheWidth() {
    // The whole point of concealing by zeroing rather than by omitting: a model
    // trained under one policy can be evaluated under the other without a
    // width mismatch that nothing would report.
    let state = position(boardSeed: 42, driverSeed: 7, moves: 150)
    let observation = observe(state, as: PlayerID(index: 0))
    let revealed = StateEncoding.features(observation, policy: .revealAll)
    let concealed = StateEncoding.features(observation, policy: .publicCountsOnly)
    #expect(revealed.count == concealed.count)
    #expect(concealed.count == StateEncoding.featureCount)
}

// MARK: - Range

@Test func everyFeatureIsFiniteAndWithinItsDocumentedRange() {
    for state in sampledPositions() {
        for index in 0..<StateEncoding.seatCount {
            let vector = StateEncoding.features(observe(state, as: PlayerID(index: index)))
            let bad = vector.firstIndex { !$0.isFinite || $0 < 0 || $0 > 1 }
            let phase = StateEncoding.phaseLabel(state.phase)
            let detail = "slot \(bad ?? -1) = \(bad.map { vector[$0] } ?? 0) escapes 0...1 in phase \(phase)"
            #expect(bad == nil, "\(detail)")
        }
    }
}

@Test func theOneHotBlocksHaveExactlyOneSetSlot() {
    // A one-hot with two bits set, or none, is the shape of an off-by-one in a
    // block offset - and unlike a width change it survives the width check.
    for state in sampledPositions() {
        let vector = StateEncoding.features(observe(state, as: PlayerID(index: 0)))
        let phaseBlock = vector[0..<StateEncoding.phaseCount]
        #expect(phaseBlock.reduce(0, +) == 1, "phase one-hot is not one-hot")

        let robberStart = StateEncoding.globalFeatureCount - StateEncoding.tileCount
        let robberBlock = vector[robberStart..<StateEncoding.globalFeatureCount]
        #expect(robberBlock.reduce(0, +) == 1, "robber one-hot is not one-hot")
    }
}

// MARK: - Egocentricity

@Test func theOwnBlockAlwaysDescribesTheObservingSeat() {
    // The property most easily got wrong, and the reason the layout is
    // egocentric at all: if slot 35 meant "seat 0's brick" a learner would have
    // to relearn its own hand at four different offsets.
    let state = position(boardSeed: 42, driverSeed: 11, moves: 150)
    let start = StateEncoding.globalFeatureCount

    for index in 0..<StateEncoding.seatCount {
        let seat = PlayerID(index: index)
        let vector = StateEncoding.features(observe(state, as: seat))
        let own = Array(vector[start..<(start + StateEncoding.perPlayerFeatureCount)])
        let player = state.players[index]

        for (offset, resource) in Resource.allCases.enumerated() {
            let expected = Float(player.resources[resource] ?? 0) / Float(StateEncoding.resourceCardsPerKind)
            #expect(abs(own[offset] - Swift.min(1, expected)) < 1e-6,
                    "seat \(index): own block holds someone else's \(resource.rawValue)")
        }
    }
}

@Test func opponentBlocksFollowSeatOrderRelativeToTheObserver() {
    let state = position(boardSeed: 42, driverSeed: 11, moves: 150)
    let start = StateEncoding.globalFeatureCount
    let width = StateEncoding.perPlayerFeatureCount
    // Public VP sits after the 14 holdings slots and the trades-this-turn slot.
    let publicVPOffset = 15

    for index in 0..<StateEncoding.seatCount {
        let seat = PlayerID(index: index)
        let vector = StateEncoding.features(observe(state, as: seat))
        for slot in 0..<StateEncoding.seatCount {
            let described = StateEncoding.seatOrder(from: seat)[slot]
            let expected = Float(state.publicVictoryPoints(for: described)) / Float(StateEncoding.victoryPointTarget)
            let actual = vector[start + slot * width + publicVPOffset]
            #expect(abs(actual - expected) < 1e-6,
                    "seat \(index) slot \(slot): expected P\(described.index)'s VP")
        }
    }
}

@Test func rotatingTheObserverRotatesTheSeatBlocks() {
    // Seat 1's vector, read from slot 1 onward, must match seat 0's vector read
    // from slot 0 onward for the seats they describe in common - which is what
    // "egocentric" means operationally.
    let state = position(boardSeed: 7, driverSeed: 3, moves: 150)
    let start = StateEncoding.globalFeatureCount
    let width = StateEncoding.perPlayerFeatureCount

    let fromSeat0 = StateEncoding.features(observe(state, as: PlayerID(index: 0)))
    let fromSeat1 = StateEncoding.features(observe(state, as: PlayerID(index: 1)))

    func block(_ vector: [Float], _ slot: Int) -> ArraySlice<Float> {
        vector[(start + slot * width)..<(start + (slot + 1) * width)]
    }
    // Seat 2 is slot 2 for observer 0 and slot 1 for observer 1.
    #expect(Array(block(fromSeat0, 2)) == Array(block(fromSeat1, 1)),
            "P2's block differs depending on who is looking at it")
    #expect(Array(block(fromSeat0, 3)) == Array(block(fromSeat1, 2)),
            "P3's block differs depending on who is looking at it")
}

@Test func vertexOwnershipIsEgocentricToo() {
    // The board blocks are the easy half to leave in absolute seat order, which
    // would leave a learner reading "my settlement" out of a different slot per
    // seat while the per-seat blocks looked correct.
    let state = position(boardSeed: 42, driverSeed: 11, moves: 150)
    let index = StateEncoding.BoardIndex(state.board)
    let vertexStart = StateEncoding.globalFeatureCount
        + StateEncoding.seatCount * StateEncoding.perPlayerFeatureCount
        + StateEncoding.tileCount * StateEncoding.perTileFeatureCount

    for seatIndex in 0..<StateEncoding.seatCount {
        let seat = PlayerID(index: seatIndex)
        let vector = StateEncoding.features(observe(state, as: seat))
        for vertex in state.players[seatIndex].settlements {
            let slot = vertexStart + index.slot(of: vertex) * StateEncoding.perVertexFeatureCount
            #expect(vector[slot] == 1,
                    "seat \(seatIndex): own settlement at v\(index.slot(of: vertex)) is not in the own sub-slot")
        }
    }
}

// MARK: - Determinism

@Test func encodingIsStableAcrossSetInsertionOrder() {
    // The real risk is `Set` iteration order, which Swift seeds ONCE PER
    // PROCESS - so encoding the same value twice in one test proves nothing at
    // all (see the determinism section of CLAUDE.md; this exact mistake was
    // made here before and read as convincing evidence).
    //
    // What can be proved in-process is the property underneath it: a board and
    // a hand whose `Set`s were built by different insertion orders, and whose
    // internal bucket layouts therefore differ, must encode identically. If any
    // walk in the encoder read a `Set` directly instead of a sorted array, the
    // two would disagree here.
    let state = position(boardSeed: 42, driverSeed: 11, moves: 150)
    var shuffled = state

    shuffled.board = Board(
        tiles: state.board.tiles,
        ports: state.board.ports,
        onBoardVertices: Set(state.board.onBoardVertices.sorted().reversed()),
        onBoardEdges: Set(state.board.onBoardEdges.sorted().reversed()),
        robberTile: state.board.robberTile
    )
    for index in shuffled.players.indices {
        let player = shuffled.players[index]
        shuffled.players[index].settlements = Set(player.settlements.sorted().reversed())
        shuffled.players[index].cities = Set(player.cities.sorted().reversed())
        shuffled.players[index].roads = Set(player.roads.sorted().reversed())
    }

    for index in 0..<StateEncoding.seatCount {
        let seat = PlayerID(index: index)
        #expect(StateEncoding.features(observe(state, as: seat))
            == StateEncoding.features(observe(shuffled, as: seat)),
            "seat \(index): vector depends on Set insertion order")
        #expect(StateEncoding.promptDescription(observe(state, as: seat))
            == StateEncoding.promptDescription(observe(shuffled, as: seat)),
            "seat \(index): prompt depends on Set insertion order")
    }
}

@Test func encodingTheSamePositionTwiceAgrees() {
    // Weaker than the test above - it shares one process's hash seed - but it
    // catches an encoder that reads a mutable cache or mints a fresh id.
    for state in sampledPositions() {
        let observation = observe(state, as: PlayerID(index: 0))
        #expect(StateEncoding.features(observation) == StateEncoding.features(observation))
        #expect(StateEncoding.promptDescription(observation) == StateEncoding.promptDescription(observation))
    }
}

@Test func boardIndicesAreTheSortedOrderAndRoundTrip() {
    let board = BoardGenerator.randomized(seed: 42)
    let index = StateEncoding.BoardIndex(board)

    #expect(index.vertices == board.onBoardVertices.sorted())
    #expect(index.edges == board.onBoardEdges.sorted())
    #expect(index.tiles.map(\.coordinate) == board.tiles.map(\.coordinate).sorted())

    for (slot, vertex) in index.vertices.enumerated() { #expect(index.slot(of: vertex) == slot) }
    for (slot, edge) in index.edges.enumerated() { #expect(index.slot(of: edge) == slot) }
    for (slot, tile) in index.tiles.enumerated() { #expect(index.slot(of: tile.coordinate) == slot) }
}

// MARK: - Text rendering

@Test func promptDescriptionNamesTheSeatPhaseAndMoveCount() {
    for state in sampledPositions() {
        let seat = PlayerID(index: 2)
        let observation = observe(state, as: seat)
        let text = StateEncoding.promptDescription(observation)

        #expect(text.contains("seat=P2"), "prompt does not name the observing seat")
        #expect(text.contains("phase=\(StateEncoding.phaseLabel(state.phase))"), "prompt does not name the phase")
        #expect(text.contains("MOVES \(observation.legalMoves.count) "), "prompt does not state the legal-move count")
        #expect(text.contains("v\(StateEncoding.layoutVersion)"), "prompt does not carry the layout version")
    }
}

@Test func promptDescriptionNumbersEveryLegalMove() {
    let state = position(boardSeed: 42, driverSeed: 11, moves: 150)
    let observation = observe(state, as: PlayerID(index: 0))
    #expect(!observation.legalMoves.isEmpty)
    let text = StateEncoding.promptDescription(observation)

    // Numbering is 0-based and positional, so `n` is `legalMoves[n]` with no
    // lookup table - the property a consumer relies on when it replies.
    let index = StateEncoding.BoardIndex(state.board)
    for (offset, move) in observation.legalMoves.enumerated() {
        #expect(text.contains("\(offset) \(StateEncoding.label(for: move, index: index))"),
                "move \(offset) is missing from the numbered list")
    }
}

@Test func promptDescriptionShowsEveryPlayerAndTheWholeBoard() {
    // The two renderings describe the same observation; a field present in one
    // and absent from the other is the drift this pairing exists to prevent.
    let state = position(boardSeed: 42, driverSeed: 11, moves: 150)
    let text = StateEncoding.promptDescription(observe(state, as: PlayerID(index: 0)))

    for index in 0..<StateEncoding.seatCount { #expect(text.contains("P\(index) ")) }
    for slot in 0..<StateEncoding.tileCount { #expect(text.contains("h\(slot)=")) }
    #expect(text.contains("BANK "))
    #expect(text.contains("PORT "))
    #expect(text.contains("you"))
}

@Test func concealingHandsRemovesOnlyOpponentCardKinds() {
    let state = position(boardSeed: 42, driverSeed: 11, moves: 150)
    let observation = observe(state, as: PlayerID(index: 0))
    let text = StateEncoding.promptDescription(observation, policy: .publicCountsOnly)

    #expect(text.contains("hand=?") == false, "the observer's own hand must stay visible")
    #expect(text.contains("[?]"), "opponents' card kinds should render as ?")

    // The public counts survive concealment, which is what makes the policy a
    // masking of hidden information rather than a deletion of state.
    for index in 1..<StateEncoding.seatCount {
        let opponent = state.players[index]
        let handSize = Resource.allCases.reduce(0) { $0 + (opponent.resources[$1] ?? 0) }
        #expect(text.contains("hand=\(handSize)[?]"), "P\(index)'s public hand size was lost")
    }
}

@Test func concealingHandsZeroesOnlyTheHiddenSlots() {
    let state = position(boardSeed: 42, driverSeed: 11, moves: 150)
    let observation = observe(state, as: PlayerID(index: 0))
    let revealed = StateEncoding.features(observation, policy: .revealAll)
    let concealed = StateEncoding.features(observation, policy: .publicCountsOnly)

    let start = StateEncoding.globalFeatureCount
    let width = StateEncoding.perPlayerFeatureCount
    // Slots 0-4 are the hand by kind and 6-10 the dev cards by type; slot 5 and
    // slot 11 are the public counts that must survive.
    let hiddenOffsets = Set(Array(0...4) + Array(6...10))

    for slot in 0..<StateEncoding.seatCount {
        for offset in 0..<width {
            let position = start + slot * width + offset
            if slot > 0 && hiddenOffsets.contains(offset) {
                #expect(concealed[position] == 0, "slot \(slot) offset \(offset) leaks a concealed hand")
            } else {
                #expect(concealed[position] == revealed[position],
                        "slot \(slot) offset \(offset) changed but is not hidden information")
            }
        }
    }
}

/// Not an assertion so much as a measurement kept honest by being run: the
/// point of the text rendering is that it costs a fraction of a state dump, and
/// a claim like that rots the moment a field is added without anyone looking.
///
/// The baseline is a `JSONEncoder` dump of the same `GameState`, which is what
/// a naive implementation would put in a context window.
@Test func promptDescriptionIsFarCheaperThanAJSONDump() throws {
    let state = position(boardSeed: 42, driverSeed: 11, moves: 150)
    let observation = observe(state, as: PlayerID(index: 0))

    let text = StateEncoding.promptDescription(observation)
    let json = try JSONEncoder().encode(state)

    // ~4 characters per token is the usual rule of thumb for English-ish text
    // with numbers; precise enough for a budget, not for billing.
    let charactersPerToken = 4
    print("promptDescription: \(text.count) chars (~\(text.count / charactersPerToken) tokens), "
        + "\(observation.legalMoves.count) legal moves")
    print("GameState JSON:    \(json.count) chars (~\(json.count / charactersPerToken) tokens)")

    #expect(json.count > 20_000, "the JSON baseline moved; the comparison below needs rechecking")
    #expect(text.count * 4 < json.count, "the text rendering has lost its cost advantage over a JSON dump")
}
