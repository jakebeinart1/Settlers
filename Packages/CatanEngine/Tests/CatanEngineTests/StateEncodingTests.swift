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
    #expect(StateEncoding.featureCount == 5182, "featureCount changed - did layoutVersion?")
    #expect(StateEncoding.layoutVersion == 3, "layout changed without the required version bump")
}

@Test func globalBlockDistinguishesVictoryPointTargets() {
    let targetOffset = StateEncoding.phaseCount
        + StateEncoding.diceFeatureCount
        + StateEncoding.resourceKindCount
        + 2 // Development deck and pending offers precede the target.
    var encodedTargets: [Float] = []

    for seatCount in GameSetup.supportedPlayerCounts {
        encodedTargets.removeAll(keepingCapacity: true)
        for target in [8, 10, 12] {
            let state = GameSetup.newGame(
                board: BoardGenerator.standard(),
                seed: 17,
                playerCount: seatCount,
                victoryPointTarget: target
            )
            let vector = StateEncoding.features(observe(state, as: PlayerID(index: 0)))
            #expect(vector.count == StateEncoding.featureCount)
            encodedTargets.append(vector[targetOffset])
        }

        #expect(encodedTargets == [Float(8) / 12, Float(10) / 12, 1],
                "\(seatCount)-seat target slots do not carry the match contract")
    }
}

@Test func numericVectorDistinguishesTheObserversAbsoluteChair() {
    var first = GameSetup.newGame(board: BoardGenerator.standard(), seed: 18)
    var second = first
    first.phase = .mainTurn(playerIndex: 0)
    second.phase = .mainTurn(playerIndex: 1)

    let fromSeatZero = StateEncoding.features(observe(first, as: PlayerID(index: 0)))
    let fromSeatOne = StateEncoding.features(observe(second, as: PlayerID(index: 1)))

    #expect(fromSeatZero != fromSeatOne,
            "absolute-victim action indices require the vector to identify the observer's chair")
}

@Test func numericVectorDistinguishesPendingOfferTerms() {
    var brickForOre = GameSetup.newGame(board: BoardGenerator.standard(), seed: 19)
    var woolForGrain = brickForOre
    brickForOre.pendingTradeOffers = [
        TradeOffer(from: PlayerID(index: 1), give: [.brick: 1], want: [.ore: 1]),
    ]
    woolForGrain.pendingTradeOffers = [
        TradeOffer(from: PlayerID(index: 1), give: [.wool: 1], want: [.grain: 1]),
    ]

    let first = StateEncoding.features(observe(brickForOre, as: PlayerID(index: 0)))
    let second = StateEncoding.features(observe(woolForGrain, as: PlayerID(index: 0)))

    #expect(first != second,
            "a response policy must see the give/want terms behind each indexed offer")
}

@Test func numericVectorDistinguishesShorelinePortTopology() throws {
    let base = BoardGenerator.standard()
    let vertices = base.onBoardVertices.sorted()
    let firstVertex = try #require(vertices.first)
    let secondVertex = try #require(vertices.dropFirst().first)
    let genericBoard = replacingPorts(
        in: base,
        with: [CatanEngine.Port(vertexA: firstVertex, vertexB: secondVertex, kind: .generic)]
    )
    let oreBoard = replacingPorts(
        in: base,
        with: [CatanEngine.Port(vertexA: firstVertex, vertexB: secondVertex, kind: .resource(.ore))]
    )
    let generic = GameSetup.newGame(board: genericBoard, seed: 20)
    let ore = GameSetup.newGame(board: oreBoard, seed: 20)

    #expect(StateEncoding.features(observe(generic, as: PlayerID(index: 0)))
            != StateEncoding.features(observe(ore, as: PlayerID(index: 0))),
            "a settlement policy must see which future trade rate a shoreline vertex grants")
}

private func replacingPorts(in board: Board, with ports: [CatanEngine.Port]) -> Board {
    Board(
        tiles: board.tiles,
        ports: ports,
        onBoardVertices: board.onBoardVertices,
        onBoardEdges: board.onBoardEdges,
        robberTile: board.robberTile
    )
}

@Test func publicVictoryPointProgressIsRelativeToTheMatchTarget() {
    var shortGame = handBuiltPosition()
    shortGame.victoryPointTarget = 8
    var epicGame = shortGame
    epicGame.victoryPointTarget = 12

    let publicVPOffset = StateEncoding.globalFeatureCount + StateEncoding.holdingsFeatureCount + 1
    let shortProgress = StateEncoding.features(observe(shortGame, as: PlayerID(index: 0)))[publicVPOffset]
    let epicProgress = StateEncoding.features(observe(epicGame, as: PlayerID(index: 0)))[publicVPOffset]
    let publicVP = Float(shortGame.publicVictoryPoints(for: PlayerID(index: 0)))

    #expect(shortProgress == publicVP / 8)
    #expect(epicProgress == publicVP / 12)
    #expect(shortProgress > epicProgress)
}

@Test func promptDescriptionNamesTheVictoryPointTarget() {
    for target in [8, 10, 12] {
        let state = GameSetup.newGame(
            board: BoardGenerator.standard(),
            seed: 23,
            victoryPointTarget: target
        )
        let prompt = StateEncoding.promptDescription(observe(state, as: PlayerID(index: 0)))
        #expect(prompt.contains("target=\(target)"))
    }
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
    // Public VP is the second standing slot, right after trades-this-turn.
    let publicVPOffset = StateEncoding.holdingsFeatureCount + 1

    for index in 0..<StateEncoding.seatCount {
        let seat = PlayerID(index: index)
        let vector = StateEncoding.features(observe(state, as: seat))
        for slot in 0..<StateEncoding.seatCount {
            let described = StateEncoding.seatOrder(from: seat)[slot]
            let expected = Float(state.publicVictoryPoints(for: described)) / Float(state.victoryPointTarget)
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

@Test func simultaneousOffersGetDistinctHandles() {
    // Regression guard. The first spelling of the handle printed six hex
    // characters of the offer's UUID, which looked fine on a position with one
    // offer and collapsed on a real one: `TradeOffer.enumerated` walks an
    // FNV-1a hash and keeps one byte per descriptor character, so offers from
    // the same proposer share nearly the whole leading window, and eight of
    // twenty-three offers rendered as the identical handle `0c62bf`. An
    // ambiguous handle means `accept <handle>` names two different trades.
    var state = position(boardSeed: 42, driverSeed: 11, moves: 150)
    let proposer = PlayerID(index: 1)
    state.pendingTradeOffers = Resource.allCases.flatMap { give in
        Resource.allCases.filter { $0 != give }.map { want in
            TradeOffer.enumerated(from: proposer, give: [give: 1], want: [want: 1])
        }
    }
    #expect(state.pendingTradeOffers.count == 20)

    let index = StateEncoding.BoardIndex(state.board)
    let handles = state.pendingTradeOffers.map {
        StateEncoding.label(for: .respondToTrade(offerID: $0.id, accept: true),
                            index: index,
                            pendingOffers: state.pendingTradeOffers)
    }
    #expect(Set(handles).count == handles.count, "two simultaneous offers share a handle")

    // And each handle has to appear in the OFFERS block, or the reader has a
    // name for something it was never shown.
    let text = StateEncoding.promptDescription(observe(state, as: PlayerID(index: 0)))
    for slot in state.pendingTradeOffers.indices {
        #expect(text.contains("#\(slot) from=P\(proposer.index)"), "offer #\(slot) is missing from OFFERS")
    }
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
    // The hand by kind, then the dev cards by type. The public hand size and
    // dev card count sit between and after them and must survive.
    let kinds = StateEncoding.resourceKindCount
    let handOffsets: [Int] = Array(0..<kinds)
    let devOffsets: [Int] = Array((kinds + 1)..<(kinds + 1 + StateEncoding.devCardKindCount))
    let hiddenOffsets = Set(handOffsets + devOffsets)

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
    // Compared position by position - the same `GameState` rendered both ways -
    // because the two grow for different reasons. The JSON grows with pieces on
    // the board; the text grows with the length of the legal-move list, which
    // peaks in a `.mainTurn` with a fat hand where enumerated trade proposals
    // alone run past a hundred moves. Pitting one's worst case against the
    // other's best would compare two different positions and prove nothing.
    var worstRatio = Double.greatestFiniteMagnitude
    var worstDetail = ""

    for state in sampledPositions() + [richMainTurnPosition()] {
        let json = try JSONEncoder().encode(state).count
        for index in 0..<StateEncoding.seatCount {
            let observation = observe(state, as: PlayerID(index: index))
            let text = StateEncoding.promptDescription(observation).count
            let ratio = Double(json) / Double(text)
            guard ratio < worstRatio else { continue }
            worstRatio = ratio
            worstDetail = "\(text) chars (~\(text / charactersPerToken) tokens) for "
                + "\(observation.legalMoves.count) moves, vs \(json) chars of JSON "
                + "(~\(json / charactersPerToken) tokens)"
        }
    }

    print("worst prompt/JSON ratio: \(String(format: "%.1f", worstRatio))x - \(worstDetail)")
    #expect(worstRatio > 4, "the text rendering has lost its 4x advantage over a JSON dump")
}

/// ~4 characters per token is the usual rule of thumb for English-ish text with
/// numbers; precise enough for a context budget, not for billing.
private let charactersPerToken = 4

/// A `.mainTurn` position with hands fat enough that move enumeration produces
/// its worst case - the size a per-turn context budget actually has to cover.
/// Uniformly-random play almost never accumulates a hand this large, so the
/// sampled positions alone would flatter the measurement.
private func richMainTurnPosition() -> GameState {
    var state = position(boardSeed: 42, driverSeed: 11, moves: 150)
    if case .mainTurn = state.phase {} else { state.phase = .mainTurn(playerIndex: 0) }
    for index in state.players.indices {
        for resource in Resource.allCases { state.players[index].resources[resource] = 4 }
    }
    return state
}

// MARK: - Cross-process stability

/// Pins the encoding of one hand-built position, the way
/// `SeededGameFingerprintTests` pins a move sequence.
///
/// ## Why a pinned constant rather than a second encode
/// Swift seeds `Set` and `Dictionary` iteration order **once per process**, so
/// encoding the same value twice inside one test agrees with itself no matter
/// how much hash order leaks into the result - that mistake was made in this
/// repo before, on the RNG, and read as convincing evidence. A constant checked
/// in from an earlier process is the only in-suite check that spans processes:
/// every test run gets a fresh hash seed, so a `Set` walk reaching the vector
/// fails this test rather than merely flaking.
///
/// The position is built by hand from `BoardGenerator.standard()` and the
/// prompt is taken with an empty move list on purpose. Both keep the fingerprint
/// a function of `StateEncoding` and the board alone - a fixture played out
/// through `RulesEngine` would repin every time move enumeration changed, and a
/// guard that gets repinned routinely guards nothing.
///
/// **If this fails after a deliberate layout change, bump `layoutVersion` and
/// repin.** If it fails after a change that was not meant to touch the layout,
/// something is reading a `Set`.
@Test func aFixedPositionEncodesToAPinnedFingerprint() {
    let state = handBuiltPosition()

    var digest: UInt64 = 0xCBF2_9CE4_8422_2325
    for index in 0..<StateEncoding.seatCount {
        let observation = GameObservation(seat: PlayerID(index: index), state: state, legalMoves: [])
        for value in StateEncoding.features(observation) {
            digest = fnv1a(digest, value.bitPattern)
        }
        for byte in StateEncoding.promptDescription(observation).utf8 {
            digest = fnv1a(digest, UInt32(byte))
        }
    }

    // Layout v3 adds observer identity, exact pending-offer terms, and static
    // shoreline port topology. Re-recorded only after tests proved all three
    // previously indistinguishable positions now differ.
    #expect(digest == 0x486C_49AC_F8E4_F195, "encoding changed; got \(String(digest, radix: 16))")
}

private func fnv1a(_ hash: UInt64, _ value: UInt32) -> UInt64 {
    var result = hash
    for shift in stride(from: 0, to: 32, by: 8) {
        result = (result ^ UInt64(UInt8(truncatingIfNeeded: value >> UInt32(shift)))) &* 0x0000_0100_0000_01B3
    }
    return result
}

/// A position assembled directly rather than played into: fixed board, fixed
/// holdings, every field the layout reads set to something non-default so the
/// fingerprint above would notice a slot going missing.
private func handBuiltPosition() -> GameState {
    let board = BoardGenerator.standard()
    let index = StateEncoding.BoardIndex(board)

    var players: [Player] = []
    for seat in 0..<StateEncoding.seatCount {
        players.append(Player(
            id: PlayerID(index: seat),
            resources: [.brick: seat, .lumber: 2, .ore: 1, .grain: seat + 1, .wool: 3],
            devCards: [.knight, .victoryPoint, .monopoly].prefix(seat % 3 + 1).map { $0 },
            playedKnights: seat,
            settlements: [index.vertices[seat * 5], index.vertices[seat * 5 + 2]],
            cities: [index.vertices[seat * 5 + 30]],
            roads: Set(index.edges[(seat * 4)..<(seat * 4 + 3)])
        ))
    }

    return GameState(
        board: board,
        players: players,
        phase: .mainTurn(playerIndex: 1),
        bank: [.brick: 12, .lumber: 9, .ore: 19, .grain: 4, .wool: 7],
        devCardDeck: Array(repeating: .knight, count: 11),
        lastDiceRoll: 8,
        longestRoadPlayer: PlayerID(index: 2),
        largestArmyPlayer: PlayerID(index: 3),
        pendingTradeOffers: [TradeOffer.enumerated(from: PlayerID(index: 1), give: [.wool: 2], want: [.ore: 1])],
        devCardsBoughtThisTurn: [PlayerID(index: 1): [.knight]],
        devCardPlayedThisTurn: PlayerID(index: 2),
        tradesAcceptedThisTurn: [PlayerID(index: 3): 2],
        rng: RandomSource(seed: 1)
    )
}
